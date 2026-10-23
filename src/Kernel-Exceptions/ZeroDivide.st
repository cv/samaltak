ArithmeticError subclass: #ZeroDivide
	instanceVariableNames: 'dividend'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

ZeroDivide comment: 'I am signaled by a division by zero; dividend is the number that was divided.'!

!ZeroDivide methodsFor: 'accessing'!
dividend
	^dividend
!
dividend: aNumber
	dividend := aNumber
!
description
	^'Division by zero'
! !
