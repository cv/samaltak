Object subclass: #NvFakeGsp
	instanceVariableNames: 'endpoint objects received answers eventsBefore memory memories pageDirectories channels host hostRunning methods launches onLaunch'
	classVariableNames: ''
	package: 'Tests-NV'!

NvFakeGsp comment: 'I am GSP-RM''s side of the message queues for tests (NvGspTransportTest): I make the status queue''s header as GSP does when it boots, and on each ring of the doorbell read every command message (the queue checks its checksum and sequence number), keep it in received, and answer it on the status queue as GSP-RM would: GSP_RM_ALLOC records the object (an unknown parent: status NV_ERR_INVALID_OBJECT_PARENT), GSP_RM_CONTROL runs the block in answers for its command on the parameters (a ByteArray) if there is one, FREE forgets the object and its children (unknown: NV_ERR_INVALID_OBJECT_HANDLE), GSP_SET_SYSTEM_INFO and SET_REGISTRY get no reply (they are sent before the boot, without waiting), anything else gets rpc_result NV_ERR_NOT_SUPPORTED; sendEvent:result: sends an event. eventsBefore: n sends n UCODE_LIBOS_PRINT events before each reply.

For the client side of RM (steps 4-6, docs/nv-gsp.md 14), given memory: (the NvFakeDmaMemory the transport allocates from): ALLOC_MEMORY records a memory object (class NV01_MEMORY_LIST_SYSTEM, one PTE per contiguous buffer, its pages in memory); GET_CLASSLIST_V2 and GR_GET_INFO_V2 answer the GB10''s classes and GR numbers as Linux reports them (docs/nv-rm.md); NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY records a VA space''s root; a GPFIFO channel''s allocation must carry its instance block, USERD and error notifier descriptors (NV_ERR_INVALID_ARGUMENT otherwise); GET_WORK_SUBMIT_TOKEN answers a token. startHost: runs a fake GPU host on the usermode window: when a token is written to the doorbell (16r90) it reads the channel''s GPPut from USERD, its GPFIFO entries and pushbuffers through the page tables in memory (my own walk of the GMMU v3 format), runs host semaphore releases, records the methods and compute launches (SEND_PCAS_A), runs onLaunch: on each launch''s QMD, and writes GPGet. Nothing of this is GSP-RM''s or the GPU''s real behaviour beyond what the 580 headers say.'!

!NvFakeGsp class methodsFor: 'instance creation'!
on: anNvGspQueues
	^self new setEndpoint: anNvGspQueues gspEndpoint
! !

!NvFakeGsp methodsFor: 'initialization'!
setEndpoint: anNvGspEndpoint
	endpoint := anNvGspEndpoint.
	endpoint initializeTransmit: NvGspQueues statusQueueSize.
	objects := Dictionary new.
	received := OrderedCollection new.
	answers := Dictionary new.
	eventsBefore := 0.
	memories := Dictionary new.
	pageDirectories := OrderedCollection new.
	channels := Dictionary new.
	methods := OrderedCollection new.
	launches := OrderedCollection new
! !

!NvFakeGsp methodsFor: 'accessing'!
objects
	"handle -> {class. parent}"
	^objects
!
received
	"The RPCs received, as NvStructs."
	^received
!
answers
	"control command -> a block on the parameters' ByteArray"
	^answers
!
eventsBefore: n
	eventsBefore := n
!
endpoint
	^endpoint
! !

!NvFakeGsp methodsFor: 'client RM'!
memory: anNvFakeDmaMemory
	memory := anNvFakeDmaMemory
!
memories
	"handle -> {device address. length} of each ALLOC_MEMORY"
	^memories
!
pageDirectories
	"{root. entries. flags. hVASpace} of each SET_PAGE_DIRECTORY"
	^pageDirectories
!
channels
	"handle -> {NV_CHANNEL_ALLOC_PARAMS (an NvGspStruct). GPGet. token}"
	^channels
!
methods
	"{channel. subchannel. method. value} the host ran, in order"
	^methods
!
launches
	"The QMD VAs of the compute launches (SEND_PCAS_A), in order."
	^launches
!
onLaunch: aBlock
	"aBlock value: a launch's QMD VA value: me (a fake kernel)."
	onLaunch := aBlock
!
gb10Classes
	"The class list of the GB10's device under Linux (docs/nv-rm.md, Objects and classes)."
	^#(16r41 16r80 16r2080 16r90F1 16r70 16r3E 16r71 16rA06C 16r9067 16rC96F 16rCA6F 16rCEC0 16rC661 16rC761 16rCAB5 16rC9B5 16rCD40 16rCE97)
