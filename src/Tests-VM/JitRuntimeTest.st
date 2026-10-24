TestCase subclass: #JitRuntimeTest
	instanceVariableNames: 'saved'
	classVariableNames: ''
	package: 'Tests-VM'!

JitRuntimeTest comment: 'The JIT runtime under the template compiler, switched on for each test (Smalltalk vm jitParameters:, every method compiled on its first activation): on-stack replacement, methods redefined and become while their machine code runs, process switches in compiled loops, deep recursion, code cache flushes (a VM with a 1 MB cache), the annotated disassembly. JitTest runs the JIT inside the simulator.'!

!JitRuntimeTest methodsFor: 'running'!
setUp
	saved := Smalltalk vm jitParameters: #('template' nil 0 5)
!
tearDown
	| on flags |
	on := (saved at: 2) substrings: ','.
	flags := #('arith' 'fuse' 'barrier' 'notes' 'embed') inject: '' into: [:all :each |
		(all isEmpty ifTrue: [''] ifFalse: [all , ',']) , ((on includes: each) ifTrue: [each] ifFalse: ['-' , each])].
	Smalltalk vm jitParameters: {saved at: 1. flags. saved at: 3. saved at: 4}.
	JitRuntimeTestSubject selectors do: [:each | JitRuntimeTestSubject removeSelector: each]
!
timeLimitMilliseconds
	^120000
! !

!JitRuntimeTest methodsFor: 'helpers'!
define: aString
	JitRuntimeTestSubject compile: aString
!
statistics
	^Smalltalk vm statistics
! !

!JitRuntimeTest methodsFor: 'tests'!
testParameters
	| now |
	now := Smalltalk vm jitParameters.
	self assert: (now at: 1) equals: 'template'.
	self assert: (now at: 3) equals: 0.
	self assert: (now at: 4) equals: 5.
	self assert: ((now at: 2) substrings: ',') asSet equals: ((saved at: 2) substrings: ',') asSet.
	self should: [Smalltalk vm jitParameters: #('nonsense' nil nil nil)] raise: Error.
	self should: [Smalltalk vm jitParameters: #(nil 'nonsense' nil nil)] raise: Error.
	self assert: Smalltalk vm jitMode equals: #template
!
testCompiledCodeRuns
	| before |
	self define: 'fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new fib: 20) equals: 6765.
	self assert: (self statistics - before) jitMethodsCompiled > 0.
	self assert: (self statistics - before) jitEntries > 0
!
testOnStackReplacement
	"A loop in a method the interpreter started: compiled after 5 backward jumps and continued in machine code."
	| before |
	Smalltalk vm jitParameters: #(nil nil 1000 5).
	self define: 'loop: n | s | s := 0. 1 to: n do: [:i | s := s + i]. ^s'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new loop: 100000) equals: 5000050000.
	self assert: (self statistics - before) jitOsrEntries > 0
!
testRedefinitionWhileRunning
	"Machine code sending a method that is redefined meanwhile finds the new one; a running activation of a redefined method finishes with its old code."
	self define: 'answer | x | x := 1. ^x'.
	self define: 'sumWhileRedefining | s | s := 0. 1 to: 10 do: [:i | i = 6 ifTrue: [self class compile: ''answer | x | x := 2. ^x'']. s := s * 10 + self answer]. ^s'.
	self assert: JitRuntimeTestSubject new sumWhileRedefining equals: 1111122222.
	self define: 'phase | r | r := 1. self class compile: ''phase ^2''. ^r'.
	self assert: JitRuntimeTestSubject new phase equals: 1.
	self assert: JitRuntimeTestSubject new phase equals: 2
!
testBecomeOfACompiledMethod
	| o |
	self define: 'alpha | x | x := 1. ^x'.
	self define: 'beta | x | x := 2. ^x'.
	self define: 'callAlpha ^self alpha + 0'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [self assert: o callAlpha equals: 1].
	(JitRuntimeTestSubject >> #alpha) becomeForward: (JitRuntimeTestSubject >> #beta).
	self assert: o callAlpha equals: 2
!
testBecomeOfAnEmbeddedLiteral
	"With --jit-flags embed old literals are in the code: full GCs and become update them."
	| o old |
	Smalltalk vm jitParameters: #(nil 'embed' nil nil).
	self define: 'literal ^#(1 2 3) , #()'.
	Smalltalk vm garbageCollect.
	o := JitRuntimeTestSubject new.
	self assert: o literal equals: #(1 2 3).
	Smalltalk vm garbageCollect.
	self assert: o literal equals: #(1 2 3).
	old := (JitRuntimeTestSubject >> #literal) literals detect: [:each | each = #(1 2 3)].
	old becomeForward: #(4 5) copy.
	self assert: o literal equals: #(4 5)
!
testProcessSwitchesInCompiledLoops
	| ping pong done log p |
	self define: 'ping: s pong: t log: log | r | r := 0. 1 to: 50 do: [:i | s signal. t wait. r := r + i. log add: i]. ^r'.
	ping := Semaphore new.
	pong := Semaphore new.
	log := OrderedCollection new.
	done := nil.
	p := self fork: [1 to: 50 do: [:i | ping wait. log add: i negated. pong signal]].
	done := JitRuntimeTestSubject new ping: ping pong: pong log: log.
	self assert: done equals: 1275.
	self assert: log size equals: 100.
	self assert: (log first: 4) asArray equals: #(-1 1 -2 2)
!
testDeepRecursion
	| before |
	self define: 'depth: n ^n = 0 ifTrue: [0] ifFalse: [(self depth: n - 1) + 1]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new depth: 300000) equals: 300000.
	self assert: (self statistics - before) frameFlushes > 0
!
testCodeCacheFlush
	"A VM with a 1 MB code cache that keeps notes fills it often: all code is dropped and compiled again, the results stay right."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. 'template'. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--jit-flags'. 'notes'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := 0. 10 timesRepeat: [r := r + (Compiler evaluate: ''(1 to: 10) inject: 0 into: [:a :b | a + b]'')]. String selectors do: [:s | Compiler compileMethod: (String >> s) source in: String classified: nil]. {r. Smalltalk vm statistics jitCacheFlushes > 0}'}).
	self assert: run output trimBoth equals: '#(550 true)'
!
testDisassembly
	| listing |
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | s := s + (i * 2)]. ^s'.
	listing := (JitRuntimeTestSubject >> #sum:) machineCode.
	self assert: (listing beginsWith: 'JitRuntimeTestSubject>>sum:  template').
	self assert: (listing includesSubstring: 'pc 0: ').
	self assert: (listing includesSubstring: '-- sum: n').
	self assert: (listing includesSubstring: 'entry: x19').
	self assert: (listing includesSubstring: 'interrupt check').
	self assert: (listing includesSubstring: 'SmallInteger tag check').
	self assert: (listing includesSubstring: '<special send>').
	self assert: (listing includesSubstring: 'return top').
	self assert: (((JitRuntimeTestSubject >> #sum:) machineCodeFor: #template) beginsWith: 'JitRuntimeTestSubject>>sum:  template').
	self should: [(JitRuntimeTestSubject >> #sum:) machineCodeFor: #nonsense] raise: Error
! !
