ToolPane subclass: #ShannonJuggler
	instanceVariableNames: 'stage hands balls frame animation'
	classVariableNames: ''
	package: 'Tools'!

ShannonJuggler comment: 'I am Claude''s Robot, modelled on Claude Shannon''s bounce-juggling machine (the W. C. Fields figure, top hat and cigar): two arms carry three balls in cups, tip them out onto a drum, and catch them as they bounce up on the other side. A simulation, per frame (step, in my window''s Process): the arms drive the cups (moveHand:, following the act''s cycle; for a catch the cup meets the ball on its way down moving with it, then slows down with it: intercept:), then every ball moves (move:): gravity, then in substeps its contacts with the cups (lined bowls: little bounce, much friction), the other balls, the drumhead and the walls. Fixed steps and no randomness, so the act is the same every run. A click restarts it.

My JugglerStage draws what it reads from me: stageExtent, drum, hands (each: position (the centre of its bowl), tilt, isLeft), balls (each: position, velocity), JugglerBall radius, JugglerHand bowlRadius and rimAngle, ballColor, frame.'!

!ShannonJuggler methodsFor: 'initialization'!
initialize
	super initialize.
	stage := JugglerStage new juggler: self; name: 'stage'; yourself.
	hands := Array
		with: (JugglerHand new left: true offset: 0; yourself)
		with: (JugglerHand new left: false offset: self beat; yourself).
	self restart.
	self add: stage
!
restart
	"The act from the top: the left cup glides in to tip out a ball, the right one waits with another; a third ball goes into the left cup once it is back; run on until all three are under way."
	| first |
	frame := -8.
	hands first place: self releasePoint - ((4 * self releaseSpeed) @ 0).
	hands last place: (self catchPointFor: hands last).
	first := JugglerBall new position: (self restingPlaceIn: hands first); velocity: 0 @ 0; yourself.
	hands first noteHolding: first at: frame; catchAt: -1000 position: hands first position velocity: 0 @ 0 tilt: 0.
	hands last catchAt: frame position: hands last position velocity: 0 @ 0 tilt: 0.
	balls := OrderedCollection with: first with: (JugglerBall new position: (self restingPlaceIn: hands last); velocity: 0 @ 0; yourself).
	[frame < 48] whileTrue: [
		frame = 32 ifTrue: [
			balls add: (JugglerBall new position: (self restingPlaceIn: hands first); velocity: hands first velocity; yourself).
			hands first catchAt: frame position: hands first position velocity: 0 @ 0 tilt: 0].
		self step]
!
minimumWindowExtent
	^240 @ 220
! !

!ShannonJuggler methodsFor: 'accessing'!
hands
	^hands
!
balls
	^balls
!
flying
	"The balls in no cup."
	^balls reject: [:each | hands anySatisfy: [:h | h holds: each]]
!
frame
	^frame
! !

!ShannonJuggler methodsFor: 'the act'!
stageExtent
	^480 @ 440
!
ballColor
	^Color r: 1.0 g: 0.75 b: 0.1
!
drum
	"The drumhead is the top edge."
	^160 @ 380 corner: 320 @ 430
!
beat
	"Frames from one drop to the next (they alternate between the hands)."
	^44
!
releasePoint
	"Where the left hand tips its ball out towards the drum (the right one mirrored), gliding inwards at releaseSpeed."
	^70 @ 200
!
releaseSpeed
	^3
!
releaseTilt
	^2.2
!
catchHeight
	"Where a ball is caught on its way down, after the top of its bounce."
	^290
!
substeps
	^4
!
drumHead
	"The height of a ball's centre when it touches the drumhead."
	^self drum top - JugglerBall radius
!
left
	"The walls, for a ball's centre."
	^JugglerBall radius
!
right
	^self stageExtent x - JugglerBall radius
!
top
	^JugglerBall radius
!
bottom
	^self stageExtent y - JugglerBall radius
!
place: aPoint for: aHand
	"aPoint of the left hand, mirrored for the right one."
	^aHand isLeft ifTrue: [aPoint] ifFalse: [self stageExtent x - aPoint x @ aPoint y]
!
restingPlaceIn: aHand
	"Where a ball lies at rest in aHand's level cup."
	^aHand position + (0 @ (JugglerHand bowlRadius - JugglerBall radius))
