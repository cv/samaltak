TestCase subclass: #LowSpaceTest
	instanceVariableNames: 'keep oldLimit'
	classVariableNames: ''
	package: 'Tests-Kernel'!

LowSpaceTest comment: 'Tests that a program filling the heap gets catchable errors, never a fatal out of memory (GarbageCollector, Process>>lowSpaceIn:depth:): large allocations fail with OutOfMemory before the heap''s reserve; small objects and deep recursion may use the reserve, and a full GC that finds it in use signals OutOfMemory or, in a deep process, StackOverflow, neither resumable; after unwinding the heap is usable again. They fill the heap, so they run only with a small one (at most 512 MB: make test-core runs them with --max-heap 128, make test-uefi boots them so), and pass trivially otherwise.'!

!LowSpaceTest methodsFor: 'running'!
setUp
	keep := OrderedCollection new.
	oldLimit := Process maxStackDepth
!
tearDown
	keep := nil.
	Process maxStackDepth: oldLimit.
	Smalltalk vm garbageCollect
! !

!LowSpaceTest methodsFor: 'helpers'!
stats
	Smalltalk vm garbageCollect.
	^Smalltalk vm statistics
!
isSmallHeap
	"Small enough to fill (--max-heap 512 or less)."
	^self stats maxHeapBytes <= (512 * 1048576)
!
largeSize
	"Bytes of an object allocated directly in old space (beyond the eden's eighth)."
	^self stats edenBytes // 8 + 1048576
!
fillWithLargeObjects
	"Fill the heap with large ByteArrays until one fails; answer the OutOfMemory."
	| size |
	size := self largeSize.
	^[[keep add: (ByteArray new: size)] repeat] on: OutOfMemory do: [:e | e return: e]
!
recurse: n
	^self recurse: n + 1
!
depth: n
	^n = 0 ifTrue: [0] ifFalse: [(self depth: n - 1) + 1]
! !

!LowSpaceTest methodsFor: 'tests'!
testStatisticsReportTheHeapLimit
	| stats |
	stats := self stats.
	self assert: stats maxHeapBytes > stats oldBytesUsed.
	self assert: stats heapReserve > 0.
	self assert: stats heapReserve <= (stats maxHeapBytes // 8)
!
testLargeAllocationsKeepTheReserve
	| e stats |
	self isSmallHeap ifFalse: [^self].
	e := self fillWithLargeObjects.
	self assert: (e isKindOf: OutOfMemory).
	self deny: e isHeapFull.
	self assert: e requestedClass equals: ByteArray.
	stats := self stats.
	self assert: stats oldBytesUsed + self largeSize > (stats maxHeapBytes - stats heapReserve).
	self assert: stats oldBytesUsed <= (stats maxHeapBytes - stats heapReserve).
	"small objects still fit, in the reserve"
	self assert: ((1 to: 20000) collect: [:i | i printString]) size equals: 20000
!
testSmallObjectsFillingTheHeapSignalOutOfMemory
	| list e |
	self isSmallHeap ifFalse: [^self].
	list := nil.
	e := [[list := Array with: list with: (ByteArray new: 4000)] repeat] on: OutOfMemory do: [:ex | ex return: ex].
	list := nil.
	self assert: (e isKindOf: OutOfMemory).
	self assert: e isHeapFull.
	self deny: e isResumable.
	self assert: ('Out of memory: the heap is nearly full*' match: e messageText).
	"re-armed once the heap is free again"
	e := [[list := Array with: list with: (ByteArray new: 4000)] repeat] on: OutOfMemory do: [:ex | ex return: ex].
	list := nil.
	self assert: e isHeapFull
!
testDeepRecursionInAFullHeapSignalsStackOverflow
	"With no depth limit, the stack grows into the heap's reserve: the full GC that notices signals a StackOverflow that cannot be resumed."
	| e |
	self isSmallHeap ifFalse: [^self].
	self fillWithLargeObjects.
	4 timesRepeat: [keep removeLast].
	Process maxStackDepth: 0.
	e := [self recurse: 1] on: StackOverflow do: [:ex | ex return: ex].
	self assert: (e isKindOf: StackOverflow).
	self assert: e isHeapFull.
	self deny: e isResumable.
	self assert: e depth > Process lowSpaceDepth.
	self assert: ('Stack overflow: * frames deep, the heap nearly full' match: e messageText).
	self assert: (self depth: 1000) equals: 1000
!
testDeepRecursionWhileAHigherProcessWakes
	"A process waking every millisecond above the deep one: a switch to it flushes the deep stack into Contexts, and the full GC that flush runs finds the heap nearly full. The signal still goes to the deep process, when it runs again, not to the one active at the next safepoint (it went to the timer process, and the deep one grew the heap past its limit: fatal)."
	| e |
	self isSmallHeap ifFalse: [^self].
	self fillWithLargeObjects.
	4 timesRepeat: [keep removeLast].
	Process maxStackDepth: 0.
	self fork: [[(Delay forMilliseconds: 1) wait] repeat] at: Processor lowIOPriority.
	10 timesRepeat: [
		e := [self recurse: 1] on: StackOverflow do: [:ex | ex return: ex].
		self assert: (e isKindOf: StackOverflow).
		self assert: e isHeapFull.
		e := nil.
		Smalltalk vm garbageCollect]
!
testResumingAHeapFullStackOverflowFails
	| e |
	self isSmallHeap ifFalse: [^self].
	self fillWithLargeObjects.
	4 timesRepeat: [keep removeLast].
	Process maxStackDepth: 0.
	e := [[self recurse: 1] on: StackOverflow do: [:ex | ex resume]] on: IllegalResumeAttempt do: [:ex | ex return: ex].
	self assert: (e isKindOf: IllegalResumeAttempt)
!
testDeepRecursionInAnotherProcess
	"As StackOverflowTest runs in a full heap: a legal depth the heap cannot hold, in a process of its own, ends in a StackOverflow, not a fatal error."
	| result done p |
	self isSmallHeap ifFalse: [^self].
	self fillWithLargeObjects.
	4 timesRepeat: [keep removeLast].
	Process maxStackDepth: 10000000.
	done := Semaphore new.
	p := [result := [self depth: 10000000] on: StackOverflow do: [:ex | ex return: ex]. done signal] fork.
	self deny: (done waitTimeoutMSecs: 60000).
	self assert: (result isKindOf: StackOverflow).
	self assert: result isHeapFull
! !
