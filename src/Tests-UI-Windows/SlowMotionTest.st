UIWindowsTestCase subclass: #SlowMotionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

SlowMotionTest comment: 'Tests slow motion (Animation timeScale:) in a hidden World: the compositor''s layer animations and toasts run on the slowed clock, a scale change applies to running animations, and 1 restores normal timing. Real time is only checked against lower bounds the slowed clock guarantees, or with wide ratios.'!

!SlowMotionTest methodsFor: 'running'!
tearDown
	Animation timeScale: 1.
	super tearDown
!
openWindow
	| w |
	w := Window new title: 'Slow'; content: RecordingTestView new; bounds: (100 @ 100 extent: 300 @ 200); yourself.
	w openIn: world.
	^w
!
millisecondsToOpen
	"Real ms from opening a window until its open animation (140 ms of the animation clock) ended."
	| start w |
	start := Time millisecondClockValue.
	w := self openWindow.
	self assert: (self waitFor: [w layer isAnimating not] timeout: 20000) description: 'the open animation did not end'.
	self assert: w layer opacity equals: 1.
	^Time millisecondClockValue - start
! !

!SlowMotionTest methodsFor: 'tests'!
testWindowOpensTenTimesSlower
	| slow normal |
	Animation timeScale: 10.
	slow := self millisecondsToOpen.
	self assert: slow >= 1000 description: 'opened in ', slow printString, ' ms'.
	Animation timeScale: 1.
	normal := self millisecondsToOpen.
	self assert: normal * 2 < slow description: normal printString, ' ms vs ', slow printString, ' ms slowed down'
!
testScaleChangeAppliesToRunningAnimation
	| w start |
	Animation timeScale: 10.
	w := self openWindow.
	(Delay forMilliseconds: 300) wait.
	self assert: w layer isAnimating.
	Animation timeScale: 1.
	start := Time millisecondClockValue.
	self assert: (self waitFor: [w layer isAnimating not] timeout: 20000).
	self assert: Time millisecondClockValue - start < 1000.
	self assert: w layer opacity equals: 1
!
testToastStaysTenTimesLonger
	| start toast |
	Animation timeScale: 10.
	start := Time millisecondClockValue.
	"180 ms in, 20 ms shown, 180 ms out: 3.8 s in slow motion"
	toast := world toast: 'Slow toast' duration: 20.
	(Delay forMilliseconds: 1000) wait.
	self deny: toast isDone.
	self assert: (self waitFor: [toast isDone] timeout: 30000) description: 'the toast did not go'.
	self assert: Time millisecondClockValue - start >= 3000
!
testTopBarShowsTheScale
	Animation timeScale: 10.
	self assert: (world topBar updateAt: Time microsecondClockValue).
	Animation timeScale: 1.
	self assert: (world topBar updateAt: Time microsecondClockValue)
! !
