PciDevice subclass: #NvFakePciFunction
	instanceVariableNames: 'space registers bars reads writes'
	classVariableNames: ''
	package: 'Tests-NV'!

NvFakePciFunction comment: 'I am a PCI function for NvProbeTest: a 4 KB configuration space, BAR resources and BAR0 registers, all given. I record the registers read and fail on any write, so a test can check that NvProbe only reads. spark is the DGX Spark''s GB10 (000f:01:00.0) as Linux shows it: the configuration space from sudo lspci -s 000f:01:00.0 -xxxx (read only, with nvidia.ko bound), BAR0''s 64 MB at 16r24000000, and register values made from the 580.178.04 headers for a GB10B of revision A1 that nobody booted (Linux gives no read-only way to read BAR0 under a running driver).'!

!NvFakePciFunction class methodsFor: 'instance creation'!
spark
	^self new setSpace: self sparkConfigurationSpace bars: (Dictionary new at: 0 put: #(16r24000000 16r4000000); yourself) registers: self unbootedRegisters
!
sparkConfigurationSpace
	"The non-zero rows of lspci -xxxx for 000f:01:00.0 (2026-11-23, driver 580.178.04 bound); the rest is zero."
	| space |
	space := ByteArray new: 4096.
	self sparkRows do: [:row | | parts base |
		parts := (row copyReplaceAll: ':' with: ' ') substrings.
		base := Integer readFrom: parts first asUppercase base: 16.
		parts allButFirst doWithIndex: [:hex :i | space at: base + i put: (Integer readFrom: hex asUppercase base: 16)]].
	^space
!
sparkRows
	^#(
		'00: de 10 12 2e 07 04 10 00 a1 00 00 03 00 00 00 00'
		'10: 0c 00 00 24 00 00 00 00 00 00 00 00 00 00 00 00'
		'20: 00 00 00 00 00 00 00 00 00 00 00 00 de 10 00 00'
		'30: 00 00 00 00 40 00 00 00 00 00 00 00 ff 01 00 00'
		'40: 01 48 13 00 08 00 00 00 05 60 88 03 00 00 00 00'
		'60: 10 9c 02 00 21 80 00 10 3f 29 00 00 01 79 45 00'
		'70: 08 00 11 10 00 00 00 00 00 00 00 00 00 00 00 00'
		'80: 00 00 00 00 13 08 67 00 40 04 00 00 02 00 80 01'
		'90: 05 00 00 00 00 00 00 00 00 00 00 00 09 b0 14 01'
		'a0: 00 00 10 80 00 00 00 00 00 00 00 00 00 00 00 00'
		'b0: 11 00 08 80 00 00 b9 00 00 00 ba 00 00 00 00 00'
		'100: 19 00 c1 12 00 00 00 00 00 00 00 00 00 7f 00 7f'
		'110: 00 7f 00 7f 00 7f 00 7f 00 7f 00 7f 00 7f 00 7f'
		'120: 00 7f 00 7f 00 7f 00 7f 00 7f 00 7f 18 00 c1 14'
		'140: 00 00 00 00 00 00 00 00 00 00 00 00 25 00 81 15'
		'150: 01 00 00 80 00 00 00 00 26 00 81 18 00 00 00 00'
		'170: 00 00 00 00 00 00 00 00 f0 f0 f0 f0 f0 f0 f0 f0'
		'180: f0 f0 f0 f0 f0 f0 f0 f0 2a 00 81 1b 01 01 00 00'
		'1a0: 00 00 00 00 00 00 00 00 f0 f0 f0 f0 f0 f0 f0 f0'
		'1b0: f0 f0 f0 f0 f0 f0 f0 f0 01 00 02 20 00 00 00 00'
		'1c0: 00 00 40 00 30 20 46 00 00 00 00 00 00 e0 00 00'
		'200: 27 00 81 24 01 00 00 00 38 9c 00 00 38 9c 00 00'
		'210: 38 9c 00 00 38 9c 00 00 38 9c 00 00 38 9c 00 00'
		'220: 38 9c 00 00 38 9c 00 00 38 9c 00 00 38 9c 00 00'
		'230: 38 9c 00 00 38 9c 00 00 38 9c 00 00 38 9c 00 00'
		'240: 38 9c 00 00 38 9c 00 00 0e 00 01 29 00 00 00 00'
		'290: 1e 00 42 2a 1f 00 28 00 00 00 00 00 28 00 00 00'
		'2a0: 00 00 00 00 0b 00 01 2e 01 00 41 01 02 00 01 00'
		'2e0: 0f 00 81 2e 60 00 00 80 1b 00 01 2f 00 14 01 00'
		'2f0: 03 00 01 00 48 b0 2d 00 00 00 00 00 00 00 00 00'
	)
!
unbootedRegisters
	"BAR0 as a GB10B (chip 16r1AB, revision A1) nobody booted would show it, from the headers (NV_PMC_BOOT_0/42 fields, nv_ref.h 108-183): SEC2's queue idle, its mailboxes 0, a production part (FUSE_OPT_SECURE_GSP_DEBUG_DIS 1), the GSP still held by SEC2 (its registers answer the PRI target-locked error 16rBADF41xx, kernel_sec2_gb10b.c 264-283)."
	^Dictionary new
		at: 16r000000 put: 16r1AB000A1;
		at: 16r000A00 put: 16r1ABA1000;
		at: 16r840C00 put: 0;
		at: 16r840C04 put: 0;
		at: 16r840040 put: 0;
		at: 16r840044 put: 0;
		at: 16r1100F4 put: 16rBADF4100;
		at: 16r110040 put: 16rBADF4100;
		at: 16r110044 put: 16rBADF4100;
		at: 16r111388 put: 16rBADF4100;
		at: 16r82074C put: 1;
		yourself
! !

!NvFakePciFunction methodsFor: 'initialization'!
setSpace: aByteArray bars: aDictionary registers: registerDictionary
	space := aByteArray.
	bars := aDictionary.
	registers := registerDictionary.
	reads := OrderedCollection new.
	writes := OrderedCollection new
! !

!NvFakePciFunction methodsFor: 'accessing'!
registers
	^registers
!
reads
	"The BAR0 offsets read, in order."
	^reads
!
writes
	^writes
!
space
	^space
! !

!NvFakePciFunction methodsFor: 'configuration'!
config: offset width: w
	| v |
	offset + w > space size ifTrue: [^0].
	v := 0.
	w to: 1 by: -1 do: [:i | v := (v bitShift: 8) + (space at: offset + i)].
	^v
!
config: offset width: w put: v
	writes add: offset -> v.
	self error: 'NvFakePciFunction: configuration write at 16r', (offset printString: 16)
!
barResource: index
	^bars at: index ifAbsent: [nil]
!
mem32At: offset bar: index
	index = 0 ifFalse: [^nil].
	reads add: offset.
	^registers at: offset ifAbsent: [16rBADF5040]
!
location
	^'000f:01:00.0'
! !

!NvFakePciFunction methodsFor: 'driving'!
disconnect
	writes add: #disconnect.
	self error: 'NvFakePciFunction: disconnect'
!
enable
	writes add: #enable.
	self error: 'NvFakePciFunction: enable'
!
allocate: bytes
	writes add: #allocate.
	self error: 'NvFakePciFunction: allocate'
!
release
! !
