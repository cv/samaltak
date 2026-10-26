Widget subclass: #FileColumns
	instanceVariableNames: 'lists preview offset contentWidth laidOutWidth scrollBar'
	classVariableNames: ''
	package: 'Tools'!

FileColumns comment: 'I lay out the File Browser''s columns side by side, a FileColumn per folder (columnWidth wide, a 1-point rule after each) and the preview at the end (the rest of my width, at least minPreviewWidth), and scroll them sideways when they do not fit: a scroll bar below, the horizontal wheel; scrolled to the end, I stay there when they or my width change. Transparent in snapshots: the columns are the window''s (@wN.column-2).'!

!FileColumns methodsFor: 'initialization'!
initialize
	super initialize.
	lists := OrderedCollection new.
	offset := 0.
	contentWidth := 0.
	laidOutWidth := 0.
	scrollBar := ScrollBar new client: self; beHorizontal; yourself.
	scrollBar setVisible: false.
	self addChild: scrollBar
! !

!FileColumns methodsFor: 'accessing'!
lists
	^lists
!
preview
	^preview
!
columnWidth
	^260
!
minPreviewWidth
	^460
!
addList: aFileColumn
	lists add: aFileColumn.
	self addChild: aFileColumn
!
removeListsAfter: index
	[lists size > index] whileTrue: [self removeChild: lists removeLast]
!
preview: aWidgetOrNil
	preview == aWidgetOrNil ifTrue: [^self].
	preview isNil ifFalse: [self removeChild: preview].
	preview := aWidgetOrNil.
	preview isNil ifFalse: [self addChild: preview]
! !

!FileColumns methodsFor: 'scrolling'!
scrollTotal
	^contentWidth
!
scrollVisible
	^self width
!
scrollOffset
	^offset
!
scrollOffset: points
	| new |
	new := (points min: contentWidth - self width) max: 0.
	new = offset ifTrue: [^self].
	offset := new.
	self layout
!
scrollToShow: aWidget
	"Scroll so that aWidget, one of mine, is in view."
	| left |
	left := aWidget bounds left + offset.
	left + aWidget width > (offset + self width) ifTrue: [^self scrollOffset: left + aWidget width - self width].
	left < offset ifTrue: [self scrollOffset: left]
!
scrollToShowEnd
	self scrollOffset: contentWidth - self width
! !

!FileColumns methodsFor: 'layout'!
layout
	| atEnd w previewWidth h x |
	atEnd := offset >= (contentWidth - laidOutWidth).
	w := self columnWidth.
	previewWidth := preview isNil ifTrue: [0] ifFalse: [self width - (lists size * (w + 1)) max: self minPreviewWidth].
	contentWidth := lists size * (w + 1) + previewWidth.
	scrollBar setVisible: contentWidth > self width.
	h := self height - (scrollBar isVisible ifTrue: [self theme metric: #scrollBarWidth] ifFalse: [0]).
	atEnd ifTrue: [offset := contentWidth].
	offset := (offset min: contentWidth - self width) max: 0.
	laidOutWidth := self width.
	x := offset negated.
	lists do: [:each |
		each bounds: (x @ 0 extent: w @ h).
		x := x + w + 1].
	preview isNil ifFalse: [preview bounds: (x @ 0 extent: previewWidth @ h)].
	scrollBar bounds: (0 @ h corner: self width @ self height).
	scrollBar invalidate.
	self ownDrawingChanged.
	self requestRedraw
! !

!FileColumns methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| h x |
	aCanvas fillRect: self localBounds color: self theme paper.
	h := scrollBar isVisible ifTrue: [self height - (self theme metric: #scrollBarWidth)] ifFalse: [self height].
	x := offset negated.
	lists do: [:each |
		x := x + self columnWidth.
		aCanvas fillRect: (x @ 0 extent: 1 @ h) color: self theme rule.
		x := x + 1]
! !

!FileColumns methodsFor: 'events'!
wheel: anEvent
	anEvent delta x = 0 ifTrue: [^false].
	self scrollOffset: offset - (anEvent delta x * 40).
	^true
! !

!FileColumns methodsFor: 'remote control'!
remoteIsTransparent
	^true
! !