!
gb10GrInfo
	"GR info index -> data on the GB10 (docs/nv-rm.md): SM version 16rA04, 4 GPCs, 6 TPCs each, 2 SMs each, 48 warps."
	^Dictionary new at: NvRm grInfoSmVersion put: 16rA04; at: NvRm grInfoNumGpcs put: 4; at: NvRm grInfoNumTpcPerGpc put: 6;
		at: NvRm grInfoNumSmPerTpc put: 2; at: NvRm grInfoMaxWarpsPerSm put: 48; yourself
!
allocMemory: anRpc
	"ALLOC_MEMORY: rpc_alloc_memory_v13_01 at 32; its PTEs (page numbers) after the 56-byte structure."
	| p count length |
	p := 32.
	(anRpc u32At: p + 12) = (NvGsp constant: 'NV01_MEMORY_LIST_SYSTEM') ifFalse: [^16r1F].
	count := anRpc u32At: p + 40.
	((anRpc u32At: p + 48) bitShift: -16) = count ifFalse: [^16r1F].
	(anRpc u32At: 8) = (32 + 56 + (8 * count)) ifFalse: [^16r1F].
	count = 1 ifFalse: [^16r56].
	length := anRpc u64At: p + 32.
	memory notNil ifTrue: [memory cpuAddressOf: (anRpc u64At: p + 56) * 4096; cpuAddressOf: (anRpc u64At: p + 56) * 4096 + length - 1].
	memories at: (anRpc u32At: p + 8) put: {(anRpc u64At: p + 56) * 4096. length}.
	objects at: (anRpc u32At: p + 8) put: {anRpc u32At: p + 12. anRpc u32At: p + 4}.
	^0
!
clientControl: command params: params
	"The controls I answer without a block in answers; false if I know none."
	command = (NvGsp constant: 'NV0080_CTRL_CMD_GPU_GET_CLASSLIST_V2') ifTrue: [
		params uint32At: 1 put: self gb10Classes size.
		self gb10Classes doWithIndex: [:c :i | params uint32At: 1 + (4 * i) put: c].
		^true].
	command = (NvGsp constant: 'NV2080_CTRL_CMD_GR_GET_INFO_V2') ifTrue: [
		1 to: (params uint32At: 1) do: [:i |
			params uint32At: 1 + 4 + (8 * (i - 1)) + 4 put: (self gb10GrInfo at: (params uint32At: 1 + 4 + (8 * (i - 1))) ifAbsent: [0])].
		^true].
	command = (NvGsp constant: 'NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY') ifTrue: [
		pageDirectories add: {(params uint32At: 1) + ((params uint32At: 5) bitShift: 32). params uint32At: 9. params uint32At: 13. params uint32At: 17}.
		^true].
	command = NvRm cmdGpfifoGetWorkSubmitToken ifTrue: [^true].
	^false
!
checkChannel: anRpc
	"A GPFIFO channel's allocation must carry the client RM's descriptors: answer 0 or a status."
	| p |
	p := NvGspStruct layout: (NvGsp layout: 'NV_CHANNEL_ALLOC_PARAMS').
	p bytesAt: 0 put: (anRpc bytes copyFrom: 65 to: 64 + p size).
	#('instanceMem' 'userdMem' 'ramfcMem' 'errorNotifierMem') do: [:d |
		((p at: d, '.base') = 0 or: [(p at: d, '.addressSpace') ~= 1]) ifTrue: [^16r1F]].
	((p at: 'instanceMem.base') \\ 4096 ~= 0 or: [(p at: 'instanceMem.size') ~= (NvGsp constant: 'NV_RAMIN_ALLOC_SIZE')]) ifTrue: [^16r1F].
	(p at: 'userdMem.size') = (NvGsp constant: 'NV_RAMUSERD_CHAN_SIZE') ifFalse: [^16r1F].
	memory notNil ifTrue: [#('instanceMem' 'userdMem' 'errorNotifierMem') do: [:d | memory cpuAddressOf: (p at: d, '.base')]].
	channels at: (anRpc u32At: 32 + 8) put: (Array with: p with: 0 with: 16r40000000 + channels size + 1).
	^0
! !

!NvFakeGsp methodsFor: 'fake host'!
translate: va
	"The device address of va through the latest VA space's page tables (GMMU v3: PD4 to PD1, dual PD0, PT), or an error."
	| table entry high |
	pageDirectories isEmpty ifTrue: [^self error: 'fake GPU: no page directory'].
	table := pageDirectories last first.
	#(56 47 38 29) with: #(1 9 9 9) do: [:low :bits |
		entry := memory u64At: table + (8 * ((va bitShift: low negated) bitAnd: (1 bitShift: bits) - 1)).
		((NvGsp field: 'NV_MMU_VER3_PDE_IS_PTE' of: entry) = 0 and: [(NvGsp field: 'NV_MMU_VER3_PDE_APERTURE' of: entry) = 2])
			ifFalse: [^self error: 'fake GPU: MMU fault at VA 16r', (va printString: 16), ' (PDE ', (entry printString: 16), ')'].
		table := (NvGsp field: 'NV_MMU_VER3_PDE_ADDRESS' of: entry) * 4096].
	high := memory u64At: table + (16 * ((va bitShift: -21) bitAnd: 255)) + 8.
	(NvGsp field: 'NV_MMU_VER3_DUAL_PDE_APERTURE_SMALL' of: (high bitShift: 64)) = 2 ifFalse: [^self error: 'fake GPU: MMU fault at VA 16r', (va printString: 16), ' (PD0)'].
	table := (NvGsp field: 'NV_MMU_VER3_DUAL_PDE_ADDRESS_SMALL' of: (high bitShift: 64)) * 4096.
	entry := memory u64At: table + (8 * ((va bitShift: -12) bitAnd: 511)).
	(NvGsp field: 'NV_MMU_VER3_PTE_VALID' of: entry) = 1 ifFalse: [^self error: 'fake GPU: MMU fault at VA 16r', (va printString: 16), ' (PTE)'].
	^((NvGsp field: 'NV_MMU_VER3_PTE_ADDRESS' of: entry) * 4096) + (va bitAnd: 16rFFF)
