ToolPane subclass: #ShannonJuggler
	instanceVariableNames: 'stage hands flying frame animation'
	classVariableNames: ''
	package: 'Tools'!

ShannonJuggler comment: 'I am Claude''s Robot, modelled on Claude Shannon''s bounce-juggling machine (the W. C. Fields figure, top hat and cigar): two hands toss three balls down onto a drum; each bounces up into the other hand. step runs in my window''s Process every compositor frame: the hands follow their path and throw on their beat, the balls in the air fly (move: gravity and the bounces), the hands catch. Everything is counted in frames, so the act repeats exactly. A click puts the balls back into the hands.

My JugglerStage draws what it reads from me: stageExtent, drum, hands (each: position, isLeft, balls), balls (each: position), ballColor, frame.'!

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
	"The start of the act: two balls in the left hand, one in the right."
	frame := 0.
	flying := OrderedCollection new.
	hands do: [:each |
		each balls removeAll: each balls copy.
		each position: (self place: self throwPoint for: each)].
	hands first balls add: JugglerBall new; add: JugglerBall new.
	hands last balls add: JugglerBall new.
	hands do: [:each | self hold: each]
!
minimumWindowExtent
	^240 @ 220
! !

!ShannonJuggler methodsFor: 'accessing'!
hands
	^hands
!
flying
	^flying
!
balls
	^(hands inject: flying asArray into: [:all :each | all, each balls asArray])
!
frame
	^frame
! !

!ShannonJuggler methodsFor: 'the act'!
stageExtent
	^480 @ 440
!
ballColor
	^Color black
!
drum
	"The drumhead is the top edge."
	^160 @ 380 corner: 320 @ 430
!
beat
	"Frames from one throw to the next (they alternate between the hands)."
	^24
!
catchPhase
	"Frames after its own throw at which a hand catches the ball the other one threw."
	^29
!
throwPoint
	"Where the left hand throws, and the velocity: down and across, so the ball bounces off the drum into the right hand."
	^190 @ 280
!
throwVelocity
	^4 @ 7
!
catchPoint
	^74 @ 262
!
drumHead
	"The height of a ball's centre when it touches the drumhead."
	^self drum top - JugglerBall radius
!
drumHit: from to: to
	"Does a ball moving from from to to hit the drumhead?"
	^(to x between: self drum left and: self drum right) and: [from y <= self drumHead and: [to y > self drumHead]]
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
! !

!ShannonJuggler methodsFor: 'animation'!
start
	animation := self window requestAnimationFrames: [:ms |
		self step.
		stage invalidate.
		true]
!
step
	"One frame: the hands move and throw, the balls in the air fly, the hands catch."
	hands do: [:each | self moveHand: each].
	flying do: [:each | self move: each].
	hands do: [:each | self catchWith: each].
	frame := frame + 1
!
move: aBall
	"Gravity pulls the ball down; it bounces off the drumhead, and dully off the walls."
	| p v |
	v := aBall velocity + (0 @ 0.4).
	p := aBall position + v.
	(self drumHit: aBall position to: p) ifTrue: [v := v x @ v y negated. p := p x @ (2 * self drumHead - p y)].
	(p x < self left or: [p x > self right]) ifTrue: [v := v x negated / 2 @ v y].
	(p y < self top or: [p y > self bottom]) ifTrue: [v := v x / 2 @ (v y negated / 2)].
	aBall velocity: v.
	aBall position: ((p max: self left @ self top) min: self right @ self bottom)
!
moveHand: aHand
	"The hand follows its path; at the start of its beat it throws a ball."
	| phase |
	phase := frame - aHand offset \\ (2 * self beat).
	aHand position: (self place: (self handAt: phase) for: aHand).
	self hold: aHand.
	(phase = 0 and: [aHand balls notEmpty]) ifTrue: [
		flying add: (aHand balls removeFirst
			velocity: (aHand isLeft ifTrue: [self throwVelocity] ifFalse: [self throwVelocity x negated @ self throwVelocity y]);
			yourself)]
!
catchWith: aHand
	"At its catch, the hand takes a falling ball that comes within reach."
	| phase cup |
	phase := frame - aHand offset \\ (2 * self beat).
	(phase between: self catchPhase and: self catchPhase + 3) ifFalse: [^self].
	cup := aHand position - (0 @ JugglerBall radius).
	(flying select: [:b | b velocity y > 0 and: [(b position dist: cup) < 16]]) do: [:b |
		flying remove: b.
		aHand balls add: b].
	self hold: aHand
!
hold: aHand
	"The balls a hand holds sit in its cup."
	aHand balls doWithIndex: [:b :i | b position: aHand position - (0 @ (2 * i - 1 * JugglerBall radius))]
!
handAt: phase
	"The left hand's cup, phase frames after its throw: out and up to the catch, then carrying the ball in and down to the next throw."
	| t |
	phase < self catchPhase ifTrue: [
		^self throwPoint + ((self catchPoint - self throwPoint) * (self ease: phase / self catchPhase))].
	t := phase - self catchPhase / (2 * self beat - self catchPhase).
	^self catchPoint + ((self throwPoint - self catchPoint) * (self ease: t)) + (0 @ ((t * Float pi) sin * 14))
!
ease: t
	^1 - (t * Float pi) cos / 2
!
windowClosed
	animation isNil ifFalse: [animation stop]
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
