Object subclass: #SystemView
	instanceVariableNames: 'title frame inner tab covered view'
	classVariableNames: ''
	package: 'ST80-UI'!

SystemView comment: 'I am a window: a frame with a black border, a title tab above its top left (reversed while I am the active window) and a view inside it (a TextView, a BallView), which draws in my inner rectangle. A view that changes while other windows cover me (the desk tells me, see ScreenController>>arrange) redraws through redisplay, which draws me and every window in front of me again.'!

!SystemView class methodsFor: 'instance creation'!
title: aString frame: aRectangle view: aView
	^self new setTitle: aString frame: aRectangle view: aView
! !

!SystemView methodsFor: 'initialization'!
setTitle: aString frame: aRectangle view: aView
	title := aString.
	covered := false.
	self frame: aRectangle.
	view := aView.
	view window: self
! !

!SystemView methodsFor: 'accessing'!
title
	^title
!
title: aString
	title := aString.
	self frame: frame.
	ScreenController current arrange; displayAll
!
frame
	^frame
!
frame: aRectangle
	| cell |
	cell := Display cell.
	frame := aRectangle.
	inner := frame insetBy: 1.
	tab := frame left @ (frame top - cell y - 1) extent: (title size * cell x + 10) @ (cell y + 2).
	view isNil ifFalse: [view layout]
!
inner
	^inner
!
tab
	^tab
!
bounds
	^frame merge: tab
!
view
	^view
!
moveTo: aPoint
	self frame: (frame translateBy: aPoint - frame origin)
!
covered: aBoolean
	covered := aBoolean
! !

!SystemView methodsFor: 'testing'!
containsPoint: aPoint
	^(frame containsPoint: aPoint) or: [tab containsPoint: aPoint]
!
isActive
	^ScreenController current activeWindow == self
!
isCovered
	"Whether a window in front of me overlaps me."
	^covered
! !

!SystemView methodsFor: 'displaying'!
display
	Display black: frame.
	Display white: inner.
	self displayTab.
	view display
!
displayTab
	Display black: tab.
	self isActive
		ifTrue: [Display showReversed: title at: tab origin + (5 @ 1)]
		ifFalse: [
			Display white: (tab insetBy: 1).
			Display show: title at: tab origin + (5 @ 1)]
!
redisplay
	ScreenController current redisplay: self
! !

!SystemView methodsFor: 'events'!
mouseDown: aPoint
	view mouseDown: aPoint
!
key: aCode modifiers: anInteger
	view key: aCode modifiers: anInteger
!
step
	view step
! !
