TestCase subclass: #AnimationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

AnimationTest comment: 'Tests Animation: easings, interpolation of numbers, points, rectangles and colors, stepping on a clock, whenDone:, stop, frame animations.'!

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
