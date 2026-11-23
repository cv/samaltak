HostEvent subclass: #QuitEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

QuitEvent comment: 'I report that the window manager closed the host window (or asked it to close). A quit of the whole process is a ProcessQuitEvent.'!

!QuitEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher quitRequested
! !

!QuitEvent class methodsFor: 'decoding'!
eventType
	^#close
! !
