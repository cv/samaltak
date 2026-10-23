HostEvent subclass: #FocusLostEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

FocusLostEvent comment: 'I report that the host window lost the keyboard focus.'!

!FocusLostEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher focusLost
! !

!FocusLostEvent class methodsFor: 'decoding'!
eventType
	^#focusLost
! !
