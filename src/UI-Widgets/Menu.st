Object subclass: #Menu
	instanceVariableNames: 'title items'
	classVariableNames: ''
	package: 'UI-Widgets'!

Menu comment: 'I am a menu model: an optional title and a list of MenuItems (items, headers, separators). asMenuView answers a MenuView showing me; World current openMenu: aMenu at: aScreenPoint opens one, and widgets answer me from contextMenuAt:.

	(Menu title: ''World'')
		addHeader: ''open…'';
		add: ''Workspace'' action: [Workspace open];
		add: ''Profiler'' description: ''samples · frames'' action: [Profiler open];
		addSeparator;
		add: ''Save image'' key: ''⌘S'' action: [Smalltalk snapshot];
		yourself'!

!Menu methodsFor: 'initialization'!
initialize
	items := OrderedCollection new
! !

!Menu methodsFor: 'accessing'!
title
	^title
!
title: aString
	title := aString
!
items
	^items
!
selectableItems
	^items select: [:each | each isSelectable]
!
itemLabeled: aString
	^items detect: [:each | each isItem and: [each label = aString]] ifNone: [nil]
!
isEmpty
	^items isEmpty
!
allItems
	"My items and, after each submenu item, its submenu's, depth first."
	| all |
	all := OrderedCollection new.
	items do: [:each |
		all add: each.
		each submenu isNil ifFalse: [all addAll: each submenu allItems]].
	^all
! !

!Menu methodsFor: 'building'!
addItem: aMenuItem
	items add: aMenuItem.
	^aMenuItem
!
add: aString action: aBlock
	^self addItem: (MenuItem new label: aString; action: aBlock; yourself)
!
add: aString key: keyString action: aBlock
	^self addItem: (MenuItem new label: aString; keyText: keyString; action: aBlock; yourself)
!
add: aString description: descString action: aBlock
	^self addItem: (MenuItem new label: aString; description: descString; action: aBlock; yourself)
!
add: aString key: keyString description: descString action: aBlock
	^self addItem: (MenuItem new label: aString; keyText: keyString; description: descString; action: aBlock; yourself)
!
add: aString checked: aBooleanOrBlock action: aBlock
	^self addItem: (MenuItem new label: aString; checked: aBooleanOrBlock; action: aBlock; yourself)
!
add: aString submenu: aMenu
	^self addItem: (MenuItem new label: aString; submenu: aMenu; yourself)
!
addHeader: aString
	^self addItem: (MenuItem new kind: #header; label: aString; yourself)
!
addSeparator
	^self addItem: (MenuItem new kind: #separator; yourself)
! !

!Menu methodsFor: 'viewing'!
asMenuView
	^MenuView on: self
! !

!Menu class methodsFor: 'instance creation'!
title: aString
	^self new title: aString; yourself
! !
