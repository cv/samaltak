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
	JitRuntimeTestSubject selectors do: [:each | JitRuntimeTestSubject removeSelector: each].
	JitRuntimeTestArray class selectors do: [:each | JitRuntimeTestArray class removeSelector: each]
!
timeLimitMilliseconds
	^120000
! !

!JitRuntimeTest methodsFor: 'helpers'!
isX64
	"The JIT emits x86-64 (listings name its registers and instructions)."
	^Smalltalk vm jitArchitecture = #x86_64
!
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
testActivationsFindCodeCompiledSinceTheEntryWasFilled
	"The send's cache entry counts answer's activations; answer is compiled at the fourth. Installing code leaves the entries as they are: the later activations through this one still enter the machine code. sends: must stay interpreted: a method compiled on its first activation (its hash shares a counter with others') calls answer from machine code, not through the entry; define it anew then."
	| before tries |
	Smalltalk vm jitParameters: #(nil nil 3 1000000).
	self define: 'answer | x | x := 1. ^x'.
	tries := 0.
	[self define: 'sends: n | s | s := 0. 1 to: n do: [:i | s := s + self answer]. ^s'.
	 before := self statistics.
	 self assert: (JitRuntimeTestSubject new sends: 20) equals: 20.
	 tries := tries + 1.
	 (JitRuntimeTestSubject >> #sends:) jitSendSites notNil and: [tries < 5]] whileTrue.
	self assert: (JitRuntimeTestSubject >> #sends:) jitSendSites isNil description: 'sends: was compiled'.
	self assert: (self statistics - before) jitEntries >= 17
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

!JitRuntimeTest methodsFor: 'tests: copying'!
replacements
	"Results and receivers of replaceFrom:to:with:startingAt: (or the error) for fresh receivers of every element kind and other objects, replacements of every kind and the receiver itself, ranges within, overlapping either way, empty, out of bounds, and other arguments; long ones too."
	| long wide dsts srcs ranges |
	self define: 'replaceIn: dsts from: srcs ranges: ranges | r | r := OrderedCollection new. dsts do: [:b | srcs do: [:s0 | ranges do: [:t | | d s | d := b value. s := s0 == #self ifTrue: [d] ifFalse: [s0]. r add: ([d replaceFrom: (t at: 1) to: (t at: 2) with: s startingAt: (t at: 3)] on: Error do: [:e | e class name]) printString , '' '' , d printString]]]. ^r asArray'.
	long := ((1 to: 700) collect: [:i | i \\ 251]) asByteArray.
	wide := String with: (Character value: 955) with: $b with: $c with: $d with: $e with: $f.
	dsts := {[#[1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20] copy]. ['abcdefghijklmnopqrst' copy]. [#abcdefghijklmnopqrst]. ['abcdefghijklmnopqrst' copy beReadOnlyObject; yourself].
		[wide copy]. [Bitmap withAll: (1 to: 20)]. [(1 to: 20) asArray]. [WeakArray new: 20].
		[(2 raisedTo: 160) + 12345]. [long copy]. [String new: 3]. [Array new: 0]. [OrderedCollection withAll: (1 to: 20)]}.
	srcs := {#self. #[101 102 103 104 105 106 107 108 109 110 111 112]. 'ABCDEFGHIJKL'. #ABCDEFGHIJKL. String with: (Character value: 1000) with: $Y with: $Z.
		Bitmap withAll: (100 to: 111). (101 to: 112) asArray. (101 to: 112) asOrderedCollection. long. 3. nil}.
	ranges := #(#(1 5 1) #(3 10 1) #(1 8 3) #(2 2 1) #(1 0 1) #(5 4 1) #(0 -1 1) #(1 0 0) #(6 5 99) #(0 3 1) #(1 3 0) #(1 21 1) #(18 22 1) #(1 3 11) #(1 3 12) #(5 3 1) #(1 1 -1) #(1 20 1) #(13 20 1) #(1 700 1) #(5 700 1) #(1 690 11) #(1 3 nil) #(nil 3 1) #(1 3.0 1) #(1 4611686018427387903 1)).
	^JitRuntimeTestSubject new replaceIn: dsts from: srcs ranges: ranges
!
testReplaceFromToWithStartingAt
	"replaceFrom:to:with:startingAt: in machine code copies and answers what its C function does, failures included (see replacements); the copies it does call no C function (the VM's counter, other Processes' calls included: the quietest of 3 rounds counts)."
	| on off calls |
	on := self replacements.
	Smalltalk vm jitParameters: #(nil '-prims' nil nil).
	[off := self replacements] ensure: [Smalltalk vm jitParameters: #(nil 'prims' nil nil)].
	self assert: on size equals: off size.
	1 to: on size do: [:i | self assert: (on at: i) equals: (off at: i)].
	self assert: (on includes: '#[1 2 1 2 3 4 5 6 7 8 11 12 13 14 15 16 17 18 19 20] #[1 2 1 2 3 4 5 6 7 8 11 12 13 14 15 16 17 18 19 20]').
	self define: 'copies: n | s t | s := ''abcdefghij''. t := Array new: 3. 1 to: n do: [:i | (s copyFrom: 2 to: 9) , ''xyz''. t replaceFrom: 1 to: 3 with: #(1 2 3) startingAt: 1]. ^t'.
	calls := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		JitRuntimeTestSubject new copies: 1000.
		(self statistics - before) jitPrimitiveCalls].
	self assert: calls min < 1000
!
testReplaceRemembersAnOldReceiver
	"Young objects copied into an old Array: it is remembered, the objects survive the scavenges (in their places)."
	| old |
	self define: 'fill: a times: n | young | 1 to: n do: [:i | young := (1 to: a size) collect: [:k | (k * i) printString]. a replaceFrom: 1 to: a size with: young startingAt: 1. Smalltalk vm scavenge. a replaceFrom: 2 to: a size with: a startingAt: 1. Smalltalk vm scavenge. a replaceFrom: 1 to: 1 with: young startingAt: 1. 1 to: a size do: [:k | (a at: k) = ((k - 1 max: 1) * i) printString ifFalse: [^k]]. Smalltalk vm garbageCollect]. ^0'.
	old := Array new: 50.
	Smalltalk vm garbageCollect.
	self assert: (JitRuntimeTestSubject new fill: old times: 5) equals: 0
! !

!JitRuntimeTest methodsFor: 'tests: copying'!
testReplaceKeepsItsSemantics
	"What code relies on, in compiled code: a copy within one object as memmove does it (either way), bytes into bytes of another class (ByteArray, ByteString, from a Symbol), 32-bit words into 32-bit words; elements of another width are the fallback's (a ByteString takes a wide Character by widening)."
	| expected |
	self define: 'semantics | r b | r := OrderedCollection new.
		b := ''hello world'' copy. b replaceFrom: 1 to: 5 with: b startingAt: 7. r add: b.
		b := ''0123456789'' copy. b replaceFrom: 3 to: 10 with: b startingAt: 1. r add: b.
		b := ((1 to: 300) collect: [:i | i \\ 256]) asByteArray. b replaceFrom: 1 to: 290 with: b startingAt: 11. r add: (b first: 3) asArray; add: (b last: 11) asArray.
		b := ((1 to: 300) collect: [:i | i \\ 256]) asByteArray. b replaceFrom: 11 to: 300 with: b startingAt: 1. r add: (b first: 12) asArray; add: (b last: 2) asArray.
		r add: ((ByteArray new: 3) replaceFrom: 1 to: 3 with: ''abc'' startingAt: 1).
		r add: ((String new: 3) replaceFrom: 1 to: 3 with: #[104 105 33] startingAt: 1).
		r add: ((String new: 4 withAll: $ ) replaceFrom: 2 to: 4 with: #symbol startingAt: 2).
		r add: ((ByteArray new: 2) replaceFrom: 1 to: 2 with: #ab startingAt: 1).
		r add: ((Bitmap new: 3) replaceFrom: 1 to: 3 with: (Bitmap withAll: #(7 8 9 10)) startingAt: 2) asArray.
		b := String new: 2. b replaceFrom: 1 to: 2 with: (String with: (Character value: 955) with: $x) startingAt: 1. r add: b isWideString; add: (b asArray collect: [:c | c value]).
		b := String with: (Character value: 955) with: $x with: $y. b replaceFrom: 2 to: 3 with: ''ab'' startingAt: 1. r add: (b asArray collect: [:c | c value]).
		r add: ([(ByteArray new: 2) replaceFrom: 1 to: 2 with: (Bitmap new: 2) startingAt: 1. #copied] on: Error do: [:e | #failed]).
		^r asArray'.
	expected := {'world world'. '0101234567'. #(11 12 13). #(44 35 36 37 38 39 40 41 42 43 44). #(1 2 3 4 5 6 7 8 9 10 1 2). #(33 34). #[97 98 99]. 'hi!!'. ' ymb'. #[97 98]. #(8 9 10). true. #(955 120). #(955 97 98). #copied}.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new semantics equals: expected]
!
testAllocationOfBytesAndWords
	"ByteArrays, ByteStrings, WideStrings and Bitmaps of sizes 0 to 70 and large ones come zeroed, of their size and class, with a hash; strings made of them compare and hash as literals do. Enough of them fill eden many times over (the slow path)."
	| scavenges |
	self define: 'allocs: n | r | r := OrderedCollection new. 0 to: n do: [:k | r add: (ByteArray new: k); add: (String new: k); add: (WideString new: k); add: (Bitmap new: k)]. #(4095 4096 4097 32767 32768 32769 100000) do: [:k | r add: (ByteArray new: k); add: (Bitmap new: k // 4)]. ^r'.
	self define: 'filled: k ^(String new: k) atAllPut: $a; yourself'.
	self define: 'churn: n | s | s := 0. 1 to: n do: [:i | s := s + (ByteArray new: i \\ 200) size + (String new: 3) size + (Bitmap new: i \\ 50) size]. ^s'.
	3 timesRepeat: [| objs |
		objs := JitRuntimeTestSubject new allocs: 70.
		self assert: objs size equals: 71 * 4 + 14.
		objs do: [:o |
			self assert: (o allSatisfy: [:e | e = 0 or: [e = (Character value: 0)]]).
			self assert: o identityHash > 0].
		0 to: 70 do: [:k |
			self assert: (objs at: 4 * k + 1) class equals: ByteArray.
			self assert: (objs at: 4 * k + 1) size equals: k.
			self assert: (objs at: 4 * k + 2) class equals: ByteString.
			self assert: (objs at: 4 * k + 2) size equals: k.
			self assert: (objs at: 4 * k + 3) class equals: WideString.
			self assert: (objs at: 4 * k + 3) size equals: k.
			self assert: (objs at: 4 * k + 4) class equals: Bitmap.
			self assert: (objs at: 4 * k + 4) size equals: k].
		self assert: ((objs last: 14) collect: [:o | o size]) asArray equals: #(4095 1023 4096 1024 4097 1024 32767 8191 32768 8192 32769 8192 100000 25000).
		0 to: 20 do: [:k |
			self assert: (JitRuntimeTestSubject new filled: k) equals: (String new: k withAll: $a).
			self assert: (JitRuntimeTestSubject new filled: k) hash equals: (String new: k withAll: $a) hash]].
	scavenges := self statistics scavenges.
	self assert: (JitRuntimeTestSubject new churn: 300000) equals: 300000 * 3 + (1500 * 199 * 200 / 2) + (6000 * 49 * 50 / 2).
	self assert: self statistics scavenges > scavenges
! !

!JitRuntimeTest methodsFor: 'tests: copying'!
testCopiesOfEveryLengthAndOverlap
	"replaceFrom:to:with:startingAt: in compiled code (the copy stub) against element by element copies: bytes, 32-bit words and pointers, every length up to 80 (40), within one object shifted either way by up to 9 elements (overlapping or not), and into another object between guard elements that stay."
	self define: 'within: b n: n by: o | e |
		e := b copy. 1 to: n do: [:i | e at: 40 + o + i - 1 put: (b at: 40 + i - 1)].
		b replaceFrom: 40 + o to: 40 + o + n - 1 with: b startingAt: 40. ^b = e'.
	self define: 'into: d from: s n: n at: k | e |
		e := d copy. 1 to: n do: [:i | e at: k + i - 1 put: (s at: i + 3)].
		d replaceFrom: k to: k + n - 1 with: s startingAt: 4. ^d = e'.
	self define: 'copies: make n: max | bad |
		bad := OrderedCollection new.
		0 to: max do: [:n |
			-9 to: 9 do: [:o | ((self within: (make value: 140) n: n by: o) and: [self into: (make value: 140) from: ((make value: 240) copyFrom: 101 to: 200) n: n at: 11 + o]) ifFalse: [bad add: n -> o]]].
		^bad asArray'.
	3 timesRepeat: [
		self assert: (JitRuntimeTestSubject new copies: [:k | ((1 to: k) collect: [:i | i * 7 \\ 251]) asByteArray] n: 80) equals: #().
		self assert: (JitRuntimeTestSubject new copies: [:k | Bitmap withAll: ((1 to: k) collect: [:i | i * 123457 \\ 16rFFFFFFFF])] n: 40) equals: #().
		self assert: (JitRuntimeTestSubject new copies: [:k | (1 to: k) collect: [:i | i printString]] n: 40) equals: #()]
! !

!JitRuntimeTest methodsFor: 'tests: allocation'!
testAllocationWhosePrimitiveFails
	"An allocation whose primitive fails answers what its fallback answers (here nil, or a String), and sends to it go to that: compiled code does not take it for an instance of the class."
	| o |
	JitRuntimeTestArray class compile: 'make: n <primitive: ''basicNew:'' error: ec> ^n = -1 ifTrue: [nil] ifFalse: [''fallback'' , ec printString]'.
	self define: 'make: n | x | x := JitRuntimeTestArray make: n. ^{x. x printString. x isNil}'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o make: 2) first class equals: JitRuntimeTestArray.
		self assert: (o make: -1) equals: {nil. 'nil'. true}.
		self assert: (o make: 1099511627776) equals: {'fallback1'. '''fallback1'''. false}]
! !
