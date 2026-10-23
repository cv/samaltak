Object subclass: #Collection
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Collection comment: 'I am the abstract class of groups of objects. Subclasses define do: (and add:/remove:ifAbsent: if they can grow and shrink); everything else here (enumeration, testing, conversion, aggregation, printing) is written in terms of those.'!

!Collection methodsFor: 'adding'!
add: anObject
	"Include anObject and answer it."
	^self subclassResponsibility
!
addAll: aCollection
	"Include every element of aCollection. Answer aCollection."
	aCollection do: [:each | self add: each].
	^aCollection
!
add: anObject withOccurrences: n
	n timesRepeat: [self add: anObject].
	^anObject
! !

!Collection methodsFor: 'removing'!
remove: oldObject ifAbsent: aBlock
	^self subclassResponsibility
!
remove: oldObject
	"Remove oldObject; signal NotFound if it is absent."
	^self remove: oldObject ifAbsent: [self errorNotFound: oldObject]
!
removeAll: aCollection
	"Remove each element of aCollection. Answer aCollection."
	(aCollection == self ifTrue: [aCollection copy] ifFalse: [aCollection])
		do: [:each | self remove: each].
	^aCollection
!
removeAllSuchThat: aBlock
	"Remove the elements for which aBlock answers true."
	(self select: aBlock) do: [:each | self remove: each]
!
removeAll
	self copy do: [:each | self remove: each]
! !

!Collection methodsFor: 'enumerating'!
do: aBlock
	"Evaluate aBlock with each element."
	^self subclassResponsibility
!
do: aBlock separatedBy: separatorBlock
	"Evaluate aBlock with each element and separatorBlock between two elements."
	| first |
	first := true.
	self do: [:each |
		first ifTrue: [first := false] ifFalse: [separatorBlock value].
		aBlock value: each]
!
collect: aBlock
	"Answer a collection like the receiver of the results of aBlock on each element."
	| result |
	result := self species new.
	self do: [:each | result add: (aBlock value: each)].
	^result
!
select: aBlock
	"Answer a collection like the receiver of the elements for which aBlock answers true."
	| result |
	result := self species new.
	self do: [:each | (aBlock value: each) ifTrue: [result add: each]].
	^result
!
reject: aBlock
	^self select: [:each | (aBlock value: each) == false]
!
collect: collectBlock thenSelect: selectBlock
	^(self collect: collectBlock) select: selectBlock
!
select: selectBlock thenCollect: collectBlock
	^(self select: selectBlock) collect: collectBlock
!
detect: aBlock
	"Answer the first element for which aBlock answers true; signal NotFound if there is none."
	^self detect: aBlock ifNone: [self errorNotFound: aBlock]
!
detect: aBlock ifNone: exceptionBlock
	self do: [:each | (aBlock value: each) ifTrue: [^each]].
	^exceptionBlock value
!
detect: aBlock ifFound: foundBlock ifNone: exceptionBlock
	self do: [:each | (aBlock value: each) ifTrue: [^foundBlock value: each]].
	^exceptionBlock value
!
inject: thisValue into: binaryBlock
	"Accumulate: evaluate binaryBlock with the running value and each element."
	| nextValue |
	nextValue := thisValue.
	self do: [:each | nextValue := binaryBlock value: nextValue value: each].
	^nextValue
!
allSatisfy: aBlock
	self do: [:each | (aBlock value: each) ifFalse: [^false]].
	^true
!
anySatisfy: aBlock
	self do: [:each | (aBlock value: each) ifTrue: [^true]].
	^false
!
noneSatisfy: aBlock
	self do: [:each | (aBlock value: each) ifTrue: [^false]].
	^true
!
allOccurrencesOf: anObject
	^self select: [:each | each = anObject]
!
count: aBlock
	"Answer how many elements satisfy aBlock."
	| n |
	n := 0.
	self do: [:each | (aBlock value: each) ifTrue: [n := n + 1]].
	^n
!
detectMax: aBlock
	"Answer the element for which aBlock answers the largest value."
	| best bestValue |
	self do: [:each |
		| v |
		v := aBlock value: each.
		(bestValue isNil or: [v > bestValue]) ifTrue: [best := each. bestValue := v]].
	^best
!
detectMin: aBlock
	| best bestValue |
	self do: [:each |
		| v |
		v := aBlock value: each.
		(bestValue isNil or: [v < bestValue]) ifTrue: [best := each. bestValue := v]].
	^best
!
flatCollect: aBlock
	"Answer an OrderedCollection of the elements of the collections aBlock answers."
	| result |
	result := OrderedCollection new.
	self do: [:each | result addAll: (aBlock value: each)].
	^result
!
gather: aBlock
	^self flatCollect: aBlock
!
groupedBy: aBlock
	"Answer a Dictionary from each key aBlock answers to an OrderedCollection of the elements with that key."
	| groups |
	groups := Dictionary new.
	self do: [:each | (groups at: (aBlock value: each) ifAbsentPut: [OrderedCollection new]) add: each].
	^groups
!
do: aBlock without: anObject
	self do: [:each | anObject = each ifFalse: [aBlock value: each]]
!
anyOne
	"Answer some element; signal CollectionIsEmpty if there is none."
	self do: [:each | ^each].
	^self errorEmptyCollection
! !

