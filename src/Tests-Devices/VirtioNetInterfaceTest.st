TestCase subclass: #VirtioNetInterfaceTest
	instanceVariableNames: 'memory notify rx tx nic rxAvail txAvail'
	classVariableNames: ''
	package: 'Tests-Devices'!

VirtioNetInterfaceTest comment: 'A VirtioNetInterface over a virtio network device in memory (Machine allocate:): its receive and transmit Virtqueues of 8 buffers laid out as the driver lays them out, the test playing the device: it takes the buffers the driver made available, writes a virtio_net_hdr and a frame into receive buffers, reads the transmit ones, and puts them on the used ring; the notifications go to a word of memory. The device''s addresses are the CPU''s plus 2^32, as behind an IOMMU.'!

!VirtioNetInterfaceTest methodsFor: 'running'!
setUp
	memory := Machine allocate: 8192 + (2048 * 16).
	notify := Machine allocate: 8.
	rx := Virtqueue ring: memory device: memory + 16r100000000 size: 8 bufferSize: 2048 buffersAt: 8192.
	rx start.
	rx notifyAt: notify queue: 0.
	tx := Virtqueue ring: memory + 4096 device: memory + 4096 + 16r100000000 size: 8 bufferSize: 2048 buffersAt: 4096 + (2048 * 8).
	tx startSending.
	tx notifyAt: notify + 2 queue: 1.
	rxAvail := txAvail := 0.
	nic := VirtioNetInterface rx: rx tx: tx mac: #[2 0 0 0 0 1]
!
tearDown
	nic forget.
	Machine free: memory.
	Machine free: notify
! !

!VirtioNetInterfaceTest methodsFor: 'device'!
frame: n byte: b
	^(ByteArray new: n) atAllPut: b; yourself
!
use: id length: n ring: ring
	| used |
	used := Machine uint16At: ring + 2048 + 2.
	Machine uint32At: ring + 2048 + 4 + (8 * (used \\ 8)) put: id.
	Machine uint32At: ring + 2048 + 8 + (8 * (used \\ 8)) put: n.
	Machine uint16At: ring + 2048 + 2 put: (used + 1 bitAnd: 16rFFFF)
!
deviceReceives: aFrame
	"Into the next buffer the driver made available, after a header: answer whether there was one."
	| id d |
	rxAvail = (Machine uint16At: memory + 1024 + 2) ifTrue: [^false].
	id := Machine uint16At: memory + 1024 + 4 + (2 * (rxAvail \\ 8)).
	rxAvail := rxAvail + 1 bitAnd: 16rFFFF.
	d := memory + (16 * id).
	self assert: (Machine uint16At: d + 12) equals: 2.
	self assert: (Machine uint32At: d + 8) equals: 2048.
	Machine bytesAt: (Machine uint64At: d) - 16r100000000 put: (ByteArray new: 12) , aFrame.
	self use: id length: aFrame size + 12 ring: memory.
	^true
!
deviceSends
	"The frames of the buffers the driver made available, each after a header of zeros; then they are used."
	| ring frames id d bytes |
	ring := memory + 4096.
	frames := OrderedCollection new.
	[txAvail ~= (Machine uint16At: ring + 1024 + 2)] whileTrue: [
		id := Machine uint16At: ring + 1024 + 4 + (2 * (txAvail \\ 8)).
		txAvail := txAvail + 1 bitAnd: 16rFFFF.
		d := ring + (16 * id).
		self assert: (Machine uint16At: d + 12) equals: 0.
		bytes := Machine bytesAt: (Machine uint64At: d) - 16r100000000 count: (Machine uint32At: d + 8).
		self assert: (bytes first: 12) equals: (ByteArray new: 12).
		frames add: (bytes allButFirst: 12).
		self use: id length: 0 ring: ring].
	^frames asArray
!
received
	| buffer frames n |
	buffer := ByteArray new: 1536.
	frames := OrderedCollection new.
	[(n := nic receiveInto: buffer) notNil] whileTrue: [frames add: (buffer copyFrom: 1 to: n)].
	^frames asArray
! !

