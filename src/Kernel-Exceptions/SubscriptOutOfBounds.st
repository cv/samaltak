Error subclass: #SubscriptOutOfBounds
	instanceVariableNames: 'subscript lowerBound upperBound collection'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

SubscriptOutOfBounds comment: 'I am signaled when an index is outside lowerBound..upperBound of collection.'!

!SubscriptOutOfBounds methodsFor: 'accessing'!
subscript
	^subscript
!
subscript: anObject
	subscript := anObject
!
lowerBound
	^lowerBound
!
lowerBound: anInteger
	lowerBound := anInteger
!
upperBound
	^upperBound
!
upperBound: anInteger
	upperBound := anInteger
!
collection
	^collection
!
collection: anObject
	collection := anObject
!
messageText
	^messageText ifNil: [
		upperBound isNil
			ifTrue: ['Index out of bounds: ', subscript printString]
			ifFalse: ['Index ', subscript printString, ' out of bounds ', lowerBound printString, '..', upperBound printString]]
! !

!SubscriptOutOfBounds class methodsFor: 'signaling'!
signalFor: index
	^self new subscript: index; signal
!
signalFor: index lowerBound: low upperBound: high in: aCollection
	^self new
		subscript: index;
		lowerBound: low;
		upperBound: high;
		collection: aCollection;
		signal
! !
