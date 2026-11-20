TestCase subclass: #E1000eInterfaceTest
	instanceVariableNames: 'registers memory nic'
	classVariableNames: ''
	package: 'Tests-Devices'!

E1000eInterfaceTest comment: 'An E1000eInterface over a controller in memory (Machine allocate:): its registers are a block of memory, the test plays the controller on its rings: it fills the receive descriptors from the head (RDH) up to the tail the driver moved (RDT) and sets DD, reads the transmit descriptors up to TDT and sets DD. The controller''s addresses are the CPU''s plus 2^32, as behind an IOMMU.'!

!E1000eInterfaceTest methodsFor: 'running'!
setUp
	registers := Machine allocate: 16r6000.
	memory := Machine allocate: E1000eInterface memorySize.
	nic := E1000eInterface registers: registers memory: memory device: memory + 16r100000000.
	nic initRings
!
tearDown
	nic forget.
	Machine free: registers.
	Machine free: memory
! !

!E1000eInterfaceTest methodsFor: 'controller'!
reg: offset
	^Machine uint32At: registers + offset
!
reg: offset put: v
	Machine uint32At: registers + offset put: v
!
frame: n byte: b
	^(ByteArray new: n) atAllPut: b; yourself
!
controllerReceives: aFrame
	"Into the descriptor at the head, if the driver gave it (head ~= tail); answer whether it could."
	^self controllerReceives: aFrame status: 3 errors: 0
!
controllerReceives: aFrame status: status errors: errors
	| head d |
	head := self reg: 16r2810.
	head = (self reg: 16r2818) ifTrue: [^false].
	d := memory + (16 * head).
	Machine bytesAt: (Machine uint64At: d) - 16r100000000 put: aFrame.
	Machine uint16At: d + 8 put: aFrame size.
	Machine uint8At: d + 13 put: errors.
	Machine uint8At: d + 12 put: status.
	self reg: 16r2810 put: head + 1 \\ E1000eInterface rxCount.
	^true
!
controllerSends
	"The frames of the descriptors from the head to the tail, done (DD)."
	| head frames d |
	head := self reg: 16r3810.
	frames := OrderedCollection new.
	[head ~= (self reg: 16r3818)] whileTrue: [
		d := memory + 2048 + (16 * head).
		self assert: (Machine uint8At: d + 11) equals: 16r0B.
		frames add: (Machine bytesAt: (Machine uint64At: d) - 16r100000000 count: (Machine uint16At: d + 8)).
		Machine uint8At: d + 12 put: 1.
		head := head + 1 \\ E1000eInterface txCount].
	self reg: 16r3810 put: head.
	^frames asArray
!
received
	| buffer frames n |
	buffer := ByteArray new: 1536.
	frames := OrderedCollection new.
	[(n := nic receiveInto: buffer) notNil] whileTrue: [frames add: (buffer copyFrom: 1 to: n)].
	^frames asArray
! !

!E1000eInterfaceTest methodsFor: 'tests'!
testRings
	"Both rings at the controller's addresses, every receive descriptor but one the controller's, receive and transmit on."
	self assert: (self reg: 16r2800) + ((self reg: 16r2804) bitShift: 32) equals: memory + 16r100000000.
	self assert: (self reg: 16r2808) equals: 16 * E1000eInterface rxCount.
	self assert: (self reg: 16r2810) equals: 0.
	self assert: (self reg: 16r2818) equals: E1000eInterface rxCount - 1.
	self assert: (self reg: 16r3800) + ((self reg: 16r3804) bitShift: 32) equals: memory + 16r100000000 + 2048.
	self assert: (self reg: 16r3808) equals: 16 * E1000eInterface txCount.
	self assert: (self reg: 16r3810) equals: 0.
	self assert: (self reg: 16r3818) equals: 0.
	self assert: (self reg: 16r0100) equals: 16r04008002.
	self assert: (self reg: 16r0400) equals: 16r0003F0FA.
	0 to: E1000eInterface rxCount - 1 do: [:i |
		self assert: (Machine uint64At: memory + (16 * i)) equals: memory + 16r100000000 + 4096 + (2048 * i).
		self assert: (Machine uint8At: memory + (16 * i) + 12) equals: 0].
	self deny: nic hasFrame.
	self assert: self received isEmpty
