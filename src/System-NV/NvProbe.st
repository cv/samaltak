Object subclass: #NvProbe
	instanceVariableNames: 'device lines command'
	classVariableNames: ''
	package: 'System-NV'!

NvProbe comment: 'I look at an NVIDIA GPU without changing anything, for step 1 of driving the GB10 from UEFI (docs/nv-gsp.md, "Step 1: the probe"): its configuration space (ids, command register, BARs with the sizes the firmware assigned, the capabilities and extended capabilities, the SEC_FAULT word in NVIDIA''s vendor-specific capability), then, if memory decoding is on, a few BAR0 registers that tell what state the firmware left the GPU in: the chip ids (NV_PMC_BOOT_0, NV_PMC_BOOT_42), SEC2''s command queue 0 and mailboxes, the GSP''s HWCFG2 (released by SEC2? RISC-V lockdown?) and mailboxes, the GSP RISC-V core''s CPUCTL, and the fuse that picks the production- or debug-signed GSP-FMC. Each answer is one line of text.

I only read: configuration space and registers are never written (not even memory decoding is turned on: without it I read no registers). The device is a PciDevice or anything with its reading protocol: vendor, deviceId, config:width:, capabilitiesDo:, extendedCapabilitiesDo:, barAddress:, barResource:, mem32At:bar: (NvProbeTest uses a fake with this Spark''s configuration space). FirmwareDiagnostics'' nvidia section runs me on each NVIDIA GPU the firmware has (make usb-image USB_DIAG=nv; the World menu on UEFI).

	(NvProbe on: aPciDevice) lines'!

!NvProbe class methodsFor: 'instance creation'!
on: aPciFunction
	^self new setDevice: aPciFunction
! !

!NvProbe class methodsFor: 'testing'!
isNvidiaGpu: aPciFunction
	"An NVIDIA function of the display class (VGA, 3D controller, ...)?"
	^aPciFunction vendor = 16r10DE and: [((aPciFunction config: 8 width: 4) bitShift: -24) = 3]
! !

!NvProbe class methodsFor: 'registers'!
registers
	"The BAR0 registers I read, in this order: {offset. name}. From the 580.178.04 headers: nv_ref.h 108-183 (PMC), gb10b dev_sec_pri.h 27-48 (SEC2 at 16r840000), gh100 dev_gsp.h 26-54 and dev_falcon_v4.h 27-81 (GSP falcon at 16r110000), ga102 dev_riscv_pri.h 27 and gh100 58-68 (GSP RISC-V at 16r111000), ga100 dev_fuse.h 30-33 (the fuse kgspIsDebugModeEnabled_GA100 reads for GB10B, kernel_gsp_ga100.c 46-48)."
	^#(#(16r000000 'NV_PMC_BOOT_0') #(16r000A00 'NV_PMC_BOOT_42')
		#(16r840C00 'SEC2 QUEUE_HEAD(0)') #(16r840C04 'SEC2 QUEUE_TAIL(0)') #(16r840040 'SEC2 MAILBOX0') #(16r840044 'SEC2 MAILBOX1')
		#(16r1100F4 'GSP HWCFG2') #(16r110040 'GSP MAILBOX0') #(16r110044 'GSP MAILBOX1') #(16r111388 'GSP RISCV_CPUCTL')
		#(16r82074C 'FUSE_OPT_SECURE_GSP_DEBUG_DIS'))
!
chipNames
	"NV_PMC_BOOT_42_CHIP_ID (29:20) of chips the image knows: architecture << 4 | implementation (nv_arch.h)."
	^Dictionary new
		at: 16r1AB put: 'GB10B';
		at: 16r1A0 put: 'GB100';
		at: 16r1A2 put: 'GB102';
		at: 16r1B2 put: 'GB202';
		at: 16r1B7 put: 'GB20B';
		at: 16r180 put: 'GH100';
		yourself
!
secFaultBits
	"NV_SYSCTRL_SEC_FAULT_BIT_POSITION_* (gb10b dev_boot.h 28-35), the bits of NV_EP_PCFG_GPU_VSEC_DEBUG_SEC (configuration offset 16r2B4, gb10b dev_xtl_ep_pcfg_gpu.h 122-129) that RM decodes when a SEC_FAULT stops the GPU (kern_gpu_gb10b.c 99-176)."
	^#('FUSE_POD' 'SEC2_SCPM' 'SEC2_DCLS' 'SEC2_L5_WDT' 'GSP_DCLS' 'GSP_L5_WDT' 'PMU_DCLS' 'PMU_L5_WDT')
! !

!NvProbe methodsFor: 'initialization'!
setDevice: aPciFunction
	device := aPciFunction
! !

