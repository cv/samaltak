Error subclass: #MessageNotUnderstood
	instanceVariableNames: 'message receiver reachedDefaultHandler'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

MessageNotUnderstood comment: 'I am signaled by doesNotUnderstand: when receiver has no method for message. I am resumable: the resumption value becomes the result of the failed send.'!

!MessageNotUnderstood methodsFor: 'accessing'!
message
	^message
!
message: aMessage
	message := aMessage
!
receiver
	^receiver
!
receiver: anObject
	receiver := anObject
!
reachedDefaultHandler
	^reachedDefaultHandler == true
!
messageText
	^messageText ifNil: [
		'Instance of ', receiver class name, ' did not understand #', (message ifNil: ['?'] ifNotNil: [:m | m selector])]
! !

!MessageNotUnderstood methodsFor: 'testing'!
isResumable
	^true
! !

!MessageNotUnderstood methodsFor: 'exception description'!
defaultAction
	reachedDefaultHandler := true.
	^super defaultAction
! !
