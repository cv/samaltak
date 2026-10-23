TestCase subclass: #ExceptionTest
	instanceVariableNames: 'log'
	classVariableNames: ''
	package: 'Tests-Kernel'!

ExceptionTest comment: 'Tests signaling and handling (return, retry, resume, pass, outer, retryUsing:), ensure:/ifCurtailed: unwinding including non-local returns, and the exceptions the kernel signals.'!

!ExceptionTest methodsFor: 'running'!
setUp
	log := OrderedCollection new
! !

!ExceptionTest methodsFor: 'helpers'!
returnFromEnsure
	"Leave through an ensure: block with a non-local return."
	[log add: #body. ^#returned] ensure: [log add: #ensure].
	log add: #notReached.
	^#fellThrough
!
returnFromIfCurtailed
	[^#returned] ifCurtailed: [log add: #curtailed].
	^#fellThrough
!
returnFromNestedEnsures
	[[[^#returned] ensure: [log add: 1]] ensure: [log add: 2]] ensure: [log add: 3].
	^#fellThrough
!
returnFromHandlerBlock
	[Error signal: 'x'] on: Error do: [:e | ^#fromHandler].
	^#fellThrough
!
deadBlock
	^[:x | ^x]
!
signalWarningAndLog
	| value |
	value := Warning signal: 'careful'.
	log add: value.
	^value
! !

!ExceptionTest methodsFor: 'tests'!
testSignalAndReturn
	self assert: ([Error signal. 1] on: Error do: [:e | 2]) = 2.
	self assert: ([Error signal. 1] on: Error do: [:e | e return: 3]) = 3.
	self assert: ([Error signal. 1] on: Error do: [:e | e return]) isNil.
	self assert: ([1] on: Error do: [:e | 2]) = 1.
	self assert: ([Error new signal: 'msg'] on: Error do: [:e | e messageText]) = 'msg'.
	self assert: ([Error signal: 'msg'] on: Error do: [:e | e description]) = 'Error'.
	self assert: ([ZeroDivide new signal] on: Error do: [:e | e class]) == ZeroDivide
!
testNotHandledByWrongClass
	self assert: ([[Error signal. 1] on: ZeroDivide do: [:e | 2]] on: Error do: [:e | 3]) = 3
!
testExceptionSet
	self assert: ([1 / 0] on: MessageNotUnderstood, ZeroDivide do: [:e | 7]) = 7.
	self assert: ([nil foo] on: ZeroDivide, MessageNotUnderstood do: [:e | 8]) = 8
!
testResume
	self assert: ([(Warning signal: 'w') + 1] on: Warning do: [:e | e resume: 41]) = 42.
	self assert: ([(Notification signal) isNil] on: Notification do: [:e | e resume]) .
	self assert: (Notification signal) isNil.
	self should: [[Error signal] on: Error do: [:e | e resume: 1]] raise: IllegalResumeAttempt
!
testUnhandledWarningResumesNil
	| old |
	old := Transcript echo.
	Transcript echo: false.
	[self assert: self signalWarningAndLog isNil] ensure: [Transcript echo: old].
	self assert: log asArray = #(nil)
!
testRetry
	| count |
	count := 0.
	self assert: ([count := count + 1. count < 3 ifTrue: [Error signal]. count] on: Error do: [:e | e retry]) = 3.
	self assert: count = 3
!
testRetryUsing
	self assert: ([Error signal. 1] on: Error do: [:e | e retryUsing: [2]]) = 2
!
testPass
	self assert: ([[Error signal: 'inner'] on: Error do: [:e | log add: 1. e pass]] on: Error do: [:e | log add: 2. 9]) = 9.
	self assert: log asArray = #(1 2)
!
testOuter
	| result |
	result := [[(Warning signal: 'w') + 100] on: Warning do: [:e | e outer + 1]] on: Warning do: [:e | e resume: 10].
	self assert: result = 11
!
testSignalInHandler
	self assert: ([[Error signal: 'a'] on: Error do: [:e | ZeroDivide new signal]] on: ZeroDivide do: [:e | #outer]) = #outer.
	self assert: ([[Error signal: 'a'] on: Error do: [:e | Error signal: 'b']] on: Error do: [:e | e messageText]) = 'b'
!
testHandlerDisabledWhileRunning
	"An exception signaled in a handler block is not caught by the same handler."
	| count |
	count := 0.
	self assert: ([[Error signal] on: Error do: [:e | count := count + 1. Error signal. 5]] on: Error do: [:e | 6]) = 6.
	self assert: count = 1
!
testEnsure
	self assert: ([log add: 1. 10] ensure: [log add: 2]) = 10.
	self assert: log asArray = #(1 2).
	log removeAll.
	[[log add: 1. Error signal. log add: #no] ensure: [log add: 2]] on: Error do: [:e | log add: 3].
	self assert: log asArray = #(1 3 2).
	log removeAll.
	[[Error signal] ensure: [log add: 2]] on: Error do: [:e | log add: 1. e return: nil].
	self assert: log asArray = #(1 2)
!
testEnsureWithNonLocalReturn
	self assert: self returnFromEnsure = #returned.
	self assert: log asArray = #(#body #ensure).
	log removeAll.
	self assert: self returnFromNestedEnsures = #returned.
	self assert: log asArray = #(1 2 3)
!
testIfCurtailed
	self assert: ([1] ifCurtailed: [log add: #curtailed]) = 1.
	self assert: log isEmpty.
	self assert: self returnFromIfCurtailed = #returned.
	self assert: log asArray = #(#curtailed).
	log removeAll.
	[[Error signal] ifCurtailed: [log add: #curtailed]] on: Error do: [:e | nil].
	self assert: log asArray = #(#curtailed)
!
testNonLocalReturnFromHandler
	self assert: self returnFromHandlerBlock = #fromHandler
!
testRetryRunsEnsureBlocks
	| count |
	count := 0.
	[[count := count + 1. count < 3 ifTrue: [Error signal]] ensure: [log add: count]]
		on: Error do: [:e | e retry].
	self assert: log asArray = #(1 2 3)
!
testBlockCannotReturn
	| block |
	block := self deadBlock.
	self should: [block value: 1] raise: BlockCannotReturn.
	self assert: ([block value: 5] on: BlockCannotReturn do: [:e | e result]) = 5.
	self assert: ([block value: 5] on: BlockCannotReturn do: [:e | e resume: 7]) = 7
!
testSignalerContext
	| ctx |
	ctx := [self error: 'here'] on: Error do: [:e | e signalerContext].
	self assert: ctx receiver == self.
	self assert: ctx selector == #error:
!
testFreezeAndResignal
	| block ex warning |
	block := [ZeroDivide new signal: 'frozen'].
	ex := block on: ZeroDivide do: [:e | e freeze. e return: e].
	self assert: ex signalerContext closure == block.
	self assert: ([ex resignal. 1] on: ZeroDivide do: [:e | e == ex ifTrue: [e return: e signalerContext closure]]) == block.
	self assert: ([ex resignal] on: ZeroDivide do: [:e | e retryUsing: [5]]) equals: 5.
	warning := [Warning new signal: 'w'] on: Warning do: [:e | e freeze. e return: e].
	self assert: ([warning resignal] on: Warning do: [:e | e resume: 7]) equals: 7
!
testErrorClasses
	self should: [1 / 0] raise: ZeroDivide.
	self should: [nil foo] raise: MessageNotUnderstood.
	self should: [#(1 2) at: 3] raise: SubscriptOutOfBounds.
	self should: [Dictionary new at: #missing] raise: KeyNotFound.
	self should: [Set new remove: 3] raise: NotFound.
	self should: [OrderedCollection new removeFirst] raise: CollectionIsEmpty.
	self should: [self assert: false] raise: TestFailure.
	self should: [Object new assert: false] raise: AssertionFailure.
	self assert: (KeyNotFound inheritsFrom: Error).
	self assert: (ZeroDivide inheritsFrom: ArithmeticError).
	self assert: ([#(1 2) at: 3] on: SubscriptOutOfBounds do: [:e | e messageText]) = 'Index 3 out of bounds 1..2'
!
testPrinting
	self assert: (Error new messageText: 'boom'; yourself) printString = 'Error: boom'.
	self assert: Error new printString = 'Error'.
	self assert: ([nil foo] on: MessageNotUnderstood do: [:e | e messageText]) = 'Instance of UndefinedObject did not understand #foo'
!
testSignalReturnValueFromDefaultAction
	self assert: (Notification new signal: 'n') isNil
!
testEnsureRunsWhenHandlerReturnsThroughSeveralFrames
	| result |
	result := [self levelOne] on: ZeroDivide do: [:e | e return: #caught].
	self assert: result = #caught.
	self assert: log asArray = #(#three #two #one)
! !

!ExceptionTest methodsFor: 'helpers'!
levelOne
	^[self levelTwo] ensure: [log add: #one]
!
levelTwo
	^[self levelThree] ensure: [log add: #two]
!
levelThree
	^[1 / 0] ensure: [log add: #three]
! !
