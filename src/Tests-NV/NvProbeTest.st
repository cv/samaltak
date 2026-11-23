TestCase subclass: #NvProbeTest
	instanceVariableNames: 'gpu'
	classVariableNames: ''
	package: 'Tests-NV'!

NvProbeTest comment: 'Tests NvProbe on NvFakePciFunction spark (the DGX Spark''s GB10 configuration space as Linux shows it, register values from the headers): the configuration space''s decoding, the registers and the state they imply, that nothing is written and that no register is read without memory decoding; and, on UEFI, FirmwareDiagnostics'' nvidia section on the real firmware (under QEMU: no NVIDIA GPU). Needs no GPU.'!

!NvProbeTest methodsFor: 'running'!
setUp
	gpu := NvFakePciFunction spark
!
lines
	^(NvProbe on: gpu) lines
! !

!NvProbeTest methodsFor: 'tests'!
testConfigurationSpace
	| lines |
	lines := self lines.
	#('id 10de:2e12 rev a1 class 030000 subsystem 10de:0000'
		'command 16r0407: memory decoding on, bus master on, INTx disabled'
		'bar 0: memory 16r24000000, 64-bit, prefetchable, 64 MB'
		'bars unused: 2, 3, 4, 5'
		'capabilities: pm 40, msi 48, pcie 60, vendor 9c, msi-x b0'
		'pm: D0, no soft reset'
		'msi: 16 vectors, disabled'
		'pcie: link 2.5 GT/s x1 of 2.5 GT/s x16, max payload 256, FLR'
		'msi-x: 9 vectors, enabled, table BAR0 + 16rb90000, pba BAR0 + 16rba0000'
		'extended capabilities: secondary-pcie 100, ltr 12c, dlf 14c, pl16 158, pl32 188, aer 1b8, margining 200, ari 248, l1ss 290, vsec 2a4, ats 2e0, pasid 2e8, dsn 2f0'
		'vsec 2a4: id 1, 20 bytes'
		'sec fault (VSEC_DEBUG_SEC 16r00000000): none'
		'ats: enabled, smallest translation unit 4096'
		'pasid: enabled, 20 bits'
		'serial number 00-00-00-00-00-2d-b0-48')
		do: [:each | self assert: (lines includes: each) description: each].
	self assert: (lines indexOf: 'capabilities: pm 40, msi 48, pcie 60, vendor 9c, msi-x b0') < (lines indexOf: 'pm: D0, no soft reset').
	self assert: (lines indexOf: 'pasid: enabled, 20 bits') < (lines indexOf: 'reg NV_PMC_BOOT_0 (16r000000) = 16r1ab000a1: architecture 16r1a, implementation 16rb, revision A1')
!
testRegistersOfAnUnbootedGpu
	| lines |
	lines := self lines.
	#('reg NV_PMC_BOOT_0 (16r000000) = 16r1ab000a1: architecture 16r1a, implementation 16rb, revision A1'
		'reg NV_PMC_BOOT_42 (16r000a00) = 16r1aba1000: chip 16r1ab (GB10B), revision A1'
		'reg SEC2 QUEUE_HEAD(0) (16r840c00) = 16r00000000'
		'reg SEC2 MAILBOX0 (16r840040) = 16r00000000'
		'reg GSP HWCFG2 (16r1100f4) = 16rbadf4100: PRI error (target locked or powered off)'
		'reg GSP RISCV_CPUCTL (16r111388) = 16rbadf4100: PRI error (target locked or powered off)'
		'reg FUSE_OPT_SECURE_GSP_DEBUG_DIS (16r82074c) = 16r00000001: GSP debug disabled: production-signed GSP-FMC'
		'state: SEC2 queue 0 idle (head = tail): a chain-of-trust message could be sent')
		do: [:each | self assert: (lines includes: each) description: each].
	self assert: (lines last beginsWith: 'state: GSP not released to the CPU').
	self assert: gpu reads asArray equals: (NvProbe registers collect: [:each | each first]).
	self assert: gpu writes isEmpty
!
testGspRunning
	| lines |
	gpu registers at: 16r1100F4 put: 16r00000400; at: 16r111388 put: 16r00000080; at: 16r110040 put: 0; at: 16r840040 put: 16rC001CAFE.
	lines := self lines.
	self assert: (lines includes: 'reg GSP HWCFG2 (16r1100f4) = 16r00000400: RISC-V lockdown released').
	self assert: (lines includes: 'reg GSP RISCV_CPUCTL (16r111388) = 16r00000080: core active').
	self assert: (lines includes: 'reg SEC2 MAILBOX0 (16r840040) = 16rc001cafe: handling a command').
	self assert: (lines last beginsWith: 'state: GSP running').
	gpu registers at: 16r1100F4 put: 16r00002400; at: 16r111388 put: 16r00000010.
	lines := self lines.
	self assert: (lines includes: 'reg GSP HWCFG2 (16r1100f4) = 16r00002400: RISC-V lockdown engaged').
	self assert: (lines includes: 'reg GSP RISCV_CPUCTL (16r111388) = 16r00000010: core not active, halted').
	self assert: lines last equals: 'state: GSP released to the CPU but not running'
!
testSecFault
	gpu space at: 16r2B4 + 1 put: 16r12; at: 16r2B4 + 3 put: 16r05.
	self assert: (self lines includes: 'sec fault (VSEC_DEBUG_SEC 16r00050012): SEC2_SCPM, GSP_DCLS IFF_POS 5')
!
testNoRegistersWithoutMemoryDecoding
	| lines |
	gpu space at: 5 put: ((gpu space at: 5) bitAnd: 16rFD).
	lines := self lines.
	self assert: (lines includes: 'command 16r0405: memory decoding off, bus master on, INTx disabled').
	self assert: lines last equals: 'registers: not read, memory decoding is off (turning it on would be a write)'.
	self assert: gpu reads isEmpty.
	self assert: gpu writes isEmpty
!
testWhichFunctionsAreNvidiaGpus
	self assert: (NvProbe isNvidiaGpu: gpu).
	gpu space at: 1 put: 16r86; at: 2 put: 16r80.
	self deny: (NvProbe isNvidiaGpu: gpu).
	gpu space at: 1 put: 16rDE; at: 2 put: 16r10; at: 12 put: 2.
	self deny: (NvProbe isNvidiaGpu: gpu)
!
testFirmwareDiagnostics
	"On UEFI (QEMU in make test-uefi: no NVIDIA GPU) the section on the real firmware; hosted, one line."
	| lines |
	lines := FirmwareDiagnostics nvidiaLines.
	Machine hasFirmware
		ifTrue: [self assert: (lines includes: 'nvidia: no NVIDIA GPU') description: lines printString]
		ifFalse: [self assert: lines equals: #('nvidia: no firmware: not on UEFI')]
! !
