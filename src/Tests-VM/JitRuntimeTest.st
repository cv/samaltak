TestCase subclass: #JitRuntimeTest
	instanceVariableNames: 'saved'
	classVariableNames: ''
	package: 'Tests-VM'!

JitRuntimeTest comment: 'The JIT runtime under the baseline compiler (JitOptRuntimeTest: under the optimizing tier), switched on for each test (Smalltalk vm jitParameters:, every method compiled on its first activation): on-stack replacement, methods redefined and become while their machine code runs, process switches in compiled loops, deep recursion, perform: (argument counts, failures, kinds of targets, many selectors at one site), code cache flushes (a VM with a 1 MB cache), the annotated disassembly. JitTest runs the JIT inside the simulator.'!

!JitRuntimeTest methodsFor: 'running'!
mode
	"The compiler under test."
	^'baseline'
!
setUp
	saved := Smalltalk vm jitParameters: {self mode. nil. 0. 5}
!
tearDown
	| on flags |
	on := (saved at: 2) substrings: ','.
	flags := #('arith' 'fuse' 'barrier' 'notes') inject: '' into: [:all :each |
		(all isEmpty ifTrue: [''] ifFalse: [all , ',']) , ((on includes: each) ifTrue: [each] ifFalse: ['-' , each])].
	Smalltalk vm jitParameters: {saved at: 1. flags. saved at: 3. saved at: 4}.
	JitRuntimeTestSubject selectors do: [:each | JitRuntimeTestSubject removeSelector: each]
!
timeLimitMilliseconds
	^120000
! !

!JitRuntimeTest methodsFor: 'helpers'!
disassemblyNotes
	"What the listing of sum: says, besides the bytecodes and the entry."
	^#('interrupt check' 'SmallInteger tag check' 'checked entry' 'return top')
!
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
	self assert: (now at: 1) equals: self mode.
	self assert: (now at: 3) equals: 0.
	self assert: (now at: 4) equals: 5.
	self assert: ((now at: 2) substrings: ',') asSet equals: ((saved at: 2) substrings: ',') asSet.
	self should: [Smalltalk vm jitParameters: #('nonsense' nil nil nil)] raise: Error.
	self should: [Smalltalk vm jitParameters: #(nil 'nonsense' nil nil)] raise: Error.
	self assert: Smalltalk vm jitMode equals: self mode asSymbol
!
testCompiledCodeRuns
	| before |
	self define: 'fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new fib: 20) equals: 6765.
	self assert: (self statistics - before) jitMethodsCompiled > 0
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
	"Old literals are in the code: full GCs and become update them."
	| o old |
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
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. self mode. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--jit-flags'. 'notes'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := 0. 10 timesRepeat: [r := r + (Compiler evaluate: ''(1 to: 10) inject: 0 into: [:a :b | a + b]'')]. String selectors do: [:s | Compiler compileMethod: (String >> s) source in: String classified: nil]. {r. Smalltalk vm statistics jitCacheFlushes > 0}'}).
	self assert: run output trimBoth equals: '#(550 true)'