! !

!ShannonJuggler methodsFor: 'animation'!
start
	animation := self window requestAnimationFrames: [:ms |
		self step.
		stage invalidate.
		true]
!
step
	"One frame: the arms move the cups, then the balls move: gravity, and the cups, the drum, each other, the walls."
	hands do: [:each | self moveHand: each].
	balls do: [:each | self move: each].
	frame := frame + 1
!
move: aBall
	"Gravity pulls the ball down; then, in small steps, it rolls in the cups and bounces off the drumhead, the other balls and the walls."
	| last |
	aBall velocity: aBall velocity + (0 @ 0.4).
	1 to: self substeps do: [:i |
		last := aBall position.
		aBall position: last + (aBall velocity / self substeps).
		hands do: [:each | self collide: aBall withCupOf: each at: i / self substeps].
		balls do: [:each | each == aBall ifFalse: [self collide: aBall with: each]].
		self bounce: aBall offDrumFrom: last.
		self bounceOffWalls: aBall]
!
windowClosed
	animation isNil ifFalse: [animation stop]
! !

!ShannonJuggler methodsFor: 'arms'!
moveHand: aHand
	"The arm drives the cup towards where it should be now: tip the ball out on the beat, meet the next one where it comes down, slow down with it, carry it up to the next drop."
	| phase ball goal |
	phase := frame - aHand offset \\ (2 * self beat).
	ball := balls detect: [:each | aHand holds: each] ifNone: [nil].
	aHand noteHolding: ball at: frame.
	ball isNil ifTrue: [self planCatchFor: aHand].
	phase = (2 * self beat - 8) ifTrue: [aHand dropping: (ball notNil and: [frame - aHand caughtAt >= (self cushionFrames + (self carryTimeFor: aHand) - 1)])].
	goal := (aHand isDropping and: [phase >= (2 * self beat - 8) or: [phase < 10 or: [phase < 24 and: [ball notNil]]]])
		ifTrue: [self releaseGoalFor: aHand at: (phase < 24 ifTrue: [phase] ifFalse: [phase - (2 * self beat)])]
		ifFalse: [
			(self intercepting: aHand) ifTrue: [^self intercept: aHand].
			ball isNil
				ifTrue: [self catchGoalFor: aHand at: phase]
				ifFalse: [self carryGoalFor: aHand at: phase]].
	aHand driveTo: goal first velocity: (goal at: 2) tilt: goal last
!
releaseGoalFor: aHand at: s
	"s frames from the drop: the cup starts gliding inwards, through the release point at releaseSpeed, tipping over towards the drum; the ball rolls out over the rim. A ball caught too late to have settled stays in the cup for another round."
	| inward v x dx |
	inward := aHand isLeft ifTrue: [1] ifFalse: [-1].
	v := self releaseSpeed.
	x := (s min: 10) max: -8.
	dx := x < 0 ifTrue: [v * (x + 8) squared / 16 - (4 * v)] ifFalse: [v * x].
	^Array
		with: (self place: self releasePoint for: aHand) + ((dx * inward) @ 0)
		with: ((x < 0 ifTrue: [v * (x + 8) / 8] ifFalse: [s < 10 ifTrue: [v] ifFalse: [0]]) * inward) @ 0
		with: (aHand isDropping ifTrue: [(self ease: ((s + 8 / 6 min: 1) max: 0)) * self releaseTilt * inward] ifFalse: [0])
!
catchGoalFor: aHand at: phase
	"After a drop: stay up a moment, out of the way of the ball just dropped; then, until the next ball to catch is known, wait below the place where it usually comes down on this side."
	frame - aHand releasedAt < self clearFrames ifTrue: [
		^Array with: (self place: self releasePoint + ((10 * self releaseSpeed) @ 0) for: aHand) with: 0 @ 0 with: 0].
	^Array
		with: (self catchPointFor: aHand) + (((aHand isLeft ifTrue: [-30] ifFalse: [30])) @ 25)
		with: 0 @ 0
		with: 0
!
planCatchFor: aHand
	"Once the next ball to come down on aHand's side is known, plan to meet it (intercept:)."
	| aim |
	aHand caughtAt + self cushionFrames < frame ifFalse: [^self].
	aim := self catchFor: aHand.
	aim isNil ifFalse: [self plan: aHand toMeet: aim last in: aim first]
