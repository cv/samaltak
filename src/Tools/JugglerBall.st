Object subclass: #JugglerBall
	instanceVariableNames: 'position velocity bounced lane'
	classVariableNames: ''
	package: 'Tools'!

JugglerBall comment: 'A ball of the ShannonJuggler: position (its centre, in the stage''s points), velocity (points per frame), whether it bounced off the drumhead since it was last in a cup, and its lane.'!

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
!
lane
	"In front of the figure's plane (1, from the left hand) or behind it (-1, from the right one): balls on their way from different hands pass each other."
	^lane ifNil: [0]
!
lane: anInteger
	lane := anInteger
! !

!JugglerBall methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a JugglerBall at '; print: position rounded
! !

!JugglerBall class methodsFor: 'accessing'!
radius
	^10
! !
