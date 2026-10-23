SequenceableCollection subclass: #ArrayedCollection
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

ArrayedCollection comment: 'I am the abstract class of fixed-size sequences whose elements are the indexable fields of the object itself (Array, ByteArray, strings, Bitmap). I cannot grow: add: is not allowed; copies are made with new: and the bulk-copy primitive.'!

!ArrayedCollection methodsFor: 'accessing'!
size
	<primitive: 'basicSize'>
	^self basicSize
! !

!ArrayedCollection methodsFor: 'adding'!
add: anObject
	^self shouldNotImplement
! !

!ArrayedCollection methodsFor: 'removing'!
remove: oldObject ifAbsent: aBlock
	^self shouldNotImplement
! !

!ArrayedCollection methodsFor: 'accessing'!
replaceFrom: start to: stop with: replacement startingAt: repStart
	"Bulk copy; the primitive handles same-format replacement, the fallback anything else."
	<primitive: 'replaceFromToWithStartingAt'>
	^super replaceFrom: start to: stop with: replacement startingAt: repStart
! !

!ArrayedCollection methodsFor: 'private'!
streamAt: index put: anObject
	"Store for a WriteStream. Strings answer nil instead of widening (the stream widens its collection itself)."
	<primitive: 'atPut'>
	^self at: index put: anObject
! !

!ArrayedCollection methodsFor: 'printing'!
storeOn: aStream
	aStream nextPutAll: '(('; nextPutAll: self class name; nextPutAll: ' new: '; print: self size; nextPutAll: ')'.
	1 to: self size do: [:i |
		aStream nextPutAll: ' at: '; print: i; nextPutAll: ' put: '; store: (self at: i); nextPut: $;].
	aStream nextPutAll: ' yourself)'
! !

!ArrayedCollection class methodsFor: 'instance creation'!
new
	^self new: 0
!
new: size withAll: anObject
	"Answer an instance with size elements, each anObject."
	^(self new: size) atAllPut: anObject; yourself
!
with: anObject
	^(self new: 1) at: 1 put: anObject; yourself
!
with: first with: second
	^(self new: 2) at: 1 put: first; at: 2 put: second; yourself
!
with: first with: second with: third
	^(self new: 3) at: 1 put: first; at: 2 put: second; at: 3 put: third; yourself
!
with: first with: second with: third with: fourth
	^(self new: 4) at: 1 put: first; at: 2 put: second; at: 3 put: third; at: 4 put: fourth; yourself
!
with: first with: second with: third with: fourth with: fifth
	^(self new: 5) at: 1 put: first; at: 2 put: second; at: 3 put: third; at: 4 put: fourth; at: 5 put: fifth; yourself
!
with: first with: second with: third with: fourth with: fifth with: sixth
	^(self new: 6) at: 1 put: first; at: 2 put: second; at: 3 put: third; at: 4 put: fourth; at: 5 put: fifth; at: 6 put: sixth; yourself
!
withAll: aCollection
	"Answer an instance with the elements of aCollection."
	| result i |
	result := self new: aCollection size.
	aCollection isSequenceable
		ifTrue: [1 to: aCollection size do: [:j | result at: j put: (aCollection at: j)]]
		ifFalse: [
			i := 0.
			aCollection do: [:each | result at: (i := i + 1) put: each]].
	^result
!
new: size streamContents: aBlock
	"Answer the contents of a WriteStream on an instance of size size after aBlock has written to it."
	| stream |
	stream := WriteStream on: (self new: size).
	aBlock value: stream.
	^stream contents
!
streamContents: aBlock
	^self new: 100 streamContents: aBlock
! !
