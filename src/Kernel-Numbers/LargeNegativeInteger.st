LargePositiveInteger variableByteSubclass: #LargeNegativeInteger
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

LargeNegativeInteger comment: 'I am a negative integer beyond the SmallInteger range; my bytes are the magnitude.'!

!LargeNegativeInteger methodsFor: 'testing'!
negative
	^true
!
sign
	^-1
! !

!LargeNegativeInteger methodsFor: 'arithmetic'!
negated
	| result |
	result := LargePositiveInteger basicNew: self basicSize.
	1 to: self basicSize do: [:i | result basicAt: i put: (self basicAt: i)].
	^result normalize
!
abs
	^self negated
! !

!LargeNegativeInteger methodsFor: 'bit manipulation'!
highBit
	^self error: 'highBit is not defined for negative integers'
! !