!
intercepting: aHand
	"Whether aHand is on its way to meet the ball it will catch next."
	^frame <= aHand caughtAt and: [frame - aHand releasedAt >= self clearFrames]
!
intercept: aHand
	"Steer the cup to where the catch begins, a little up the ball's way, to arrive there at rest (meetStartFrom:velocity:); from there to the catch, speeding up with the ball until it moves as fast. Each frame the arm takes the path from where the cup is now, and how fast it goes, on which it speeds up evenly more or less."
	| s n target speed dv dx b |
	s := self meetFrames.
	n := aHand caughtAt - frame + 1.
	n > s
		ifTrue: [
			n := n - s.
			target := self meetStartFrom: aHand caughtPosition velocity: aHand caughtVelocity.
			speed := 0 @ 0]
		ifFalse: [
			target := aHand caughtPosition.
			speed := aHand caughtVelocity].
	dv := speed - aHand velocity.
	n <= 1 ifTrue: [^aHand accelerate: dv tilt: aHand caughtTilt].
	dx := target - aHand position - (aHand velocity * n).
	b := (dv * ((n + 1) / 2) - dx) * (12 / (n * (n * n - 1))).
	aHand accelerate: dv / n - (b * ((n - 1) / 2)) tilt: aHand caughtTilt
!
plan: aHand toMeet: aBall in: frames
	"aBall comes down through the catch height in frames; the cup will meet it there (or further down, if it could not be up its way in time), moving with it, its opening turned towards where it comes from in the cup's view."
	| wait k at speed approach tilt |
	wait := self clearFrames - (frame - aHand releasedAt) max: 0.
	k := frames ceiling max: 1.
	[at := aBall position + (aBall velocity * k) + (0 @ (0.2 * k * (k + 1))).
	 speed := aBall velocity + (0 @ (0.4 * k)).
	 approach := speed - (0 @ (0.4 * self meetFrames)).
	 tilt := ((approach x negated arcTan: approach y) max: -0.9) min: 0.9.
	 at := at - ((tilt sin negated @ tilt cos) * (JugglerHand bowlRadius - JugglerBall radius)).
	 k < (frames + 24) and: [k - self meetFrames - wait < ((((self meetStartFrom: at velocity: speed) dist: aHand position) / 2.5) sqrt * 2)]]
		whileTrue: [k := k + 1].
	aHand catchAt: frame + k - 1 position: at velocity: speed tilt: tilt
!
meetStartFrom: aPoint velocity: aVelocity
	"Where the cup waits, at rest, to catch a ball at aPoint meetFrames later, moving at aVelocity: from there it speeds up evenly less, at the end as the ball does, so that the ball comes to lie in the bowl without a knock."
	| s |
	s := self meetFrames.
	^aPoint - (0 @ (0.2 * s * (s + 1))) - ((aVelocity - (0 @ (0.4 * s))) * (2 * (s + 1) / 3))
!
cushionGoalFor: aHand
	"Just caught: the cup slows down with the ball, the bowl coming level."
	| t d |
	d := self cushionFrames.
	t := frame - aHand caughtAt min: d.
	^Array
		with: aHand caughtPosition + (aHand caughtVelocity * (t - (t * t / (2 * d))))
		with: aHand caughtVelocity * (1 - (t / d))
		with: aHand caughtTilt * (1 - (t / d))
!
meetFrames
	"For how many frames before a catch the cup speeds up with the ball."
	^8
!
cushionFrames
	"For how many frames after a catch the cup slows down with the ball."
	^6
!
clearFrames
	"For how many frames after a ball has left it the cup stays out of its way."
	^4
!
catchPointFor: aHand
	"Where the cup usually waits for a ball."
	^self place: 110 @ (self catchHeight + (JugglerHand bowlRadius - JugglerBall radius)) for: aHand