!NvProbe methodsFor: 'probing'!
lines
	"What I find, one line each; nothing written to the device."
	lines := OrderedCollection new.
	self identity; bars; capabilities; extendedCapabilities; registers.
	^lines asArray
!
identity
	| class |
	class := device config: 8 width: 4.
	command := device config: 4 width: 2.
	self add: 'id ', (self hex: device vendor digits: 4), ':', (self hex: device deviceId digits: 4), ' rev ', (self hex: (class bitAnd: 16rFF) digits: 2),
		' class ', (self hex: (class bitShift: -8) digits: 6), ' subsystem ', (self hex: (device config: 16r2C width: 2) digits: 4), ':', (self hex: (device config: 16r2E width: 2) digits: 4).
	self add: 'command 16r', (self hex: command digits: 4), ': memory decoding ', (self onOff: 2), ', bus master ', (self onOff: 4), ', INTx ', (((command bitAnd: 16r400) = 0) ifTrue: ['enabled'] ifFalse: ['disabled'])
!
bars
	| index unused |
	index := 0.
	unused := OrderedCollection new.
	[index < 6] whileTrue: [| low wide |
		low := device config: 16r10 + (4 * index) width: 4.
		wide := (low bitAnd: 7) = 4.
		low = 0
			ifTrue: [unused add: index printString]
			ifFalse: [(low bitAnd: 1) = 1
				ifTrue: [self add: 'bar ', index printString, ': I/O 16r', (self hex: (low bitAnd: 16rFFFFFFFC) digits: 1)]
				ifFalse: [| resource |
					resource := device barResource: index.
					self add: 'bar ', index printString, ': memory 16r', (self hex: (device barAddress: index) digits: 1),
						(wide ifTrue: [', 64-bit'] ifFalse: [', 32-bit']), (((low bitAnd: 8) = 8) ifTrue: [', prefetchable'] ifFalse: ['']),
						(resource isNil ifTrue: [', size unknown (no firmware resource)'] ifFalse: [', ', (self sizeText: (resource at: 2))])]].
		index := index + (wide ifTrue: [2] ifFalse: [1])].
	unused isEmpty ifFalse: [self add: 'bars unused: ', (', ' join: unused)]
!
capabilities
	| names details |
	names := OrderedCollection new.
	details := self collecting: [device capabilitiesDo: [:offset :id |
		names add: (self capabilityName: id), ' ', (self hex: offset digits: 2).
		id = 16r01 ifTrue: [self powerManagementAt: offset].
		id = 16r05 ifTrue: [self msiAt: offset].
		id = 16r10 ifTrue: [self expressAt: offset].
		id = 16r11 ifTrue: [self msixAt: offset]]].
	self add: 'capabilities: ', (names isEmpty ifTrue: ['none'] ifFalse: [', ' join: names]).
	lines addAll: details
!
extendedCapabilities
	| names details |
	names := OrderedCollection new.
	details := self collecting: [device extendedCapabilitiesDo: [:offset :id |
		names add: (self extendedCapabilityName: id), ' ', (self hex: offset digits: 3).
		id = 16r000B ifTrue: [self vendorSpecificAt: offset].
		id = 16r000F ifTrue: [self atsAt: offset].
		id = 16r001B ifTrue: [self pasidAt: offset].
		id = 16r0003 ifTrue: [self serialNumberAt: offset]]].
	self add: 'extended capabilities: ', (names isEmpty ifTrue: ['none (or only 256 bytes of configuration space)'] ifFalse: [', ' join: names]).
	lines addAll: details
!
registers
	| values |
	(command bitAnd: 2) = 0 ifTrue: [^self add: 'registers: not read, memory decoding is off (turning it on would be a write)'].
	values := Dictionary new.
	self class registers do: [:each | | value |
		value := device mem32At: each first bar: 0.
		values at: each first put: value.
		self add: 'reg ', each last, ' (16r', (self hex: each first digits: 6), ') = ', (value isNil ifTrue: ['read failed'] ifFalse: ['16r', (self hex: value digits: 8), (self decode: value at: each first)])].
	self state: values
! !

