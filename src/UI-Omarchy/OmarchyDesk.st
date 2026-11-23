Application subclass: #OmarchyDesk
	instanceVariableNames: 'entries cards area hidden'
	classVariableNames: ''
	package: 'UI-Omarchy'!

OmarchyDesk comment: 'I am the Omarchy desktop''s cards (the desktop-cards plugin of omarchy-shell) as Samaltak applications, in one process: each card is an Application whose class names its card (class side cardId: weather, agents, wodify), opened on the desktop (runOnDesktopHidden:: on Wayland a layer surface above the wallpaper and below every window) and placed as ~/.config/omarchy/desktop-cards.json says, the plugin''s layout file: the free area (Omarchy freeArea, less a gap all round) in three columns, a stack at the top and one at the bottom of each, cards top to bottom in the file''s order; hidden cards are left out, maxHeight caps a card, and a card the file does not name goes at the top of the right column. When a card''s height changes the cards of its stack move.

	bin/samaltak desk                  "every application of apps/ that is a card"
	OmarchyDesk run

Right-click a card for its menu: Agent opens the agent on that card in a window of its own (a tiled one, which takes the keyboard). The plugin and I read the same file, so either can show the cards; turn the plugin off in ~/.config/omarchy/shell.json before starting me.

Layout as the plugin''s Layout.js: arrange:heights:width:height: answers each card''s place.'!

!OmarchyDesk methodsFor: 'accessing'!
title
	^'Desktop'
!
cards
	"id -> the Application showing that card."
	^cards
!
entries
	^entries
!
gap
	"Between the cards and around them: the plugin's Math.max(4, Style.gapsOut * 2)."
	^10
!
columns
	^3
! !

!OmarchyDesk methodsFor: 'layout'!
readLayout
	"The entries of the layout file, as Layout.js normalizes them: {id. column. edge (#top or #bottom). hidden. maxHeight (nil: none)}, cards of applications the file does not name added at the top of the right column."
	^self class entriesIn: ([File readText: Omarchy cardsPath] on: Error do: [:e | e return: nil]) available: self class cardIds
!
arrange
	"Move every card to its place."
	| heights places |
	heights := Dictionary new.
	cards keysAndValuesDo: [:id :app | app world isNil ifFalse: [heights at: id put: app world extent y]].
	places := self class arrange: entries heights: heights width: area width - (2 * self gap) height: area height - (2 * self gap) gap: self gap columns: self columns.
	places keysAndValuesDo: [:id :r |
		(cards at: id ifAbsent: [nil]) ifNotNil: [:app |
			app world isNil ifFalse: [app world moveTo: r origin + self gap]]]
!
columnWidth
	^self class columnWidthIn: area width - (2 * self gap) gap: self gap columns: self columns
! !

!OmarchyDesk methodsFor: 'running'!
runHidden: aBoolean
	"Open every card the layout shows (hidden: offscreen, for tests) and place them; answer myself."
	hidden := aBoolean.
	area := Omarchy freeArea ifNil: [0 @ 0 extent: 1512 @ 950].
	entries := self readLayout.
	cards := Dictionary new.
	entries do: [:entry |
		| class app |
		class := (entry at: 4) ifFalse: [self class applicationFor: (entry at: 1)].
		class isNil ifFalse: [
			app := class new.
			cards at: (entry at: 1) put: app.
			(app content isKindOf: OmarchyCard) ifTrue: [app content columnWidth: self columnWidth; framed: true].
			app runOnDesktopHidden: aBoolean.
			(entry at: 5) isNil ifFalse: [
				app window do: [app content maxHeight: (entry at: 5). app fitToContent]].
			app world whenResized: [:w | self arrange]]].
	self arrange
!
stop
	cards isNil ifFalse: [cards do: [:app | app stop]]
! !

!OmarchyDesk class methodsFor: 'cards'!
applicationFor: anId
	"The Application that shows the card anId, or nil."
	^Application allSubclasses detect: [:c | c cardId = anId] ifNone: [nil]
!
cardIds
	"The cards some Application of the image shows."
	^((Application allSubclasses collect: [:c | c cardId]) reject: [:each | each isNil]) asArray
! !

!OmarchyDesk class methodsFor: 'layout'!
entriesIn: aJSONString available: anArrayOfIds
	"Layout.js normalize: the layout file's cards as {id. column. edge. hidden. maxHeight}, the ids of anArrayOfIds it does not name at the top of the right column."
	| data list seen out |
	data := aJSONString isNil ifTrue: [nil] ifFalse: [[JSON parse: aJSONString] on: Error do: [:e | e return: nil]].
	list := (data isKindOf: Dictionary) ifTrue: [data at: 'cards' ifAbsent: [#()]] ifFalse: [#()].
	(list isKindOf: Array) ifFalse: [list := #()].
	seen := Set new.
	out := OrderedCollection new.
	list do: [:each |
		| id column edge max |
		(each isKindOf: Dictionary) ifTrue: [
			id := (each at: 'id' ifAbsent: ['']) asString.
			(id notEmpty and: [(seen includes: id) not]) ifTrue: [
				seen add: id.
				column := each at: 'column' ifAbsent: [2].
				column := column isInteger ifTrue: [(column max: 0) min: 2] ifFalse: [2].
				edge := (each at: 'edge' ifAbsent: ['top']) = 'bottom' ifTrue: [#bottom] ifFalse: [#top].
				max := each at: 'maxHeight' ifAbsent: [nil].
				max := (max isNumber and: [max > 0]) ifTrue: [max rounded max: 80] ifFalse: [nil].
				out add: (Array with: id with: column with: edge with: (each at: 'hidden' ifAbsent: [false]) == true with: max)]]].
	anArrayOfIds do: [:id |
		(seen includes: id) ifFalse: [
			seen add: id.
			out add: (Array with: id with: 2 with: #top with: false with: nil)]].
	^out asArray
!
columnWidthIn: width gap: gap columns: columns
	^((width - (gap * (columns - 1))) / columns) floor max: 0
!
arrange: entries heights: aDictionary width: width height: height gap: gap columns: columns
	"Layout.js arrange: id -> the Rectangle of each shown card (of a height aDictionary knows) in an area of width × height. A top stack grows down from the top, a bottom one up from the bottom, gap between cards."
	| colWidth places |
	colWidth := self columnWidthIn: width gap: gap columns: columns.
	places := Dictionary new.
	0 to: columns - 1 do: [:c |
		| x |
		x := c * (colWidth + gap).
		#(#top #bottom) do: [:edge |
			| ids total y |
			ids := (entries select: [:e | (e at: 2) = c and: [(e at: 3) == edge and: [(e at: 4) not and: [aDictionary includesKey: (e at: 1)]]]])
				collect: [:e | e at: 1].
			total := 0.
			ids doWithIndex: [:id :i | total := total + (aDictionary at: id) + (i > 1 ifTrue: [gap] ifFalse: [0])].
			y := edge == #top ifTrue: [0] ifFalse: [height - total].
			ids do: [:id |
				places at: id put: (x @ y extent: colWidth @ (aDictionary at: id)).
				y := y + (aDictionary at: id) + gap]]].
	^places
! !
