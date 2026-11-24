HostEvent subclass: #HostMovedEvent
	instanceVariableNames: 'origin'
	classVariableNames: ''
	package: 'UI-Windows'!

HostMovedEvent comment: 'I report where the host window now is (origin, points: a desktop window from the top left of the area the bar leaves free, another on the screen), once the system applied a move (HostWindow>>moveTo:). Pointer events before me are relative to the old place, those after me to the new one: the InputDispatcher adds origin to their position (PointerEvent>>screenPosition).'!

!HostMovedEvent methodsFor: 'accessing'!
origin
	^origin
!
setFrom: anArray
	origin := (anArray at: 3) @ (anArray at: 4)
! !

!HostMovedEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher hostMoved: origin
! !

!HostMovedEvent class methodsFor: 'decoding'!
eventType
	^#moved
! !
