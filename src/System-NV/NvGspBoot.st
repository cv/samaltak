Object subclass: #NvGspBoot
	instanceVariableNames: 'registers memory firmware sysmemHeapSize timeoutMs buffers queues endpoint fmcParams message rpcs rpcSequence events sequencer log'
	classVariableNames: ''
	package: 'System-NV'!

NvGspBoot comment: 'I boot GSP-RM on a GB10 the way nvidia.ko 580.178.04 does (docs/nv-gsp.md 2): prepare puts the firmware (NvGspFirmware) and every structure it needs in DMA memory (an NvDmaMemory): the boot loader, the GSP-RM image behind radix-3 tables, its signature, the GSP-FMC, the LIBOS log buffers, the message queues, GSP-RM''s system-memory heap, GSP_ARGUMENTS_CACHED, the LIBOS arguments, GspFwWprMeta, the FMC boot parameters and the SEC2 chain-of-trust message; check refuses a GPU that is not a GB10B or whose GSP is not held by SEC2 (someone booted it: it needs a reset first); sendChainOfTrust hands the message to SEC2 through its EMEM queue; waitForRelease waits for SEC2 to release the GSP and the FMC to release its lockdown; startRiscv writes FALCON_OS and checks the core; waitForInitDone waits on the status queue for GSP_INIT_DONE, running GSP''s CPU sequencer requests (sequencer:) and keeping other events. boot does all of it and answers an NvGspTransport on the queues.

registers is anything with read32: and write32:value: (NvBar0 on the GPU''s PciDevice, with its write list and dry run; a fake GB10 in tests). Every wait has the GPU default timeout of 4 s (timeoutMs:) and says, when it runs out, what it waited for and what the mailboxes held. dryRun goes as far as the chain of trust on registers that only record writes (NvBar0 on: dryRun: true) and answers the log. Every step adds a line to log.'!

!NvGspBoot class methodsFor: 'instance creation'!
registers: aRegisters memory: anNvDmaMemory firmware: anNvGspFirmware
	^self new setRegisters: aRegisters memory: anNvDmaMemory firmware: anNvGspFirmware
! !

!NvGspBoot class methodsFor: 'registers'!
registers
	"The BAR0 registers of the boot by name (docs/nv-gsp.md 2.3: gb10b dev_sec_pri.h 27-48, gh100 dev_gsp.h 26-54, dev_falcon_v4.h 27-81, dev_riscv_pri.h 58-68, ga102 dev_gsp.h 38, nv_ref.h 149)."
	^Dictionary new
		at: #pmcBoot42 put: 16r000A00;
		at: #sec2Mailbox0 put: 16r840040;
		at: #sec2Mailbox1 put: 16r840044;
		at: #sec2Ememc put: 16r840AC0;
		at: #sec2Ememd put: 16r840AC4;
		at: #sec2QueueHead put: 16r840C00;
		at: #sec2QueueTail put: 16r840C04;
		at: #gspMailbox0 put: 16r110040;
		at: #gspMailbox1 put: 16r110044;
		at: #gspFalconOs put: 16r110080;
		at: #gspHwcfg2 put: 16r1100F4;
		at: #gspQueueHead put: 16r110C00;
		at: #gspRiscvCpuctl put: 16r111388;
		yourself
!
register: aSymbol
	^self registers at: aSymbol
