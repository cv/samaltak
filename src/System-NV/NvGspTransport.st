NvTransport subclass: #NvGspTransport
	instanceVariableNames: 'endpoint doorbell sequence nextClient nextObject gpuId events timeoutMs open memory usermode buffers vaSpaces virtuals channelMemory classes nextVa'
	classVariableNames: ''
	package: 'System-NV'!

NvGspTransport comment: 'I reach GSP-RM over its message queues (docs/nv-gsp.md 3): NvDevice''s alloc, control and free become GSP_RM_ALLOC, GSP_RM_CONTROL and FREE RPCs (NvGsp) carrying the same parameter blocks NvRm builds, sent through an NvGspEndpoint (the CPU side of NvGspQueues); after each I ring the doorbell (a block: on the GB10, writing 0 to NV_PGSP_QUEUE_HEAD(0), BAR0 16r110C00, kgspSetCmdQueueHead_TU102) and poll the status queue for the reply, keeping the events GSP sends meanwhile (events). A reply''s rpc_result or status other than NV_OK signals an NvError.

I pick the handles, as a client RM does: root clients from 16rC1D00001, objects from 16rCAF00001. And I do what nvidia.ko''s CPU-RM does itself (docs/nv-gsp.md 3.3 and 14), once memory: (an NvDmaMemory) and usermode: (the CPU address of BAR0''s usermode window, bar0:) are set:
- step 4: GPU_GET_ID_INFO_V2 is answered here (one GPU, instance 0); the class list and GR info, whose parameters point at other memory, are asked of GSP-RM in their flat V2 forms (GET_CLASSLIST_V2 once, GR_GET_INFO_V2) and answered from them;
- step 5: system memory (NV01_MEMORY_SYSTEM) is a buffer of memory described to GSP-RM with ALLOC_MEMORY (NV01_MEMORY_LIST_SYSTEM, its pages), mapped for the CPU where it is; a VA space (FERMI_VASPACE_A) is allocated on GSP-RM too and gets page tables of mine (NvGmmu) whose root goes to GSP-RM with NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY; mapping for the GPU writes PTEs at VAs I pick from 8 GB up;
- step 6: a GPFIFO channel''s allocation gets the descriptors CPU-RM fills (kernel_channel.c 2750-2830): an instance block (NV_RAMIN_ALLOC_SIZE, its RAMFC at its start), USERD (where hUserdMemory and userdOffset say), the error notifier; the usermode page is BAR0''s window (NV_VIRTUAL_FUNCTION_FULL_PHYS_OFFSET, the doorbell at 16r90).
Which of these GSP-RM accepts as sent, and what else CPU-RM sends, is verified only against NvFakeGsp. Without memory: the client-side calls signal errors that say so. GSP must be running (booted, GSP_INIT_DONE): NvGspBoot.'!

!NvGspTransport class methodsFor: 'instance creation'!
endpoint: anNvGspEndpoint doorbell: aBlock
	^self new setEndpoint: anNvGspEndpoint doorbell: aBlock
! !

!NvGspTransport class methodsFor: 'controls'!
pointerControls
	"Controls NvDevice makes whose parameters hold pointers to other memory: I answer them from their flat V2 forms."
	^{NvRm cmdDeviceGetClassList. NvRm cmdGrGetInfo}
!
vaBase
	"Where my GPU VAs start (8 GB; RM-owned VA spaces on Linux start near 16r120000000)."
	^16r200000000
! !

!NvGspTransport methodsFor: 'initialization'!
setEndpoint: anNvGspEndpoint doorbell: aBlock
	endpoint := anNvGspEndpoint.
	doorbell := aBlock.
	sequence := 0.
	nextClient := 16rC1D00001.
	nextObject := 16rCAF00001.
	gpuId := 0.
	events := OrderedCollection new.
	timeoutMs := 4000.
	buffers := Dictionary new.
	vaSpaces := Dictionary new.
	virtuals := Dictionary new.
	channelMemory := Dictionary new.
	nextVa := self class vaBase
! !

!NvGspTransport methodsFor: 'accessing'!
endpoint
	^endpoint
!
events
	"The events (RPCs GSP sent on its own) received while waiting for replies, oldest first."
	^events
!
gpuId: anInteger
	gpuId := anInteger
!
sequence: anInteger
	"The next RPC's sequence number (after RPCs sent before me: NvGspBoot's)."
	sequence := anInteger
!
timeoutMs: anInteger
	"How long to wait for a reply: RM's default GPU timeout is 4 s (osGetTimeoutParams)."
	timeoutMs := anInteger
