Object subclass: #JugglerHand
	instanceVariableNames: 'left offset position velocity tilt spin lastPosition lastTilt holding caughtAt caughtPosition caughtVelocity caughtTilt knock dropping releasedAt now acceleration turn carry'
	classVariableNames: ''
	package: 'Tools'!

JugglerHand comment: 'A hand of the ShannonJuggler, holding a cup: a bowl (bowlRadius, open within rimAngle of its axis) whose pose is position (the bowl''s centre, stage points) and tilt (radians; positive turns the opening towards +x), moved by the arm: steerTo:velocity:acceleration:in:tilt: moves it smoothly, velocity and spin per frame. The contacts within a frame see the cup between its last pose and this one (positionAt:, downAt:). offset is the frame of its first drop; it remembers the plan of its catch (caughtAt...) and when its last ball left it.'!

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
	acceleration := 0 @ 0.
	turn := 0.
	holding := dropping := carry := releasedAt := nil
!
push: aVelocity
	velocity := aVelocity
! !

!JugglerHand methodsFor: 'moving'!
steerTo: aPoint velocity: aVelocity acceleration: anAcceleration in: frames tilt: anAngle
	"One frame of the arm: move the cup on the smooth path (smoothPathFrom:...) from where it is, how fast it goes and how it speeds up now, to aPoint at aVelocity and anAcceleration in frames, and turn it towards anAngle."
	self
		accelerate: (self class smoothPathFrom: position velocity: velocity acceleration: acceleration to: aPoint velocity: aVelocity acceleration: anAcceleration in: frames)
		tilt: anAngle
!
accelerate: anAcceleration tilt: anAngle
	"One frame of the arm: speed the cup up by anAcceleration, as far as the arm can, and turn it smoothly towards anAngle. With a ball lying in it, the cup never drops faster than the ball would fall."
	| a |
	knock := 0.
	lastPosition := position.
	lastTilt := tilt.
	a := anAcceleration.
	(holding notNil and: [now > caughtAt])
		ifTrue: [a := ((a x max: -0.6) min: 0.6) @ ((a y max: -1.5) min: 0.35)]
		ifFalse: [a r > 4 ifTrue: [a := a * (4 / a r)]].
	acceleration := a.
	velocity := velocity + a.
	position := position + velocity.
	turn := self class smoothPathFrom: tilt velocity: spin acceleration: turn to: anAngle velocity: 0 acceleration: 0 in: 8.
	spin := spin + turn.
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
	carry := nil.
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
carry
	"What the juggler worked out about carrying the ball I caught."
	^carry
!
carry: anArray
	carry := anArray
!
acceleration
	^acceleration ifNil: [0 @ 0]
!
knock
	"How hard a ball hit my cup in this frame: how fast it came at it (points per frame), before or after this frame's pull of gravity and of the arm, whichever is less."
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

!JugglerHand class methodsFor: 'moving'!
smoothPathFrom: x0 velocity: v0 acceleration: a0 to: x1 velocity: v1 acceleration: a1 in: n
	"The acceleration for the next frame on the path from x0, v0, a0 to x1, v1, a1 in n frames on which the acceleration in frame i is a0 + (j * i) + (c * i * i) + (d * i * i * i) (each frame the velocity grows by it, then the position by the velocity): so it changes smoothly. Points or numbers."
	| s1 s2 s3 w1 w2 w3 r1 r2 r3 n2 n3 det |
	n <= 1 ifTrue: [^a1].
	n = 2 ifTrue: [^v1 - v0 - a1].
	s1 := s2 := s3 := w1 := w2 := w3 := 0.
	1 to: n do: [:i | | w |
		w := n + 1 - i.
		s1 := s1 + i. s2 := s2 + (i * i). s3 := s3 + (i * i * i).
		w1 := w1 + (w * i). w2 := w2 + (w * i * i). w3 := w3 + (w * i * i * i)].
	r1 := v1 - v0 - (a0 * n).
	r2 := x1 - x0 - (v0 * n) - (a0 * (n * (n + 1) / 2)).
	r3 := a1 - a0.
	n2 := n * n. n3 := n2 * n.
	det := (s1 * (w2 * n3 - (w3 * n2))) - (s2 * (w1 * n3 - (w3 * n))) + (s3 * (w1 * n2 - (w2 * n))).
	^a0 + (((r1 * (w2 * n3 - (w3 * n2))) - ((r2 * n3 - (r3 * w3)) * s2) + ((r2 * n2 - (r3 * w2)) * s3)
		+ ((r2 * n3 - (r3 * w3)) * s1) - (r1 * (w1 * n3 - (w3 * n))) + ((r3 * w1 - (r2 * n)) * s3)
		+ ((r3 * w2 - (r2 * n2)) * s1) - ((r3 * w1 - (r2 * n)) * s2) + (r1 * (w1 * n2 - (w2 * n)))) / det)
! !

!JugglerHand class methodsFor: 'the cup'!
bowlRadius
	^15
!
rimAngle
	"How far the rim is from the bottom of the bowl, seen from its centre."
	^1.57
! !
