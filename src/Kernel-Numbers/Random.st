Object subclass: #Random
	instanceVariableNames: 'seed'
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Random comment: 'I am a pseudo-random number generator: the Park-Miller "minimal standard" multiplicative congruential generator (seed := seed * 16807 \\ (2^31 - 1)), which stays within SmallIntegers. Not for cryptography.'!

!Random methodsFor: 'initialization'!
initialize
	self seed: Time microsecondClockValue
!
seed: anInteger
	"Set the seed; any integer is mapped into 1..2^31-2."
	seed := anInteger abs \\ 16r7FFFFFFE + 1
! !

!Random methodsFor: 'accessing'!
seed
	^seed
!
nextValue
	"Advance and answer the next raw value in 1..2^31-2."
	seed := seed * 16807 \\ 16r7FFFFFFF.
	^seed
!
next
	"Answer a Float in [0, 1)."
	^(self nextValue - 1) asFloat / 2147483646.0
!
nextInt: anInteger
	"Answer an Integer in 1..anInteger."
	anInteger <= 0 ifTrue: [^self error: 'nextInt: needs a positive argument'].
	^(self next * anInteger) truncated + 1
!
between: low and: high
	^low + (self nextInt: high - low + 1) - 1
!
next: n
	^(1 to: n) collect: [:i | self next]
! !

!Random class methodsFor: 'instance creation'!
seed: anInteger
	^self basicNew seed: anInteger; yourself
! !