!NvProbe methodsFor: 'configuration space'!
powerManagementAt: offset
	self add: 'pm: ', (#('D0' 'D1' 'D2' 'D3hot') at: ((device config: offset + 4 width: 2) bitAnd: 3) + 1),
		((((device config: offset + 4 width: 2) bitAnd: 8) = 8) ifTrue: [', no soft reset'] ifFalse: [''])
!
msiAt: offset
	| control |
	control := device config: offset + 2 width: 2.
	self add: 'msi: ', (1 bitShift: ((control bitShift: -1) bitAnd: 7)) printString, ' vectors, ', ((control bitAnd: 1) = 1 ifTrue: ['enabled'] ifFalse: ['disabled'])
!
expressAt: offset
	| devCap devCtl linkCap linkStatus |
	devCap := device config: offset + 4 width: 4.
	devCtl := device config: offset + 8 width: 2.
	linkCap := device config: offset + 16rC width: 4.
	linkStatus := device config: offset + 16r12 width: 2.
	self add: 'pcie: link ', (self speed: (linkStatus bitAnd: 15)), ' x', ((linkStatus bitShift: -4) bitAnd: 63) printString,
		' of ', (self speed: (linkCap bitAnd: 15)), ' x', ((linkCap bitShift: -4) bitAnd: 63) printString,
		', max payload ', (128 bitShift: ((devCtl bitShift: -5) bitAnd: 7)) printString,
		(((devCap bitAnd: 16r10000000) = 0) ifTrue: [', no FLR'] ifFalse: [', FLR'])
!
msixAt: offset
	| control table pba |
	control := device config: offset + 2 width: 2.
	table := device config: offset + 4 width: 4.
	pba := device config: offset + 8 width: 4.
	self add: 'msi-x: ', ((control bitAnd: 16r7FF) + 1) printString, ' vectors, ', (((control bitAnd: 16r8000) = 0) ifTrue: ['disabled'] ifFalse: ['enabled']),
		', table BAR', (table bitAnd: 7) printString, ' + 16r', (self hex: (table bitAnd: 16rFFFFFFF8) digits: 1),
		', pba BAR', (pba bitAnd: 7) printString, ' + 16r', (self hex: (pba bitAnd: 16rFFFFFFF8) digits: 1)
!
vendorSpecificAt: offset
	"NVIDIA's VSEC: on GB10B its range holds NV_EP_PCFG_GPU_VSEC_DEBUG_SEC at the fixed offset 16r2B4."
	| header length |
	header := device config: offset + 4 width: 4.
	length := header bitShift: -20.
	self add: 'vsec ', (self hex: offset digits: 3), ': id ', (header bitAnd: 16rFFFF) printString, ', ', length printString, ' bytes'.
	(device vendor = 16r10DE and: [16r2B4 >= offset and: [16r2B8 <= (offset + length)]]) ifTrue: [self secFault: (device config: 16r2B4 width: 4)]
!
secFault: value
	| set iff |
	set := (1 to: 8) select: [:i | (value bitAt: i) = 1].
	iff := (value bitShift: -16) bitAnd: 16r7F.
	self add: 'sec fault (VSEC_DEBUG_SEC 16r', (self hex: value digits: 8), '): ',
		((set isEmpty and: [iff = 0]) ifTrue: ['none'] ifFalse: [(', ' join: (set collect: [:i | self class secFaultBits at: i])), (iff = 0 ifTrue: [''] ifFalse: [' IFF_POS ', iff printString])])
!
atsAt: offset
	| control |
	control := device config: offset + 6 width: 2.
	self add: 'ats: ', (((control bitAnd: 16r8000) = 0) ifTrue: ['disabled'] ifFalse: ['enabled']), ', smallest translation unit ', (4096 bitShift: (control bitAnd: 31)) printString
!
pasidAt: offset
	self add: 'pasid: ', (((device config: offset + 6 width: 2) bitAnd: 1) = 0 ifTrue: ['disabled'] ifFalse: ['enabled']),
		', ', (((device config: offset + 4 width: 2) bitShift: -8) bitAnd: 31) printString, ' bits'
!
serialNumberAt: offset
	| n |
	n := (device config: offset + 4 width: 4) + ((device config: offset + 8 width: 4) bitShift: 32).
	self add: 'serial number ', ('-' join: ((7 to: 0 by: -1) collect: [:i | self hex: ((n bitShift: i * -8) bitAnd: 255) digits: 2]))
! !

!NvProbe methodsFor: 'registers'!
decode: value at: offset
	"What a register's value says, after a colon; PRI errors (16rBADxxxxx: the target is locked or powered off) and all ones (no response) first."
	(value bitShift: -20) = 16rBAD ifTrue: [^': PRI error (target locked or powered off)'].
	value = 16rFFFFFFFF ifTrue: [^': all ones (no response?)'].
	offset = 16r000000 ifTrue: [^': architecture 16r', (self hex: ((((value bitShift: -8) bitAnd: 1) bitShift: 5) bitOr: ((value bitShift: -24) bitAnd: 31)) digits: 2),
		', implementation 16r', (self hex: ((value bitShift: -20) bitAnd: 15) digits: 1), ', revision ', (self revision: ((value bitShift: -4) bitAnd: 15) minor: (value bitAnd: 15))].
	offset = 16r000A00 ifTrue: [| chip |
		chip := (value bitShift: -20) bitAnd: 16r3FF.
		^': chip 16r', (self hex: chip digits: 3), ' (', (self class chipNames at: chip ifAbsent: ['unknown']), '), revision ',
			(self revision: ((value bitShift: -16) bitAnd: 15) minor: ((value bitShift: -12) bitAnd: 15))].
	offset = 16r840040 ifTrue: [value = 16rC001CAFE ifTrue: [^': handling a command']].
	offset = 16r1100F4 ifTrue: [^': RISC-V lockdown ', (((value bitAt: 14) = 1) ifTrue: ['engaged'] ifFalse: ['released'])].
	offset = 16r82074C ifTrue: [^((value bitAnd: 1) = 1) ifTrue: [': GSP debug disabled: production-signed GSP-FMC'] ifFalse: [': GSP debug enabled: debug-signed GSP-FMC']].
	offset = 16r111388 ifTrue: [^': core ', (((value bitAt: 8) = 1) ifTrue: ['active'] ifFalse: ['not active']), (((value bitAt: 5) = 1) ifTrue: [', halted'] ifFalse: [''])].
	^''
!
state: values
	"What the registers together say about the GPU's state (an inference: docs/nv-gsp.md 2.3)."
	| head tail hwcfg2 cpuctl |
	head := values at: 16r840C00.
	tail := values at: 16r840C04.
	hwcfg2 := values at: 16r1100F4.
	cpuctl := values at: 16r111388.
	(head notNil and: [tail notNil and: [(head bitShift: -20) ~= 16rBAD]]) ifTrue: [
		self add: 'state: SEC2 queue 0 ', (head = tail ifTrue: ['idle (head = tail): a chain-of-trust message could be sent'] ifFalse: ['busy (head ~= tail)'])].
	(hwcfg2 isNil or: [cpuctl isNil]) ifTrue: [^self add: 'state: GSP unknown (a read failed)'].
	(hwcfg2 bitShift: -8) = 16rBADF41 ifTrue: [^self add: 'state: GSP not released to the CPU (HWCFG2 reads the PRI "target locked" error): not booted by anyone yet, as nvidia.ko expects before its chain of trust'].
	((cpuctl bitShift: -20) ~= 16rBAD and: [(cpuctl bitAt: 8) = 1 and: [(hwcfg2 bitAt: 14) = 0]])
		ifTrue: [^self add: 'state: GSP running (lockdown released, RISC-V active): something booted it before us (the firmware''s GPU driver?); a second chain of trust would likely be refused until a reset'].
	self add: 'state: GSP released to the CPU but not running'
! !

!NvProbe methodsFor: 'private'!
add: aString
	lines add: aString
!
collecting: aBlock
	"The lines aBlock adds, kept apart (a capability's details follow the list of capabilities)."
	| saved collected |
	saved := lines.
	lines := OrderedCollection new.
	[aBlock value] ensure: [collected := lines. lines := saved].
	^collected
!
onOff: bit
	^(command bitAnd: bit) = 0 ifTrue: ['off'] ifFalse: ['on']
!
speed: code
	^#('2.5 GT/s' '5 GT/s' '8 GT/s' '16 GT/s' '32 GT/s' '64 GT/s') at: code ifAbsent: ['speed ', code printString]
!
revision: major minor: minor
	^(self hex: major digits: 1) asUppercase, (self hex: minor digits: 1)
!
sizeText: bytes
	bytes >= 1048576 ifTrue: [^(bytes // 1048576) printString, ' MB'].
	bytes >= 1024 ifTrue: [^(bytes // 1024) printString, ' KB'].
	^bytes printString, ' bytes'
!
hex: anInteger digits: n
	^(anInteger printString: 16) asLowercase padLeftTo: n with: $0
!
capabilityName: id
	^(Dictionary new at: 16r01 put: 'pm'; at: 16r05 put: 'msi'; at: 16r09 put: 'vendor'; at: 16r10 put: 'pcie'; at: 16r11 put: 'msi-x'; yourself)
		at: id ifAbsent: ['16r', (self hex: id digits: 2)]
!
extendedCapabilityName: id
	^(Dictionary new at: 16r01 put: 'aer'; at: 16r03 put: 'dsn'; at: 16r0B put: 'vsec'; at: 16r0D put: 'acs'; at: 16r0E put: 'ari'; at: 16r0F put: 'ats';
		at: 16r18 put: 'ltr'; at: 16r19 put: 'secondary-pcie'; at: 16r1B put: 'pasid'; at: 16r1E put: 'l1ss'; at: 16r25 put: 'dlf'; at: 16r26 put: 'pl16'; at: 16r27 put: 'margining'; at: 16r2A put: 'pl32'; yourself)
		at: id ifAbsent: ['16r', (self hex: id digits: 4)]
! !
