LookupKey subclass: #Association
	instanceVariableNames: 'value'
	classVariableNames: ''
	package: 'Kernel-Objects'!

Association comment: 'I am a key -> value pair. Dictionaries store me; compiled methods reference globals and class variables through me (the VM reads my value for "push literal variable"). My field order (key value) is fixed by the VM.'!

!Association methodsFor: 'accessing'!
value
	^value
!
value: anObject
	value := anObject
!
key: aKey value: anObject
	key := aKey.
	value := anObject
! !

!Association methodsFor: 'comparing'!
= anAssociation
	^super = anAssociation and: [value = anAssociation value]
!
hash
	^key hash
! !

!Association methodsFor: 'printing'!
printOn: aStream
	aStream print: key; nextPutAll: '->'; print: value
!
storeOn: aStream
	aStream nextPut: $(; store: key; nextPutAll: '->'; store: value; nextPut: $)
! !

!Association class methodsFor: 'instance creation'!
key: aKey value: anObject
	^self basicNew key: aKey value: anObject
! !
