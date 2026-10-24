UIWindowsTestCase subclass: #ProfilerViewTest
	instanceVariableNames: 'crunch window view'
	classVariableNames: ''
	package: 'Tests-Tools-Profiler'!

ProfilerViewTest comment: 'I run the Profiler window on real data: a factorial loop runs in a Process named crunch, the Profiler opens in a hidden World, and injected clicks, drags and keys drive it. The flame graph must contain the workload''s real methods, the process list filters, a click zooms (animated), a drag in the frame overview pins and filters a range, the tally has its MessageTally sections, ⌘P in the evaluator prints a real Dictionary. Live: the window refreshes ten times a second with the CPU-bound crunch running, using little CPU itself; a pinned range stays frozen; the filtered trees equal a rebuild from the samples.'!

!ProfilerViewTest methodsFor: 'running'!
setUp
	previous := World current.
	"A ring of this test's own, as in the walkthrough (not the earlier tests' Processes and marks)."
	Profiler default reset.
	world := World openHidden: 1100 @ 760.
	crunch := self fork: [[true] whileTrue: [300 factorial]] named: 'crunch' at: 30.
	"1.5 s of samples to show."
	(Delay forMilliseconds: 1500) wait.
	window := ProfilerView open.
	view := window content.
	self settle.
	self refresh
!
tearDown
	self terminateForkedProcesses.
	window isNil ifFalse: [window close].
	super tearDown
!
timeLimitMilliseconds
	^60000
! !

!ProfilerViewTest methodsFor: 'support'!
refresh
	"Take a fresh snapshot in the window's Process and wait for the redraw."
	window sync: [view refresh].
	self settle
!
clickAt: aLocalPoint in: aWidget
	self click: (aWidget screenPointFrom: aLocalPoint) rounded
!
click: aWidget screenPointFrom: aPoint
	self click: (aWidget screenPointFrom: aPoint) rounded
!
flameLabels
	^view flame entries collect: [:e | e first name]
!
entryNamed: aString
	"The widest entry named aString in the crunch Process (earlier tests' Processes can call the same method)."
	| all |
	all := view flame entries select: [:e | e first name = aString and: [e first path anySatisfy: [:n | n process == crunch]]].
	all isEmpty ifTrue: [^nil].
	^all detectMax: [:e | (view flame displayRectOf: e) width]
!
rowOf: aKey
	^view processList items findFirst: [:row | row first == aKey]
! !

