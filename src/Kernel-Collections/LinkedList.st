SequenceableCollection subclass: #LinkedList
	instanceVariableNames: 'firstLink lastLink'
	classVariableNames: ''
	package: 'Kernel-Collections'!

LinkedList comment: 'I am a sequence of Links chained through nextLink. The VM uses me for the process run queues (one per priority) and Semaphore inherits from me, so my field order (firstLink lastLink) is fixed. Never change a run queue or a Semaphore''s list from Smalltalk directly; use the process primitives.'!

!LinkedList methodsFor: 'accessing'!
first
	firstLink isNil ifTrue: [^self errorEmptyCollection].
	^firstLink
!
last
	lastLink isNil ifTrue: [^self errorEmptyCollection].
	^lastLink
!
firstLink
	^firstLink
!
lastLink
	^lastLink
!
size
	| n link |
	n := 0.
	link := firstLink.
	[link isNil] whileFalse: [n := n + 1. link := link nextLink].
	^n
!
at: index
	| i link |
	i := 0.
	link := firstLink.
	[link isNil] whileFalse: [
		i := i + 1.
		i = index ifTrue: [^link].
		link := link nextLink].
	^self errorSubscriptBounds: index
!
at: index put: anObject
	^self shouldNotImplement
! !

!LinkedList methodsFor: 'testing'!
isEmpty
	^firstLink isNil
!
includes: aLink
	| link |
	link := firstLink.
	[link isNil] whileFalse: [
		link == aLink ifTrue: [^true].
		link := link nextLink].
	^false
! !

!LinkedList methodsFor: 'adding'!
add: aLink
	^self addLast: aLink
!
addLast: aLink
	lastLink isNil
		ifTrue: [firstLink := aLink]
		ifFalse: [lastLink nextLink: aLink].
	lastLink := aLink.
	^aLink
!
addFirst: aLink
	lastLink isNil ifTrue: [lastLink := aLink].
	aLink nextLink: firstLink.
	firstLink := aLink.
	^aLink
! !

!LinkedList methodsFor: 'removing'!
removeFirst
	| oldLink |
	firstLink isNil ifTrue: [^self errorEmptyCollection].
	oldLink := firstLink.
	firstLink == lastLink
		ifTrue: [firstLink := nil. lastLink := nil]
		ifFalse: [firstLink := oldLink nextLink].
	oldLink nextLink: nil.
	^oldLink
!
removeLast
	| oldLink link |
	lastLink isNil ifTrue: [^self errorEmptyCollection].
	oldLink := lastLink.
	firstLink == lastLink
		ifTrue: [firstLink := nil. lastLink := nil]
		ifFalse: [
			link := firstLink.
			[link nextLink == oldLink] whileFalse: [link := link nextLink].
			link nextLink: nil.
			lastLink := link].
	oldLink nextLink: nil.
	^oldLink
!
remove: aLink ifAbsent: aBlock
	| prev link |
	firstLink isNil ifTrue: [^aBlock value].
	aLink == firstLink ifTrue: [^self removeFirst].
	prev := firstLink.
	link := firstLink nextLink.
	[link isNil] whileFalse: [
		link == aLink ifTrue: [
			prev nextLink: link nextLink.
			link == lastLink ifTrue: [lastLink := prev].
			link nextLink: nil.
			^link].
		prev := link.
		link := link nextLink].
	^aBlock value
!
removeAll
	[firstLink isNil] whileFalse: [self removeFirst]
! !

!LinkedList methodsFor: 'enumerating'!
do: aBlock
	| link |
	link := firstLink.
	[link isNil] whileFalse: [
		| next |
		next := link nextLink.
		aBlock value: link.
		link := next]
!
collect: aBlock
	^self asArray collect: aBlock
!
select: aBlock
	^self asArray select: aBlock
!
reverseDo: aBlock
	self asArray reverseDo: aBlock
!
asArray
	| result i |
	result := Array new: self size.
	i := 0.
	self do: [:each | result at: (i := i + 1) put: each].
	^result
! !

!LinkedList methodsFor: 'private'!
species
	^Array
! !
