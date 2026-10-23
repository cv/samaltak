Error subclass: #SubclassResponsibility
	instanceVariableNames: 'selector'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

SubclassResponsibility comment: 'I am signaled by subclassResponsibility: an abstract method was not overridden.'!

!SubclassResponsibility methodsFor: 'accessing'!
selector
	^selector
!
selector: aSymbol
	selector := aSymbol
! !
