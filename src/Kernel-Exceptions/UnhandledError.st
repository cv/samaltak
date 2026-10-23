Exception subclass: #UnhandledError
	instanceVariableNames: 'exception'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

UnhandledError comment: 'I am signaled when an Error (or another exception without its own default) is not handled. My default action asks Smalltalk to deal with it: a hookable handler (the debugger, once the UI is loaded), or, headless, printing the error and the stack to stderr and terminating the faulting process. The value my default action answers resumes the original exception.'!

!UnhandledError methodsFor: 'accessing'!
exception
	^exception
!
exception: anException
	exception := anException
!
description
	^'Unhandled: ', exception printString
! !

!UnhandledError methodsFor: 'testing'!
isResumable
	^true
! !

!UnhandledError methodsFor: 'exception description'!
defaultAction
	^Smalltalk handleUnhandledError: exception
! !

!UnhandledError class methodsFor: 'signaling'!
signalForException: anException
	^self new exception: anException; signal
! !
