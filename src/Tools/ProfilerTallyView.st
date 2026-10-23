Widget subclass: #ProfilerTallyView
	instanceVariableNames: 'profiler lines open offset scrollBar hoverLine memoryText memoryKey memoryTime'
	classVariableNames: ''
	package: 'Tools'!

ProfilerTallyView comment: 'I show the Profiler window''s data as a Squeak MessageTally report in monospace: a header (tallies, msec, idle share, sampling rate, range), **Tree** (per Process, the call tree with percentages and msec; rows above 2% start expanded, ▸/▾ toggles a row), **Leaves**, and the **Memory** and **GCs** summaries of the Profile. A click on a method picks it (status bar), a double click opens it in a System Browser. Lines are Arrays {kind. text. node. depth. hasChildren. isOpen. pathKey}; kinds #header #dim #blank #section #rule #process #node #leaf #plain.'!

!ProfilerTallyView methodsFor: 'initialization'!
initialize
	super initialize.
	lines := #().
	open := Dictionary new.
	offset := 0.
	scrollBar := ScrollBar new client: self; yourself.
	scrollBar setVisible: false.
	self addChild: scrollBar
! !

!ProfilerTallyView methodsFor: 'accessing'!
profiler: aProfilerView
	profiler := aProfilerView
!
lines
	^lines
!
text
	"Answer the report as one String."
	^String new: 4000 streamContents: [:s |
		lines do: [:l | s nextPutAll: (self plainTextOf: l); nextPut: Character lf]]
