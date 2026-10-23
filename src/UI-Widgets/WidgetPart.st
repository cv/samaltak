Object subclass: #WidgetPart
	instanceVariableNames: 'widget role label state name rect rectBlock children text'
	classVariableNames: ''
	package: 'UI-Widgets'!

WidgetPart comment: 'I stand for a part of a widget in the remote-control tree (a list row, a segment, a menu item, an editor mark): role, label, state words, optional name, and my rectangle in the widget''s local coordinates (nil when not visible), from which I answer remoteBounds and remoteClickPoint in screen points. Widgets make me fresh for every snapshot.'!

!WidgetPart methodsFor: 'accessing'!
widget
	^widget
!
widget: aWidget
	widget := aWidget
!
role: aSymbol
	role := aSymbol
!
label: aString
	label := aString
!
state: anArray
	state := anArray
!
name: aString
	name := aString
!
rect
	^rect
!
rect: aRectangleOrNil
	rect := aRectangleOrNil
!
rectBlock: aBlock
	"aBlock value: reveal answers my rectangle (local to the widget) or nil; with reveal true the widget may scroll me into view first."
	rectBlock := aBlock
!
rectRevealing: aBoolean
	rect isNil ifFalse: [^rect].
	rectBlock isNil ifTrue: [^nil].
	^rectBlock value: aBoolean
!
children: aCollection
	children := aCollection
!
text: aString
	text := aString
! !

!WidgetPart methodsFor: 'remote control'!
remoteRole
	^role
!
remoteLabel
	^label
!
remoteState
	^state ifNil: [#()]
!
remoteName
	^name
!
remoteChildren
	^children ifNil: [#()]
!
remoteBounds
	| r |
	r := self rectRevealing: false.
	r isNil ifTrue: [^nil].
	^(widget localToScreen: r origin) extent: r extent
!
remoteClickPoint
	| r |
	r := self rectRevealing: true.
	r isNil ifTrue: [^nil].
	^widget localToScreen: r center
!
remoteText
	^text
! !

!WidgetPart methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a WidgetPart('; print: role; space; print: label; nextPut: $)
! !

!WidgetPart class methodsFor: 'instance creation'!
of: aWidget role: aSymbol label: aString
	^self new widget: aWidget; role: aSymbol; label: aString; yourself
!
of: aWidget role: aSymbol label: aString state: anArray rect: aRectangle
	^(self of: aWidget role: aSymbol label: aString) state: anArray; rect: aRectangle; yourself
! !
