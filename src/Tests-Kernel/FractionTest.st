TestCase subclass: #FractionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

FractionTest comment: 'Tests exact rational arithmetic and its coercion with integers and floats.'!

!FractionTest methodsFor: 'tests'!
testCreationAndNormalization
	self assert: (1 / 2) class == Fraction.
	self assert: (2 / 4) = (1 / 2).
	self assert: (2 / 4) numerator = 1.
	self assert: (2 / 4) denominator = 2.
	self assert: (4 / 2) = 2.
	self assert: (4 / 2) class == SmallInteger.
	self assert: (1 / -2) numerator = -1.
	self assert: (1 / -2) denominator = 2.
	self assert: (0 / 5) = 0
!
testArithmetic
	self assert: (1 / 2) + (1 / 3) = (5 / 6).
	self assert: (1 / 2) - (1 / 3) = (1 / 6).
	self assert: (2 / 3) * (3 / 4) = (1 / 2).
	self assert: (1 / 2) / (1 / 4) = 2.
	self assert: (1 / 2) + 1 = (3 / 2).
	self assert: 1 + (1 / 2) = (3 / 2).
	self assert: 3 - (1 / 2) = (5 / 2).
	self assert: 3 * (1 / 3) = 1.
	self assert: (1 / 3) reciprocal = 3.
	self assert: (2 / 3) reciprocal = (3 / 2).
	self assert: (-2 / 3) reciprocal = (-3 / 2).
	self assert: (1 / 2) negated = (-1 / 2).
	self assert: (-1 / 2) abs = (1 / 2).
	self assert: ((1 / 2) raisedTo: 3) = (1 / 8).
	self assert: ((2 / 3) raisedTo: -2) = (9 / 4).
	self assert: (1 / 2) squared = (1 / 4)
!
testMixedWithFloats
	self assert: (1 / 2) + 0.5 = 1.0.
	self assert: 0.5 + (1 / 2) = 1.0.
	self assert: (1 / 2) = 0.5.
	self assert: 0.5 = (1 / 2).
	self assert: (1 / 2) hash = 0.5 hash.
	self assert: (1 / 3) asFloat printString = '0.3333333333333333'.
	self assert: (1 / 3) < 0.34.
	self assert: (2 / 3) asFloat = (2 / 3) asFloat
!
testComparing
	self assert: (1 / 3) < (1 / 2).
	self assert: (1 / 2) > (1 / 3).
	self assert: (1 / 2) <= (1 / 2).
	self assert: (1 / 2) < 1.
	self assert: 1 > (1 / 2).
	self assert: ((1 / 2) max: (2 / 3)) = (2 / 3).
	self deny: (1 / 2) = 'half'.
	self assert: (1 / 2) hash = (2 / 4) hash
!
testTruncation
	self assert: (7 / 2) truncated = 3.
	self assert: (-7 / 2) truncated = -3.
	self assert: (7 / 2) floor = 3.
	self assert: (-7 / 2) floor = -4.
	self assert: (7 / 2) ceiling = 4.
	self assert: (7 / 2) rounded = 4.
	self assert: (-7 / 2) rounded = -4.
	self assert: (7 / 3) rounded = 2.
	self assert: (7 / 2) // 1 = 3.
	self assert: (7 / 2) \\ 1 = (1 / 2)
!
testPrinting
	self assert: (7 / 2) printString = '(7/2)'.
	self assert: (-7 / 2) printString = '(-7/2)'.
	self assert: (Array with: 1 / 2) printString = '#((1/2))'
!
testAverage
	self assert: #(1 2) average = (3 / 2).
	self assert: #(1 2 3) average = 2.
	self assert: (1 to: 4) average = (5 / 2)
!
testLargeFractions
	| f |
	f := (2 raisedTo: 100) / (3 raisedTo: 50).
	self assert: f class == Fraction.
	self assert: f * (3 raisedTo: 50) = (2 raisedTo: 100).
	self assert: (f asFloat - ((2 raisedTo: 100) asFloat / (3 raisedTo: 50) asFloat)) abs < 1.0e-3
! !
