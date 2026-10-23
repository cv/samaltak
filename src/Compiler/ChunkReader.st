Object subclass: #ChunkReader
	instanceVariableNames: 'source position'
	classVariableNames: ''
	package: 'Compiler'!

ChunkReader comment: 'I split chunk-format source into chunks. A chunk ends at a single exclamation mark; a doubled one stands for one exclamation mark inside the chunk.'!

!ChunkReader class methodsFor: 'instance creation'!
on: aString
	^self new setSource: aString
! !

!ChunkReader methodsFor: 'initialization'!
setSource: aString
	source := aString.
	position := 1
! !

!ChunkReader methodsFor: 'reading'!
nextChunk
	"Answer the next chunk (without its terminator), or nil at the end."
	| result start i bang |
	bang := Character value: 33.
	[position <= source size and: [(source at: position) value <= 32]] whileTrue: [position := position + 1].
	position > source size ifTrue: [^nil].
	result := nil.
	start := position.
	i := position.
	[i <= source size] whileTrue: [
		(source at: i) == bang
			ifTrue: [
				result := result isNil
					ifTrue: [source copyFrom: start to: i - 1]
					ifFalse: [result , (source copyFrom: start to: i - 1)].
				(i < source size and: [(source at: i + 1) == bang])
					ifTrue: [
						result := result , (String with: bang).
						i := i + 2.
						start := i]
					ifFalse: [
						position := i + 1.
						^result]]
			ifFalse: [i := i + 1]].
	position := source size + 1.
	^result isNil
		ifTrue: [source copyFrom: start to: source size]
		ifFalse: [result , (source copyFrom: start to: source size)]
!
isBlank: aString
	aString do: [:c | c value > 32 ifTrue: [^false]].
	^true
!
trim: aString
	"Answer aString without leading and trailing separators."
	| first last |
	first := 1.
	last := aString size.
	[first <= last and: [(aString at: first) value <= 32]] whileTrue: [first := first + 1].
	[last >= first and: [(aString at: last) value <= 32]] whileTrue: [last := last - 1].
	^aString copyFrom: first to: last
! !
