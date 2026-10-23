HostEvent subclass: #QuitEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

QuitEvent comment: 'I report that the host window was closed or the application asked to quit.'!

!QuitEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher quitRequested
! !

!QuitEvent class methodsFor: 'decoding'!
eventType
	^#quit
! !
