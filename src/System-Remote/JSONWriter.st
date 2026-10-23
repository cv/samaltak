Object subclass: #JSONWriter
	instanceVariableNames: 'stream'
	classVariableNames: ''
	package: 'System-Remote'!

JSONWriter comment: 'I write objects as compact JSON onto a character stream (see JSON for the mapping).'!

!JSONWriter methodsFor: 'initialization'!
setStream: aStream
	stream := aStream
! !

!JSONWriter methodsFor: 'writing'!
write: anObject
	anObject isNil ifTrue: [^stream nextPutAll: 'null'].
	anObject == true ifTrue: [^stream nextPutAll: 'true'].
	anObject == false ifTrue: [^stream nextPutAll: 'false'].
	anObject isString ifTrue: [^self writeString: anObject].
	anObject isCharacter ifTrue: [^self writeString: anObject asString].
	anObject isNumber ifTrue: [^self writeNumber: anObject].
	anObject isDictionary ifTrue: [^self writeDictionary: anObject].
	anObject isSequenceable ifTrue: [^self writeArray: anObject].
	^self writeString: anObject printString
!
writeNumber: aNumber
	aNumber isInteger ifTrue: [^stream nextPutAll: aNumber printString].
	aNumber isFloat ifFalse: [^self writeNumber: aNumber asFloat].
	(aNumber isNaN or: [aNumber isInfinite]) ifTrue: [^stream nextPutAll: 'null'].
	stream nextPutAll: aNumber printString
!
writeDictionary: aDictionary
	| keys |
	keys := (aDictionary keys collect: [:k | k]) asSortedCollection: [:a :b | a asString <= b asString].
	stream nextPut: ${.
	keys do: [:key |
			self writeString: key asString.
			stream nextPut: $:.
			self write: (aDictionary at: key)]
		separatedBy: [stream nextPut: $,].
	stream nextPut: $}
!
writeArray: aCollection
	stream nextPut: $[.
	aCollection do: [:each | self write: each] separatedBy: [stream nextPut: $,].
	stream nextPut: $]
!
writeString: aString
	stream nextPut: $".
	aString do: [:c | self writeCharacter: c].
	stream nextPut: $"
!
writeCharacter: aCharacter
	| v |
	v := aCharacter value.
	v = 34 ifTrue: [^stream nextPutAll: '\"'].
	v = 92 ifTrue: [^stream nextPutAll: '\\'].
	v >= 32 ifTrue: [^stream nextPut: aCharacter].
	v = 10 ifTrue: [^stream nextPutAll: '\n'].
	v = 13 ifTrue: [^stream nextPutAll: '\r'].
	v = 9 ifTrue: [^stream nextPutAll: '\t'].
	v = 8 ifTrue: [^stream nextPutAll: '\b'].
	v = 12 ifTrue: [^stream nextPutAll: '\f'].
	stream nextPutAll: '\u'; nextPutAll: ((v printString: 16) asLowercase padLeftTo: 4 with: $0)
! !

!JSONWriter class methodsFor: 'instance creation'!
on: aStream
	^self new setStream: aStream
! !
