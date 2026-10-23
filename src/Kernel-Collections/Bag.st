Collection subclass: #Bag
	instanceVariableNames: 'contents'
	classVariableNames: ''
	package: 'Kernel-Collections'!

Bag comment: 'I am an unordered collection that counts occurrences: contents maps each distinct element to its count.'!

!Bag methodsFor: 'initialization'!
initialize
	contents := Dictionary new
! !

!Bag methodsFor: 'adding'!
add: anObject
	^self add: anObject withOccurrences: 1
!
add: anObject withOccurrences: n
	contents at: anObject put: (contents at: anObject ifAbsent: [0]) + n.
	^anObject
! !

!Bag methodsFor: 'removing'!
remove: oldObject ifAbsent: aBlock
	| count |
	count := contents at: oldObject ifAbsent: [^aBlock value].
	count = 1
		ifTrue: [contents removeKey: oldObject]
		ifFalse: [contents at: oldObject put: count - 1].
	^oldObject
!
removeAll
	contents := Dictionary new
! !

!Bag methodsFor: 'accessing'!
size
	^contents inject: 0 into: [:sum :count | sum + count]
!
occurrencesOf: anObject
	^contents at: anObject ifAbsent: [0]
!
asSet
	^contents keys asSet
!
sortedCounts
	"Answer an Array of count -> element Associations, most frequent first."
	^(contents associations collect: [:a | a value -> a key])
		sort: [:a :b | a key >= b key]; yourself
!
valuesAndCounts
	^contents
! !

!Bag methodsFor: 'testing'!
includes: anObject
	^contents includesKey: anObject
! !

!Bag methodsFor: 'enumerating'!
do: aBlock
	contents associationsDo: [:assoc | assoc value timesRepeat: [aBlock value: assoc key]]
! !

!Bag methodsFor: 'comparing'!
= aBag
	self == aBag ifTrue: [^true].
	^self class == aBag class and: [contents = aBag valuesAndCounts]
!
hash
	^contents hash
! !

!Bag methodsFor: 'copying'!
postCopy
	contents := contents copy
! !