!
memory: anNvDmaMemory
	"Where system memory, page tables and channel buffers come from (NvPciDmaMemory on the GPU's PciDevice)."
	memory := anNvDmaMemory
!
usermode: aCpuAddress
	"The CPU address of the usermode (doorbell) window."
	usermode := aCpuAddress
!
bar0: aCpuAddress
	"BAR0 mapped at aCpuAddress (VfioPciDevice bar: 0, or the BAR's address on UEFI): its usermode window (gb100 dev_vm.h 39; GB10B publishes no dev_vm.h)."
	usermode := aCpuAddress + (NvGsp constant: 'NV_VIRTUAL_FUNCTION_FULL_PHYS_OFFSET.low')
!
buffers
	"handle -> NvDmaBuffer of each system memory object"
	^buffers
!
vaSpaces
	"handle -> NvGmmu of each VA space"
	^vaSpaces
!
channelMemory
	"channel handle -> its instance block"
	^channelMemory
! !

!NvGspTransport methodsFor: 'opening'!
open
	open := true
!
isOpen
	^open == true
!
attachGpu: index
	index = 0 ifFalse: [^self error: 'GSP transport: one GPU, not number ', index printString].
	^gpuId
!
close
	open := false
! !

!NvGspTransport methodsFor: 'rpc'!
call: anRpc
	"Send anRpc, ring the doorbell, answer GSP's reply (the message with the same function), keeping the events that come before it."
	| function start reply |
	function := anRpc u32At: 12.
	endpoint send: anRpc.
	sequence := sequence + 1.
	doorbell value.
	start := Time millisecondClockValue.
	[reply := endpoint receive.
	reply notNil and: [(reply u32At: 12) = function]] whileFalse: [
		reply isNil
			ifTrue: [
				Time millisecondClockValue - start > timeoutMs ifTrue: [^self error: 'GSP: no reply to RPC ', function printString, ' in ', timeoutMs printString, ' ms'].
				(Delay forMilliseconds: 1) wait]
			ifFalse: [events add: reply]].
	(reply u32At: 16) = 0 ifFalse: [^NvError signal: 'GSP RPC ', function printString status: (reply u32At: 16)].
	^reply
!
newClient
	^nextClient := nextClient + 1
!
newObject
	^nextObject := nextObject + 1
!
clientSide: what
	"memory, or an error naming what needs it."
	memory isNil ifTrue: [^self error: 'GSP transport: ', what, ' is the client side of RM: set memory: first (docs/nv-gsp.md 14)'].
	^memory
! !

!NvGspTransport methodsFor: 'resource manager'!
alloc: rmClass client: hClient parent: hParent params: anNvStructOrNil
	"GSP_RM_ALLOC: a new root client when hClient is 0 (its NV0000_ALLOC_PARAMETERS made if there are none), else an object of hClient; the parameters come back as GSP left them. System memory, VA spaces and channels get the client RM's part (steps 5, 6)."
	| handle |
	hClient = 0 ifTrue: [
		handle := nextClient.
		self newClient.
		^self rmAlloc: rmClass client: handle parent: hParent object: handle
			params: (anNvStructOrNil ifNil: [NvStruct on: (NvGsp rootParamsClient: handle)])].
	handle := nextObject.
	self newObject.
	rmClass = NvRm classMemorySystem ifTrue: [^self allocSystemMemory: handle client: hClient device: hParent params: anNvStructOrNil].
	(NvRm gpfifoClasses includes: rmClass) ifTrue: [self describeChannel: handle params: anNvStructOrNil].
	self rmAlloc: rmClass client: hClient parent: hParent object: handle params: anNvStructOrNil.
	rmClass = NvRm classVaSpace ifTrue: [self pageTablesFor: handle client: hClient device: hParent].
	rmClass = NvRm classMemoryVirtual ifTrue: [virtuals at: handle put: ((anNvStructOrNil ifNil: [NvStruct new: 24]) u32At: 16)].
	^handle
!
rmAlloc: rmClass client: hClient parent: hParent object: handle params: anNvStructOrNil
	| reply status |
	reply := self call: (NvGsp rmAllocClient: hClient parent: hParent object: handle class: rmClass params: (anNvStructOrNil ifNotNil: [:p | p bytes]) sequence: sequence).
	status := reply u32At: 32 + 16.
	status = 0 ifFalse: [^NvError signal: 'RM alloc of class 16r', (rmClass printString: 16) status: status].
	anNvStructOrNil ifNotNil: [:p | p bytesAt: 0 put: (reply bytes copyFrom: 65 to: 64 + p size)].
	^handle
