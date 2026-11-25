TestCase subclass: #ComplexTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ComplexTest comment: 'Tests complex arithmetic.'!

!ComplexTest methodsFor: 'tests'!
testSquared
	"squared agrees with z * z and keeps exact components exact."
	| z |
	self assert: (Complex real: 3 imaginary: 4) squared equals: (Complex real: -7 imaginary: 24).
	self assert: (Complex real: 3 imaginary: 4) squared imaginary isInteger.
	z := Complex real: 1 / 2 imaginary: 1 / 3.
	self assert: z squared equals: z * z.
	z := Complex real: 1.5 imaginary: -0.75.
	self assert: z squared equals: z * z
! !
