Widget subclass: #DebuggerRule
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

DebuggerRule comment: 'I am a 1-point Blue Book rule between panes that have none of their own.'!

!DebuggerRule methodsFor: 'initialization'!
initialize
	super initialize.
	self fixed: 1
! !

!DebuggerRule methodsFor: 'drawing'!
drawSelfOn: aCanvas
	aCanvas fillRect: self localBounds color: self theme rule
! !

!DebuggerRule methodsFor: 'remote control'!
remoteIsTransparent
	^true
! !
