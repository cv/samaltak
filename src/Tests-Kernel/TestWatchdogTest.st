TestCase subclass: #TestWatchdogTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

TestWatchdogTest comment: 'Tests the watchdog of TestResult (its class comment): in an image that runs only the tests it watches each test, and what it prints when a test outlived its time limit and its runner did not end it names the test and shows every Process with its stack.'!

!TestWatchdogTest methodsFor: 'tests'!
testWatchesTheRunningTest
	| watched watchdog |
	TestCase runsInThrowawayImage ifFalse: [^self skip: 'only an image that runs only the tests has the watchdog'].
	watched := TestResult classPool at: #Watched.
	watchdog := TestResult classPool at: #Watchdog.
	self assert: (watched at: 1) == self.
	self assert: (watched at: 3) equals: self timeLimitMilliseconds.
	self assert: (watched at: 2) > Time millisecondClockValue.
	self deny: watchdog isTerminated.
	self assert: watchdog priority > 70
!
testReportShowsTheTestAndEveryProcess
	| sleeper report |
	sleeper := self fork: [Semaphore new wait] named: 'watchdog test sleeper' at: Processor userBackgroundPriority.
	Processor yield.
	report := TestResult watchdogReportFor: self limit: 20000 over: 15001.
	self assert: (report beginsWith: 'test watchdog: ', self printString, ' still runs 15001 ms after its time limit of 20000 ms').
	self assert: (report includesSubstring: sleeper printString).
	self assert: (report includesSubstring: 'Semaphore>>wait')
! !
