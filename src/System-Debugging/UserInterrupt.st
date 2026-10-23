Halt subclass: #UserInterrupt
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Debugging'!

UserInterrupt comment: 'I am signaled in a process by Process>>interrupt (the user''s interrupt key): a halt at the process''s next safepoint. Proceeding continues where the process was interrupted.'!

!UserInterrupt methodsFor: 'accessing'!
description
	^'User interrupt'
! !
