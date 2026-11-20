PciNetworkInterface subclass: #VirtioNetInterface
	instanceVariableNames: 'virtio rx tx'
	classVariableNames: ''
	package: 'System-Devices'!

VirtioNetInterface comment: 'I drive a virtio network device (virtio 1.2, 5.1: QEMU''s virtio-net-pci, make uefi-run''s NIC on arm64) over VirtioPci, polled. Features VIRTIO_F_VERSION_1 and VIRTIO_NET_F_MAC only: no offloads, no merged receive buffers, so a buffer holds a whole frame after its virtio_net_hdr (12 bytes; all zero going out). The receive queue (0) and the transmit queue (1) are Virtqueues of 2 KB buffers in one block of DMA memory: their pages, then the receive buffers, then the transmit ones.'!

!VirtioNetInterface class methodsFor: 'driving'!
supports: aPciDevice
	"Vendor 1AF4: device 1041, or the transitional 1000 with subsystem 1 (network)."
	^aPciDevice vendor = 16r1AF4 and: [aPciDevice deviceId = 16r1041 or: [aPciDevice deviceId = 16r1000 and: [aPciDevice subsystemId = 1]]]
!
queueSize
	^64
!
memorySize
	^8192 + (2048 * 2 * self queueSize)
!
rx: aVirtqueue tx: anotherVirtqueue mac: aByteArray
	"A driver of the device behind the two queues, started (tests: a device in memory)."
	^self new setRx: aVirtqueue tx: anotherVirtqueue mac: aByteArray
! !

!VirtioNetInterface methodsFor: 'initialization'!
setRx: aVirtqueue tx: anotherVirtqueue mac: aByteArray
	rx := aVirtqueue.
	tx := anotherVirtqueue.
	mac := aByteArray
! !

!VirtioNetInterface methodsFor: 'controller'!
startDevice
	"Reset, negotiate VIRTIO_F_VERSION_1 and VIRTIO_NET_F_MAC, the queues (every receive buffer available), the MAC address from the device's configuration, DRIVER_OK."
	| memory n |
	virtio := VirtioPci on: pci.
	(virtio notNil and: [virtio reset]) ifFalse: [^false].
	(virtio negotiate: (1 << 32) + (1 << 5)) = ((1 << 32) + (1 << 5)) ifFalse: [^false].
	n := self class queueSize.
	memory := pci allocate: self class memorySize.
	memory isNil ifTrue: [^false].
	rx := virtio queue: 0 size: n bufferSize: 2048 at: memory buffersAt: 8192 receiving: true.
	tx := virtio queue: 1 size: n bufferSize: 2048 at: memory + 4096 buffersAt: 4096 + (2048 * n) receiving: false.
	(rx notNil and: [tx notNil]) ifFalse: [^false].
	mac := ByteArray new: 6.
	1 to: 6 do: [:i | mac at: i put: (virtio config: i - 1 width: 1)].
	virtio driverOk ifFalse: [^false].
	rx kick.
	^true
!
stopDevice
	virtio isNil ifFalse: [virtio reset]
! !

!VirtioNetInterface methodsFor: 'frames'!
hasFrame
	^rx hasUsed
!
waiting
	^rx waiting
!
receiveFrame: aByteArray
	"The frame after the header in the next buffer the device used; the buffer is the device's again."
	| n |
	[n := nil.
	 (rx takeNext: [:buffer :length |
		length > 12 ifTrue: [
			n := length - 12 min: aByteArray size.
			Machine copy: n from: buffer at: 12 to: aByteArray at: 0]]) ifFalse: [^nil].
	 rx kick.
	 n isNil] whileTrue.
	^n
!
transmit: aFrame count: n
	"After a header of zeros (none of the buffers' first 12 bytes is ever written). False if the device still has every buffer."
	(tx send: n + 12 with: [:buffer | Machine copy: n from: aFrame at: 0 to: buffer at: 12]) ifFalse: [^false].
	tx kick.
	^true
! !
