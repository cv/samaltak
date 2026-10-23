ListView subclass: #ProfilerProcessList
	instanceVariableNames: 'idleProcess shown from glideT glide fits style rowDrawings'
	classVariableNames: ''
	package: 'Tools'!

ProfilerProcessList comment: 'I am the Profiler window''s Processes list: rows {key. label. samples. percent} from ProfilerData>>summary — All but idle (bold, ruled off), then each sampled Process with a window icon if it belongs to a window, a small bar and its share of the samples. Terminated Processes are italic, idle is muted. Live refreshes keep the rows in place unless a Process gets busier than the one above it by more than about 6%, and when a share changes by 4 points or more the bars and percentages glide to the new values in 120 ms.'!

!ProfilerProcessList methodsFor: 'accessing'!
idleProcess: aProcess
	idleProcess := aProcess
!
rows: anArray selectedKey: aKey
	"Show anArray (summary rows) with the row of aKey selected, silently."
	| rows i |
	rows := self stableOrderOf: anArray.
	self forgetRowDrawingsBut: rows.
	self glideTo: rows.
	self items: rows.
	i := 0.
	rows doWithIndex: [:row :k | row first == aKey ifTrue: [i := k]].
	self selectionIndex: i
!
forgetRowDrawingsBut: rows
	"Drop the drawings of rows that are gone (their Processes may have terminated)."
	rowDrawings isNil ifTrue: [^self].
	rowDrawings do: [:d | (d keys reject: [:k | rows anySatisfy: [:row | row first == k]]) do: [:k | d removeKey: k]]
