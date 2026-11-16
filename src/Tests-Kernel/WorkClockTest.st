TestCase subclass: #WorkClockTest
	instanceVariableNames: 'frames index'
	classVariableNames: ''
	package: 'Tests-Kernel'!

WorkClockTest comment: 'I test the work clock of the VM''s Scheduler, the clock of a recording: it counts the cycles of the VM''s thread, jumps to the next deadline when nothing can run, signals frames, and stands still when it is told to.'!

!WorkClockTest methodsFor: 'running'!
setUp
	frames := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: frames
!
tearDown
	Smalltalk vm workClockStop.
	Smalltalk vm unregisterExternalSemaphore: index
! !

!WorkClockTest methodsFor: 'support'!
start
	^Smalltalk vm workClockStart: 60 semaphore: index
!
whileStopped: aBlock
	"Stop the clock and evaluate aBlock in a Process that may run then (the control server's priority), start the clock again."
	| done |
	done := Semaphore new.
	[Smalltalk vm workClockRunning: false.
	 [aBlock value] ensure: [
		Smalltalk vm workClockRunning: true.
		done signal]] forkAt: Processor userInterruptPriority.
	done wait
!
spin: n
	| x |
	x := 0.
	1 to: n do: [:i | x := x + i].
	^x
! !

!WorkClockTest methodsFor: 'tests'!
testOffUnlessStarted
	self deny: Smalltalk vm isOnWorkClock.
	self start.
	self assert: Smalltalk vm isOnWorkClock.
	Smalltalk vm workClockStop.
	self deny: Smalltalk vm isOnWorkClock
!
testDelaysJumpAcrossIdleTime
	"Nothing to do until the Delay is due: ten seconds of the clock pass in much less than that."
	| clock real |
	self start.
	clock := Time millisecondClockValue.
	real := Time utcMicroseconds.
	(Delay forSeconds: 10) wait.
	self assert: Time millisecondClockValue - clock >= 10000.
	self assert: Time millisecondClockValue - clock < 10100.
	self assert: Time utcMicroseconds - real < 5000000
!
testWorkMovesTheClock
	| t0 |
	self start.
	t0 := Time microsecondClockValue.
	self spin: 30000000.
	self assert: Time microsecondClockValue - t0 > 1000
!
testAFrameIsSignaledPerTickOnTheMillisecondGrid
	| origin |
	origin := self start.
	self assert: origin \\ 1000 equals: 0.
	(Delay forMilliseconds: 1000) wait.
	"frame 0 is due at origin, frame k at ceiling(k * 1000 / 60) ms after it"
	self assert: (frames excessSignals between: 60 and: 61).
	self assert: Smalltalk vm workClockNextFrame \\ 1000 equals: 0
!
testTheClockNeverPassesAFrame
	"However long a Process works, each frame is signaled when the clock reaches it."
	| before |
	self start.
	before := frames excessSignals.
	self spin: 60000000.
	Processor yield.
	self assert: frames excessSignals >= before
!
testStandsStillWhenStopped
	| t0 t1 |
	self start.
	self whileStopped: [
		t0 := Time microsecondClockValue.
		self spin: 30000000.
		t1 := Time microsecondClockValue].
	self assert: t1 equals: t0.
	self spin: 30000000.
	self assert: Time microsecondClockValue > t0
!
testOnlyControlProcessesRunWhileStopped
	"A Process below the control server's priority (50) waits for the clock; one at 50 runs, and the clock stands still."
	| low high t0 t1 |
	self start.
	low := false.
	high := false.
	self whileStopped: [
		[low := true] forkAt: 40.
		t0 := Time microsecondClockValue.
		[high := true] forkAt: 50.
		Processor yield.
		self spin: 1000.
		t1 := Time microsecondClockValue.
		self assert: low not].
	self assert: high.
	self assert: t1 equals: t0
!
testWorkDoneWhileHeldIsNotCounted
	| t0 work |
	self start.
	Smalltalk vm workClockHold.
	t0 := Time microsecondClockValue.
	self spin: 30000000.
	self assert: Time microsecondClockValue equals: t0.
	self assert: Smalltalk vm workClockHeldMicros > t0.
	work := Smalltalk vm workClockRelease.
	self assert: work > 1000.
	self assert: Time microsecondClockValue - t0 < 1000
!
testChargeMovesTheClock
	| t0 |
	self start.
	t0 := Time microsecondClockValue.
	Smalltalk vm workClockCharge: 40000.
	self assert: Time microsecondClockValue - t0 >= 40000
!
testPacedKeepsUpWithRealTime
	"An external program runs: the clock waits for real time and moves even when no command is in flight."
	| clock real |
	self start.
	Smalltalk vm workClockRunning: false.
	Smalltalk vm workClockPaced: true.
	clock := Time millisecondClockValue.
	real := Time utcMicroseconds.
	(Delay forMilliseconds: 50) wait.
	self assert: Time millisecondClockValue - clock >= 50.
	self assert: Time utcMicroseconds - real >= 45000.
	Smalltalk vm workClockPaced: false
!
testSkippedRealTimeIsNotCounted
	"Paced: 30 ms of real time go by while the clock is held (a recorded frame waiting for its reader). Skipped, they are not counted: a Delay of 20 ms then still takes its real time."
	| real |
	self start.
	Smalltalk vm workClockPaced: true.
	Smalltalk vm workClockHold.
	real := Time utcMicroseconds.
	[Time utcMicroseconds - real < 30000] whileTrue: [self spin: 1000].
	Smalltalk vm workClockSkipRealTime.
	Smalltalk vm workClockRelease.
	real := Time utcMicroseconds.
	(Delay forMilliseconds: 20) wait.
	real := Time utcMicroseconds - real.
	Smalltalk vm workClockPaced: false.
	self assert: real >= 15000
!
testStopGoesOnFromTheClock
	| before |
	self start.
	(Delay forSeconds: 5) wait.
	before := Time microsecondClockValue.
	Smalltalk vm workClockStop.
	self assert: Time microsecondClockValue >= before.
	self assert: Time microsecondClockValue - before < 1000000
! !
