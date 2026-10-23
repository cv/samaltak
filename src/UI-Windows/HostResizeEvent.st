HostEvent subclass: #HostResizeEvent
	instanceVariableNames: 'extent'
	classVariableNames: ''
	package: 'UI-Windows'!

HostResizeEvent comment: 'I report the host window''s new size (extent, points).'!

!HostResizeEvent methodsFor: 'accessing'!
extent
	^extent
!
setFrom: anArray
	extent := (anArray at: 3) @ (anArray at: 4)
! !

!HostResizeEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher hostResized: extent
! !

!HostResizeEvent class methodsFor: 'decoding'!
eventType
	^#resize
! !
