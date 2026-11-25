Object subclass: #CalculatorEngine
	instanceVariableNames: 'value entry accumulator operator operandReady lastOperator lastOperand memory error'
	classVariableNames: ''
	package: 'Tools'!

CalculatorEngine comment: 'I am the arithmetic of the Calculator, the Windows 95 standard calculator: digit:, point, backspace, negate, operate: (#+ #- #* #/), equals (pressed again it repeats the last operation), squareRoot, reciprocal, percent (x% of the first operand), clear (C), clearEntry (CE) and memoryClear/Recall/Store/Add. Numbers are exact (Integers and Fractions; a square root goes through a Float); display formats the value to 16 significant digits with the trailing point Windows shows (''42.''), or the error (''Cannot divide by zero.'') until a digit or C.'!

!CalculatorEngine methodsFor: 'private'!
apply: aSymbol to: a and: b
	"a aSymbol b, or nil after an error."
	(aSymbol == #/ and: [b isZero]) ifTrue: [^self fail: 'Cannot divide by zero.'].
	^a perform: aSymbol with: b
!
entered
	value := self parse: entry.
	operandReady := true
!
fail: aString
	error := aString.
	^nil
!
parse: aString
	| n scale fractional |
	n := 0.
	scale := 1.
	fractional := false.
	aString do: [:c |
		c = $.
			ifTrue: [fractional := true]
			ifFalse: [c isDigit ifTrue: [
				n := n * 10 + c digitValue.
				fractional ifTrue: [scale := scale * 10]]]].
	^(aString notEmpty and: [aString first = $-])
		ifTrue: [(n / scale) negated]
		ifFalse: [n / scale]
!
recover
	"After an error a digit starts over."
	error isNil ifFalse: [self clear]
!
result: aNumber
	value := aNumber.
	entry := nil.
	operandReady := true
! !

!CalculatorEngine methodsFor: 'keys'!
backspace
	(error isNil and: [entry notNil]) ifFalse: [^self].
	entry := entry allButLast.
	(entry isEmpty or: [entry = '-']) ifTrue: [entry := '0'].
	self entered
!
clear
	"C: everything but the memory."
	value := 0.
	entry := nil.
	accumulator := nil.
	operator := nil.
	operandReady := false.
	lastOperator := nil.
	lastOperand := nil.
	error := nil
!
clearEntry
	"CE: the number being entered."
	error isNil ifFalse: [^self clear].
	value := 0.
	entry := nil.
	operandReady := true
!
digit: aCharacter
	self recover.
	entry isNil ifTrue: [entry := '0'].
	(entry count: [:c | c isDigit]) >= self maxDigits ifTrue: [^self].
	entry := entry = '0'
		ifTrue: [String with: aCharacter]
		ifFalse: [entry = '-0'
			ifTrue: ['-' , (String with: aCharacter)]
			ifFalse: [entry , (String with: aCharacter)]].
	self entered
!
equals
	"= computes the pending operation; pressed again it repeats the last one (2 + 3 = = shows 8)."
	| r |
	error isNil ifFalse: [^self].
	operator isNil
		ifTrue: [lastOperator isNil ifFalse: [r := self apply: lastOperator to: value and: lastOperand]]
		ifFalse: [
			lastOperator := operator.
			lastOperand := value.
			r := self apply: operator to: accumulator and: value.
			operator := nil].
	r isNil ifFalse: [value := r].
	entry := nil.
	operandReady := false
!
negate
	error isNil ifFalse: [^self].
	entry isNil ifTrue: [^self result: value negated].
	entry := entry first = $-
		ifTrue: [entry allButFirst]
		ifFalse: ['-' , entry].
	self entered
!
operate: aSymbol
	"A binary operator: #+ #- #* #/. A pending one is computed first (2 + 3 * shows 5)."
	| r |
	error isNil ifFalse: [^self].
	operator isNil
		ifTrue: [accumulator := value]
		ifFalse: [operandReady ifTrue: [
			r := self apply: operator to: accumulator and: value.
			r isNil ifTrue: [^self].
			value := accumulator := r]].
	operator := aSymbol.
	operandReady := false.
	entry := nil.
	lastOperator := nil
!
percent
	"x% of the first operand, as 200 + 5 % shows 10."
	error isNil ifFalse: [^self].
	self result: (operator isNil ifTrue: [0] ifFalse: [accumulator * value / 100])
!
point
	self recover.
	entry isNil ifTrue: [entry := '0'].
	(entry includes: $.) ifFalse: [entry := entry , '.'].
	self entered
!
reciprocal
	error isNil ifFalse: [^self].
	value isZero ifTrue: [^self fail: 'Cannot divide by zero.'].
	self result: 1 / value
!
squareRoot
	error isNil ifFalse: [^self].
	value negative ifTrue: [^self fail: 'Invalid input for function.'].
	self result: value asFloat sqrt asExactFraction
! !

!CalculatorEngine methodsFor: 'displaying'!
display
	"The display's text: the entry as typed, else the value, Windows 95 style with a trailing point ('42.')."
	error isNil ifFalse: [^error].
	entry isNil ifFalse: [^(entry includes: $.) ifTrue: [entry] ifFalse: [entry , '.']].
	^self format: value
!
format: aNumber
	"aNumber rounded to my significant digits (integers in full up to 32 digits); scientific (a Float's printString) when very large or small."
	| abs places digits whole fraction |
	aNumber isZero ifTrue: [^'0.'].
	abs := aNumber abs.
	(aNumber isInteger and: [abs < (10 raisedTo: 32)]) ifTrue: [^aNumber printString , '.'].
	(abs >= (10 raisedTo: self significantDigits) or: [abs < (1 / (10 raisedTo: 10))])
		ifTrue: [^aNumber asFloat printString].
	places := self significantDigits - abs truncated printString size max: 0.
	digits := (abs * (10 raisedTo: places)) rounded printString.
	digits size <= places ifTrue: [digits := (String new: places + 1 - digits size withAll: $0) , digits].
	whole := digits copyFrom: 1 to: digits size - places.
	fraction := digits copyFrom: digits size - places + 1 to: digits size.
	[fraction notEmpty and: [fraction last = $0]] whileTrue: [fraction := fraction allButLast].
	^(aNumber negative ifTrue: ['-'] ifFalse: ['']) , whole , '.' , fraction
! !

!CalculatorEngine methodsFor: 'accessing'!
error
	^error
!
hasMemory
	^memory isZero not
!
maxDigits
	^16
!
memory
	^memory
!
significantDigits
	^16
!
value
	"The number shown, exact (an Integer or a Fraction)."
	^value
! !

!CalculatorEngine methodsFor: 'initialize-release'!
initialize
	memory := 0.
	self clear
! !

!CalculatorEngine methodsFor: 'memory'!
memoryAdd
	error isNil ifFalse: [^self].
	memory := memory + value
!
memoryClear
	memory := 0
!
memoryRecall
	error isNil ifFalse: [^self].
	self result: memory
!
memoryStore
	error isNil ifFalse: [^self].
	memory := value
! !
