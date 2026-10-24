TestCase subclass: #MarriedContextTest
	instanceVariableNames: 'log'
	classVariableNames: ''
	package: 'Tests-Kernel'!

MarriedContextTest comment: 'Tests activations whose frames got a Context by creating a closure (married Contexts, Interpreter): outer temps, non-local returns, exceptions, unwinding and reflection through them behave as with flushed Contexts. Each helper creates a closure, so its frame is married when the interesting part runs.'!

!MarriedContextTest methodsFor: 'running'!
setUp
	log := OrderedCollection new
! !

!MarriedContextTest methodsFor: 'helpers'!
sumDepth: n with: aBlock
	"n married frames, each adding its n to aBlock's value; mine is read before and after aBlock runs."
	| mine |
	mine := n.
	^n = 0
		ifTrue: [aBlock value]
		ifFalse: [[| before | before := mine. (self sumDepth: n - 1 with: aBlock) + before + (mine - before)] value]
!
ensureDepth: n with: aBlock
	| mine |
	mine := n.
	^[n = 0 ifTrue: [aBlock value] ifFalse: [(self ensureDepth: n - 1 with: aBlock) + mine]] ensure: [log add: mine]
!
returnFrom: n through: aBlock
	| mine |
	mine := n.
	^n = 0 ifTrue: [aBlock value] ifFalse: [[(self returnFrom: n - 1 through: aBlock) + mine] value]
!
returnThroughFrames
	self returnFrom: 5 through: [^42].
	^0
!
returnThroughEnsure
	^[self returnFrom: 3 through: [^42]] ensure: [log add: #ensured]
!
returnThroughIfCurtailed
	^[self returnFrom: 3 through: [^42]] ifCurtailed: [log add: #curtailed]
!
counter
	| n |
	n := 0.
	^Array with: [n := n + 1] with: [n]
!
deadReturner
	| t |
	t := 9.
	^[^t]
!
married: aBlock
	"aBlock gets this activation's married Context (temps: aBlock, x)."
	| x |
	x := 42.
	^aBlock value: [x] outerContext
!
chain: aBlock
	| t |
	t := 1.
	^[:x | aBlock value: thisContext] value: t
!
switchWith: aSemaphore holder: anArray
	| x blk |
	x := 1.
	blk := [x := x + 10].
	blk value.
	anArray at: 1 put: blk.
	aSemaphore signal.
	x := x + 100.
	blk value.
	^x
!
blockDepth: n
	^n = 0 ifTrue: [0] ifFalse: [[:k | (self blockDepth: k) + 1] value: n - 1]
! !

!MarriedContextTest methodsFor: 'tests'!
testOuterTempsBeforeAndAfterReturn
	| pair |
	pair := self counter.
	(pair at: 1) value.
	(pair at: 1) value.
	self assert: (pair at: 2) value = 2.
	self assert: (pair at: 1) outerContext isDead.
	self assert: ((pair at: 1) outerContext tempAt: 1) = 2
!
testNestedOuterTemps
	| a |
	a := 1.
	[:x | | b | b := 10. [:y | [a := a + x + y + b] value] value: 100] value: 1000.
	[[[a := a * 2] value] value] value.
	self assert: a = 2222
!
testNonLocalReturnThroughFrames
	self assert: self returnThroughFrames = 42
!
testNonLocalReturnThroughEnsure
	self assert: self returnThroughEnsure = 42.
	self assert: log asArray = #(#ensured)
!
testNonLocalReturnThroughIfCurtailed
	self assert: self returnThroughIfCurtailed = 42.
	self assert: log asArray = #(#curtailed)
!
testCannotReturn
	self assert: ([self deadReturner value] on: BlockCannotReturn do: [:e | e result]) = 9
!
testSignalResume
	self assert: ([self sumDepth: 5 with: [Warning signal: 'w']] on: Warning do: [:e | e resume: 100]) = 115
!
testSignalReturn
	self assert: ([self sumDepth: 5 with: [Error signal: 'e']] on: Error do: [:e | e return: 7]) = 7
!
testRetry
	| count |
	count := 0.
	self assert: ([count := count + 1. self sumDepth: 3 with: [count < 3 ifTrue: [Error signal] ifFalse: [0]]]
		on: Error do: [:e | e retry]) = 6.
	self assert: count = 3
!
testPass
	self assert: ([[self sumDepth: 3 with: [Error signal: 'p']] on: Error do: [:e | e pass]]
		on: Error do: [:e | e return: e messageText]) = 'p'
!
testEnsureUnwinding
	self assert: ([self ensureDepth: 3 with: [Error signal]] on: Error do: [:e | e return: -1]) = -1.
	self assert: log asArray = #(0 1 2 3).
	log removeAll.
	self assert: (self ensureDepth: 3 with: [0]) = 6.
	self assert: log asArray = #(0 1 2 3)
!
testSenderChains
	| blk |
	blk := [:ctx |
		self assert: ctx sender == ctx home.
		self assert: ctx home method == (MarriedContextTest >> #chain:).
		self assert: (ctx home tempAt: 2) = 1.
		self assert: ctx closure outerContext == ctx home.
		ctx home sender].
	self assert: (self chain: blk) == blk outerContext.
	self assert: blk outerContext == thisContext
!
testMarriedOuterContextReflection
	self assert: (self married: [:c | c receiver]) == self.
	self assert: (self married: [:c | c method]) == (MarriedContextTest >> #married:).
	self assert: (self married: [:c | c sender method]) == (MarriedContextTest >> #testMarriedOuterContextReflection).
	self assert: (self married: [:c | thisContext sender == c]).
	self assert: (self married: [:c | c tempAt: 2]) = 42.
	self assert: (self married: [:c | (c instVarAt: 4) selector]) == #married:.
	self assert: (self married: [:c | c printString]) = 'MarriedContextTest>>married:'.
	self deny: (self married: [:c | c isDead]).
	self assert: (self married: [:c | c shallowCopy method]) == (MarriedContextTest >> #married:).
	self assert: (self married: [:c | c]) isDead.
	self assert: ((self married: [:c | c]) tempAt: 2) = 42
!
testProcessSwitch
	| s h |
	s := Semaphore new.
	h := Array new: 1.
	[s wait. (h at: 1) value] forkAt: Processor activeProcess priority + 1.
	self assert: (self switchWith: s holder: h) = 131
!
testDeepRecursion
	| old ex |
	self assert: (self blockDepth: 100000) = 100000.
	old := Process maxStackDepth: 10000.
	[ex := [self blockDepth: 1000000000] on: StackOverflow do: [:e | e return: e]] ensure: [Process maxStackDepth: old].
	self assert: (ex isKindOf: StackOverflow)
! !
