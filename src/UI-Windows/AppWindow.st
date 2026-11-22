Window subclass: #AppWindow
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

AppWindow comment: 'I am the window of an application in its AppWorld: my content fills the host window, which the host''s window manager decorates, so I draw no chrome and have no title bar, boxes or resize zones; my bounds follow the host window. Everything else (my Process, retained drawing, events, animations, do: and sync:) is a Window''s.'!

!AppWindow methodsFor: 'geometry'!
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

!AppWindow methodsFor: 'chrome'!
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

!AppWindow methodsFor: 'remote control'!
remoteClickPoint
	^bounds center
!
remoteChildren
	content isNil ifTrue: [^#()].
	^View remoteFlatten: (Array with: content)
! !