!
carryGoalFor: aHand at: phase
	"Just caught: slow down with the ball (cushionGoalFor:); then carry it to where the cup starts its glide to the drop: up quickly, then slowing gently (well below the pull of gravity), so it stays in the cup."
	| since d u start end duration t a |
	since := frame - aHand caughtAt.
	d := self cushionFrames.
	since <= d ifTrue: [^self cushionGoalFor: aHand].
	start := self cushionEndFor: aHand.
	end := (self place: self releasePoint - ((4 * self releaseSpeed) @ 0) for: aHand).
	duration := self carryTimeFor: aHand.
	t := since - d min: duration.
	u := t / duration.
	a := self lift: start y - end y in: duration at: t.
	^Array
		with: ((start x * (2 * u * u * u - (3 * u * u) + 1)) + (end x * (3 * u * u - (2 * u * u * u)))) @ (start y - a first)
		with: (start x - end x * (6 * u * u - (6 * u)) / duration) @ a last negated
		with: 0
!
cushionEndFor: aHand
	"Where the cup comes to rest after a catch."
	^aHand caughtPosition + (aHand caughtVelocity * (self cushionFrames / 2))
!
carryTimeFor: aHand
	"Frames from the end of the cushioning to the start of the glide; a ball caught too late to be lifted gently in time is carried on to the drop after."
	| d h |
	d := 2 * self beat - 8 - ((aHand caughtAt - aHand offset \\ (2 * self beat)) + self cushionFrames).
	h := (self cushionEndFor: aHand) y - self releasePoint y max: 0.
	d * d < (2 * h / 0.2) ifTrue: [d := d + (2 * self beat)].
	^d
!
lift: height in: duration at: t
	"Rising by height in duration frames, from rest to rest: speeding up quickly, slowing down gently (well below the pull of gravity, so the ball stays down in the cup): {how far up at t. how fast}."
	| v t1 fast slow |
	height <= 0 ifTrue: [^Array with: 0 with: 0].
	v := 2 * height / duration.
	t1 := duration - (v / 0.25) max: duration / 6.
	fast := v / t1.
	slow := v / (duration - t1).
	t < t1 ifTrue: [^Array with: fast * t * t / 2 with: fast * t].
	^Array
		with: (fast * t1 * t1 / 2) + (v * (t - t1)) - (slow * (t - t1) squared / 2)
		with: v - (slow * (t - t1))
!
catchFor: aHand
	"The first ball that bounced off the drum and will come down on aHand's side: {frames until it comes down through the catch height. the ball}, or nil."
	| best |
	balls do: [:each |
		(each bounced and: [(hands anySatisfy: [:h | h holds: each]) not]) ifTrue: [
			(self descentOf: each to: self catchHeight) ifNotNil: [:hit |
				(hit first < (self stageExtent x / 2)) = aHand isLeft ifTrue: [
					(best isNil or: [(hit at: 3) < best first]) ifTrue: [best := Array with: (hit at: 3) with: each]]]]].
	^best
!
descentOf: aBall to: height
	"Where and when aBall, flying freely, will come down through height after its bounce off the drumhead: {x. x velocity. frames}, or nil."
	| g x y vx vy t root |
	g := 0.4.
	x := aBall position x. y := aBall position y.
	vx := aBall velocity x. vy := aBall velocity y.
	t := 0.
	aBall bounced ifFalse: [
		y > self drumHead ifTrue: [^nil].
		t := vy negated + (vy * vy + (2 * g * (self drumHead - y))) sqrt / g.
		x := x + (vx * t).
		(x between: self drum left and: self drum right) ifFalse: [^nil].
		vy := (vy + (g * t)) negated * self drumRestitution.
		y := self drumHead].
	root := vy * vy + (2 * g * (height - y)).
	(root < 0 or: [y > height and: [vy > 0]]) ifTrue: [^Array with: x with: vx with: t].
	root := vy negated + root sqrt / g.
	^Array with: x + (vx * root) with: vx with: t + root
!
ease: t
	^1 - (t * Float pi) cos / 2
! !

!ShannonJuggler methodsFor: 'contacts'!
drumRestitution
	^0.95
