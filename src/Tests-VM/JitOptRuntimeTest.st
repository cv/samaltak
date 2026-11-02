JitRuntimeTest subclass: #JitOptRuntimeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitOptRuntimeTest comment: 'JitRuntimeTest under the optimizing tier (--jit opt, --jit-flags eager: every method optimized at its first count), and what only it does: deoptimizing a failed speculation, and not where nothing was speculated (perform:, doesNotUnderstand:, SmallIntegers beside Floats, BoxedFloat64s), invalidating inlined code while it runs, the deoptimization stress.'!

!JitOptRuntimeTest methodsFor: 'running'!
mode
	^'opt'
!
setUp
	saved := Smalltalk vm jitParameters: {self mode. 'eager'. 0. 5}
!
tearDown
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	super tearDown
! !

!JitOptRuntimeTest methodsFor: 'helpers'!
disassemblyNotes
	^#('interrupt check' 'guard: a SmallInteger' 'frame pc and sp' 'entry: x19')
!
stressed
	"--jit-flags deopt: optimized code deoptimizes every so often anyway."
	^((Smalltalk vm jitParameters at: 2) substrings: ',') includes: 'deopt'
! !

!JitOptRuntimeTest methodsFor: 'tests'!
testParameters
	| now |
	now := Smalltalk vm jitParameters.
	self assert: (now at: 1) equals: self mode.
	self assert: (((now at: 2) substrings: ',') includes: 'eager').
	self assert: Smalltalk vm jitMode equals: self mode asSymbol
!
testDeoptimizationOfASpeculation
	"SmallInteger arithmetic speculated from feedback: a Float deoptimizes to the send, the next compilation takes Floats too."
	| o before |
	self define: 'twice: x ^x + x'.
	self define: 'sumTwice: n | s | s := 0. 1 to: n do: [:i | s := s + (self twice: i)]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o sumTwice: 1000) equals: 1001000.
	before := self statistics.
	self assert: (o twice: 1.5) equals: 3.0.
	self assert: (o twice: 1/2) equals: 1.
	self assert: (o sumTwice: 1000) equals: 1001000.
	self assert: (self statistics - before) optDeoptimizations + (self statistics - before) optMethodsCompiled > 0
!
testInvalidationWhileRunning
	"A method inlined into running optimized code (a loop's unit, from feedback) is redefined: the code is invalidated, the running activation continues with the new method."
	| before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'answer ^1'.
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | i = n ifTrue: [self class compile: ''answer ^2'']. s := s + self answer]. ^s'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new sum: 20000) equals: 20001.
	self assert: (self statistics - before) optInvalidations > 0
!
testPerformInALoopStaysOptimized
	"perform: and perform:with: of constant selectors are sends of them, perform:withArguments: calls its machine code: a loop of them neither deoptimizes nor sends through the runtime (unless --jit-flags deopt makes it)."
	| o before |
	self define: 'one ^1'.
	self define: 'plus: x ^x + 1'.
	self define: 'performs: n | s a | s := 0. a := Array new: 1. 1 to: n do: [:i | a at: 1 put: i. s := s + (self perform: #one) + (self perform: #plus: with: i) + (i perform: #+ with: 1) + (self perform: #plus: withArguments: a)]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o performs: 100) equals: 15550.
	before := self statistics.
	self assert: (o performs: 10000) equals: 150055000.
	self stressed ifFalse: [
		self assert: (self statistics - before) optDeoptimizations < 1000.
		self assert: (self statistics - before) optRuntimeSends < 50]
!
testPerformOfAConstantIsInlined
	"perform: of a constant selector is a send of it, inlined into a loop's unit: redefining the method invalidates the code, the loop goes on with the new one."
	| before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'answer ^1'.
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | i = n ifTrue: [self class compile: ''answer ^2'']. s := s + (self perform: #answer)]. ^s'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new sum: 20000) equals: 20001.
	self assert: (self statistics - before) optInvalidations > 0
!
testNotUnderstoodInALoopStaysOptimized
	"A selector not understood in optimized code: the runtime sends doesNotUnderstand: with its Message, a loop of them does not deoptimize every time (unless --jit-flags deopt makes it)."
	| o before |
	self define: 'doesNotUnderstand: aMessage ^aMessage arguments isEmpty ifTrue: [1] ifFalse: [aMessage arguments first]'.
	self define: 'unknowns: n | s | s := 0. 1 to: n do: [:i | s := s + self unknownUnary + (self unknownWith: i)]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o unknowns: 100) equals: 5150.
	before := self statistics.
	self assert: (o unknowns: 10000) equals: 50015000.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations < 1000]
