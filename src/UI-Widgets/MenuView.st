Widget subclass: #MenuView
	instanceVariableNames: 'menu highlight onClose closed submenuView armed parentView'
	classVariableNames: ''
	package: 'UI-Widgets'!

MenuView comment: 'I show a Menu as a Blue Book popup: a 1-point black frame (the hard shadow is the overlay''s), an optional striped title bar, tracked-capitals headers, 21-point items with an italic description and a right-aligned key equivalent, dotted separators, check marks. The item under the pointer or chosen with the arrow keys is inverted.

Keys: up/down (skipping headers, separators and disabled items), home/end, return/enter/space to choose, right to open a submenu, escape/left to close, letters jump to the next item starting with them. Choosing an item closes me and the menus I am a submenu of (through the World) and runs its action in the Process of the window the first of them was opened from (the overlay''s invoker), or in a new Process when there is none.

The World hosts me (World current openMenu: aMenu at: aPoint calls aMenu asMenuView); my preferredExtent is my size.'!

!MenuView methodsFor: 'accessing'!
menu
	^menu
!
setMenu: aMenu
	menu := aMenu.
	highlight := 0
!
items
	^menu items
!
highlightIndex
	^highlight
!
highlightIndex: anInteger
	highlight = anInteger ifTrue: [^self].
	highlight := anInteger.
	self invalidate
!
highlightedItem
	^highlight = 0 ifTrue: [nil] ifFalse: [self items at: highlight]
!
onClose: aBlock
	"aBlock runs when I close (chosen or dismissed)."
	onClose := aBlock
!
parentView: aMenuView
	"The menu I am a submenu of."
	parentView := aMenuView
!
isClosed
	^closed == true
! !

