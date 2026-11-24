TestCase subclass: #NativeCountedTextTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

!NativeCountedTextTest methodsFor: 'tests'!
testNativeCopyInSimulation
	| sim helper libc mem a src copy |
	sim := VMSimulation modules: {NativeCountedText}.
	helper := sim module: NativeCountedText.
	libc := sim library: LibC.
	mem := sim memory.
	a := mem allocate: 3.
	mem bytesAt: a put: #[97 255 98].
	src := mem pointerTo: (CTypeRegistry default at: 'uint8_t') at: a.
	"Input ends exactly here: no terminator is read. The copy is independent of the borrow."
	copy := helper copyTerminated: src size: 3.
	self assert: copy notNull.
	[ self assert: (mem bytesAt: copy address count: 4) equals: #[97 255 98 0].
	  src at: 1 put: 0.
	  self assert: (mem bytesAt: copy address count: 4) equals: #[97 255 98 0].
	  self assert: (helper copyTerminated: src size: 3) isNull ]
		ensure: [libc free: copy].
	"Only the counted prefix is validated and copied."
	copy := helper copyTerminated: src size: 1.
	self assert: copy notNull.
	[self assert: (mem bytesAt: copy address count: 2) equals: #[97 0]]
		ensure: [libc free: copy].
	self assert: (helper copyTerminated: CPointer null size: 1) isNull.
	self assert: (helper copyTerminated: src size: 16r800000000) isNull.
	self assert: (helper copyTerminated: src size: 16rFFFFFFFFFFFFFFFF) isNull.
	copy := helper copyTerminated: CPointer null size: 0.
	self assert: copy notNull.
	[self assert: (mem bytesAt: copy address count: 1) equals: #[0]]
		ensure: [libc free: copy]
! !