!
testCallsTakeMachineCode
	"What optimized code does not inline it calls as baseline code does, through no runtime: primitives in machine code (uint32At:put:, uint32At:, identityHash), a method too big to inline, a megamorphic send, a block it did not make."
	| o bytes block mixed before |
	self define: 'big: x | a | a := x. ' , ((1 to: 150) inject: '' into: [:all :i | all , 'a := a. ']) , '^a'.
	self define: 'callsIn: bytes block: b mixed: m n: n | s | s := 0. 1 to: n do: [:i | bytes uint32At: 1 put: i. s := s + (bytes uint32At: 1) + (bytes identityHash bitAnd: 0) + (b value: i) + (self big: 0) + ((m at: i \\ m size + 1) yourself == nil ifTrue: [1] ifFalse: [0])]. ^s'.
	o := JitRuntimeTestSubject new.
	bytes := ByteArray new: 8.
	block := [:x | x * 2].
	mixed := {1. 'a'. #b. 2.5. nil. $c. Object new}.
	self assert: (o callsIn: bytes block: block mixed: mixed n: 700) equals: 736150.
	before := self statistics.
	self assert: (o callsIn: bytes block: block mixed: mixed n: 7000) equals: 73511500.
	self stressed ifFalse: [self assert: (self statistics - before) optRuntimeSends < 50]
!
testClosureTheFrameMadeInALoopUnit
	"A loop's unit (entered at on-stack replacement) inlines the closures its frame made before the loop, guarded: one that stores a temp, one that returns from the method, one the temp stops holding (another closure: the guard fails, deoptimize)."
	| o |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'count: n | k b | k := 0. b := [k := k + 1]. 1 to: n do: [:i | b value]. ^k'.
	self define: 'find: n | b | b := [:x | x = n ifTrue: [^x]]. 1 to: n * 2 do: [:i | b value: i]. ^0'.
	self define: 'other ^[:x | x + 2]'.
	self define: 'switch: n | s b | s := 0. b := [:x | x + 1]. 1 to: n do: [:i | i = (n // 2) ifTrue: [b := self other]. s := b value: s]. ^s'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o count: 30000) equals: 30000.
		self assert: (o find: 30000) equals: 30000.
		self assert: (o switch: 30000) equals: 45001]
!
testProcessPrimitivesThatDoNotSwitch
	"signal and wait that switch no process (their C primitives commit their results) return into the optimized code that called them."
	| o s |
	self define: 'signalAndWait: s n: n | k | k := 0. 1 to: n do: [:i | s signal. s wait. k := k + 1]. ^k'.
	o := JitRuntimeTestSubject new.
	s := Semaphore new.
	3 timesRepeat: [self assert: (o signalAndWait: s n: 1000) equals: 1000]
!
testPerformTheRuntimeDoesNotSend
	"The interpreter does what perform: cannot send from optimized code: a selector not understood, perform: again, the wrong number of arguments; a frame without room (recursion through perform:with:)."
	| o |
	self define: 'doesNotUnderstand: aMessage ^aMessage arguments first'.
	self define: 'plus: x ^x + 1'.
	self define: 'unknown: x ^self perform: #noSuchSelector: with: x'.
	self define: 'twice: x ^self perform: #perform:with: with: #plus: with: x'.
	self define: 'wrong ^self perform: #plus:'.
	self define: 'deep: n block: b ^n = 0 ifTrue: [0] ifFalse: [1 + (b perform: #value: with: n - 1)]'.
	self define: 'deep: n | b | b := [:k | self deep: k block: b]. ^self deep: n block: b'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o unknown: 7) equals: 7.
		self assert: (o twice: 1) equals: 2.
		self should: [o wrong] raise: Error.
		self assert: (o deep: 20000) equals: 20000]
!
testPerformedPrimitiveThatMakesFramesContexts
	"A primitive perform: sends from optimized code makes the frames Contexts before it answers (new JIT flags): the Context has its receiver and arguments, the answer replaces them."
	self define: 'modeVia: vm ^(vm perform: #jitParameters: with: #(nil ''eager'' nil nil)) first'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new modeVia: Smalltalk vm) equals: self mode]
!
testIntegerArithmeticBesideFloats
	"Where only other arithmetic of the method saw Floats the optimized code also takes two SmallIntegers: it does not deoptimize and compile again, site after site (unless --jit-flags deopt makes it)."
	| o a before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'mixed: a | s f | s := 0. f := 0. 1 to: a size do: [:i | f := f + (a at: i). s := s + (i \\ 7) - (i // 3)]. ^s + f'.
	o := JitRuntimeTestSubject new.
	a := (1 to: 100000) asArray collect: [:i | i / 2.0].
	before := self statistics.
	self assert: (o mixed: a) equals: 833675000.0.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations < 2]
