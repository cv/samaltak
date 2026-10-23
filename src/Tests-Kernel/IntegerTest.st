TestCase subclass: #IntegerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

IntegerTest comment: 'Tests SmallInteger and LargeInteger arithmetic, printing, bit operations and number theory.'!

!IntegerTest methodsFor: 'tests'!
testSmallIntegerArithmetic
	self assert: 3 + 4 = 7.
	self assert: 3 - 4 = -1.
	self assert: 6 * 7 = 42.
	self assert: 12 / 4 = 3.
	self assert: (12 / 4) class == SmallInteger.
	self assert: 7 // 2 = 3.
	self assert: -7 // 2 = -4.
	self assert: 7 \\ 2 = 1.
	self assert: -7 \\ 2 = 1.
	self assert: 7 \\ -2 = -1.
	self assert: (-7 quo: 2) = -3.
	self assert: (-7 rem: 2) = -1.
	self assert: 5 negated = -5.
	self assert: -5 abs = 5.
	self assert: (3 max: 9) = 9.
	self assert: (3 between: 1 and: 3).
	self assert: 10 sqrt = 10 sqrt.
	self assert: 16 sqrt = 4.
	self assert: (2 raisedTo: 10) = 1024.
	self assert: (2 ** 3) = 8
!
testOverflowIntoLargeIntegers
	| max min |
	max := SmallInteger maxVal.
	min := SmallInteger minVal.
	self assert: max = 4611686018427387903.
	self assert: (max + 1) class == LargePositiveInteger.
	self assert: (min - 1) class == LargeNegativeInteger.
	self assert: max + 1 - 1 = max.
	self assert: (max + 1 - 1) class == SmallInteger.
	self assert: min negated class == LargePositiveInteger.
	self assert: min negated negated = min.
	self assert: (min negated negated) class == SmallInteger.
	self assert: (max * max) // max = max.
	self assert: (max + 1) printString = '4611686018427387904'.
	self assert: (min - 1) printString = '-4611686018427387905'.
	self assert: max + 1 > max.
	self assert: min - 1 < min.
	self assert: (max + 1) hash = (max + 1) hash.
	self assert: (2 raisedTo: 64) - (2 raisedTo: 64) = 0.
	self assert: ((2 raisedTo: 64) - (2 raisedTo: 64)) class == SmallInteger
