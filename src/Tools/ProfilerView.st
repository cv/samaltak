Widget subclass: #ProfilerView
	instanceVariableNames: 'data filter tab selection selectedBar span bigEnd picked pickLabel tipLines tipPoint timer refreshMicros live nextTick refreshCount summaryKey summaryTime bindings pauseButton markButton tabs ringStats captureLabel processList stripHeader overview views tallyView flameHeader flame allocHeader allocFlame sites framesHeader spanToggle timeline record evaluator statusBar stale'
	classVariableNames: ''
	package: 'Tools'!

ProfilerView comment: 'I am the Profiler window (docs/design.md, Debugging and profiling): a view onto the always-on sampling profiler. Ten times a second (unless capture is paused or a range is pinned) I catch up with the profiler (ProfilerLive: aggregates that fold in only what was recorded since, and drop what left the ring) and redraw; a pinned range freezes the data (ProfilerData>>frozen). Left: the Processes with their share of the samples; selecting one filters every view. Top: the FRAMES overview of the whole ring; dragging in it (or in the Frames timeline) selects and pins a range, a click selects one frame. Tabs: Tally (MessageTally text), Flame graph (CPU samples; click zooms, double click browses), Allocations (the same by bytes, and the top allocating sites) and Frames (frame timeline, frame records). Bottom: an evaluator where profile data are objects (Profiler last samples groupBy: #method, ⌘P prints), and the status bar.

	ProfilerView open.
	ProfilerView openSelecting: aProcess.'!

!ProfilerView methodsFor: 'initialization'!
initialize
	super initialize.
	filter := #all.
	tab := #flame.
	span := 2000000.
	stale := Set new.
	bindings := Dictionary new.
	self build
