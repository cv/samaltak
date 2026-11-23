TestCase subclass: #CalculatorTest
	instanceVariableNames: 'calculator'
	classVariableNames: ''
	package: 'Tests-Tools'!

CalculatorTest comment: 'I test the Calculator''s arithmetic by pressing its keys (press:) outside a window.'!

!CalculatorTest methodsFor: 'running'!
press: aString
	"Press the keys of aString, separated by spaces; answer the display."
	(aString substrings: ' ') do: [:each | calculator press: each].
	^calculator displayText
!
setUp
	calculator := Calculator new
! !

!CalculatorTest methodsFor: 'tests'!
testEditingTheEntry
	self assert: (self press: '1 2 3 ⌫ ⌫') equals: '1'.
	self assert: (self press: 'C . 5') equals: '0.5'.
	self assert: (self press: 'C 1 . 2 5 ±') equals: '-1.25'.
	self assert: (self press: 'C 1 + 2 CE 5 =') equals: '6'
!
testEqualsRepeats
	self assert: (self press: '2 + 3 = = =') equals: '11'.
	self assert: (self press: 'C 5 + =') equals: '10'.
	self assert: (self press: 'C 2 + 3 = 7 =') equals: '10'
!
testErrorsClearOnTheNextDigit
	self assert: (self press: '1 ÷ 0 =') equals: 'Cannot divide by zero'.
	self assert: (self press: '+') equals: 'Cannot divide by zero'.
	self assert: (self press: '5') equals: '5'.
	self assert: (self press: 'C 1 ± √') equals: 'Invalid input'.
	self assert: (self press: 'C 0 1/x') equals: 'Cannot divide by zero'
!
testExactArithmetic
	self assert: (self press: '0 . 1 + 0 . 2 =') equals: '0.3'.
	self assert: (self press: 'C 1 ÷ 3 × 3 =') equals: '1'.
	self assert: (self press: 'C 2 ÷ 3 =') equals: '0.6666666666666667'.
	self assert: (self press: 'C 2 √') equals: '1.414213562373095'.
	self assert: (self press: 'C 1 6 √') equals: '4'
!
testOperatorsApplyLeftToRight
	self assert: (self press: '1 2 + 3 × 2 =') equals: '30'.
	self assert: (self press: 'C 9 + √ +') equals: '12'.
	self assert: (self press: 'C 2 − 5 =') equals: '-3'
!
testPercent
	self assert: (self press: '2 0 0 + 1 0 %') equals: '20'.
	self assert: (self press: 'C 2 0 0 × 1 0 %') equals: '0.1'
!
testSixteenDigits
	self assert: (self press: '1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7') equals: '1234567890123456'.
	self assert: (calculator format: 1 / 7) equals: '0.1428571428571429'.
	self assert: (calculator format: (10 raisedTo: 20)) equals: '1.0e20'
! !
