ToolPane subclass: #ShannonJuggler
	instanceVariableNames: 'stage hands balls frame animation'
	classVariableNames: ''
	package: 'Tools'!

ShannonJuggler comment: 'I am Claude''s Robot, modelled on Claude Shannon''s bounce-juggling machine (the W. C. Fields figure, top hat and cigar): two arms carry three balls in cups, tip them out onto a drum, and catch them as they bounce up on the other side. A simulation, per frame (step, in my window''s Process): the arms move the cups (moveHand:, following the act''s cycle on smooth paths: each frame an arm takes the path to where its cup should be a few frames on on which the acceleration changes smoothly; for a catch the cup meets the ball on its way down moving with it, intercept:, then gives with it and carries it up and out to the next drop in one loop, pathFor:at:), then every ball moves (move:): gravity, then in substeps its contacts with the cups (lined bowls: little bounce, much friction), the other balls, the drumhead and the walls. Fixed steps and no randomness, so the act is the same every run. A click restarts it.

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
	[frame < (self beat + 4)] whileTrue: [
		frame = (self beat - 12) ifTrue: [
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
	^Color r: 0.8 g: 0.3 b: 0.4
!
drum
	"The drumhead is the top edge."
	^160 @ 380 corner: 320 @ 430
!
beat
	"Frames from one drop to the next (they alternate between the hands)."
	^46
!
releasePoint
	"Where the left hand tips its ball out towards the drum (the right one mirrored), gliding inwards at releaseSpeed."
	^90 @ 200
!
releaseSpeed
	^2.4
!
releaseTilt
	^2.2
!
catchHeight
	"Where a ball is caught on its way down, after the top of its bounce."
	^280
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
	"The arm moves the cup on smooth paths, from wherever it is and however it moves: tip the ball out on the beat, meet the next one where it comes down, slow down with it, carry it up to the next drop."
	| phase ball s |
	phase := frame - aHand offset \\ (2 * self beat).
	ball := balls detect: [:each | aHand holds: each] ifNone: [nil].
	aHand noteHolding: ball at: frame.
	phase = (2 * self beat - 8) ifTrue: [aHand dropping: (ball notNil and: [frame - aHand caughtAt >= (self carryTimeFor: aHand)])].
	s := phase < 24 ifTrue: [phase] ifFalse: [phase - (2 * self beat)].
	ball isNil ifTrue: [self planCatchFor: aHand].
	(aHand isDropping and: [s >= -8 and: [s < 24 and: [ball notNil or: [frame - aHand releasedAt < self clearFrames]]]]) ifTrue: [
		^self follow: aHand holding: ball notNil tilt: (self ease: ((s + 8 / 6 min: 1) max: 0)) * self releaseTilt * (aHand isLeft ifTrue: [1] ifFalse: [-1])].
	(self intercepting: aHand) ifTrue: [^self intercept: aHand].
	ball isNil ifTrue: [^self wait: aHand].
	self follow: aHand holding: true tilt: 0
!
glideAt: s
	"The cup's glide to the drop, s frames from it: from rest releaseSpeed * 4 before the release point, through it at releaseSpeed, on until the ball has rolled out: {how far in. how fast. how it speeds up}."
	| v x |
	v := self releaseSpeed.
	s <= -8 ifTrue: [^Array with: -4 * v with: 0 with: 0].
	s <= 0 ifTrue: [
		x := s + 8 / 8.
		^Array with: (x * x * x * x * (x * x - (3 * x) + 2.5) * 8 - 4 * v) with: (self smooth: x) * v with: (self smoothSlope: x) * v / 8].
	^Array with: v * s with: v with: 0
!
wait: aHand
	"No ball: stay a moment where the glide ended, out of the way of the ball just dropped; then, until the next ball to catch is known, wait below the place where it usually comes down on this side."
	| at |
	at := frame - aHand releasedAt < self clearFrames
		ifTrue: [aHand position]
		ifFalse: [(self catchPointFor: aHand) + (((aHand isLeft ifTrue: [-30] ifFalse: [30])) @ 25)].
	aHand steerTo: at velocity: 0 @ 0 acceleration: 0 @ 0 in: 12 tilt: 0
!
planCatchFor: aHand
	"Once the next ball to come down on aHand's side is known, plan to meet it (intercept:)."
	| aim |
	frame > aHand caughtAt ifFalse: [^self].
	aim := self catchFor: aHand.
	aim isNil ifFalse: [self plan: aHand toMeet: aim last in: aim first]
!
intercepting: aHand
	"Whether aHand is on its way to meet the ball it will catch next."
	^frame <= aHand caughtAt and: [frame - aHand releasedAt >= self clearFrames]
!
intercept: aHand
	"To where the catch begins, a little up the ball's way, as if to arrive there at rest (meetStartFrom:velocity:); from there (heading on a few frames before it gets there, so as not to stop dead) to the catch, speeding up with the ball until it moves as fast and speeds up as gravity does."
	| s n |
	s := self meetFrames.
	n := aHand caughtAt - frame + 1.
	n > (s + 3) ifFalse: [
		^aHand steerTo: aHand caughtPosition velocity: aHand caughtVelocity acceleration: 0 @ 0.4 in: n tilt: aHand caughtTilt].
	aHand steerTo: (self meetStartFrom: aHand caughtPosition velocity: aHand caughtVelocity) velocity: 0 @ 0 acceleration: 0 @ 0.4 in: n - s tilt: aHand caughtTilt
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
	"Where the cup waits, at rest, to catch a ball at aPoint meetFrames later, moving at aVelocity: from there it speeds up with gravity and more, then just with gravity again, so that the ball comes to lie in the bowl without a knock."
	| s g |
	s := self meetFrames.
	g := 0 @ 0.4.
	^aPoint - (g * (s * (s + 1) / 2)) - (aVelocity - (g * s) * ((s + 2) / 2))
!
meetFrames
	"For how many frames before a catch the cup speeds up with the ball."
	^8
!
clearFrames
	"For how many frames after a ball has left it the cup stays out of its way."
	^2
!
catchPointFor: aHand
	"Where the cup usually waits for a ball."
	^self place: 110 @ (self catchHeight + (JugglerHand bowlRadius - JugglerBall radius)) for: aHand
!
follow: aHand holding: aBoolean tilt: anAngle
	"Along the path the cup takes with a ball (pathFor:at:), or on its glide once the ball is gone, looking a few frames ahead."
	| ahead at |
	ahead := 6.
	at := aBoolean
		ifTrue: [self pathFor: aHand at: frame + ahead - 1]
		ifFalse: [
			(self glideAt: frame + ahead - 1 - aHand offset + 24 \\ (2 * self beat) - 24) collect: [:each | (each * (aHand isLeft ifTrue: [1] ifFalse: [-1])) @ 0]].
	aBoolean ifFalse: [at at: 1 put: (self place: self releasePoint for: aHand) + at first].
	aHand steerTo: at first velocity: (at at: 2) acceleration: at last in: ahead tilt: anAngle
!
pathFor: aHand at: f
	"Where the cup with a ball should be after frame f, how fast it goes and how it speeds up: on from the catch, slowing down outwards to the start of the glide and on in the glide; meanwhile giving with the ball, then up, quickly at first, then slowing gently (well below the pull of gravity, so the ball stays down in the cup), to the release point's height as the cup passes it (lift:from:at:)."
	| t across start end inward x up s |
	t := f - aHand caughtAt.
	across := self carryTimeFor: aHand.
	start := aHand caughtPosition.
	end := self place: self releasePoint - ((4 * self releaseSpeed) @ 0) for: aHand.
	inward := aHand isLeft ifTrue: [1] ifFalse: [-1].
	t < across
		ifTrue: [x := self quintic: (Array with: start x with: aHand caughtVelocity x with: 0) to: (Array with: end x with: 0 with: 0) in: across at: t]
		ifFalse: [
			s := f - aHand offset + 24 \\ (2 * self beat) - 24.
			x := (self glideAt: s) collect: [:each | each * inward].
			x at: 1 put: x first + (self place: self releasePoint for: aHand) x].
	up := self lift: (self carryFor: aHand) last from: aHand caughtVelocity y at: t.
	^Array
		with: x first @ (start y - up first)
		with: (x at: 2) @ (up at: 2) negated
		with: x last @ up last negated
!
carryTimeFor: aHand
	"Frames from the catch to the start of the glide."
	^(self carryFor: aHand) first
!
carryFor: aHand
	"How aHand carries the ball it caught: {frames from the catch to the start of the glide. how the lift speeds up in each frame (liftShape:from:in:)}; a ball caught too late to be lifted gently in time is carried on to the drop after. Worked out once for each catch."
	| d h shape |
	(aHand carry notNil and: [aHand carry first = aHand caughtAt]) ifTrue: [^aHand carry allButFirst].
	d := 2 * self beat - 8 - (aHand caughtAt - aHand offset) \\ (2 * self beat).
	h := aHand caughtPosition y - self releasePoint y.
	shape := self liftShape: h from: aHand caughtVelocity y in: d + 8.
	(d >= 0 and: [self liftFits: shape]) ifFalse: [
		d := d + (2 * self beat).
		shape := self liftShape: h from: aHand caughtVelocity y in: d + 8].
	aHand carry: (Array with: aHand caughtAt with: d with: shape).
	^Array with: d with: shape
!
lift: shape from: speed at: t
	"Rising from coming down at speed to rest, the acceleration changing smoothly, as shape has it (liftShape:from:in:): {how far up after frame t. how fast. how it speeds up}."
	| y v |
	y := 0.
	v := speed negated.
	1 to: (t min: shape size) do: [:i | v := v + (shape at: i). y := y + v].
	^Array with: y with: v with: ((t between: 1 and: shape size) ifTrue: [shape at: t] ifFalse: [0])
!
liftShape: height from: speed in: duration
	"How the lift (lift:from:at:) speeds up in each frame, for a ball caught height below the release point, coming down at speed: up evenly, with smooth ends, as briefly as the arm can push, then down evenly, with smooth ends, for the rest."
	| up down fast pulse even |
	up := 2.
	[up := up + 1.
	 down := duration - up.
	 fast := height + (speed * duration) - (speed * (duration + 1 - (up + 1 / 2))) / (duration + 1 - (up + 1 / 2) - (down + 1 / 2)).
	 up < (duration - 4) and: [fast + speed / (up - (up // 3 min: 4)) > 1.35]] whileTrue.
	pulse := self evenPulse: up.
	even := self evenPulse: down.
	^(pulse collect: [:each | each * (fast + speed)]) , (even collect: [:each | each * fast negated])
!
evenPulse: frames
	"A pulse over frames adding up to 1: even, rising and falling smoothly over a few frames at its ends."
	| r pulse sum |
	r := (frames // 3 min: 4) max: 1.
	pulse := (1 to: frames) collect: [:k |
		k <= r
			ifTrue: [1 - (k - 0.5 / r * Float pi) cos / 2]
			ifFalse: [k > (frames - r) ifTrue: [1 - (frames - k + 0.5 / r * Float pi) cos / 2] ifFalse: [1]]].
	sum := pulse inject: 0 into: [:a :b | a + b].
	^pulse collect: [:each | each / sum]
!
liftFits: shape
	"Whether the cup can carry a ball so (liftShape:from:in:): speeding up no harder than the arm can, slowing down well below the pull of gravity."
	shape size < 8 ifTrue: [^false].
	^(shape inject: 0 into: [:m :each | m max: each]) <= 1.45 and: [(shape inject: 0 into: [:m :each | m min: each]) >= -0.3]
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
!
quintic: from to: to in: duration at: t
	"On the smooth path (the position a quintic in time) from {position. velocity. acceleration} to another in duration frames: the one after t frames."
	| p0 v0 a0 p1 v1 a1 c3 c4 c5 u |
	p0 := from first. v0 := (from at: 2) * duration. a0 := from last * duration * duration.
	p1 := to first. v1 := (to at: 2) * duration. a1 := to last * duration * duration.
	c3 := (p1 - p0 * 20) - (v1 * 8) - (v0 * 12) - (a0 * 3) + a1 / 2.
	c4 := (p0 - p1 * 30) + (v1 * 14) + (v0 * 16) + (a0 * 3) - (a1 * 2) / 2.
	c5 := (p1 - p0 * 12) - (v1 + v0 * 6) - a0 + a1 / 2.
	u := t / duration.
	^Array
		with: p0 + (v0 * u) + (a0 / 2 * u * u) + (c3 * u * u * u) + (c4 * u * u * u * u) + (c5 * u * u * u * u * u)
		with: v0 + (a0 * u) + (c3 * 3 * u * u) + (c4 * 4 * u * u * u) + (c5 * 5 * u * u * u * u) / duration
		with: a0 + (c3 * 6 * u) + (c4 * 12 * u * u) + (c5 * 20 * u * u * u) / (duration * duration)
!
smooth: x
	"From 0 to 1 as x goes from 0 to 1, starting and ending at rest, without a jolt."
	^x * x * x * (x * (x * 6 - 15) + 10)
!
smoothSlope: x
	^x * x * (x * (x * 30 - 60) + 30)
! !

!ShannonJuggler methodsFor: 'contacts'!
drumRestitution
	^1
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
	aHand knock: (vn negated min: vn negated + ((0 @ 0.4) - aHand acceleration dotProduct: n)).
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
	"The drumhead throws a ball that comes down on it back up."
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
