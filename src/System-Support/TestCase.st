Object subclass: #TestCase
	instanceVariableNames: 'testSelector forkedProcesses scratchDirectory cleanupBlocks'
	classVariableNames: 'RunInline Throwaway'
	package: 'System-Support'!

TestCase comment: 'I am a minimal SUnit: each instance runs one test method (a unary selector starting with "test") between setUp and tearDown. Assertions signal TestFailure; other errors count as errors. Subclass me, write test methods, and run them with "MyTest run" or "TestCase runAll" (the --test command-line option).

Each test runs in its own process with a time limit (see timeLimitMilliseconds), so a deadlocked test cannot hang the run. After tearDown, the processes a test started with fork: (or registered with track:) are terminated, its cleanups run (addCleanup:) and its scratchDirectory is deleted; then the instance variables of its class are set to nil, so that a TestResult kept afterwards (the agent''s run-tests tool keeps it) does not keep the conversations, Worlds or servers the test made. Tests wait for asynchronous effects with waitFor:timeout: and assert its answer.

Tests also run in the image someone works in (the agent runs them there with its run-tests tool), so a test must leave the image as it found it, also when it fails: work on objects of its own, and when it must change the image''s global state (a default account, SourceFiler default, World current, a class''s setting), change it with replace:of:with: or put it back in a cleanup (addCleanup:). Never sign out, clear or forget what the image itself uses. A test that cannot help changing the whole image (one that writes a snapshot, which runs every shutDown: hook and so forgets the image''s keys) calls needsThrowawayImage: first: it runs only in an image started to run tests and quit (--test, as make test does) and is skipped elsewhere.'!

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
			[self terminateForkedProcesses] ensure: [
				[self runCleanups] ensure: [
					[self removeScratchDirectory] ensure: [self releaseVariables]]]]]
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
needsThrowawayImage: why
	"Skip this test unless the image runs only the tests (TestCase runsInThrowawayImage): for a test that changes the whole image in a way it cannot undo; why says how."
	self class runsInThrowawayImage ifFalse: [self skip: 'not run in a live image: ', why, ' (it runs with --test, as make test does)']
!
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

!TestCase methodsFor: 'global state'!
addCleanup: aBlock
	"Evaluate aBlock after the test (after tearDown and the forked processes' end), also when the test failed; the last added runs first, each even when one before it fails. Put back here the global state the test changed. Answer aBlock."
	cleanupBlocks isNil ifTrue: [cleanupBlocks := OrderedCollection new].
	cleanupBlocks addFirst: aBlock.
	^aBlock
!
replace: aSelector of: anObject with: aValue
	"Make aValue what anObject answers to aSelector for this test, through the setter (aSelector, ':'); after the test (addCleanup:) the value it had is set back. Answer aValue.
		self replace: #default of: GitHubAccount with: GitHubAccount new"
	| setter old |
	setter := (aSelector, ':') asSymbol.
	old := anObject perform: aSelector.
	self addCleanup: [anObject perform: setter with: old].
	anObject perform: setter with: aValue.
	^aValue
!
keep: aSelector of: anObject
	"Set back after the test what anObject answers to aSelector now (replace:of:with:), whatever the test sets.
		self keep: #current of: World"
	^self replace: aSelector of: anObject with: (anObject perform: aSelector)
!
runCleanups
	| blocks |
	blocks := cleanupBlocks.
	cleanupBlocks := nil.
	blocks isNil ifFalse: [self evaluateCleanups: blocks asArray from: 1]
!
evaluateCleanups: blocks from: index
	index > blocks size ifTrue: [^self].
	[(blocks at: index) value] ensure: [self evaluateCleanups: blocks from: index + 1]
!
releaseVariables
	"Set my class's instance variables (not TestCase's) to nil: what the test made is garbage once it ran."
	TestCase instSize + 1 to: self class instSize do: [:i | self instVarAt: i put: nil]
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
!
runsByDefault
	"Does runAll (--test without names) run me? Tests that need hardware the default run cannot assume (an NVIDIA GPU:
	NvCudaComputeTest) answer false; they run only when named, from a make target of their own (make test-nv)."
	^true
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
!
runsInThrowawayImage
	"Whether this image was started to run tests and quit (--test: make test, tests/st_suite.sh, the UEFI tests), where tests may change what they cannot put back. Any other image is one someone works in (the agent runs tests there with its run-tests tool): needsThrowawayImage: skips the tests that would harm it."
	^Throwaway ifNil: [Smalltalk vm arguments includes: '--test']
!
runsInThrowawayImage: aBooleanOrNil
	"Say whether this image is a throwaway one (tests of the isolation: false makes it a live one); nil: as its command line says."
	Throwaway := aBooleanOrNil
! !

!TestCase class methodsFor: 'running'!
run
	"Run my tests, print a summary on the Transcript and answer the TestResult."
	^TestResult new runClasses: (Array with: self); yourself
!
runAll
	"Run all tests that run by default (runsByDefault), print failures, errors and a summary, and answer the TestResult."
	^TestResult new runClasses: (self classesNamed: #()) asArray; yourself
!
runNamed: names
	"Run the test classes named in names, and those of the packages named in names."
	^TestResult new runClasses: (self classesNamed: names) asArray; yourself
!
classesNamed: names
	"Answer the test classes --test names runs, sorted by name: those named in names and those of the packages named in names; with no names, all that run by default (runsByDefault)."
	^names isEmpty
		ifTrue: [self allTestClasses select: [:c | c runsByDefault]]
		ifFalse: [self allTestClasses select: [:c | (names includes: c name asString) or: [names includes: c packageName]]]
!
printClassesNamed: names
	"Print a line 'test-class <class> <package> <number of tests>' for each class --test names runs (--test-list: tests/st_suite.sh shards them)."
	(self classesNamed: names) do: [:c |
		Transcript show: 'test-class '; show: c name asString; show: ' '; show: c packageName asString; show: ' ';
			show: c testSelectors size printString; cr]
! !
