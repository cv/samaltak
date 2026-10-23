PositionableStream subclass: #WriteStream
	instanceVariableNames: 'writeLimit'
	classVariableNames: ''
	package: 'Kernel-Streams'!

WriteStream comment: 'I write into an ArrayedCollection, growing it as needed; contents answers what has been written. Writing a wide Character into a ByteString makes the collection a WideString. String new: n streamContents: [:s | ...] is the usual way to build Strings.'!

!WriteStream methodsFor: 'initialization'!
on: aCollection
	super on: aCollection.
	readLimit := 0.
	writeLimit := aCollection size
!
with: aCollection
	"Start at the end of aCollection, appending to it."
	super on: aCollection.
	position := readLimit := writeLimit := aCollection size
! !

!WriteStream methodsFor: 'accessing'!
nextPut: anObject
	position >= writeLimit ifTrue: [self growTo: position + 1].
	position := position + 1.
	position > readLimit ifTrue: [readLimit := position].
	(collection streamAt: position put: anObject) == nil ifTrue: [
		(collection isString and: [collection isWideString not]) ifTrue: [
			collection := collection asWideString.
			collection at: position put: anObject]].
	^anObject
!
nextPutAll: aCollection
	"Append the elements of aCollection, bulk-copying sequenceable ones."
	| newEnd |
	aCollection isSequenceable ifFalse: [^super nextPutAll: aCollection].
	newEnd := position + aCollection size.
	newEnd > writeLimit ifTrue: [self growTo: newEnd].
	(collection isString and: [collection isWideString not
		and: [(aCollection isString and: [aCollection isWideString]) or: [aCollection isString not and: [aCollection anySatisfy: [:c | c isCharacter and: [c value > 255]]]]]])
			ifTrue: [collection := collection asWideString].
	collection replaceFrom: position + 1 to: newEnd with: aCollection startingAt: 1.
	position := newEnd.
	position > readLimit ifTrue: [readLimit := position].
	^aCollection
!
contents
	readLimit := readLimit max: position.
	^collection copyFrom: 1 to: position
!
next
	^self shouldNotImplement
!
reset
	readLimit := readLimit max: position.
	position := 0
!
resetContents
	position := 0.
	readLimit := 0
!
setToEnd
	readLimit := readLimit max: position.
	position := readLimit
!
position: anInteger
	readLimit := readLimit max: position.
	super position: anInteger
!
size
	^readLimit max: position
! !

!WriteStream methodsFor: 'printing'!
cr
	self nextPut: Character cr
!
space
	self nextPut: Character space
!
tab
	self nextPut: Character tab
! !

!WriteStream methodsFor: 'private'!
growTo: minSize
	"Grow the collection to at least minSize elements."
	| newSize newCollection |
	newSize := (collection size * 2 max: minSize) max: 16.
	newCollection := collection species new: newSize.
	newCollection replaceFrom: 1 to: collection size with: collection startingAt: 1.
	collection := newCollection.
	writeLimit := newSize
! !

!WriteStream class methodsFor: 'instance creation'!
on: aCollection
	^self basicNew on: aCollection
!
with: aCollection
	^self basicNew with: aCollection
! !
