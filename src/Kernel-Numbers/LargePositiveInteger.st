Integer variableByteSubclass: #LargePositiveInteger
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

LargePositiveInteger comment: 'I am a positive integer beyond the SmallInteger range. My indexable bytes are the magnitude, least significant first, without leading zero bytes. Arithmetic is inherited from Integer; results are normalized back to SmallIntegers when they fit.'!

!LargePositiveInteger methodsFor: 'private'!
digitAt: index
	index > self basicSize ifTrue: [^0].
	^self basicAt: index
!
digitLength
	^self basicSize
!
generality
	^40
! !

!LargePositiveInteger methodsFor: 'testing'!
negative
	^false
!
isLarge
	^true
!
sign
	^1
!
isZero
	^false
! !

!LargePositiveInteger methodsFor: 'arithmetic'!
abs
	^self
! !

!LargePositiveInteger methodsFor: 'printing'!
printString: base
	"Divide by the largest power of base below 2^30 repeatedly (one 32-bit limb at a time); each division yields a chunk of digits."
	| power k n chunks s |
	power := base.
	k := 1.
	[power * base < 16r40000000] whileTrue: [power := power * base. k := k + 1].
	chunks := OrderedCollection new.
	n := self abs.
	[n isLarge] whileTrue: [
		chunks addFirst: n \\ power.
		n := n // power].
	s := WriteStream on: (String new: chunks size + 1 * k + 1).
	self negative ifTrue: [s nextPut: $-].
	s nextPutAll: (n printString: base).
	chunks do: [:chunk | s nextPutAll: ((chunk printString: base) padLeftTo: k with: $0)].
	^s contents
! !

!LargePositiveInteger methodsFor: 'copying'!
shallowCopy
	^self
!
deepCopy
	^self
! !
