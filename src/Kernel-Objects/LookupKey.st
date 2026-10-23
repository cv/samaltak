Object subclass: #LookupKey
	instanceVariableNames: 'key'
	classVariableNames: ''
	package: 'Kernel-Objects'!

LookupKey comment: 'I am an object with a key. I compare (and sort) by my key; Association adds a value.'!

!LookupKey methodsFor: 'accessing'!
key
	^key
!
key: anObject
	key := anObject
!
name
	^key
! !

!LookupKey methodsFor: 'comparing'!
< aLookupKey
	^key < aLookupKey key
!
<= aLookupKey
	^(aLookupKey key < key) not
!
> aLookupKey
	^aLookupKey key < key
!
>= aLookupKey
	^(key < aLookupKey key) not
!
= aLookupKey
	^self class == aLookupKey class and: [key = aLookupKey key]
!
hash
	^key hash
! !

!LookupKey methodsFor: 'printing'!
printOn: aStream
	aStream print: key
! !

!LookupKey class methodsFor: 'instance creation'!
key: aKey
	^self basicNew key: aKey; yourself
! !
