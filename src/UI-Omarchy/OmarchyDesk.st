Application subclass: #OmarchyDesk
	instanceVariableNames: 'path text stamp layout cards area hidden lock placed moves fades opacities animator arrangement drag grab target overlay watcher animates'
	classVariableNames: ''
	package: 'UI-Omarchy'!

OmarchyDesk comment: 'I am the Omarchy desktop''s cards (the desktop-cards plugin of omarchy-shell) as Samaltak applications, in one process: each card is an Application whose class names its card (class side cardId: weather, agents, wodify), opened on the desktop (runOnDesktopHidden:: on Wayland a layer surface above the wallpaper and below every window) and placed as ~/.config/omarchy/desktop-cards.json says, the plugin''s layout file: the free area (Omarchy freeArea, less a gap all round) in three columns, a stack at the top and one at the bottom of each, cards top to bottom in the file''s order; hidden cards are left out, maxHeight caps a card, and a card the file does not name goes at the top of the right column (and into the file). When a card''s height changes the cards of its stack move.

	bin/samaltak desk                  "every application of apps/ that is a card"
	OmarchyDesk run

Drag a card (press it with the left button and move) to another column, the other stack of its column, or another place in its stack, as with the plugin (DesktopWindow.qml): the card follows the pointer, raised above the others and faded to 0.85; the other cards close up where it was; the column it would land in is tinted and a line shows where in it; on release the file is rewritten (as the plugin writes it) and the card settles into its place. The other cards slide (200 ms, Omarchy''s Style.easeOut; at once when Hyprland does not animate). The tint and the line are drawn in a transparent desktop window under the cards that the pointer passes through (overlay). A plain click runs the card''s action, a middle click refreshes it. Edits of the file show within a second.

Right-click a card for its menu: Agent opens the agent on that card in a window of its own (a tiled one, which takes the keyboard). The plugin and I read the same file, so either can show the cards; turn the plugin off in ~/.config/omarchy/shell.json before starting me.

The layout as the plugin''s Layout.js, class side: normalize:available: (the file read), serialize:, move:id:column:edge:index:available:, arrangement:heights:width:height:gap:columns:skip: (each card''s place and each stack''s bounds) and dropTarget:x:y:height:gap:columns:heights:.'!

!OmarchyDesk methodsFor: 'accessing'!
title
	^'Desktop'
!
cards
	"id -> the Application showing that card."
	^cards
!
layout
	"The layout file as normalized: screen, opacity, cards (Dictionaries: id, column, edge and, when set, hidden, maxHeight, settings)."
	^layout
!
entries
	^self class entriesOf: layout
!
path
	"The layout file."
	^path ifNil: [Omarchy cardsPath]
!
path: aString
	path := aString
!
area
	"The free area, from the top left of the screen (Omarchy freeArea)."
	^area
!
area: aRectangle
	"Lay out in aRectangle rather than in the free area Hyprland reports (tests)."
	area := aRectangle
!
gap
	"Between the cards and around them: the plugin's Math.max(4, Style.gapsOut * 2)."
	^10
!
columns
	^3
!
placeOf: anId
	"Where card anId is (its host window, from the top left of the free area), or nil."
	^placed at: anId ifAbsent: [nil]
!
dragged
	"The id of the card being dragged, or nil."
	^drag
!
target
	"Where the card being dragged would land (dropTarget:...), or nil."
	^target
!
overlay
	"The GlassPane under the cards that shows where a dragged card would land."
	^overlay
!
innerExtent
	"The free area less the gap all round: the plugin's area."
	^(area width - (2 * self gap)) @ (area height - (2 * self gap))
!
columnWidth
	^self class columnWidthIn: self innerExtent x gap: self gap columns: self columns
! !

!OmarchyDesk methodsFor: 'layout file'!
readLayout
	"Read the layout file as Layout.js normalizes it (a missing or broken file is an empty layout) and, as the plugin does, write it back when that changed it (cards it did not name, entries it dropped)."
	| t |
	t := [File readText: self path] on: Error do: [:e | e return: nil].
	stamp := self fileStamp.
	text := t.
	layout := self class normalize: t available: self class cardIds.
	(self class serialize: layout) = t ifFalse: [self save]