!
testDisassembly
	| listing |
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | s := s + (i * 2)]. ^s'.
	listing := (JitRuntimeTestSubject >> #sum:) machineCode.
	self assert: (listing beginsWith: 'JitRuntimeTestSubject>>sum:  ' , self mode).
	self assert: (listing includesSubstring: 'pc 0: ').
	self assert: (listing includesSubstring: '-- sum: n').
	self disassemblyNotes do: [:each | self assert: (listing includesSubstring: each)].
	self assert: (((JitRuntimeTestSubject >> #sum:) machineCodeFor: self mode asSymbol) beginsWith: 'JitRuntimeTestSubject>>sum:  ' , self mode).
	self should: [(JitRuntimeTestSubject >> #sum:) machineCodeFor: #nonsense] raise: Error
! !

!JitRuntimeTest methodsFor: 'tests: perform'!
testPerform
	"perform: with up to four arguments and perform:withArguments: with up to two, selectors the sends do not know: once their targets are cached no lookups (inline cache misses) and no sends through the runtime; three arguments in an Array go through the interpreter. The counters are the VM's, other Processes' included: the quietest of 3 rounds counts."
	| o sels arrays deltas |
	self define: 'zero ^0'.
	self define: 'one: x ^x'.
	self define: 'two: x with: y ^x * 10 + y'.
	self define: 'three: x with: y with: z ^(x * 10 + y) * 10 + z'.
	self define: 'four: x with: y with: z with: w ^((x * 10 + y) * 10 + z) * 10 + w'.
	self define: 'performs: n with: s with: a | r | r := 0. 1 to: n do: [:i | r := r + (self perform: (s at: 1)) + (self perform: (s at: 2) with: 1) + (self perform: (s at: 3) with: 1 with: 2) + (self perform: (s at: 4) with: 1 with: 2 with: 3) + (self perform: (s at: 5) with: 1 with: 2 with: 3 with: 4) + (self perform: (s at: 1) withArguments: (a at: 1)) + (self perform: (s at: 2) withArguments: (a at: 2)) + (self perform: (s at: 3) withArguments: (a at: 3))]. ^r'.
	self define: 'call: s withArguments: a ^self perform: s withArguments: a'.
	o := JitRuntimeTestSubject new.
	sels := #(#zero #one: #two:with: #three:with:with: #four:with:with:with:).
	arrays := #(#() #(1) #(1 2)).
	self assert: (o performs: 10 with: sels with: arrays) equals: 13830.
	deltas := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		self assert: (o performs: 3000 with: sels with: arrays) equals: 4149000.
		self statistics - before].
	self assert: (deltas collect: [:d | d jitInlineCacheMisses]) min < 300.
	self assert: (deltas collect: [:d | d optRuntimeSends]) min < 300.
	3 timesRepeat: [
		self assert: (o call: #three:with:with: withArguments: #(1 2 3)) equals: 123.
		self assert: (o call: #four:with:with:with: withArguments: #(1 2 3 4)) equals: 1234]
!
testPerformWithTheWrongArgumentCount
	"A selector of another argument count, or arguments not in an Array: the primitive fails, as in the interpreter."
	| o |
	self define: 'one: x ^x'.
	self define: 'call: s ^self perform: s'.
	self define: 'call: s with: x with: y ^self perform: s with: x with: y'.
	self define: 'call: s withArguments: a ^self perform: s withArguments: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self should: [o call: #one:] raise: Error.
		self should: [o call: #one: with: 1 with: 2] raise: Error.
		self should: [o call: #one: withArguments: #(1 2)] raise: Error.
		self should: [o call: #one: withArguments: (OrderedCollection with: 1)] raise: Error.
		self assert: (o call: #one: withArguments: #(5)) equals: 5]
!
testPerformNotUnderstood
	"A selector not understood: doesNotUnderstand: gets it and the arguments."
	| o |
	self define: 'doesNotUnderstand: aMessage ^{aMessage selector. aMessage arguments}'.
	self define: 'call: s with: x ^self perform: s with: x'.
	self define: 'call: s withArguments: a ^self perform: s withArguments: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o call: #noSuchSelector: with: 7) equals: #(#noSuchSelector: #(7)).
		self assert: (o call: #noSuch:selector: withArguments: #(1 2)) equals: #(#noSuch:selector: #(1 2))]
!
testPerformOfPerform
	| o |
	self define: 'plus: x ^x + 1'.
	self define: 'twice: x ^self perform: #perform:with: with: #plus: with: x'.
	self define: 'call: p with: s with: x ^self perform: p with: s with: x'.
	self define: 'call: p with: s withArguments: a ^self perform: p with: s with: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o twice: 1) equals: 2.
		self assert: (o call: #perform:with: with: #plus: with: 2) equals: 3.
		self assert: (o call: #perform:withArguments: with: #plus: withArguments: #(4)) equals: 5.
		self assert: (o perform: #perform: with: #yourself) == o]
!
testPerformTargets
	"Targets that are primitives in machine code, through their C function (one failing into its body), quick methods, a closure, a method not compiled yet."
	| o block |
	self define: 'x ^a'.
	self define: 'x: v a := v'.
	self define: 'call: r with: s ^r perform: s'.
	self define: 'call: r with: s with: v ^r perform: s with: v'.
	o := JitRuntimeTestSubject new.
	block := [:v | v * 2].
	3 timesRepeat: [
		self assert: (o call: 3 with: #+ with: 4) equals: 7.
		self assert: (o call: 3 with: #+ with: 2.5) equals: 5.5.
		self assert: (o call: #(10 20 30) with: #at: with: 2) equals: 20.
		self assert: (o call: 'abc' with: #size) equals: 3.
		self assert: (o call: #(1 2) with: #shallowCopy) equals: #(1 2).
		self assert: (o call: o with: #x: with: 5) == o.
		self assert: (o call: o with: #x) equals: 5.
		self assert: (o call: o with: #yourself) == o.
		self assert: (o call: nil with: #isNil).
		self assert: (o call: block with: #value: with: 21) equals: 42].
	Smalltalk vm jitParameters: #(nil nil 1000 nil).
	self define: 'fresh: v ^v + 1'.
	3 timesRepeat: [self assert: (o call: o with: #fresh: with: 1) equals: 2]
!
testPerformManySelectorsAndClasses
	"One perform: site, ten receiver classes and eleven selectors."
	| o receivers selectors |
	self define: 'call: r with: s ^r perform: s'.
	o := JitRuntimeTestSubject new.
	receivers := {3. 4.5. $a. 'str'. #sym. #(1 2). nil. Object new. 1 / 2. o}.
	selectors := #(#yourself #isNil #notNil #isString #isSymbol #isNumber #isCharacter #printString #class #isArray #isInteger).
	2 timesRepeat: [
		receivers do: [:r |
			self assert: (selectors collect: [:s | o call: r with: s]) equals: {r yourself. r isNil. r notNil. r isString. r isSymbol. r isNumber. r isCharacter. r printString. r class. r isArray. r isInteger}]]
!
testPerformAfterRedefinition
	"The method perform: finds is redefined while its target is cached: the next one finds the new method."
	self define: 'answer ^1'.
	self define: 'sumPerforming: s | t | t := 0. 1 to: 10 do: [:i | i = 6 ifTrue: [self class compile: ''answer ^2'']. t := t * 10 + (self perform: s)]. ^t'.
	self assert: (JitRuntimeTestSubject new sumPerforming: #answer) equals: 1111122222
!
testPerformDeepRecursion
	"Recursion through perform:with: (a selector the send knows, and one it does not) deeper than the C stack: the frames become Contexts."
	| before |
	self define: 'depth: n ^n = 0 ifTrue: [0] ifFalse: [(self perform: #depth: with: n - 1) + 1]'.
	self define: 'depth: n via: s ^n = 0 ifTrue: [0] ifFalse: [(self perform: s with: n - 1 with: s) + 1]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new depth: 200000) equals: 200000.
	self assert: (JitRuntimeTestSubject new depth: 200000 via: #depth:via:) equals: 200000.
	self assert: (self statistics - before) frameFlushes > 0
!
testPerformWithProcessSwitches
	"A process wakes up every millisecond while perform: enters methods (their arguments moved down over the selector): interrupts at their entries switch to it, the results stay right."
	| o result ticks stop |
	self define: 'sum: n via: s | t | t := 0. 1 to: n do: [:i | t := t + (self perform: s with: i with: 1)]. ^t'.
	self define: 'add: x to: y ^x + y'.
	o := JitRuntimeTestSubject new.
	ticks := 0.
	stop := false.
	self fork: [[stop] whileFalse: [(Delay forMilliseconds: 1) wait. ticks := ticks + 1]] at: Processor activePriority + 1.
	"a loaded machine may wake it late: until it has woken up during a run"
	[[result := o sum: 1000000 via: #add:to:.
	  self assert: result equals: 500001500000.
	  ticks = 0] whileTrue] ensure: [stop := true]
! !
