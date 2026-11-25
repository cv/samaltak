Magnitude subclass: #Number
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Number comment: 'I am the abstract class of numbers. Mixed arithmetic works by generality: when a primitive fails because the argument is of another kind, the operation is retried after converting the less general operand (SmallInteger 20 < LargeInteger 40 < Fraction 60 < Float 80). See retry:coercing:.'!

!Number methodsFor: 'arithmetic'!
+ aNumber
	^self subclassResponsibility
!
- aNumber
	^self subclassResponsibility
!
* aNumber
	^self subclassResponsibility
!
/ aNumber
	^self subclassResponsibility
!
// aNumber
	"Answer the integer quotient, truncated toward negative infinity."
	^(self / aNumber) floor
!
\\ aNumber
	"Answer the modulo, with the sign of aNumber (floored division)."
	^self - (self // aNumber * aNumber)
!
quo: aNumber
	"Answer the integer quotient, truncated toward zero."
	^(self / aNumber) truncated
!
rem: aNumber
	"Answer the remainder of truncated division, with the sign of the receiver."
	^self - ((self quo: aNumber) * aNumber)
!
abs
	^self negative ifTrue: [self negated] ifFalse: [self]
!
negated
	^0 - self
!
reciprocal
	^1 / self
!
squared
	^self * self
! !

!Number methodsFor: 'mathematical functions'!
sqrt
	^self asFloat sqrt
!
raisedTo: aNumber
	"Answer the receiver raised to aNumber."
	aNumber isInteger ifTrue: [^self raisedToInteger: aNumber].
	aNumber isFraction ifTrue: [
		(self >= 0 and: [aNumber denominator = 2]) ifTrue: [^(self raisedToInteger: aNumber numerator) sqrt]].
	self < 0 ifTrue: [^ArithmeticError new signal: 'Negative number raised to a non-integer power'].
	^(aNumber asFloat * self asFloat ln) exp
!
raisedToInteger: anInteger
	"Answer the receiver raised to anInteger by repeated squaring (exact for exact numbers)."
	| result base n |
	anInteger < 0 ifTrue: [^(self raisedToInteger: anInteger negated) reciprocal].
	result := self unity.
	base := self.
	n := anInteger.
	[n > 0] whileTrue: [
		(n bitAnd: 1) = 1 ifTrue: [result := result * base].
		n := n bitShift: -1.
		n > 0 ifTrue: [base := base * base]].
	^result
!
unity
	^1
!
** aNumber
	^self raisedTo: aNumber
!
exp
	^self asFloat exp
!
ln
	^self asFloat ln
!
log
	"Answer the base-10 logarithm."
	^self asFloat log
!
log: aNumber
	^self ln / aNumber ln
!
sin
	^self asFloat sin
!
cos
	^self asFloat cos
!
tan
	^self asFloat tan
!
arcTan
	^self asFloat arcTan
!
arcSin
	^self asFloat arcSin
!
arcCos
	^self asFloat arcCos
! !

!Number methodsFor: 'truncation and rounding'!
truncated
	^self subclassResponsibility
!
floor
	"Answer the largest integer <= the receiver."
	| t |
	t := self truncated.
	(self < 0 and: [t ~= self]) ifTrue: [^t - 1].
	^t
!
ceiling
	"Answer the smallest integer >= the receiver."
	| t |
	t := self truncated.
	(self > 0 and: [t ~= self]) ifTrue: [^t + 1].
	^t
!
rounded
	"Answer the nearest integer, halves away from zero."
	^(self + (self sign / 2)) truncated
!
roundTo: quantum
	^(self / quantum) rounded * quantum
!
truncateTo: quantum
	^(self quo: quantum) * quantum
!
fractionPart
	^self - self integerPart
!
integerPart
	^self truncated
! !

!Number methodsFor: 'testing'!
isNumber
	^true
!
isZero
	^self = 0
!
negative
	^self < 0
!
positive
	"Answer whether the receiver is >= 0."
	^self >= 0
!
strictlyPositive
	^self > 0
!
sign
	self > 0 ifTrue: [^1].
	self < 0 ifTrue: [^-1].
	^0
!
even
	^(self \\ 2) = 0
!
odd
	^self even not
!
isNaN
	^false
!
isInfinite
	^false
!
isFinite
	^true
!
isLiteral
	^true
! !

!Number methodsFor: 'converting'!
asNumber
	^self
!
asInteger
	^self truncated
!
asFloat
	^self subclassResponsibility
!
asPoint
	^Point x: self y: self
!
@ y
	"Answer the Point with the receiver as x and y as y."
	^Point x: self y: y
!
degreesToRadians
	^self asFloat * Float pi / 180.0
!
radiansToDegrees
	^self asFloat * 180.0 / Float pi
!
asString
	^self printString
! !

!Number methodsFor: 'intervals'!
to: stop
	^Interval from: self to: stop
!
to: stop by: step
	^Interval from: self to: stop by: step
!
to: stop do: aBlock
	"Evaluate aBlock for each number from the receiver to stop. Inlined by the compiler for literal blocks."
	| i |
	i := self.
	[i <= stop] whileTrue: [
		aBlock value: i.
		i := i + 1]
!
to: stop by: step do: aBlock
	| i |
	step = 0 ifTrue: [^self error: 'step must not be zero'].
	i := self.
	step > 0
		ifTrue: [[i <= stop] whileTrue: [aBlock value: i. i := i + step]]
		ifFalse: [[i >= stop] whileTrue: [aBlock value: i. i := i + step]]
!
to: stop collect: aBlock
	^(self to: stop) collect: aBlock
! !

!Number methodsFor: 'printing'!
printOn: aStream
	self printOn: aStream base: 10
!
printOn: aStream base: base
	^self subclassResponsibility
!
printString: base
	^String new: 16 streamContents: [:s | self printOn: s base: base]
!
printStringBase: base
	^self printString: base
!
displayOn: aStream
	self printOn: aStream
!
storeOn: aStream
	self printOn: aStream
!
printShowingDecimalPlaces: placesDesired
	"Answer a String with placesDesired digits after the decimal point, rounded."
	| scaled int frac s |
	placesDesired <= 0 ifTrue: [^self rounded printString].
	scaled := (self asExactNumber * (10 raisedTo: placesDesired)) rounded.
	int := scaled abs // (10 raisedTo: placesDesired).
	frac := scaled abs \\ (10 raisedTo: placesDesired).
	s := WriteStream on: (String new: 16).
	(scaled < 0) ifTrue: [s nextPut: $-].
	s print: int; nextPut: $.; nextPutAll: (frac printPaddedWith: $0 to: placesDesired).
	^s contents
!
asExactNumber
	^self
! !

!Number methodsFor: 'private'!
generality
	^self subclassResponsibility
!
coerce: aNumber
	"Answer aNumber converted to the receiver's kind."
	^self subclassResponsibility
!
retry: aSelector coercing: aNumber
	"An arithmetic primitive failed: convert the less general operand and try again."
	| myGenerality hisGenerality |
	aNumber isNumber ifFalse: [
		aSelector == #= ifTrue: [^false].
		aSelector == #~= ifTrue: [^true].
		aNumber isPoint ifTrue: [^self asPoint perform: aSelector with: aNumber].
		(aNumber respondsTo: #adaptToNumber:andSend:) ifTrue: [^aNumber adaptToNumber: self andSend: aSelector].
		aNumber isNil ifTrue: [^self error: 'Cannot ', aSelector, ' with nil'].
		^self error: 'Cannot ', aSelector, ' a ', self class name, ' with a ', aNumber class name].
	myGenerality := self generality.
	hisGenerality := aNumber generality.
	myGenerality > hisGenerality ifTrue: [^self perform: aSelector with: (self coerce: aNumber)].
	myGenerality < hisGenerality ifTrue: [^(aNumber coerce: self) perform: aSelector with: aNumber].
	^self error: 'Coercion failed for ', aSelector
! !

!Number class methodsFor: 'instance creation'!
readFrom: aStringOrStream
	"Answer the number described by aStringOrStream: [-]digits[.digits][e[-]digits], radix 16rFF or a fraction 3/4."
	^NumberParser parse: aStringOrStream
!
readFrom: aStringOrStream ifFail: aBlock
	^[self readFrom: aStringOrStream] on: Error do: [:e | e return: aBlock value]
! !
