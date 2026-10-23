OrderedCollection subclass: #SortedCollection
	instanceVariableNames: 'sortBlock'
	classVariableNames: ''
	package: 'Kernel-Collections'!

SortedCollection comment: 'I am an OrderedCollection that keeps its elements sorted by sortBlock (a two-argument block answering whether its first argument goes before the second; default a <= b). add: inserts with a binary search; equal elements keep their insertion order.'!

!SortedCollection methodsFor: 'accessing'!
sortBlock
	^sortBlock
!
sortBlock: aBlock
	sortBlock := aBlock.
	self reSort
!
setSortBlock: aBlock
	sortBlock := aBlock
!
median
	^self at: self size + 1 // 2
!
at: index put: anObject
	^self shouldNotImplement
! !

!SortedCollection methodsFor: 'adding'!
add: anObject
	"Insert anObject after all elements that go before or equal it."
	| low high mid |
	low := firstIndex.
	high := lastIndex.
	[low <= high] whileTrue: [
		mid := low + high // 2.
		(sortBlock value: (array at: mid) value: anObject)
			ifTrue: [low := mid + 1]
			ifFalse: [high := mid - 1]].
	^self add: anObject beforeIndex: low - firstIndex + 1
!
addAll: aCollection
	aCollection size > (self size // 3)
		ifTrue: [
			aCollection do: [:each | self addLast: each].
			self reSort]
		ifFalse: [aCollection do: [:each | self add: each]].
	^aCollection
!
addFirst: anObject
	^self shouldNotImplement
!
addAllFirst: aCollection
	^self shouldNotImplement
! !

!SortedCollection methodsFor: 'enumerating'!
collect: aBlock
	"Answer an OrderedCollection: the results need not be sortable."
	| result |
	result := OrderedCollection new: self size.
	self do: [:each | result addLast: (aBlock value: each)].
	^result
! !

!SortedCollection methodsFor: 'copying'!
copyEmpty
	^(self species new: self size) setSortBlock: sortBlock; yourself
!
copyFrom: start to: stop
	| result |
	result := self copyEmpty.
	start to: stop do: [:i | result addLast: (self at: i)].
	^result
!
reversed
	| result |
	result := OrderedCollection new: self size.
	self reverseDo: [:each | result addLast: each].
	^result
!
, aCollection
	^self copy addAll: aCollection; yourself
!
copyWith: anObject
	^self copy add: anObject; yourself
! !

!SortedCollection methodsFor: 'converting'!
asSortedCollection: aBlock
	^aBlock = sortBlock
		ifTrue: [self copy]
		ifFalse: [super asSortedCollection: aBlock]
! !

!SortedCollection methodsFor: 'private'!
reSort
	| elements |
	elements := self asArray.
	elements sort: sortBlock.
	firstIndex to: lastIndex do: [:i | array at: i put: (elements at: i - firstIndex + 1)]
! !

!SortedCollection class methodsFor: 'instance creation'!
new
	^self sortBlock: [:a :b | a <= b]
!
new: anInteger
	^(super new: anInteger) setSortBlock: [:a :b | a <= b]; yourself
!
sortBlock: aBlock
	^(super new: 10) setSortBlock: aBlock; yourself
! !
