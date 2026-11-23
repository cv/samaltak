HostEvent subclass: #ProcessQuitEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

ProcessQuitEvent comment: 'I report that the process was asked to quit (SIGTERM, SIGINT, the session ending), not one host window: whichever World''s InputDispatcher receives me quits, whether or not its host window is the application''s main one (World>>processQuitRequested).'!

!ProcessQuitEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher processQuitRequested
! !

!ProcessQuitEvent class methodsFor: 'decoding'!
eventType
	^#quit
! !
