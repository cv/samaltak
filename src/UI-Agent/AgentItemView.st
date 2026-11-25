Widget subclass: #AgentItemView
	instanceVariableNames: 'item shown heights selectionAnchor selectionEnd selecting selectionWidth'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentItemView comment: 'I am the abstract view of one AgentItem in an AgentWindow''s transcript (AgentTranscript), as tall as heightFor: my width answers. AgentItemView for: anItem answers the view for its kind (nil: not shown, e.g. #reasoning): the seam for richer views. refresh redraws me when what I show of the item changed (an assistant message grows while it streams, a cell gets its result).

Geometry: a gutter of gutterWidth on the left (who speaks), the content up to margin from the right.'!

!AgentItemView methodsFor: 'accessing'!
item
	^item
!
item: anAgentItem
	item := anAgentItem.
	shown := self shownState
!
gutterWidth
	^62
!
margin
	^14
!
contentWidth
	^self width - self gutterWidth - self margin max: 40
!
agentContext
	^AgentContext new
		receiver: item object;
		label: item objectId;
		yourself
! !

!AgentItemView methodsFor: 'updating'!
shownState
	^Array with: item text with: item result with: item failed
!
refresh
	"Redraw me if my item changed since I last showed it."
	| state |
	state := self shownState.
	state = shown ifTrue: [^self].
	shown := state.
	heights := nil.
	self clearTextSelection.
	self invalidate
! !

!AgentItemView methodsFor: 'layout'!
heightFor: aWidth
	"My height when I am aWidth wide (cached)."
	(heights notNil and: [heights key = aWidth]) ifTrue: [^heights value].
	heights := aWidth -> (self computeHeightFor: aWidth).
	^heights value
!
computeHeightFor: aWidth
	^self subclassResponsibility
