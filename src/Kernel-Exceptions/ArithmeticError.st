Error subclass: #ArithmeticError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

ArithmeticError comment: 'I am signaled for arithmetic that has no defined result. I am resumable: the handler may supply a value.'!

!ArithmeticError methodsFor: 'testing'!
isResumable
	^true
! !
