Error subclass: #NotYetImplemented
	instanceVariableNames: 'selector'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

NotYetImplemented comment: 'I am signaled by shouldBeImplemented: a method that still has to be written.'!

!NotYetImplemented methodsFor: 'accessing'!
selector
	^selector
!
selector: aSymbol
	selector := aSymbol
!
messageText
	^messageText ifNil: ['Not yet implemented: ', selector printString]
! !
