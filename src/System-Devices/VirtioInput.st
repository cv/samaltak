Object subclass: #VirtioInput
	instanceVariableNames: 'firmware display pci scratch commonBar commonOffset notifyBar notifyOffset deviceBar deviceOffset queue absMaxX absMaxY absX absY relX relY buttons wheel process'
	classVariableNames: ''
	package: 'System-Devices'!

VirtioInput comment: 'I am a virtio input device (QEMU''s virtio-tablet or virtio-mouse; virtio 1.x over PCI) driven through the firmware''s PCI I/O protocol (UEFI 2.10, 14.4), for machines whose firmware has no pointer driver (OVMF has none). One event queue (a Virtqueue of 8-byte buffers in a page of the device''s DMA memory), polled by my Process every 10 ms: the events (Linux evdev: absolute X and Y, relative X, Y and wheel, buttons) become the pointer''s state, reported to my display.'!

!VirtioInput methodsFor: 'PCI'!
setFirmware: aFirmware display: aDisplay
	firmware := aFirmware.
	display := aDisplay.
	absX := absY := -1.
	relX := relY := buttons := wheel := 0
!
pci: offset with: a with: b with: c
	"Call the PCI I/O function at offset in the protocol."
	^Machine call: (firmware function: pci at: offset) with: pci with: a with: b with: c
!
pci: offset with: a with: b with: c with: d with: e
	^Machine call: (firmware function: pci at: offset) with: pci with: a with: b with: c with: d with: e
!
widthCode: w
	^w = 1 ifTrue: [0] ifFalse: [w = 2 ifTrue: [1] ifFalse: [2]]
!
config: offset width: w
	"PCI configuration space, w bytes (1, 2, 4)."
	Machine uint32At: scratch put: 0.
	Machine call: (firmware function: pci at: 48) with: pci with: (self widthCode: w) with: offset with: 1 with: scratch.
	^Machine read: scratch size: w
!
read: bar offset: offset width: w
	Machine uint32At: scratch put: 0.
	self pci: 16 with: (self widthCode: w) with: bar with: offset with: 1 with: scratch.
	^Machine read: scratch size: w
!
write: bar offset: offset width: w value: v
	Machine uint32At: scratch put: v.
	self pci: 24 with: (self widthCode: w) with: bar with: offset with: 1 with: scratch
!
common: offset width: w
	^self read: commonBar offset: commonOffset + offset width: w
!
common: offset width: w put: v
	self write: commonBar offset: commonOffset + offset width: w value: v
! !

!VirtioInput methodsFor: 'starting'!
start
	"Find a virtio input device (vendor 1AF4, device 1052) and start it; answer whether there is one."
	| guid |
	guid := '4cf5b200-68b8-4ca5-9eec-b23e3f50029a'.
	scratch := Machine allocate: 32.
	pci := (firmware handlesSupporting: guid)
		inject: nil
		into: [:found :h | found ifNil: [
			(firmware protocol: guid on: h) ifNotNil: [:p |
				pci := p.
				((self config: 0 width: 2) = 16r1AF4 and: [(self config: 2 width: 2) = 16r1052]) ifTrue: [p] ifFalse: [nil]]]].
	(pci notNil and: [self findCapabilities and: [self startDevice]]) ifTrue: [
		process := [[(Delay forMilliseconds: 10) wait. self poll] repeat] forkAt: Processor highIOPriority + 5 named: 'virtio input'.
		^true].
	pci := nil.
	Machine free: scratch.
	^false
!
findCapabilities
	"The common, notify and device configuration structures (virtio 1.2, 4.1.4)."
	| cap type bar offset found |
	found := 0.
	cap := self config: 16r34 width: 1.
	[cap ~= 0] whileTrue: [
		(self config: cap width: 1) = 9 ifTrue: [
			type := self config: cap + 3 width: 1.
			bar := self config: cap + 4 width: 1.
			offset := self config: cap + 8 width: 4.
			type = 1 ifTrue: [commonBar := bar. commonOffset := offset. found := found bitOr: 1].
			type = 2 ifTrue: [notifyBar := bar. notifyOffset := offset. found := found bitOr: 2].
			type = 4 ifTrue: [deviceBar := bar. deviceOffset := offset. found := found bitOr: 4]].
		cap := self config: cap + 1 width: 1].
	^found = 7
!
notifyCapability
	"The configuration offset of the notify capability."
	| cap |
	cap := self config: 16r34 width: 1.
	[cap ~= 0] whileTrue: [
		((self config: cap width: 1) = 9 and: [(self config: cap + 3 width: 1) = 2]) ifTrue: [^cap].
		cap := self config: cap + 1 width: 1].
	^0
