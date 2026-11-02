TestCase subclass: #LazyContextTest
	instanceVariableNames: 'log'
	classVariableNames: ''
	package: 'Tests-Kernel'!

LazyContextTest comment: 'Tests Contexts married to the VM''s frames (thisContext, senders, the handler and unwind contexts the primitives find): their identity, what reading and writing them answers before and after their frames are flushed, the primitives nextHandlerContext, findNextUnwindContextUpTo: and terminateTo:, and that handling exceptions and unwinding flush no frames.'!

!LazyContextTest methodsFor: 'running'!
setUp
	log := OrderedCollection new
! !

!LazyContextTest methodsFor: 'helpers'!
answerSender
	^thisContext sender
!
answerContext
	| t |
	t := 7.
	^thisContext
!
flushFrames
	"Switch to another process and back: a process switch flushes the frames."
	| s |
	s := Semaphore new.
	[s signal] forkAt: Processor activePriority.
	s wait
!
fieldsOf: aContext
	"What Smalltalk reads of aContext."
	^{aContext sender. aContext pc. aContext stackp. aContext method. aContext receiver. aContext closure. aContext tempAt: 1. aContext tempAt: 2. aContext instVarAt: 1. aContext instVarAt: 2. aContext instVarAt: 3. aContext instVarAt: 9. aContext size. aContext isDead. aContext printString}
!
readTwice: aContext
	"aContext's fields from the same pc: first as it is, then after a flush."
	| result |
	result := OrderedCollection new.
	1 to: 2 do: [:i |
		result add: (self fieldsOf: aContext).
		i = 1 ifTrue: [self flushFrames]].
	^result
!
married: x with: y
	"Two arguments, a temp: the frame of this activation is read through its Context."
	| t |
	t := x + y.
	^self readTwice: thisContext
!
setSenderTemp: index to: anObject
	thisContext sender tempAt: index put: anObject
!
setSenderSlot: index to: anObject
	thisContext sender instVarAt: 6 + index put: anObject
!
handlerOf: aBlock
	^[aBlock value] on: ZeroDivide do: [:e | e return: 0]
