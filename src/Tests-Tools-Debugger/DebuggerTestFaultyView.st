Widget subclass: #DebuggerTestFaultyView
	instanceVariableNames: 'clicks'
	classVariableNames: ''
	package: 'Tests-Tools-Debugger'!

DebuggerTestFaultyView comment: 'I divide by zero when clicked, in my window''s Process (for the Window errorHandler test).'!

!DebuggerTestFaultyView methodsFor: 'accessing'!
clicks
	^clicks ifNil: [0]
! !

!DebuggerTestFaultyView methodsFor: 'events'!
mouseDown: anEvent
	clicks := self clicks + 1.
	^(1 / 0) notNil
!
mouseUp: anEvent
	^true
! !

!DebuggerTestFaultyView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	aCanvas fillRect: self localBounds color: self theme paper
! !

!DebuggerTestFaultyView methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteName
	^'faulty'
! !
