TestCase subclass: #StackOverflowTest
	instanceVariableNames: 'oldLimit counter'
	classVariableNames: ''
	package: 'Tests-Kernel'!

StackOverflowTest comment: 'Tests Process maxStackDepth and StackOverflow: unbounded recursion signals a catchable, resumable error instead of exhausting the heap; its memory is freed when the stack unwinds or the process is terminated. A small limit keeps the tests fast; the check overshoots by up to the C stack''s frames (tens of thousands).'!

!StackOverflowTest methodsFor: 'running'!
setUp
	oldLimit := Process maxStackDepth: 10000
!
tearDown
	Process maxStackDepth: oldLimit
! !

!StackOverflowTest methodsFor: 'helpers'!
recurse: n
	^self recurse: n + 1
!
depth: n
	"A legal recursion n deep; answers n."
	^n = 0 ifTrue: [0] ifFalse: [(self depth: n - 1) + 1]
!
countDown
	"No arguments, no temporaries: the VM may interrupt it with an empty stack (Context>>stackOverflow: continues it through a process switch)."
	counter := counter - 1.
	counter = 0 ifTrue: [^0].
	^self countDown + 1
!
oldBytesAfterGC
	Smalltalk vm garbageCollect.
	^Smalltalk vm statistics oldBytesUsed
! !

!StackOverflowTest methodsFor: 'tests'!
testRecursionSignalsStackOverflow
	| ex |
	ex := [self recurse: 1. nil] on: StackOverflow do: [:e | e return: e].
	self assert: (ex isKindOf: StackOverflow).
	self assert: (ex isKindOf: Error).
	self assert: ex isResumable.
	self assert: ex depth > 10000.
	self assert: ex signalerContext selector equals: #recurse:.
	self assert: ex receiver == self.
	self assert: ('Stack overflow: *' match: ex messageText)
!
testBlockRecursionSignalsStackOverflow
	| block ex |
	block := nil.
	block := [:n | block value: n + 1].
	ex := [block value: 1. nil] on: StackOverflow do: [:e | e return: e].
	self assert: (ex isKindOf: StackOverflow).
	self assert: ex signalerContext isBlockContext
!
testResumeContinuesWithHeadroom
	"Each resumption allows maxStackDepth more activations before the next signal."
	| depths |
	depths := OrderedCollection new.
	self assert: ([self depth: 200000] on: StackOverflow do: [:e | depths add: e depth. e resume]) equals: 200000.
	self assert: depths size > 1.
	2 to: depths size do: [:i | self assert: (depths at: i) - (depths at: i - 1) > 10000]
!
testResumeWithEmptyStack
	| signals |
	signals := 0.
	counter := 200000.
	self assert: ([self countDown] on: StackOverflow do: [:e | signals := signals + 1. e resume]) equals: 199999.
	self assert: signals > 0
!
testRearmedAfterUnwinding
	| first second |
	first := 0.
	second := 0.
	[self depth: 100000] on: StackOverflow do: [:e | first := first + 1. e resume].
	[self depth: 100000] on: StackOverflow do: [:e | second := second + 1. e resume].
	self assert: first > 0.
	self assert: second > 0
!
testDeepRecursionBelowTheLimit
	Process maxStackDepth: 300000.
	self assert: ([self depth: 200000] on: StackOverflow do: [:e | e return: -1]) equals: 200000
!
testNoLimit
	Process maxStackDepth: 0.
	self assert: Process maxStackDepth equals: 0.
	self should: [Process maxStackDepth: 10] raise: Error.
	self assert: Process maxStackDepth equals: 0.
	self assert: ([self depth: 60000] on: StackOverflow do: [:e | e return: -1]) equals: 60000
!
testProcessUsableAfterwards
	self assert: ([self recurse: 1] on: StackOverflow do: [:e | e return: 7]) equals: 7.
	self assert: ([self recurse: 1] on: StackOverflow do: [:e | e return: 8]) equals: 8.
	self assert: (self depth: 1000) equals: 1000
!
testMemoryFreedAfterUnwinding
	| before deep after |
	Process maxStackDepth: 100000.
	before := self oldBytesAfterGC.
	deep := [self recurse: 1] on: StackOverflow do: [:e | e return: self oldBytesAfterGC].
	after := self oldBytesAfterGC.
	self assert: deep - before > (5 * 1024 * 1024).
	self assert: after - before < (2 * 1024 * 1024)
!
testUnhandledInAnotherProcessAndTerminate
	"Like the debugger: the error handler stops the overflowing process; terminating it (Abandon) frees its stack."
	| before caught stopped p deep after |
	Process maxStackDepth: 100000.
	before := self oldBytesAfterGC.
	stopped := Semaphore new.
	p := self fork: [self recurse: 1].
	p errorHandler: [:ex | caught := ex. stopped signal. Processor activeProcess suspend].
	self deny: (stopped waitTimeoutMSecs: 10000).
	self assert: (caught isKindOf: StackOverflow).
	self assert: caught signalerContext selector equals: #recurse:.
	deep := self oldBytesAfterGC.
	p terminate.
	caught := nil.
	after := self oldBytesAfterGC.
	self assert: p isTerminated.
	self assert: deep - before > (5 * 1024 * 1024).
	self assert: after - before < (2 * 1024 * 1024)
! !
