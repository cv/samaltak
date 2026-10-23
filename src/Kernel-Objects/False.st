Boolean subclass: #False
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Objects'!

False comment: 'I have a single instance, false.'!

!False methodsFor: 'logical operations'!
& aBoolean
	^false
!
| aBoolean
	^aBoolean
!
not
	^true
! !

!False methodsFor: 'controlling'!
and: aBlock
	^false
!
or: aBlock
	^aBlock value
!
ifTrue: aBlock
	^nil
!
ifFalse: aBlock
	^aBlock value
!
ifTrue: trueBlock ifFalse: falseBlock
	^falseBlock value
!
ifFalse: falseBlock ifTrue: trueBlock
	^falseBlock value
! !

!False methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'false'
! !

!False methodsFor: 'converting'!
asBit
	^0
! !