!
testBoxedFloatsInFloatArithmetic
	"BoxedFloat64s (the infinities, NaN) are decoded as SmallFloat64s are: comparing them does not deoptimize (unless --jit-flags deopt makes it); NaN compares false."
	| o a before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'atMostOne: a | n | n := 0. 1 to: a size do: [:i | (a at: i) <= 1.0 ifTrue: [n := n + 1]]. ^n'.
	o := JitRuntimeTestSubject new.
	a := (1 to: 30000) asArray collect: [:i | i \\ 3 = 0 ifTrue: [Float infinity] ifFalse: [i \\ 5 = 0 ifTrue: [Float nan] ifFalse: [i \\ 7 = 0 ifTrue: [Float negativeInfinity] ifFalse: [i / 30000.0]]]].
	before := self statistics.
	5 timesRepeat: [self assert: (o atMostOne: a) equals: 16000].
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations < 2]
!
testBlockCallWithoutRoomForItsFrame
	"Optimized code calls a block while the stack is full: the frames become Contexts for its frame, the interpreter goes on from there."
	self define: 'deep: n block: b ^n = 0 ifTrue: [0] ifFalse: [1 + (b value: n - 1)]'.
	self define: 'deep: n | b | b := [:k | self deep: k block: b]. ^self deep: n block: b'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new deep: 20000) equals: 20000]
!
testSendToAMarriedContext
	"A Context married to a frame keeps its state in the frame: optimized code does not inline its methods (from feedback) nor call them directly; the runtime's send makes it a Context first."
	| o |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'senderOf: x ^x sender'.
	self define: 'probe ^self senderOf: [:a | a] outerContext'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:i | self assert: (o probe isKindOf: Context)]
!
testNonLocalReturnThroughAMarriedLoop
	"thisContext makes the frames Contexts; each:'s Context goes on married to a frame in its loop's unit, whose frame has more slots than the Context holds. A non-local return through it fills the Context, not the object after it (the block's Context)."
	| o r |
	self define: 'setA: x b: y a := x. b := y'.
	self define: 'each: aBlock 1 to: b do: [:i | aBlock value: (a at: i)]'.
	self define: 'callerContext ^thisContext sender'.
	self define: 'escape | c n | self each: [:x | x = 1 ifTrue: [c := self callerContext. n := c basicSize]. x = 50 ifTrue: [^{c. n}]]. ^nil'.
	o := JitRuntimeTestSubject new setA: (1 to: 100) asArray b: 100; yourself.
	3 timesRepeat: [
		r := o escape.
		self assert: r first basicSize equals: r last]
!
testEntryFromBaselineCodeWithoutRoom
	"Baseline code (thisContext keeps down: from being optimized) calls optimized code with many temps while the stack is nearly full: its entry checks for room as the baseline entry it took over did."
	self define: 'down: n ^n = 0 ifTrue: [thisContext. 0] ifFalse: [(self many: n) + 0]'.
	self define: 'many: n | a b c d e f g h i j k l | a := n. b := a. c := b. d := c. e := d. f := e. g := f. h := g. i := h. j := i. k := j. l := k. ^(self down: l - 1) + 1'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new down: 30000) equals: 30000]
!
testDeoptimizationStress
	"--jit-flags deopt: optimized code deoptimizes every so often at its guards and safepoints; the compiler's tests still pass."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. 'opt'. '--jit-threshold'. '0'. '--jit-flags'. 'eager,deopt'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := TestCase runNamed: #(''Tests-Compiler''). {r failures size + r errors size. r runCount > 0. Smalltalk vm statistics optDeoptimizations > 0}'}).
	self assert: (run output trimBoth endsWith: '#(0 true true)')