!
plainTextOf: aLine
	(aLine first == #node) ifFalse: [^aLine at: 2].
	^(self guidesFor: (aLine at: 4)), ((aLine at: 5) ifTrue: [(aLine at: 6) ifTrue: [self openGlyph] ifFalse: [self closedGlyph]] ifFalse: [' ']), (aLine at: 2)
!
lineHeight
	^17
!
font
	^self theme font: #code12
!
openGlyph
	^'▾'
!
closedGlyph
	^'▸'
!
guidesFor: depth
	^String new: depth * 3 streamContents: [:s | depth timesRepeat: [s nextPutAll: '  |']]
! !

!ProfilerTallyView methodsFor: 'building'!
rebuild
	"Rebuild the report from my profiler's data."
	| data root total ms out all span |
	data := profiler data.
	data isNil ifTrue: [lines := #(). ^self invalidate].
	root := data cpuTree.
	total := root weight.
	ms := data microsPerSample / 1000.0.
	all := data filter == #all.
	span := data rangeStop - data rangeStart.
	out := OrderedCollection new.
	out add: (self line: #header text: ' - ', total asStringWithCommas, ' tallies, ', (total * ms) rounded asStringWithCommas, ' msec.',
		(all ifTrue: ['  (idle excluded: ', (ProfilerFormat percentString: data totalSamples - data busySamples of: data totalSamples), ')'] ifFalse: [''])).
	out add: (self line: #dim text: '   sampled at ', (self rateString: data profiler interval), ' over ', (ProfilerFormat seconds: span),
		(data range isNil ifTrue: [' (whole ring)'] ifFalse: [' (selected range)'])).
	out add: (self line: #blank text: '').
	out add: (self line: #section text: '**Tree**').
	(all ifTrue: [root stableChildren] ifFalse: [Array with: root]) do: [:procNode |
		out add: (self line: #rule text: '--------------------------------').
		out add: (self line: #process text: 'Process: (', (procNode process isNil ifTrue: ['?'] ifFalse: [procNode process priority printString]), ') ',
			(procNode process isNil ifTrue: ['?'] ifFalse: [procNode process identityHash printString]), ': ',
			(procNode process isNil ifTrue: [procNode name] ifFalse: [data labelFor: procNode process])).
		out add: (self line: #rule text: '--------------------------------').
		self addNodes: procNode stableChildren depth: 0 path: procNode name total: total ms: ms to: out].
	out add: (self line: #blank text: '').
	out add: (self line: #section text: '**Leaves**').
	(data leaves first: (data leaves size min: 14)) do: [:a |
		(total > 0 and: [a value * 100.0 / total >= 0.5]) ifTrue: [
			out add: {#leaf.
				(self percentOf: a value total: total width: 5), ' {', (a value * ms) rounded asStringWithCommas, 'ms} ', a key label.
				a key. 0. false. false. nil}]].
	(self memoryTextFor: data) lines do: [:l |
		(l beginsWith: '**')
			ifTrue: [out add: (self line: #section text: l)]
			ifFalse: [out add: (self line: (l isEmpty ifTrue: [#blank] ifFalse: [#plain]) text: (self expandTabs: l))]].
	lines := out asArray.
	self clampOffset.
	self layout.
	self invalidate
!
memoryTextFor: data
	"The **Memory** and **GCs** sections of data's range and filter, made again at most once a second (they follow VM statistics checkpoints)."
	| key now profile |
	key := Array with: data filter with: data range with: data isFrozen.
	now := Time millisecondClockValue.
	(memoryText notNil and: [memoryKey = key and: [now - memoryTime < 1000 or: [data isFrozen]]]) ifTrue: [^memoryText].
	profile := data memoryProfile.
	memoryText := String new: 1000 streamContents: [:s | profile printMemoryOn: s. profile printGCsOn: s].
	memoryKey := key.
	memoryTime := now.
	^memoryText
!
addNodes: nodes depth: depth path: pathKey total: total ms: ms to: out
	nodes do: [:node | | key kids isOpen |
		(total > 0 and: [node weight * 100.0 / total >= 0.5]) ifTrue: [
			key := pathKey, (String with: Character lf), node name.
			kids := node stableChildren anySatisfy: [:k | k weight * 100.0 / total >= 0.5].
			isOpen := open at: key ifAbsent: [node weight * 100.0 / total >= 2.0].
			out add: {#node.
				(self percentOf: node weight total: total width: (depth = 0 ifTrue: [5] ifFalse: [4])), ' {', (node weight * ms) rounded asStringWithCommas, 'ms} ', node name.
				node. depth. kids. isOpen. key}.
			(kids and: [isOpen]) ifTrue: [
				self addNodes: node stableChildren depth: depth + 1 path: key total: total ms: ms to: out]]]
!
line: kind text: aString
	^{kind. aString. nil. 0. false. false. nil}
!
percentOf: weight total: total width: width
	| s |
	s := (ProfilerFormat percent: weight of: total), '%'.
	^(String new: (width + 1 - s size max: 0) withAll: $ ), s
!
rateString: intervalMicros
	intervalMicros = 1000 ifTrue: [^'1 kHz'].
	^(1000000 / intervalMicros) rounded printString, ' Hz'
!
expandTabs: aString
	"Tabs to 8-column stops (the Memory and GCs lines are tab-separated)."
	^String new: aString size + 16 streamContents: [:s | | col |
		col := 0.
		aString do: [:c |
			c = Character tab
				ifTrue: [[s nextPut: $ . col := col + 1. col \\ 8 = 0] whileFalse]
				ifFalse: [s nextPut: c. col := col + 1]]]
!
toggle: aLine
	| node |
	node := aLine at: 3.
	(aLine first == #node and: [aLine at: 5]) ifFalse: [^self].
	open at: (aLine at: 7) put: (aLine at: 6) not.
	self rebuild
! !

!ProfilerTallyView methodsFor: 'scrolling'!
scrollTotal
	^lines size * self lineHeight + 16
!
scrollVisible
	^self height
!
scrollOffset
	^offset
!
scrollOffset: points
	offset := ((points min: self scrollTotal - self height) max: 0).
	self invalidate
!
clampOffset
	offset := ((offset min: self scrollTotal - self height) max: 0)
!
layout
	| bar |
	bar := self theme metric: #scrollBarWidth.
	self clampOffset.
	scrollBar setVisible: self scrollTotal > self height.
	scrollBar bounds: ((self width - bar) @ 0 corner: self width @ self height)
! !

!ProfilerTallyView methodsFor: 'geometry'!
lineIndexAt: aPoint
	| i |
	i := ((aPoint y + offset - 6) / self lineHeight) floor + 1.
	^(i between: 1 and: lines size) ifTrue: [i] ifFalse: [0]
!
lineTop: index
	^6 + ((index - 1) * self lineHeight) - offset
!
nameStartOf: aLine
	"The x where the method name starts."
	| adv prefix |
	adv := self font widthOf: 'M'.
	aLine first == #node ifTrue: [
		prefix := (self guidesFor: (aLine at: 4)), ' ', ((aLine at: 2) copyFrom: 1 to: ((aLine at: 2) indexOf: $}) + 1).
		^12 + (prefix size * adv)].
	aLine first == #leaf ifTrue: [^12 + ((((aLine at: 2) indexOf: $}) + 1) * adv)].
	^nil
!
toggleXOf: aLine
	^12 + ((aLine at: 4) * 3 * (self font widthOf: 'M'))
! !

!ProfilerTallyView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| font bold adv first last ink picked |
	aCanvas fillRect: self localBounds color: self theme paper.
	font := self font.
	bold := self theme font: #code12Bold.
	adv := font widthOf: 'M'.
	ink := self theme ink.
	picked := profiler isNil ifTrue: [nil] ifFalse: [profiler picked].
	first := (self lineIndexAt: 0 @ 0) max: 1.
	last := ((self height + offset - 6) / self lineHeight) ceiling min: lines size.
	first to: last do: [:i | | l y x text kind |
		l := lines at: i.
		kind := l first.
		y := self lineTop: i.
		x := 12.
		i = hoverLine ifTrue: [aCanvas fillRect: (0 @ (y + self lineHeight - 1) corner: self width @ (y + self lineHeight)) color: ink].
		kind == #node
			ifTrue: [ | guides name nameX |
				guides := self guidesFor: (l at: 4).
				aCanvas drawString: guides at: x @ y font: font color: (self theme color: #ink4).
				x := x + (guides size * adv).
				(l at: 5) ifTrue: [aCanvas drawString: ((l at: 6) ifTrue: [self openGlyph] ifFalse: [self closedGlyph]) at: x @ y font: font color: ink].
				x := x + adv.
				text := l at: 2.
				nameX := (text indexOf: $}) + 1.
				aCanvas drawString: (text copyFrom: 1 to: nameX) at: x @ y font: font color: ink.
				self drawName: (text copyFrom: nameX + 1 to: text size) at: (x + (nameX * adv)) @ y picked: ((l at: 3) frame == picked and: [picked notNil]) font: font on: aCanvas]
			ifFalse: [
				kind == #leaf
					ifTrue: [ | nameX |
						text := l at: 2.
						nameX := (text indexOf: $}) + 1.
						aCanvas drawString: (text copyFrom: 1 to: nameX) at: x @ y font: font color: ink.
						self drawName: (text copyFrom: nameX + 1 to: text size) at: (x + (nameX * adv)) @ y picked: ((l at: 3) == picked and: [picked notNil]) font: font on: aCanvas]
					ifFalse: [
						aCanvas drawString: (l at: 2) at: x @ y
							font: ((kind == #section or: [kind == #process]) ifTrue: [bold] ifFalse: [font])
							color: ((kind == #dim or: [kind == #rule]) ifTrue: [self theme muted] ifFalse: [(kind == #header) ifTrue: [self theme color: #ink2] ifFalse: [ink]])]]]
!
drawName: aString at: aPoint picked: aBoolean font: font on: aCanvas
	aBoolean ifTrue: [
		aCanvas fillRect: ((aPoint x - 2) @ aPoint y extent: ((font widthOf: aString) + 4) @ self lineHeight) color: self theme ink.
		^aCanvas drawString: aString at: aPoint font: font color: self theme paper].
	aCanvas drawString: aString at: aPoint font: font color: self theme ink
! !

!ProfilerTallyView methodsFor: 'events'!
mouseDown: anEvent
	| p i l nameX node frame |
	anEvent button = 1 ifFalse: [^false].
	p := self localEventPosition: anEvent.
	i := self lineIndexAt: p.
	i = 0 ifTrue: [^true].
	l := lines at: i.
	(l first == #node or: [l first == #leaf]) ifFalse: [^true].
	(l first == #node and: [(l at: 5) and: [p x between: (self toggleXOf: l) - 4 and: (self toggleXOf: l) + (self font widthOf: 'M') + 4]])
		ifTrue: [self toggle: l. ^true].
	nameX := self nameStartOf: l.
	p x >= nameX ifFalse: [^true].
	node := l first == #node ifTrue: [l at: 3] ifFalse: [nil].
	frame := l first == #node ifTrue: [node frame] ifFalse: [l at: 3].
	frame isNil ifTrue: [^true].
	profiler isNil ifTrue: [^true].
	profiler pickFrame: frame.
	(anEvent clickCount >= 2 or: [anEvent modifiers commandKey]) ifTrue: [profiler browseFrame: frame].
	^true
!
mouseUp: anEvent
	^true
!
mouseMove: anEvent
	| i |
	i := self lineIndexAt: (self localEventPosition: anEvent).
	i ~= hoverLine ifTrue: [hoverLine := i. self invalidate].
	^true
!
mouseLeave: anEvent
	hoverLine := nil.
	self invalidate.
	^false
!
wheel: anEvent
	self scrollOffset: offset - (anEvent delta y * 40).
	^true
!
cursorAt: aPoint
	| i l |
	i := self lineIndexAt: aPoint.
	i = 0 ifTrue: [^#arrow].
	l := lines at: i.
	(l first == #node or: [l first == #leaf]) ifFalse: [^#arrow].
	^#hand
! !

!ProfilerTallyView methodsFor: 'remote control'!
remoteRole
	^#tally
!
remoteLabel
	^lines isEmpty ifTrue: [nil] ifFalse: [(lines first at: 2) trimBoth]
!
remoteState
	^Array with: 'lines=', lines size printString
!
remoteText
	^self text
!
remoteChildren
	| parts |
	parts := OrderedCollection new.
	lines doWithIndex: [:l :i | | kind role label part |
		kind := l first.
		role := kind == #node ifTrue: [#'tally-node'] ifFalse: [kind == #leaf ifTrue: [#'tally-leaf'] ifFalse: [kind == #section ifTrue: [#'tally-section'] ifFalse: [nil]]].
		role isNil ifFalse: [
			label := kind == #node
				ifTrue: [(l at: 3) name, ' ', ((l at: 2) copyFrom: 1 to: ((l at: 2) indexOf: $%)) trimBoth]
				ifFalse: [kind == #leaf ifTrue: [(l at: 3) label, ' ', ((l at: 2) copyFrom: 1 to: ((l at: 2) indexOf: $%)) trimBoth] ifFalse: [l at: 2]].
			part := WidgetPart of: self role: role label: label
				state: ((kind == #node and: [l at: 5]) ifTrue: [(l at: 6) ifTrue: [#(#open)] ifFalse: [#(#closed)]] ifFalse: [#()])
				rect: (((self lineTop: i) between: 0 and: self height - self lineHeight)
					ifTrue: [(self nameStartOf: l) isNil
						ifTrue: [0 @ (self lineTop: i) extent: self width @ self lineHeight]
						ifFalse: [(self nameStartOf: l) @ (self lineTop: i) corner: self width @ ((self lineTop: i) + self lineHeight)]]
					ifFalse: [nil]).
			kind == #section ifFalse: [part name: label].
			parts add: part]].
	^parts asArray
! !
