TestCase subclass: #MachineTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Devices'!

MachineTest comment: 'The machine primitives on a host: memory outside the heap, read and written by address, copied to and from objects; the firmware is not there (it is on UEFI).'!

!MachineTest methodsFor: 'tests'!
testMemory
	| a b |
	a := Machine allocate: 64.
	[self assert: (Machine bytesAt: a count: 64) equals: (ByteArray new: 64).
	Machine uint64At: a put: 16rFEDCBA9876543210.
	self assert: (Machine uint64At: a) equals: 16rFEDCBA9876543210.
	self assert: (Machine uint32At: a) equals: 16r76543210.
	self assert: (Machine uint16At: a + 6) equals: 16rFEDC.
	self assert: (Machine uint8At: a + 7) equals: 16rFE.
	Machine uint32At: a + 8 put: -2.
	self assert: (Machine int32At: a + 8) equals: -2.
	Machine bytesAt: a + 16 put: #[1 2 3 4 5].
	b := ByteArray new: 8.
	Machine copy: 5 from: a at: 16 to: b at: 2.
	self assert: b equals: #[0 0 1 2 3 4 5 0].
	Machine copy: 4 from: a + 16 at: 0 to: a + 17 at: 0.
	self assert: (Machine bytesAt: a + 16 count: 6) equals: #[1 1 2 3 4 0].
	self should: [Machine copy: 9 from: a at: 0 to: b at: 0] raise: Error.
	self should: [Machine copy: 1 from: a at: 0 to: #[1 2] at: 0] raise: Error]
		ensure: [Machine free: a]
!
testNoFirmwareOnAHost
	Machine hasFirmware ifTrue: [^self].
	self assert: Machine systemTable isNil.
	self should: [Machine call: 4096] raise: Error.
	self assert: Firmware current isNil.
	self assert: InputQueue current isNil
! !