!
save
	"Write the layout to the file: a new file next to it, renamed over it."
	| s tmp |
	s := self class serialize: layout.
	text := s.
	tmp := self path, '.tmp'.
	[File writeText: s to: tmp.
	 File rename: tmp to: self path] on: Error do: [:e | e return: nil].
	stamp := self fileStamp
!
fileStamp
	^[Array with: (File modificationTime: self path) with: (File sizeOf: self path)] on: Error do: [:e | e return: nil]
!
checkFile
	"An edit of the layout file (not mine): read it and apply it."
	| t |
	self fileStamp = stamp ifTrue: [^self].
	t := [File readText: self path] on: Error do: [:e | e return: nil].
	stamp := self fileStamp.
	t = text ifTrue: [^self].
	lock critical: [
		self readLayout.
		self applyLayout]
!
watch
	"Once a second, look whether the layout file changed."
	[(Delay forSeconds: 1) wait.
	 [self checkFile] on: Error do: [:e | e return: nil]] repeat
! !

!OmarchyDesk methodsFor: 'cards'!
openCard: anId
	"Open the card anId as its Application, on the desktop, at the top left until it is placed."
	| class app entry |
	class := self class applicationFor: anId.
	class isNil ifTrue: [^nil].
	entry := self entryOf: anId.
	app := class new.
	cards at: anId put: app.
	(app content isKindOf: OmarchyCard) ifTrue: [
		app content columnWidth: self columnWidth; framed: true.
		app content onDrag: [:phase :p | self card: anId drag: phase at: p]].
	app runOnDesktopHidden: hidden.
	(entry notNil and: [(entry at: 5) notNil]) ifTrue: [
		app window do: [app content maxHeight: (entry at: 5). app fitToContent]].
	placed at: anId put: 0 @ 0.
	app world whenResized: [:w | lock critical: [self arrange]].
	self warmDragPreviewFor: app.
	^app
!
closeCard: anId
	| app |
	app := cards removeKey: anId ifAbsent: [^self].
	placed removeKey: anId ifAbsent: [].
	self finishMove: anId.
	drag = anId ifTrue: [self closeDragPreview. drag := nil. target := nil. self drawTarget].
	(self dragPreviews removeKey: app ifAbsent: [nil]) ifNotNil: [:p | p close].
	app stop
!
entryOf: anId
	^self entries detect: [:e | (e at: 1) = anId] ifNone: [nil]
!
applyLayout
	"Open the cards the layout shows and close those it hides, give each its maxHeight, and arrange them."
	| shown |
	shown := (self entries reject: [:e | e at: 4]) collect: [:e | e at: 1].
	cards keys asArray do: [:id | (shown includes: id) ifFalse: [self closeCard: id]].
	self entries do: [:e |
		(e at: 4) ifFalse: [
			(cards includesKey: (e at: 1))
				ifTrue: [
					| app |
					app := cards at: (e at: 1).
					(app content isKindOf: OmarchyCard) ifTrue: [
						app content maxHeight = (e at: 5) ifFalse: [
							app window do: [app content maxHeight: (e at: 5). app fitToContent]]]]
				ifFalse: [self openCard: (e at: 1)]]].
	self arrange
! !

!OmarchyDesk methodsFor: 'arranging'!
heights
	"id -> the height of each open card."
	| heights |
	heights := Dictionary new.
	cards keysAndValuesDo: [:id :app | app world isNil ifFalse: [heights at: id put: app world extent y]].
	^heights
!
arrange
	self arrangeImmediately: nil
!
move: anId to: aPoint animated: aBoolean
	"Slide the existing preview, when there is one; otherwise move the card itself."
	| from move |
	move := moves at: anId ifAbsent: [nil].
	(move notNil and: [move size > 3]) ifTrue: [
		self place: anId at: aPoint.
		from := move at: 5.
		(aBoolean and: [from ~= aPoint]) ifFalse: [^self finishMove: anId].
		(move at: 2) = aPoint ifTrue: [^self].
		moves at: anId put: {from. aPoint. Time millisecondClockValue. move at: 4. from}.
		^self animate].
	from := placed at: anId ifAbsent: [aPoint].
	(aBoolean and: [from ~= aPoint]) ifFalse: [
		moves removeKey: anId ifAbsent: [].
		^self place: anId at: aPoint].
	(move notNil and: [(move at: 2) = aPoint]) ifTrue: [^self].
	moves at: anId put: {from. aPoint. Time millisecondClockValue}.
	self animate
