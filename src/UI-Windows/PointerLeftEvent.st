HostEvent subclass: #PointerLeftEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

PointerLeftEvent comment: 'I report that the pointer left the host window.'!

!PointerLeftEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher pointerLeft
! !

!PointerLeftEvent class methodsFor: 'decoding'!
eventType
	^#pointerLeft
! !
