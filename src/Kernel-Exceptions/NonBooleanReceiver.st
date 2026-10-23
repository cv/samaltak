Error subclass: #NonBooleanReceiver
	instanceVariableNames: 'object'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

NonBooleanReceiver comment: 'I am signaled (via mustBeBoolean) when a conditional finds an object that is neither true nor false. Resume me with a Boolean to continue the conditional.'!

!NonBooleanReceiver methodsFor: 'accessing'!
object
	^object
!
object: anObject
	object := anObject
!
messageText
	^messageText ifNil: ['Not a Boolean: ', object printString]
! !

!NonBooleanReceiver methodsFor: 'testing'!
isResumable
	^true
! !
