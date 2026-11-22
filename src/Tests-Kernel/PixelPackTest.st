TestCase subclass: #PixelPackTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

PixelPackTest comment: 'PixelPack: 4-byte pixels as 3-byte ones, the VM''s primitive and the Smalltalk the same to the byte, on rectangles of rows of every width to 40 (the vector part and the rest), both byte orders, inside larger rows; bad rectangles refused.'!

!PixelPackTest methodsFor: 'helpers'!
randomBytes: n seed: anInteger
	| random |
	random := Random seed: anInteger.
	^((1 to: n) collect: [:i | (random nextInt: 256) - 1]) asByteArray
! !

!PixelPackTest methodsFor: 'tests'!
testBgraAndRgba
	| px |
	px := #[1 2 3 255 4 5 6 255].
	self assert: (PixelPack pack: px width: 2 height: 1 swap: false) equals: #[1 2 3 4 5 6].
	self assert: (PixelPack pack: px width: 2 height: 1 swap: true) equals: #[3 2 1 6 5 4]
!
testPrimitiveMatchesSmalltalk
	| src |
	src := self randomBytes: 50 * 4 * 5 seed: 5.
	#(false true) do: [:swap | 0 to: 40 do: [:w | #(0 3) do: [:x | 1 to: 3 do: [:h | | a b r |
		a := ByteArray new: w * h * 3 + 7.
		b := ByteArray new: w * h * 3 + 7.
		r := PixelPack primPack: src stride: 200 x: x y: 1 width: w height: h swap: (swap ifTrue: [1] ifFalse: [0]) into: a.
		self assert: r == a description: 'the primitive ran'.
		PixelPack packInSmalltalk: src stride: 200 x: x y: 1 width: w height: h swap: swap into: b.
		self assert: a equals: b]]]]
!
testBadRectanglesAreRefused
	| src |
	src := ByteArray new: 64.
	self assert: (PixelPack primPack: src stride: 16 x: 0 y: 0 width: 4 height: 5 swap: 0 into: (ByteArray new: 60)) isNil.
	self assert: (PixelPack primPack: src stride: 16 x: 1 y: 0 width: 4 height: 1 swap: 0 into: (ByteArray new: 12)) isNil.
	self assert: (PixelPack primPack: src stride: 16 x: 0 y: 0 width: 4 height: 1 swap: 0 into: (ByteArray new: 11)) isNil.
	self assert: (PixelPack primPack: src stride: 16 x: 0 y: 0 width: 4 height: 1 swap: 2 into: (ByteArray new: 12)) isNil.
	self assert: (PixelPack primPack: src stride: 16 x: 0 y: 0 width: 4 height: 1 swap: 0 into: src) isNil.
	self should: [PixelPack pack: src stride: 16 x: 0 y: 0 width: 4 height: 5 swap: false into: (ByteArray new: 60)] raise: Error.
	self assert: (PixelPack pack: src stride: 16 x: 0 y: 0 width: 0 height: 0 swap: false into: #[]) equals: #[]
! !
