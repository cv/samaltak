TestCase subclass: #GuestScreenTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

GuestScreenTest comment: 'I test the guest screen without a window: its text (the 7x14 bitmap font''s cells, plain and reversed) and its scale (whole points per guest pixel).'!

!GuestScreenTest methodsFor: 'tests'!
testTextIsTheBitmapFont
	"H: stems in rows 3 to 12, the bar in row 7, a blank row above and below the 14 rows of the font."
	| screen black white h |
	black := 16rFF000000.
	white := 16rFFFFFFFF.
	screen := GuestScreen new.
	screen open: 14 height: 16.
	screen text: 'H' x: 0 y: 0 rule: 0.
	screen text: 'H' x: 7 y: 0 rule: 1.
	screen flush.
	h := [:x :y | screen form bits at: y * 14 + x + 1].
	0 to: 15 do: [:y |
		0 to: 6 do: [:x | | ink |
			ink := (y between: 3 and: 12) and: [x = 0 or: [x = 5 or: [y = 7 and: [x <= 5]]]].
			self assert: (h value: x value: y) equals: (ink ifTrue: [black] ifFalse: [white]).
			self assert: (h value: x + 7 value: y) equals: (ink ifTrue: [white] ifFalse: [black])]]
!
testACodeOutsideTheFontIsABlankCell
	| screen |
	screen := GuestScreen new.
	screen open: 7 height: 16.
	screen text: (String with: (Character value: 200)) x: 0 y: 0 rule: 1.
	screen flush.
	self assert: (screen form bits allSatisfy: [:p | p = 16rFF000000])
!
testPixelSizeIsWholePoints
	| screen |
	screen := GuestScreen new.
	screen open: 640 height: 400.
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
