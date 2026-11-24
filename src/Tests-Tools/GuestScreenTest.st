TestCase subclass: #GuestScreenTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

GuestScreenTest comment: 'I test presentation of packed guest frames without opening a window. VMSimulationTest tests the guest renderer itself.'!

!GuestScreenTest methodsFor: 'tests'!
testPackedFramesArePresented
	| screen black white |
	black := 16rFF000000.
	white := 16rFFFFFFFF.
	screen := GuestScreen new.
	"11 pixels per row, even though the first row has set padding bits."
	screen displayFrame: #[16r80 16r3F 16rFF 16rE0 16r55 16r40] extent: 11 @ 3 time: nil.
	self assert: screen screenExtent equals: 11 @ 3.
	#(1 0 0 0 0 0 0 0 0 0 1
	  1 1 1 1 1 1 1 1 1 1 1
	  0 1 0 1 0 1 0 1 0 1 0) doWithIndex: [:ink :i |
		self assert: (screen form bits at: i) equals: (ink = 1 ifTrue: [black] ifFalse: [white])].
	screen displayFrame: (ByteArray new: 6) extent: 11 @ 3 time: nil.
	self assert: (screen form bits allSatisfy: [:p | p = white])
!
testPixelSizeIsWholePoints
	| screen |
	screen := GuestScreen new.
	screen displayFrame: (ByteArray new: 32000) extent: 640 @ 400 time: nil.
	screen bounds: (0 @ 0 extent: 1402 @ 800).
	self assert: screen pixelSize equals: 2.
	screen bounds: (0 @ 0 extent: 1402 @ 799).
	self assert: screen pixelSize equals: 1.
	screen bounds: (0 @ 0 extent: 1919 @ 1199).
	self assert: screen pixelSize equals: 2.
	screen bounds: (0 @ 0 extent: 1920 @ 1200).
	self assert: screen pixelSize equals: 3.
	screen bounds: (0 @ 0 extent: 300 @ 200).
	self assert: screen pixelSize equals: 1
! !
