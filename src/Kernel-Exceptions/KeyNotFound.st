Error subclass: #KeyNotFound
	instanceVariableNames: 'key collection'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

KeyNotFound comment: 'I am signaled when a key is missing from a Dictionary.'!

!KeyNotFound methodsFor: 'accessing'!
key
	^key
!
key: anObject
	key := anObject
!
collection
	^collection
!
collection: aCollection
	collection := aCollection
!
messageText
	^messageText ifNil: ['Key not found: ', key printString]
! !

!KeyNotFound class methodsFor: 'signaling'!
signalFor: aKey in: aCollection
	^self new key: aKey; collection: aCollection; signal
! !