!
u32AtVa: va
	^memory u32At: (self translate: va)
!
u64AtVa: va
	^memory u64At: (self translate: va)
!
write64: value atVa: va
	Machine uint64At: (memory cpuAddressOf: (self translate: va)) put: value
!
write32: value atVa: va
	Machine uint32At: (memory cpuAddressOf: (self translate: va)) put: value
!
startHost: aUsermodeAddress
	"Run the fake host on the usermode window at aUsermodeAddress until stopHost."
	hostRunning := true.
	host := [[hostRunning] whileTrue: [
		self serveDoorbell: aUsermodeAddress.
		(Delay forMilliseconds: 1) wait]] forkAt: Processor userInterruptPriority
!
stopHost
	hostRunning := false.
	host notNil ifTrue: [host terminate. host := nil]
!
serveDoorbell: aUsermodeAddress
	| token channel |
	token := Machine uint32At: aUsermodeAddress + (NvGsp constant: 'NVC361_NOTIFY_CHANNEL_PENDING').
	token = 0 ifTrue: [^self].
	Machine uint32At: aUsermodeAddress + (NvGsp constant: 'NVC361_NOTIFY_CHANNEL_PENDING') put: 0.
	channel := channels keys detect: [:h | ((channels at: h) at: 3) = token] ifNone: [^self].
	self run: channel
!
run: hChannel
	"Run hChannel's GPFIFO entries from GPGet to GPPut (USERD 16r88, 16r8C)."
	| c p userd put get entries |
	c := channels at: hChannel.
	p := c first.
	userd := memory cpuAddressOf: (p at: 'userdMem.base').
	entries := p at: 'gpFifoEntries'.
	put := Machine uint32At: userd + 16r8C.
	get := c at: 2.
	[get ~= put] whileTrue: [| entry |
		entry := self u64AtVa: (p at: 'gpFifoOffset') + (8 * get).
		self run: hChannel pushBuffer: (entry bitAnd: 16rFFFFFFFFFC) words: ((entry bitShift: -42) bitAnd: 16r1FFFFF).
		get := get + 1 \\ entries].
	c at: 2 put: get.
	Machine uint32At: userd + 16r88 put: get
!
run: hChannel pushBuffer: va words: n
	"Methods: SEC_OP 31:29 (1 incrementing, 3 non-incrementing, 4 immediate, 5 increment once), COUNT 28:16, SUBCHANNEL 15:13, ADDRESS 11:0 (dwords)."
	| i sem |
	sem := Dictionary new.
	i := 0.
	[i < n] whileTrue: [| header op count sub method |
		header := self u32AtVa: va + (4 * i).
		i := i + 1.
		op := header bitShift: -29. count := (header bitShift: -16) bitAnd: 16r1FFF. sub := (header bitShift: -13) bitAnd: 7. method := (header bitAnd: 16rFFF) * 4.
		op = 4
			ifTrue: [self method: method value: count subchannel: sub channel: hChannel semaphore: sem]
			ifFalse: [0 to: count - 1 do: [:k | | m |
				m := op = 1 ifTrue: [method + (4 * k)] ifFalse: [(op = 5 and: [k > 0]) ifTrue: [method + 4] ifFalse: [method]].
				self method: m value: (self u32AtVa: va + (4 * i)) subchannel: sub channel: hChannel semaphore: sem.
				i := i + 1]]]
