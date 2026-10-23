TestCase subclass: #FloatTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

FloatTest comment: 'Tests Float arithmetic, printing, rounding, special values and conversions.'!

!FloatTest methodsFor: 'tests'!
testPrinting
	self assert: 0.1 printString = '0.1'.
	self assert: 1.0 printString = '1.0'.
	self assert: -2.5 printString = '-2.5'.
	self assert: 100.0 printString = '100.0'.
	self assert: 1.0e100 printString = '1.0e100'.
	self assert: 1.5e-10 printString = '1.5e-10'.
	self assert: (1 / 3) asFloat printString = '0.3333333333333333'.
	self assert: (0.1 + 0.2) printString = '0.30000000000000004'.
	self assert: 2 sqrt printString = '1.4142135623730951'.
	self assert: Float pi printString = '3.141592653589793'.
	self assert: Float nan printString = 'Float nan'.
	self assert: Float infinity printString = 'Float infinity'.
	self assert: Float negativeInfinity printString = 'Float negativeInfinity'.
	self assert: (3.14159 printShowingDecimalPlaces: 2) = '3.14'.
	self assert: (2.5 printShowingDecimalPlaces: 0) = '3'
!
testArithmetic
	self assert: 1.5 + 1.5 = 3.0.
	self assert: 1.5 + 1 = 2.5.
	self assert: 1 + 1.5 = 2.5.
	self assert: 3.0 * 2 = 6.0.
	self assert: 1.0 / 4 = 0.25.
	self assert: 1 / 4.0 = 0.25.
	self assert: 7.5 // 2 = 3.
	self assert: 7.5 \\ 2 = 1.5.
	self assert: -7.5 // 2 = -4.
	self assert: 2.0 negated = -2.0.
	self assert: -2.0 abs = 2.0.
	self deny: 0.1 + 0.2 = 0.3.
	self assert: ((0.1 + 0.2) - 0.3) abs < 1.0e-15.
	self assert: (2 raisedTo: 0.5) closeTo: 2 sqrt.
	self assert: (2.0 raisedTo: 3) = 8.0
!
testRounding
	self assert: 3.7 truncated = 3.
	self assert: -3.7 truncated = -3.
	self assert: 3.5 rounded = 4.
	self assert: -3.5 rounded = -4.
	self assert: 3.2 rounded = 3.
	self assert: 3.2 floor = 3.
	self assert: -3.2 floor = -4.
	self assert: 3.2 ceiling = 4.
	self assert: -3.2 ceiling = -3.
	self assert: 3.0 floor = 3.
	self assert: 0.49999999999999994 rounded = 0.
	self assert: 1.0e20 truncated = 100000000000000000000.
	self assert: 1.0e20 truncated class == LargePositiveInteger.
	self assert: -1.0e20 truncated = -100000000000000000000.
	self assert: 3.75 fractionPart = 0.75.
	self assert: (3.14159 roundTo: 0.01) closeTo: 3.14
!
testSpecialValues
	| nan inf |
	nan := Float nan.
	inf := Float infinity.
	self assert: nan isNaN.
	self deny: nan = nan.
	self assert: inf isInfinite.
	self assert: inf > 1.0e308.
	self assert: inf negated = Float negativeInfinity.
	self assert: (inf - inf) isNaN.
	self deny: 1.0 isNaN.
	self assert: 1.0 isFinite.
	self deny: inf isFinite.
	self should: [1.0 / 0] raise: ZeroDivide.
	self should: [1.0 / 0.0] raise: ZeroDivide.
	self should: [inf truncated] raise: ArithmeticError.
	self assert: (1.0e308 * 10) = inf.
	self assert: inf class == BoxedFloat64.
	self assert: 1.0 class == SmallFloat64
!
testFunctions
	self assert: 4.0 sqrt = 2.0.
	self assert: 0.0 sin = 0.0.
	self assert: 0.0 cos = 1.0.
	self assert: 1.0 exp closeTo: Float e.
	self assert: Float e ln closeTo: 1.0.
	self assert: 100 log closeTo: 2.0.
	self assert: (8 log: 2) closeTo: 3.0.
	self assert: 1.0 arcTan * 4 closeTo: Float pi.
	self assert: (Float pi / 2) sin closeTo: 1.0.
	self assert: (Float pi / 4) tan closeTo: 1.0.
	self assert: 0.5 arcSin closeTo: Float pi / 6.
	self assert: 0.5 arcCos closeTo: Float pi / 3.
	self assert: -1.0 sqrt isNaN
!
testConversions
	self assert: 0.5 asExactFraction = (1 / 2).
	self assert: 0.75 asExactFraction = (3 / 4).
	self assert: 3.0 asExactFraction = 3.
	self assert: 0.1 asExactFraction = (3602879701896397 / 36028797018963968).
	self assert: 1.0 hash = 1 hash.
	self assert: 2.5 hash = (5 / 2) hash.
	self assert: (Float readFrom: '3.25') = 3.25.
	self assert: '1e10' asNumber = 1.0e10.
	self assert: '-0.5' asNumber = -0.5.
	self assert: '0.1' asNumber = 0.1.
	self assert: '2.5e-3' asNumber = 0.0025.
	self assert: '123.456' asNumber = 123.456.
	self assert: 1.0e300 class == BoxedFloat64.
	self assert: (1.0e300 * 1.0e-300) closeTo: 1.0.
	self assert: 3 asFloat = 3.0.
	self assert: (2 raisedTo: 80) asFloat asExactFraction = (2 raisedTo: 80).
	self assert: 1.0e20 = 100000000000000000000.
	self assert: 100000000000000000000 = 1.0e20
!
testComparing
	self assert: 1.5 < 2.
	self assert: 2 > 1.5.
	self assert: 1.5 < ((3 / 2) + 0.1).
	self assert: (1.5 max: 2) = 2.
	self assert: 1.0 = 1.
	self deny: 1.0 = 'one'.
	self assert: (1.5 between: 1 and: 2)
! !