!
testReceivingWrapsAround
	"Frames come in order; each descriptor goes back to the controller (RDT) once taken, round the ring many times."
	| k |
	k := 0.
	1 to: 40 do: [:round |
		1 to: round * 3 \\ 50 + 1 do: [:i |
			k := k + 1.
			self assert: (self controllerReceives: (self frame: k \\ 1400 + 60 byte: k \\ 256))].
		self assert: nic hasFrame.
		self assert: nic waiting equals: round * 3 \\ 50 + 1.
		self assert: self received equals: ((k - (round * 3 \\ 50) to: k) collect: [:j | self frame: j \\ 1400 + 60 byte: j \\ 256]) asArray.
		self assert: (self reg: 16r2818) equals: (self reg: 16r2810) - 1 \\ E1000eInterface rxCount].
	self assert: k > (3 * E1000eInterface rxCount).
	self assert: nic status equals: {k. 0. 0. 0}
!
testTheControllerStopsWhenTheRingIsFull
	"rxCount - 1 descriptors are the controller's: then it has none until the driver gives back those it took, 16 at a time or when no frame waits."
	| buffer |
	buffer := ByteArray new: 1536.
	1 to: E1000eInterface rxCount - 1 do: [:i | self assert: (self controllerReceives: (self frame: 64 byte: i))].
	self deny: (self controllerReceives: (self frame: 64 byte: 0)).
	self assert: nic waiting equals: E1000eInterface rxCount - 1.
	1 to: 15 do: [:i | self assert: (nic receiveInto: buffer) equals: 64].
	self deny: (self controllerReceives: (self frame: 64 byte: 0)).
	self assert: (nic receiveInto: buffer) equals: 64.
	1 to: 16 do: [:i | self assert: (self controllerReceives: (self frame: 64 byte: 0))].
	self deny: (self controllerReceives: (self frame: 64 byte: 0)).
	self assert: self received size equals: E1000eInterface rxCount - 1 - 16 + 16.
	self assert: (self reg: 16r2818) equals: (self reg: 16r2810) - 1 \\ E1000eInterface rxCount
!
testBadFramesAreSkipped
	"Not whole (no EOP) or with a receive error: given back, not answered."
	self controllerReceives: (self frame: 70 byte: 1) status: 1 errors: 0.
	self controllerReceives: (self frame: 71 byte: 2) status: 3 errors: 16r80.
	self controllerReceives: (self frame: 72 byte: 3) status: 3 errors: 16r60.
	self assert: self received equals: {self frame: 72 byte: 3}.
	self assert: (self reg: 16r2818) equals: 2
!
testAFrameIsCutToTheBuffer
	| buffer |
	self controllerReceives: (self frame: 100 byte: 7).
	buffer := ByteArray new: 40.
	self assert: (nic receiveInto: buffer) equals: 40.
	self assert: buffer equals: (self frame: 40 byte: 7)
!
testSendingAndReclaimingWrapAround
	"Frames go out in order (short ones padded to 60 bytes); a full ring refuses one until the controller is done with some."
	| expected |
	1 to: E1000eInterface txCount - 1 do: [:i | self assert: (nic send: (self frame: 200 byte: i) count: 60 + i)].
	self deny: (nic send: (self frame: 100 byte: 0) count: 60).
	self assert: self controllerSends equals: ((1 to: E1000eInterface txCount - 1) collect: [:i | self frame: 60 + i byte: i]) asArray.
	1 to: 300 do: [:k |
		expected := (1 to: k \\ 7 + 1) collect: [:i | self frame: k + i \\ 1400 + 60 byte: k \\ 256].
		expected do: [:f | self assert: (nic send: f , #[1 2 3] count: f size)].
		self assert: self controllerSends equals: expected asArray].
	self assert: (nic send: #[1 2 3] count: 3).
	self assert: self controllerSends equals: {#[1 2 3] , (ByteArray new: 57)}.
	self assert: (nic status first: 3) equals: {0. E1000eInterface txCount + ((1 to: 300) inject: 0 into: [:a :k | a + (k \\ 7) + 1]). 1}
!
testAFrameWakesTheStackWhileFramesComeAndGo
	"After a frame went out, the driver's Process looks for one without pause and signals the stack's semaphore once one is there."
	| semaphore |
	semaphore := Semaphore new.
	nic semaphore: semaphore.
	self assert: (nic send: (self frame: 60 byte: 1) count: 60).
	self controllerReceives: (self frame: 60 byte: 2).
	self deny: (semaphore waitTimeoutMSecs: 2000).
	self assert: self received equals: {self frame: 60 byte: 2}.
	self controllerReceives: (self frame: 60 byte: 3).
	self deny: (semaphore waitTimeoutMSecs: 2000).
	self assert: self received equals: {self frame: 60 byte: 3}
! !
