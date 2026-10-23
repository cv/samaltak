Exception subclass: #Notification
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

Notification comment: 'I am an exception that signals an event rather than a problem. Unhandled, I resume with nil.'!

!Notification methodsFor: 'exception description'!
defaultAction
	^nil
! !
