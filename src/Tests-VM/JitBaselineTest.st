TestCase subclass: #JitBaselineTest
	instanceVariableNames: 'saved defined'
	classVariableNames: ''
	package: 'Tests-VM'!

JitBaselineTest comment: 'The baseline compiler, switched on for each test (Smalltalk vm jitParameters:, every method compiled on its first activation): inline caches through their states (jitSendSites), relinking after redefinition, unboxed Floats and temps in registers when Smalltalk runs in a slow path, non-local returns, closures, allocation, every ablation flag, code cache flushes, deep recursion, process switches, the listing.'!

!JitBaselineTest methodsFor: 'running'!
setUp
	saved := Smalltalk vm jitParameters: #('baseline' nil 0 5).
	defined := OrderedCollection new
!
tearDown
	| on flags |
	on := (saved at: 2) substrings: ','.
	flags := self flagNames inject: '' into: [:all :each |
		(all isEmpty ifTrue: [''] ifFalse: [all , ',']) , ((on includes: each) ifTrue: [each] ifFalse: ['-' , each])].
	Smalltalk vm jitParameters: {saved at: 1. flags. saved at: 3. saved at: 4}.
	defined do: [:each | each key removeSelector: each value]
!
timeLimitMilliseconds
	^120000
! !

!JitBaselineTest methodsFor: 'helpers'!
flagNames
	^#('arith' 'fuse' 'barrier' 'notes' 'embed' 'ic' 'pic' 'mega' 'regs' 'prims' 'access' 'alloc' 'float' 'blocks' 'nlr' 'quick' 'temps')
!
define: aString
	self define: aString in: JitBaselineTestSubject
!
define: aString in: aClass
	| m |
	m := aClass compile: aString.
	defined add: aClass -> (m isSymbol ifTrue: [m] ifFalse: [m selector])
!
subject
	^JitBaselineTestSubject new
!
statistics
	^Smalltalk vm statistics
!
sitesOf: aSelector
	^(JitBaselineTestSubject >> aSelector) jitSendSites
! !