!Collection methodsFor: 'testing'!
isCollection
	^true
!
isEmpty
	^self size = 0
!
notEmpty
	^self isEmpty not
!
isNotEmpty
	^self isEmpty not
!
isEmptyOrNil
	^self isEmpty
!
ifEmpty: aBlock
	"Answer aBlock value if I am empty, else myself."
	self isEmpty ifTrue: [^aBlock value].
	^self
!
ifNotEmpty: aBlock
	"Answer aBlock value (with me as optional argument) unless I am empty; else myself."
	self isEmpty ifFalse: [^aBlock cull: self].
	^self
!
ifEmpty: emptyBlock ifNotEmpty: notEmptyBlock
	^self isEmpty
		ifTrue: [emptyBlock value]
		ifFalse: [notEmptyBlock cull: self]
!
ifNotEmpty: notEmptyBlock ifEmpty: emptyBlock
	^self ifEmpty: emptyBlock ifNotEmpty: notEmptyBlock
!
includes: anObject
	"Answer whether some element equals anObject."
	^self anySatisfy: [:each | each = anObject]
!
identityIncludes: anObject
	^self anySatisfy: [:each | each == anObject]
!
includesAll: aCollection
	^aCollection allSatisfy: [:each | self includes: each]
!
includesAny: aCollection
	^aCollection anySatisfy: [:each | self includes: each]
!
occurrencesOf: anObject
	^self count: [:each | each = anObject]
! !

!Collection methodsFor: 'accessing'!
size
	"Answer the number of elements."
	| n |
	n := 0.
	self do: [:each | n := n + 1].
	^n
!
capacity
	^self size
! !

!Collection methodsFor: 'math functions'!
sum
	"Answer the sum of the elements (0 when empty)."
	^self inject: 0 into: [:a :b | a + b]
!
sum: aBlock
	^self inject: 0 into: [:a :each | a + (aBlock value: each)]
!
detectSum: aBlock
	^self sum: aBlock
!
average
	"Answer the arithmetic mean (a Fraction for integers that do not divide evenly)."
	self isEmpty ifTrue: [^self errorEmptyCollection].
	^self sum / self size
!
max
	^self inject: self anyOne into: [:a :b | a max: b]
!
min
	^self inject: self anyOne into: [:a :b | a min: b]
!
max: aBlock
	^self inject: (aBlock value: self anyOne) into: [:a :each | a max: (aBlock value: each)]
!
min: aBlock
	^self inject: (aBlock value: self anyOne) into: [:a :each | a min: (aBlock value: each)]
! !

!Collection methodsFor: 'converting'!
asArray
	| array i |
	array := Array new: self size.
	i := 0.
	self do: [:each | array at: (i := i + 1) put: each].
	^array
!
asOrderedCollection
	^(OrderedCollection new: self size) addAll: self; yourself
!
asSet
	^Set withAll: self
!
asIdentitySet
	^IdentitySet withAll: self
!
asBag
	^Bag withAll: self
!
asSortedCollection
	^self asSortedCollection: [:a :b | a <= b]
!
asSortedCollection: aSortBlock
	^(SortedCollection sortBlock: aSortBlock) addAll: self; yourself
!
asByteArray
	^ByteArray withAll: self
!
sorted
	"Answer an Array (or a copy, for sequenceable collections) of my elements in ascending order."
	^self sorted: [:a :b | a <= b]
!
sorted: aSortBlock
	^self asArray sort: aSortBlock
! !

!Collection methodsFor: 'copying'!
, aCollection
	^self copy addAll: aCollection; yourself
!
copyWith: anObject
	^self copy add: anObject; yourself
!
copyWithout: anObject
	^self reject: [:each | each = anObject]
! !

!Collection methodsFor: 'printing'!
printOn: aStream
	"Print like: an OrderedCollection(1 2 3)."
	self printNameOn: aStream.
	self printElementsOn: aStream
!
printNameOn: aStream
	super printOn: aStream
!
printElementsOn: aStream
	aStream nextPut: $(.
	self do: [:each | aStream print: each] separatedBy: [aStream space].
	aStream nextPut: $)
!
storeOn: aStream
	aStream nextPutAll: '(('; nextPutAll: self class name; nextPutAll: ' new)'.
	self do: [:each | aStream nextPutAll: ' add: '; store: each; nextPut: $;].
	aStream nextPutAll: ' yourself)'
! !

!Collection methodsFor: 'private'!
emptyCheck
	self isEmpty ifTrue: [self errorEmptyCollection]
! !

!Collection class methodsFor: 'instance creation'!
with: anObject
	^self new add: anObject; yourself
!
with: first with: second
	^self new add: first; add: second; yourself
!
with: first with: second with: third
	^self new add: first; add: second; add: third; yourself
!
with: first with: second with: third with: fourth
	^self new add: first; add: second; add: third; add: fourth; yourself
!
with: first with: second with: third with: fourth with: fifth
	^self new add: first; add: second; add: third; add: fourth; add: fifth; yourself
!
with: first with: second with: third with: fourth with: fifth with: sixth
	^self new add: first; add: second; add: third; add: fourth; add: fifth; add: sixth; yourself
!
withAll: aCollection
	^self new addAll: aCollection; yourself
!
newFrom: aCollection
	^self withAll: aCollection
! !
