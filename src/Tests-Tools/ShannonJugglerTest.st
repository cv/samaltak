ToolsTestCase subclass: #ShannonJugglerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

ShannonJugglerTest comment: 'I test Claude''s Robot: its stage shows the 3D scene rendered on the GPU, it changes while the act runs and stays the same picture once the act halts; the simulation keeps all three balls going for ten minutes of frames without two ever touching, catching each without a knock and letting it go only on the drop, its arms moving smoothly, bounces balls that do touch off each other, is the same every run and keeps its rhythm, restarts the same, and with gravity turned round the balls end up at rest against the ceiling.'!

!ShannonJugglerTest methodsFor: 'support'!
pictureOf: aView
	self settle.
	^world compositor sync: [:c | c screenshotOf: aView scale: 1]
!
run: aJuggler frames: anInteger
	anInteger timesRepeat: [aJuggler step]
!
dropped: aJuggler
	"Whether a ball got away: down on the floor, or against a wall."
	^aJuggler balls anySatisfy: [:each | each position y > 400 or: [each position x < 15 or: [each position x > (aJuggler stageExtent x - 15)]]]
!
isTipping: aHand in: aJuggler
	"Whether aHand tips its ball out in the frame just gone: from its glide towards the release point until the ball has rolled out."
	| phase |
	phase := aJuggler frame - 1 - aHand offset \\ (2 * aJuggler beat).
	^aHand isDropping and: [phase >= (2 * aJuggler beat - 8) or: [phase < 24]]
!
colorsIn: aForm
	"The distinct pixel values in a coarse grid over aForm."
	| seen |
	seen := Set new.
	0 to: aForm height - 1 by: 7 do: [:y |
		0 to: aForm width - 1 by: 7 do: [:x | seen add: (aForm pixelValueAt: x @ y)]].
	^seen size
! !

!ShannonJugglerTest methodsFor: 'tests'!
testRendersAndAnimates
	| w juggler stage first frame halted |
	w := self open: [ShannonJuggler openIn: (100 @ 100 extent: 504 @ 500)].
	juggler := w content.
	stage := juggler widgetNamed: 'stage'.
	self assert: (self waitFor: [juggler frame > 5]) description: 'the act does not run'.
	first := self pictureOf: stage.
	self assert: (self colorsIn: first) > 200 description: 'the stage shows no scene'.
	self assert: (self waitFor: [(self pictureOf: stage) bits ~= first bits] timeout: 3000) description: 'the picture does not change while the act runs'.
	self in: w do: [juggler windowClosed].
	frame := juggler frame.
	halted := self pictureOf: stage.
	(Delay forMilliseconds: 300) wait.
	self assert: juggler frame equals: frame.
	self assert: (self pictureOf: stage) bits = halted bits description: 'a halted act changes its picture'
!
testKeepsJugglingForTenMinutesSoftlyWithoutTheBallsTouching
	"Ten minutes of frames: no ball gets away or comes near another; every ball comes into a cup without a knock and leaves it only when the cup tips it out; the cups move smoothly, their speed and their turn changing without a jolt."
	| juggler closest hardest moves push jolt turn |
	juggler := ShannonJuggler new.
	closest := 1000.
	hardest := push := jolt := turn := 0.
	moves := juggler hands collect: [:each | Array with: each velocity with: 0 @ 0 with: each tilt with: 0].
	36000 timesRepeat: [
		juggler step.
		self deny: (self dropped: juggler) description: 'a ball dropped at frame ', juggler frame printString.
		juggler hands doWithIndex: [:each :i | | m a spin |
			hardest := hardest max: each knock.
			each releasedAt = (juggler frame - 1) ifTrue: [
				self assert: (self isTipping: each in: juggler) description: 'a ball left ', each printString, ' at frame ', each releasedAt printString].
			m := moves at: i.
			a := each velocity - m first.
			spin := each tilt - (m at: 3).
			push := push max: a r.
			jolt := jolt max: (a - (m at: 2)) r.
			turn := turn max: (spin - m last) abs.
			moves at: i put: (Array with: each velocity with: a with: each tilt with: spin)].
		juggler balls doWithIndex: [:a :i |
			juggler balls doWithIndex: [:b :k | k > i ifTrue: [closest := closest min: (a position dist: b position)]]]].
	self assert: juggler balls size equals: 3.
	self assert: closest > (2 * JugglerBall radius + 10) description: 'balls came within ', closest printString.
	self assert: hardest < 1 description: 'a ball hit a cup at ', hardest printString, ' points per frame'.
	self assert: push < 2.5 description: 'a cup sped up by ', push printString, ' points per frame in a frame'.
	self assert: jolt < 1.25 description: 'a cup''s acceleration jumped by ', jolt printString.
	self assert: turn < 0.2 description: 'a cup''s spin jumped by ', turn printString
!
testBallsBounceOffEachOther
	"Two balls flying at each other bounce apart, nothing lost along the line between them but what the restitution takes."
	| juggler a b |
	juggler := ShannonJuggler new.
	a := JugglerBall new position: 100 @ 100; velocity: 3 @ 0; yourself.
	b := JugglerBall new position: 119 @ 100; velocity: -3 @ 0; yourself.
	juggler collide: a with: b.
	self assert: (a position dist: b position) >= (2 * JugglerBall radius - 0.001).
	self assert: a velocity x < 0.
	self assert: b velocity x > 0.
	self assert: (a velocity x + b velocity x) abs < 0.001.
	self assert: (b velocity x - a velocity x - (6 * juggler ballRestitution)) abs < 0.001
!
testSameEveryRunAndInRhythm
	| a b positions |
	a := ShannonJuggler new.
	b := ShannonJuggler new.
	self run: a frames: 2000.
	self run: b frames: 2000.
	self assert: (a balls collect: [:each | each position]) asArray equals: (b balls collect: [:each | each position]) asArray.
	self assert: (a hands collect: [:each | each position]) equals: (b hands collect: [:each | each position]).
	"After three rounds of the hands each ball is about where it was."
	positions := (a balls collect: [:each | each position]) asArray.
	self run: a frames: 6 * a beat.
	a balls doWithIndex: [:each :i | self assert: ((positions at: i) dist: each position) < (2 * JugglerBall radius)]
!
testRestartIsTheSame
	| juggler positions |
	juggler := ShannonJuggler new.
	positions := (juggler balls collect: [:each | each position]) asArray.
	self run: juggler frames: 500.
	juggler restart.
	self assert: (juggler balls collect: [:each | each position]) asArray equals: positions.
	self assert: juggler balls size equals: 3
!
testGravityTurnedRoundSettlesTheBallsAtTheCeiling
	| source juggler |
	source := (ShannonJuggler sourceCodeAt: #move:) asString.
	self assert: (source includesSubstring: 'velocity + (0 @ 0.4).').
	[ShannonJuggler compile: (source copyReplaceAll: '0 @ 0.4' with: '0 @ -0.4') classified: 'animation'.
	 juggler := ShannonJuggler new.
	 self run: juggler frames: 900]
		ensure: [ShannonJuggler compile: source classified: 'animation'].
	juggler balls do: [:each |
		self assert: each position y < (juggler top + 1).
		self assert: each velocity r < 0.5]
! !
