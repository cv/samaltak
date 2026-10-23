Boolean subclass: #True
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Objects'!

True comment: 'I have a single instance, true.'!

!True methodsFor: 'logical operations'!
& aBoolean
	^aBoolean
!
| aBoolean
	^true
!
not
	^false
! !

!True methodsFor: 'controlling'!
and: aBlock
	^aBlock value
!
or: aBlock
	^true
!
ifTrue: aBlock
	^aBlock value
!
ifFalse: aBlock
	^nil
!
ifTrue: trueBlock ifFalse: falseBlock
	^trueBlock value
!
ifFalse: falseBlock ifTrue: trueBlock
	^trueBlock value
! !

!True methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'true'
! !

!True methodsFor: 'converting'!
asBit
	^1
! !
