TestCase subclass: #VirtqueueTest
	instanceVariableNames: 'page queue'
	classVariableNames: ''
	package: 'Tests-Devices'!

VirtqueueTest comment: 'A Virtqueue in a page of memory (Machine allocate:), the test playing the device: it reads the descriptors and the available ring the driver set up, writes events into buffers and puts them on the used ring; the driver takes them in order and makes the buffers available again. And one the device reads (sending): the driver fills free buffers and makes them available, the device puts them on the used ring, the driver takes them back. On a host, which has no device, as on UEFI.'!

!VirtqueueTest methodsFor: 'running'!
setUp
	page := Machine allocate: 4096.
	queue := Virtqueue ring: page device: page + 16r100000000 size: 8 bufferSize: 8.
	queue start
!
tearDown
	Machine free: page
! !

!VirtqueueTest methodsFor: 'device'!
availableIndex
	^Machine uint16At: page + 1024 + 2
!
deviceUses: aBufferIndex event: type code: code value: value
	"What the device does: write an evdev event into a buffer it was given and put it on the used ring."
	| addr used |
	addr := (Machine uint64At: page + (16 * aBufferIndex)) - 16r100000000.
	Machine uint16At: addr put: type.
	Machine uint16At: addr + 2 put: code.
	Machine uint32At: addr + 4 put: (value bitAnd: 16rFFFFFFFF).
	used := Machine uint16At: page + 2048 + 2.
	Machine uint32At: page + 2048 + 4 + (8 * (used \\ 8)) put: aBufferIndex.
	Machine uint32At: page + 2048 + 8 + (8 * (used \\ 8)) put: 8.
	Machine uint16At: page + 2048 + 2 put: (used + 1 bitAnd: 16rFFFF)
!
taken
	| events |
	events := OrderedCollection new.
	queue takeUsed: [:b | events add: {Machine uint16At: b. Machine uint16At: b + 2. Machine int32At: b + 4}].
	^events asArray
! !

!VirtqueueTest methodsFor: 'tests'!
testEveryBufferStartsAvailable
	"Device-writable descriptors of the buffers at the device's addresses, each on the available ring."
	self assert: self availableIndex equals: 8.
	0 to: 7 do: [:i |
		self assert: (Machine uint64At: page + (16 * i)) equals: page + 16r100000000 + 3072 + (8 * i).
		self assert: (Machine uint32At: page + (16 * i) + 8) equals: 8.
		self assert: (Machine uint16At: page + (16 * i) + 12) equals: 2.
		self assert: (Machine uint16At: page + 1024 + 4 + (2 * i)) equals: i].
	self assert: queue descriptorArea equals: page + 16r100000000.
	self assert: queue driverArea equals: page + 16r100000000 + 1024.
	self assert: queue deviceArea equals: page + 16r100000000 + 2048
!
testUsedBuffersAreTakenInOrderAndGivenBack
	self assert: self taken isEmpty.
	self deviceUses: 3 event: 3 code: 0 value: 1234.
	self deviceUses: 0 event: 1 code: 16r110 value: 1.
	self assert: self taken equals: #(#(3 0 1234) #(1 16r110 1)).
	self assert: self availableIndex equals: 10.
	self assert: (Machine uint16At: page + 1024 + 4) equals: 3.
	self assert: (Machine uint16At: page + 1024 + 6) equals: 0.
	self deviceUses: 5 event: 2 code: 8 value: -1.
	self assert: self taken equals: #(#(2 8 -1)).
	self assert: self taken isEmpty
!
testTheIndicesWrap
	"Used and available indices are 16 bits: they wrap."
	1 to: 70000 do: [:i |
		self deviceUses: i \\ 8 event: 2 code: 0 value: i.
		self assert: self taken equals: {{2. 0. i}}].
	self assert: self availableIndex equals: (8 + 70000 bitAnd: 16rFFFF)
!
testTakeNextGivesTheLength
	| got |
	self deviceUses: 6 event: 1 code: 2 value: 3.
	Machine uint32At: page + 2048 + 8 put: 5.
	self assert: (queue takeNext: [:b :n | got := {b. n}]).
	self assert: got equals: {page + 3072 + 48. 5}.
	self deny: (queue takeNext: [:b :n | self fail])
!
testSendingFillsFreeBuffersAndTakesBackThoseRead
	"The device reads the buffers made available (in order), puts them on the used ring; the driver reuses them, also after the 16-bit indices wrap."
	| out avail used sentFrames |
	out := Virtqueue ring: page device: page + 16r100000000 size: 8 bufferSize: 64 buffersAt: 3072.
	out startSending.
	self assert: (Machine uint16At: page + 1024 + 2) equals: 0.
	0 to: 7 do: [:i | self assert: (Machine uint16At: page + (16 * i) + 12) equals: 0].
	avail := used := 0.
	1 to: 8 do: [:i | self assert: (out send: i with: [:b | Machine uint8At: b put: i])].
	self deny: (out send: 1 with: [:b | self fail]).
	1 to: 70000 do: [:k |
		sentFrames := OrderedCollection new.
		[avail ~= (Machine uint16At: page + 1024 + 2)] whileTrue: [| id |
			id := Machine uint16At: page + 1024 + 4 + (2 * (avail \\ 8)).
			sentFrames add: {Machine uint32At: page + (16 * id) + 8. Machine uint8At: (Machine uint64At: page + (16 * id)) - 16r100000000}.
			Machine uint32At: page + 2048 + 4 + (8 * (used \\ 8)) put: id.
			used := used + 1 bitAnd: 16rFFFF.
			Machine uint16At: page + 2048 + 2 put: used.
			avail := avail + 1 bitAnd: 16rFFFF].
		k = 1
			ifTrue: [self assert: sentFrames asArray equals: ((1 to: 8) collect: [:i | {i. i}])]
			ifFalse: [self assert: sentFrames asArray equals: {{k - 1 \\ 50 + 1. k - 1 \\ 256}}].
		self assert: (out send: k \\ 50 + 1 with: [:b | Machine uint8At: b put: k \\ 256])]
!
testKickUnlessTheDeviceSaysNot
	| notify |
	notify := Machine allocate: 8.
	[queue notifyAt: notify + 2 queue: 5.
	Machine uint16At: notify + 2 put: 16rFFFF.
	Machine uint16At: page + 2048 put: 1.
	queue kick.
	self assert: (Machine uint16At: notify + 2) equals: 16rFFFF.
	Machine uint16At: page + 2048 put: 0.
	queue kick.
	self assert: (Machine uint16At: notify + 2) equals: 5.
	self assert: (Machine uint16At: page + 1024) equals: 1]
		ensure: [Machine free: notify]
! !
