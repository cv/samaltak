SequenceableCollection subclass: #OrderedCollection
	instanceVariableNames: 'array firstIndex lastIndex'
	classVariableNames: ''
	package: 'Kernel-Collections'!

OrderedCollection comment: 'I am a growable sequence: elements live in array between firstIndex and lastIndex, with free room at both ends, so adding and removing at either end is cheap.'!

!OrderedCollection methodsFor: 'initialization'!
setCapacity: n
	array := Array new: (n max: 1).
	firstIndex := array size // 3 max: 1.
	lastIndex := firstIndex - 1
! !

!OrderedCollection methodsFor: 'accessing'!
size
	^lastIndex - firstIndex + 1
!
capacity
	^array size
!
at: index
	(index between: 1 and: lastIndex - firstIndex + 1) ifFalse: [^self errorSubscriptBounds: index].
	^array at: index + firstIndex - 1
!
at: index put: anObject
	(index between: 1 and: lastIndex - firstIndex + 1) ifFalse: [^self errorSubscriptBounds: index].
	^array at: index + firstIndex - 1 put: anObject
!
first
	lastIndex < firstIndex ifTrue: [^self errorEmptyCollection].
	^array at: firstIndex
!
last
	lastIndex < firstIndex ifTrue: [^self errorEmptyCollection].
	^array at: lastIndex
! !

!OrderedCollection methodsFor: 'adding'!
add: anObject
	^self addLast: anObject
!
addLast: anObject
	lastIndex = array size ifTrue: [self makeRoomAtLast].
	lastIndex := lastIndex + 1.
	^array at: lastIndex put: anObject
!
addFirst: anObject
	firstIndex = 1 ifTrue: [self makeRoomAtFirst].
	firstIndex := firstIndex - 1.
	^array at: firstIndex put: anObject
!
addAll: aCollection
	^self addAllLast: aCollection
!
addAllLast: aCollection
	aCollection do: [:each | self addLast: each].
	^aCollection
!
addAllFirst: aCollection
	aCollection reverseDo: [:each | self addFirst: each].
	^aCollection
!
add: newObject beforeIndex: index
	"Insert newObject so that it ends up at index."
	(index between: 1 and: self size + 1) ifFalse: [^self errorSubscriptBounds: index].
	lastIndex = array size ifTrue: [self makeRoomAtLast].
	array replaceFrom: index + firstIndex to: lastIndex + 1 with: array startingAt: index + firstIndex - 1.
	array at: index + firstIndex - 1 put: newObject.
	lastIndex := lastIndex + 1.
	^newObject
!
add: newObject afterIndex: index
	^self add: newObject beforeIndex: index + 1
!
insert: newObject before: index
	^self add: newObject beforeIndex: index
! !

!OrderedCollection methodsFor: 'removing'!
removeFirst
	"Remove and answer the first element."
	| obj |
	lastIndex < firstIndex ifTrue: [^self errorEmptyCollection].
	obj := array at: firstIndex.
	array at: firstIndex put: nil.
	firstIndex := firstIndex + 1.
	^obj
!
removeLast
	| obj |
	lastIndex < firstIndex ifTrue: [^self errorEmptyCollection].
	obj := array at: lastIndex.
	array at: lastIndex put: nil.
	lastIndex := lastIndex - 1.
	^obj
!
removeFirst: n
	| result |
	result := Array new: n.
	1 to: n do: [:i | result at: i put: self removeFirst].
	^result
!
removeLast: n
	| result |
	result := Array new: n.
	n to: 1 by: -1 do: [:i | result at: i put: self removeLast].
	^result
!
removeIndex: index
	"Remove and answer the element at index."
	| obj i |
	obj := self at: index.
	i := index + firstIndex - 1.
	array replaceFrom: i to: lastIndex - 1 with: array startingAt: i + 1.
	array at: lastIndex put: nil.
	lastIndex := lastIndex - 1.
	^obj
