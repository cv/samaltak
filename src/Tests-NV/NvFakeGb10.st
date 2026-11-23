Object subclass: #NvFakeGb10
	instanceVariableNames: 'memory firmware faults writes rejections emem ememOffset aincw head tail sec2Mailbox0 sec2Mailbox1 sec2Countdown gspState gspCountdown gspMailbox0 gspMailbox1 os fmcParamsAddress wprMeta queues gsp boot42'
	classVariableNames: ''
	package: 'Tests-NV'!

NvFakeGb10 comment: 'I am a GB10''s registers as NvGspBoot sees them, for NvGspBootTest (docs/nv-gsp.md 2.3; read32:, write32:value:, and as a PCI function mem32At:bar: for NvBar0). SEC2: EMEM channel 0 with EMEMC''s offset and auto-increment, queue 0 HEAD and TAIL; writing HEAD hands SEC2 the message, which checks it as far as a test can: the MCTP and NVDM words, the COT payload, the GSP-FMC''s SHA-384 against the hash, the FMC boot parameters, GspFwWprMeta (magic, revision, the boot loader''s bytes, the GSP-RM image behind the radix-3 tables), the LIBOS arguments and, through RMARGS, GSP_ARGUMENTS_CACHED and the queues'' page table. MAILBOX0 reads 16rC001CAFE for a few reads while it works. If all is well the GSP leaves SEC2''s hold (HWCFG2 stops answering the PRI error), the FMC holds the RISC-V lockdown with its parameters'' address in the mailboxes for a few reads, then releases it; writing FALCON_OS starts GSP-RM: an NvFakeGsp on the queues, which reads the RPCs queued before the boot and sends GSP_INIT_DONE. The doorbell (NV_PGSP_QUEUE_HEAD(0)) makes it answer.

rejections says what SEC2 or the FMC found wrong. faults: make me misbehave: #running (booted already), #otherChip, #busySec2, #fmcError, #noInitDone.'!

!NvFakeGb10 class methodsFor: 'instance creation'!
memory: anNvFakeDmaMemory firmware: anNvGspFirmware
	^self new setMemory: anNvFakeDmaMemory firmware: anNvGspFirmware
! !

!NvFakeGb10 methodsFor: 'initialization'!
setMemory: anNvFakeDmaMemory firmware: anNvGspFirmware
	memory := anNvFakeDmaMemory.
	firmware := anNvGspFirmware.
	faults := Set new.
	writes := OrderedCollection new.
	rejections := OrderedCollection new.
	emem := ByteArray new: 1024.
	ememOffset := 0.
	aincw := false.
	head := 0.
	tail := 0.
	sec2Mailbox0 := 0.
	sec2Mailbox1 := 0.
	sec2Countdown := 0.
	gspState := #held.
	gspCountdown := 0.
	boot42 := 16r1ABA1000
!
fault: aSymbol
	faults add: aSymbol.
	aSymbol = #running ifTrue: [gspState := #running. gspMailbox0 := 0. gspMailbox1 := 0].
	aSymbol = #otherChip ifTrue: [boot42 := 16r1B7A1000].
	aSymbol = #busySec2 ifTrue: [tail := 16r40]
! !

!NvFakeGb10 methodsFor: 'accessing'!
writes
	"offset -> value of every write, in order"
	^writes
!
rejections
	^rejections
!
os
	^os
!
wprMeta
	"The GspFwWprMeta SEC2 read (an NvGspStruct)."
	^wprMeta
!
queues
	^queues
!
gsp
	"The fake GSP-RM, once it runs."
	^gsp
! !

!NvFakeGb10 methodsFor: 'registers'!
reg: aSymbol
	^NvGspBoot register: aSymbol
