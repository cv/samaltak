Object subclass: #VirtioPci
	instanceVariableNames: 'pci common notify multiplier config'
	classVariableNames: ''
	package: 'System-Devices'!

VirtioPci comment: 'I am the virtio 1.x PCI transport (virtio 1.2, 4.1) of a PciDevice: its common, notify and device configuration structures (found by their capabilities; addresses in its memory BARs, read and written directly), the device''s initialization (reset, feature negotiation, DRIVER_OK) and its virtqueues (Virtqueue, in DMA memory of the device''s).'!

!VirtioPci class methodsFor: 'instance creation'!
on: aPciDevice
	"The transport of aPciDevice, or nil if it has not the capabilities of a virtio 1.x device."
	^self new setPci: aPciDevice
! !

!VirtioPci methodsFor: 'initialization'!
setPci: aPciDevice
	pci := aPciDevice.
	pci capabilitiesDo: [:cap :id | | type at |
		id = 9 ifTrue: [
			type := pci config: cap + 3 width: 1.
			(pci barAddress: (pci config: cap + 4 width: 1)) ifNotNil: [:bar |
				at := bar + (pci config: cap + 8 width: 4).
				type = 1 ifTrue: [common := at].
				type = 2 ifTrue: [
					notify := at.
					multiplier := pci config: cap + 16 width: 4].
				type = 4 ifTrue: [config := at]]]].
	(common isNil or: [notify isNil or: [config isNil]]) ifTrue: [^nil]
! !

!VirtioPci methodsFor: 'accessing'!
pci
	^pci
!
common: offset width: w
	^Machine read: common + offset size: w
!
common: offset width: w put: v
	Machine write: common + offset size: w value: v
!
common: offset put64: v
	"A 64-bit field, as two 32-bit halves."
	self common: offset width: 4 put: (v bitAnd: 16rFFFFFFFF).
	self common: offset + 4 width: 4 put: (v bitShift: -32)
!
config: offset width: w
	"The device-specific configuration."
	^Machine read: config + offset size: w
!
config: offset width: w put: v
	Machine write: config + offset size: w value: v
!
status
	^self common: 20 width: 1
! !

!VirtioPci methodsFor: 'initializing the device'!
reset
	"Reset the device (it lets go of its queues). Answer whether it did."
	self common: 20 width: 1 put: 0.
	1000 timesRepeat: [self status = 0 ifTrue: [^true]].
	^false
!
negotiate: features
	"After reset: acknowledge the device, accept those of features (a bit mask: VIRTIO_F_VERSION_1 is bit 32) it offers. Answer them, nil if it does not accept them or does not offer VIRTIO_F_VERSION_1."
	| offered accepted |
	self common: 20 width: 1 put: 1.
	self common: 20 width: 1 put: 3.
	self common: 0 width: 4 put: 0.
	offered := self common: 4 width: 4.
	self common: 0 width: 4 put: 1.
	offered := offered + ((self common: 4 width: 4) bitShift: 32).
	accepted := offered bitAnd: features.
	(accepted bitAnd: (1 bitShift: 32)) = 0 ifTrue: [^nil].
	self common: 8 width: 4 put: 0.
	self common: 12 width: 4 put: (accepted bitAnd: 16rFFFFFFFF).
	self common: 8 width: 4 put: 1.
	self common: 12 width: 4 put: (accepted bitShift: -32).
	self common: 20 width: 1 put: 11.
	(self status bitAnd: 8) = 0 ifTrue: [^nil].
	^accepted
!
queue: index size: n bufferSize: bytes at: hostAddress buffersAt: offset receiving: aBoolean
	"Set up queue index (at most n buffers) in the DMA memory at hostAddress (allocated by my PciDevice): the ring's page there, the buffers from offset on; the device writes into them if aBoolean, else reads them. Answer the Virtqueue, nil if the device has no such queue."
	| size q |
	self common: 22 width: 2 put: index.
	size := (self common: 24 width: 2) min: n.
	size = 0 ifTrue: [^nil].
	self common: 24 width: 2 put: size.
	q := Virtqueue ring: hostAddress device: (pci deviceAddress: hostAddress) size: size bufferSize: bytes buffersAt: offset.
	aBoolean ifTrue: [q start] ifFalse: [q startSending].
	self common: 32 put64: q descriptorArea.
	self common: 40 put64: q driverArea.
	self common: 48 put64: q deviceArea.
	self common: 26 width: 2 put: 16rFFFF.
	q notifyAt: notify + ((self common: 30 width: 2) * multiplier) queue: index.
	self common: 28 width: 2 put: 1.
	^q
!
driverOk
	"The device may use its queues. Answer whether it is not in trouble (DEVICE_NEEDS_RESET, FAILED)."
	self common: 20 width: 1 put: 15.
	^(self status bitAnd: 16rC0) = 0
! !