!
build
	| toolbar left right main evalPane stack |
	pauseButton := Button label: 'Pause' action: [self togglePause].
	pauseButton name: 'pause'; tooltip: 'pause / resume capture (the ring keeps its data)'.
	markButton := Button label: 'Mark' action: [self dropMark].
	markButton name: 'mark'; tooltip: 'drop a marker into the timeline'.
	tabs := Tabs options: (Array with: #tally -> 'Tally' with: #flame -> 'Flame graph' with: #alloc -> 'Allocations' with: #frames -> 'Frames').
	tabs name: 'tabs'; selection: tab; onChange: [:key | self showTab: key].
	ringStats := Label new font: #smallItalic; color: #ink3; align: #right; name: 'ring-stats'; fixed: 330; yourself.
	captureLabel := Label new font: #smallItalic; align: #right; name: 'capture'; yourself.
	captureLabel text: self captureText.
	toolbar := Row with: {pauseButton sizeToContent. markButton sizeToContent. (ProfilerSpacer new fixed: 6). tabs sizeToContent. ProfilerSpacer new. ringStats. captureLabel fixed: 76}.
	toolbar spacing: 6; padding: (8 @ 5 corner: 8 @ 5).
	processList := ProfilerProcessList new title: 'Processes'; name: 'processes'; yourself.
	processList labelBlock: [:row | row at: 2];
		remoteStateBlock: [:row | Array with: 'pct=', ((row at: 4) printShowingDecimalPlaces: 1), '%'];
		onSelect: [:row | row isNil ifFalse: [self selectFilter: row first]].
	left := Column with: {PaneHeader title: 'Processes' right: 'of samples'. processList}.
	stripHeader := ProfilerHeader new title: 'Frames'; yourself.
	overview := ProfilerTimeline new profiler: self; detailed: false; name: 'frame-overview'; yourself.
	views := Dictionary new.
	views at: #tally put: self buildTally.
	views at: #flame put: self buildFlame.
	views at: #alloc put: self buildAllocations.
	views at: #frames put: self buildFrames.
	stack := Stack with: (#(#tally #flame #alloc #frames) collect: [:k | views at: k]).
	views keysAndValuesDo: [:k :v | v setVisible: k == tab].
	right := Column with: {stripHeader. overview fixed: 57. ProfilerRule new. stack}.
	main := Row with: {left fixed: 214. right}.
	main separators: true.
	evaluator := TextEditor new title: 'evaluate'; name: 'evaluate'; yourself.
	evaluator text: self defaultEvaluatorText.
	evaluator onPrintIt: [:text :interval :editor | self evaluate: text print: true];
		onDoIt: [:text :interval :editor | self evaluate: text print: false].
	evalPane := Column with: {PaneHeader title: 'Evaluate' right: 'profile data are objects', ProfilerFormat dot, '⌘', 'P print it'. evaluator}.
	statusBar := ProfilerStatusBar new name: 'status'; yourself.
	statusBar clearButton action: [self clearRange].
	statusBar browseButton action: [picked isNil ifFalse: [self browseFrame: picked]].
	self addChild: (Column with: {toolbar fixed: 30. ProfilerRule new. main. ProfilerRule new. evalPane fixed: 99. statusBar})
!
buildTally
	tallyView := ProfilerTallyView new profiler: self; name: 'tally-tree'; yourself.
	^Column with: {ProfilerHeader new title: 'MessageTally'; rightText: 'click ', '▸', ' to expand', ProfilerFormat dot, 'double-click a method to browse'; yourself. tallyView}
!
buildFlame
	flameHeader := ProfilerHeader new title: 'Flame graph'; name: 'flame-header'; rightText: 'click: zoom', ProfilerFormat dot, 'double-click: browse'; yourself.
	flameHeader onCrumb: [:i | flame zoomToDepth: i - 1].
	flame := ProfilerFlameGraph new profiler: self; unit: #samples; name: 'flame-graph'; yourself.
	^Column with: {flameHeader. flame}
!
buildAllocations
	allocHeader := ProfilerHeader new title: 'Allocations'; name: 'allocation-header'; yourself.
	allocHeader onCrumb: [:i | allocFlame zoomToDepth: i - 1].
	allocFlame := ProfilerFlameGraph new profiler: self; unit: #bytes; name: 'allocation-graph'; yourself.
	allocFlame emptyText: 'No allocation samples for this Process in the selected range.'.
	sites := TableView new title: 'Top allocating sites'; name: 'alloc-sites'; yourself.
	sites addColumn: ((TableColumn title: 'bytes' width: 62 text: [:s | ProfilerFormat bytes: s bytes]) align: #right; yourself);
		addColumn: ((TableColumn title: '%' width: 46 text: [:s | ProfilerFormat percentString: s bytes of: self allocationTotal]) align: #right; yourself);
		addColumn: ((TableColumn title: 'class' width: 150 text: [:s | s allocatedClass isNil ifTrue: ['?'] ifFalse: [s allocatedClass name]]) styleBlock: [:s | #accent]; yourself);
		addColumn: (TableColumn title: 'site' flex: 1 text: [:s | s frame isNil ifTrue: ['?'] ifFalse: [s frame label]]);
		addColumn: ((TableColumn title: 'Process' width: 90 text: [:s | s process isNil ifTrue: ['?'] ifFalse: [Profiler labelFor: s process]]) styleBlock: [:s | #italic]; yourself).
	sites labelBlock: [:s | s frame isNil ifTrue: ['?'] ifFalse: [s frame label]];
		emptyText: 'No allocation samples in range.';
		onSelect: [:s | (s notNil and: [s frame notNil]) ifTrue: [self pickFrame: s frame]];
		onDoubleClick: [:s | s frame isNil ifFalse: [self browseFrame: s frame]].
	^Column with: {allocHeader. allocFlame. ProfilerRule new. PaneHeader title: 'Top allocating sites'. sites fixed: 116}
!
buildFrames
	spanToggle := ToggleGroup options: (Array with: 2000000 -> '2 s' with: 5000000 -> '5 s' with: 0 -> 'all').
	spanToggle name: 'span'; selection: span; onChange: [:key | self setSpan: key].
	framesHeader := ProfilerHeader new title: 'Frame timeline'; name: 'timeline-header'; legend: true; yourself.
	framesHeader rightWidget: spanToggle.
	timeline := ProfilerTimeline new profiler: self; detailed: true; name: 'frame-timeline'; yourself.
	record := ProfilerRecordView new name: 'frame-record'; yourself.
	^Column with: {framesHeader. timeline. record fixed: 92}
!
defaultEvaluatorText
	^'Profiler last samples groupBy: #method
Profiler last frames detectMax: [:f | f duration]
Profiler mark: ''before zoom'''
! !

!ProfilerView methodsFor: 'accessing'!
data
	^data
!
filter
	^filter
!
tab
	^tab
!
selectionRange
	^selection
!
selectedBar
	^selectedBar
!
isPinned
	^selection notNil
!
picked
	"Answer the picked ProfileFrame (or Process), or nil."
	^picked
!
flame
	^flame
!
allocationFlame
	^allocFlame
!
tallyView
	^tallyView
!
timeline
	^timeline
!
overview
	^overview
!
processList
	^processList
!
evaluator
	^evaluator
!
statusBar
	^statusBar
!
recordView
	^record
!
sites
	^sites
!
refreshMicros
	"Answer how long the last refresh took (µs)."
	^refreshMicros
!
allocationTotal
	^data isNil ifTrue: [0] ifFalse: [data allocationTree weight]
!
captureText
	^Profiler default isRunning
		ifTrue: ['■', ' capturing']
		ifFalse: ['□', ' paused']
! !

!ProfilerView methodsFor: 'windows'!
overviewWindow
	"The whole snapshot: {oldest. now} (µs)."
	data isNil ifTrue: [^Array with: 0 with: 1].
	^Array with: data oldest with: data now
!
detailWindow
	| e |
	data isNil ifTrue: [^Array with: 0 with: 1].
	(span isNil or: [span = 0]) ifTrue: [^self overviewWindow].
	e := bigEnd ifNil: [data now].
	^Array with: e - span with: e
! !

!ProfilerView methodsFor: 'live updates'!
start
	"Take the first snapshot and refresh ten times a second (in my window's Process)."
	self refresh.
	self scheduleTick
!
scheduleTick
	"Keep the phase: a refresh that took longer delays the next one less."
	| w now |
	w := self window.
	w isNil ifTrue: [^self].
	now := Time millisecondClockValue.
	nextTick := (nextTick isNil or: [now - nextTick > self tickInterval])
		ifTrue: [now + self tickInterval]
		ifFalse: [nextTick + self tickInterval].
	timer := w after: (nextTick - now max: 10) do: [self tick]
!
tickInterval
	"Answer the ms between live refreshes: 100 (10 Hz). A refresh costs about what was recorded since the previous one, so this holds with a full ring. The Tally tab, a text report of every call path, refreshes 4 times a second."
	^tab == #tally ifTrue: [250] ifFalse: [100]
!
tick
	| w |
	w := self window.
	(w isNil or: [w isOpen not]) ifTrue: [^self].
	(self isPinned not and: [Profiler default isRunning and: [w isCollapsed not]]) ifTrue: [self refresh].
	self scheduleTick
!
stop
	timer isNil ifFalse: [timer cancel. timer := nil]
!
refresh
	"Catch up with the profiler (unless a range is pinned) and update every visible view."
	| t0 |
	t0 := Time microsecondClockValue.
	(data isNil or: [self isPinned not]) ifTrue: [
		(live isNil or: [live profiler ~~ Profiler default]) ifTrue: [live := ProfilerLive on: Profiler default].
		live update.
		data := ProfilerData live: live filter: filter range: nil.
		self isPinned ifTrue: [data := data frozen]].
	self updateViews.
	refreshCount := (refreshCount ifNil: [0]) + 1.
	refreshMicros := Time microsecondClockValue - t0
!
refreshCount
	"Answer how many refreshes I made."
	^refreshCount ifNil: [0]
!
freeze
	"A range is being pinned: stop following the profiler."
	(data notNil and: [data isFrozen not]) ifTrue: [data := data frozen]
!
updateViews
	data filter: filter; range: selection.
	stale := Set withAll: #(#tally #flame #alloc #frames).
	ringStats text: data ringStats.
	pauseButton label: (Profiler default isRunning ifTrue: ['Pause'] ifFalse: ['Resume']).
	captureLabel text: self captureText.
	processList idleProcess: data idleProcess.
	processList rows: data summary selectedKey: filter.
	self updateStripHeader.
	overview invalidate.
	self updateTab.
	self updateStatus
!
updateTab
	(stale includes: tab) ifFalse: [^self].
	stale remove: tab.
	tab == #tally ifTrue: [^tallyView rebuild].
	tab == #flame ifTrue: [^self updateFlame].
	tab == #alloc ifTrue: [^self updateAllocations].
	tab == #frames ifTrue: [^self updateFrames]
!
updateStripHeader
	| bars dropped |
	bars := data bars.
	dropped := data droppedCount.
	stripHeader rightText: bars size asStringWithCommas, ' frames', ProfilerFormat dot, dropped printString, ' dropped', ProfilerFormat dot, 'drag to select a range'
!
updateFlame
	flame root: data cpuTree.
	self updateCrumbs: flameHeader of: flame
!
updateAllocations
	| seconds |
	allocFlame root: data allocationTree.
	self updateCrumbs: allocHeader of: allocFlame.
	seconds := ((data rangeStop - data rangeStart) max: 1) / 1000000.0.
	allocHeader note: (ProfilerFormat bytes: allocFlame root weight), ProfilerFormat dot, (ProfilerFormat bytes: allocFlame root weight / seconds), '/s'.
	allocHeader rightText: 'sampled every ', (Profiler printBytes: data profiler allocationInterval), ' at the bump limit'.
	sites items: (data topSites: 8)
!
updateCrumbs: aHeader of: aFlameGraph
	| path |
	path := aFlameGraph zoomPath.
	aHeader crumbs: (path collect: [:n |
		n == aFlameGraph root
			ifTrue: [filter == #all ifTrue: ['all'] ifFalse: [n name]]
			ifFalse: [n isProcessNode ifTrue: ['''', (data labelFor: n process), ''''] ifFalse: [n name]]]).
	aHeader == flameHeader ifTrue: [
		aHeader note: (ProfilerFormat weight: aFlameGraph root weight unit: #samples)]
!
updateFrames
	framesHeader otherLabel: (filter == #all ifTrue: ['system'] ifFalse: ['others']).
	timeline invalidate.
	self updateRecord
!
updateStatus
	| now text |
	now := data now.
	text := selection isNil
		ifTrue: ['whole ring', ProfilerFormat dot, 'last ', (ProfilerFormat seconds: data now - data oldest), ProfilerFormat dot, 'live']
		ifFalse: ['range ', (ProfilerFormat seconds: now - selection first), ' ', '–', ' ',
			(ProfilerFormat seconds: now - selection last), ' ago (', (ProfilerFormat span: selection last - selection first), ')',
			ProfilerFormat dot, 'pinned'].
	statusBar rangeText: text pinned: selection notNil.
	statusBar pickText: (pickLabel ifNil: ['click a frame or method']) browsable: (picked isKindOf: ProfileFrame)
!
zoomChanged: aFlameGraph
	aFlameGraph == flame ifTrue: [self updateCrumbs: flameHeader of: flame].
	aFlameGraph == allocFlame ifTrue: [self updateCrumbs: allocHeader of: allocFlame]
! !

!ProfilerView methodsFor: 'actions'!
showTab: aSymbol
	tab := aSymbol.
	tabs selection: aSymbol.
	views keysAndValuesDo: [:k :v | v setVisible: k == aSymbol].
	(views at: aSymbol) owner layout.
	self hideTip.
	data isNil ifFalse: [self updateTab].
	self invalidate
!
selectFilter: aKey
	filter == aKey ifTrue: [^self].
	filter := aKey.
	processList selectedKey == aKey ifFalse: [processList rows: processList items selectedKey: aKey].
	flame resetZoomKeys.
	allocFlame resetZoomKeys.
	data isNil ifFalse: [self updateViews].
	self invalidate
!
togglePause
	Profiler default isRunning ifTrue: [Profiler pause] ifFalse: [Profiler resume].
	self refresh
!
dropMark
	| m |
	m := Profiler mark: 'mark ', (data isNil ifTrue: [1] ifFalse: [data marks size + 1]) printString.
	self toast: m label, ' ', '—', ' also from code: Profiler mark: ''label'''.
	self isPinned ifFalse: [self refresh]
!
setSpan: microseconds
	span := microseconds.
	(selection notNil and: [span > 0]) ifTrue: [self followSelection] ifFalse: [bigEnd := nil].
	timeline invalidate.
	self invalidate
!
dragRange: anArray final: isFinal refilter: aBoolean
	"A range dragged in a timeline: pin the snapshot, select the range."
	self freeze.
	selection := anArray.
	selectedBar := nil.
	isFinal ifTrue: [self followSelection].
	aBoolean
		ifTrue: [self updateViews. self invalidate]
		ifFalse: [overview invalidate. timeline invalidate. self updateStatus]
!
selectBar: aBar fromOverview: aBoolean
	self freeze.
	selectedBar := aBar.
	selection := Array with: aBar start with: aBar end.
	aBoolean ifTrue: [self followSelection].
	self updateViews.
	self invalidate
!
followSelection
	"Center the detailed timeline on the selection."
	selection isNil ifTrue: [^self].
	(span isNil or: [span = 0]) ifTrue: [^bigEnd := nil].
	bigEnd := data now min: selection last + (((span - (selection last - selection first)) max: 0) / 2)
!
clearRange
	selection := nil.
	selectedBar := nil.
	bigEnd := nil.
	self refresh.
	self invalidate
!
pickNode: aNode
	aNode isNil ifTrue: [^self].
	aNode isMethodNode
		ifTrue: [self pickFrame: aNode frame]
		ifFalse: [
			picked := aNode process.
			pickLabel := aNode name.
			self updateStatus.
			self invalidate]
!
pickFrame: aFrame
	picked := aFrame.
	pickLabel := aFrame label.
	self updateStatus.
	self invalidate
!
browseNode: aNode
	aNode isMethodNode ifFalse: [^self toast: aNode name, ' is not a method'].
	self browseFrame: aNode frame
!
browseFrame: aFrame
	| method |
	method := aFrame method.
	method isNil ifTrue: [^self toast: aFrame label, ' is not a method'].
	Tools browseMethod: method
! !

!ProfilerView methodsFor: 'frames'!
tipLinesForBar: aBar
	| rec |
	rec := aBar record.
	^Array
		with: 'Frame #', rec number printString, ProfilerFormat dot, (ProfilerFormat ms: aBar duration), (aBar isDropped ifTrue: [ProfilerFormat dot, 'dropped'] ifFalse: [''])
		with: (self topProcessesOf: rec count: 3)
		with: 'draw ', (ProfilerFormat ms: rec draw), ProfilerFormat dot, 'raster ', (ProfilerFormat ms: rec raster), ProfilerFormat dot,
			'GPU ', (ProfilerFormat ms: rec gpu), (rec gcCount > 0 ifTrue: [ProfilerFormat dot, 'GC ', (ProfilerFormat ms: rec gcMicros)] ifFalse: [''])
!
topProcessesOf: aFrameRecord count: n
	| ps |
	ps := aFrameRecord processes reject: [:p | (data isIdle: p) or: [ProfilerTimeline isCompositor: p]].
	ps isEmpty ifTrue: [^'idle'].
	^((ps first: (ps size min: n)) collect: [:p | (data labelFor: p), ' ', (ProfilerFormat ms: (aFrameRecord timeFor: p))])
		inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc, ProfilerFormat dot, each]]
!
updateRecord
	"The summary of the range's frames (median, p95 over up to a thousand frames) is made again at most once a second while live."
	| key now |
	selectedBar isNil ifFalse: [summaryKey := nil. ^self updateRecordFor: selectedBar].
	key := Array with: selection with: filter with: data isFrozen.
	now := Time millisecondClockValue.
	(summaryKey = key and: [data isFrozen or: [now - summaryTime < 1000]]) ifTrue: [^self].
	summaryKey := key.
	summaryTime := now.
	self updateRecordSummary
!
updateRecordFor: aBar
	| rec over head procs idle samples bytes frameProfile gcText |
	rec := aBar record.
	over := aBar duration - FrameRecord budgetMicros.
	head := OrderedCollection new.
	head add: (Array with: 'a FrameRecord ' with: #italic); add: (Array with: '#', rec number printString with: #bold);
		add: (Array with: ProfilerFormat dot, 'presented ', (ProfilerFormat seconds: data now - rec end), ' ago', ProfilerFormat dot with: #italic);
		add: (Array with: (ProfilerFormat ms: aBar duration) with: #bold);
		add: (Array with: (over > 500 ifTrue: [ProfilerFormat dot, 'over budget by ', (ProfilerFormat ms: over)] ifFalse: [ProfilerFormat dot, 'within budget']) with: #italic).
	aBar isDropped ifTrue: [head add: (Array with: ProfilerFormat dot with: #italic); add: (Array with: 'dropped' with: #drop)].
	procs := OrderedCollection new.
	(rec processes reject: [:p | (data isIdle: p) or: [ProfilerTimeline isCompositor: p]]) do: [:p |
		procs isEmpty ifFalse: [procs add: (Array with: ProfilerFormat dot with: #plain)].
		procs add: (Array with: (data labelFor: p), ' ' with: #plain); add: (Array with: (ProfilerFormat ms: (rec timeFor: p)) with: #bold)].
	idle := rec timeFor: data idleProcess.
	idle > 0 ifTrue: [procs add: (Array with: ProfilerFormat dot, 'idle ' with: #plain); add: (Array with: (ProfilerFormat ms: idle) with: #bold)].
	procs isEmpty ifTrue: [procs add: (Array with: 'none' with: #plain)].
	frameProfile := data profile from: aBar start to: aBar end.
	samples := frameProfile samples size.
	bytes := frameProfile allocations totalWeight.
	gcText := rec gcCount = 0
		ifTrue: [Array with: (Array with: 'none' with: #plain)]
		ifFalse: [Array with: (Array with: rec gcCount printString, (rec gcCount = 1 ifTrue: [' GC '] ifFalse: [' GCs ']) with: #plain) with: (Array with: (ProfilerFormat ms: rec gcMicros) with: #bold)].
	record heading: head asArray.
	record rows: (Array
		with: (Array with: 'Processes' with: procs asArray)
		with: (Array with: 'Compositor' with: (Array
			with: #('draw ' #plain) with: (Array with: (ProfilerFormat ms: rec draw) with: #bold)
			with: (Array with: ProfilerFormat dot, 'raster ' with: #plain) with: (Array with: (ProfilerFormat ms: rec raster) with: #bold)
			with: (Array with: ProfilerFormat dot, 'GPU ' with: #plain) with: (Array with: (ProfilerFormat ms: rec gpu) with: #bold)))
		with: (Array with: 'GC' with: gcText)
		with: (Array with: 'Samples' with: (Array
			with: (Array with: samples printString, ' CPU', ProfilerFormat dot, (ProfilerFormat bytes: bytes), ' allocated ', '—', ' flame graph and tally now show this frame' with: #plain))))
!
updateRecordSummary
	| bars times dropped worst gcs gcMicros head rows dropRuns n |
	bars := data barsInRange.
	times := (bars collect: [:b | b duration]) asArray sort: [:a :b | a < b].
	dropped := (bars select: [:b | b isDropped]) asArray.
	n := times size.
	gcs := bars inject: 0 into: [:sum :b | sum + b record gcCount].
	gcMicros := bars inject: 0 into: [:sum :b | sum + b record gcMicros].
	head := Array with: (Array with: (selection isNil ifTrue: ['Whole ring'] ifFalse: ['Selected range']), ProfilerFormat dot,
		n asStringWithCommas, ' frames over ', (ProfilerFormat seconds: data rangeStop - data rangeStart), ' ', '—',
		' click a bar for its record, drag to select' with: #italic).
	dropRuns := OrderedCollection new.
	dropRuns add: (Array with: dropped size printString, (dropped size = 1 ifTrue: [' frame'] ifFalse: [' frames']), ' over budget or not shown' with: #plain).
	dropped isEmpty ifFalse: [
		worst := dropped inject: dropped first into: [:m :b | b duration > m duration ifTrue: [b] ifFalse: [m]].
		dropRuns add: (Array with: ' ', '—', ' worst ' with: #plain); add: (Array with: (ProfilerFormat ms: worst duration) with: #bold);
			add: (Array with: ' while ', (self topProcessesOf: worst record count: 2) with: #plain)].
	data displayHidden ifTrue: [dropRuns add: (Array with: ProfilerFormat dot, 'display hidden: no frame shown' with: #italic)].
	rows := Array
		with: (Array with: 'Frame time' with: (n = 0
			ifTrue: [Array with: (Array with: '—' with: #plain)]
			ifFalse: [Array
				with: #('median ' #plain) with: (Array with: (ProfilerFormat ms: (times at: n + 1 // 2)) with: #bold)
				with: (Array with: ProfilerFormat dot, 'p95 ' with: #plain) with: (Array with: (ProfilerFormat ms: (times at: ((n * 0.95) ceiling max: 1))) with: #bold)
				with: (Array with: ProfilerFormat dot, 'worst ' with: #plain) with: (Array with: (ProfilerFormat ms: times last) with: #bold)]))
		with: (Array with: 'Dropped' with: dropRuns asArray)
		with: (Array with: 'GC' with: (Array with: (Array with: gcs printString, (gcs = 1 ifTrue: [' GC'] ifFalse: [' GCs']), ProfilerFormat dot, (ProfilerFormat ms: gcMicros), ' paused' with: #plain))).
	record heading: head.
	record rows: rows
! !

!ProfilerView methodsFor: 'evaluating'!
evaluate: aString print: aBoolean
	"Evaluate the evaluator's selection (or line); print the result after it."
	| result text interval failed |
	text := aString asString.
	text trimBoth isEmpty ifTrue: [^self].
	failed := nil.
	result := [Compiler evaluate: text for: nil bindings: bindings]
		on: Error do: [:e | failed := e messageText ifNil: [e class name]. e return: nil].
	failed notNil ifTrue: [
		interval := evaluator insertAfterSelection: ' ', '‹', failed asString, '›' select: true.
		evaluator addMark: interval style: #error.
		^self].
	aBoolean ifTrue: [
		interval := evaluator insertAfterSelection: ' ', (result printStringLimitedTo: 160) select: true.
		evaluator addMark: interval style: #result].
	self isPinned ifFalse: [self refresh]
! !

!ProfilerView methodsFor: 'tooltip'!
showTip: lines near: aPoint
	(tipLines = lines and: [tipPoint = aPoint]) ifTrue: [^self].
	tipLines := lines.
	tipPoint := aPoint.
	self invalidateOverlay
!
hideTip
	tipLines isNil ifTrue: [^self].
	tipLines := nil.
	self invalidateOverlay
!
tipLines
	^tipLines
!
drawOverlayOn: aCanvas
	| bold italic w h x y r |
	tipLines isNil ifTrue: [^self].
	bold := self theme font: #codeSmallBold.
	italic := self theme font: #smallItalic.
	w := bold widthOf: tipLines first.
	tipLines allButFirst do: [:l | w := w max: (italic widthOf: l)].
	w := (w + 16) min: 420.
	h := 10 + 17 + (tipLines size - 1 * 16).
	x := tipPoint x + 14.
	y := tipPoint y + 16.
	x + w > (self width - 6) ifTrue: [x := tipPoint x - w - 10].
	y + h > (self height - 6) ifTrue: [y := tipPoint y - h - 10].
	r := x @ y extent: w @ h.
	aCanvas fillRect: (r translateBy: 2 @ 2) color: self theme ink.
	aCanvas fillRect: r color: self theme paper.
	aCanvas strokeRect: r color: self theme ink width: 1.
	aCanvas clip: (r insetBy: 1) during: [
		aCanvas drawString: tipLines first at: (x + 8) @ (y + 5) font: bold color: self theme ink.
		tipLines allButFirst doWithIndex: [:l :i |
			aCanvas drawString: l at: (x + 8) @ (y + 6 + 17 + (i - 1 * 16)) font: italic color: self theme ink]]
! !

!ProfilerView methodsFor: 'layout'!
layout
	self children do: [:each | each bounds: self localBounds]
! !

!ProfilerView methodsFor: 'remote control'!
remoteRole
	^#profiler
!
remoteIsTransparent
	^true
! !

!ProfilerView class methodsFor: 'opening'!
open
	"Open the Profiler window (or bring the open one to the front)."
	^self openSelecting: nil
!
openSelecting: aProcessOrNil
	^self openSelecting: aProcessOrNil at: nil
!
openAt: aPointOrNil
	"From the World menu: near the desk click at aPointOrNil (like the prototype's at(): 30 left of and 10 above it, kept on the screen)."
	^self openSelecting: nil at: aPointOrNil
!
openSelecting: aProcessOrNil at: aPointOrNil
	| world existing view window extent origin |
	world := Desktop current.
	world isNil ifTrue: [^nil].
	existing := world windows detect: [:w | w content isKindOf: self] ifNone: [nil].
	existing notNil ifTrue: [
		world activate: existing.
		aProcessOrNil isNil ifFalse: [existing do: [existing content selectFilter: aProcessOrNil]].
		^existing].
	view := self new.
	aProcessOrNil isNil ifFalse: [view setFilter: aProcessOrNil].
	extent := 900 @ 660.
	origin := aPointOrNil isNil ifTrue: [100 @ (world desktopBounds top + 40)] ifFalse: [aPointOrNil - (30 @ 10)].
	origin := ((origin x min: world extent x - extent x - 8) max: 8) @ ((origin y min: world extent y - extent y - 8) max: world desktopBounds top + 8).
	window := Desktop newWindow title: 'Profiler'; content: view; bounds: (origin extent: extent); yourself.
	window minExtent: 620 @ 420.
	window whenClosed: [view stop].
	window open.
	window do: [view start].
	^window
! !

!ProfilerView class methodsFor: 'class initialization'!
initialize
	self register
!
register
	"Register in the World menu and as the #profiler opener."
	ToolsMenu register: 'Profiler' description: 'samples', ProfilerFormat dot, 'frames' group: #tools order: 60 action: [:aPoint | self openAt: aPoint].
	Tools registerOpener: #profiler with: [:arg | (arg isKindOf: Process) ifTrue: [self openSelecting: arg] ifFalse: [self open]]
! !

!ProfilerView methodsFor: 'private'!
setFilter: aProcessOrAll
	filter := aProcessOrAll
! !
