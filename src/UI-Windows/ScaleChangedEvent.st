HostEvent subclass: #ScaleChangedEvent
	instanceVariableNames: 'scale'
	classVariableNames: ''
	package: 'UI-Windows'!

ScaleChangedEvent comment: 'I report the host window''s new display scale (pixels per point).'!

!ScaleChangedEvent methodsFor: 'accessing'!
scale
	^scale
!
setFrom: anArray
	scale := anArray at: 3
! !

!ScaleChangedEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	^anInputDispatcher displayScaleChanged: scale
! !

!ScaleChangedEvent class methodsFor: 'decoding'!
eventType
	^#scaleChanged
! !
