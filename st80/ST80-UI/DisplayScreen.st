Object subclass: #DisplayScreen
	instanceVariableNames: 'extent cell event'
	classVariableNames: ''
	package: 'ST80-UI'!

DisplayScreen comment: 'I am Display, the 1-bit screen, through the VM''s display primitives (DisplayPrimitives; only a simulated VM has them): rectangles white, black, grey or reversed, text in a fixed-width font (cell is a character''s extent), 1-bit pictures, copies (scrolling), the input events, and flush, which ends a frame. Coordinates are integers; the VM clips.'!

!DisplayScreen methodsFor: 'opening'!
open: aPoint
	"Answer whether there is a screen."
	cell := self primOpen: aPoint x height: aPoint y.
	cell isNil ifTrue: [^false].
	extent := aPoint.
	event := Array new: 5.
	^true
! !

!DisplayScreen methodsFor: 'accessing'!
extent
	^extent
!
bounds
	^0 @ 0 extent: extent
!
cell
	"A character's extent."
	^cell
! !

!DisplayScreen methodsFor: 'drawing'!
white: aRectangle
	self fill: aRectangle rule: 0
!
black: aRectangle
	self fill: aRectangle rule: 1
!
grey: aRectangle
	self fill: aRectangle rule: 2
!
reverse: aRectangle
	self fill: aRectangle rule: 3
!
fill: aRectangle rule: anInteger
	self primFillX: aRectangle left y: aRectangle top width: aRectangle width height: aRectangle height rule: anInteger
!
copy: aRectangle to: aPoint
	self primCopyX: aRectangle left y: aRectangle top width: aRectangle width height: aRectangle height toX: aPoint x y: aPoint y
!
show: aString at: aPoint
	"Black on white, one cell per character."
	self primText: aString x: aPoint x y: aPoint y rule: 0
!
showReversed: aString at: aPoint
	self primText: aString x: aPoint x y: aPoint y rule: 1
!
bits: aByteArray extent: aPoint at: anOrigin
	"Opaque: rows of (aPoint x + 7) // 8 bytes, the high bit leftmost, set bits black."
	self primBits: aByteArray x: anOrigin x y: anOrigin y width: aPoint x height: aPoint y rule: 0
! !

!DisplayScreen methodsFor: 'input'!
nextEvent
	"The next input event, {type. x. y. key. modifiers} (DisplayPrimitives), or nil. The Array is reused."
	^self primNextEvent: event
!
flush
	"The frame is complete."
	self primFlush
! !

!DisplayScreen methodsFor: 'primitives'!
primOpen: w height: h
	<primitive: 'displayOpen'>
	^nil
!
primFillX: x y: y width: w height: h rule: rule
	<primitive: 'displayFill'>
	^self primitiveFailed
!
primCopyX: x y: y width: w height: h toX: toX y: toY
	<primitive: 'displayCopy'>
	^self primitiveFailed
!
primText: aString x: x y: y rule: rule
	<primitive: 'displayText'>
	^self primitiveFailed
!
primBits: aByteArray x: x y: y width: w height: h rule: rule
	<primitive: 'displayBits'>
	^self primitiveFailed
!
primNextEvent: anArray
	<primitive: 'displayNextEvent'>
	^self primitiveFailed
!
primFlush
	<primitive: 'displayFlush'>
	^self primitiveFailed
! !
