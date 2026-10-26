JitRuntimeTest subclass: #JitOptRuntimeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitOptRuntimeTest comment: 'JitRuntimeTest under the optimizing tier (--jit opt, --jit-flags eager: every method optimized at its first count), and what only it does: deoptimizing a failed speculation, invalidating inlined code while it runs, the deoptimization stress.'!

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
	^#('interrupt check' 'guard: a SmallInteger' 'frame pc and sp')
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
! !
