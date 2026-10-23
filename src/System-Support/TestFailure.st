Exception subclass: #TestFailure
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

TestFailure comment: 'I am signaled by a failing assertion in a TestCase.'!

!TestFailure methodsFor: 'testing'!
isResumable
	^false
! !
