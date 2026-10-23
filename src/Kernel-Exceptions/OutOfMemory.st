Error subclass: #OutOfMemory
	instanceVariableNames: 'requestedClass requestedSize'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

OutOfMemory comment: 'I am signaled when an allocation can never fit in the heap, even after a full garbage collection: requestedSize indexable fields of requestedClass.'!

!OutOfMemory methodsFor: 'accessing'!
requestedClass
	^requestedClass
!
requestedClass: aClass
	requestedClass := aClass
!
requestedSize
	^requestedSize
!
requestedSize: anInteger
	requestedSize := anInteger
!
messageText
	^messageText ifNil: ['Out of memory: ', requestedClass printString, ' with ', requestedSize printString, ' indexable fields']
! !

!OutOfMemory class methodsFor: 'signaling'!
signalForClass: aClass size: anInteger
	^self new requestedClass: aClass; requestedSize: anInteger; signal
! !
