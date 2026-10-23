Object subclass: #MethodDictionary
	instanceVariableNames: 'tally keys values'
	classVariableNames: ''
	package: 'Kernel-Classes'!

MethodDictionary comment: 'I map selectors to CompiledMethods for one class. The VM probes me directly during method lookup: keys and values are parallel Arrays whose capacity is a power of two; a selector lives at (identityHash bitAnd: capacity - 1) + 1 or after it (linear probing, wrapping around); nil keys are empty slots. I never fill up beyond half my capacity. Because the VM can look me up at any send, every change stores the value before the key and replaces both Arrays in consecutive statements without sends.'!

!MethodDictionary methodsFor: 'accessing'!
at: aSelector
	^self at: aSelector ifAbsent: [self errorKeyNotFound: aSelector]
!
at: aSelector ifAbsent: aBlock
	| index |
	index := self scanFor: aSelector.
	(keys at: index) == nil ifTrue: [^aBlock value].
	^values at: index
!
at: aSelector put: aCompiledMethod
	| index |
	index := self scanFor: aSelector.
	(keys at: index) == nil
		ifTrue: [
			(tally + 1) * 2 > keys size ifTrue: [
				self growTo: keys size * 2.
				^self at: aSelector put: aCompiledMethod].
			values at: index put: aCompiledMethod.
			keys at: index put: aSelector.
			tally := tally + 1]
		ifFalse: [values at: index put: aCompiledMethod].
	^aCompiledMethod
!
keyAtValue: aCompiledMethod
	^self keyAtValue: aCompiledMethod ifAbsent: [nil]
!
keyAtValue: aCompiledMethod ifAbsent: aBlock
	1 to: keys size do: [:i |
		((keys at: i) notNil and: [(values at: i) == aCompiledMethod]) ifTrue: [^keys at: i]].
	^aBlock value
!
keys
	"Answer an Array of my selectors."
	| result |
	result := OrderedCollection new: tally.
	self keysDo: [:k | result add: k].
	^result asArray
!
values
	| result |
	result := OrderedCollection new: tally.
	self valuesDo: [:v | result add: v].
	^result asArray
!
size
	^tally
!
capacity
	^keys size
! !

!MethodDictionary methodsFor: 'testing'!
includesKey: aSelector
	^(keys at: (self scanFor: aSelector)) notNil
!
isEmpty
	^tally = 0
!
notEmpty
	^tally > 0
! !

!MethodDictionary methodsFor: 'enumerating'!
keysDo: aBlock
	1 to: keys size do: [:i | | k | (k := keys at: i) == nil ifFalse: [aBlock value: k]]
!
valuesDo: aBlock
	1 to: keys size do: [:i | (keys at: i) == nil ifFalse: [aBlock value: (values at: i)]]
!
keysAndValuesDo: aBlock
	1 to: keys size do: [:i | | k | (k := keys at: i) == nil ifFalse: [aBlock value: k value: (values at: i)]]
!
associationsDo: aBlock
	self keysAndValuesDo: [:k :v | aBlock value: (Association key: k value: v)]
!
do: aBlock
	self valuesDo: aBlock
! !

!MethodDictionary methodsFor: 'removing'!
removeKey: aSelector
	^self removeKey: aSelector ifAbsent: [self errorKeyNotFound: aSelector]
!
removeKey: aSelector ifAbsent: aBlock
	"Rebuild without aSelector; the new Arrays replace the old ones atomically."
	| value newKeys newValues |
	(self includesKey: aSelector) ifFalse: [^aBlock value].
	value := self at: aSelector.
	newKeys := Array new: keys size.
	newValues := Array new: keys size.
	self keysAndValuesDo: [:k :v |
		k == aSelector ifFalse: [| index |
			index := self class scanFor: k in: newKeys.
			newValues at: index put: v.
			newKeys at: index put: k]].
	values := newValues.
	keys := newKeys.
	tally := tally - 1.
	^value
! !

!MethodDictionary methodsFor: 'private'!
scanFor: aSelector
	"Answer the index of aSelector or of the empty slot where it would go."
	^self class scanFor: aSelector in: keys
!
growTo: newCapacity
	| newKeys newValues |
	newKeys := Array new: newCapacity.
	newValues := Array new: newCapacity.
	self keysAndValuesDo: [:k :v | | index |
		index := self class scanFor: k in: newKeys.
		newValues at: index put: v.
		newKeys at: index put: k].
	values := newValues.
	keys := newKeys
!
rehash
	self growTo: keys size
!
init: capacity
	tally := 0.
	keys := Array new: capacity.
	values := Array new: capacity
! !

!MethodDictionary methodsFor: 'copying'!
postCopy
	keys := keys copy.
	values := values copy
! !

!MethodDictionary methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a MethodDictionary('.
	self keys asSortedCollection do: [:k | aStream print: k] separatedBy: [aStream space].
	aStream nextPut: $)
! !

!MethodDictionary class methodsFor: 'instance creation'!
new
	^self new: 16
!
new: n
	"Answer an empty MethodDictionary with room for n methods."
	| capacity |
	capacity := 4.
	[capacity < (n * 2)] whileTrue: [capacity := capacity * 2].
	^self basicNew init: capacity
! !

!MethodDictionary class methodsFor: 'private'!
scanFor: aSelector in: anArray
	| mask index k |
	mask := anArray size - 1.
	index := (aSelector identityHash bitAnd: mask) + 1.
	[(k := anArray at: index) == nil or: [k == aSelector]]
		whileFalse: [index := (index bitAnd: mask) + 1].
	^index
! !
