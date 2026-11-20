TestCase subclass: #VirtqueueTest
	instanceVariableNames: 'page queue'
	classVariableNames: ''
	package: 'Tests-Devices'!

VirtqueueTest comment: 'A Virtqueue in a page of memory (Machine allocate:), the test playing the device: it reads the descriptors and the available ring the driver set up, writes events into buffers and puts them on the used ring; the driver takes them in order and makes the buffers available again. On a host, which has no device, as on UEFI.'!

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
! !
