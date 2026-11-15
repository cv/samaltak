View subclass: #RecordingTestView
	instanceVariableNames: 'events color handles focusable subviews layouts cursor menu failOnClick tooltip'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

RecordingTestView comment: 'I am a test View: I fill myself with color, record the events and focus changes I get (with their local positions), optionally hold child views, and answer handled as configured.'!

!RecordingTestView methodsFor: 'initialization'!
initialize
	super initialize.
	events := OrderedCollection new.
	color := Color white.
	handles := true.
	focusable := true.
	subviews := #().
	layouts := 0.
	cursor := #arrow.
	failOnClick := false
! !

!RecordingTestView methodsFor: 'accessing'!
events
	^events
!
color: aColor
	color := aColor
!
handles: aBoolean
	handles := aBoolean
!
focusable: aBoolean
	focusable := aBoolean
!
cursor: aSymbol
	cursor := aSymbol
!
menu: aView
	menu := aView
!
tooltip: aString
	tooltip := aString
!
failOnClick: aBoolean
	failOnClick := aBoolean
!
layouts
	^layouts
!
addSubview: aView
	aView owner: self.
	subviews := subviews copyWith: aView.
	^aView
!
children
	^subviews
!
eventsOfType: aSymbol
	^events select: [:e | e isUIEvent and: [e type == aSymbol]]
!
pointerEvents
	^events select: [:e | e isUIEvent and: [e isPointer]]
! !

!RecordingTestView methodsFor: 'drawing'!
drawOn: aCanvas
	aCanvas fillRect: self localBounds color: color.
	self drawChildrenOn: aCanvas
!
layout
	layouts := layouts + 1
! !

!RecordingTestView methodsFor: 'events'!
handlePointer: anEvent
	events add: anEvent.
	(failOnClick and: [anEvent isDown]) ifTrue: [self error: 'click failure'].
	^handles
!
handleKey: anEvent
	events add: anEvent.
	^handles
!
handleText: anEvent
	events add: anEvent.
	^handles
!
handleTextEditing: anEvent
	events add: anEvent.
	^handles
!
wantsKeyboardFocus
	^focusable
!
focusGained
	events add: #focusGained
!
focusLost
	events add: #focusLost
!
cursorAt: aPoint
	^cursor
!
contextMenuAt: aPoint
	^menu
!
tooltipAt: aPoint
	^tooltip
! !

!RecordingTestView methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteName
	^'view'
! !
