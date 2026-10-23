Widget subclass: #DebuggerSeparator
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

DebuggerSeparator comment: 'I am the short vertical rule between groups of buttons in the Debugger''s button bar (prototype .dbg-sep).'!

!DebuggerSeparator methodsFor: 'initialization'!
initialize
	super initialize.
	self fixed: 9
! !

!DebuggerSeparator methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| x |
	x := (self width / 2) floor.
	aCanvas fillRect: (x @ ((self height - 14) / 2) extent: 1 @ 14) color: self theme rule
! !

!DebuggerSeparator methodsFor: 'remote control'!
remoteIsTransparent
	^true
! !
