Window subclass: #OverlayWindow
	instanceVariableNames: 'invoker'
	classVariableNames: ''
	package: 'UI-Windows'!

OverlayWindow comment: 'I am a chromeless window above all others: the World hosts menus (and other popups) in me. My content fills me; the compositor draws my hard 2-point shadow. I fade in with a 4-point drop, get every key while I am open, and close when the pointer goes down outside me. invoker is the window that was active when I opened: menu actions that touch its widgets run there (invoker do: [...]).'!

!OverlayWindow methodsFor: 'accessing'!
invoker
	^invoker
!
invoker: aWindow
	invoker := aWindow
! !

!OverlayWindow methodsFor: 'geometry'!
contentTop
	^0
!
contentRectInWindow
	^0 @ 0 extent: bounds extent
!
collapsedHeight
	^bounds height
!
zoneAt: aScreenPoint
	^(bounds containsPoint: aScreenPoint) ifTrue: [#content] ifFalse: [nil]
!
constrain: aRectangle
	^aRectangle
! !

!OverlayWindow methodsFor: 'testing'!
isOverlay
	^true
!
isFocused
	^true
!
isBusy
	^false
! !

!OverlayWindow methodsFor: 'chrome'!
chromeKey
	^bounds extent
!
drawChromeOn: aCanvas
!
chromeDisplayListScale: aNumber
	^nil
!
drawDecorationsOn: aCanvas time: ms
!
needsDecorations: ms
	^false
!
decorationsNeedFrameAt: ms
	^false
! !

!OverlayWindow methodsFor: 'opening and closing'!
openIn: aWorld
	state == #new ifFalse: [^self].
	super openIn: aWorld.
	content isNil ifFalse: [self do: [self keyboardFocus: content]]
!
addToWorld
	world addOverlay: self
!
removeFromWorld
	world removeOverlay: self
! !

!OverlayWindow methodsFor: 'remote control'!
remoteRole
	^content isNil ifTrue: [#overlay] ifFalse: [content remoteRole]
!
remoteLabel
	^content isNil ifTrue: [nil] ifFalse: [content remoteLabel]
!
remoteState
	^content isNil ifTrue: [#()] ifFalse: [content remoteState]
!
remoteName
	^content isNil ifTrue: ['menu'] ifFalse: [content remoteName ifNil: ['menu']]
!
remoteClickPoint
	^bounds center
!
remoteChildren
	^content isNil ifTrue: [#()] ifFalse: [content remoteChildren]
! !
