UIEvent subclass: #PointerEvent
	instanceVariableNames: 'position globalPosition button buttons clickCount delta'
	classVariableNames: ''
	package: 'UI-Windows'!

PointerEvent comment: 'I am a pointer event: type #down #up #move #wheel #enter #leave; position (a Point local to the View receiving me; the Window re-localizes me as I bubble), globalPosition (screen points), button (1 left, 2 right — also ctrl-click —, 3 middle; 0 for moves), buttons (held during a move: 1 left, 2 middle, 4 right, as the platform reports), clickCount, delta (wheel: Point, +y = away from the user), modifiers.'!

!PointerEvent methodsFor: 'accessing'!
position
	^position
!
position: aPoint
	position := aPoint
!
globalPosition
	^globalPosition
!
globalPosition: aPoint
	globalPosition := aPoint
!
button
	^button
!
buttons
	^buttons
!
clickCount
	^clickCount
!
delta
	^delta
!
setPosition: aPoint button: b buttons: bs clickCount: n delta: d
	position := aPoint.
	globalPosition := aPoint.
	button := b.
	buttons := bs.
	clickCount := n.
	delta := d
! !

!PointerEvent methodsFor: 'testing'!
isPointer
	^true
!
isDown
	^type == #down
!
isUp
	^type == #up
!
isMove
	^type == #move
!
isWheel
	^type == #wheel
!
isEnter
	^type == #enter
!
isLeave
	^type == #leave
!
isPrimary
	"Left button (without ctrl)."
	^button = 1
!
isSecondary
	"Right button, or ctrl-click."
	^button = 2
!
isMiddle
	^button = 3
!
isDragging
	"A move with the left button held."
	^type == #move and: [((buttons ifNil: [0]) bitAnd: 1) ~= 0]
! !

!PointerEvent methodsFor: 'dispatching'!
deliverTo: aWindow
	^aWindow dispatchPointer: self
!
dispatchTo: anInputDispatcher
	^anInputDispatcher handlePointer: self
! !

!PointerEvent methodsFor: 'copying'!
at: aPoint
	"A copy of me with position aPoint."
	^self copy position: aPoint; yourself
!
translatedBy: aPoint
	^self at: position + aPoint
!
withType: aSymbol
	^self copy setType: aSymbol time: timeStamp modifiers: modifiers; yourself
! !

!PointerEvent methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'PointerEvent('; print: type; space; print: position.
	button = 0 ifFalse: [aStream nextPutAll: ' button '; print: button].
	(clickCount notNil and: [clickCount > 1]) ifTrue: [aStream nextPutAll: ' x'; print: clickCount].
	delta isNil ifFalse: [aStream nextPutAll: ' delta '; print: delta].
	aStream nextPut: $)
! !

!PointerEvent class methodsFor: 'decoding'!
decode: anArray
	| code time mods point |
	code := anArray at: 1.
	time := self timeFrom: anArray.
	mods := self modifiersFrom: anArray.
	point := (anArray at: 3) @ (anArray at: 4).
	code = self evMouseMove ifTrue: [^self type: #move at: point button: 0 buttons: (anArray at: 5) clickCount: 0 delta: nil modifiers: mods time: time].
	code = self evWheel ifTrue: [
		^self type: #wheel at: point button: 0 buttons: 0 clickCount: 0
			delta: (self pointFrom: (anArray at: 7)) modifiers: mods time: time].
	^self type: (code = self evMouseDown ifTrue: [#down] ifFalse: [#up]) at: point
		button: (self buttonFrom: (anArray at: 5) modifiers: mods) buttons: 0
		clickCount: ((anArray at: 7) ifNil: [1]) delta: nil modifiers: mods time: time
!
buttonFrom: platformButton modifiers: aModifiers
	"Platform buttons: 1 left, 2 middle, 3 right. Ours: 1 left, 2 right (also ctrl-click), 3 middle."
	platformButton = 3 ifTrue: [^2].
	platformButton = 2 ifTrue: [^3].
	(platformButton = 1 and: [aModifiers control]) ifTrue: [^2].
	^platformButton ifNil: [1]
!
pointFrom: anObject
	anObject isNil ifTrue: [^0 @ 0].
	anObject isPoint ifTrue: [^anObject].
	^(anObject at: 1) @ (anObject at: 2)
! !

!PointerEvent class methodsFor: 'instance creation'!
type: aSymbol at: aPoint button: b buttons: bs clickCount: n delta: d modifiers: aModifiers time: ms
	^self new
		setType: aSymbol time: ms modifiers: aModifiers;
		setPosition: aPoint button: b buttons: bs clickCount: n delta: d;
		yourself
!
type: aSymbol at: aPoint
	^self type: aSymbol at: aPoint button: (aSymbol == #move ifTrue: [0] ifFalse: [1]) buttons: 0 clickCount: 1 delta: nil modifiers: Modifiers none time: Time millisecondClockValue
! !
