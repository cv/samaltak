Object subclass: #JugglerBall
	instanceVariableNames: 'position velocity bounced'
	classVariableNames: ''
	package: 'Tools'!

JugglerBall comment: 'A ball of the ShannonJuggler: position (its centre, in the stage''s points), velocity (points per frame), and whether it bounced off the drumhead since it was last in a cup.'!

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
!
bounced
	^bounced == true
!
bounced: aBoolean
	bounced := aBoolean
! !

!JugglerBall methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a JugglerBall at '; print: position rounded
! !

!JugglerBall class methodsFor: 'accessing'!
radius
	^10
! !
