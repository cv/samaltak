Error subclass: #NotFound
	instanceVariableNames: 'object'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

NotFound comment: 'I am signaled when an element searched for is not in a collection.'!

!NotFound methodsFor: 'accessing'!
object
	^object
!
object: anObject
	object := anObject
!
messageText
	^messageText ifNil: ['Not found: ', object printString]
! !

!NotFound class methodsFor: 'signaling'!
signalFor: anObject
	^self new object: anObject; signal
! !
