TestCase subclass: #NvGspBootTest
	instanceVariableNames: 'memory firmware gpu boot'
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspBootTest comment: 'Tests NvGspBoot against NvFakeGb10, a GB10''s SEC2, GSP-FMC and GSP-RM as far as their side of the boot is known (docs/nv-gsp.md 2): the register writes in order, what SEC2 and the FMC find in memory (checked by the fake: the message, the FMC''s hash, WprMeta, the radix-3 image, the LIBOS and GSP arguments, the queues), GSP_INIT_DONE, then RPCs on the transport it answers; the refusals (another chip, a GSP someone booted, a busy SEC2) before any write, the failures with what the mailboxes held, NvBar0''s write list and dry run. Small synthetic firmware; needs no GPU.'!

!NvGspBootTest class methodsFor: 'fixtures'!
firmware
	"Synthetic firmware: images of a few pages (the radix-3 tables still take three levels), the FMC's hash its SHA-384 as the fake SEC2 checks."
	| image fmc bootImage desc |
	image := ByteArray new: 5 * 4096 + 100 streamContents: [:s | 1 to: 5 * 4096 + 100 do: [:i | s nextPut: i * 7 \\ 251]].
	fmc := ByteArray new: 5000 withAll: 16r3C.
	bootImage := ByteArray new: 8192 withAll: 16r5A.
	desc := (NvGsp struct: 'RM_RISCV_UCODE_DESC') at: 'appVersion' put: 16r3456; at: 'monitorCodeOffset' put: 16r100; at: 'monitorDataOffset' put: 16r1000; at: 'manifestOffset' put: 16r1800; yourself.
	^NvGspFirmware gspImage: image signature: (ByteArray new: 4096 withAll: 16r77) version: '580.178.04'
		fmcImage: fmc hash: (SHA384 hash: fmc) signature: (ByteArray new: 384 withAll: 16r11) publicKey: (ByteArray new: 384 withAll: 16r22)
		bootImage: bootImage descriptor: desc
! !

!NvGspBootTest methodsFor: 'running'!
setUp
	memory := NvFakeDmaMemory new.
	firmware := self class firmware.
	gpu := NvFakeGb10 memory: memory firmware: firmware.
	boot := NvGspBoot registers: gpu memory: memory firmware: firmware.
	boot sysmemHeapSize: 1048576; timeoutMs: 200
!
tearDown
	memory release
!
writesTo: aSymbol
	^(gpu writes select: [:w | w key = (NvGspBoot register: aSymbol)]) collect: [:w | w value]
! !

