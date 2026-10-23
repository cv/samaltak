Error subclass: #CollectionIsEmpty
	instanceVariableNames: 'collection'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

CollectionIsEmpty comment: 'I am signaled when an operation needs at least one element.'!

!CollectionIsEmpty methodsFor: 'accessing'!
collection
	^collection
!
collection: aCollection
	collection := aCollection
!
messageText
	^messageText ifNil: ['Collection is empty']
! !

!CollectionIsEmpty class methodsFor: 'signaling'!
signalOn: aCollection
	^self new collection: aCollection; signal
! !