!
wrap: aString font: aFont width: aWidth
	"aString's lines broken at spaces to fit aWidth."
	| lines |
	lines := OrderedCollection new.
	(aString isEmpty ifTrue: [#('')] ifFalse: [aString lines]) do: [:paragraph | | line |
		line := ''.
		(paragraph substrings: ' ') do: [:word | | candidate |
			candidate := line isEmpty ifTrue: [word] ifFalse: [line, ' ', word].
			((aFont widthOf: candidate) > aWidth and: [line notEmpty])
				ifTrue: [lines add: line. line := word]
				ifFalse: [line := candidate]].
		lines add: line].
	^lines
! !

!AgentItemView methodsFor: 'drawing'!
drawOref: anId at: aPoint on: aCanvas
	"An object id boxed in ultramarine (the mock's .oref); answer its width."
	| font w |
	font := self theme font: #codeSmall.
	w := (font widthOf: anId) + 8.
	aCanvas strokeRect: (aPoint extent: w @ font lineHeight) color: self theme ultramarine width: 1.
	aCanvas drawString: anId at: aPoint + (4 @ 0) font: font color: self theme ultramarine.
	^w
!
drawOverlayOn: aCanvas
	(self hasKeyboardFocus and: [item objectId notNil and: [item failed not]]) ifTrue: [
		aCanvas strokeRect: ((self gutterWidth @ 0 corner: (self width - self margin) @ (self height - 8)) insetBy: 1) color: self theme ultramarine width: 2]
! !

!AgentItemView methodsFor: 'remote control'!
remoteRole
	^#item
!
remoteLabel
	^item text
!
remoteState
	^item failed ifTrue: [#(#failed)] ifFalse: [#()]
! !

!AgentItemView class methodsFor: 'instance creation'!
for: anAgentItem
	"The view for anAgentItem, or nil if it is not shown."
	| class |
	class := Dictionary new
		at: #user put: AgentMessageView;
		at: #assistant put: AgentMessageView;
		at: #error put: AgentMessageView;
		at: #code put: AgentCodeView;
		at: #show put: AgentShowView;
		yourself.
	^(class at: anAgentItem kind ifAbsent: [^nil]) new item: anAgentItem; yourself
! !

!AgentItemView methodsFor: 'events'!
wantsKeyboardFocus
	^item notNil and: [(item objectId notNil and: [item failed not]) or: [self selectionRows notEmpty]]
!
mouseDown: anEvent
	| offset |
	(anEvent button = 1 and: [self wantsKeyboardFocus]) ifFalse: [^false].
	self focus.
	self selectionRows isEmpty ifTrue: [^true].
	offset := self selectionOffsetAt: (self localEventPosition: anEvent).
	(anEvent modifiers shift and: [selectionAnchor notNil and: [selectionWidth = self width]])
		ifFalse: [selectionAnchor := offset].
	selectionWidth := self width.
	selectionEnd := offset.
	selecting := true.
	self invalidate.
	^true
!
focusLost
	super focusLost.
	self clearTextSelection.
	self invalidate
!
cursorAt: aPoint
	^(self selectionRows anySatisfy: [:row |
		(aPoint y >= row second y) and: [aPoint y < (row second y + row third lineHeight)]])
			ifTrue: [#ibeam] ifFalse: [super cursorAt: aPoint]
!
mouseMove: anEvent
	(selecting == true and: [selectionWidth = self width]) ifFalse: [^false].
	selectionEnd := self selectionOffsetAt: (self localEventPosition: anEvent).
	self invalidate.
	^true
!
mouseUp: anEvent
	selecting == true ifFalse: [^false].
	self mouseMove: anEvent.
	selecting := false.
	^true
!
keyDown: anEvent
	| key |
	key := anEvent key.
	(anEvent modifiers commandKey and: [key isCharacter]) ifTrue: [
		key := key asLowercase.
		(key = $c and: [self hasTextSelection]) ifTrue: [
			self clipboardText: self selectedText.
			^true].
		(key = $a and: [self selectionRows notEmpty]) ifTrue: [
			selectionAnchor := 0.
			selectionEnd := self selectionText size.
			selectionWidth := self width.
			self invalidate.
			^true]].
	^super keyDown: anEvent
! !

!AgentItemView methodsFor: 'selection'!
selectionRows
	"Each row holds its displayed text, origin and font."
	^#()
!
appendSelectionRows: lines at: origin font: font to: rows
	| y |
	y := origin y.
	lines do: [:line |
		rows add: {line. origin x @ y. font}.
		y := y + font lineHeight]
!
selectionOffsetAt: aPoint
	| offset |
	offset := 0.
	self selectionRows do: [:row | | line origin font |
		line := row first.
		origin := row second.
		font := row third.
		aPoint y < origin y ifTrue: [^offset].
		aPoint y < (origin y + font lineHeight) ifTrue: [
			^offset + (font indexAt: aPoint x - origin x in: line)].
		offset := offset + line size + 1].
	^offset - 1 max: 0
!
selectionText
	| rows |
	rows := self selectionRows.
	^String streamContents: [:stream |
		rows doWithIndex: [:row :i |
			i > 1 ifTrue: [stream nextPut: Character lf].
			stream nextPutAll: row first]]
!
hasTextSelection
	^selectionAnchor notNil and: [selectionWidth = self width and: [selectionAnchor ~= selectionEnd]]
!
selectedText
	self hasTextSelection ifFalse: [^''].
	^self selectionText copyFrom: (selectionAnchor min: selectionEnd) + 1 to: (selectionAnchor max: selectionEnd)
!
drawSelectionOn: aCanvas
	| start stop offset color |
	self hasTextSelection ifFalse: [^self].
	start := selectionAnchor min: selectionEnd.
	stop := selectionAnchor max: selectionEnd.
	offset := 0.
	color := self theme color: #textSelection.
	self selectionRows do: [:row | | line origin font a b left right |
		line := row first.
		origin := row second.
		font := row third.
		a := (start - offset) max: 0.
		b := (stop - offset) min: line size.
		b > a ifTrue: [
			left := a = 0 ifTrue: [0] ifFalse: [font widthOf: (line copyFrom: 1 to: a)].
			right := font widthOf: (line copyFrom: 1 to: b).
			aCanvas fillRect: (origin + (left @ 0) extent: (right - left) @ font lineHeight) color: color].
		offset := offset + line size + 1]
!
clearTextSelection
	selectionAnchor := selectionEnd := selectionWidth := nil.
	selecting := false
! !
