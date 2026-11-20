Object subclass: #VirtioInput
	instanceVariableNames: 'firmware display device queue absMaxX absMaxY absX absY relX relY buttons wheel process'
	classVariableNames: ''
	package: 'System-Devices'!

VirtioInput comment: 'I am a virtio input device (QEMU''s virtio-tablet or virtio-mouse; virtio 1.x over PCI, VirtioPci), for machines whose firmware has no pointer driver (OVMF has none). One event queue (a Virtqueue of 8-byte buffers in a page of the device''s DMA memory), polled by my Process every 10 ms: the events (Linux evdev: absolute X and Y, relative X, Y and wheel, buttons) become the pointer''s state, reported to my display.'!

!VirtioInput methodsFor: 'initialization'!
setFirmware: aFirmware display: aDisplay
	firmware := aFirmware.
	display := aDisplay.
	absX := absY := -1.
	relX := relY := buttons := wheel := 0
! !

!VirtioInput methodsFor: 'starting'!
start
	"Find a virtio input device (vendor 1AF4, device 1052) and start it; answer whether there is one."
	| pci |
	pci := PciDevice in: firmware detect: [:d | d vendor = 16r1AF4 and: [d deviceId = 16r1052]].
	pci isNil ifTrue: [^false].
	device := VirtioPci on: pci.
	(device notNil and: [self startDevice]) ifTrue: [
		process := [[(Delay forMilliseconds: 10) wait. self poll] repeat] forkAt: Processor highIOPriority + 5 named: 'virtio input'.
		^true].
	device isNil ifFalse: [device reset].
	pci release.
	device := nil.
	^false
!
startDevice
	"Reset, negotiate VIRTIO_F_VERSION_1, set up queue 0 with every buffer available, DRIVER_OK."
	| ring |
	(device pci enable and: [device reset]) ifFalse: [^false].
	(device negotiate: 1 << 32) isNil ifTrue: [^false].
	ring := device pci allocate: 4096.
	ring isNil ifTrue: [^false].
	queue := device queue: 0 size: 64 bufferSize: 8 at: ring buffersAt: 3072 receiving: true.
	(queue notNil and: [device driverOk]) ifFalse: [^false].
	absMaxX := self absMaximum: 0.
	absMaxY := self absMaximum: 1.
	queue kick.
	^true
!
absMaximum: axis
	"VIRTIO_INPUT_CFG_ABS_INFO of axis: its max; 0 if none."
	device config: 0 width: 1 put: 16r12.
	device config: 1 width: 1 put: axis.
	(device config: 2 width: 1) < 8 ifTrue: [^0].
	^device config: 12 width: 4
!
stop
	self abandon.
	device isNil ifFalse: [
		device reset.
		device pci release].
	device := nil
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
	queue kick.
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