!
testDisassemblyShowsInlinedActivations
	| listing |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'inc: x ^x + 1'.
	self define: 'sumInc: n | s | s := 0. 1 to: n do: [:i | s := s + (self inc: i)]. ^s'.
	self assert: (JitRuntimeTestSubject new sumInc: 20000) equals: 200030000.
	listing := (JitRuntimeTestSubject >> #sumInc:) machineCodeFor: #opt.
	self assert: (listing beginsWith: 'JitRuntimeTestSubject>>sumInc:  opt').
	self assert: (listing includesSubstring: 'inlined activation 1')
!
testDisassemblyLeavesFeedback
	"A listing of code compiled without notes compiles a copy: the Float the method's baseline code saw stays feedback, its optimized code takes Floats."
	| m |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'add: x to: y ^x + y'.
	m := JitRuntimeTestSubject >> #add:to:.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new add: 1.5 to: 2.5) equals: 4.0].
	self assert: ((m machineCodeFor: #opt) includesSubstring: 'fadd').
	self assert: ((m machineCodeFor: #baseline) beginsWith: 'JitRuntimeTestSubject>>add:to:  baseline').
	self assert: ((m machineCodeFor: #opt) includesSubstring: 'fadd')
!
testCharacterValueGuardsItsArgumentFirst
	"Character value: inlined (feedback) for a value not known to be a SmallInteger: the guard on it comes before the conversion, which reads the guard's result."
	| listing g |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'char: n ^Character value: n'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new char: 65) equals: $A].
	listing := (JitRuntimeTestSubject >> #char:) machineCodeFor: #opt.
	g := listing indexOfSubCollection: 'guard: a SmallInteger'.
	self assert: (g > 0 and: [g < (listing indexOfSubCollection: 'the Character of a SmallInteger')])
!
testClosureMadeBeforeALoopStoresATemp
	"The closure, inlined into the loop, stores a temp of the loop's activation: the loop does not keep the temp's value on entry."
	self define: 'storeInLoop | n b | n := 0. b := [n := n + 1]. 1 to: 3 do: [:i | b value]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInLoop equals: 3]
!
testClosureStoresATempInNestedLoops
	self define: 'storeInNestedLoops | n b | n := 0. b := [n := n + 1]. 1 to: 3 do: [:i | 1 to: 4 do: [:j | b value]]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInNestedLoops equals: 12]
!
testClosureStoresATempInAWhileLoop
	self define: 'storeInWhileLoop | n k b | n := 0. k := 0. b := [n := n + 2]. [k < 5] whileTrue: [b value. k := k + 1]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInWhileLoop equals: 10]
!
testClosureAndLoopStoreATemp
	self define: 'storeInLoopAndClosure | n b | n := 0. b := [n := n * 2]. 1 to: 3 do: [:i | n := n + i. b value]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInLoopAndClosure equals: 22]
!
testClosureMadeInALoopStoresATemp
	self define: 'storeInLoopBlock | n | n := 0. 1 to: 3 do: [:i | [n := n + i] value]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInLoopBlock equals: 6]
!
testClosureCalledConditionallyInALoop
	self define: 'storeSometimes | n b | n := 0. b := [n := n + 1]. 1 to: 10 do: [:i | (i bitAnd: 1) = 1 ifTrue: [b value]]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeSometimes equals: 5]
!
testClosureStoresATempOfAnInlinedBlock
	"The loop and the closure belong to a block inlined into the method."
	self define: 'storeInBlockLoop ^[:k | | n b | n := 0. b := [n := n + 1]. 1 to: k do: [:i | b value]. n] value: 3'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInBlockLoop equals: 3]
!
testClosurePassedToAMethodInALoop
	"The closure reaches the loop through an inlined method (from feedback: optimized after 1000 counts)."
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'call: aBlock ^aBlock value'.
	self define: 'storeThroughCall | n b | n := 0. b := [n := n + 1]. 1 to: 3 do: [:i | self call: b]. ^n'.
	3000 timesRepeat: [self assert: JitRuntimeTestSubject new storeThroughCall equals: 3]
!
testCountSharedWithAFailedMethod
	"Methods count toward optimization in slots by identity hash (modulo 65536). One the optimizer cannot compile ({} is not compiled) leaves its slot counting: a method sharing it is still optimized."
	| failing plain o before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'failing: x ^{x}'.
	self define: 'plain: x ^x + 1'.
	self define: 'plain: x times: n 1 to: n do: [:i | self plain: x]. ^{x}'.
	failing := JitRuntimeTestSubject >> #failing:.
	plain := JitRuntimeTestSubject >> #plain:.
	"one slot, two hashes: failures are remembered by hash"
	[(plain identityHash bitAnd: 16rFFFF) = (failing identityHash bitAnd: 16rFFFF) and: [plain identityHash ~= failing identityHash]] whileFalse: [plain := plain shallowCopy].
	JitRuntimeTestSubject addSelectorSilently: #plain: withMethod: plain.
	o := JitRuntimeTestSubject new.
	"plain: counts in the slot before failing: fails (installing its code later would start the count over)"
	o plain: 0.
	before := self statistics.
	3000 timesRepeat: [o failing: 0].
	self assert: (self statistics - before) optCompileFailures > 0.
	"plain:times: fails too ({}): what is compiled is plain:"
	before := self statistics.
	o plain: 0 times: 3000.
	self assert: (self statistics - before) optMethodsCompiled > 0
! !
