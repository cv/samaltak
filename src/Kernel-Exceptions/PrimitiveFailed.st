Error subclass: #PrimitiveFailed
	instanceVariableNames: 'selector'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

PrimitiveFailed comment: 'I am signaled when a primitive fails and its method has no fallback code.'!

!PrimitiveFailed methodsFor: 'accessing'!
selector
	^selector
!
selector: aSymbol
	selector := aSymbol
!
messageText
	^messageText ifNil: ['Primitive failed: ', selector printString]
! !