!
control: command client: hClient object: hObject params: anNvStruct
	"GSP_RM_CONTROL with anNvStruct's bytes; answer anNvStruct with GSP's. The ones CPU-RM answers itself (step 4) are answered here."
	command = NvRm cmdGpuGetIdInfoV2 ifTrue: [^anNvStruct u32At: 8 put: 0; u32At: 12 put: 0; yourself].
	command = NvRm cmdDeviceGetClassList ifTrue: [^self classList: anNvStruct client: hClient device: hObject].
	command = NvRm cmdGrGetInfo ifTrue: [^self grInfo: anNvStruct client: hClient subdevice: hObject].
	^self rmControl: command client: hClient object: hObject params: anNvStruct
!
rmControl: command client: hClient object: hObject params: anNvStruct
	| reply status |
	reply := self call: (NvGsp rmControlClient: hClient object: hObject command: command params: (anNvStruct ifNotNil: [:p | p bytes]) sequence: sequence).
	status := reply u32At: 32 + 12.
	status = 0 ifFalse: [^NvError signal: 'RM control 16r', (command printString: 16) status: status].
	anNvStruct ifNotNil: [:p | p bytesAt: 0 put: (reply bytes copyFrom: 73 to: 72 + p size)].
	^anNvStruct
!
free: hObject client: hClient parent: hParent
	| reply status |
	reply := self call: (NvGsp freeClient: hClient parent: hParent object: hObject sequence: sequence).
	status := reply u32At: 32 + 12.
	status = 0 ifFalse: [^NvError signal: 'RM free' status: status].
	buffers removeKey: hObject ifAbsent: [].
	vaSpaces removeKey: hObject ifAbsent: [].
	virtuals removeKey: hObject ifAbsent: [].
	channelMemory removeKey: hObject ifAbsent: []
! !

!NvGspTransport methodsFor: 'step 4: static information'!
classList: anNvStruct client: hClient device: hDevice
	"NV0080_CTRL_CMD_GPU_GET_CLASSLIST (count, then a pointer to count u32s) from GET_CLASSLIST_V2, asked once. CPU-RM answers it from its own class database (deviceCtrlCmdGpuGetClasslist_IMPL, device_ctrl.c 60-95; not ROUTE_TO_PHYSICAL, g_device_nvoc.c 185)."
	| count list |
	classes isNil ifTrue: [| p |
		p := self rmControl: (NvGsp constant: 'NV0080_CTRL_CMD_GPU_GET_CLASSLIST_V2') client: hClient object: hDevice params: NvGsp classListV2.
		classes := (1 to: (p at: 'numClasses')) collect: [:i | p u32At: 4 * i]].
	count := anNvStruct u32At: 0.
	list := anNvStruct u64At: 8.
	(count = 0 or: [list = 0]) ifTrue: [^anNvStruct u32At: 0 put: classes size; yourself].
	1 to: (count min: classes size) do: [:i | Machine uint32At: list + (4 * (i - 1)) put: (classes at: i)].
	^anNvStruct
!
grInfo: anNvStruct client: hClient subdevice: hSubdevice
	"NV2080_CTRL_CMD_GR_GET_INFO ({index, data} pairs at a pointer) from GR_GET_INFO_V2 (the pairs inline). CPU-RM answers it from GR's static information (kernel_graphics.c, NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_GET_INFO; not ROUTE_TO_PHYSICAL, g_subdevice_nvoc.c 5208)."
	| count list p base |
	count := anNvStruct u32At: 0.
	list := anNvStruct u64At: 8.
	count > (NvGsp constant: 'NV0080_CTRL_GR_INFO_MAX_SIZE') ifTrue: [^self error: 'GR info: at most 58 indexes'].
	p := NvGsp grInfoV2: ((1 to: count) collect: [:i | Machine uint32At: list + (8 * (i - 1))]).
	self rmControl: (NvGsp constant: 'NV2080_CTRL_CMD_GR_GET_INFO_V2') client: hClient object: hSubdevice params: p.
	base := p layout offsetOf: 'grInfoList'.
	1 to: count do: [:i | Machine uint32At: list + (8 * (i - 1)) + 4 put: (p u32At: base + (8 * (i - 1)) + 4)].
	^anNvStruct
! !

!NvGspTransport methodsFor: 'step 5: memory and VA'!
allocSystemMemory: handle client: hClient device: hDevice params: anNvStruct
	"NV01_MEMORY_SYSTEM: a buffer of memory, described to GSP-RM with ALLOC_MEMORY (system_mem.c 470-500, rpc.c 3458-3500); its size at 64 in NV_MEMORY_ALLOCATION_PARAMS."
	| size b |
	size := anNvStruct u64At: 64.
	b := (self clientSide: 'system memory') allocate: size.
	self call: (NvGsp allocMemoryClient: hClient device: hDevice memory: handle address: b deviceAddress length: b size sequence: sequence).
	buffers at: handle put: b.
	anNvStruct u64At: 64 put: b size.
	^handle