!
testLargeArithmetic
	| a b |
	a := 12345678901234567890123456789.
	b := 98765432109876543210.
	self assert: (a + b) printString = '12345678999999999999999999999'.
	self assert: (a - a) = 0.
	self assert: (a * b) // b = a.
	self assert: (a * b) \\ b = 0.
	self assert: (a * b + 17) \\ b = 17.
	self assert: (a quo: b) = 124999998.
	self assert: (a rem: b) = (a - (124999998 * b)).
	self assert: (a negated // b) = -124999999.
	self assert: (a negated \\ b) = (b - (a rem: b)).
	self assert: (a gcd: a * 3) = a.
	self assert: ((2 raisedTo: 100) sqrtFloor) = (2 raisedTo: 50).
	self assert: (2 raisedTo: 100) printString = '1267650600228229401496703205376'.
	self assert: ((2 raisedTo: 100) / (2 raisedTo: 98)) = 4.
	self assert: ((2 raisedTo: 100) / 3) class == Fraction.
	self assert: (10 raisedTo: 30) / (10 raisedTo: 28) = 100
!
testDivisionIdentity
	"x = (x // y) * y + (x \\ y) and |x \\ y| < |y| for many sizes and signs."
	| random |
	random := Random seed: 42.
	1 to: 60 do: [:i |
		| x y q r |
		x := (random nextInt: 1000000000) * (10 raisedTo: (random nextInt: 40)) + (random nextInt: 1000).
		y := (random nextInt: 1000000) * (10 raisedTo: (random nextInt: 25)) + 1.
		i odd ifTrue: [x := x negated].
		i \\ 3 = 0 ifTrue: [y := y negated].
		q := x // y.
		r := x \\ y.
		self assert: q * y + r = x.
		self assert: r abs < y abs.
		self assert: (r = 0 or: [r negative = y negative]).
		self assert: (x quo: y) * y + (x rem: y) = x]
!
testFactorial
	self assert: 0 factorial = 1.
	self assert: 20 factorial = 2432902008176640000.
	self assert: 100 factorial printString = '93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000'.
	self assert: 1000 factorial printString size = 2568.
	self assert: 100 factorial / 98 factorial = 9900.
	self assert: (1000 factorial // 999 factorial) = 1000.
	"factorial multiplies by small integers (32-bit limbs); the general product agrees"
	self assert: 700 factorial = (Integer productFrom: 2 to: 700).
	self assert: (2 raisedTo: 333) * 16rFFFFFF = ((2 raisedTo: 333) * (16rFFFFFF * (2 raisedTo: 100)) bitShift: -100)
!
testPrinting
	self assert: 0 printString = '0'.
	self assert: -42 printString = '-42'.
	self assert: (255 printString: 16) = 'FF'.
	self assert: (255 radix: 16) = 'FF'.
	self assert: (255 printStringRadix: 16) = '16rFF'.
	self assert: (-255 printStringRadix: 2) = '-2r11111111'.
	self assert: (5 printPaddedWith: $0 to: 3) = '005'.
	self assert: SmallInteger minVal printString = '-4611686018427387904'.
	self assert: ((2 raisedTo: 70) printString: 16) = '400000000000000000'.
	self assert: 1234567 asStringWithCommas = '1,234,567'.
	self assert: 16rFF = 255.
	self assert: 2r1010 = 10.
	self assert: 36rZZ = 1295
!
testNumberTheory
	self assert: (12 gcd: 18) = 6.
	self assert: (12 lcm: 18) = 36.
	self assert: (-12 gcd: 18) = 6.
	self assert: 97 isPrime.
	self deny: 91 isPrime.
	self deny: 1 isPrime.
	self assert: 2 isPrime.
	self assert: 17 sqrtFloor = 4.
	self assert: 16 sqrtFloor = 4.
	self assert: 4 even.
	self assert: 5 odd.
	self assert: (SmallInteger maxVal + 1) even.
	self assert: (3 raisedTo: 200 modulo: 1000) = ((3 raisedTo: 200) \\ 1000)
!
testBitOperations
	self assert: (12 bitAnd: 10) = 8.
	self assert: (12 bitOr: 10) = 14.
	self assert: (12 bitXor: 10) = 6.
	self assert: (1 bitShift: 10) = 1024.
	self assert: (1024 bitShift: -10) = 1.
	self assert: (-1 bitShift: -5) = -1.
	self assert: (-16 bitShift: -2) = -4.
	self assert: (1 bitShift: 100) = (2 raisedTo: 100).
	self assert: ((1 bitShift: 100) bitShift: -100) = 1.
	self assert: ((2 raisedTo: 100) negated bitShift: -99) = -2.
	self assert: (((2 raisedTo: 100) + 5) bitAnd: 16rFF) = 5.
	self assert: ((2 raisedTo: 100) bitOr: 1) = ((2 raisedTo: 100) + 1).
	self assert: (-1 bitAnd: (2 raisedTo: 80)) = (2 raisedTo: 80).
	self assert: ((2 raisedTo: 80) negated bitAnd: 16rFFFF) = 0.
	self assert: (((2 raisedTo: 80) - 1) bitXor: ((2 raisedTo: 80) - 1)) = 0.
	self assert: (5 bitAt: 1) = 1.
	self assert: (5 bitAt: 2) = 0.
	self assert: 255 highBit = 8.
	self assert: (2 raisedTo: 100) highBit = 101.
	self assert: 12 lowBit = 3.
	self assert: 0 bitInvert = -1
!
testIteration
	| count sum |
	count := 0.
	5 timesRepeat: [count := count + 1].
	self assert: count = 5.
	sum := 0.
	1 to: 10 do: [:i | sum := sum + i].
	self assert: sum = 55.
	sum := 0.
	10 to: 1 by: -2 do: [:i | sum := sum + i].
	self assert: sum = 30.
	sum := 0.
	1 perform: #to:do: with: 4 with: [:i | sum := sum + i].
	self assert: sum = 10.
	count := 0.
	3 perform: #timesRepeat: with: [count := count + 1].
	self assert: count = 3.
	self assert: (1 to: 5) asArray = #(1 2 3 4 5)
!
testConversion
	self assert: 3 asFloat = 3.0.
	self assert: 3 asFloat class == SmallFloat64.
	self assert: (2 raisedTo: 70) asFloat = 1180591620717411303424.0.
	self assert: ((2 raisedTo: 70) + 1) asFloat = (2 raisedTo: 70) asFloat.
	self assert: 65 asCharacter = $A.
	self assert: '42' asNumber = 42.
	self assert: '-17' asInteger = -17.
	self assert: 'abc' asNumber isNil.
	self assert: (Integer readFrom: '123') = 123.
	self assert: (Number readFrom: '16r1F') = 31.
	self assert: (Number readFrom: '3/4') = (3 / 4).
	self assert: '123456789012345678901234567890' asNumber = 123456789012345678901234567890
!
testDivisionByZero
	self should: [1 / 0] raise: ZeroDivide.
	self should: [1 // 0] raise: ZeroDivide.
	self should: [1 \\ 0] raise: ZeroDivide.
	self should: [(2 raisedTo: 100) // 0] raise: ZeroDivide.
	self assert: ([1 / 0] on: ZeroDivide do: [:e | e return: e dividend]) = 1.
	self assert: ([1 / 0] on: ZeroDivide do: [:e | e resume: 7]) = 7
!
testComparisonWithOtherNumbers
	self assert: 1 = 1.0.
	self assert: 1 < 1.5.
	self assert: 2 > (3 / 2).
	self assert: (2 raisedTo: 70) > 1.0.
	self assert: (2 raisedTo: 70) = (2 raisedTo: 70) asFloat.
	self deny: 1 = 'one'.
	self deny: 1 = nil.
	self assert: 1 ~= 'one'
! !
