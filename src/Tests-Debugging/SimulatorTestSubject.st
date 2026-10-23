Object subclass: #SimulatorTestSubject
	instanceVariableNames: 'log value'
	classVariableNames: ''
	package: 'Tests-Debugging'!

SimulatorTestSubject comment: 'My example methods are run by the VM and by the Simulator; SimulatorTest compares their results and my log of side effects.'!

!SimulatorTestSubject methodsFor: 'accessing'!
log
	^log ifNil: [log := OrderedCollection new]
!
value
	^value
!
setValue: anObject
	value := anObject
! !

!SimulatorTestSubject methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPutAll: '!!'
! !

!SimulatorTestSubject methodsFor: 'helpers'!
makeReturner
	^[:x | ^x]
!
fib: n
	n < 2 ifTrue: [^n].
	^(self fib: n - 1) + (self fib: n - 2)
! !

!SimulatorTestSubject methodsFor: 'examples'!
exampleNonLocalReturnThroughEnsure
	#(1 2 3) do: [:e | [e = 2 ifTrue: [^e * 10]] ensure: [self log add: e]].
	^0
!
exampleEnsureOrder
	[[self log add: 1] ensure: [self log add: 2]] ensure: [self log add: 3].
	^self log size
!
exampleIfCurtailed
	^[^5] ifCurtailed: [self log add: #curtailed]
!
exampleResume
	^[(Warning signal: 'w') + 1] on: Warning do: [:e | e resume: 41]
!
exampleRetry
	| n |
	n := 0.
	^[n := n + 1. n < 3 ifTrue: [Error signal: 'again']. n] on: Error do: [:e | e retry]
!
examplePass
	^[[Error signal: 'x'] on: ZeroDivide do: [:e | 0]] on: Error do: [:e | e messageText]
!
exampleSignalInEnsure
	^[[Error signal: 'boom'] ensure: [self log add: #ensured]] on: Error do: [:e | e return: e messageText]
!
exampleOuter
	^[[Warning signal: 'w'] on: Warning do: [:e | self log add: (e outer); add: #afterOuter. 7]]
		on: Warning do: [:e | e resume: 3]
!
exampleDnuHandled
	^[3 zork: 4] on: MessageNotUnderstood do: [:e | e message arguments first + e receiver]
!
exampleDnuResumed
	^[3 zork + 1] on: MessageNotUnderstood do: [:e | e resume: 10]
!
exampleMustBeBoolean
	| x |
	x := nil.
	^[x ifTrue: [1] ifFalse: [2]] on: NonBooleanReceiver do: [:e | e resume: true]
!
exampleAttemptToAssign
	| other |
	other := SimulatorTestSubject new.
	other beReadOnlyObject.
	^[other setValue: 5. other value] on: ModificationForbidden do: [:e |
		self log add: e fieldIndex.
		e object beWritableObject.
		e retryModification]
!
examplePerform
	^Array
		with: (3 perform: #+ with: 4)
		with: (5 perform: #max: withArguments: #(9))
		with: ([:a :b | a - b] valueWithArguments: #(10 3))
		with: (3 perform: #factorial)
!
exampleCannotReturn
	| blk |
	blk := self makeReturner.
	^[blk value: 5] on: BlockCannotReturn do: [:e | e return: #cannot]
!
exampleRecursion
	^self fib: 15
!
exampleDictionary
	| d |
	d := Dictionary new.
	1 to: 20 do: [:i | d at: i printString put: i * i].
	^d values inject: 0 into: [:a :b | a + b]
!
exampleStream
	^String new: 10 streamContents: [:s | #(1 2 3) do: [:e | s print: e] separatedBy: [s nextPutAll: ', ']]
!
exampleLargeIntegers
	^(100 factorial / 98 factorial) printString, ' ', (2 raisedTo: 100) printString
!
exampleFloats
	^(0.1 + 0.2) printString, ' ', (2 sqrt * 2 sqrt) printString
!
exampleOuterTemps
	| a |
	a := 0.
	#(1 2) do: [:x | #(10 20) do: [:y | a := a + (x * y)]].
	^a
!
exampleSuper
	^self printString
!
exampleThisContext
	^thisContext selector
!
exampleNestedNonLocalReturn
	#(1 2 3) do: [:x | #(4 5) do: [:y | x * y = 10 ifTrue: [^x @ y]]].
	^nil
!
exampleSort
	^(#(5 3 9 1) asSortedCollection: [:a :b | a > b]) asArray
!
exampleLoops
	| s |
	s := 0.
	1 to: 10 by: 2 do: [:i | s := s + i].
	3 timesRepeat: [s := s * 2].
	[s > 1000] whileFalse: [s := s + 100].
	^s
!
exampleSemaphore
	| s |
	s := Semaphore new.
	s signal.
	s wait.
	^#ok
!
exampleIvarStore
	self setValue: 3.
	value := value + 4.
	^value
!
exampleCascadeAndBraces
	^{OrderedCollection new add: 1; add: 2; yourself. #(#a $b 'c' 1.5). 3 @ 4}
! !

!SimulatorTestSubject class methodsFor: 'accessing'!
exampleSelectors
	^(self selectors select: [:s | s beginsWith: 'example']) asSortedCollection asArray
! !
