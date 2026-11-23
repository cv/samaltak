Object subclass: #DisplayScreen
	instanceVariableNames: 'extent bitmap font mailbox event serial dirty frameStart'
	classVariableNames: ''
	package: 'ST80-UI'!

DisplayScreen comment: 'I am Display, the guest''s 1-bit screen. I draw into an image-side bitmap and exchange completed frames and input through GuestDisplayMailbox.

The host sets the global to true to attach. I replace it on open with the v1 Array: {version. width. height. frame. serial. input. read. write. frameTimeUs}. Frames are packed MSB-left, black=1. Input is a flat ring of 32 five-slot records; the guest advances read, the host advances write, and both indices are zero-based.'!

Smalltalk at: #GuestDisplayMailbox put: nil!

!DisplayScreen methodsFor: 'opening'!
open: aPoint
	"Answer false if no display is attached or the requested extent is invalid."
	| attachment previousSerial w h |
	attachment := Smalltalk at: #GuestDisplayMailbox.
	previousSerial := 0.
	attachment == true ifFalse: [
		(attachment isArray and: [attachment size = 9 and: [(attachment at: 1) = 1]])
			ifFalse: [^false].
		previousSerial := attachment at: 5.
		(previousSerial isInteger and: [previousSerial > 0]) ifFalse: [^false]].
	w := aPoint x.
	h := aPoint y.
	(w isInteger and: [h isInteger and: [
		(w between: 1 and: 4096) and: [(h between: 1 and: 4096) and: [w * h <= 4194304]]]])
			ifFalse: [^false].
	serial := previousSerial.
	extent := aPoint.
	bitmap := DisplayBitmap new extent: extent.
	font := DisplayFont new.
	event := Array new: 5.
	mailbox := Array new: 9.
	mailbox at: 1 put: 1; at: 2 put: w; at: 3 put: h;
		at: 6 put: (Array new: 160); at: 7 put: 0; at: 8 put: 0.
	dirty := true.
	frameStart := nil.
	self flush.
	Smalltalk at: #GuestDisplayMailbox put: mailbox.
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
	"A character's extent, including one line of padding above and below the 7x14 glyph."
	^7 @ 16
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
fill: aRectangle rule: rule
	bitmap isNil ifTrue: [^self].
	(rule isInteger and: [rule between: 0 and: 3]) ifFalse: [^self error: 'Invalid fill rule'].
	self noteFrameStart.
	(bitmap fill: aRectangle rule: rule) ifTrue: [dirty := true]
!
copy: aRectangle to: aPoint
	bitmap isNil ifTrue: [^self].
	self noteFrameStart.
	(bitmap copy: aRectangle to: aPoint) ifTrue: [dirty := true]
!
show: aString at: aPoint
	"Black on white, one cell per character."
	self show: aString at: aPoint reversed: false
!
showReversed: aString at: aPoint
	"White on black."
	self show: aString at: aPoint reversed: true
!
bits: aByteArray extent: aPoint at: anOrigin
	"Opaque: rows of (aPoint x + 7) // 8 bytes, the high bit leftmost, set bits black."
	self bits: aByteArray extent: aPoint at: anOrigin rule: 0
!
bits: aByteArray extent: aPoint at: anOrigin rule: rule
	"Rule 0 paints the whole rectangle; rules 1 and 2 paint or invert at the set bits only."
	bitmap isNil ifTrue: [^self].
	(rule isInteger and: [rule between: 0 and: 2]) ifFalse: [^self error: 'Invalid bitmap rule'].
	(aPoint x < 0 or: [aPoint y < 0]) ifTrue: [^self error: 'Invalid bitmap extent'].
	self noteFrameStart.
	(bitmap bits: aByteArray extent: aPoint at: anOrigin rule: rule) ifTrue: [dirty := true]
! !

!DisplayScreen methodsFor: 'input and output'!
nextEvent
	"Answer the next {type. x. y. key. modifiers}, or nil. The Array is reused."
	| read offset input |
	mailbox isNil ifTrue: [^nil].
	self noteFrameStart.
	read := mailbox at: 7.
	read = (mailbox at: 8) ifTrue: [^nil].
	offset := read * 5.
	input := mailbox at: 6.
	event replaceFrom: 1 to: 5 with: input startingAt: offset + 1.
	mailbox at: 7 put: (read + 1 \\ 32).
	^event
!
flush
	"Publish the completed frame, if drawn. Serial zero fences a partial publication."
	| elapsed snapshot |
	mailbox isNil ifTrue: [^self].
	dirty ifTrue: [
		snapshot := bitmap snapshot.
		elapsed := frameStart ifNotNil: [Time microsecondClockValue - frameStart].
		serial := serial + 1.
		mailbox at: 5 put: 0; at: 4 put: snapshot; at: 9 put: elapsed; at: 5 put: serial.
		dirty := false].
	frameStart := nil
! !

!DisplayScreen methodsFor: 'private'!
noteFrameStart
	frameStart isNil ifTrue: [frameStart := Time microsecondClockValue]
!
show: aString at: aPoint reversed: aBoolean
	| x y first last rows |
	bitmap isNil ifTrue: [^self].
	x := aPoint x.
	y := aPoint y.
	(y >= extent y or: [y + 16 <= 0]) ifTrue: [^self].
	first := (x negated // 7 max: 0) + 1.
	last := aString size min: (extent x - x + 6 // 7).
	first > last ifTrue: [^self].
	self noteFrameStart.
	first to: last do: [:i |
		rows := font rowsFor: (aString at: i) value reversed: aBoolean.
		bitmap glyph: rows x: (i - 1 * 7) + x y: y].
	dirty := true
! !