!
stableOrderOf: anArray
	"anArray's rows (the first stays first) in the order of my current rows, unless a row has more samples than the one above it by more than about 6%; new rows after the known ones."
	| ranks known fresh a |
	(anArray size < 2 or: [(self items ifNil: [#()]) isEmpty]) ifTrue: [^anArray].
	ranks := IdentityDictionary new.
	self items doWithIndex: [:row :k | ranks at: row first put: k].
	known := (anArray allButFirst select: [:row | ranks includesKey: row first]) asArray sort: [:x :y | (ranks at: x first) <= (ranks at: y first)].
	fresh := anArray allButFirst reject: [:row | ranks includesKey: row first].
	a := (known, fresh) asArray.
	2 to: a size do: [:i | | x w j |
		x := a at: i.
		w := x at: 3.
		j := i - 1.
		[j >= 1 and: [w > (((a at: j) at: 3) + (((a at: j) at: 3) // 16 max: 1))]] whileTrue: [
			a at: j + 1 put: (a at: j).
			j := j - 1].
		a at: j + 1 put: x].
	^(Array with: anArray first), a
!
glideTo: rows
	"Glide the shown percentages from where they are to rows' when one of them changed by 4 points or more."
	| now far |
	now := IdentityDictionary new.
	far := false.
	rows do: [:row | | old |
		old := self shownPercentOf: row.
		now at: row first put: old.
		((old - (row at: 4)) abs >= 4.0 and: [shown notNil and: [shown includesKey: row first]]) ifTrue: [far := true]].
	glide isNil ifFalse: [glide stop. glide := nil].
	shown := IdentityDictionary new.
	rows do: [:row | shown at: row first put: (row at: 4)].
	far ifFalse: [^glideT := 1].
	from := now.
	glideT := 0.
	glide := self tweenFrom: 0 to: 1 duration: 120 do: [:t |
		glideT := t.
		t >= 1 ifTrue: [glide := nil].
		self invalidate]
!
shownPercentOf: aRow
	"The percentage drawn for aRow now (between the old and the new value while gliding)."
	| target old |
	target := aRow at: 4.
	(glideT isNil or: [glideT >= 1 or: [from isNil]]) ifTrue: [^target].
	old := from at: aRow first ifAbsent: [^target].
	^old + (target - old * glideT)
!
selectedKey
	^self selection isNil ifTrue: [nil] ifFalse: [self selection first]
! !

!ProfilerProcessList methodsFor: 'drawing'!
drawSelfOn: aCanvas
	"Look the theme up once per redraw, not per row."
	| t |
	t := self theme.
	style := IdentityDictionary new.
	style at: #ink put: t ink; at: #paper put: t paper; at: #muted put: t muted; at: #ultramarine put: t ultramarine.
	#(#small #ui #uiBold #uiItalic) do: [:f | | font |
		font := t font: f.
		style at: f put: font.
		style at: (#(#smallHeight #uiHeight #uiBoldHeight #uiItalicHeight) at: (#(#small #ui #uiBold #uiItalic) indexOf: f)) put: font lineHeight].
	super drawSelfOn: aCanvas
!
drawItem: aRow in: r on: aCanvas inverted: inverted
	"Replay the row's last drawing while what it shows is the same (live refreshes change only some rows)."
	| key shows cached |
	style isNil ifTrue: [^self].
	key := aRow first.
	shows := Array with: aRow with: (self shownPercentOf: aRow) with: r with: key == idleProcess with: (key ~~ #all and: [key isTerminated]) with: (key ~~ #all and: [key window notNil]).
	rowDrawings isNil ifTrue: [rowDrawings := Array with: IdentityDictionary new with: IdentityDictionary new].
	cached := (rowDrawings at: (inverted ifTrue: [2] ifFalse: [1])) at: key ifAbsent: [nil].
	(cached notNil and: [cached first = shows and: [aCanvas replay: cached last]]) ifTrue: [^self].
	(rowDrawings at: (inverted ifTrue: [2] ifFalse: [1])) at: key put: (Array
		with: shows
		with: (aCanvas record: [self drawProcessRow: aRow in: r on: aCanvas inverted: inverted]))
!
drawProcessRow: aRow in: r on: aCanvas inverted: inverted
	| key x right pctFont pct barR fill ink paper font color label shown height pctWidth lineHeight |
	style isNil ifTrue: [^self].
	key := aRow first.
	ink := style at: #ink.
	paper := style at: #paper.
	x := r left + self paddingX.
	right := r right - self paddingX.
	height := r height.
	pctFont := style at: #small.
	shown := self shownPercentOf: aRow.
	pct := (ProfilerFormat oneDecimal: shown), '%'.
	pctWidth := pctFont widthOf: pct.
	aCanvas drawString: pct at: (right - pctWidth) @ (r top + (height - (style at: #smallHeight) / 2.0)) font: pctFont
		color: (inverted ifTrue: [paper] ifFalse: [(key == idleProcess) ifTrue: [style at: #muted] ifFalse: [ink]]).
	barR := (right - 44 - 6 - 30) @ (r top + ((height - 5) * 0.5)) rounded extent: 30 @ 5.
	aCanvas fillRect: barR color: (inverted ifTrue: [ink] ifFalse: [paper]).
	fill := (30 * (shown min: 100) / 100.0) max: ((aRow at: 3) > 0 ifTrue: [1] ifFalse: [0]).
	aCanvas fillLeft: barR left top: barR top right: barR left + fill bottom: barR bottom
		color: (inverted
			ifTrue: [paper]
			ifFalse: [(key == #all or: [key == idleProcess]) ifTrue: [ink] ifFalse: [style at: #ultramarine]]).
	aCanvas strokeRect: barR color: (inverted ifTrue: [paper] ifFalse: [ink]) width: 1.
	right := barR left - 6.
	(key ~~ #all and: [key window notNil]) ifTrue: [
		self drawWindowIconAt: x @ (r top + ((height - 10) * 0.5)) rounded on: aCanvas color: (inverted ifTrue: [paper] ifFalse: [ink]).
		x := x + 15].
	font := style at: #ui.
	lineHeight := style at: #uiHeight.
	color := inverted ifTrue: [paper] ifFalse: [ink].
	key == #all ifTrue: [font := style at: #uiBold. lineHeight := style at: #uiBoldHeight].
	key == idleProcess ifTrue: [inverted ifFalse: [color := style at: #muted]].
	(key ~~ #all and: [key isTerminated]) ifTrue: [
		font := style at: #uiItalic.
		lineHeight := style at: #uiItalicHeight.
		inverted ifFalse: [color := style at: #muted]].
	label := self fit: (aRow at: 2) font: font width: right - x.
	aCanvas drawString: label at: x @ (r top + (height - lineHeight / 2.0)) font: font color: color.
	(key == #all and: [inverted not]) ifTrue: [
		aCanvas fillLeft: r left top: r bottom - 1 right: r right bottom: r bottom color: ink]
!
fit: aString font: aFont width: points
	"ProfilerFormat fit:font:width:, remembered (labels and widths rarely change)."
	| key cached |
	fits isNil ifTrue: [fits := Dictionary new].
	key := Array with: aString with: aFont with: points.
	cached := fits at: key ifAbsent: [nil].
	cached isNil ifFalse: [^cached].
	fits size > 500 ifTrue: [fits := Dictionary new].
	^fits at: key put: (ProfilerFormat fit: aString font: aFont width: points)
!
drawWindowIconAt: aPoint on: aCanvas color: aColor
	"A 10-point window: frame and title bar."
	| r |
	r := aPoint extent: 11 @ 10.
	aCanvas strokeRect: r color: aColor width: 1.
	aCanvas fillRect: (r left @ (r top + 3) corner: r right @ (r top + 4)) color: aColor
! !