!
removeAt: index
	^self removeIndex: index
!
remove: oldObject ifAbsent: aBlock
	firstIndex to: lastIndex do: [:i |
		(array at: i) = oldObject ifTrue: [^self removeIndex: i - firstIndex + 1]].
	^aBlock value
!
removeAll
	self setCapacity: 10
!
removeAllSuchThat: aBlock
	| n |
	n := firstIndex.
	firstIndex to: lastIndex do: [:i |
		| each |
		each := array at: i.
		(aBlock value: each) ifFalse: [
			array at: n put: each.
			n := n + 1]].
	n to: lastIndex do: [:i | array at: i put: nil].
	lastIndex := n - 1
! !

!OrderedCollection methodsFor: 'enumerating'!
do: aBlock
	firstIndex to: lastIndex do: [:i | aBlock value: (array at: i)]
!
reverseDo: aBlock
	lastIndex to: firstIndex by: -1 do: [:i | aBlock value: (array at: i)]
!
collect: aBlock
	| result |
	result := OrderedCollection new: self size.
	firstIndex to: lastIndex do: [:i | result addLast: (aBlock value: (array at: i))].
	^result
!
collectWithIndex: aBlock
	| result |
	result := OrderedCollection new: self size.
	1 to: self size do: [:i | result addLast: (aBlock value: (self at: i) value: i)].
	^result
!
select: aBlock
	| result |
	result := self copyEmpty.
	firstIndex to: lastIndex do: [:i |
		| each |
		each := array at: i.
		(aBlock value: each) ifTrue: [result addLast: each]].
	^result
!
with: aCollection collect: aBlock
	| result |
	aCollection size = self size ifFalse: [^self error: 'Collections must have the same size'].
	result := OrderedCollection new: self size.
	1 to: self size do: [:i | result addLast: (aBlock value: (self at: i) value: (aCollection at: i))].
	^result
! !

!OrderedCollection methodsFor: 'copying'!
postCopy
	array := array copy
!
copyEmpty
	^self species new: self size
!
copyFrom: start to: stop
	| result |
	result := self species new: stop - start + 1.
	start to: stop do: [:i | result addLast: (self at: i)].
	^result
!
, aCollection
	^self copy addAll: aCollection; yourself
!
copyWith: anObject
	^self copy addLast: anObject; yourself
!
reversed
	| result |
	result := self species new: self size.
	self reverseDo: [:each | result addLast: each].
	^result
!
copyReplaceFrom: start to: stop with: replacement
	| result |
	result := self species new: self size + replacement size.
	1 to: start - 1 do: [:i | result addLast: (self at: i)].
	result addAll: replacement.
	stop + 1 to: self size do: [:i | result addLast: (self at: i)].
	^result
!
copyReplaceAll: oldSubCollection with: newSubCollection
	^(self asArray copyReplaceAll: oldSubCollection asArray with: newSubCollection asArray) asOrderedCollection
! !

!OrderedCollection methodsFor: 'converting'!
asOrderedCollection
	^self copy
! !

!OrderedCollection methodsFor: 'private'!
makeRoomAtLast
	| newArray delta |
	delta := array size max: 4.
	newArray := Array new: array size + delta.
	newArray replaceFrom: firstIndex to: lastIndex with: array startingAt: firstIndex.
	array := newArray
!
makeRoomAtFirst
	| newArray delta |
	delta := array size max: 4.
	newArray := Array new: array size + delta.
	newArray replaceFrom: firstIndex + delta to: lastIndex + delta with: array startingAt: firstIndex.
	array := newArray.
	firstIndex := firstIndex + delta.
	lastIndex := lastIndex + delta
! !

!OrderedCollection class methodsFor: 'instance creation'!
new
	^self new: 10
!
new: anInteger
	^self basicNew setCapacity: anInteger
!
new: size withAll: anObject
	| result |
	result := self new: size.
	size timesRepeat: [result addLast: anObject].
	^result
! !
