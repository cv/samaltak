Error subclass: #BlockCannotReturn
	instanceVariableNames: 'result deadHome'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

BlockCannotReturn comment: 'I am signaled when a block tries a non-local return (^) to a method context that has already returned. If resumed, the block answers the resumption value to its caller instead.'!

!BlockCannotReturn methodsFor: 'accessing'!
result
	^result
!
result: anObject
	result := anObject
!
deadHome
	^deadHome
!
deadHome: aContext
	deadHome := aContext
! !

!BlockCannotReturn methodsFor: 'testing'!
isResumable
	^true
! !