!
unwindIn: aBlock
	^[aBlock value] ensure: [log add: #ensured]
!
deep: n do: aBlock
	"n frames, then aBlock."
	^n = 0 ifTrue: [aBlock value] ifFalse: [(self deep: n - 1 do: aBlock) yourself]
!
terminateCallerOf: aContext
	"Return 5 to aContext's caller: the activations between are dropped."
	thisContext terminateTo: aContext sender.
	^5
!
middle: aBlock
	log add: #middle.
	^(aBlock value: thisContext) + 100
!
returnFromEnsure
	[^#returned] ensure: [log add: 0].
	^#fellThrough
!
signalDeep: n
	n = 0 ifTrue: [^ZeroDivide new signal: 'deep'].
	^(self signalDeep: n - 1) + 0
!
returnThroughEnsures: n
	n = 0 ifTrue: [[^#returned] ensure: [log add: n]].
	^[self returnThroughEnsures: n - 1] ensure: [log add: n]
!
flushes: aBlock
	"How many more frame flushes than process switches aBlock causes (a process switch flushes)."
	| before after |
	before := Smalltalk vm statistics.
	aBlock value.
	after := Smalltalk vm statistics.
	^(after frameFlushes - before frameFlushes) - (after processSwitches - before processSwitches)
! !

!LazyContextTest methodsFor: 'tests'!
testThisContextIdentity
	| a b |
	a := thisContext.
	b := thisContext.
	self assert: a == b.
	self assert: thisContext == thisContext.
	self assert: [thisContext == thisContext] value.
	self assert: ([:x | thisContext sender] value: 1) == thisContext
!
testSenderIdentity
	self assert: thisContext sender == thisContext sender.
	self assert: thisContext sender sender == thisContext sender sender.
	self assert: self answerSender == thisContext.
	self assert: [self answerSender sender] value == thisContext.
	self assert: (self deep: 5 do: [thisContext home]) == thisContext.
	self assert: (self deep: 5 do: [thisContext sender sender sender sender sender sender sender]) == thisContext
!
testMarriedReadsEqualFlushed
	| reads |
	reads := self married: 3 with: 4.
	self assert: reads first equals: reads last.
	self assert: (reads first at: 4) == (LazyContextTest >> #married:with:).
	self assert: (reads first at: 5) == self.
	self assert: (reads first at: 6) isNil.
	self assert: (reads first at: 7) equals: 3.
	self assert: (reads first at: 8) equals: 4.
	self assert: (reads first at: 9) == thisContext.
	self assert: (reads first at: 12) equals: 7.
	self deny: (reads first at: 14).
	self assert: (reads first at: 15) equals: 'LazyContextTest>>married:with:'
!
testBlockContextReads
	| reads outer |
	outer := thisContext.
	reads := [:a | | t | t := a. self readTwice: thisContext] value: 9.
	self assert: reads first equals: reads last.
	self assert: (reads first at: 1) == outer.
	self assert: (reads first at: 6) notNil.
	self assert: (reads first at: 6) outerContext == outer.
	self assert: (reads first at: 7) equals: 9
!
testTempWrites
	| x y blk |
	x := 1.
	thisContext tempAt: 1 put: 2.
	self assert: x equals: 2.
	self setSenderTemp: 2 to: 3.
	self assert: y equals: 3.
	self setSenderSlot: 1 to: 4.
	self assert: x equals: 4.
	thisContext at: 2 put: 5.
	self assert: y equals: 5.
	blk := [x].
	blk outerContext tempAt: 1 put: 6.
	self assert: blk value equals: 6.
	self flushFrames.
	self setSenderTemp: 1 to: 7.
	self assert: x equals: 7
!
testReturnedContexts
	| ctx blockCtx |
	ctx := self answerContext.
	self assert: ctx isDead.
	self assert: ctx sender isNil.
	self assert: (ctx tempAt: 1) equals: 7.
	self assert: ctx printString equals: 'LazyContextTest>>answerContext (dead)'.
	blockCtx := [:k | thisContext] value: 3.
	self assert: blockCtx isDead.
	self assert: (blockCtx tempAt: 1) equals: 3
!
testHandlerAndUnwindSearch
	| found |
	found := [[thisContext nextHandlerContext] ensure: [log add: 1]] on: ZeroDivide do: [:e | nil].
	self assert: found method == (BlockClosure >> #on:do:).
	self assert: (found tempAt: 1) == ZeroDivide.
	found := [self deep: 4 do: [thisContext findNextUnwindContextUpTo: nil]] ensure: [log add: 2].
	self assert: found method == (BlockClosure >> #ensure:).
	self assert: (found tempAt: 1) isBlock.
	found := [self deep: 4 do: [self flushFrames. thisContext findNextUnwindContextUpTo: nil]] ensure: [log add: 3].
	self assert: found method == (BlockClosure >> #ensure:).
	[| protected |
	 protected := thisContext.
	 found := self deep: 3 do: [thisContext findNextUnwindContextUpTo: protected]] ensure: [log add: 4].
	self assert: found isNil.
	self assert: ([self deep: 3 do: [thisContext nextHandlerContext]] on: Error do: [:e | nil]) method == (BlockClosure >> #on:do:).
	self assert: log asArray equals: #(1 2 3 4)
!
testTerminateTo
	| outer |
	outer := thisContext.
	self assert: (self middle: [:ctx | self terminateCallerOf: ctx]) equals: 5.
	self assert: log asArray equals: #(#middle).
	log removeAll.
	self assert: (self middle: [:ctx | self flushFrames. self terminateCallerOf: ctx]) equals: 5.
	self assert: log asArray equals: #(#middle).
	self assert: thisContext == outer.
	self deny: outer isDead
!
testTerminatedFramesAreDead
	| inner |
	self assert: (self middle: [:ctx | inner := thisContext. self deep: 3 do: [self terminateCallerOf: ctx]]) equals: 5.
	self assert: inner isDead
!
testExceptionsKeepFramesLazy
	| n |
	n := self flushes: [
		1 to: 200 do: [:i |
			self assert: ([1 / 0] on: ZeroDivide do: [:e | e return: i]) equals: i.
			self assert: ([(Warning signal: 'w') + 1] on: Warning do: [:e | e resume: i]) equals: i + 1.
			self assert: ([[Error signal: 'p'] on: Error do: [:e | e pass]] on: Error do: [:e | e return: i]) equals: i.
			self assert: ([[(Warning signal: 'o') + 100] on: Warning do: [:e | e outer + 1]] on: Warning do: [:e | e resume: i]) equals: i + 1.
			self assert: ([[Error signal] ensure: [log add: i]] on: Error do: [:e | 0]) equals: 0.
			self assert: ([[Error signal] ifCurtailed: [log add: i]] on: Error do: [:e | e return: 1]) equals: 1.
			self assert: self returnFromEnsure equals: #returned.
			self assert: (self deep: 20 do: [[self deep: 20 do: [Error signal]] on: Error do: [:e | e return: 3]]) equals: 3]].
	self assert: log size equals: 600.
	self assert: n <= 0
!
testSignalInsideUnwindBlock
	| result |
	result := [[Error signal: 'first'] ensure: [[ZeroDivide new signal: 'second'] on: ZeroDivide do: [:e | log add: e messageText]]] on: Error do: [:e | e return: e messageText].
	self assert: result equals: 'first'.
	self assert: log asArray equals: #('second').
	log removeAll.
	result := [[[Error signal: 'a'] ensure: [log add: #unwinding. Warning signal: 'b'. log add: #resumed]] on: Error do: [:e | 1]] on: Warning do: [:e | e resume].
	self assert: result equals: 1.
	self assert: log asArray equals: #(#unwinding #resumed)
!
testNonLocalReturnThroughUnwindBlocks
	self assert: (self returnThroughEnsures: 5) equals: #returned.
	self assert: log asArray equals: #(0 1 2 3 4 5).
	log removeAll.
	self assert: (self deep: 10 do: [self returnThroughEnsures: 2]) equals: #returned.
	self assert: log asArray equals: #(0 1 2)
!
testSignalerAndReceiver
	| ex |
	ex := [self signalDeep: 3] on: ZeroDivide do: [:e | {e signalerContext selector. e receiver. e signaler}].
	self assert: ex first equals: #signalDeep:.
	self assert: ex second == self.
	self assert: ex third == self.
	ex := [Error new signaler: 3; signal] on: Error do: [:e | e signaler].
	self assert: ex equals: 3
!
testUnwindingDeepStacks
	"Handlers and unwind blocks far below the frames (in Contexts after a flush) and far above them."
	| result |
	result := [self deep: 100 do: [[self deep: 100 do: [self flushFrames. Error signal: 'x']] ensure: [log add: #inner]]] on: Error do: [:e | e return: #caught].
	self assert: result equals: #caught.
	self assert: log asArray equals: #(#inner).
	log removeAll.
	result := [self deep: 100 do: [[self deep: 100 do: [Error signal: 'x']] ensure: [self flushFrames. log add: #inner]]] on: Error do: [:e | e retryUsing: [#retried]].
	self assert: result equals: #retried.
	self assert: log asArray equals: #(#inner)
!
testProcessTerminationUnwinds
	| p done |
	done := Semaphore new.
	p := self fork: [self deep: 30 do: [[self deep: 30 do: [[Processor activeProcess terminate] ensure: [log add: #inner]]] ensure: [log add: #outer. done signal]]].
	self assert: (done waitTimeoutMSecs: 5000) not.
	self assert: log asArray equals: #(#inner #outer).
	self assert: (self waitFor: [p isTerminated] timeout: 5000)
! !
