TestCase subclass: #PNGCodecTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

PNGCodecTest comment: 'I check PNGWriter''s compressed encodings against PNGReader without a GPU: indexed (with transparency), RGB and RGBA Forms read back identical, a screen-sized Form small before and after scaling, the stored PNGs written before compression read too, corrupt files refused; and Form''s scaling: aspect kept within the limits, area averaging with fractional weights.'!

!PNGCodecTest methodsFor: 'tests'!
testIndexedRoundTrip
	| form png |
	form := Form width: 37 height: 23.
	1 to: form bits size do: [:i | form bits at: i put: (#(16rFF0000FF 16rFFFFFFFF 16r80402010) at: i \\ 3 + 1)].
	png := form pngBytes.
	self assert: (png at: 26) equals: 3.
	self assertRoundTrip: form
!
testRGBRoundTrip
	| form |
	form := self gradient: 300 by: 200 alpha: [:x :y | 255].
	self assert: (form pngBytes at: 26) equals: 2.
	self assertRoundTrip: form
!
testRGBARoundTrip
	| form |
	form := self gradient: 300 by: 200 alpha: [:x :y | x + y \\ 256].
	self assert: (form pngBytes at: 26) equals: 6.
	self assertRoundTrip: form
!
testScreenSizedForm
	| form png scaled |
	form := self screenForm.
	png := form pngBytes.
	self assert: png size < 200000.
	self assert: (PNGReader formFrom: png) bits equals: form bits.
	scaled := form scaledToFit: 1568 pixels: 1150000.
	png := scaled pngBytes.
	self assert: png size < 700000.
	self assert: (PNGReader formFrom: png) bits equals: scaled bits
!
testReadsStoredPNG
	| form |
	form := self gradient: 50 by: 40 alpha: [:x :y | x * 5].
	self assert: (PNGReader formFrom: (PNGWriter storedBytesFor: form asByteArray width: 50 height: 40)) bits equals: form bits
!
testCorruptPNGIsRefused
	| png |
	png := (self gradient: 20 by: 10 alpha: [:x :y | 255]) pngBytes.
	png at: 40 put: ((png at: 40) bitXor: 1).
	self should: [PNGReader formFrom: png] raise: Error.
	self should: [PNGReader formFrom: #[1 2 3]] raise: Error
!
testScaledToFitKeepsAspect
	| form scaled |
	form := Form width: 1920 height: 1080.
	scaled := form scaledToFit: 1568 pixels: 1150000.
	self assert: scaled extent equals: 1429 @ 804.
	self assert: scaled width * scaled height <= 1150000.
	self assert: (scaled width / scaled height - (16 / 9)) abs < 0.01.
	self assert: ((Form width: 1000 height: 4000) scaledToFit: 1568 pixels: 1150000) extent equals: 392 @ 1568.
	self assert: (form scaledToFit: 3000 pixels: 10000000) == form.
	self assert: form extent equals: 1920 @ 1080
!
testScaledToAverages
	| form scaled |
	form := Form width: 3 height: 1.
	form bits at: 1 put: 16rFF000000; at: 2 put: 16rFF00005A; at: 3 put: 16rFF0000B4.
	scaled := form scaledTo: 2 @ 1.
	self assert: (scaled bits at: 1) equals: 16rFF00001E.
	self assert: (scaled bits at: 2) equals: 16rFF000096.
	form := Form width: 2 height: 2.
	form bits at: 1 put: 16r00000000; at: 2 put: 16rFF0064C8; at: 3 put: 16rFF0000C8; at: 4 put: 16r000064C8.
	self assert: ((form scaledTo: 1 @ 1) bits at: 1) equals: 16r80003296
! !

!PNGCodecTest methodsFor: 'support'!
assertRoundTrip: aForm
	| back |
	back := PNGReader formFrom: aForm pngBytes.
	self assert: back extent equals: aForm extent.
	self assert: back bits equals: aForm bits
!
gradient: w by: h alpha: aBlock
	| form |
	form := Form width: w height: h.
	0 to: h - 1 do: [:y | 0 to: w - 1 do: [:x |
		form bits at: y * w + x + 1 put: (x \\ 256) + (y \\ 256 bitShift: 8) + (x * y \\ 256 bitShift: 16) + ((aBlock value: x value: y) bitShift: 24)]].
	^form
!
screenForm
	"A 1920x1080 stand-in for a screenshot: a dithered desktop, a window of text-like strokes, a gradient panel."
	| form |
	form := Form width: 1920 height: 1080.
	0 to: 1079 do: [:y | 0 to: 1919 do: [:x | | v |
		v := (x + y) odd ifTrue: [16rFF808080] ifFalse: [16rFFFFFFFF].
		((x between: 100 and: 900) and: [y between: 100 and: 700]) ifTrue: [
			v := ((x // 3 + (y // 7) * 31) \\ 11 < 3 and: [y \\ 14 < 10]) ifTrue: [16rFF000000] ifFalse: [16rFFFFFFFF]].
		((x between: 1000 and: 1800) and: [y between: 50 and: 300]) ifTrue: [v := 16rFF000000 + ((x \\ 256) bitShift: 8) + (y \\ 256)].
		form bits at: y * 1920 + x + 1 put: v]].
	^form
! !
