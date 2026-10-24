Object subclass: #JugglerBall
	instanceVariableNames: 'position velocity'
	classVariableNames: ''
	package: 'Tools'!

JugglerBall comment: 'A ball of the ShannonJuggler: position (its centre, in the stage''s points) and velocity (points per frame).'!

!JugglerBall methodsFor: 'accessing'!
position
	^position
!
position: aPoint
	position := aPoint
!
velocity
	^velocity
!
velocity: aPoint
	velocity := aPoint
! !

!JugglerBall methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a JugglerBall at '; print: position rounded
! !

!JugglerBall class methodsFor: 'accessing'!
radius
	^10
! !
