Object subclass: #JugglerHand
	instanceVariableNames: 'left offset position balls'
	classVariableNames: ''
	package: 'Tools'!

JugglerHand comment: 'A hand of the ShannonJuggler: its cup''s position, the balls it holds, and its beat (offset: the frame of its first throw). The right hand moves as the left one, mirrored.'!

!JugglerHand methodsFor: 'accessing'!
isLeft
	^left
!
left: aBoolean offset: anInteger
	left := aBoolean.
	offset := anInteger.
	balls := OrderedCollection new
!
offset
	^offset
!
position
	^position
!
position: aPoint
	position := aPoint
!
balls
	^balls
! !

!JugglerHand methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: (left ifTrue: ['the left hand'] ifFalse: ['the right hand'])
! !
