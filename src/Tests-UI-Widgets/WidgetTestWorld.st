Object subclass: #WidgetTestWorld
	instanceVariableNames: 'clipboard menus toasts windows'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

WidgetTestWorld comment: 'I stand in for the World in widget tests: a clipboard, and the menus and toasts widgets opened.'!

!WidgetTestWorld methodsFor: 'world protocol'!
clipboard
	^clipboard ifNil: ['']
!
clipboard: aString
	clipboard := aString
!
openMenu: aMenu at: aPoint
	| view |
	view := (aMenu isKindOf: View) ifTrue: [aMenu] ifFalse: [aMenu asMenuView].
	self menus add: view -> aPoint.
	^view
!
closeMenu: aView
	self menus removeAllSuchThat: [:each | each key == aView]
!
toast: aString
	self toasts add: aString
! !

!WidgetTestWorld methodsFor: 'remote control'!
remoteRole
	^#screen
!
remoteLabel
	^'test'
!
remoteState
	^#()
!
remoteChildren
	^self windows asArray , (self menus collect: [:each | each key]) asArray
! !

!WidgetTestWorld methodsFor: 'accessing'!
windows
	^windows ifNil: [windows := OrderedCollection new]
!
menus
	^menus ifNil: [menus := OrderedCollection new]
!
toasts
	^toasts ifNil: [toasts := OrderedCollection new]
!
lastMenu
	^self menus isEmpty ifTrue: [nil] ifFalse: [self menus last key]
! !