!
method: m value: v subchannel: sub channel: hChannel semaphore: sem
	methods add: {hChannel. sub. m. v}.
	sub = 0 ifTrue: [
		sem at: m put: v.
		(m = 16r6C and: [(v bitAnd: 7) = 1]) ifTrue: [| address payload |
			address := (sem at: 16r5C ifAbsent: [0]) + ((sem at: 16r60 ifAbsent: [0]) bitShift: 32).
			payload := (sem at: 16r64 ifAbsent: [0]) + ((sem at: 16r68 ifAbsent: [0]) bitShift: 32).
			(v bitAt: 25) = 1 ifTrue: [self write64: payload atVa: address] ifFalse: [self write32: (payload bitAnd: 16rFFFFFFFF) atVa: address]]].
	(sub = 1 and: [m = 16r2B4]) ifTrue: [
		launches add: v * 256.
		onLaunch notNil ifTrue: [onLaunch value: v * 256 value: self]]
! !

!NvFakeGsp methodsFor: 'serving'!
ring
	"The doorbell: answer every message waiting."
	| m |
	[(m := endpoint receive) notNil] whileTrue: [
		received add: m.
		self answer: m]
!
answer: anRpc
	| function reply |
	eventsBefore timesRepeat: [endpoint send: (NvGsp rpcFunction: (NvGsp function: #UCODE_LIBOS_PRINT) length: 0 sequence: 0)].
	function := anRpc u32At: 12.
	"Sent before the boot without waiting for a reply (kgspQueueAsyncInitRpcs): GSP answers none."
	({NvGsp function: #GSP_SET_SYSTEM_INFO. NvGsp function: #SET_REGISTRY} includes: function) ifTrue: [^self].
	reply := NvStruct on: anRpc bytes copy.
	((anRpc u32At: 0) = NvGsp headerVersion and: [(anRpc u32At: 4) = (NvGsp constant: 'NV_VGPU_MSG_SIGNATURE_VALID')])
		ifFalse: [^self reply: reply result: 16r1F].
	function = (NvGsp function: #GSP_RM_ALLOC) ifTrue: [^self reply: reply result: 0 status: (self alloc: reply) at: 32 + 16].
	function = (NvGsp function: #GSP_RM_CONTROL) ifTrue: [^self reply: reply result: 0 status: (self control: reply) at: 32 + 12].
	function = (NvGsp function: #FREE) ifTrue: [^self reply: reply result: 0 status: (self free: reply) at: 32 + 12].
	function = (NvGsp function: #ALLOC_MEMORY) ifTrue: [| status | status := self allocMemory: reply. ^self reply: reply result: status].
	self reply: reply result: 16r56
!
sendEvent: aSymbol result: anInteger
	"An event (GSP_INIT_DONE, ...) on the status queue."
	endpoint send: ((NvGsp rpcFunction: (NvGsp function: aSymbol) length: 0 sequence: 0) at: 'rpc_result' put: anInteger; at: 'rpc_result_private' put: anInteger; yourself)
!
alloc: anRpc
	| parent |
	parent := anRpc u32At: 32 + 4.
	(parent = 0 or: [objects includesKey: parent]) ifFalse: [^16r1E].
	(NvRm gpfifoClasses includes: (anRpc u32At: 32 + 12)) ifTrue: [| status |
		status := self checkChannel: anRpc.
		status = 0 ifFalse: [^status]].
	objects at: (anRpc u32At: 32 + 8) put: {anRpc u32At: 32 + 12. parent}.
	^0
!
control: anRpc
	| n params |
	n := anRpc u32At: 32 + 16.
	params := anRpc bytes copyFrom: 73 to: 72 + n.
	(answers at: (anRpc u32At: 32 + 8) ifAbsent: [nil])
		ifNil: [self clientControl: (anRpc u32At: 32 + 8) params: params]
		ifNotNil: [:block | block value: params].
	(anRpc u32At: 32 + 8) = NvRm cmdGpfifoGetWorkSubmitToken ifTrue: [
		params uint32At: 1 put: ((channels at: (anRpc u32At: 32 + 4) ifAbsent: [#(nil 0 0)]) at: 3)].
	anRpc bytesAt: 72 put: params.
	^0
!
free: anRpc
	| handle |
	handle := anRpc u32At: 32 + 8.
	(objects includesKey: handle) ifFalse: [^16r19].
	self forget: handle.
	^0
!
forget: handle
	(objects keys select: [:h | ((objects at: h) at: 2) = handle]) do: [:child | self forget: child].
	objects removeKey: handle
!
reply: anRpc result: result status: status at: offset
	anRpc u32At: offset put: status.
	self reply: anRpc result: result
!
reply: anRpc result: result
	| length |
	anRpc u32At: 16 put: result; u32At: 20 put: result.
	"Answer as many bytes as the message's entries hold, but no more than fit them (an alloc's parameters lie past its length)."
	length := 48 + (anRpc u32At: 8).
	endpoint send: (NvStruct on: (anRpc bytes copyFrom: 1 to: ((length + 4095 // 4096 * 4096) - 48 min: anRpc size)))
! !
