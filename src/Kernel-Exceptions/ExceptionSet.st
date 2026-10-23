Object subclass: #ExceptionSet
	instanceVariableNames: 'exceptions'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

ExceptionSet comment: 'I group exception classes for one handler: [...] on: ZeroDivide, MessageNotUnderstood do: [...].'!

!ExceptionSet methodsFor: 'initialization'!
initialize
	exceptions := OrderedCollection new
! !

!ExceptionSet methodsFor: 'accessing'!
add: anExceptionClass
	exceptions add: anExceptionClass.
	^anExceptionClass
!
, anExceptionClass
	^self copy add: anExceptionClass; yourself
!
handles: anException
	^exceptions anySatisfy: [:each | each handles: anException]
! !

!ExceptionSet methodsFor: 'copying'!
postCopy
	exceptions := exceptions copy
! !
