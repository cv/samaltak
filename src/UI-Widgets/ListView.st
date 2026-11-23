Widget subclass: #ListView
	instanceVariableNames: 'items labelBlock rightBlock cellBlock cellWidth headerBlock styleBlock remoteNameBlock remoteStateBlock title selection offset scrollBar onSelect onDoubleClick itemMenuBlock barTop barAnimation typeAhead typeAheadTime rowTops font rightFont emptyText menuKeepsSelection'
	classVariableNames: ''
	package: 'UI-Widgets'!

ListView comment: 'I am a scrolling list of items (any objects) in the Blue Book style: 19-point rows with an optional leading cell (icon, layer chip, breakpoint dot), the label, and right-aligned muted text; group header rows in tracked capitals. The selection is inverted (white on black) while I have keyboard focus and a 1-point box otherwise; when it changes the bar glides to the new row (~100 ms, ease-out).

	list := ListView new
		title: ''Packages'';
		items: packages;
		labelBlock: [:p | p name];
		rightBlock: [:p | p layerName];
		cellBlock: (ListView layerChipCell: [:p | p layer]);
		onSelect: [:p | self packageSelected: p];
		onDoubleClick: [:p | p browse];
		itemMenuBlock: [:p | aMenu].

Blocks: labelBlock (default asString), rightBlock (muted right text or nil), cellBlock: [:canvas :rect :item :inverted | ...] drawn in a cellWidth-wide cell, headerBlock (true for group header rows, which cannot be selected), styleBlock (a Symbol or Array of #bold #italic #muted #code #modified for the label), remoteNameBlock (ref slug; default: the label), remoteStateBlock (extra state words of a row).

Keys (when focused): up/down, home/end, page up/down, return (= double click), type-ahead on the labels. Wheel and scroll bar scroll; selection changes scroll the selection into view. selectIndex: selects as the user does (notifies onSelect:); selectionIndex: and selection: do not notify.'!

!ListView methodsFor: 'initialization'!
initialize
	super initialize.
	items := #().
	selection := 0.
	offset := 0.
	cellWidth := 14.
	typeAhead := ''.
	typeAheadTime := 0.
	scrollBar := ScrollBar new client: self; yourself.
	scrollBar setVisible: false.
	self addChild: scrollBar
! !

!ListView methodsFor: 'accessing'!
title
	^title
!
title: aString
	title := aString
!
items
	^items
!
items: aCollection
	"Show aCollection, keeping the selected item selected if it is still there (silently)."
	| old |
	old := self selection.
	items := aCollection asArray.
	rowTops := nil.
	selection := old isNil ifTrue: [0] ifFalse: [(items indexOf: old) ifNil: [0]].
	barAnimation isNil ifFalse: [barAnimation stop. barAnimation := nil].
	barTop := nil.
	self clampOffset.
	self layout.
	self invalidate
!
items: aCollection selected: anItem
	items := aCollection asArray.
	rowTops := nil.
	selection := 0.
	self selection: anItem.
	self clampOffset.
	self layout.
	self invalidate
!
replaceItems: aCollection
	"Show aCollection instead of my items, one for one: it draws the same rows (the same labels, the same row selected), so nothing is drawn again."
	items := aCollection asArray
!
size
	^items size
!
labelBlock: aBlock
	labelBlock := aBlock.
	self invalidate
!
rightBlock: aBlock
	rightBlock := aBlock.
	self invalidate
!
cellBlock: aBlock
	"aBlock value: aCanvas value: cellRect value: item value: inverted draws the leading cell."
	cellBlock := aBlock.
	self invalidate
!
cellWidth: points
	cellWidth := points
!
headerBlock: aBlock
	headerBlock := aBlock.
	rowTops := nil.
	self invalidate
!
styleBlock: aBlock
	styleBlock := aBlock.
	self invalidate
!
remoteNameBlock: aBlock
	remoteNameBlock := aBlock
!
remoteStateBlock: aBlock
	remoteStateBlock := aBlock
!
onSelect: aBlock
	"aBlock receives the newly selected item (nil when the selection is cleared) when the user changes the selection."
	onSelect := aBlock
!
onDoubleClick: aBlock
	onDoubleClick := aBlock
!
itemMenuBlock: aBlock
	"aBlock (receiving the item under the pointer, after selecting it, and me) answers a Menu or nil."
	itemMenuBlock := aBlock
!
font
	^self fontFor: (font ifNil: [#ui])
!
font: aFontOrSymbol
	font := aFontOrSymbol.
	self invalidate
!
rightFont
	^self fontFor: (rightFont ifNil: [#smallItalic])
!
rightFont: aFontOrSymbol
	rightFont := aFontOrSymbol.
	self invalidate
!
emptyText: aString
	"Muted italic text shown when there are no items."
	emptyText := aString
!
labelOf: anItem
	labelBlock isNil ifTrue: [^anItem isString ifTrue: [anItem] ifFalse: [anItem printString]].
	^(labelBlock value: anItem) ifNil: [''] ifNotNil: [:s | s asString]
!
rightTextOf: anItem
	rightBlock isNil ifTrue: [^nil].
	^(rightBlock value: anItem) ifNotNil: [:s | s asString]
!
isHeader: index
	^headerBlock notNil and: [(headerBlock value: (items at: index)) == true]
!
stylesOf: anItem
	| s |
	styleBlock isNil ifTrue: [^#()].
	s := styleBlock value: anItem.
	s isNil ifTrue: [^#()].
	s isSymbol ifTrue: [^Array with: s].
	^s
! !

!ListView methodsFor: 'selection'!
selectionIndex
	^selection
!
selection
	^selection = 0 ifTrue: [nil] ifFalse: [items at: selection]
!
selectionIndex: index
	"Select the row index (0 for none) without notifying; the bar glides from the old row."
	| new old oldTop |
	new := (index between: 1 and: items size) ifTrue: [index] ifFalse: [0].
	(new > 0 and: [self isHeader: new]) ifTrue: [new := 0].
	new = selection ifTrue: [^self].
	old := selection.
	oldTop := self barTop.
	selection := new.
	(old > 0 and: [new > 0]) ifTrue: [self glideFrom: oldTop to: (self rowTop: new)] ifFalse: [barTop := nil].
	new > 0 ifTrue: [self scrollToShowIndex: new].
	self invalidate
!
selection: anItem
	self selectionIndex: (anItem isNil ifTrue: [0] ifFalse: [items indexOf: anItem])
!
selectIndex: index
	"Select as the user does: notify onSelect: if the selection changed."
	| old |
	old := selection.
	self selectionIndex: index.
	(selection ~= old and: [onSelect notNil]) ifTrue: [onSelect cull: self selection cull: self]
!
select: anItem
	self selectIndex: (items indexOf: anItem)
!
glideFrom: startTop to: endTop
	barAnimation isNil ifFalse: [barAnimation stop].
	barTop := startTop.
	barAnimation := self tweenFrom: startTop to: endTop duration: (self theme metric: #glideMs) do: [:y |
		barTop := y.
		y = endTop ifTrue: [barTop := nil. barAnimation := nil].
		self invalidate]
!
barTop
	"The selection bar's top in content coordinates (animated while gliding)."
	selection = 0 ifTrue: [^nil].
	^barTop ifNil: [self rowTop: selection]
!
selectableIndexFrom: start by: step
	| i |
	i := start.
	[i between: 1 and: items size] whileTrue: [
		(self isHeader: i) ifFalse: [^i].
		i := i + step].
	^0
! !

!ListView methodsFor: 'geometry'!
paddingY
	^self theme metric: #listPaddingY
!
paddingX
	^self theme metric: #listPaddingX
!
rowHeight
	^self theme metric: #rowHeight
!
heightOfRow: index
	^(self isHeader: index) ifTrue: [self theme metric: #groupRowHeight] ifFalse: [self rowHeight]
!
rowTops
	"Content y of every row top, plus the content height at the end."
	| tops y |
	rowTops isNil ifFalse: [^rowTops].
	tops := Array new: items size + 1.
	y := self paddingY.
	1 to: items size do: [:i |
		tops at: i put: y.
		y := y + (headerBlock isNil ifTrue: [self rowHeight] ifFalse: [self heightOfRow: i])].
	tops at: items size + 1 put: y + self paddingY.
	^rowTops := tops
!
rowTop: index
	^self rowTops at: index
!
rowBottom: index
	^(self rowTops at: index) + (self heightOfRow: index)
!
contentHeight
	^self rowTops last
!
contentTop
	"Where the rows start in my coordinates (subclasses with a header strip move it down)."
	^0
!
viewportHeight
	^self height - self contentTop
!
rowsWidth
	^scrollBar isVisible ifTrue: [self width - (self theme metric: #scrollBarWidth)] ifFalse: [self width]
!
rowIndexAtContentY: y
	"Binary search; answer 0 if y is outside the rows."
	| tops lo hi mid |
	tops := self rowTops.
	items isEmpty ifTrue: [^0].
	(y < (tops at: 1) or: [y >= ((tops at: items size) + (self heightOfRow: items size))]) ifTrue: [^0].
	lo := 1.
	hi := items size.
	[lo < hi] whileTrue: [
		mid := lo + hi + 1 // 2.
		(tops at: mid) <= y ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
	^lo
!
rowIndexAt: aPoint
	"The row under a local point, or 0."
	aPoint y < self contentTop ifTrue: [^0].
	^self rowIndexAtContentY: aPoint y - self contentTop + offset
!
rowRect: index
	"The row's rectangle in my coordinates."
	| top |
	top := (self rowTop: index) - offset + self contentTop.
	^0 @ top extent: self rowsWidth @ (self heightOfRow: index)
!
isRowVisible: index
	| r |
	r := self rowRect: index.
	^r top >= self contentTop and: [r bottom <= self height]
! !

!ListView methodsFor: 'scrolling'!
scrollTotal
	^self contentHeight
!
scrollVisible
	^self viewportHeight
!
scrollOffset
	^offset
!
scrollOffset: points
	| new |
	new := (points min: self contentHeight - self viewportHeight) max: 0.
	new = offset ifTrue: [^self].
	offset := new.
	self invalidate
!
clampOffset
	offset := (offset min: self contentHeight - self viewportHeight) max: 0
!
scrollToShowIndex: index
	| top bottom |
	(index between: 1 and: items size) ifFalse: [^self].
	top := self rowTop: index.
	bottom := self rowBottom: index.
	top < offset ifTrue: [^self scrollOffset: top - self paddingY].
	bottom > (offset + self viewportHeight) ifTrue: [self scrollOffset: bottom - self viewportHeight + self paddingY]
!
visibleRowCount
	^(self viewportHeight / self rowHeight) floor max: 1
! !

!ListView methodsFor: 'layout'!
layout
	| bar |
	bar := self theme metric: #scrollBarWidth.
	self clampOffset.
	scrollBar setVisible: self contentHeight > self viewportHeight.
	scrollBar bounds: ((self width - bar) @ self contentTop corner: self width @ self height)
! !

!ListView methodsFor: 'drawing'!
showsFocusedSelection
	^self isFocused
!
drawSelfOn: aCanvas
	| first last clip top bar rowsRect |
	aCanvas fillRect: self localBounds color: self theme paper.
	self drawHeaderStripOn: aCanvas.
	rowsRect := 0 @ self contentTop corner: self rowsWidth @ self height.
	items isEmpty ifTrue: [
		emptyText isNil ifFalse: [
			aCanvas drawString: emptyText at: self paddingX @ (self contentTop + 4) font: (self theme font: #smallItalic) color: self theme muted].
		^self].
	clip := aCanvas clipRect intersect: rowsRect.
	first := (self rowIndexAtContentY: clip top - self contentTop + offset) max: 1.
	last := self rowIndexAtContentY: clip bottom - self contentTop + offset - 0.01.
	last = 0 ifTrue: [last := items size].
	aCanvas clip: rowsRect during: [
		first to: last do: [:i | self drawRow: i on: aCanvas inverted: false].
		top := self barTop.
		top isNil ifFalse: [
			bar := 0 @ (top - offset + self contentTop) extent: self rowsWidth @ (self heightOfRow: selection).
			self showsFocusedSelection
				ifTrue: [
					aCanvas fillRect: bar color: self theme ink.
					aCanvas clip: bar during: [
						((self rowIndexAtContentY: bar top - self contentTop + offset) max: 1)
							to: ((self rowIndexAtContentY: bar bottom - self contentTop + offset - 0.01) max: 1)
							do: [:i | (self isHeader: i) ifFalse: [self drawRow: i on: aCanvas inverted: true]]]]
				ifFalse: [aCanvas strokeRect: bar color: self theme ink width: 1]]]
!
drawHeaderStripOn: aCanvas
	"Subclasses with column headers draw them above contentTop."
!
drawRow: index on: aCanvas inverted: inverted
	| item r |
	item := items at: index.
	r := self rowRect: index.
	(self isHeader: index) ifTrue: [^self drawHeaderRow: item in: r first: index = 1 on: aCanvas].
	self drawItem: item in: r on: aCanvas inverted: inverted
!
drawHeaderRow: anItem in: r first: isFirst on: aCanvas
	isFirst ifFalse: [aCanvas fillRect: (r left @ r top corner: r right @ (r top + 1)) color: (self theme color: #hair)].
	aCanvas drawString: (self labelOf: anItem) in: ((r left + self paddingX) @ r top corner: r corner)
		font: (self theme font: #header) color: self theme ink align: #left
!
drawItem: anItem in: r on: aCanvas inverted: inverted
	| x right rightText rw labelFont styles color label |
	x := r left + self paddingX.
	cellBlock isNil ifFalse: [
		cellBlock value: aCanvas value: (x @ r top extent: cellWidth @ r height) value: anItem value: inverted.
		x := x + cellWidth + 6].
	right := r right - self paddingX.
	rightText := self rightTextOf: anItem.
	(rightText isNil or: [rightText isEmpty]) ifFalse: [
		rw := self rightFont widthOf: rightText.
		aCanvas drawString: rightText in: ((right - rw) @ r top corner: right @ r bottom)
			font: self rightFont color: (inverted ifTrue: [self theme color: #inverseMuted] ifFalse: [self theme muted]) align: #left.
		right := right - rw - 8].
	styles := self stylesOf: anItem.
	labelFont := self labelFontFor: styles.
	color := inverted
		ifTrue: [self theme paper]
		ifFalse: [(styles includes: #muted) ifTrue: [self theme muted] ifFalse: [self theme ink]].
	label := self labelOf: anItem.
	aCanvas clip: (r left @ r top corner: right @ r bottom) during: [
		aCanvas drawString: label in: (x @ r top corner: right @ r bottom) font: labelFont color: color align: #left.
		(styles includes: #modified) ifTrue: [
			aCanvas drawString: ' *' at: (x + (labelFont widthOf: label)) @ (r top + (r height - labelFont lineHeight / 2))
				font: labelFont color: (inverted ifTrue: [self theme paper] ifFalse: [self theme ultramarine])]]
!
labelFontFor: styles
	styles isEmpty ifTrue: [^self font].
	(styles includes: #code) ifTrue: [^self theme font: ((styles includes: #bold) ifTrue: [#codeSmallBold] ifFalse: [#codeSmall])].
	(styles includes: #bold) ifTrue: [^self theme font: #uiBold].
	(styles includes: #italic) ifTrue: [^self theme font: #uiItalic].
	^self font
! !

!ListView methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
mouseDown: anEvent
	| i |
	anEvent button = 1 ifFalse: [^false].
	i := self rowIndexAt: (self localEventPosition: anEvent).
	(i = 0 or: [self isHeader: i]) ifTrue: [^true].
	self selectIndex: i.
	(anEvent clickCount >= 2 and: [onDoubleClick notNil]) ifTrue: [onDoubleClick cull: (items at: i) cull: self].
	^true
!
mouseUp: anEvent
	^true
!
clickItemAt: aPoint
	^self rowIndexAt: aPoint
!
wheel: anEvent
	self scrollOffset: offset - (anEvent delta y * 40).
	^true
!
contextMenuAt: aPoint
	"The item menu of the row at aPoint; that row becomes the selection unless menuKeepsSelection: true."
	| i |
	itemMenuBlock isNil ifTrue: [^super contextMenuAt: aPoint].
	i := self rowIndexAt: aPoint.
	(i > 0 and: [(self isHeader: i) not]) ifFalse: [^itemMenuBlock cull: self selection cull: self].
	menuKeepsSelection == true ifTrue: [^itemMenuBlock cull: (items at: i) cull: self].
	self selectIndex: i.
	^itemMenuBlock cull: self selection cull: self
!
menuKeepsSelection: aBoolean
	menuKeepsSelection := aBoolean
!
keyDown: anEvent
	| key cmd |
	key := anEvent key.
	cmd := anEvent modifiers commandKey.
	key == #down ifTrue: [^self moveSelection: (cmd ifTrue: [items size] ifFalse: [1])].
	key == #up ifTrue: [^self moveSelection: (cmd ifTrue: [items size negated] ifFalse: [-1])].
	key == #home ifTrue: [self selectIndex: (self selectableIndexFrom: 1 by: 1). ^true].
	key == #end ifTrue: [self selectIndex: (self selectableIndexFrom: items size by: -1). ^true].
	key == #pageDown ifTrue: [^self moveSelection: self visibleRowCount].
	key == #pageUp ifTrue: [^self moveSelection: self visibleRowCount negated].
	(key == #return or: [key == #enter]) ifTrue: [
		(selection > 0 and: [onDoubleClick notNil]) ifTrue: [onDoubleClick cull: self selection cull: self. ^true].
		^false].
	^false
!
moveSelection: delta
	| target i |
	items isEmpty ifTrue: [^true].
	selection = 0
		ifTrue: [target := delta > 0 ifTrue: [self selectableIndexFrom: 1 by: 1] ifFalse: [self selectableIndexFrom: items size by: -1]]
		ifFalse: [
			i := ((selection + delta) max: 1) min: items size.
			target := self selectableIndexFrom: i by: (delta > 0 ifTrue: [1] ifFalse: [-1]).
			target = 0 ifTrue: [target := self selectableIndexFrom: i by: (delta > 0 ifTrue: [-1] ifFalse: [1])]].
	target = 0 ifFalse: [self selectIndex: target].
	^true
!
textInput: anEvent
	| now prefix start i |
	anEvent string isEmpty ifTrue: [^false].
	(anEvent string allSatisfy: [:c | c isWhiteSpace]) ifTrue: [^false].
	now := Time millisecondClock.
	now - typeAheadTime > 1000 ifTrue: [typeAhead := ''].
	typeAheadTime := now.
	typeAhead := typeAhead , anEvent string asLowercase.
	prefix := typeAhead.
	start := selection max: 1.
	0 to: items size - 1 do: [:k |
		i := start + k - 1 \\ items size + 1.
		((self isHeader: i) not and: [(self labelOf: (items at: i)) asLowercase beginsWith: prefix])
			ifTrue: [self selectIndex: i. ^true]].
	^true
!
resetTypeAhead
	typeAhead := ''.
	typeAheadTime := 0
! !

!ListView methodsFor: 'remote control'!
remoteRole
	^#list
!
remoteLabel
	^title
!
remoteState
	| s |
	s := OrderedCollection new.
	selection > 0 ifTrue: [s add: 'sel=', (self remoteQuote: (self labelOf: self selection))].
	s add: 'n=', (items reject: [:each | headerBlock notNil and: [(headerBlock value: each) == true]]) size printString.
	self isFocused ifTrue: [s add: #focused].
	self isEnabled ifFalse: [s add: #disabled].
	^s asArray
!
remoteChildren
	^(1 to: items size) collect: [:i | self remotePartFor: i]
!
remoteRowRole
	^#item
!
remotePartFor: index
	| item part state |
	item := items at: index.
	part := WidgetPart of: self
		role: ((self isHeader: index) ifTrue: [#head] ifFalse: [self remoteRowRole])
		label: (self labelOf: item).
	state := OrderedCollection new.
	remoteStateBlock isNil ifFalse: [state addAll: ((remoteStateBlock value: item) ifNil: [#()])].
	index = selection ifTrue: [state add: #selected].
	part state: state asArray.
	remoteNameBlock isNil ifFalse: [part name: (remoteNameBlock value: item) asString].
	part rectBlock: [:reveal | self remoteRectOf: index reveal: reveal].
	^part
!
remoteRectOf: index reveal: aBoolean
	"The row's rectangle if visible; with aBoolean, scroll it into view (in my window's process) first."
	(index between: 1 and: items size) ifFalse: [^nil].
	(self isRowVisible: index) ifTrue: [^self rowRect: index].
	aBoolean ifFalse: [^nil].
	self inWindowWait: [self scrollToShowIndex: index].
	^(self isRowVisible: index) ifTrue: [self rowRect: index] ifFalse: [nil]
! !

!ListView class methodsFor: 'cell renderers'!
layerChipCell: aBlock
	"A cellBlock drawing a 14-point layer chip (the number on its layer color) for the layer aBlock answers (nil: none)."
	^[:canvas :rect :item :inverted |
		| n theme r |
		n := aBlock value: item.
		n isNil ifFalse: [
			theme := Theme current.
			r := rect left @ (rect top + (rect height - 14 / 2)) extent: 14 @ 14.
			canvas fillRect: r color: (theme layerColor: n).
			(n >= 5 or: [inverted]) ifTrue: [canvas strokeRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme ink]) width: 1].
			canvas drawString: n printString in: r font: (theme font: #chip)
				color: (n >= 4 ifTrue: [theme ink] ifFalse: [theme paper]) align: #center]]
!
dotCell: aBlock
	"A cellBlock drawing a 9-point breakpoint dot: aBlock answers #on (filled ultramarine), #off (grey ring), or nil (nothing)."
	^[:canvas :rect :item :inverted |
		| kind theme r |
		kind := aBlock value: item.
		kind isNil ifFalse: [
			theme := Theme current.
			r := rect left + 2 @ (rect top + (rect height - 9 / 2)) extent: 9 @ 9.
			kind == #on
				ifTrue: [canvas fillRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme ultramarine])]
				ifFalse: [canvas strokeRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme color: #ink4]) width: 1]]]
! !