!VirtioNetInterfaceTest methodsFor: 'tests'!
testReceivingWrapsAround
	"Frames come in order without their header; each buffer is available again once taken, round the ring many times."
	| k |
	k := 0.
	1 to: 60 do: [:round |
		1 to: round \\ 8 + 1 do: [:i |
			k := k + 1.
			self assert: (self deviceReceives: (self frame: k \\ 1450 + 60 byte: k \\ 256))].
		self assert: nic hasFrame.
		self assert: nic waiting equals: round \\ 8 + 1.
		self assert: self received equals: ((k - (round \\ 8) to: k) collect: [:j | self frame: j \\ 1450 + 60 byte: j \\ 256]) asArray].
	self deny: nic hasFrame.
	self assert: nic status equals: {k. 0. 0. 0}
!
testTheDeviceStopsWhenEveryBufferIsUsed
	1 to: 8 do: [:i | self assert: (self deviceReceives: (self frame: 64 byte: i))].
	self deny: (self deviceReceives: (self frame: 64 byte: 0)).
	self assert: (nic receiveInto: (ByteArray new: 1536)) equals: 64.
	self assert: (self deviceReceives: (self frame: 64 byte: 9)).
	self assert: self received equals: ((2 to: 9) collect: [:i | self frame: 64 byte: i]) asArray
!
testARuntIsSkippedAndAFrameIsCutToTheBuffer
	| id buffer |
	id := Machine uint16At: memory + 1024 + 4.
	rxAvail := 1.
	self use: id length: 12 ring: memory.
	self deviceReceives: (self frame: 100 byte: 5).
	buffer := ByteArray new: 30.
	self assert: (nic receiveInto: buffer) equals: 30.
	self assert: buffer equals: (self frame: 30 byte: 5).
	self assert: (nic receiveInto: buffer) isNil
!
testTheDeviceIsNotifiedUnlessItSaysNot
	"After receive buffers are given back and frames are made available to send (VIRTQ_USED_F_NO_NOTIFY off)."
	Machine uint16At: notify put: 16rFFFF.
	Machine uint16At: notify + 2 put: 16rFFFF.
	Machine uint16At: memory + 2048 put: 1.
	Machine uint16At: memory + 4096 + 2048 put: 1.
	self deviceReceives: (self frame: 60 byte: 1).
	self assert: self received size equals: 1.
	self assert: (nic send: (self frame: 60 byte: 2) count: 60).
	self assert: (Machine uint16At: notify) equals: 16rFFFF.
	self assert: (Machine uint16At: notify + 2) equals: 16rFFFF.
	Machine uint16At: memory + 2048 put: 0.
	Machine uint16At: memory + 4096 + 2048 put: 0.
	self deviceReceives: (self frame: 60 byte: 1).
	self assert: self received size equals: 1.
	self assert: (nic send: (self frame: 60 byte: 2) count: 60).
	self assert: (Machine uint16At: notify) equals: 0.
	self assert: (Machine uint16At: notify + 2) equals: 1
!
testSendingAndReclaimingWrapAround
	"Each frame after a header of zeros, in order; with every buffer the device's a frame is refused, until the device used some."
	| expected |
	1 to: 8 do: [:i | self assert: (nic send: (self frame: 100 byte: i) count: 40 + i)].
	self deny: (nic send: (self frame: 100 byte: 0) count: 60).
	self assert: self deviceSends equals: ((1 to: 8) collect: [:i | self frame: 40 + i byte: i]) asArray.
	1 to: 200 do: [:k |
		expected := (1 to: k \\ 8 + 1) collect: [:i | self frame: k * i \\ 1454 + 60 byte: k + i].
		expected do: [:f | self assert: (nic send: f , #[1 2 3] count: f size)].
		self assert: self deviceSends equals: expected asArray].
	self deny: (nic send: (ByteArray new: 1515) count: 1515).
	self assert: nic status equals: {0. 8 + ((1 to: 200) inject: 0 into: [:a :k | a + (k \\ 8) + 1]). 2. 0}
!
testAFrameWakesTheStackWhileFramesComeAndGo
	| semaphore |
	semaphore := Semaphore new.
	nic semaphore: semaphore.
	self assert: (nic send: (self frame: 60 byte: 1) count: 60).
	self deviceReceives: (self frame: 60 byte: 2).
	self deny: (semaphore waitTimeoutMSecs: 2000).
	self assert: self received equals: {self frame: 60 byte: 2}
! !
