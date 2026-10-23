HostEvent subclass: #ExposeEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

ExposeEvent comment: 'I report that the host window must be presented again (exposed).'!

!ExposeEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher exposed
! !

!ExposeEvent class methodsFor: 'decoding'!
eventType
	^#expose
! !