!
wprHeapSize
	"GspFwWprMeta's gspFwHeapSize on GB10B, GSP-RM's heap inside WPR2 (_kgspCalculateFwHeapSize, kernel_gsp.c 5542-5590): the LIBOS 3 bare-metal OS carveout 22 MB, the base 14 MB, 96 KB a GB of memory (1 GB for a GPU without video memory) and 48 KB for each of 2048 channels, each rounded up to 1 MB; between 88 and 280 MB (gsp_fw_heap.h 32-110). 133 MB."
	| mb heap |
	mb := 1048576.
	heap := (22 * mb) + (14 * mb) + (96 * 1024 * 1 + mb - 1 // mb * mb) + (48 * 1024 * 2048 + mb - 1 // mb * mb).
	^(heap max: 88 * mb) min: 280 * mb
! !

!NvGspBoot methodsFor: 'initialization'!
setRegisters: aRegisters memory: anNvDmaMemory firmware: anNvGspFirmware
	registers := aRegisters.
	memory := anNvDmaMemory.
	firmware := anNvGspFirmware.
	sysmemHeapSize := NvGsp sysmemHeapSize.
	timeoutMs := 4000.
	rpcs := OrderedCollection new.
	rpcSequence := 0.
	events := OrderedCollection new.
	log := OrderedCollection new.
	sequencer := [:anRpc | self error: 'GSP asked for the CPU sequencer (GSP_RUN_CPU_SEQUENCER), which is not here yet']
! !

!NvGspBoot methodsFor: 'accessing'!
sysmemHeapSize: bytes
	sysmemHeapSize := bytes
!
timeoutMs: anInteger
	timeoutMs := anInteger
!
sequencer: aBlock
	"What runs GSP_RUN_CPU_SEQUENCER events: aBlock value: the event's RPC."
	sequencer := aBlock
!
buffers
	"name -> NvDmaBuffer of everything prepare allocated"
	^buffers
!
queues
	^queues
!
message
	"The SEC2 message (an NvStruct), after prepare."
	^message
!
events
	^events
!
log
	^log
!
queue: anRpc
	"An RPC to put in the command queue before the boot, as nvidia.ko does with GSP_SET_SYSTEM_INFO and SET_REGISTRY (kgspQueueAsyncInitRpcs, kernel_gsp.c 3792-3815); its header's sequence is set here."
	anRpc u32At: 24 put: rpcSequence.
	rpcSequence := rpcSequence + 1.
	rpcs add: anRpc
! !

!NvGspBoot methodsFor: 'booting'!
boot
	"Boot GSP-RM; answer an NvGspTransport to it."
	self prepare; check; sendChainOfTrust; waitForRelease; startRiscv; waitForInitDone.
	^self transport
!
dryRun
	"Prepare, check and send the chain of trust on registers that only record (NvBar0 on: dryRun: true); answer the log."
	self prepare; check; sendChainOfTrust.
	^log
!
transport
	^(NvGspTransport endpoint: endpoint doorbell: [registers write32: (self class register: #gspQueueHead) value: 0])
		sequence: rpcSequence;
		open;
		yourself
! !

!NvGspBoot methodsFor: 'preparing'!
prepare
	"Everything in memory, nothing on the GPU (kgspInitRm_IMPL, kernel_gsp.c 3984-4179; kgspPrepareForBootstrap_GH100, kernel_gsp_gh100.c 775-810)."
	| radix3 signature regions heap args libos wprMeta |
	firmware problems isEmpty ifFalse: [^self error: 'GSP firmware: ', (', ' join: firmware problems)].
	buffers := Dictionary new.
	(self copy: firmware bootImage named: #bootloader) yourself.
	radix3 := self radix3.
	signature := self copy: firmware gspSignature named: #signature.
	self copy: firmware fmcImage named: #fmc.
	regions := NvGsp logBuffers collect: [:each | self logBuffer: each first size: each last].
	queues := self allocate: NvGspQueues size named: #queues.
	queues := NvGspQueues at: queues cpuAddress device: queues deviceAddress.
	queues prepare.
	endpoint := queues cpuEndpoint.
	heap := self allocate: sysmemHeapSize named: #heap.
	args := (queues arguments: heap deviceAddress size: heap size) at: 'bDmemStack' put: 1; yourself.
	args := self page: args named: #arguments.
	libos := self page: (NvGsp libosArguments: regions asArray, {NvGsp libosRegion: 'RMARGS' address: args deviceAddress size: args size}) named: #libos.
	wprMeta := self page: (NvGsp wprMetaBootloader: (buffers at: #bootloader) deviceAddress size: firmware bootImage size descriptor: firmware bootDescriptor
		radix3: radix3 deviceAddress imageSize: firmware gspImage size signature: signature deviceAddress size: signature size heapSize: self class wprHeapSize) named: #wprMeta.
	fmcParams := self page: (NvGsp fmcBootParamsWprMeta: wprMeta deviceAddress libosArgs: libos deviceAddress) named: #fmcParams.
	message := NvGsp sec2Message: (NvGsp cotPayloadFmc: (buffers at: #fmc) deviceAddress size: firmware fmcImage size hash: firmware fmcHash
		publicKey: firmware fmcPublicKey signature: firmware fmcSignature bootArgs: fmcParams deviceAddress).
	rpcs do: [:each | endpoint send: each].
	self note: 'prepared: ', buffers size printString, ' buffers, ', ((buffers inject: 0 into: [:sum :b | sum + b size]) // 1024) printString, ' KB; ', rpcs size printString, ' RPCs queued; SEC2 message ', message size printString, ' bytes'
!
allocate: bytes named: aSymbol
	| b |
	b := memory allocate: bytes.
	buffers at: aSymbol put: b.
	^b
!
copy: aByteArray named: aSymbol
	"A buffer holding aByteArray (4 KB-aligned, the rest zero)."
	^(self allocate: aByteArray size named: aSymbol) bytesAt: 0 put: aByteArray; yourself
!
page: anNvStruct named: aSymbol
	^self copy: anNvStruct bytes named: aSymbol
!
radix3
	"GSP-RM's image behind its radix-3 tables, all in one buffer (kgspCreateRadix3_IMPL, kernel_gsp.c 4913-5048)."
	| counts tablePages b |
	counts := NvGsp radix3Counts: firmware gspImage size.
	tablePages := (counts at: 1) + (counts at: 2) + (counts at: 3).
	b := self allocate: (tablePages + (counts at: 4)) * NvGsp page named: #radix3.
	b bytesAt: 0 put: (NvGsp radix3Tables: firmware gspImage size pageAddress: [:i | b deviceAddress + (i * NvGsp page)]) bytes.
	b bytesAt: tablePages * NvGsp page put: firmware gspImage.
	^b
!
logBuffer: aName size: bytes
	"A LIBOS log buffer: zeroed, its put pointer at 0 and its pages' device addresses from 8 (kernel_gsp.c 3070-3105); answer its LIBOS region."
	| b |
	b := self allocate: bytes named: aName asSymbol.
	0 to: b size // NvGsp page - 1 do: [:i | b u64At: 8 * (i + 1) put: b deviceAddress + (i * NvGsp page)].
	^NvGsp libosRegion: aName address: (b u64At: 8) size: b size
! !

!NvGspBoot methodsFor: 'registers'!
read: aSymbol
	^registers read32: (self class register: aSymbol)
!
write: aSymbol value: anInteger
	registers write32: (self class register: aSymbol) value: anInteger
!
isDryRun
	^(registers respondsTo: #isDryRun) and: [registers isDryRun]
!
hex: anInteger
	^'16r', ((anInteger printString: 16) padLeftTo: 8 with: $0)
!
mailboxes
	^'SEC2 MAILBOX0/1 ', (self hex: (self read: #sec2Mailbox0)), ' ', (self hex: (self read: #sec2Mailbox1)),
		', GSP HWCFG2 ', (self hex: (self read: #gspHwcfg2)), ', GSP MAILBOX0/1 ', (self hex: (self read: #gspMailbox0)), ' ', (self hex: (self read: #gspMailbox1))
!
waitFor: aString until: aBlock
	"Poll aBlock until it answers true, at most timeoutMs (gpuTimeoutCondWait)."
	| start |
	start := Time millisecondClockValue.
	[aBlock value] whileFalse: [
		Time millisecondClockValue - start > timeoutMs ifTrue: [^self error: 'GSP boot: no ', aString, ' in ', timeoutMs printString, ' ms (', self mailboxes, ')'].
		(Delay forMilliseconds: 1) wait].
	self note: aString, ' after ', (Time millisecondClockValue - start) printString, ' ms'
!
note: aString
	log add: aString
! !

!NvGspBoot methodsFor: 'booting steps'!
check
	"Refuse a GPU that is not a GB10B, or whose GSP SEC2 does not hold (docs/nv-gsp.md 6.3: someone booted it; a second chain of trust would be refused): read only."
	| boot42 hwcfg2 |
	boot42 := self read: #pmcBoot42.
	((boot42 bitShift: -20) bitAnd: 16r3FF) = 16r1AB ifFalse: [^self error: 'GSP boot: not a GB10B (NV_PMC_BOOT_42 ', (self hex: boot42), ')'].
	hwcfg2 := self read: #gspHwcfg2.
	(hwcfg2 bitShift: -8) = 16rBADF41 ifFalse: [^self error: 'GSP boot: the GSP is not held by SEC2 (HWCFG2 ', (self hex: hwcfg2), ', RISCV_CPUCTL ', (self hex: (self read: #gspRiscvCpuctl)), '): something booted it; it needs a reset first'].
	self note: 'checked: GB10B (NV_PMC_BOOT_42 ', (self hex: boot42), '), GSP held by SEC2'
!
sendChainOfTrust
	"The COT message into SEC2's EMEM channel 0, then its queue's TAIL and HEAD (ksec2SendPacket_GB10B, kernel_sec2_gb10b.c 699-733, 118-214, 72-93); wait while SEC2 handles it (285-311)."
	| words start end |
	self waitFor: 'idle SEC2 queue 0 (HEAD = TAIL)' until: [(self read: #sec2QueueHead) = (self read: #sec2QueueTail)].
	words := (0 to: message size - 1 by: 4) collect: [:i | message u32At: i].
	self write: #sec2Ememc value: (1 bitShift: 24).
	start := self ememOffset.
	words do: [:w | self write: #sec2Ememd value: w].
	self isDryRun ifFalse: [
		end := self ememOffset.
		end - start = words size ifFalse: [^self error: 'GSP boot: SEC2 EMEM took ', (end - start) printString, ' of ', words size printString, ' words']].
	self write: #sec2QueueTail value: (NvGsp sec2QueueTail: message).
	self write: #sec2QueueHead value: 0.
	self note: 'sent the chain of trust: ', words size printString, ' words, TAIL ', (NvGsp sec2QueueTail: message) printString.
	self isDryRun ifTrue: [^self].
	self waitFor: 'end of SEC2''s command handling (MAILBOX0 ~= 16rC001CAFE)' until: [(self read: #sec2Mailbox0) ~= 16rC001CAFE]
!
ememOffset
	"EMEMC(0)'s offset in words: OFFS (7:2) within a 64-word block, BLK (15:8)."
	| v |
	v := self read: #sec2Ememc.
	^((v bitShift: -2) bitAnd: 63) + (((v bitShift: -8) bitAnd: 255) * 64)
!
waitForRelease
	"SEC2 releases the GSP to the CPU (_ksec2IsGspTargetMaskReleased, kernel_sec2_gb10b.c 264-283), then the GSP-FMC releases its lockdown or reports an error (_kgspLockdownReleasedOrFmcError, kernel_gsp_gh100.c 492-535, 926-948)."
	| fmcError |
	self waitFor: 'release of the GSP by SEC2 (HWCFG2 not 16rBADF41xx)' until: [| v |
		v := self read: #gspHwcfg2.
		v ~= 0 and: [(v bitAnd: 16rFFFFFF00) ~= 16rBADF4100]].
	self waitFor: 'release of the RISC-V lockdown by the GSP-FMC' until: [self lockdownReleasedOrFmcError].
	fmcError := self read: #gspMailbox0.
	fmcError = 0 ifFalse: [^self error: 'GSP boot: the GSP-FMC reports error ', (self hex: fmcError), ' (', self mailboxes, ')']
!
lockdownReleasedOrFmcError
	| mailbox0 address |
	mailbox0 := self read: #gspMailbox0.
	address := (buffers at: #fmcParams) deviceAddress.
	(mailbox0 ~= 0 and: [mailbox0 = (address bitAnd: 16rFFFFFFFF) and: [(self read: #gspMailbox1) = (address bitShift: -32)]]) ifTrue: [^false].
	^((self read: #gspHwcfg2) bitAt: 14) = 0 or: [mailbox0 ~= 0]
!
startRiscv
	"FALCON_OS = the boot loader's appVersion, then the RISC-V core must be active (kernel_gsp_gh100.c 955-966)."
	| cpuctl |
	self write: #gspFalconOs value: (firmware bootDescriptor at: 'appVersion').
	cpuctl := self read: #gspRiscvCpuctl.
	(cpuctl bitAt: 8) = 1 ifFalse: [^self error: 'GSP boot: the RISC-V core is not active (RISCV_CPUCTL ', (self hex: cpuctl), ')'].
	self note: 'GSP RISC-V active (RISCV_CPUCTL ', (self hex: cpuctl), ')'
!
waitForInitDone
	"GSP-RM makes its status queue (GspStatusQueueInit), then sends GSP_INIT_DONE (kgspWaitForRmInitDone_IMPL, kernel_gsp.c 5252-5282); meanwhile GSP_RUN_CPU_SEQUENCER goes to the sequencer and other events are kept."
	| done |
	self waitFor: 'status queue from GSP-RM' until: [endpoint isLinked].
	done := false.
	self waitFor: 'GSP_INIT_DONE' until: [| m |
		[done not and: [(m := endpoint receive) notNil]] whileTrue: [
			(m u32At: 12) = (NvGsp function: #GSP_INIT_DONE)
				ifTrue: [
					(m u32At: 16) = 0 ifFalse: [^self error: 'GSP boot: GSP_INIT_DONE with result ', (self hex: (m u32At: 16))].
					done := true]
				ifFalse: [(m u32At: 12) = (NvGsp function: #GSP_RUN_CPU_SEQUENCER)
					ifTrue: [sequencer value: m]
					ifFalse: [events add: m]]].
		done].
	self note: 'GSP-RM up: ', events size printString, ' events before GSP_INIT_DONE'
! !
