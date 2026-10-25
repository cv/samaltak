Object subclass: #JugglerHand
	instanceVariableNames: 'left offset position velocity tilt spin lastPosition lastTilt holding caughtAt caughtPosition caughtVelocity caughtTilt knock dropping releasedAt now aimed acceleration'
	classVariableNames: ''
	package: 'Tools'!

JugglerHand comment: 'A hand of the ShannonJuggler, holding a cup: a bowl (bowlRadius, open within rimAngle of its axis) whose pose is position (the bowl''s centre, stage points) and tilt (radians; positive turns the opening towards +x), moved by the arm: driveTo:velocity:tilt: steers both, velocity and spin per frame. The contacts within a frame see the cup between its last pose and this one (positionAt:, downAt:). offset is the frame of its first drop; it remembers the plan of its catch (caughtAt...) and when its last ball left it.'!

!JugglerHand methodsFor: 'accessing'!
isLeft
	^left
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
place: aPoint
	"Put the cup at aPoint, level and still."
	position := lastPosition := aPoint.
	velocity := 0 @ 0.
	tilt := lastTilt := spin := 0.
	holding := dropping := aimed := nil
!
push: aVelocity
	velocity := aVelocity
! !

!JugglerHand methodsFor: 'moving'!
driveTo: aPoint velocity: aVelocity tilt: anAngle
	"One frame of the arm: accelerate the cup towards aPoint (moving at aVelocity, as it was going to), braking in time not to overshoot, and its tilt towards anAngle."
	| e want a |
	e := aPoint - position - velocity.
	want := aVelocity + (e * (0.35 min: (1.0 / (e r max: 0.01)) sqrt)).
	a := aVelocity - (aimed ifNil: [aVelocity]).
	a r > 1.5 ifTrue: [a := 0 @ 0].
	self accelerate: a + ((want - velocity) * 0.7) tilt: anAngle.
	aimed := aVelocity
!
accelerate: anAcceleration tilt: anAngle
	"One frame of the arm: speed the cup up by anAcceleration, as far as the arm can, and turn it towards anAngle. With a ball lying in it, the cup never drops faster than the ball would fall."
	| a |
	knock := 0.
	aimed := nil.
	lastPosition := position.
	lastTilt := tilt.
	a := anAcceleration.
	(holding notNil and: [now > caughtAt])
		ifTrue: [a := ((a x max: -0.6) min: 0.6) @ ((a y max: -1.5) min: 0.35)]
		ifFalse: [a r > 4 ifTrue: [a := a * (4 / a r)]].
	acceleration := a.
	velocity := velocity + a.
	position := position + velocity.
	spin := ((spin + ((anAngle - tilt) * 0.25) - (spin * 0.7)) max: -0.3) min: 0.3.
	tilt := tilt + spin
!
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
noteHolding: aBallOrNil at: aFrame
	"Remember when the last ball left my cup."
	(aBallOrNil isNil and: [holding notNil]) ifTrue: [releasedAt := aFrame].
	holding := aBallOrNil.
	now := aFrame
!
catchAt: aFrame position: aPoint velocity: aVelocity tilt: anAngle
	"The plan of my next catch: in frame aFrame my bowl is at aPoint, tilted by anAngle, moving at aVelocity with the ball lying in it."
	caughtAt := aFrame.
	caughtPosition := aPoint.
	caughtVelocity := aVelocity.
	caughtTilt := anAngle
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
caughtVelocity
	^caughtVelocity
!
caughtTilt
	^caughtTilt
!
acceleration
	^acceleration ifNil: [0 @ 0]
!
knock
	"How hard a ball hit my cup in this frame: how fast it came at it (points per frame), before this frame's pull of gravity and of the arm."
	^knock ifNil: [0]
!
knock: aNumber
	knock := self knock max: aNumber
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
