Exception subclass: #Error
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

Error comment: 'I am the class of errors: conditions a program does not expect. I am not resumable; unhandled I end in UnhandledError (debugger, or a printed stack when headless).'!

!Error methodsFor: 'testing'!
isResumable
	^false
! !
