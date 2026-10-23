Object subclass: #Magnitude
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Magnitude comment: 'I am the abstract class of linearly ordered values (numbers, characters, dates). Subclasses define < and =; I derive the other comparisons.'!

!Magnitude methodsFor: 'comparing'!
< aMagnitude
	^self subclassResponsibility
!
= aMagnitude
	^self subclassResponsibility
!
hash
	^self subclassResponsibility
!
> aMagnitude
	^aMagnitude < self
!
<= aMagnitude
	^(aMagnitude < self) not
!
>= aMagnitude
	^(self < aMagnitude) not
!
between: min and: max
	^self >= min and: [self <= max]
!
max: aMagnitude
	^self > aMagnitude ifTrue: [self] ifFalse: [aMagnitude]
!
min: aMagnitude
	^self < aMagnitude ifTrue: [self] ifFalse: [aMagnitude]
!
min: min max: max
	^(self max: min) min: max
!
compare: aMagnitude
	"Answer -1, 0 or 1."
	self < aMagnitude ifTrue: [^-1].
	aMagnitude < self ifTrue: [^1].
	^0
! !
