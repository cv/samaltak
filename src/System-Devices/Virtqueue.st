Object subclass: #Virtqueue
	instanceVariableNames: 'ring device size bufferSize buffers lastUsed free notify index'
	classVariableNames: ''
	package: 'System-Devices'!

Virtqueue comment: 'I am a split virtqueue (virtio 1.2, 2.7) of size buffers of bufferSize bytes, descriptor i always buffer i: the descriptors at 0, the available ring at 1024 and the used ring at 2048 of a page (size at most 64), the buffers from buffersAt: on (3072: in the page). ring is the page''s address for the CPU, device the one the device uses (they differ behind an IOMMU). Either the device writes into my buffers (start: an input device''s events, frames received; all available at first; takeNext: and takeUsed: hand each one the device used to a block, then make it available again), or it reads them (startSending: frames to send; send:with: fills a free one and makes it available, reclaim takes back those it read). The device is never asked to interrupt; kick notifies it (at notifyAt:queue:) unless it said it needs no notification.'!

!Virtqueue methodsFor: 'initialization'!
setRing: hostAddress device: deviceAddress size: n bufferSize: bytes buffersAt: offset
	ring := hostAddress.
	device := deviceAddress.
	size := n.
	bufferSize := bytes.
	buffers := offset.
	lastUsed := 0
!
notifyAt: anAddress queue: anIndex
	"Where kick writes anIndex."
	notify := anAddress.
	index := anIndex
!
describe: i flags: flags
	Machine uint64At: ring + (16 * i) put: device + buffers + (bufferSize * i).
	Machine uint32At: ring + (16 * i) + 8 put: bufferSize.
	Machine uint16At: ring + (16 * i) + 12 put: flags
!
start
	"Every buffer a device-writable descriptor (VIRTQ_DESC_F_WRITE), all available; no interrupts (VIRTQ_AVAIL_F_NO_INTERRUPT)."
	0 to: size - 1 do: [:i |
		self describe: i flags: 2.
		Machine uint16At: ring + 1024 + 4 + (2 * i) put: i].
	Machine uint16At: ring + 1024 put: 1.
	Machine barrier.
	Machine uint16At: ring + 1024 + 2 put: size
!
startSending
	"Every buffer a device-readable descriptor, none available yet; no interrupts."
	0 to: size - 1 do: [:i | self describe: i flags: 0].
	Machine uint16At: ring + 1024 put: 1.
	Machine uint16At: ring + 1024 + 2 put: 0.
	free := (0 to: size - 1) asOrderedCollection
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
!
buffer: id
	^ring + buffers + (bufferSize * id)
!
waiting
	"How many buffers the device used that I have not taken."
	^(Machine uint16At: ring + 2048 + 2) - lastUsed bitAnd: 16rFFFF
!
hasUsed
	^(Machine uint16At: ring + 2048 + 2) ~= lastUsed
! !

!Virtqueue methodsFor: 'using'!
makeAvailable: id
	| avail |
	avail := Machine uint16At: ring + 1024 + 2.
	Machine uint16At: ring + 1024 + 4 + (2 * (avail \\ size)) put: id.
	Machine barrier.
	Machine uint16At: ring + 1024 + 2 put: (avail + 1 bitAnd: 16rFFFF)
!
takeNext: aBlock
	"If the device used a buffer I have not taken: aBlock value: its address value: the length it wrote; the buffer is available again afterwards. Answer whether there was one."
	| e id |
	(Machine uint16At: ring + 2048 + 2) = lastUsed ifTrue: [^false].
	Machine barrier.
	e := ring + 2048 + 4 + (8 * (lastUsed \\ size)).
	id := Machine uint32At: e.
	aBlock value: (self buffer: id) value: (Machine uint32At: e + 4).
	self makeAvailable: id.
	lastUsed := lastUsed + 1 bitAnd: 16rFFFF.
	^true
!
takeUsed: aBlock
	"aBlock value: the address of each buffer the device used since the last time, in order; each is available again afterwards. Answer whether there were any."
	| any |
	any := false.
	[self takeNext: [:buffer :n | aBlock value: buffer]] whileTrue: [any := true].
	^any
!
send: count with: aBlock
	"aBlock value: the address of a free buffer, which it fills; its first count bytes go to the device. Answer false if the device still has every buffer."
	| id |
	free isEmpty ifTrue: [self reclaim].
	free isEmpty ifTrue: [^false].
	id := free removeLast.
	aBlock value: (self buffer: id).
	Machine uint32At: ring + (16 * id) + 8 put: count.
	self makeAvailable: id.
	^true
!
reclaim
	"Take back the buffers the device has read."
	| used |
	used := Machine uint16At: ring + 2048 + 2.
	used = lastUsed ifTrue: [^self].
	Machine barrier.
	[lastUsed ~= used] whileTrue: [
		free addLast: (Machine uint32At: ring + 2048 + 4 + (8 * (lastUsed \\ size))).
		lastUsed := lastUsed + 1 bitAnd: 16rFFFF]
!
kick
	"Tell the device about the buffers made available, unless it said it needs no notification (VIRTQ_USED_F_NO_NOTIFY)."
	Machine barrier.
	((Machine uint16At: ring + 2048) bitAnd: 1) = 0 ifTrue: [Machine uint16At: notify put: index]
! !

!Virtqueue class methodsFor: 'instance creation'!
ring: hostAddress device: deviceAddress size: n bufferSize: bytes
	^self ring: hostAddress device: deviceAddress size: n bufferSize: bytes buffersAt: 3072
!
ring: hostAddress device: deviceAddress size: n bufferSize: bytes buffersAt: offset
	"The buffers at offset from hostAddress (and deviceAddress)."
	^self new setRing: hostAddress device: deviceAddress size: n bufferSize: bytes buffersAt: offset
! !