!
place: anId at: aPoint
	| app |
	app := cards at: anId ifAbsent: [^self].
	(placed at: anId ifAbsent: [nil]) = aPoint ifTrue: [^self].
	placed at: anId put: aPoint.
	app world isNil ifFalse: [app world moveTo: aPoint]
!
fade: anId to: aNumber
	"Fade card anId to aNumber opacity in 120 ms."
	| from |
	from := opacities at: anId ifAbsent: [1].
	from = aNumber ifTrue: [^self].
	animates ifFalse: [^self opacity: anId to: aNumber].
	fades at: anId put: (Array with: from with: aNumber with: Time millisecondClockValue).
	self animate
!
opacity: anId to: aNumber
	| app |
	app := cards at: anId ifAbsent: [^self].
	opacities at: anId put: aNumber.
	app world isNil ifFalse: [app world opacity: aNumber]
!
animate
	"Step the slides and fades every 8 ms until they are done (with the lock held, as the animator gives up when none is left)."
	animator isNil ifFalse: [^self].
	animator := [
		[lock critical: [
			self step or: [
				animator := nil.
				false]]] whileTrue: [(Delay forMilliseconds: 8) wait]] newProcess.
	animator priority: Processor userInterruptPriority - 1; name: 'desk animations'.
	animator resume
