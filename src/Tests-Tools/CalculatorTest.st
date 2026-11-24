TestCase subclass: #CalculatorTest
	instanceVariableNames: 'engine'
	classVariableNames: ''
	package: 'Tests-Tools'!

CalculatorTest comment: 'I test the CalculatorEngine''s arithmetic and display, and that the Calculator''s keys and typing drive its display.'!

!CalculatorTest methodsFor: 'private'!
press: aString
	"Keys as typed: digits, the point and the operators."
	aString do: [:c |
		c isDigit ifTrue: [engine digit: c] ifFalse: [
		c = $. ifTrue: [engine point] ifFalse: [
		c = $= ifTrue: [engine equals] ifFalse: [engine operate: (Symbol with: c)]]]].
	^engine display
! !

!CalculatorTest methodsFor: 'running'!
setUp
	engine := CalculatorEngine new
! !

!CalculatorTest methodsFor: 'tests'!
testArithmeticIsExact
	self assert: (self press: '0.1+0.2=') equals: '0.3'.
	engine clear.
	self assert: (self press: '1/3=') equals: '0.333333333333333'.
	engine clear.
	self assert: (self press: '99999999*99999999=') equals: '9999999800000001.'
!
testBackspaceAndClearEntry
	self press: '123'.
	engine backspace.
	self assert: engine display equals: '12.'.
	self press: '+5'.
	engine clearEntry.
	self assert: (self press: '1=') equals: '13.'
!
testDivisionByZeroIsAnErrorUntilCleared
	self assert: (self press: '1/0=') equals: 'Cannot divide by zero.'.
	self assert: (self press: '+') equals: 'Cannot divide by zero.'.
	self assert: (self press: '7') equals: '7.'
!
testEntryShowsATrailingPoint
	self assert: engine display equals: '0.'.
	self assert: (self press: '42') equals: '42.'.
	self assert: (self press: '.5') equals: '42.5'
!
testEqualsRepeatsTheLastOperation
	self assert: (self press: '2+3==') equals: '8.'.
	engine clear.
	self assert: (self press: '5+=') equals: '10.'
!
testKeysAndTypingDriveTheDisplay
	| calculator |
	calculator := Calculator new.
	(calculator widgetNamed: '7') click.
	(calculator widgetNamed: '*') click.
	calculator typeAll: '6='.
	self assert: calculator displayText equals: '42.'.
	(calculator widgetNamed: 'MS') click.
	self assert: (calculator widgetNamed: 'memory') text equals: 'M'
!
testMemory
	self press: '6'.
	engine memoryStore.
	self assert: engine hasMemory.
	self press: '+4='.
	engine memoryAdd.
	engine clear.
	engine memoryRecall.
	self assert: engine display equals: '16.'.
	engine memoryClear.
	self deny: engine hasMemory
!
testOperatorsChainLeftToRight
	self assert: (self press: '2+3*') equals: '5.'.
	self assert: (self press: '4=') equals: '20.'
!
testUnaryKeys
	self press: '9'.
	engine squareRoot.
	self assert: engine display equals: '3.'.
	engine reciprocal.
	self assert: engine display equals: '0.333333333333333'.
	engine clear.
	self press: '200+5'.
	engine percent.
	self assert: (self press: '=') equals: '210.'.
	engine clear.
	self press: '4'.
	engine negate; squareRoot.
	self assert: engine error equals: 'Invalid input for function.'
! !
