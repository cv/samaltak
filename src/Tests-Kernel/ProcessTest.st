TestCase subclass: #ProcessTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ProcessTest comment: 'Tests processes, priorities, semaphores, mutexes, delays, shared queues, time slicing and termination with unwinding.'!

!ProcessTest methodsFor: 'tests'!
testForkRuns
	| done sem |
	sem := Semaphore new.
	done := false.
	[done := true. sem signal] fork.
	sem wait.
	self assert: done
!
testPriorityPreemption
	| log |
	log := OrderedCollection new.
	[log add: #high] forkAt: Processor activePriority + 1.
	log add: #main.
	[log add: #low] forkAt: Processor activePriority - 1.
	log add: #main2.
	self assert: log asArray = #(#high #main #main2).
	self assert: (self waitFor: [log size = 4]).
	self assert: log asArray = #(#high #main #main2 #low)
!
testYield
	| log |
	log := OrderedCollection new.
	[log add: #other] fork.
	log add: #first.
	Processor yield.
	log add: #second.
	self assert: log asArray = #(#first #other #second)
!
testSemaphore
	| sem log |
	sem := Semaphore new.
	log := OrderedCollection new.
	[sem wait. log add: 1] fork.
	[sem wait. log add: 2] fork.
	Processor yield.
	self assert: log isEmpty.
	sem signal.
	Processor yield.
	self assert: log asArray = #(1).
	sem signal; signal.
	Processor yield.
	self assert: log asArray = #(1 2).
	self assert: sem excessSignals = 1.
	sem wait.
	self assert: sem excessSignals = 0
!
testCritical
	| mutex log p |
	mutex := Semaphore forMutualExclusion.
	log := OrderedCollection new.
	p := [mutex critical: [log add: #p]].
	mutex critical: [
		p fork.
		Processor yield.
		log add: #main].
	Processor yield.
	self assert: log asArray = #(#main #p).
	self assert: (mutex critical: [42]) = 42.
	self assert: mutex excessSignals = 1.
	self assert: ([mutex critical: [Error signal]] on: Error do: [:e | 1]) = 1.
	self assert: mutex excessSignals = 1
!
testMutexIsReentrant
	| m |
	m := Mutex new.
	self assert: (m critical: [m critical: [7]]) = 7.
	self deny: m isOwned
!
testDelay
	| start elapsed |
	start := Time millisecondClockValue.
	(Delay forMilliseconds: 50) wait.
	elapsed := Time millisecondClockValue - start.
	self assert: elapsed >= 49.
	self assert: elapsed < 1000
!
testDelaysWakeInOrder
	| log sem |
	log := OrderedCollection new.
	sem := Semaphore new.
	#(30 10 20) do: [:ms | [(Delay forMilliseconds: ms) wait. log add: ms. sem signal] fork].
	3 timesRepeat: [sem wait].
	self assert: log asArray = #(10 20 30)
!
testWaitTimeout
	| sem start |
	sem := Semaphore new.
	start := Time millisecondClockValue.
	self assert: (sem waitTimeoutMSecs: 30).
	self assert: Time millisecondClockValue - start >= 29.
	[sem signal] fork.
	self deny: (sem waitTimeoutMSecs: 1000).
	sem signal.
	self deny: (sem waitTimeoutMSecs: 0).
	self assert: (sem waitTimeoutMSecs: 0).
	self assert: sem excessSignals = 0
!
testSharedQueue
	| q results consumer |
	q := SharedQueue new.
	results := OrderedCollection new.
	consumer := self fork: [5 timesRepeat: [results add: q next]].
	1 to: 5 do: [:i | q nextPut: i * i].
	self assert: (self waitFor: [results size = 5]).
	self assert: results asArray = #(1 4 9 16 25).
	self assert: q isEmpty.
	self assert: q nextOrNil isNil.
	q nextPut: 7.
	self assert: q peek = 7.
	self assert: q size = 1.
	self assert: q next = 7
!
testRoundRobin
	"Two busy processes of the same priority both make progress (time slicer)."
	| counts stop procs |
	counts := Array new: 2 withAll: 0.
	stop := false.
	procs := (1 to: 2) collect: [:i |
		self fork: [[stop] whileFalse: [counts at: i put: (counts at: i) + 1]] at: Processor activePriority - 1].
	"Only the time slicer can switch between them during this one sleep."
	(Delay forMilliseconds: 200) wait.
	stop := true.
	self assert: (self waitFor: [procs allSatisfy: [:p | p isTerminated]]).
	self assert: (counts at: 1) > 0.
	self assert: (counts at: 2) > 0
!
testTerminateRunsUnwindBlocks
	| sem log p |
	sem := Semaphore new.
	log := OrderedCollection new.
	p := self fork: [[sem wait. log add: #notReached] ensure: [log add: #ensure]].
	Processor yield.
	self deny: p isTerminated.
	self assert: p isWaiting.
	p terminate.
	self assert: log asArray = #(#ensure).
	self assert: p isTerminated.
	sem signal.
	Processor yield.
	self assert: log asArray = #(#ensure).
	self assert: sem excessSignals = 1
!
testTerminateActive
	| log done p |
	log := OrderedCollection new.
	done := Semaphore new.
	p := [[log add: #start. Processor activeProcess terminate. log add: #no] ensure: [log add: #ensure. done signal]] fork.
	done wait.
	Processor yield.
	self assert: log asArray = #(#start #ensure).
	self assert: p isTerminated
!
testSuspendResume
	| p count |
	count := 0.
	p := self fork: [[true] whileTrue: [count := count + 1. Processor yield]].
	Processor yield.
	p suspend.
	self assert: p isSuspended.
	count := 0.
	Processor yield.
	self assert: count = 0.
	p resume.
	Processor yield.
	self assert: count > 0.
	p terminate.
	self assert: p isTerminated
!
testProcessAccessors
	| p |
	p := [nil] newProcess.
	p name: 'worker'.
	self assert: p name = 'worker'.
	self assert: p priority = Processor activePriority.
	p priority: 30.
	self assert: p priority = 30.
	self assert: p isSuspended.
	self assert: (p printString includesSubstring: 'worker').
	self assert: Processor activeProcess isActiveProcess.
	self assert: Processor activeProcess priority = Processor activePriority.
	self assert: Processor timingPriority = 80.
	self assert: Processor idleProcess priority = 1.
	self should: [p priority: 0] raise: Error.
	p terminate
!
testSignalException
	| sem p caught done |
	sem := Semaphore new.
	done := Semaphore new.
	caught := nil.
	p := self fork: [[sem wait] on: ZeroDivide do: [:e | caught := e class]. done signal].
	Processor yield.
	p signalException: ZeroDivide new.
	done wait.
	self assert: caught == ZeroDivide
!
testValueWithin
	self assert: ([3 + 4] valueWithin: 1000 onTimeout: [#timeout]) = 7.
	self assert: ([(Delay forMilliseconds: 500) wait. 1] valueWithin: 20 onTimeout: [#timeout]) = #timeout
!
testCpuTime
	| p sem |
	sem := Semaphore new.
	p := [1 to: 20000 do: [:i | i * i]. sem signal] fork.
	sem wait.
	self assert: p cpuTime >= 0
! !
