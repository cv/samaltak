Object subclass: #Virtqueue
	instanceVariableNames: 'ring device size bufferSize lastUsed'
	classVariableNames: ''
	package: 'System-Devices'!

Virtqueue comment: 'I am a split virtqueue (virtio 1.2, 2.7) whose buffers the device writes into (an input device''s events), all in one page of memory: size descriptors at 0, the available ring at 1024, the used ring at 2048, size buffers of bufferSize bytes at 3072 (size at most 64). ring is the page''s address for the CPU, device the one the device uses (they differ behind an IOMMU). Every buffer starts out available; takeUsed: hands each one the device used to a block, then makes it available again.'!

!Virtqueue methodsFor: 'initialization'!
setRing: hostAddress device: deviceAddress size: n bufferSize: bytes
	ring := hostAddress.
	device := deviceAddress.
	size := n.
	bufferSize := bytes.
	lastUsed := 0
!
start
	"Every buffer a device-writable descriptor (VIRTQ_DESC_F_WRITE), all available."
	0 to: size - 1 do: [:i |
		Machine uint64At: ring + (16 * i) put: device + 3072 + (bufferSize * i).
		Machine uint32At: ring + (16 * i) + 8 put: bufferSize.
		Machine uint16At: ring + (16 * i) + 12 put: 2.
		Machine uint16At: ring + 1024 + 4 + (2 * i) put: i].
	Machine barrier.
	Machine uint16At: ring + 1024 + 2 put: size
! !

!Virtqueue methodsFor: 'accessing'!
size
	^size
!
descriptorArea
	"The addresses the device is told (queue_desc, queue_driver, queue_device)."
	^device
!
driverArea
	^device + 1024
!
deviceArea
	^device + 2048
! !

!Virtqueue methodsFor: 'using'!
takeUsed: aBlock
	"aBlock value: the address of each buffer the device used since the last time, in order; each is available again afterwards. Answer whether there were any."
	| used id avail any |
	Machine barrier.
	used := Machine uint16At: ring + 2048 + 2.
	any := false.
	[lastUsed ~= used] whileTrue: [
		id := Machine uint32At: ring + 2048 + 4 + (8 * (lastUsed \\ size)).
		aBlock value: ring + 3072 + (bufferSize * id).
		avail := Machine uint16At: ring + 1024 + 2.
		Machine uint16At: ring + 1024 + 4 + (2 * (avail \\ size)) put: id.
		Machine barrier.
		Machine uint16At: ring + 1024 + 2 put: (avail + 1 bitAnd: 16rFFFF).
		lastUsed := lastUsed + 1 bitAnd: 16rFFFF.
		any := true].
	^any
! !

!Virtqueue class methodsFor: 'instance creation'!
ring: hostAddress device: deviceAddress size: n bufferSize: bytes
	^self new setRing: hostAddress device: deviceAddress size: n bufferSize: bytes
! !
