WindowGesture subclass: #DragGesture
	instanceVariableNames: 'grabOffset'
	classVariableNames: ''
	package: 'UI-Windows'!

DragGesture comment: 'I move a window dragged by its title bar: grabOffset is where the pointer holds it (from its origin). I keep 60 points of the window on the desk horizontally and its title bar between the top bar and the bottom of the screen.'!

!DragGesture methodsFor: 'accessing'!
grabOffset
	^grabOffset
!
setGrabOffset: aPoint
	grabOffset := aPoint
! !

!DragGesture methodsFor: 'pointer'!
pointerMoved: p
	| world b |
	world := window world.
	b := window bounds.
	window moveTo: (((p x - grabOffset x) max: 60 - b width) min: world extent x - 60)
		@ (((p y - grabOffset y) max: world topBar height) min: world extent y - 26)
! !

!DragGesture class methodsFor: 'instance creation'!
window: aWindow grabOffset: aPoint
	^self new setWindow: aWindow; setGrabOffset: aPoint; yourself
! !
