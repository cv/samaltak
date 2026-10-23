Object subclass: #DemoButtonNode
	instanceVariableNames: 'view'
	classVariableNames: ''
	package: 'Demos'!

DemoButtonNode comment: 'I expose a DemoView''s button-like box to remote control (@w1.view.button).'!

!DemoButtonNode methodsFor: 'remote control'!
setView: aDemoView
	view := aDemoView
!
remoteRole
	^#button
!
remoteLabel
	^'Click me'
!
remoteName
	^'button'
!
remoteState
	^#()
!
remoteChildren
	^#()
!
remoteBounds
	| b |
	b := view screenBounds.
	^b isNil ifTrue: [nil] ifFalse: [view buttonRect translateBy: b origin]
! !

!DemoButtonNode class methodsFor: 'instance creation'!
view: aDemoView
	^self new setView: aDemoView
! !