!
pageTablesFor: hVaSpace client: hClient device: hDevice
	"Page tables for a new VA space, their root given to GSP-RM (gvaspace; NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY, dma.c 430-520)."
	| g |
	g := NvGmmu on: (self clientSide: 'a VA space').
	vaSpaces at: hVaSpace put: g.
	self rmControl: (NvGsp constant: 'NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY') client: hClient object: hDevice
		params: (NvGsp setPageDirectory: g root deviceAddress entries: g rootEntries vaSpace: hVaSpace)
!
buffer: hMemory
	^buffers at: hMemory ifAbsent: [self error: 'GSP transport: no system memory object 16r', (hMemory printString: 16)]
!
gmmuOf: hDma
	"The page tables of the VA space of the virtual memory object hDma (or of the only VA space)."
	| h |
	h := virtuals at: hDma ifAbsent: [0].
	h = 0 ifTrue: [vaSpaces size = 1 ifTrue: [^vaSpaces anyOne]. ^self error: 'GSP transport: which VA space is 16r', (hDma printString: 16), '''s?'].
	^vaSpaces at: h ifAbsent: [self error: 'GSP transport: no VA space 16r', (h printString: 16)]
! !

!NvGspTransport methodsFor: 'step 6: channels'!
describeChannel: hChannel params: anNvStruct
	"Fill what CPU-RM fills in a GPFIFO channel's NV_CHANNEL_ALLOC_PARAMS on a GSP client (kernel_channel.c 2750-2830): the instance block (its RAMFC at its start), USERD and the error notifier, in coherent system memory (ADDR_SYSMEM 1, g_mem_desc_nvoc.h 115)."
	| p instance userd error |
	p := NvGspStruct layout: (NvGsp layout: 'NV_CHANNEL_ALLOC_PARAMS').
	p bytesAt: 0 put: anNvStruct bytes.
	instance := (self clientSide: 'a channel') allocate: (NvGsp constant: 'NV_RAMIN_ALLOC_SIZE').
	channelMemory at: hChannel put: instance.
	userd := (self buffer: (p u32At: (p layout offsetOf: 'hUserdMemory'))) deviceAddress + (p u64At: (p layout offsetOf: 'userdOffset')).
	error := self buffer: (p at: 'hObjectError').
	self describe: 'instanceMem' in: p base: instance deviceAddress size: instance size.
	self describe: 'ramfcMem' in: p base: instance deviceAddress size: (NvGsp constant: 'NV_RAMUSERD_CHAN_SIZE').
	self describe: 'userdMem' in: p base: userd size: (NvGsp constant: 'NV_RAMUSERD_CHAN_SIZE').
	self describe: 'errorNotifierMem' in: p base: error deviceAddress size: error size.
	anNvStruct bytesAt: 0 put: p bytes
!
describe: aName in: p base: address size: n
	p at: aName, '.base' put: address; at: aName, '.size' put: n; at: aName, '.addressSpace' put: 1; at: aName, '.cacheAttrib' put: 0
! !

!NvGspTransport methodsFor: 'mapping'!
mapMemory: hMemory client: hClient device: hDevice size: size
	"System memory is the CPU's where it is."
	| b |
	b := self buffer: hMemory.
	size > b size ifTrue: [^self error: 'GSP transport: ', size printString, ' bytes of a ', b size printString, '-byte buffer'].
	^b cpuAddress
!
mapUsermode: hUsermode client: hClient device: hDevice size: size
	usermode isNil ifTrue: [^self error: 'GSP transport: the usermode page is BAR0''s window: set bar0: or usermode: first'].
	^usermode
!
unmapCpu: address size: size
	"Nothing: memory and BAR0 stay mapped as they were."
!
mapToGpu: hMemory client: hClient device: hDevice dma: hDma size: size flags: flags
	"A VA of mine for the buffer's pages, PTEs written."
	| b va |
	b := self buffer: hMemory.
	va := nextVa.
	nextVa := nextVa + (b size + 16rFFFF // 16r10000 * 16r10000).
	(self gmmuOf: hDma) map: b deviceAddress at: va size: (size min: b size).
	^va
!
unmapFromGpu: hMemory client: hClient device: hDevice dma: hDma gpuAddress: gpuAddress
	(self gmmuOf: hDma) unmap: gpuAddress size: (self buffer: hMemory) size
! !
