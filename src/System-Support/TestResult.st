Object subclass: #TestResult
	instanceVariableNames: 'passed failures errors skipped'
	classVariableNames: 'PrintsClassTimes Watched Watchdog'
	package: 'System-Support'!

TestResult comment: 'I run TestCases and collect their outcomes: passed tests, failures and errors (each with its message), and skipped tests. Failures and errors are reported on the Transcript as they happen, with a short stack for errors; runClasses: ends with a summary line.

In an image that runs only the tests (TestCase runsInThrowawayImage) a watchdog Process at the timing priority watches each test: when its time limit passed 15 s ago and its runner still did not end it (the runner and the tests run below Processes that may take all of the CPU: a compositor drawing frame after frame), it prints every Process''s stack on stderr and quits the VM with 1, so that the run fails saying where it was instead of hanging.'!

!TestResult class methodsFor: 'settings'!
printsClassTimes: aBoolean
	"Whether runClasses: prints a line 'test-time <class> <ms>' after each class's tests (--test-times: tests/st_suite.sh records them to balance its shards)."
	PrintsClassTimes := aBoolean
! !

!TestResult class methodsFor: 'watchdog'!
watchdogGraceMilliseconds
	"How long after a test's time limit the watchdog waits for its runner to end it."
	^15000
!
startWatchdog
	"The watchdog Process (my comment), once."
	(Watchdog notNil and: [Watchdog isTerminated not]) ifTrue: [^self].
	Watchdog := [[(Delay forMilliseconds: 1000) wait. self checkWatched] repeat] newProcess.
	Watchdog priority: Processor timingPriority - 1; name: 'test watchdog'.
	Watchdog resume
!
checkWatched
	| w over |
	w := Watched.
	w isNil ifTrue: [^self].
	over := Time millisecondClockValue - (w at: 2).
	over < self watchdogGraceMilliseconds ifTrue: [^self].
	Smalltalk vm stderrWrite: (self watchdogReportFor: (w at: 1) limit: (w at: 3) over: over).
	Smalltalk quit: 1
!
watchdogReportFor: aTestCase limit: limit over: over
	"What the watchdog prints: the test, and every Process with its stack (at most 30 frames each), the highest priority first."
	| lf |
	lf := String with: Character lf.
	^String new: 4000 streamContents: [:s |
		s nextPutAll: 'test watchdog: '; print: aTestCase; nextPutAll: ' still runs '; print: over; nextPutAll: ' ms after its time limit of '; print: limit; nextPutAll: ' ms, and its runner did not end it: the VM quits. Its Processes:'; nextPutAll: lf.
		((Processor allProcesses reject: [:p | p == Processor activeProcess])
			asSortedCollection: [:a :b | a priority >= b priority]) do: [:p |
				| ctx n |
				s print: p; nextPutAll: lf.
				ctx := p suspendedContext.
				n := 0.
				[ctx notNil and: [n < 30]] whileTrue: [
					s tab; print: ctx; nextPutAll: lf.
					ctx := ctx sender.
					n := n + 1]]]
! !

!TestResult methodsFor: 'initialization'!
initialize
	passed := OrderedCollection new.
	failures := OrderedCollection new.
	errors := OrderedCollection new.
	skipped := OrderedCollection new
! !

!TestResult methodsFor: 'accessing'!
passed
	^passed
!
failures
	"Answer the failed tests as TestCase -> message Associations."
	^failures
!
errors
	"Answer the tests that signaled an error as TestCase -> report Associations."
	^errors
!
skipped
	^skipped
!
runCount
	^passed size + failures size + errors size + skipped size
!
hasPassed
	^failures isEmpty and: [errors isEmpty]
! !

!TestResult methodsFor: 'running'!
runClasses: testClasses
	| start classStart |
	start := Time millisecondClockValue.
	testClasses do: [:class |
		classStart := Time millisecondClockValue.
		class suite do: [:test | self runCase: test].
		PrintsClassTimes == true ifTrue: [
			Transcript show: 'test-time '; show: class name asString; show: ' ';
				show: (Time millisecondClockValue - classStart) printString; cr]].
	Transcript
		show: self summary;
		show: ' in ';
		show: (Time millisecondClockValue - start) printString;
		show: ' ms';
		cr
!
runCase: aTestCase
	"Run aTestCase in its own process with a time limit and record the outcome."
	| outcome done process timedOut |
	TestCase runsInline ifTrue: [^self record: (self outcomeOf: aTestCase) for: aTestCase].
	done := Semaphore new.
	self watch: aTestCase during: [
	process := [
		outcome := self outcomeOf: aTestCase.
		done signal] newProcess.
	process priority: Processor userSchedulingPriority; name: aTestCase printString.
	process resume.
	"If the run is stopped (the run-tests tool's timeout, an interrupted turn), the test stops with it, tearing down: a test left running would overlap the next run's and put back each other's World current."
	timedOut := [done waitTimeoutMSecs: aTestCase timeLimitMilliseconds] ifCurtailed: [process terminate].
	timedOut ifTrue: [
		process terminate.
		outcome := #error -> ('Timed out after ', aTestCase timeLimitMilliseconds printString, ' ms')]].
	self record: outcome for: aTestCase
!
watch: aTestCase during: aBlock
	"Run aBlock (aTestCase's run) watched by the watchdog (my class comment), in an image that runs only the tests."
	| previous |
	TestCase runsInThrowawayImage ifFalse: [^aBlock value].
	self class startWatchdog.
	previous := Watched.
	Watched := Array with: aTestCase with: Time millisecondClockValue + aTestCase timeLimitMilliseconds with: aTestCase timeLimitMilliseconds.
	^aBlock ensure: [Watched := previous]
!
outcomeOf: aTestCase
	"Answer kind -> message, kind being #passed, #failure, #error or #skipped."
	^[[[aTestCase runCase.
		#passed -> nil]
			on: TestSkip do: [:e | e return: #skipped -> e messageText]]
			on: TestFailure do: [:e | e return: #failure -> e messageText]]
			on: Error, Halt do: [:e | e return: #error -> (self reportFor: e)]
!
record: outcome for: aTestCase
	| kind |
	kind := outcome key.
	kind == #passed ifTrue: [^passed add: aTestCase].
	kind == #skipped ifTrue: [^skipped add: aTestCase].
	kind == #failure
		ifTrue: [
			failures add: aTestCase -> outcome value.
			Transcript show: 'FAIL  '; show: aTestCase printString; show: ': '; show: outcome value asString; cr]
		ifFalse: [
			errors add: aTestCase -> outcome value.
			Transcript show: 'ERROR '; show: aTestCase printString; show: ': '; show: outcome value asString; cr]
!
reportFor: anException
	"Answer the exception's description and the top of its signaler's stack."
	^String new: 400 streamContents: [:s |
		s nextPutAll: ([anException printString] on: Error do: [:e | e return: anException class name]).
		anException signalerContext ifNotNil: [:ctx |
			(ctx stackOfSize: 8) do: [:each | s nextPut: Character lf; nextPutAll: '      '; print: each]]]
! !

!TestResult methodsFor: 'printing'!
summary
	^String new: 80 streamContents: [:s |
		s print: self runCount; nextPutAll: ' run, ';
			print: passed size; nextPutAll: ' passed, ';
			print: failures size; nextPutAll: ' failed, ';
			print: errors size; nextPutAll: ' errors'.
		skipped isEmpty ifFalse: [s nextPutAll: ', '; print: skipped size; nextPutAll: ' skipped']]
!
printOn: aStream
	aStream nextPutAll: 'a TestResult('; nextPutAll: self summary; nextPut: $)
! !