!ProfilerViewTest methodsFor: 'tests'!
testFlameGraphShowsTheWorkloadsMethods
	| labels parts |
	labels := self flameLabels.
	self assert: (labels includes: 'all Processes').
	self assert: (labels includes: 'Process ''crunch''').
	self assert: (labels includes: 'Integer>>factorial').
	self assert: (labels anySatisfy: [:l | l beginsWith: 'Integer class>>productFrom:to:']).
	parts := view flame remoteChildren.
	self assert: (parts anySatisfy: [:p | p remoteRole == #'flame-frame' and: [(p remoteLabel beginsWith: 'Integer>>factorial ') and: [p remoteLabel includesSubstring: 'samples)']]]).
	self assert: ((view processList items collect: [:row | row at: 2]) includes: 'crunch').
	self assert: (view processList items first at: 2) equals: 'All but idle'
!
testProcessFilter
	| i root |
	i := self rowOf: crunch.
	self assert: i > 0.
	self clickAt: (view processList rowRect: i) center in: view processList.
	self assert: view filter == crunch.
	window sync: [view stop]. "compare trees and samples of one refresh"
	root := view flame root.
	self assert: root name equals: 'Process ''crunch'''.
	self assert: root process == crunch.
	self deny: (self flameLabels includes: 'all Processes').
	self assert: (view data cpuTree weight) equals: (view data rangeProfile samples count: [:s | s process == crunch]).
	i := self rowOf: #all.
	self clickAt: (view processList rowRect: i) center in: view processList.
	self assert: view filter == #all.
	self assert: view flame root name equals: 'all Processes'
!
testClickZoomsAndCrumbsZoomOut
	| e r |
	window sync: [view stop]. "a live refresh between measuring the entry and clicking it would move it"
	e := self entryNamed: 'Integer>>factorial'.
	self assert: e notNil.
	r := view flame displayRectOf: e.
	self clickAt: r left + 20 @ r center y in: view flame.
	self assert: view flame zoomNode name equals: 'Integer>>factorial'.
	self assert: view picked == e first frame.
	self assert: (view flame zoomPath collect: [:n | n name]) first equals: 'all Processes'.
	self assert: ((view flame entries select: [:x | x at: 5]) collect: [:x | x first name]) size equals: view flame zoomNode depth.
	self assert: (view flame remoteChildren anySatisfy: [:p | (p remoteState includes: #zoomed) and: [p remoteLabel beginsWith: 'Integer>>factorial']]).
	self refresh.
	self assert: view flame zoomNode name equals: 'Integer>>factorial'.
	self clickAt: ((view flame displayRectOf: view flame entries first) center) in: view flame.
	self assert: view flame zoomNode == view flame root
!
testZoomIsAnimated
	| e |
	e := self entryNamed: 'Integer>>factorial'.
	window sync: [view flame zoomTo: e first].
	self assert: view flame isAnimating.
	self assert: (self waitFor: [view flame isAnimating not] timeout: 2000) description: 'the zoom animation did not end'
!
testRangeSelectionFiltersEveryView
	| ov from to range samples |
	ov := view overview.
	from := ov width * 0.3 @ (ov height / 2).
	to := ov width * 0.7 @ (ov height / 2).
	self drag: (ov screenPointFrom: from) rounded to: (ov screenPointFrom: to) rounded.
	self assert: view isPinned.
	range := view selectionRange.
	self assert: range first < range last.
	samples := view data rangeProfile samples.
	self assert: (samples allSatisfy: [:s | s time between: range first and: range last]).
	self assert: view data cpuTree weight <= view data busySamples.
	self assert: (view statusBar fullText includesSubstring: 'pinned').
	self assert: view statusBar clearButton isVisible.
	self click: (view statusBar clearButton screenPointFrom: view statusBar clearButton localBounds center).
	self deny: view isPinned.
	self assert: (view statusBar fullText includesSubstring: 'live')
!
testTallyHasMessageTallySections
	| text |
	self click: (view widgetNamed: 'tabs') screenPointFromSegment: 1.
	self assert: view tab equals: #tally.
	text := view tallyView text.
	#('tallies' '**Tree**' '**Leaves**' '**Memory**' '**GCs**' 'Process: (30)' 'Integer>>factorial' 'scavenges') do: [:s |
		self assert: (text includesSubstring: s) description: 'tally lacks ', s]
!
testEvaluatorPrintsARealDictionary
	| editor |
	editor := view evaluator.
	window sync: [editor text: 'Profiler last samples groupBy: #method'. editor selectFrom: 1 to: editor text size].
	self click: (editor screenPointFrom: 40 @ 12).
	window sync: [editor selectFrom: 1 to: editor text size].
	self key: $p modifiers: 8.
	self assert: (self waitFor: [editor text includesSubstring: ' a Dictionary(']) description: 'no result after ⌘P'.
	self assert: (editor text includesSubstring: 'SampleSet(')
!
testFramesTabShowsRecords
	| tl bar x |
	self click: (view widgetNamed: 'tabs') screenPointFromSegment: 4.
	self assert: view tab equals: #frames.
	self assert: (view recordView plainText includesSubstring: 'Frame time').
	"No live refresh between measuring the last bar and clicking it: a new snapshot would move it."
	window sync: [view stop; setSpan: 0].
	self settle.
	tl := view timeline.
	"A bar in the middle: the last one can sit within the window's resize edge, where a click resizes."
	bar := view data bars detect: [:b | (tl xOf: b start) > (tl width / 2)] ifNone: [view data bars last].
	x := tl xOf: bar start + (bar end - bar start / 2).
	self click: (tl screenPointFrom: x @ (tl height / 2)) rounded.
	self assert: view selectedBar notNil.
	self assert: view isPinned.
	self assert: (view recordView plainText includesSubstring: 'a FrameRecord #')
!
testAllocationsShowRealSites
	self click: (view widgetNamed: 'tabs') screenPointFromSegment: 3.
	self assert: view tab equals: #alloc.
	self assert: view allocationFlame root weight > 0.
	self assert: view sites items notEmpty.
	self assert: (view sites items allSatisfy: [:site | site bytes > 0])
!
testTallyRowsToggle
	| tally before line i |
	window sync: [view stop]. "a live refresh between the clicks could change the line count"
	self click: (view widgetNamed: 'tabs') screenPointFromSegment: 1.
	self settle.
	tally := view tallyView.
	"Count the tree rows only: the memory and GC sections below follow live VM statistics."
	before := (tally lines select: [:l | l first == #node]) size.
	i := tally lines findFirst: [:l | l first == #node and: [(l at: 5) and: [l at: 6]]].
	self assert: i > 0.
	line := tally lines at: i.
	self clickAt: ((tally toggleXOf: line) + 3) @ ((tally lineTop: i) + 8) in: tally.
	self assert: (tally lines select: [:l | l first == #node]) size < before.
	self assert: ((tally lines at: i) at: 6) not.
	self clickAt: ((tally toggleXOf: line) + 3) @ ((tally lineTop: i) + 8) in: tally.
	self assert: (tally lines select: [:l | l first == #node]) size equals: before
!
testLiveUpdatesMarkAndPause
	| first pause |
	first := view data.
	self assert: (self waitFor: [view data ~~ first]) description: 'no live refresh'.
	self settle.
	self assert: view data now > first now.
	self click: (view widgetNamed: 'mark') screenPointFrom: (view widgetNamed: 'mark') localBounds center.
	self assert: (view data marks anySatisfy: [:m | m label beginsWith: 'mark ']).
	pause := view widgetNamed: 'pause'.
	[self click: (pause screenPointFrom: pause localBounds center) rounded.
	self deny: Profiler default isRunning.
	self assert: pause label equals: 'Resume'.
	self assert: (view widgetNamed: 'capture') text equals: '□ paused'.
	first := view data.
	"Paused: no refresh may happen in 600 ms (several refresh intervals)."
	(Delay forMilliseconds: 600) wait.
	self assert: view data == first.
	self click: (pause screenPointFrom: pause localBounds center) rounded.
	self assert: Profiler default isRunning.
	self assert: pause label equals: 'Pause']
		ensure: [Profiler resume]
!
testRemoteNames
	| text |
	text := (RemoteSnapshot root: world refTable: RemoteRefTable new) renderDepth: 6 bounds: false maxItems: 2000.
	#('.pause "Pause"' '.mark "Mark"' '.tabs.tally' '.tabs.flame-graph' '.tabs.allocations' '.tabs.frames' '.ring-stats '
		'.processes.all-but-idle' '.processes.crunch' '.frame-overview ' '.flame-graph.integer-factorial "Integer>>factorial '
		'.evaluate ' '.status ') do: [:s |
			self assert: (text includesSubstring: s) description: 'snapshot lacks ', s]
! !

!ProfilerViewTest methodsFor: 'live'!
testRefreshesTenTimesASecondUnderLoad
	"With the CPU-bound crunch running and a full flame graph shown, the window refreshes at 10 Hz while its own Process uses little CPU. Measured once the first seconds are over, in which earlier tests' Processes leave the ring and the overview rescales while the ring grows."
	| n0 c0 t0 n1 c1 t1 cpu |
	(Delay forMilliseconds: 3000) wait.
	n0 := view refreshCount.
	c0 := window process cpuMicroseconds.
	t0 := Time microsecondClockValue.
	(Delay forMilliseconds: 3050) wait.
	n1 := view refreshCount.
	c1 := window process cpuMicroseconds.
	t1 := Time microsecondClockValue.
	self assert: n1 - n0 >= 30 description: (n1 - n0) printString, ' refreshes in 3 s'.
	cpu := (c1 - c0) * 100.0 / (t1 - t0).
	"A refresh redraws only the views whose data changed (retained drawing)."
	self assert: cpu < 2.0 description: 'the Profiler used ', (cpu printShowingDecimalPlaces: 2), '% CPU'.
	self assert: view refreshMicros < 20000
!
testPinnedRangeStaysFrozen
	| ov data weight rows samples |
	ov := view overview.
	self drag: (ov screenPointFrom: (ov width * 0.4) @ (ov height / 2)) rounded to: (ov screenPointFrom: (ov width * 0.8) @ (ov height / 2)) rounded.
	self assert: view isPinned.
	data := view data.
	self assert: data isFrozen.
	weight := data cpuTree weight.
	rows := data summary.
	samples := data samples asArray.
	self assert: (samples allSatisfy: [:s | s time between: view selectionRange first and: view selectionRange last]).
	"Several refresh intervals: crunch keeps running, the pinned data must not move."
	(Delay forMilliseconds: 700) wait.
	self assert: view data == data.
	self assert: view data cpuTree weight equals: weight.
	self assert: view data summary equals: rows.
	self assert: (view data samples asArray collect: [:s | s serial]) equals: (samples collect: [:s | s serial]).
	self assert: view flame root weight equals: weight.
	self click: (view statusBar clearButton screenPointFrom: view statusBar clearButton localBounds center).
	self deny: view isPinned.
	self assert: (self waitFor: [view data ~~ data and: [view data isFrozen not]]) description: 'not live again'
!
testFilteredTreesEqualARebuild
	"The live aggregate's subtree for crunch equals the call tree of crunch's samples, for CPU and allocations."
	| data canonical samples allocs |
	window sync: [view selectFilter: crunch. view refresh. view stop].
	data := view data.
	canonical := [:node | | d walk |
		d := Dictionary new.
		walk := nil.
		walk := [:n :path | | k |
			d at: path put: (Array with: n weight with: n selfWeight).
			n children do: [:c |
				k := c frame ifNil: [c key].
				walk value: c value: (path copyWith: k)]].
		node children do: [:c | walk value: c value: (Array with: (c frame ifNil: [c key]))].
		d].
	samples := data samples select: [:s | s process == crunch].
	self assert: samples notEmpty.
	self assert: data cpuTree weight equals: samples size.
	self assert: (canonical value: data cpuTree) equals: (canonical value: samples tallyTree children first).
	self assert: view flame root == data cpuTree.
	self assert: (data summary detect: [:row | row first == crunch]) third equals: samples size.
	allocs := data allocationAggregate samples select: [:s | s process == crunch].
	self assert: data allocationTree weight equals: allocs totalWeight.
	allocs isEmpty ifFalse: [
		self assert: (canonical value: data allocationTree) equals: (canonical value: allocs tallyTree children first)]
! !

!ProfilerViewTest methodsFor: 'support'!
click: aToggleGroup screenPointFromSegment: index
	self click: (aToggleGroup screenPointFrom: (aToggleGroup segmentRects at: index) center) rounded
! !
