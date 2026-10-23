Object subclass: #WindowControl
	instanceVariableNames: 'window kind'
	classVariableNames: ''
	package: 'UI-Windows'!

WindowControl comment: 'I stand for one part of a window''s frame in remote-control snapshots: the close box, the collapse box or the resize grip (@w3.close, @w3.collapse, @w3.resize). Remote input aimed at me lands on that part of the frame, where the InputDispatcher handles it.'!

!WindowControl methodsFor: 'private'!
setWindow: aWindow kind: aSymbol
	window := aWindow.
	kind := aSymbol
! !

!WindowControl methodsFor: 'accessing'!
window
	^window
!
kind
	^kind
! !

!WindowControl methodsFor: 'remote control'!
remoteRole
	^kind == #resize ifTrue: [#handle] ifFalse: [#button]
!
remoteLabel
	^kind asString
!
remoteName
	^kind asString
!
remoteState
	^#()
!
remoteChildren
	^#()
!
remoteBounds
	| r |
	kind == #close ifTrue: [r := window closeBoxRect].
	kind == #collapse ifTrue: [r := window collapseBoxRect].
	kind == #resize ifTrue: [
		window isCollapsed ifTrue: [^nil].
		r := (window extent - (7 @ 7)) extent: 6 @ 6].
	^r translateBy: window bounds origin
!
remoteClickPoint
	| b |
	b := self remoteBounds.
	^b isNil ifTrue: [nil] ifFalse: [b center]
! !

!WindowControl class methodsFor: 'instance creation'!
window: aWindow kind: aSymbol
	^self new setWindow: aWindow kind: aSymbol
! !