!
step
	"One step of the slides (Style.easeOut, 200 ms) and the fades (OutCubic, 120 ms); answer whether any is left."
	| now |
	now := Time millisecondClockValue.
	moves keys asArray do: [:id |
		| m t e p |
		m := moves at: id.
		t := ((now - (m at: 3)) / 200) min: 1.
		e := Animation ease: #(0.23 1.0 0.32 1.0) at: t.
		p := ((m at: 1) + (((m at: 2) - (m at: 1)) * e)) rounded.
		m size > 3
			ifTrue: [
				p = (m at: 5) ifFalse: [
					(m at: 4) hostWindow moveTo: p.
					m at: 5 put: p]]
			ifFalse: [self place: id at: p].
		t >= 1 ifTrue: [self finishMove: id]].
	fades keys asArray do: [:id |
		| f t |
		f := fades at: id.
		t := ((now - (f at: 3)) / 120) min: 1.
		self opacity: id to: (f at: 1) + (((f at: 2) - (f at: 1)) * (Animation ease: #easeOutCubic at: t)).
		t >= 1 ifTrue: [fades removeKey: id]].
	^moves notEmpty or: [fades notEmpty]
!
arrangeImmediately: anId
	"Slide the other cards into place, but snap anId without a second animation."
	| inner |
	inner := self innerExtent.
	arrangement := self class arrangement: self entries heights: self heights width: inner x height: inner y
		gap: self gap columns: self columns skip: drag.
	(arrangement at: #slots) keysAndValuesDo: [:id :r |
		(cards includesKey: id) ifTrue: [self move: id to: r origin + self gap animated: (animates and: [id ~= anId])]]
! !

!OmarchyDesk methodsFor: 'dragging'!
card: anId drag: aSymbol at: aScreenPoint
	"Card anId is dragged (OmarchyCard>>onDrag:): #start, #move or #end, the pointer at aScreenPoint (from the top left of the free area)."
	lock critical: [
		| p |
		p := aScreenPoint - self gap.
		aSymbol == #start ifTrue: [
			(drag isNil or: [drag = anId]) ifFalse: [^self].
			^self beginDrag: anId at: p].
		drag = anId ifFalse: [^self].
		aSymbol == #move ifTrue: [^self updateDrag: p].
		aSymbol == #end ifTrue: [^self endDrag]]
!
beginDrag: anId at: aPoint
	| app origin preview |
	app := cards at: anId ifAbsent: [^self].
	self finishMove: anId.
	fades removeKey: anId ifAbsent: [].
	origin := placed at: anId ifAbsent: [self gap @ self gap].
	drag := anId.
	preview := self dragPreviewFor: app at: origin.
	grab := {aPoint - (origin - self gap). preview. origin}.
	preview isNil ifTrue: [
		app world isNil ifFalse: [app world raise].
		self fade: anId to: 0.85].
	self arrange
!
updateDrag: aPoint
	"Move first. Only repaint the overlay when the snap slot changes."
	| extent inner x y maxX maxY next |
	extent := (cards at: drag) world extent.
	inner := self innerExtent.
	maxX := inner x - extent x + self gap.
	maxY := inner y - extent y + self gap.
	x := ((aPoint x - grab first x) max: (maxX min: self gap negated)) min: (maxX max: self gap negated).
	y := ((aPoint y - grab first y) max: (maxY min: self gap negated)) min: (maxY max: self gap negated).
	self moveDraggedTo: (x @ y) rounded + self gap.
	next := self class dropTarget: arrangement x: aPoint x y: aPoint y height: inner y
		gap: self gap columns: self columns heights: self heights.
	(target notNil and: [(#(#column #edge #index #lineY #x #width) allSatisfy: [:key | (next at: key) = (target at: key)])]) ifTrue: [^self].
	target := next.
	self drawTarget
!
endDrag
	"Keep the dragged surface visible until its settling slide is complete."
	| id t preview from |
	id := drag.
	t := target.
	preview := grab at: 2.
	from := grab at: 3.
	grab := nil.
	drag := nil.
	target := nil.
	preview isNil
		ifTrue: [self fade: id to: 1]
		ifFalse: [moves at: id put: {from. nil. Time millisecondClockValue. preview. from}].
	t isNil ifFalse: [
		layout := self class move: layout id: id column: (t at: #column) edge: (t at: #edge) index: (t at: #index)
			available: self class cardIds].
	self arrange.
	preview isNil ifFalse: [
		(moves at: id ifAbsent: [nil]) ifNotNil: [:m |
			(m at: 2) isNil ifTrue: [self finishMove: id]]].
	self drawTarget.
	t isNil ifFalse: [self save]
!
accent
	| theme |
	theme := Theme current.
	^(theme respondsTo: #accent) ifTrue: [theme accent] ifFalse: [Color ultramarine]
!
space: points
	| theme |
	theme := Theme current.
	^(theme respondsTo: #space:) ifTrue: [theme space: points] ifFalse: [points]
!
drawTarget
	"The drop affordances of DesktopWindow.qml, or nothing: the target column tinted (the accent at 0.06, framed at 0.3) and a line (the accent) where the card would land."
	| t accent column h |
	overlay isNil ifTrue: [^self].
	t := target.
	t isNil ifTrue: [^overlay clear].
	accent := self accent.
	column := (t at: #x) @ 0 extent: (t at: #width) @ self innerExtent y.
	h := (self space: 3) max: 3.
	overlay show: [:pane |
		pane fillRect: (column insetBy: 1) color: (accent alpha: 0.06).
		pane strokeRect: column color: (accent alpha: 0.3) width: 1.
		pane fillPill: ((t at: #x) @ ((t at: #lineY) - (h / 2)) rounded extent: (t at: #width) @ h) color: accent]
!
dragPreviewFor: app at: aPoint
	"Refresh the already mapped preview before revealing it at the card."
	| source extent p canvas |
	p := self dragPreviews at: app ifAbsent: [^nil].
	^[
		source := app world displayWindow surface.
		extent := app world extent.
		p extent = extent ifFalse: [p extent: extent].
		canvas := Canvas extent: extent scale: p scale.
		canvas image: source in: (0 @ 0 extent: extent).
		(p show: canvas displayList clear: Color paper) ifFalse: [^nil].
		p hostWindow moveTo: aPoint.
		(app world opacity: 0) ifFalse: [self parkDragPreview: p. ^nil].
		p hostWindow opacity: 0.85.
		p]
		on: Error do: [:error | app world opacity: 1. self parkDragPreview: p. nil]
!
moveDraggedTo: aPoint
	| preview |
	preview := grab at: 2.
	preview isNil ifTrue: [^self move: drag to: aPoint animated: false].
	(grab at: 3) = aPoint ifTrue: [^self].
	preview hostWindow moveTo: aPoint.
	grab at: 3 put: aPoint
!
closeDragPreview
	| preview |
	grab isNil ifTrue: [^self].
	preview := grab at: 2.
	grab := nil.
	preview isNil ifFalse: [self parkDragPreview: preview]
!
finishMove: anId
	| move |
	move := moves removeKey: anId ifAbsent: [^self].
	move size > 3 ifFalse: [^self].
	self parkDragPreview: (move at: 4).
	self opacity: anId to: 1
!
dragPreviews
	^opacities at: #dragPreviews ifAbsentPut: [Dictionary new]
!
parkDragPreview: preview
	preview hostWindow opacity: 0.
	preview hostWindow moveTo: (area width @ area height)
!
warmDragPreviewFor: app
	"Map an invisible preview before the first drag, then park it offscreen."
	| p extent canvas |
	(hidden or: [app world isNil or: [self dragPreviews includesKey: app]]) ifTrue: [^self].
	extent := app world extent.
	p := nil.
	[
		p := AppWorld desktopWindowExtent: extent title: 'Desktop card drag'.
		p hostWindow opacity: 0.
		canvas := Canvas extent: extent scale: p scale.
		canvas fillRect: (0 @ 0 extent: extent) color: Color paper.
		(p show: canvas displayList clear: Color paper) ifFalse: [p close. ^self].
		self parkDragPreview: p.
		self dragPreviews at: app put: p]
		on: Error do: [:error | p isNil ifFalse: [p close]]
! !

!OmarchyDesk methodsFor: 'running'!
runHidden: aBoolean
	"Open every card the layout shows (hidden: offscreen, for tests) and place them; answer myself. The overlay opens first, so that it stays under the cards."
	| inner |
	hidden := aBoolean.
	lock := Mutex new.
	animates := false.
	cards := Dictionary new.
	placed := Dictionary new.
	moves := Dictionary new.
	fades := Dictionary new.
	opacities := Dictionary new.
	area isNil ifTrue: [area := Omarchy freeArea ifNil: [0 @ 0 extent: 1512 @ 950]].
	inner := self innerExtent.
	overlay := GlassPane extent: inner title: 'Desktop' desktop: true hidden: aBoolean.
	overlay clear.
	overlay moveTo: self gap @ self gap.
	lock critical: [
		self readLayout.
		self applyLayout].
	"From now on the cards slide, as the plugin's do."
	animates := aBoolean not and: [Omarchy animates].
	watcher := [self watch] newProcess.
	watcher priority: Processor userBackgroundPriority; name: 'desk layout file'.
	watcher resume
!
animates: aBoolean
	"Whether the cards slide and fade (tests: at once)."
	animates := aBoolean
!
stop
	watcher isNil ifFalse: [watcher terminate. watcher := nil].
	animator isNil ifFalse: [animator terminate. animator := nil].
	self closeDragPreview.
	moves isNil ifFalse: [moves keys asArray do: [:id | self finishMove: id]].
	opacities isNil ifFalse: [self dragPreviews do: [:p | p close]. self dragPreviews removeAll].
	cards isNil ifFalse: [cards do: [:app | app stop]].
	overlay isNil ifFalse: [overlay close. overlay := nil]
! !

!OmarchyDesk class methodsFor: 'cards'!
applicationFor: anId
	"The Application that shows the card anId, or nil."
	^Application allSubclasses detect: [:c | c cardId = anId] ifNone: [nil]
!
cardIds
	"The cards some Application of the image shows, sorted (as the plugin finds cards/*/Card.qml)."
	^((Application allSubclasses collect: [:c | c cardId]) reject: [:each | each isNil]) asSortedCollection asArray
! !

!OmarchyDesk class methodsFor: 'layout'!
normalize: aJSONString available: anArrayOfIds
	"Layout.js normalize: the layout file's text (nil: none) as screen, opacity (0.2 to 1) and cards, each a Dictionary of id, column (0 to 2), edge ('top' or 'bottom') and, when set, hidden (true), maxHeight (at least 80) and settings; entries without a proper id, repeated ones and those not objects are dropped, and the ids of anArrayOfIds the file does not name are added at the top of the right column."
	| data list seen cards screen opacity |
	data := aJSONString isNil ifTrue: [nil] ifFalse: [[JSON parse: aJSONString] on: Error do: [:e | e return: nil]].
	(data isKindOf: Dictionary) ifFalse: [data := Dictionary new].
	list := data at: 'cards' ifAbsent: [nil].
	(list isKindOf: Array) ifFalse: [list := #()].
	seen := Set new.
	cards := OrderedCollection new.
	list do: [:each |
		| id clean max |
		(each isKindOf: Dictionary) ifTrue: [
			id := self idFrom: (each at: 'id' ifAbsent: [nil]).
			(id notNil and: [(seen includes: id) not]) ifTrue: [
				seen add: id.
				clean := Dictionary new.
				clean
					at: 'id' put: id;
					at: 'column' put: (self columnFrom: (each at: 'column' ifAbsent: [nil]));
					at: 'edge' put: ((each at: 'edge' ifAbsent: [nil]) = 'bottom' ifTrue: ['bottom'] ifFalse: ['top']).
				(each at: 'hidden' ifAbsent: [nil]) == true ifTrue: [clean at: 'hidden' put: true].
				max := self numberFrom: (each at: 'maxHeight' ifAbsent: [nil]).
				(max notNil and: [max > 0]) ifTrue: [clean at: 'maxHeight' put: (max rounded max: 80)].
				((each at: 'settings' ifAbsent: [nil]) isKindOf: Dictionary) ifTrue: [clean at: 'settings' put: (each at: 'settings')].
				cards add: clean]]].
	anArrayOfIds do: [:id |
		(seen includes: id) ifFalse: [
			seen add: id.
			cards add: (Dictionary new at: 'id' put: id; at: 'column' put: 2; at: 'edge' put: 'top'; yourself)]].
	screen := data at: 'screen' ifAbsent: [''].
	screen isString ifFalse: [screen := ''].
	opacity := data at: 'opacity' ifAbsent: [nil].
	opacity := opacity isNumber ifTrue: [(opacity max: 0.2) min: 1] ifFalse: [1].
	^Dictionary new
		at: 'screen' put: screen;
		at: 'opacity' put: opacity;
		at: 'cards' put: cards asArray;
		yourself
!
idFrom: anObject
	"String(entry.id || ''), if it is 1 to 64 of A-Z a-z 0-9 _ . -; else nil."
	| id |
	id := anObject isString
		ifTrue: [anObject]
		ifFalse: [(anObject isNumber and: [anObject ~= 0]) ifTrue: [anObject printString] ifFalse: ['']].
	(id size between: 1 and: 64) ifFalse: [^nil].
	(id allSatisfy: [:c | (c isLetter and: [c asInteger < 128]) or: [c isDigit or: ['_.-' includes: c]]]) ifFalse: [^nil].
	^id asString
!
columnFrom: anObject
	"clampColumn: parseInt(value, 10), the right column when it is no number, within the columns."
	| n s i |
	n := nil.
	anObject isNumber ifTrue: [n := anObject truncated].
	anObject isString ifTrue: [
		s := anObject trimBoth.
		i := (s notEmpty and: ['+-' includes: s first]) ifTrue: [2] ifFalse: [1].
		[i <= s size and: [(s at: i) isDigit]] whileTrue: [i := i + 1].
		(i > 1 and: [(s at: i - 1) isDigit]) ifTrue: [n := (s copyFrom: 1 to: i - 1) asNumber]].
	n isNil ifTrue: [^2].
	^(n max: 0) min: 2
!
numberFrom: anObject
	"Number(value) for a number or a string of one; else nil."
	anObject isNumber ifTrue: [^anObject].
	anObject isString ifTrue: [^[anObject trimBoth asNumber] on: Error do: [:e | e return: nil]].
	^nil
!
entriesOf: aLayout
	"The layout's cards as {id. column. edge (#top or #bottom). hidden. maxHeight (nil: none)}."
	^(aLayout at: 'cards') collect: [:c |
		Array
			with: (c at: 'id')
			with: (c at: 'column')
			with: (c at: 'edge') asSymbol
			with: (c at: 'hidden' ifAbsent: [false]) == true
			with: (c at: 'maxHeight' ifAbsent: [nil])]
!
entriesIn: aJSONString available: anArrayOfIds
	^self entriesOf: (self normalize: aJSONString available: anArrayOfIds)
!
stack: aLayout column: column edge: edge available: anArrayOfIds
	"Layout.js stack: the ids of the shown cards of a stack, top to bottom."
	^((aLayout at: 'cards') select: [:c |
		(c at: 'column') = column and: [(c at: 'edge') = edge asString and: [self isShown: c available: anArrayOfIds]]])
			collect: [:c | c at: 'id']
!
find: aLayout id: anId
	"Layout.js find: the entry of card anId, or nil."
	^(aLayout at: 'cards') detect: [:c | (c at: 'id') = anId] ifNone: [nil]
!
isShown: anEntry available: anArrayOfIds
	^(anEntry at: 'hidden' ifAbsent: [false]) ~~ true and: [anArrayOfIds isNil or: [anArrayOfIds includes: (anEntry at: 'id')]]
!
move: aLayout id: anId column: column edge: edge index: index available: anArrayOfIds
	"Layout.js move: a new layout with card anId at position index (counted among the other shown cards of that stack, from 0) of the stack at column and edge (#top or #bottom)."
	| cards current moved others members at |
	cards := aLayout at: 'cards'.
	current := cards detect: [:c | (c at: 'id') = anId] ifNone: [^aLayout].
	moved := current copy.
	moved at: 'column' put: column; at: 'edge' put: edge asString.
	others := (cards reject: [:c | (c at: 'id') = anId]) asOrderedCollection.
	members := (1 to: others size) select: [:j |
		| c |
		c := others at: j.
		(c at: 'column') = column and: [(c at: 'edge') = edge asString and: [self isShown: c available: anArrayOfIds]]].
	at := members isEmpty
		ifTrue: [others size + 1]
		ifFalse: [index < members size ifTrue: [members at: (index max: 0) + 1] ifFalse: [members last + 1]].
	others add: moved beforeIndex: at.
	^Dictionary new
		at: 'screen' put: (aLayout at: 'screen');
		at: 'opacity' put: (aLayout at: 'opacity');
		at: 'cards' put: others asArray;
		yourself
!
serialize: aLayout
	"Layout.js serialize: JSON.stringify({screen, cards, opacity unless 1}, null, 2) and a line feed; a card's keys in the order id, column, edge, hidden, maxHeight, settings, other objects' keys (settings') sorted: JSON reads objects into Dictionaries, which keep no order."
	^String new: 512 streamContents: [:s |
		s nextPutAll: '{'; nextPut: Character lf.
		s nextPutAll: '  "screen": '; nextPutAll: (JSON quote: (aLayout at: 'screen')).
		s nextPut: $,; nextPut: Character lf; nextPutAll: '  "cards": '.
		self write: (aLayout at: 'cards') on: s indent: 1.
		(aLayout at: 'opacity') = 1 ifFalse: [
			s nextPut: $,; nextPut: Character lf; nextPutAll: '  "opacity": '.
			self write: (aLayout at: 'opacity') on: s indent: 1].
		s nextPut: Character lf; nextPutAll: '}'; nextPut: Character lf]
!
write: anObject on: aStream indent: n
	"anObject as JSON.stringify(…, null, 2) writes it at indentation level n."
	| keys |
	(anObject isKindOf: Dictionary) ifTrue: [
		anObject isEmpty ifTrue: [^aStream nextPutAll: '{}'].
		keys := (#('id' 'column' 'edge' 'hidden' 'maxHeight' 'settings') select: [:k | anObject includesKey: k]),
			(anObject keys asSortedCollection asArray reject: [:k | #('id' 'column' 'edge' 'hidden' 'maxHeight' 'settings') includes: k]).
		aStream nextPut: ${.
		keys doWithIndex: [:k :i |
			i > 1 ifTrue: [aStream nextPut: $,].
			aStream nextPut: Character lf; nextPutAll: (String new: 2 * (n + 1) withAll: Character space); nextPutAll: (JSON quote: k); nextPutAll: ': '.
			self write: (anObject at: k) on: aStream indent: n + 1].
		^aStream nextPut: Character lf; nextPutAll: (String new: 2 * n withAll: Character space); nextPut: $}].
	(anObject isString not and: [anObject isKindOf: SequenceableCollection]) ifTrue: [
		anObject isEmpty ifTrue: [^aStream nextPutAll: '[]'].
		aStream nextPut: $[.
		anObject doWithIndex: [:each :i |
			i > 1 ifTrue: [aStream nextPut: $,].
			aStream nextPut: Character lf; nextPutAll: (String new: 2 * (n + 1) withAll: Character space).
			self write: each on: aStream indent: n + 1].
		^aStream nextPut: Character lf; nextPutAll: (String new: 2 * n withAll: Character space); nextPut: $]].
	(anObject isFloat and: [anObject isFinite and: [anObject fractionPart = 0]]) ifTrue: [
		^aStream nextPutAll: anObject truncated printString].
	aStream nextPutAll: (JSON render: anObject)
!
columnWidthIn: width gap: gap columns: columns
	^((width - (gap * (columns - 1))) / columns) floor max: 0
!
arrangement: entries heights: aDictionary width: width height: height gap: gap columns: columns skip: skipId
	"Layout.js arrange: colWidth, slots (id -> the Rectangle of each shown card of a height aDictionary knows, but skipId) and stacks ('column:edge' -> x, y, width, height and the ids, top to bottom) in an area of width × height. A top stack grows down from the top, a bottom one up from the bottom, gap between cards."
	| colWidth slots stacks |
	colWidth := self columnWidthIn: width gap: gap columns: columns.
	slots := Dictionary new.
	stacks := Dictionary new.
	0 to: columns - 1 do: [:c |
		| x |
		x := c * (colWidth + gap).
		#(#top #bottom) do: [:edge |
			| ids total y top |
			ids := (entries select: [:e | (e at: 2) = c and: [(e at: 3) == edge and: [(e at: 4) not
					and: [(e at: 1) ~= skipId and: [aDictionary includesKey: (e at: 1)]]]]])
				collect: [:e | e at: 1].
			total := 0.
			ids doWithIndex: [:id :i | total := total + (aDictionary at: id) + (i > 1 ifTrue: [gap] ifFalse: [0])].
			y := edge == #top ifTrue: [0] ifFalse: [height - total].
			top := y.
			ids do: [:id |
				slots at: id put: (x @ y extent: colWidth @ (aDictionary at: id)).
				y := y + (aDictionary at: id) + gap].
			stacks at: c printString, ':', edge put: (Dictionary new
				at: #x put: x; at: #y put: top; at: #width put: colWidth; at: #height put: total; at: #ids put: ids asArray;
				yourself)]].
	^Dictionary new at: #colWidth put: colWidth; at: #slots put: slots; at: #stacks put: stacks; yourself
!
arrange: entries heights: aDictionary width: width height: height gap: gap columns: columns
	"id -> the place of each shown card (of a height aDictionary knows)."
	^(self arrangement: entries heights: aDictionary width: width height: height gap: gap columns: columns skip: nil) at: #slots
!
dropTarget: anArrangement x: px y: py height: height gap: gap columns: columns heights: aDictionary
	"Layout.js dropTarget: where a card dropped at px @ py (its center's x, the pointer's y) would land: column, edge (#top or #bottom), index (among that stack's cards, from 0), lineY (where to draw the line), x and width (of the column)."
	| colWidth column top bottom edge s index y lineY |
	colWidth := anArrangement at: #colWidth.
	column := ((px + (gap / 2)) / (colWidth + gap)) floor.
	column := (column max: 0) min: columns - 1.
	top := (anArrangement at: #stacks) at: column printString, ':top'.
	bottom := (anArrangement at: #stacks) at: column printString, ':bottom'.
	edge := ((top at: #ids) notEmpty and: [py <= ((top at: #y) + (top at: #height) + gap)])
		ifTrue: [#top]
		ifFalse: [
			((bottom at: #ids) notEmpty and: [py >= ((bottom at: #y) - gap)])
				ifTrue: [#bottom]
				ifFalse: [py < (height / 2) ifTrue: [#top] ifFalse: [#bottom]]].
	s := edge == #top ifTrue: [top] ifFalse: [bottom].
	index := 0.
	y := s at: #y.
	(s at: #ids) doWithIndex: [:id :i |
		| h |
		h := aDictionary at: id ifAbsent: [0].
		py > (y + (h / 2)) ifTrue: [index := i].
		y := y + h + gap].
	(s at: #ids) isEmpty
		ifTrue: [lineY := edge == #top ifTrue: [0] ifFalse: [height]]
		ifFalse: [
			| yy |
			yy := s at: #y.
			1 to: index do: [:j | yy := yy + (aDictionary at: ((s at: #ids) at: j) ifAbsent: [0]) + gap].
			lineY := index = 0
				ifTrue: [(s at: #y) - (gap / 2)]
				ifFalse: [index = (s at: #ids) size ifTrue: [(s at: #y) + (s at: #height) + (gap / 2)] ifFalse: [yy - (gap / 2)]].
			lineY := (lineY max: 0) min: height].
	^Dictionary new
		at: #column put: column; at: #edge put: edge; at: #index put: index; at: #lineY put: lineY;
		at: #x put: column * (colWidth + gap); at: #width put: colWidth;
		yourself
! !
