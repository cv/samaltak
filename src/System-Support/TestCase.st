Object subclass: #TestCase
	instanceVariableNames: 'testSelector forkedProcesses scratchDirectory'
	classVariableNames: 'RunInline'
	package: 'System-Support'!

TestCase comment: 'I am a minimal SUnit: each instance runs one test method (a unary selector starting with "test") between setUp and tearDown. Assertions signal TestFailure; other errors count as errors. Subclass me, write test methods, and run them with "MyTest run" or "TestCase runAll" (the --test command-line option).

Each test runs in its own process with a time limit (see timeLimitMilliseconds), so a deadlocked test cannot hang the run. After tearDown, the processes a test started with fork: (or registered with track:) are terminated and its scratchDirectory is deleted. Tests wait for asynchronous effects with waitFor:timeout: and assert its answer.'!

!TestCase methodsFor: 'accessing'!
selector
	^testSelector
!
setTestSelector: aSymbol
	testSelector := aSymbol
!
timeLimitMilliseconds
	"Override for tests that need longer."
	^20000
! !

!TestCase methodsFor: 'running'!
setUp
!
tearDown
!
runCase
	[self setUp. self performTest] ensure: [
		[self tearDown] ensure: [
			[self terminateForkedProcesses] ensure: [self removeScratchDirectory]]]
!
performTest
	self perform: testSelector
!
run
	"Run me alone; answer the TestResult."
	| result |
	result := TestResult new.
	result runCase: self.
	^result
! !

!TestCase methodsFor: 'asserting'!
assert: aBooleanOrBlock
	aBooleanOrBlock value == true ifFalse: [self signalFailure: 'Assertion failed']
!
assert: aBooleanOrBlock description: aStringOrBlock
	aBooleanOrBlock value == true ifFalse: [self signalFailure: aStringOrBlock value]
!
deny: aBooleanOrBlock
	aBooleanOrBlock value == false ifFalse: [self signalFailure: 'Denial failed']
!
deny: aBooleanOrBlock description: aStringOrBlock
	aBooleanOrBlock value == false ifFalse: [self signalFailure: aStringOrBlock value]
!
assert: actual equals: expected
	expected = actual ifFalse: [
		self signalFailure: 'Expected ', (self safePrint: expected), ' but got ', (self safePrint: actual)]
!
deny: actual equals: unexpected
	unexpected = actual ifTrue: [
		self signalFailure: 'Did not expect ', (self safePrint: unexpected)]
!
assert: actual closeTo: expected
	self assert: actual closeTo: expected precision: 1.0e-9
!
assert: actual closeTo: expected precision: epsilon
	(actual - expected) abs <= (epsilon * (expected abs max: 1.0)) ifFalse: [
		self signalFailure: 'Expected ', (self safePrint: expected), ' (approximately) but got ', (self safePrint: actual)]
!
assert: actual identicalTo: expected
	expected == actual ifFalse: [
		self signalFailure: 'Expected the same object as ', (self safePrint: expected), ' but got ', (self safePrint: actual)]
!
should: aBlock
	self assert: aBlock value
!
shouldnt: aBlock
	self deny: aBlock value
!
should: aBlock raise: anExceptionClass
	"Fail unless evaluating aBlock signals anExceptionClass."
	(self raised: anExceptionClass in: aBlock) ifFalse: [
		self signalFailure: 'Expected ', anExceptionClass name, ' to be signaled']
!
should: aBlock raise: anExceptionClass withExceptionDo: checkBlock
	| raised |
	raised := false.
	[aBlock value] on: anExceptionClass do: [:e |
		raised := true.
		checkBlock value: e.
		e return: nil].
	raised ifFalse: [self signalFailure: 'Expected ', anExceptionClass name, ' to be signaled']
!
shouldnt: aBlock raise: anExceptionClass
	(self raised: anExceptionClass in: aBlock) ifTrue: [
		self signalFailure: anExceptionClass name, ' was signaled']
!
fail
	self signalFailure: 'Test failed'
!
fail: aString
	self signalFailure: aString
!
skip
	TestSkip signal: 'skipped'
!
skip: aString
	TestSkip signal: aString
!
signalFailure: aString
	TestFailure new signal: aString
! !

!TestCase methodsFor: 'environment'!
runsOnTheDefaultJit
	"Whether the VM runs as usual: the optimizing JIT at its threshold, without stress flags. CPU and time budgets of the tools hold only then (the interpreter is slower; compiling every method at its first activation, or deoptimizing for the stress, takes the CPU)."
	^Smalltalk vm jitMode == #opt and: [(Smalltalk vm jitParameters at: 3) > 0 and: [(Smalltalk vm jitFlags includes: 'deopt') not]]
! !

!TestCase methodsFor: 'waiting'!
waitFor: aBlock
	^self waitFor: aBlock timeout: 5000