!
startDevice
	"Reset, negotiate VIRTIO_F_VERSION_1, set up queue 0 with every buffer available, DRIVER_OK."
	| size host device |
	self pci: 120 with: 4 with: 0 with: scratch.
	self pci: 120 with: 2 with: ((Machine uint64At: scratch) bitAnd: 16r0600) with: 0.
	self common: 20 width: 1 put: 0.
	self common: 20 width: 1 put: 3.
	self common: 8 width: 4 put: 1.
	self common: 12 width: 4 put: 1.
	self common: 8 width: 4 put: 0.
	self common: 12 width: 4 put: 0.
	self common: 20 width: 1 put: 11.
	((self common: 20 width: 1) bitAnd: 8) = 0 ifTrue: [^false].
	self common: 22 width: 2 put: 0.
	size := (self common: 24 width: 2) min: 64.
	size = 0 ifTrue: [^false].
	self common: 24 width: 2 put: size.
	(firmware isError: (self pci: 88 with: 0 with: 4 with: 1 with: scratch with: 0)) ifTrue: [^false].
	host := Machine uint64At: scratch.
	Machine bytesAt: host put: (ByteArray new: 4096).
	Machine uint64At: scratch put: 4096.
	(firmware isError: (self pci: 72 with: 2 with: host with: scratch with: scratch + 8 with: scratch + 16)) ifTrue: [^false].
	device := Machine uint64At: scratch + 8.
	queue := Virtqueue ring: host device: device size: size bufferSize: 8.
	queue start.
	self common: 32 width: 4 put: (queue descriptorArea bitAnd: 16rFFFFFFFF).
	self common: 36 width: 4 put: queue descriptorArea >> 32.
	self common: 40 width: 4 put: (queue driverArea bitAnd: 16rFFFFFFFF).
	self common: 44 width: 4 put: queue driverArea >> 32.
	self common: 48 width: 4 put: (queue deviceArea bitAnd: 16rFFFFFFFF).
	self common: 52 width: 4 put: queue deviceArea >> 32.
	self common: 28 width: 2 put: 1.
	notifyOffset := notifyOffset + ((self common: 30 width: 2) * (self config: self notifyCapability + 16 width: 4)).
	self common: 20 width: 1 put: 15.
	absMaxX := self absMaximum: 0.
	absMaxY := self absMaximum: 1.
	self notify.
	^true
!
absMaximum: axis
	"VIRTIO_INPUT_CFG_ABS_INFO of axis: its max; 0 if none."
	self write: deviceBar offset: deviceOffset width: 1 value: 16r12.
	self write: deviceBar offset: deviceOffset + 1 width: 1 value: axis.
	(self read: deviceBar offset: deviceOffset + 2 width: 1) < 8 ifTrue: [^0].
	^self read: deviceBar offset: deviceOffset + 12 width: 4
!
notify
	Machine barrier.
	self write: notifyBar offset: notifyOffset width: 2 value: 0
!
stop
	self abandon.
	scratch isNil ifFalse: [Machine free: scratch].
	scratch := nil
!
abandon
	"Stop without the device (the previous VM's)."
	process isNil ifFalse: [process terminate].
	process := nil
! !

!VirtioInput methodsFor: 'polling'!
poll
	"Take the events the device wrote, give their buffers back, report the pointer if any came."
	| extent p |
	(queue takeUsed: [:event |
		self event: (Machine uint16At: event) code: (Machine uint16At: event + 2) value: (Machine int32At: event + 4)])
			ifFalse: [^self].
	self notify.
	extent := display extent.
	p := display pointerPosition.
	(absX >= 0 and: [absMaxX > 0]) ifTrue: [p := (absX / (absMaxX + 1) * extent x) asFloat @ p y].
	(absY >= 0 and: [absMaxY > 0]) ifTrue: [p := p x @ (absY / (absMaxY + 1) * extent y) asFloat].
	display pointerAt: p + (relX @ relY) buttons: buttons wheel: wheel.
	relX := relY := wheel := 0
!
event: type code: code value: value
	"Linux evdev: EV_KEY 1 (BTN_LEFT 110, RIGHT 111, MIDDLE 112 hex), EV_REL 2 (X 0, Y 1, WHEEL 8), EV_ABS 3 (X 0, Y 1)."
	| mask |
	type = 1 ifTrue: [
		mask := code = 16r110 ifTrue: [1] ifFalse: [code = 16r111 ifTrue: [4] ifFalse: [code = 16r112 ifTrue: [2] ifFalse: [0]]].
		buttons := value ~= 0 ifTrue: [buttons bitOr: mask] ifFalse: [buttons bitClear: mask]].
	type = 2 ifTrue: [
		code = 0 ifTrue: [relX := relX + value].
		code = 1 ifTrue: [relY := relY + value].
		code = 8 ifTrue: [wheel := wheel + value]].
	type = 3 ifTrue: [
		code = 0 ifTrue: [absX := value].
		code = 1 ifTrue: [absY := value]]
! !

!VirtioInput class methodsFor: 'instance creation'!
firmware: aFirmware display: aDisplay
	^self new setFirmware: aFirmware display: aDisplay
! !