!
read32: offset
	offset = (self reg: #pmcBoot42) ifTrue: [^boot42].
	offset = (self reg: #sec2QueueHead) ifTrue: [^head].
	offset = (self reg: #sec2QueueTail) ifTrue: [^tail].
	offset = (self reg: #sec2Ememc) ifTrue: [^((ememOffset \\ 64) bitShift: 2) + ((ememOffset // 64) bitShift: 8) + (aincw ifTrue: [16r1000000] ifFalse: [0])].
	offset = (self reg: #sec2Mailbox0) ifTrue: [
		sec2Countdown > 0 ifTrue: [sec2Countdown := sec2Countdown - 1. ^16rC001CAFE].
		^sec2Mailbox0].
	offset = (self reg: #sec2Mailbox1) ifTrue: [^sec2Mailbox1].
	gspState = #held ifTrue: [
		({self reg: #gspHwcfg2. self reg: #gspMailbox0. self reg: #gspMailbox1. self reg: #gspRiscvCpuctl} includes: offset) ifTrue: [^16rBADF4100]].
	(gspState = #fmc and: [offset = (self reg: #gspHwcfg2) or: [offset = (self reg: #gspMailbox0)]]) ifTrue: [self tickFmc].
	offset = (self reg: #gspHwcfg2) ifTrue: [^gspState = #fmc ifTrue: [16r00002400] ifFalse: [16r00000400]].
	offset = (self reg: #gspMailbox0) ifTrue: [^gspMailbox0].
	offset = (self reg: #gspMailbox1) ifTrue: [^gspMailbox1].
	offset = (self reg: #gspRiscvCpuctl) ifTrue: [^16r80].
	^16rBADF5040
!
write32: offset value: aValue
	writes add: offset -> aValue.
	offset = (self reg: #sec2Ememc) ifTrue: [
		ememOffset := ((aValue bitShift: -2) bitAnd: 63) + (((aValue bitShift: -8) bitAnd: 255) * 64).
		^aincw := (aValue bitAt: 25) = 1].
	offset = (self reg: #sec2Ememd) ifTrue: [
		emem uint32At: ememOffset * 4 + 1 put: aValue.
		aincw ifTrue: [ememOffset := ememOffset + 1].
		^aValue].
	offset = (self reg: #sec2QueueTail) ifTrue: [^tail := aValue].
	offset = (self reg: #sec2QueueHead) ifTrue: [head := aValue. ^self sec2Receive].
	offset = (self reg: #gspFalconOs) ifTrue: [os := aValue. ^self startGspRm].
	offset = (self reg: #gspQueueHead) ifTrue: [^gsp ifNotNil: [:g | g ring]].
	^self error: 'NvFakeGb10: write at 16r', (offset printString: 16)
!
tickFmc
	"The FMC works a few reads, then releases the lockdown (or, with #fmcError, reports an error and keeps it)."
	gspCountdown > 0 ifTrue: [^gspCountdown := gspCountdown - 1].
	(faults includes: #fmcError) ifTrue: [^gspMailbox0 := 16r00000F01].
	gspState := #released.
	gspMailbox0 := 0.
	gspMailbox1 := 0
!
mem32At: offset bar: index
	^self read32: offset
!
mem32At: offset bar: index put: aValue
	self write32: offset value: aValue.
	^true
! !

!NvFakeGb10 methodsFor: 'SEC2 and the FMC'!
reject: aString
	rejections add: aString.
	sec2Mailbox0 := 16r00000BAD
!
sec2Receive
	"SEC2 got a message: check it; if it is good, hand the GSP to the FMC."
	| m payload fmc params |
	sec2Countdown := 2.
	gspState = #held ifFalse: [^self reject: 'the GSP is not held'].
	m := NvStruct on: (emem copyFrom: 1 to: tail + 4).
	m size = 868 ifFalse: [^self reject: 'message of ', m size printString, ' bytes'].
	(m u32At: 0) = 1 ifFalse: [^self reject: 'MCTP word ', (m u32At: 0) printString].
	(m u32At: 4) = 16r1410DE7E ifFalse: [^self reject: 'NVDM word'].
	payload := NvStruct on: (m bytes copyFrom: 9 to: 868).
	((payload u16At: 0) = 1 and: [(payload u16At: 2) = 860]) ifFalse: [^self reject: 'COT version or size'].
	fmc := memory bytesAt: (payload u64At: 4) count: (payload u32At: 20).
	(SHA384 hash: fmc) = (payload bytes copyFrom: 37 to: 84) ifFalse: [^self reject: 'GSP-FMC hash'].
	(payload bytes copyFrom: 85 to: 468) = firmware fmcPublicKey ifFalse: [^self reject: 'GSP-FMC public key'].
	(payload bytes copyFrom: 469 to: 852) = firmware fmcSignature ifFalse: [^self reject: 'GSP-FMC signature'].
	fmcParamsAddress := payload u64At: 852.
	params := NvStruct on: (memory bytesAt: fmcParamsAddress count: 88).
	((params u32At: 8) = 1 and: [(params u32At: 12) = 256 and: [(params u8At: 36) = 1 and: [(params u32At: 40) = 1]]]) ifFalse: [^self reject: 'FMC boot parameters'].
	self checkWprMeta: (params u64At: 16) libos: (params u64At: 48).
	rejections isEmpty ifFalse: [^self].
	sec2Mailbox0 := 0.
	gspState := #fmc.
	gspCountdown := 3.
	gspMailbox0 := fmcParamsAddress bitAnd: 16rFFFFFFFF.
	gspMailbox1 := fmcParamsAddress bitShift: -32
!
checkWprMeta: address libos: libosAddress
	| m image |
	m := NvGspStruct layout: (NvGsp layout: 'GspFwWprMeta').
	m bytesAt: 0 put: (memory bytesAt: address count: 256).
	wprMeta := m.
	((m at: 'magic') = 16rDC3AAE21371A60B3 and: [(m at: 'revision') = 1]) ifFalse: [^self reject: 'WprMeta magic or revision'].
	(memory bytesAt: (m at: 'sysmemAddrOfBootloader') count: (m at: 'sizeOfBootloader')) = firmware bootImage ifFalse: [^self reject: 'boot loader bytes'].
	image := self radix3: (m at: 'sysmemAddrOfRadix3Elf') size: (m at: 'sizeOfRadix3Elf').
	image = firmware gspImage ifFalse: [^self reject: 'GSP-RM image behind the radix-3 tables'].
	(memory bytesAt: (m at: 'sysmemAddrOfSignature') count: firmware gspSignature size) = firmware gspSignature ifFalse: [^self reject: 'GSP-RM signature'].
	self checkLibos: libosAddress
!
radix3: address size: n
	"The bytes the radix-3 tables at address describe: level 0 -> level 1 -> level 2 -> data pages."
	| counts level out |
	counts := NvGsp radix3Counts: n.
	level := Array with: address.
	2 to: 4 do: [:l | | next |
		next := OrderedCollection new.
		level do: [:table | 0 to: 511 do: [:k | next size < (counts at: l) ifTrue: [next add: (memory u64At: table + (8 * k))]]].
		level := next].
	out := WriteStream on: (ByteArray new: n).
	level do: [:p | out nextPutAll: (memory bytesAt: p count: 4096)].
	^out contents first: n
!
checkLibos: address
	"The LIBOS arguments: log regions then RMARGS -> GSP_ARGUMENTS_CACHED -> the queues' page table."
	| rm args shared |
	0 to: 15 do: [:i | | id |
		id := memory u64At: address + (32 * i).
		id = (NvGsp initArgId: 'RMARGS') ifTrue: [rm := memory u64At: address + (32 * i) + 8]].
	rm isNil ifTrue: [^self reject: 'no RMARGS region'].
	args := NvGspStruct layout: (NvGsp layout: 'GSP_ARGUMENTS_CACHED').
	args bytesAt: 0 put: (memory bytesAt: rm count: args size).
	shared := args at: 'messageQueueInitArguments.sharedMemPhysAddr'.
	0 to: (args at: 'messageQueueInitArguments.pageTableEntryCount') - 1 do: [:i |
		(memory u64At: shared + (8 * i)) = (shared + (4096 * i)) ifFalse: [^self reject: 'queue page table entry ', i printString]].
	(args at: 'sysmemHeapArgs.size') > 0 ifFalse: [^self reject: 'no system-memory heap'].
	queues := NvGspQueues at: (memory cpuAddressOf: shared) device: shared
!
startGspRm
	"FALCON_OS written: GSP-RM runs, makes its status queue, reads what was queued, says it is up."
	gspState = #released ifFalse: [^self].
	gspState := #running.
	gsp := NvFakeGsp on: queues.
	gsp ring.
	(faults includes: #noInitDone) ifFalse: [gsp sendEvent: #UCODE_LIBOS_PRINT result: 0; sendEvent: #GSP_INIT_DONE result: 0]
! !