!
waitFor: aBlock timeout: milliseconds
	"Poll aBlock every few milliseconds; answer true as soon as it answers true, false if it has not within milliseconds. Assert the answer."
	| deadline |
	deadline := Time millisecondClockValue + milliseconds.
	[aBlock value] whileFalse: [
		Time millisecondClockValue >= deadline ifTrue: [^false].
		(Delay forMilliseconds: 5) wait].
	^true
! !

!TestCase methodsFor: 'processes'!
fork: aBlock
	"Like aBlock fork, but the process is terminated after the test if it is still alive."
	^self fork: aBlock at: Processor activePriority
!
fork: aBlock at: priority
	^self fork: aBlock named: nil at: priority
!
fork: aBlock named: aString at: priority
	| process |
	process := aBlock newProcess.
	process priority: priority.
	aString isNil ifFalse: [process name: aString].
	^(self track: process) resume
!
track: aProcess
	"Terminate aProcess after the test if it is still alive; answer it."
	forkedProcesses isNil ifTrue: [forkedProcesses := OrderedCollection new].
	^forkedProcesses add: aProcess
!
terminateForkedProcesses
	"Done after tearDown; call it earlier where the processes must stop before the rest of tearDown."
	forkedProcesses isNil ifTrue: [^self].
	forkedProcesses do: [:p | p isTerminated ifFalse: [p terminate]].
	forkedProcesses := nil
! !

!TestCase methodsFor: 'scratch files'!
scratchDirectory
	"Answer this test's scratch directory in /tmp, created on first use and deleted with its contents after the test. Its name (wall clock µs, created with mkdir) is unique across concurrent runs."
	| base |
	scratchDirectory isNil ifFalse: [^scratchDirectory].
	base := '/tmp/samaltak-', self class name, '-', Time utcMicroseconds printString, '-'.
	1 to: 100 do: [:n |
		([Directory create: base, n printString. true] on: FileError do: [:e | e return: false])
			ifTrue: [^scratchDirectory := base, n printString]].
	^self error: 'Cannot create a scratch directory in /tmp'
!
scratchPath: aName
	"Answer the path of aName in the scratch directory."
	^self scratchDirectory / aName
!
removeScratchDirectory
	scratchDirectory isNil ifTrue: [^self].
	self deleteTree: scratchDirectory.
	scratchDirectory := nil
! !

!TestCase methodsFor: 'private'!
deleteTree: aPath
	(File isDirectory: aPath) ifTrue: [(Directory entries: aPath) do: [:n | self deleteTree: aPath / n]].
	File deleteIfExists: aPath
!
raised: anExceptionClass in: aBlock
	^[aBlock value. false] on: anExceptionClass do: [:e | e return: true]
!
safePrint: anObject
	^[anObject printString] on: Error do: [:e | e return: 'a ', anObject class name, ' (printString failed)']
! !

!TestCase methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: self class name; nextPutAll: '>>#'; nextPutAll: (testSelector ifNil: ['?'])
! !

!TestCase class methodsFor: 'testing'!
isAbstract
	"Abstract test classes are not run; override on the class side."
	^self == TestCase
! !

!TestCase class methodsFor: 'instance creation'!
selector: aSymbol
	^self new setTestSelector: aSymbol; yourself
! !

!TestCase class methodsFor: 'accessing'!
testSelectors
	"Answer my test selectors (inherited ones included), sorted."
	| selectors class |
	selectors := Set new.
	class := self.
	[class notNil and: [class ~~ TestCase]] whileTrue: [
		class selectors do: [:s | ((s beginsWith: 'test') and: [s numArgs = 0]) ifTrue: [selectors add: s]].
		class := class superclass].
	^selectors asSortedCollection asArray
!
suite
	^self testSelectors collect: [:s | self selector: s]
!
allTestClasses
	"Answer the concrete subclasses of TestCase, sorted by name."
	^(TestCase allSubclasses reject: [:c | c isAbstract])
		asSortedCollection: [:a :b | a name <= b name]
!
runInline: aBoolean
	"Run tests in the runner's process (no time limit); for debugging the scheduler."
	RunInline := aBoolean
!
runsInline
	^RunInline == true
! !

!TestCase class methodsFor: 'running'!
run
	"Run my tests, print a summary on the Transcript and answer the TestResult."
	^TestResult new runClasses: (Array with: self); yourself
!
runAll
	"Run all tests, print failures, errors and a summary, and answer the TestResult."
	^TestResult new runClasses: self allTestClasses asArray; yourself
!
runNamed: names
	"Run the test classes named in names, and those of the packages named in names."
	| classes |
	classes := self allTestClasses select: [:c |
		(names includes: c name asString) or: [names includes: c packageName]].
	^TestResult new runClasses: classes asArray; yourself
! !