!
collide: aBall withCupOf: aHand at: s
	"The cup is a bowl, open at the top within its rim: inside, the ball lies on its wall; it can roll out over the rim; outside, it bounces off."
	| c down d dist rimCos q |
	c := aHand positionAt: s.
	down := aHand downAt: s.
	d := aBall position - c.
	dist := d r.
	rimCos := JugglerHand rimAngle cos.
	(dist < JugglerHand bowlRadius and: [(d dotProduct: down) > (dist * rimCos)])
		ifTrue: [
			dist > (JugglerHand bowlRadius - JugglerBall radius) ifTrue: [
				self push: aBall to: c + (d * ((JugglerHand bowlRadius - JugglerBall radius) / dist)) normal: d negated / dist hand: aHand restitution: 0.3]]
		ifFalse: [
			(dist >= JugglerHand bowlRadius and: [(d dotProduct: down) > (dist * rimCos) and: [dist < (JugglerHand bowlRadius + 2 + JugglerBall radius)]]) ifTrue: [
				self push: aBall to: c + (d * ((JugglerHand bowlRadius + 2 + JugglerBall radius) / dist)) normal: d / dist hand: aHand restitution: 0.4]].
	#(-1 1) do: [:side |
		q := c + ((aHand rimDirection: side at: s) * JugglerHand bowlRadius).
		d := aBall position - q.
		dist := d r.
		(dist < JugglerBall radius and: [dist > 0]) ifTrue: [
			self push: aBall to: q + (d * (JugglerBall radius / dist)) normal: d / dist hand: aHand restitution: 0.3]]
!
push: aBall to: aPoint normal: n hand: aHand restitution: e
	"Contact with aHand's cup: aBall is put back on its surface; it bounces off (by e) as the cup moves; the friction (the lining) takes away slipping, the more the harder it hits."
	| wall rel vn vt |
	aBall position: aPoint.
	wall := aHand velocityAt: aPoint.
	rel := aBall velocity - wall.
	vn := rel dotProduct: n.
	vn < 0 ifFalse: [^self].
	aHand knock: vn negated + ((0 @ 0.4) - aHand acceleration dotProduct: n).
	vt := rel - (n * vn).
	vt := vt * ((1 - (0.6 * (1 + e) * vn negated / (vt r max: 0.001))) max: 0) * 0.97.
	aBall velocity: wall + vt - (n * (vn * e)).
	aBall bounced: false
!
collide: aBall with: other
	"Two balls that touch are pushed apart and bounce off each other: an impulse along the line between their centres (restitution), friction across it."
	| d dist n rel vn vt j |
	d := aBall position - other position.
	dist := d r.
	(dist < (2 * JugglerBall radius) and: [dist > 0]) ifFalse: [^self].
	n := d / dist.
	aBall position: aBall position + (n * (2 * JugglerBall radius - dist / 2)).
	other position: other position - (n * (2 * JugglerBall radius - dist / 2)).
	rel := aBall velocity - other velocity.
	vn := rel dotProduct: n.
	vn < 0 ifFalse: [^self].
	vt := rel - (n * vn).
	j := n * (vn * (1 + self ballRestitution) / 2) + (vt * ((0.3 * (1 + self ballRestitution) * vn negated / (vt r max: 0.001) min: 1) / 2)).
	aBall velocity: aBall velocity - j.
	other velocity: other velocity + j
!
ballRestitution
	^0.8
!
bounce: aBall offDrumFrom: last
	"The drumhead throws a ball that comes down on it back up, giving a little."
	| p |
	p := aBall position.
	((p x between: self drum left and: self drum right) and: [last y <= self drumHead and: [p y > self drumHead]]) ifFalse: [^self].
	aBall position: p x @ (2 * self drumHead - p y).
	aBall velocity: aBall velocity x @ (aBall velocity y negated * self drumRestitution).
	aBall bounced: true
!
bounceOffWalls: aBall
	"The walls, the ceiling and the floor take half the ball's speed."
	| p v |
	p := aBall position.
	v := aBall velocity.
	(p x < self left or: [p x > self right]) ifTrue: [v := v x negated / 2 @ v y].
	(p y < self top or: [p y > self bottom]) ifTrue: [v := v x / 2 @ (v y negated / 2)].
	aBall velocity: v.
	aBall position: ((p max: self left @ self top) min: self right @ self bottom)
! !

!ShannonJuggler class methodsFor: 'opening'!
openIn: aRectangle
	| view window |
	view := self new.
	window := view openIn: aRectangle title: 'Claude''s Robot'.
	window do: [view start].
	^window
!
initialize
	ToolsMenu register: 'Claude''s Robot' description: 'bounce juggling' order: 58 action: [:point |
		self openIn: (Tools placeAt: point extent: 500 @ 480)]
! !