!NvGspBootTest methodsFor: 'tests'!
testBoot
	| transport root order |
	transport := boot boot.
	self assert: gpu rejections isEmpty description: gpu rejections printString.
	order := (gpu writes collect: [:w | w key]) asArray.
	self assert: order first equals: (NvGspBoot register: #sec2Ememc).
	self assert: (order copyFrom: 2 to: 218) asSet equals: (Set with: (NvGspBoot register: #sec2Ememd)).
	self assert: (order copyFrom: 219 to: 221) equals: {NvGspBoot register: #sec2QueueTail. NvGspBoot register: #sec2QueueHead. NvGspBoot register: #gspFalconOs}.
	self assert: order size equals: 221.
	self assert: (self writesTo: #sec2Ememc) asArray equals: #(16r1000000).
	self assert: ((self writesTo: #sec2Ememd) first: 2) asArray equals: #(1 16r1410DE7E).
	self assert: (self writesTo: #sec2QueueTail) asArray equals: #(864).
	self assert: (self writesTo: #sec2QueueHead) asArray equals: #(0).
	self assert: gpu os equals: 16r3456.
	self assert: boot events size equals: 1.
	root := transport alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	self assert: (gpu gsp objects includesKey: root).
	self assert: (self writesTo: #gspQueueHead) asArray equals: #(0)
!
testWhatTheFmcAndGspRmSee
	| meta args regions |
	boot boot.
	meta := gpu wprMeta.
	self assert: (meta at: 'gspFwHeapSize') equals: 133 * 1048576.
	self assert: NvGspBoot wprHeapSize equals: 133 * 1048576.
	self assert: (meta at: 'sizeOfRadix3Elf') equals: firmware gspImage size.
	self assert: (meta at: 'bootloaderCodeOffset') equals: 16r100.
	self assert: (meta at: 'sizeOfSignature') equals: 4096.
	self assert: (meta at: 'sysmemAddrOfRadix3Elf') equals: (boot buffers at: #radix3) deviceAddress.
	regions := (0 to: 7) collect: [:i | (boot buffers at: #libos) u64At: 32 * i].
	self assert: regions asArray equals: (#('LOGINIT' 'LOGINTR' 'LOGRM' 'LOGMNOC' 'LOGDBG' 'LOGROOT' 'LOGKRNL' 'RMARGS') collect: [:n | NvGsp initArgId: n]).
	self assert: ((boot buffers at: #libos) u64At: 32 * 8) equals: 0.
	self assert: ((boot buffers at: #LOGRM) u64At: 8) equals: (boot buffers at: #LOGRM) deviceAddress.
	self assert: ((boot buffers at: #LOGRM) u64At: 16 * 8) equals: (boot buffers at: #LOGRM) deviceAddress + (15 * 4096).
	args := NvStruct on: ((boot buffers at: #arguments) bytesAt: 0 count: 88).
	self assert: (args u8At: 48) equals: 1.
	self assert: (args u64At: 80) equals: 1048576.
	self assert: (args u64At: 72) equals: (boot buffers at: #heap) deviceAddress
!
testRpcsQueuedBeforeTheBoot
	boot queue: (NvGsp rpc: (NvGsp function: #GSP_SET_SYSTEM_INFO) payload: (NvStruct new: 16) counted: 0 params: nil sequence: 0).
	boot queue: (NvGsp rpc: (NvGsp function: #SET_REGISTRY) payload: (NvStruct new: 8) counted: 0 params: nil sequence: 0).
	(boot boot) alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	self assert: (gpu gsp received collect: [:m | m u32At: 12]) asArray equals: #(72 73 103).
	self assert: (gpu gsp received collect: [:m | m u32At: 24]) asArray equals: #(0 1 2)
!
testCpuSequencerDuringTheBoot
	gpu sequence: ((NvStruct new: 12) u32At: 0 put: 0; u32At: 4 put: 16r123400; u32At: 8 put: 7; bytes).
	boot boot.
	self assert: (gpu others at: 16r123400) equals: 7.
	self assert: (boot log anySatisfy: [:l | l = 'ran the CPU sequencer: 1 commands'])
!
testInitRpcs
	boot queueSystemInfo: (NvGsp systemInfoBar0: 16r24000000 domain: 16rF bus: 1 devfn: 0 deviceVendor: 16r2E1210DE subsystem: 16r10DE revision: 16rA1) registry: #(#('RmFoo' 1)).
	boot boot.
	self assert: (gpu gsp received collect: [:m | m u32At: 12]) asArray equals: #(72 73).
	self assert: ((gpu gsp received first) u64At: 32) equals: 16r24000000
!
testLogs
	| words |
	boot boot.
	self assert: (boot logPutPointers at: 'LOGRM') equals: 0.
	(boot buffers at: #LOGRM) u64At: 0 put: 2; u64At: 8 put: 16rAA; u64At: 16 put: 16rBB.
	words := boot logWords: 'LOGRM'.
	self assert: words asArray equals: #(16rAA 16rBB).
	self assert: boot logPutPointers size equals: 7
!
testRefusals
	"Another chip, a GSP someone booted, a busy SEC2: refused before any write."
	#(#otherChip #running #busySec2) do: [:fault |
		| g e |
		g := NvFakeGb10 memory: memory firmware: firmware.
		g fault: fault.
		e := [(NvGspBoot registers: g memory: memory firmware: firmware) sysmemHeapSize: 4096; timeoutMs: 50; boot. nil] on: Error do: [:ex | ex return: ex messageText].
		self assert: e notNil description: fault.
		self assert: g writes isEmpty description: fault.
		fault = #running ifTrue: [self assert: (e includesSubstring: 'not held by SEC2')].
		fault = #otherChip ifTrue: [self assert: (e includesSubstring: 'not a GB10B')].
		fault = #busySec2 ifTrue: [self assert: (e includesSubstring: 'idle SEC2 queue')]]
!
testBadFirmwareIsSeen
	| e |
	firmware fmcHash at: 1 put: 0.
	e := [boot boot. nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'release of the GSP by SEC2').
	self assert: (e includesSubstring: 'SEC2 MAILBOX0/1 16r00000BAD').
	self assert: gpu rejections asArray equals: #('GSP-FMC hash')
!
testFmcError
	| e |
	gpu fault: #fmcError.
	e := [boot boot. nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'GSP-FMC reports error 16r00000F01').
	self assert: (self writesTo: #gspFalconOs) isEmpty
!
testNoInitDone
	| e |
	gpu fault: #noInitDone.
	e := [boot boot. nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'no GSP_INIT_DONE')
!
testWrongFirmwareVersion
	| f e |
	f := NvGspFirmware gspImage: firmware gspImage signature: firmware gspSignature version: '570.144' fmcImage: firmware fmcImage hash: firmware fmcHash
		signature: firmware fmcSignature publicKey: firmware fmcPublicKey bootImage: firmware bootImage descriptor: firmware bootDescriptor.
	e := [(NvGspBoot registers: gpu memory: memory firmware: f) boot. nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'not 580.178.04').
	self assert: gpu writes isEmpty
!
testBar0WriteListAndDryRun
	| bar log |
	bar := NvBar0 on: gpu dryRun: true.
	log := (NvGspBoot registers: bar memory: memory firmware: firmware) sysmemHeapSize: 4096; dryRun.
	self assert: gpu writes isEmpty.
	self assert: bar writes size equals: 220.
	self assert: (bar writes collect: [:w | w key]) asSet equals: (#(#sec2Ememc #sec2Ememd #sec2QueueTail #sec2QueueHead) collect: [:s | NvGspBoot register: s]) asSet.
	self assert: (log last includesSubstring: 'TAIL 864').
	bar := NvBar0 on: gpu.
	self should: [bar write32: 16r840100 value: 1] raise: Error.
	self assert: gpu writes isEmpty.
	bar write32: (NvGspBoot register: #gspQueueHead) value: 0.
	self assert: gpu writes size equals: 1
! !
