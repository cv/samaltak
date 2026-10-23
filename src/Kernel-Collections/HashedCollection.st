Collection subclass: #HashedCollection
	instanceVariableNames: 'tally array'
	classVariableNames: ''
	package: 'Kernel-Collections'!

HashedCollection comment: 'I am the abstract class of hash tables with open addressing: an element (or, in a Dictionary, its key) lives at (hash \\ array size) + 1 or in the next free slot after it (linear probing, wrapping around). nil marks an empty slot. The capacity is a power of two at least twice tally. This layout (exactly the fields tally and array) is shared with the bootstrapper, which builds the seed dictionaries; startup rehashes all instances.'!

!HashedCollection methodsFor: 'accessing'!
size
	^tally
!
capacity
	^array size
! !

!HashedCollection methodsFor: 'testing'!
isEmpty
	^tally = 0
! !

!HashedCollection methodsFor: 'removing'!
removeAll
	self init: 8
! !

!HashedCollection methodsFor: 'copying'!
postCopy
	array := array copy
! !

!HashedCollection methodsFor: 'private'!
init: capacity
	tally := 0.
	array := Array new: capacity
!
scanFor: anObject
	"Answer the index of the slot holding anObject (or its key), or of the empty slot where it would go."
	^self subclassResponsibility
!
keyOf: element
	"Answer what element is hashed by."
	^element
!
atNewIndex: index put: anObject
	array at: index put: anObject.
	tally := tally + 1.
	self fullCheck
!
fullCheck
	"Keep the load factor at most one half."
	tally * 2 > array size ifTrue: [self growTo: array size * 2]
!
growTo: newCapacity
	"Reinsert every element into a fresh array of newCapacity slots."
	| oldArray |
	oldArray := array.
	array := Array new: newCapacity.
	1 to: oldArray size do: [:i |
		| element |
		element := oldArray at: i.
		element isNil ifFalse: [array at: (self scanFor: (self keyOf: element)) put: element]]
!
rehash
	"Reinsert all elements, e.g. after their hashes changed."
	| capacity |
	capacity := 8.
	[capacity < (tally * 2)] whileTrue: [capacity := capacity * 2].
	self growTo: (capacity max: array size)
!
removeIndex: index
	"Empty the slot at index and move the following elements of its cluster to where probing finds them."
	| i element newIndex |
	array at: index put: nil.
	tally := tally - 1.
	i := index.
	[element := array at: (i := i \\ array size + 1).
	 element isNil] whileFalse: [
		newIndex := self scanFor: (self keyOf: element).
		newIndex = i ifFalse: [
			array at: newIndex put: element.
			array at: i put: nil]]
!
array
	^array
! !

!HashedCollection class methodsFor: 'instance creation'!
new
	^self new: 4
!
new: n
	"Answer an empty instance with room for n elements."
	| capacity |
	capacity := 8.
	[capacity < (n * 2)] whileTrue: [capacity := capacity * 2].
	^self basicNew init: capacity
!
rehashAll
	"Rehash every instance of me and my subclasses (startup: the bootstrapper's hashes may differ from ours)."
	self withAllSubclassesDo: [:class | class allInstances do: [:each | each rehash]]
! !
