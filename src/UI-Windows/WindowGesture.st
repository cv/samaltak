Object subclass: #WindowGesture
	instanceVariableNames: 'window'
	classVariableNames: ''
	package: 'UI-Windows'!

WindowGesture comment: 'I am the abstract window-manager gesture the InputDispatcher runs between a press on a window''s frame and the release: it sends me pointerMoved: for each move and pointerReleased: at the end (screen points), in its own Process, so I work while the window''s Process is busy.'!

!WindowGesture methodsFor: 'accessing'!
window
	^window
!
setWindow: aWindow
	window := aWindow
! !

!WindowGesture methodsFor: 'pointer'!
pointerMoved: aPoint
	self subclassResponsibility
!
pointerReleased: aPoint
	self pointerMoved: aPoint
! !
