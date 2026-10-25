Object subclass: #JugglerHand
	instanceVariableNames: 'left offset position velocity tilt spin lastPosition lastTilt holding caughtAt caughtPosition caughtPhase caughtSpeed dropping releasedAt depth'
	classVariableNames: ''
	package: 'Tools'!

JugglerHand comment: 'A hand of the ShannonJuggler, holding a cup: a bowl (bowlRadius, open within rimAngle of its axis) whose pose is position (the bowl''s centre, stage points) and tilt (radians; positive turns the opening towards +x), moved by the arm: driveTo:velocity:tilt: is a PD controller on both, velocity and spin per frame. The contacts within a frame see the cup between its last pose and this one (positionAt:, downAt:). offset is the frame of its first drop; it remembers when and where it caught the ball it holds.'!

!JugglerHand methodsFor: 'accessing'!
isLeft
	^left
!
lane
	"The lane of the balls this hand throws: in front of the figure's plane (left hand) or behind it."
	^left ifTrue: [1] ifFalse: [-1]
!
left: aBoolean offset: anInteger
	left := aBoolean.
	offset := anInteger
!
offset
	^offset
!
position
	^position
!
velocity
	^velocity
!
tilt
	^tilt
!
depth
	"How far in front of the figure's plane the cup is (points), for the picture: it moves to the lane of the ball it will throw or catch."
	^depth ifNil: [0]
!
place: aPoint
	"Put the cup at aPoint, level and still."
	position := lastPosition := aPoint.
	velocity := 0 @ 0.
	tilt := lastTilt := spin := 0.
	holding := dropping := nil
!
push: aVelocity
	velocity := aVelocity
! !

!JugglerHand methodsFor: 'moving'!
driveTo: aPoint velocity: aVelocity tilt: anAngle
	"One frame of the arm: accelerate the cup towards aPoint (moving at aVelocity) and its tilt towards anAngle."
	| a |
	lastPosition := position.
	lastTilt := tilt.
	a := (aPoint - position) * 0.5 + ((aVelocity - velocity) * 1.2).
	holding isNil
		ifTrue: [a r > 4 ifTrue: [a := a * (4 / a r)]]
		ifFalse: [a := ((a x max: -0.6) min: 0.6) @ ((a y max: -1.5) min: 0.35)].
	velocity := velocity + a.
	position := position + velocity.
	spin := ((spin + ((anAngle - tilt) * 0.25) - (spin * 0.7)) max: -0.15) min: 0.15.
	tilt := tilt + spin
!
drift: aDepth
	depth := self depth + (aDepth - self depth * 0.12)
! !

!JugglerHand methodsFor: 'the cup'!
positionAt: s
	"The bowl's centre at s of this frame (0: its start, 1: now)."
	^lastPosition + ((position - lastPosition) * s)
!
downAt: s
	"The bowl's axis, from its centre to its bottom, at s of this frame."
	| t |
	t := lastTilt + ((tilt - lastTilt) * s).
	^t sin negated @ t cos
!
rimDirection: side at: s
	"From the centre to the rim on one side (-1 or 1), at s of this frame."
	| d a |
	d := self downAt: s.
	a := self class rimAngle * side.
	^(d x * a cos) - (d y * a sin) @ ((d x * a sin) + (d y * a cos))
!
velocityAt: aPoint
	"How fast the cup's surface at aPoint moves, per frame."
	| r |
	r := aPoint - position.
	^velocity + ((spin * r y) negated @ (spin * r x))
!
holds: aBall
	"Whether aBall lies in my bowl (or bobs in it; the one I hold may bob a little more)."
	| d slack |
	d := aBall position - position.
	slack := aBall == holding ifTrue: [6] ifFalse: [0].
	^d r < (self class bowlRadius + 3 + slack) and: [(d dotProduct: (self downAt: 1)) > (-8 - slack)]
!
noteHolding: aBallOrNil at: aFrame phase: aPhase
	"Remember when and where the ball I hold came into my cup, and when the last one left it."
	(aBallOrNil isNil and: [holding notNil]) ifTrue: [releasedAt := aFrame].
	(aBallOrNil notNil and: [holding isNil]) ifTrue: [
		caughtAt := aFrame.
		caughtPosition := position.
		caughtPhase := aPhase.
		caughtSpeed := aBallOrNil velocity y - velocity y max: 0].
	holding := aBallOrNil
!
caughtAt
	^caughtAt
!
releasedAt
	"When the last ball left my cup."
	^releasedAt ifNil: [-1000]
!
caughtPosition
	^caughtPosition
!
caughtPhase
	^caughtPhase
!
caughtSpeed
	"How fast the ball came down into the cup."
	^caughtSpeed
!
dropping: aBoolean
	dropping := aBoolean
!
isDropping
	"Whether the cup tips its ball out in this glide."
	^dropping ~~ false
! !

!JugglerHand methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: (left ifTrue: ['the left hand'] ifFalse: ['the right hand'])
! !

!JugglerHand class methodsFor: 'the cup'!
bowlRadius
	^15
!
rimAngle
	"How far the rim is from the bottom of the bowl, seen from its centre."
	^1.57
! !
