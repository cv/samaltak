TestCase subclass: #AnimationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

AnimationTest comment: 'Tests Animation: easings, interpolation of numbers, points, rectangles and colors, stepping on a clock, whenDone:, stop, frame animations, the slowed-down clock (timeScale:).'!

!AnimationTest methodsFor: 'tests'!
testEasingsMapEndpoints
	Animation easings do: [:e |
		self assert: ((Animation ease: e at: 0) abs < 0.001) description: e.
		self assert: (((Animation ease: e at: 1) - 1) abs < 0.001) description: e].
	self assert: (Animation ease: #easeOutCubic at: 0.5) > 0.5.
	self assert: (Animation ease: #easeInCubic at: 0.5) < 0.5.
	self assert: ((Animation ease: #easeInOutQuad at: 0.5) - 0.5) abs < 0.001.
	"the spring never overshoots"
	self assert: ((0 to: 20) allSatisfy: [:i | (Animation ease: #spring at: i / 20) <= 1.0001])
!
testCubicBezierEasing
	"cubic-bezier(x1, y1, x2, y2): the straight one is linear; Omarchy's Style.easeOut starts at once and settles."
	#(0 0.1 0.25 0.5 0.9 1) do: [:t |
		self assert: ((Animation ease: #(0 0 1 1) at: t) - t) abs < 0.0001].
	self assert: (Animation ease: #(0.23 1.0 0.32 1.0) at: 0) equals: 0.
	self assert: (Animation ease: #(0.23 1.0 0.32 1.0) at: 1) equals: 1.
	self assert: (Animation ease: #(0.23 1.0 0.32 1.0) at: 0.25) > 0.75.
	self assert: ((0 to: 20) allSatisfy: [:i | (Animation ease: #(0.23 1.0 0.32 1.0) at: i / 20) <= 1.0001]).
	"CSS's ease, cubic-bezier(0.25, 0.1, 0.25, 1), is 0.8024 at 0.5"
	self assert: ((Animation ease: #(0.25 0.1 0.25 1.0) at: 0.5) - 0.8024) abs < 0.001
!
testSteppingOnAClock
	| values anim done |
	values := OrderedCollection new.
	anim := Animation from: 10 to: 20 duration: 100 easing: #linear do: [:v | values add: v].
	anim whenDone: [done := true].
	self assert: (anim stepAt: 1000).
	self assert: values last equals: 10.
	self assert: (anim stepAt: 1050).
	self assert: values last equals: 15.
	self deny: (anim stepAt: 1100).
	self assert: values last equals: 20.
	self assert: done == true.
	self assert: anim isFinished.
	self deny: (anim stepAt: 1200).
	self assert: values size equals: 3
!
testInterpolation
	self assert: (Animation interpolate: 0 @ 0 to: 10 @ 20 at: 0.5) equals: 5 @ 10.
	self assert: (Animation interpolate: (0 @ 0 corner: 10 @ 10) to: (10 @ 10 corner: 30 @ 30) at: 0.5) equals: (5 @ 5 corner: 20 @ 20).
	self assert: ((Animation interpolate: Color black to: Color white at: 0.5) red - 0.5) abs < 0.01.
	self assert: (Animation interpolate: 10 to: 20 at: 0.25) equals: 12.5.
	self assert: (3 interpolateTo: 5 at: 0.5) equals: 4.
	self assert: ((1 / 2) interpolateTo: 1 at: 1 / 2) equals: 3 / 4.
	self assert: (2 @ 4 interpolateTo: 4 @ 8 at: 0.5) equals: 3 @ 6.
	self assert: ((0 @ 0 corner: 4 @ 4) interpolateTo: (4 @ 4 corner: 8 @ 8) at: 0.25) equals: (1 @ 1 corner: 5 @ 5).
	self assert: (((Color r: 0 g: 0 b: 1) interpolateTo: (Color r: 1 g: 0 b: 0) at: 0.25) blue - 0.75) abs < 0.01.
	"anything else jumps at the end"
	self assert: (#a interpolateTo: #b at: 0.99) equals: #a.
	self assert: (#a interpolateTo: #b at: 1) equals: #b.
	self assert: (Animation interpolate: 'x' to: 'y' at: 0.5) equals: 'x'.
	self assert: (nil interpolateTo: 3 at: 1) equals: 3
!
testStopAndFinish
	| anim v done |
	anim := Animation from: 0 to: 1 duration: 100 easing: #easeOutCubic do: [:x | v := x].
	anim whenDone: [done := true].
	anim stepAt: 0.
	anim stop.
	self deny: (anim stepAt: 50).
	self assert: done isNil.
	anim := Animation from: 0 to: 1 duration: 100 easing: #easeOutCubic do: [:x | v := x].
	anim finish.
	self assert: v equals: 1.
	self assert: anim isFinished
!
testFrameAnimationRunsUntilFalse
	| n anim |
	n := 0.
	anim := Animation everyFrame: [:ms | n := n + 1. n < 3].
	self assert: (anim stepAt: 0).
	self assert: (anim stepAt: 16).
	self deny: (anim stepAt: 32).
	self assert: anim isFinished.
	self assert: n equals: 3
!
testDelay
	| v anim |
	anim := Animation from: 0 to: 10 duration: 100 easing: #linear do: [:x | v := x].
	anim delay: 50.
	anim stepAt: 0.
	self assert: v isNil.
	anim stepAt: 100.
	self assert: v equals: 5
! !

!AnimationTest methodsFor: 'running'!
tearDown
	Animation timeScale: 1
! !

!AnimationTest methodsFor: 'time scale'!
testTimeScaleSlowsTheClock
	| real0 clock0 clock real |
	self assert: Animation timeScale equals: 1.
	Animation timeScale: 10.
	self assert: Animation timeScale equals: 10.
	real0 := Time microsecondClockValue / 1000.0.
	clock0 := Animation now.
	(Delay forMilliseconds: 150) wait.
	clock := Animation now - clock0.
	real := Time microsecondClockValue / 1000.0 - real0.
	self assert: clock > (real / 20).
	self assert: clock < (real / 5).
	self should: [Animation timeScale: 0] raise: Error
!
testAnimationRunsTenTimesSlower
	| v anim real0 real |
	Animation timeScale: 10.
	anim := Animation from: 0 to: 100 duration: 100 easing: #linear do: [:x | v := x].
	real0 := Time microsecondClockValue / 1000.0.
	anim stepAt: Animation now.
	(Delay forMilliseconds: 150) wait.
	real := Time microsecondClockValue / 1000.0 - real0.
	self assert: (anim stepAt: Animation now) description: 'finished after ', real printString, ' ms'.
	"about a tenth of the real time passed"
	self assert: (v - (real / 10)) abs < 5 description: v printString, ' after ', real printString, ' ms'
!
testScaleChangesDoNotJump
	| v anim before |
	anim := Animation from: 0 to: 100 duration: 1000 easing: #linear do: [:x | v := x].
	Animation timeScale: 10.
	anim stepAt: Animation now.
	(Delay forMilliseconds: 100) wait.
	anim stepAt: Animation now.
	before := v.
	Animation timeScale: 1.
	anim stepAt: Animation now.
	self assert: v >= before.
	self assert: v - before < 5.
	"back at normal speed"
	before := v.
	(Delay forMilliseconds: 100) wait.
	anim stepAt: Animation now.
	self assert: v - before >= 9.
	before := v.
	Animation timeScale: 10.
	anim stepAt: Animation now.
	self assert: v >= before.
	self assert: v - before < 5
! !
