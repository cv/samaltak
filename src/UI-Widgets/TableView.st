ListView subclass: #TableView
	instanceVariableNames: 'columns columnRects columnsWidth'
	classVariableNames: ''
	package: 'UI-Widgets'!

TableView comment: 'I am a ListView with columns and a header strip (the Process Browser''s PRI / PROCESS / STATE / CPU): each row shows its item in TableColumns (text or custom drawing); selection, keys, scrolling and the glide are the ListView''s.

	table := TableView new.
	table addColumn: (TableColumn title: '''' width: 8 draw: (TableView squareDotCell: [:p | p isRunning]));
		addColumn: ((TableColumn title: ''Pri'' width: 26 text: [:p | p priority printString]) align: #right; remoteKey: ''pri''; yourself);
		addColumn: (TableColumn title: ''Process'' flex: 1 text: [:p | p name]);
		addColumn: ((TableColumn title: ''State'' width: 70 text: [:p | p state]) styleBlock: [:p | #italic]; remoteKey: ''''; yourself);
		addColumn: (TableColumn title: ''CPU'' width: 78 draw: (TableView barCell: [:p | p cpu] text: [:p | p cpuString])).
	table labelBlock: [:p | p name]; remoteNameBlock: [:p | p pid printString].

Rows are role #row in snapshots, labelled by labelBlock, with the columns'' remoteKey words as state.'!

!TableView methodsFor: 'initialization'!
initialize
	super initialize.
	columns := OrderedCollection new
! !

!TableView methodsFor: 'columns'!
columns
	^columns
!
addColumn: aTableColumn
	columns add: aTableColumn.
	columnRects := nil.
	self invalidate.
	^aTableColumn
!
columnRectsFor: aWidth
	"Left and right x of each column for a row aWidth wide."
	| pad gap fixed flexSum x remaining rects |
	(columnRects notNil and: [columnsWidth = aWidth]) ifTrue: [^columnRects].
	pad := self paddingX.
	gap := 8.
	fixed := 0.
	flexSum := 0.
	columns do: [:c | c isFlexible ifTrue: [flexSum := flexSum + c flex] ifFalse: [fixed := fixed + c width]].
	remaining := aWidth - (2 * pad) - (gap * (columns size - 1 max: 0)) - fixed max: 0.
	x := pad.
	rects := columns collect: [:c |
		| w r |
		w := c isFlexible ifTrue: [remaining * c flex / flexSum] ifFalse: [c width].
		r := Array with: x with: x + w.
		x := x + w + gap.
		r].
	columnsWidth := aWidth.
	^columnRects := rects asArray
! !

!TableView methodsFor: 'geometry'!
headerHeight
	^self theme metric: #paneHeaderHeight
!
contentTop
	^self headerHeight
! !

!TableView methodsFor: 'drawing'!
drawHeaderStripOn: aCanvas
	| h rects |
	h := self headerHeight.
	aCanvas fillRect: (0 @ 0 corner: self width @ (h - 1)) color: self theme paper.
	aCanvas fillRect: (0 @ (h - 1) corner: self width @ h) color: self theme rule.
	rects := self columnRectsFor: self rowsWidth.
	columns doWithIndex: [:c :i |
		| r |
		r := ((rects at: i) first @ 0) corner: ((rects at: i) last @ (h - 1)).
		aCanvas drawString: c title in: r font: (self theme font: #header) color: self theme ink align: c align]
!
drawItem: anItem in: r on: aCanvas inverted: inverted
	| rects |
	rects := self columnRectsFor: r width.
	columns doWithIndex: [:c :i |
		| cr styles font color |
		cr := ((r left + (rects at: i) first) @ r top) corner: ((r left + (rects at: i) last) @ r bottom).
		c drawBlock isNil
			ifTrue: [
				styles := c stylesOf: anItem.
				font := self labelFontFor: styles.
				color := inverted
					ifTrue: [(styles includes: #muted) ifTrue: [self theme color: #inverseMuted] ifFalse: [self theme paper]]
					ifFalse: [
						(styles includes: #accent)
							ifTrue: [self theme ultramarine]
							ifFalse: [(styles includes: #muted) ifTrue: [self theme muted] ifFalse: [self theme ink]]].
				aCanvas clip: cr during: [
					aCanvas drawString: (c textOf: anItem) in: cr font: font color: color align: c align]]
			ifFalse: [c drawBlock value: aCanvas value: cr value: anItem value: inverted]]
! !

!TableView methodsFor: 'remote control'!
remoteRowRole
	^#row
!
remotePartFor: index
	| part extra |
	part := super remotePartFor: index.
	remoteStateBlock notNil ifTrue: [^part].
	extra := OrderedCollection new.
	columns do: [:c |
		c remoteKey isNil ifFalse: [
			| t |
			t := c textOf: (items at: index).
			t isEmpty ifFalse: [extra add: (c remoteKey isEmpty ifTrue: [t] ifFalse: [c remoteKey, '=', t])]]].
	part state: extra asArray , part remoteState.
	^part
! !

!TableView class methodsFor: 'cell renderers'!
barCell: fractionBlock text: textBlock
	"A drawBlock for a load column: a 5-point framed track filled to the fraction (0..1) fractionBlock answers, and the text textBlock answers right-aligned after it."
	^[:canvas :rect :item :inverted |
		| theme fraction track fg text tw |
		theme := Theme current.
		fg := inverted ifTrue: [theme paper] ifFalse: [theme ink].
		text := (textBlock value: item) ifNil: [''].
		tw := 38.
		track := rect left @ (rect top + (rect height - 5 / 2)) extent: (rect width - tw - 4 max: 8) @ 5.
		fraction := ((fractionBlock value: item) ifNil: [0]) max: 0.
		canvas strokeRect: track color: fg width: 1.
		canvas fillRect: (track origin extent: (track width * (fraction min: 1)) @ track height) color: fg.
		canvas drawString: text asString in: ((rect right - tw) @ rect top corner: rect corner)
			font: (theme font: #mono11) color: fg align: #right]
!
squareDotCell: aBlock
	"A drawBlock for a 6-point state square: filled when aBlock answers true, ultramarine for #busy, open otherwise."
	^[:canvas :rect :item :inverted |
		| theme state r |
		theme := Theme current.
		state := aBlock value: item.
		r := rect left @ (rect top + (rect height - 6 / 2)) extent: 6 @ 6.
		state == #busy
			ifTrue: [canvas fillRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme ultramarine])]
			ifFalse: [
				state == true
					ifTrue: [canvas fillRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme ink])]
					ifFalse: [
						canvas fillRect: r color: (inverted ifTrue: [theme ink] ifFalse: [theme paper]).
						canvas strokeRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme ink]) width: 1]]]
! !
