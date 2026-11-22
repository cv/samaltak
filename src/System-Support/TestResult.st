Object subclass: #TestResult
	instanceVariableNames: 'passed failures errors skipped'
	classVariableNames: 'PrintsClassTimes'
	package: 'System-Support'!

TestResult comment: 'I run TestCases and collect their outcomes: passed tests, failures and errors (each with its message), and skipped tests. Failures and errors are reported on the Transcript as they happen, with a short stack for errors; runClasses: ends with a summary line.'!

!TestResult class methodsFor: 'settings'!
printsClassTimes: aBoolean
	"Whether runClasses: prints a line 'test-time <class> <ms>' after each class's tests (--test-times: tests/st_suite.sh records them to balance its shards)."
	PrintsClassTimes := aBoolean
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
	process := [
		outcome := self outcomeOf: aTestCase.
		done signal] newProcess.
	process priority: Processor userSchedulingPriority; name: aTestCase printString.
	process resume.
	timedOut := done waitTimeoutMSecs: aTestCase timeLimitMilliseconds.
	timedOut ifTrue: [
		process terminate.
		outcome := #error -> ('Timed out after ', aTestCase timeLimitMilliseconds printString, ' ms')].
	self record: outcome for: aTestCase
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
