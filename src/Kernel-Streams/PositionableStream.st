Stream subclass: #PositionableStream
	instanceVariableNames: 'collection position readLimit'
	classVariableNames: ''
	package: 'Kernel-Streams'!

PositionableStream comment: 'I am a stream over a SequenceableCollection with a position: the number of elements before the next one (0 at the start). readLimit is the number of readable elements.'!

!PositionableStream methodsFor: 'initialization'!
on: aCollection
	collection := aCollection.
	readLimit := aCollection size.
	position := 0
! !

!PositionableStream methodsFor: 'accessing'!
collection
	^collection
!
contents
	"Answer the readable part of my collection."
	^collection copyFrom: 1 to: readLimit
!
next
	"Answer the next element, or nil at the end."
	position >= readLimit ifTrue: [^nil].
	position := position + 1.
	^collection at: position
!
next: anInteger
	"Answer the next anInteger elements (fewer at the end)."
	| end result |
	end := position + anInteger min: readLimit.
	result := collection copyFrom: position + 1 to: end.
	position := end.
	^result
!
peek
	"Answer the next element without consuming it, or nil at the end."
	position >= readLimit ifTrue: [^nil].
	^collection at: position + 1
!
peekFor: anObject
	"Consume the next element if it equals anObject; answer whether it did."
	position >= readLimit ifTrue: [^false].
	(collection at: position + 1) = anObject ifFalse: [^false].
	position := position + 1.
	^true
!
upTo: anObject
	"Answer the elements up to (not including) anObject, consuming anObject; or the rest if it does not occur."
	| start |
	start := position + 1.
	[position < readLimit] whileTrue: [
		position := position + 1.
		(collection at: position) = anObject ifTrue: [^collection copyFrom: start to: position - 1]].
	^collection copyFrom: start to: readLimit
!
upToAll: aCollection
	"Answer the elements up to the next occurrence of aCollection (consumed), or the rest."
	| start index |
	start := position + 1.
	index := collection indexOfSubCollection: aCollection startingAt: start.
	(index = 0 or: [index + aCollection size - 1 > readLimit]) ifTrue: [^self upToEnd].
	position := index + aCollection size - 1.
	^collection copyFrom: start to: index - 1
!
upToEnd
	| start |
	start := position + 1.
	position := readLimit.
	^collection copyFrom: start to: readLimit
!
nextLine
	"Answer the characters up to the next line end (cr, lf or crlf), consuming it; nil at the end."
	| start c |
	self atEnd ifTrue: [^nil].
	start := position + 1.
	[position < readLimit] whileTrue: [
		position := position + 1.
		c := collection at: position.
		c = Character lf ifTrue: [^collection copyFrom: start to: position - 1].
		c = Character cr ifTrue: [
			self peekFor: Character lf.
			^collection copyFrom: start to: position - 1]].
	^collection copyFrom: start to: readLimit
!
skip: anInteger
	"Move the position by anInteger (may be negative)."
	self position: (position + anInteger max: 0)
!
skipTo: anObject
	"Consume up to and including anObject; answer whether it was found."
	[position < readLimit] whileTrue: [
		position := position + 1.
		(collection at: position) = anObject ifTrue: [^true]].
	^false
!
skipSeparators
	[position < readLimit and: [(collection at: position + 1) isSeparator]]
		whileTrue: [position := position + 1]
!
nextWord
	| start |
	self skipSeparators.
	start := position + 1.
	[position < readLimit and: [(collection at: position + 1) isSeparator not]]
		whileTrue: [position := position + 1].
	^collection copyFrom: start to: position
!
originalContents
	^collection
! !

!PositionableStream methodsFor: 'positioning'!
position
	^position
!
position: anInteger
	(anInteger between: 0 and: readLimit) ifFalse: [^self error: 'Position out of bounds'].
	position := anInteger
!
reset
	position := 0
!
setToEnd
	position := readLimit
!
size
	^readLimit
! !

!PositionableStream methodsFor: 'testing'!
atEnd
	^position >= readLimit
!
isEmpty
	^readLimit = 0
!
notEmpty
	^readLimit > 0
! !

!PositionableStream class methodsFor: 'instance creation'!
on: aCollection
	^self basicNew on: aCollection
!
on: aCollection from: firstIndex to: lastIndex
	^self on: (aCollection copyFrom: firstIndex to: lastIndex)
! !
