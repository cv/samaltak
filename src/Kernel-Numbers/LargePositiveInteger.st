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
digitAt: index put: aByte
	^self basicAt: index put: aByte
!
digitLength
	^self basicSize
!
uint32At: byteIndex
	"Bytes byteIndex .. byteIndex + 3 of the magnitude as one little-endian 32-bit limb."
	<primitive: 'bytesUint32At'>
	^(self digitAt: byteIndex) + ((self digitAt: byteIndex + 1) bitShift: 8) + ((self digitAt: byteIndex + 2) bitShift: 16) + ((self digitAt: byteIndex + 3) bitShift: 24)
!
uint32At: byteIndex put: anInteger
	<primitive: 'bytesUint32AtPut'>
	0 to: 3 do: [:k | self digitAt: byteIndex + k put: ((anInteger bitShift: -8 * k) bitAnd: 255)].
	^anInteger
!
generality
	^40
!
normalize
	"Answer the receiver without leading zero bytes, as a SmallInteger if it fits."
	| len value |
	len := self basicSize.
	[len > 0 and: [(self basicAt: len) = 0]] whileTrue: [len := len - 1].
	len = 0 ifTrue: [^0].
	(len < 8 or: [len = 8 and: [(self basicAt: 8) < 16r40]]) ifTrue: [
		value := 0.
		len to: 1 by: -1 do: [:i | value := (value bitShift: 8) + (self basicAt: i)].
		^self negative ifTrue: [value negated] ifFalse: [value]].
	(self negative and: [len = 8 and: [(self basicAt: 8) = 16r40 and: [(1 to: 7) allSatisfy: [:i | (self basicAt: i) = 0]]]])
		ifTrue: [^SmallInteger minVal].
	len < self basicSize ifTrue: [^self copyDigits: len].
	^self
!
copyDigits: len
	| result |
	result := self class basicNew: len.
	1 to: len do: [:i | result basicAt: i put: (self basicAt: i)].
	^result
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
negated
	| result |
	result := LargeNegativeInteger basicNew: self basicSize.
	1 to: self basicSize do: [:i | result basicAt: i put: (self basicAt: i)].
	^result normalize
!
abs
	^self
! !

!LargePositiveInteger methodsFor: 'printing'!
printString: base
	"Divide by the largest power of base below 2^48 repeatedly; each division yields a chunk of digits."
	| power k n qr chunks s |
	power := base.
	k := 1.
	[power * base < 16r1000000000000] whileTrue: [power := power * base. k := k + 1].
	chunks := OrderedCollection new.
	n := self abs.
	[n isLarge] whileTrue: [
		qr := n digitShortDivide: power neg: false.
		chunks addFirst: qr last.
		n := qr first].
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