!MenuView methodsFor: 'geometry'!
titleHeight
	^menu title isNil ifTrue: [0] ifFalse: [self theme metric: #menuTitleHeight]
!
heightOf: anItem
	anItem isSeparator ifTrue: [^7].
	anItem isHeader ifTrue: [^20].
	^self theme metric: #menuItemHeight
!
itemTops
	| y tops |
	y := 1 + self titleHeight + (menu title isNil ifTrue: [0] ifFalse: [3]).
	tops := Array new: self items size.
	self items doWithIndex: [:each :i |
		tops at: i put: y.
		y := y + (self heightOf: each)].
	^tops
!
itemRect: index
	| top |
	top := self itemTops at: index.
	^1 @ top extent: (self width - 2) @ (self heightOf: (self items at: index))
!
itemIndexAt: aPoint
	| tops |
	(aPoint x >= 0 and: [aPoint x < self width]) ifFalse: [^0].
	tops := self itemTops.
	1 to: self items size do: [:i |
		(aPoint y >= (tops at: i) and: [aPoint y < ((tops at: i) + (self heightOf: (self items at: i)))]) ifTrue: [^i]].
	^0
!
checkGutter
	^(self items anySatisfy: [:each | each hasCheck]) ifTrue: [16] ifFalse: [0]
!
preferredExtent
	| w pad h ui key desc |
	pad := self theme metric: #menuPaddingX.
	ui := self theme font: #ui.
	key := self theme font: #menuKey.
	desc := self theme font: #smallItalic.
	w := self theme metric: #menuMinWidth.
	menu title isNil ifFalse: [w := w max: ((self theme font: #title) widthOf: menu title) + 60].
	self items do: [:each |
		| iw |
		each isItem ifTrue: [
			iw := (2 * pad) + self checkGutter + (ui widthOf: each label).
			each description isNil ifFalse: [iw := iw + 10 + (desc widthOf: each description)].
			each keyText isNil ifFalse: [iw := iw + 18 + (key widthOf: each keyText)].
			each submenu isNil ifFalse: [iw := iw + 18].
			w := w max: iw].
		each isHeader ifTrue: [w := w max: (2 * pad) + ((self theme font: #header) widthOf: each label)]].
	h := 1 + self titleHeight + (menu title isNil ifTrue: [0] ifFalse: [3]).
	self items do: [:each | h := h + (self heightOf: each)].
	^w ceiling @ (h + 3 + 1)
! !

!MenuView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| ink tops |
	ink := self theme ink.
	aCanvas fillRect: self localBounds color: self theme paper.
	aCanvas strokeRect: self localBounds color: ink width: 1.
	menu title isNil ifFalse: [self drawTitleOn: aCanvas].
	tops := self itemTops.
	self items doWithIndex: [:each :i |
		self drawItem: each at: i in: (1 @ (tops at: i) extent: (self width - 2) @ (self heightOf: each)) on: aCanvas]
!
drawTitleOn: aCanvas
	| h font tw x0 x1 |
	h := self titleHeight.
	font := self theme font: #title.
	tw := font widthOf: menu title.
	x0 := (self width - tw / 2) floor.
	x1 := x0 + tw.
	aCanvas pattern: #stripes in: (6 @ 5 corner: (x0 - 6) @ 16).
	aCanvas pattern: #stripes in: ((x1 + 6) @ 5 corner: (self width - 6) @ 16).
	aCanvas drawString: menu title in: (0 @ 1 corner: self width @ h) font: font color: self theme ink align: #center.
	aCanvas fillRect: (0 @ h corner: self width @ (h + 1)) color: self theme rule
!
drawItem: anItem at: index in: r on: aCanvas
	| pad x right on fg muted font |
	pad := self theme metric: #menuPaddingX.
	anItem isSeparator ifTrue: [
		| y |
		y := r top + 3.
		r left to: r right - 1 by: 2 do: [:dx | aCanvas fillRect: (dx @ y extent: 1 @ 1) color: self theme ink].
		^self].
	anItem isHeader ifTrue: [
		^aCanvas drawString: anItem label at: (r left + pad) @ (r top + 5) font: (self theme font: #header) color: self theme muted].
	on := index = highlight and: [anItem isEnabled].
	on ifTrue: [aCanvas fillRect: r color: self theme ink].
	fg := anItem isEnabled
		ifTrue: [on ifTrue: [self theme paper] ifFalse: [self theme ink]]
		ifFalse: [self theme color: #ink4].
	muted := on ifTrue: [self theme color: #inverseKey] ifFalse: [anItem isEnabled ifTrue: [self theme muted] ifFalse: [self theme color: #ink4]].
	x := r left + pad.
	anItem isChecked ifTrue: [
		aCanvas drawString: (String with: (Character value: 16r2713)) in: (x @ r top corner: (x + 14) @ r bottom) font: (self theme font: #ui) color: fg align: #left].
	x := x + self checkGutter.
	font := self theme font: #ui.
	aCanvas drawString: anItem label in: (x @ r top corner: r right @ r bottom) font: font color: fg align: #left.
	x := x + (font widthOf: anItem label) + 10.
	anItem description isNil ifFalse: [
		aCanvas drawString: anItem description in: (x @ r top corner: r right @ r bottom) font: (self theme font: #smallItalic) color: muted align: #left].
	right := r right - pad.
	anItem submenu isNil ifFalse: [
		aCanvas drawString: (String with: (Character value: 16r25B8)) in: (r left @ r top corner: right @ r bottom) font: font color: fg align: #right.
		right := right - 14].
	anItem keyText isNil ifFalse: [
		aCanvas drawString: anItem keyText in: (r left @ r top corner: right @ r bottom) font: (self theme font: #menuKey) color: muted align: #right]
! !

!MenuView methodsFor: 'choosing'!
choose: index
	"Close and run the item's action (or open its submenu)."
	| item |
	(index between: 1 and: self items size) ifFalse: [^self].
	item := self items at: index.
	item isSelectable ifFalse: [^self].
	item submenu isNil ifFalse: [^self openSubmenuAt: index].
	self close: item
!
close: anItem
	"Close and run anItem's action: in the invoking window's Process when I am hosted in an overlay (closing the overlay ends its Process), else right after closing."
	| w invoker |
	parentView isNil ifFalse: [
		"My parent does this without me (onClose makes it forget me): closing my overlay ends my Process, so I close last."
		onClose value.
		parentView close: anItem.
		^self close].
	w := self window.
	invoker := (w notNil and: [w respondsTo: #invoker]) ifTrue: [w invoker] ifFalse: [nil].
	invoker notNil ifTrue: [
		invoker do: [anItem run].
		^self close].
	(w notNil and: [w respondsTo: #invoker]) ifTrue: [
		[anItem run] fork.
		^self close].
	self close.
	anItem run
!
chooseLabeled: aString
	| item |
	item := menu itemLabeled: aString.
	item isNil ifFalse: [self choose: (self items indexOf: item)]
!
openSubmenuAt: index
	| r |
	submenuView isNil ifFalse: [submenuView close].
	r := self itemRect: index.
	submenuView := (self items at: index) submenu asMenuView.
	submenuView onClose: [submenuView := nil]; parentView: self.
	self worldDo: [:world | world openMenu: submenuView at: (self localToScreen: r topRight)].
	^submenuView
!
close
	closed == true ifTrue: [^self].
	closed := true.
	submenuView isNil ifFalse: [submenuView close].
	onClose isNil ifFalse: [onClose value].
	self worldDo: [:world | world closeMenu: self]
!
moveHighlight: delta
	| n i |
	n := self items size.
	n = 0 ifTrue: [^self].
	i := highlight.
	n timesRepeat: [
		i := i + delta.
		i < 1 ifTrue: [i := n].
		i > n ifTrue: [i := 1].
		(self items at: i) isSelectable ifTrue: [^self highlightIndex: i]]
! !

!MenuView methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
mouseMove: anEvent
	| i |
	i := self itemIndexAt: (self localEventPosition: anEvent).
	(i > 0 and: [(self items at: i) isSelectable]) ifFalse: [i := 0].
	self highlightIndex: i.
	^true
!
mouseEnter: anEvent
	^self mouseMove: anEvent
!
mouseLeave: anEvent
	self highlightIndex: (submenuView ifNil: [0] ifNotNil: [:sub | self items findFirst: [:each | each submenu == sub menu]]).
	^true
!
mouseDown: anEvent
	armed := true.
	^true
!
mouseUp: anEvent
	"Only a click that started in me chooses (the release of the click that opened me does not)."
	| i |
	armed == true ifFalse: [^true].
	armed := false.
	i := self itemIndexAt: (self localEventPosition: anEvent).
	i > 0 ifTrue: [self choose: i].
	^true
!
keyDown: anEvent
	| key |
	key := anEvent key.
	key == #down ifTrue: [self moveHighlight: 1. ^true].
	key == #up ifTrue: [self moveHighlight: -1. ^true].
	key == #home ifTrue: [highlight := 0. self moveHighlight: 1. ^true].
	key == #end ifTrue: [highlight := self items size + 1. self moveHighlight: -1. ^true].
	(key == #return or: [key == #enter or: [key == #space]]) ifTrue: [highlight > 0 ifTrue: [self choose: highlight]. ^true].
	key == #right ifTrue: [
		(self highlightedItem notNil and: [self highlightedItem submenu notNil]) ifTrue: [self openSubmenuAt: highlight].
		^true].
	(key == #escape or: [key == #left]) ifTrue: [self close. ^true].
	^true
!
textInput: anEvent
	| c n start |
	anEvent string isEmpty ifTrue: [^true].
	c := anEvent string first asLowercase.
	n := self items size.
	start := highlight.
	1 to: n do: [:k |
		| i item |
		i := start + k - 1 \\ n + 1.
		item := self items at: i.
		(item isSelectable and: [item label notEmpty and: [item label first asLowercase = c]]) ifTrue: [
			self highlightIndex: i.
			^true]].
	^true
! !

!MenuView methodsFor: 'remote control'!
remoteRole
	^#menu
!
remoteLabel
	^menu title
!
remoteName
	^name ifNil: ['menu']
!
remoteChildren
	| parts |
	parts := OrderedCollection new.
	self items doWithIndex: [:each :i |
		each isSeparator ifFalse: [
			| part state |
			part := WidgetPart of: self role: (each isHeader ifTrue: [#head] ifFalse: [#item]) label: each label.
			state := OrderedCollection new.
			each isItem ifTrue: [
				each description isNil ifFalse: [state add: 'desc=', (self remoteQuote: each description)].
				each keyText isNil ifFalse: [state add: 'key=', (self remoteQuote: each keyText)].
				each isChecked ifTrue: [state add: #checked].
				each isEnabled ifFalse: [state add: #disabled].
				i = highlight ifTrue: [state add: #selected].
				part rect: (self itemRect: i)].
			part state: state asArray.
			each name isNil ifFalse: [part name: each name].
			parts add: part]].
	^parts asArray
! !

!MenuView class methodsFor: 'instance creation'!
on: aMenu
	^self new setMenu: aMenu; yourself
! !
