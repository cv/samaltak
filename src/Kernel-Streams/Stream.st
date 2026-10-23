Object subclass: #Stream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Streams'!

Stream comment: 'I am the abstract class of sequential readers and writers. Readers implement next and atEnd, writers nextPut:; I build the rest (nextPutAll:, print:, <<, do:, next:) on those.'!

!Stream methodsFor: 'accessing'!
next
	^self subclassResponsibility
!
next: anInteger
	"Answer the next anInteger elements."
	| result |
	result := OrderedCollection new.
	[result size < anInteger and: [self atEnd not]] whileTrue: [result add: self next].
	^result asArray
!
nextPut: anObject
	^self subclassResponsibility
!
nextPutAll: aCollection
	aCollection do: [:each | self nextPut: each].
	^aCollection
!
next: anInteger put: anObject
	anInteger timesRepeat: [self nextPut: anObject].
	^anObject
!
contents
	^self subclassResponsibility
!
upToEnd
	| result |
	result := OrderedCollection new.
	[self atEnd] whileFalse: [result add: self next].
	^result asArray
! !

!Stream methodsFor: 'testing'!
atEnd
	^self subclassResponsibility
!
isStream
	^true
! !

!Stream methodsFor: 'enumerating'!
do: aBlock
	[self atEnd] whileFalse: [aBlock value: self next]
! !

!Stream methodsFor: 'printing'!
print: anObject
	"Append anObject's printString."
	anObject printOn: self
!
display: anObject
	"Append anObject's displayString."
	anObject displayOn: self
!
store: anObject
	anObject storeOn: self
!
<< anObject
	"Append anObject: Strings verbatim, anything else via displayString. Answer the receiver for chaining."
	anObject isString
		ifTrue: [self nextPutAll: anObject]
		ifFalse: [anObject displayOn: self]
!
space
	self nextPut: Character space
!
space: n
	n timesRepeat: [self space]
!
tab
	self nextPut: Character tab
!
tab: n
	n timesRepeat: [self tab]
!
cr
	self nextPut: Character cr
!
lf
	self nextPut: Character lf
!
newLine
	self nextPut: Character lf
!
crlf
	self cr; lf
!
print: aNumber showingDecimalPlaces: n
	self nextPutAll: (aNumber printShowingDecimalPlaces: n)
! !

!Stream methodsFor: 'flushing'!
flush
!
close
! !