!JitBaselineTest methodsFor: 'tests'!
testParameters
	| now |
	now := Smalltalk vm jitParameters.
	self assert: (now at: 1) equals: 'baseline'.
	self assert: Smalltalk vm jitMode equals: #baseline.
	self flagNames do: [:each | self assert: (self flagNames includes: each)].
	self should: [Smalltalk vm jitParameters: #(nil 'nonsense' nil nil)] raise: Error
!
testEveryMethodCompiles
	"Every method of the image has baseline code but those whose primitive is perform (the interpreter runs those sends)."
	| failed |
	failed := OrderedCollection new.
	Smalltalk allClasses do: [:c |
		{c. c class} do: [:k |
			k methodDict do: [:m | (m jitCode: 'baseline') isNil ifTrue: [failed add: m]]]].
	self assert: (failed allSatisfy: [:m | m selector beginsWith: 'perform:']) description: [failed printString]
!
testCompiledCodeRuns
	| before |
	self define: 'fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'.
	before := self statistics.
	self assert: (self subject fib: 20) equals: 6765.
	self assert: (self statistics - before) jitMethodsCompiled > 0
!
testInlineCacheStates
	"A send site goes monomorphic, polymorphic, megamorphic; it answers right in each state, and says which classes it saw."
	| s sites receivers |
	self define: 'foo ^0' in: Object.
	self define: 'foo ^1'.
	self define: 'foo ^2' in: JitBaselineTestOther.
	self define: 'poke: x ^x foo'.
	s := self subject.
	self assert: (s poke: s) equals: 1.
	self assert: (s poke: s) equals: 1.
	sites := self sitesOf: #poke:.
	self assert: sites size equals: 1.
	self assert: (sites first at: 2) equals: 1.
	self assert: (sites first at: 3) asArray equals: {JitBaselineTestSubject}.
	self assert: (s poke: JitBaselineTestOther new) equals: 2.
	self assert: (s poke: s) equals: 1.
	sites := self sitesOf: #poke:.
	self assert: (sites first at: 2) equals: 2.
	self assert: (sites first at: 3) asSet equals: {JitBaselineTestSubject. JitBaselineTestOther} asSet.
	receivers := {3. $a. 'str'. #(1). 2.5. nil. true. Object new}.
	receivers do: [:each | self assert: (s poke: each) equals: 0].
	sites := self sitesOf: #poke:.
	self assert: (sites first at: 2) equals: 3.
	receivers do: [:each | self assert: (s poke: each) equals: 0].
	self assert: (s poke: s) equals: 1.
	self assert: (s poke: JitBaselineTestOther new) equals: 2
!
testRedefinitionRelinks
	| s |
	self define: 'answer ^1'.
	self define: 'callAnswer ^self answer + 0'.
	s := self subject.
	3 timesRepeat: [self assert: s callAnswer equals: 1].
	self define: 'answer ^2'.
	self assert: s callAnswer equals: 2.
	self define: 'answer ^3' in: JitBaselineTestOther.
	self assert: JitBaselineTestOther new callAnswer equals: 3.
	self assert: s callAnswer equals: 2
!
testFloats
	| s |
	self define: 'f1: n | x | x := 0.0. 1 to: n do: [:i | x := x + (i * 0.5) - (i / 4)]. ^x'.
	self define: 'f2: p ^(p * 0.5) + ((3.0 @ 4.0 - p) * 1.2)'.
	self define: 'f3: i ^(i * 0.5) - (i / 4)'.
	self define: 'f4: x | a b | a := x * 0.5. b := a + 1.0. ^a * b + (a - b)'.
	self define: 'f5: x ^(x * 2.0) < (x + 1.5) ifTrue: [#less] ifFalse: [#more]'.
	self define: 'f6: x ^x * 1.0e300 * 1.0e300'.
	s := self subject.
	self assert: (s f1: 10) equals: 13.75.
	self assert: (s f2: 2 @ 4) equals: 2.2 @ 2.0.
	self assert: (s f3: 2) equals: 0.5.
	self assert: (s f3: 4) equals: 1.0.
	self assert: (s f4: 3) equals: 2.75.
	self assert: (s f5: 1.0) equals: #less.
	self assert: (s f5: 2) equals: #more.
	self assert: (s f6: 2.0) isInfinite.
	self assert: ((s f6: 1.0e-300) - 1.0e300) abs < 1.0e290
!
testUnboxedTempChangedInASlowPath
	"x is unboxed in a d register; the slow path of w + x runs a block that stores a String into x: the code goes on with x's new value."
	| w |
	self define: 'unboxed: w | x | w block: [x := ''abc'']. x := 2.0 * 1.0. w + x. ^x * 2.0'.
	w := self subject.
	self assert: ([self subject unboxed: w] on: MessageNotUnderstood do: [:e | e return: #dnu]) equals: #dnu
!
testLoopTempChangedInASlowPath
	"s lives in a register in the loop; the slow path of w + 1 runs a block that stores into it."
	self define: 'loop: w | s | w block: [s := 1000]. s := 0. 1 to: 3 do: [:i | s := s + i. w + 1. s := s + i]. ^s'.
	self assert: (self subject loop: self subject) equals: 1003
!
testNonLocalReturns
	| before |
	self define: 'firstAbove: n in: c c do: [:e | e > n ifTrue: [^e]]. ^nil'.
	self define: 'guarded: c ^[self firstAbove: 2 in: c] ensure: [a := #done]'.
	self define: 'unwinding: c [c do: [:e | e > 2 ifTrue: [^e]]] ensure: [b := #unwound]. ^nil'.
	self define: 'aState ^{a. b}'.
	before := self statistics.
	self assert: (self subject firstAbove: 2 in: #(1 2 3 4)) equals: 3.
	self assert: (self subject firstAbove: 5 in: #(1 2 3 4)) isNil.
	self assert: (self subject guarded: #(1 5)) equals: 5.
	self assert: (self subject unwinding: #(1 5); aState) equals: #(nil #unwound).
	self assert: (self statistics - before) jitNonLocalReturns > 0
!
testClosures
	self define: 'adder ^[:x | [:y | x + y]]'.
	self define: 'counter | n | n := 0. ^[n := n + 1]'.
	self define: 'sum: c ^c inject: 0 into: [:acc :e | acc + e]'.
	self define: 'nested: n | r | r := 0. 1 to: n do: [:i | #(1 2) do: [:k | r := r + (i * k)]]. ^r'.
	self assert: ((self subject adder value: 5) value: 3) equals: 8.
	self assert: (self subject counter value; value; value) equals: 3.
	self assert: (self subject sum: (1 to: 100)) equals: 5050.
	self assert: (self subject nested: 10) equals: 165
!
testAllocation
	| arrays objects |
	self define: 'arrays ^(1 to: 100) collect: [:i | Array new: i \\ 7]'.
	self define: 'objects ^(1 to: 100) collect: [:i | Object new]'.
	self define: 'bytes ^(ByteArray new: 5) , (String new: 3) asByteArray'.
	arrays := self subject arrays.
	self assert: (arrays collect: [:each | each size]) asArray equals: ((1 to: 100) collect: [:i | i \\ 7]) asArray.
	self assert: (arrays allSatisfy: [:each | each allSatisfy: [:x | x isNil]]).
	objects := self subject objects.
	self assert: (objects collect: [:each | each identityHash]) asSet size > 90.
	self assert: (objects allSatisfy: [:each | each identityHash > 0]).
	self assert: self subject bytes size equals: 8
!
testPrimitives
	"The primitives in machine code answer what their C functions answer, failures included."
	| on off |
	self define: 'prims: objs | r try ints strs | r := OrderedCollection new. try := [:b | r add: (b on: Error do: [:e | e class name])]. ints := {17. -17. 5. -5. 0. 1. -1. SmallInteger maxVal. SmallInteger minVal}. ints do: [:a | ints do: [:b | try value: [a quo: b]. try value: [a rem: b]. try value: [a // b]. try value: [a \\ b]]]. #(65 0 16r3FFFFFFF -1 16r40000000) do: [:v | try value: [(Character value: v) value]]. strs := #('''' ''a'' ''abc'' ''abd'' ''ab'' ''zz'' #abc) , {String with: (Character value: 300). 3}. strs do: [:x | strs do: [:y | try value: [x compare: y]]]. objs do: [:o | try value: [o basicSize]. 0 to: 10 do: [:i | try value: [o basicAt: i]. try value: [o basicAt: i put: i * 37]. try value: [o basicAt: i put: 300]. try value: [o basicAt: i put: nil]. try value: [o uint32At: i]. try value: [o uint32At: i put: 16rDEADBEEF]. try value: [o uint32At: i put: -1]]. r add: o printString]. ^r asArray'.
	on := self subject prims: {Array new: 5. ByteArray new: 9. Bitmap new: 3. 2 raisedTo: 100. 'abc' copy. #sym. 3. nil. Object new}.
	Smalltalk vm jitParameters: #(nil '-prims' nil nil).
	off := self subject prims: {Array new: 5. ByteArray new: 9. Bitmap new: 3. 2 raisedTo: 100. 'abc' copy. #sym. 3. nil. Object new}.
	Smalltalk vm jitParameters: #(nil 'prims' nil nil).
	self assert: on equals: off.
	self assert: (on first: 4) equals: #(1 0 1 0)
!
testNilTests
	"isNil and notNil compare with nil until a class defines them; then all code is dropped and they are sent."
	| other |
	self define: 'nilTests: x ^{x isNil. x notNil. x isNil ifTrue: [1] ifFalse: [2]}'.
	other := JitBaselineTestOther new.
	self assert: (self subject nilTests: nil) equals: #(true false 1).
	self assert: (self subject nilTests: other) equals: #(false true 2).
	self define: 'isNil ^true' in: JitBaselineTestOther.
	self assert: (self subject nilTests: other) equals: #(true true 1).
	self assert: (self subject nilTests: nil) equals: #(true false 1)
!
testNilTestsInline
	"In a fresh VM nothing but UndefinedObject and ProtoObject defines isNil: it compiles to a comparison."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. 'baseline'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'((Dictionary >> #at:ifAbsent:) machineCodeFor: #baseline) includesSubstring: ''isNil: == nil'''}).
	self assert: run output trimBoth equals: 'true'
!
testEveryFlagOff
	"Each optimization switched off alone: the same answers (loop temps stay in registers only across inline code)."
	self define: 'fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'.
	self define: 'pow: n | r b k | r := 1. b := 10. k := n. [k > 0] whileTrue: [(k bitAnd: 1) = 1 ifTrue: [r := r * b]. k := k bitShift: -1. k > 0 ifTrue: [b := b * b]]. ^r'.
	self define: 'mix: n | x a | x := 0.0. a := Array new: n. 1 to: n do: [:i | a at: i put: i * 2. x := x + (i / 2.0)]. ^{x. (a inject: 0 into: [:s :e | s + e]). a printString size}'.
	#('arith' 'fuse' 'barrier' 'ic' 'pic' 'mega' 'regs' 'prims' 'access' 'alloc' 'float' 'blocks' 'nlr' 'quick' 'temps') do: [:flag |
		Smalltalk vm jitParameters: {nil. '-' , flag. nil. nil}.
		self assert: (self subject fib: 15) equals: 610.
		self assert: (self subject mix: 20) equals: #(105.0 420 58).
		self assert: (self subject pow: 22) equals: 10000000000000000000000.
		Smalltalk vm jitParameters: {nil. flag. nil. nil}]
!
testCodeCacheFlush
	"A VM with a 1 MB code cache that keeps notes fills it often: all code is dropped and compiled again (inline caches, polymorphic caches and all), the results stay right."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. 'baseline'. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--jit-flags'. 'notes'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := 0. 10 timesRepeat: [r := r + (Compiler evaluate: ''(1 to: 10) inject: 0 into: [:a :b | a + b]'')]. String selectors do: [:s | Compiler compileMethod: (String >> s) source in: String classified: nil]. {r. Smalltalk vm statistics jitCacheFlushes > 0}'}).
	self assert: run output trimBoth equals: '#(550 true)'
!
testDeepRecursion
	| before |
	self define: 'depth: n ^n = 0 ifTrue: [0] ifFalse: [(self depth: n - 1) + 1]'.
	before := self statistics.
	self assert: (self subject depth: 300000) equals: 300000.
	self assert: (self statistics - before) frameFlushes > 0
!
testProcessSwitchesInCompiledLoops
	| ping pong done log |
	self define: 'ping: s pong: t log: log | r | r := 0. 1 to: 50 do: [:i | s signal. t wait. r := r + i. log add: i]. ^r'.
	ping := Semaphore new.
	pong := Semaphore new.
	log := OrderedCollection new.
	self fork: [1 to: 50 do: [:i | ping wait. log add: i negated. pong signal]].
	done := self subject ping: ping pong: pong log: log.
	self assert: done equals: 1275.
	self assert: log size equals: 100.
	self assert: (log first: 4) asArray equals: #(-1 1 -2 2)
!
testDisassembly
	| listing |
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | s := s + (i * 2.5)]. ^s'.
	listing := (JitBaselineTestSubject >> #sum:) machineCodeFor: #baseline.
	self assert: (listing beginsWith: 'JitBaselineTestSubject>>sum:  baseline').
	self assert: (listing includesSubstring: 'checked entry').
	self assert: (listing includesSubstring: 'stack check').
	self assert: (listing includesSubstring: 'native frame record').
	self assert: (listing includesSubstring: 'Floats').
	self assert: (listing includesSubstring: 'jump back: interrupt check').
	self assert: (listing includesSubstring: 'pop the frame and the record, return').
	self assert: (listing includesSubstring: '-- sum: n')
! !
