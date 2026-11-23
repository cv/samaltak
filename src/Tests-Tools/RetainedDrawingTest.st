ToolsTestCase subclass: #RetainedDrawingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

RetainedDrawingTest comment: 'I check retained drawing (View>>drawRetainedOn:) in the real tools: in each scenario a window''s content drawn as its next redraw would (replaying the views that did not change) draws the same quads and, read back from a Surface, the same pixels as drawn all anew (Window>>retainedDrawingMismatch): the default layout, scrolling, a list selection gliding (in the middle of the glide), a Profiler zooming its flame graph (in the middle of the zoom). View verifyDrawing: is on throughout, so every replay in every redraw is also compared with drawing anew.'!

!RetainedDrawingTest methodsFor: 'running'!
setUp
	super setUp.
	View verifyDrawing: true
!
tearDown
	View verifyDrawing: false.
	super tearDown
! !

!RetainedDrawingTest methodsFor: 'support'!
assertRetainedDrawingOfAll
	"Every window, the Process Browser too: it draws the Processes' states as its last refresh read them."
	world windows do: [:w | self assertRetainedDrawingOf: w]
!
assertRetainedDrawingOf: aWindow
	self assertRetainedDrawingOf: aWindow after: []
!
assertRetainedDrawingOf: aWindow after: aBlock
	| mismatch |
	mismatch := aWindow retainedDrawingMismatchAfter: aBlock.
	self assert: mismatch isNil description: aWindow title, ': ', mismatch printString
!
assertNoStaleReplays
	| stale |
	stale := View staleDrawings.
	stale isEmpty ifFalse: [self fail: stale size printString, ' replays differed from drawing anew, first ', stale first printString]
!
middleOf: anAnimation
	"Step anAnimation (of a window, in its Process) to half its duration."
	anAnimation startTime isNil ifTrue: [anAnimation startAt: Animation now].
	anAnimation stepAt: anAnimation startTime + (anAnimation duration / 2)
!
openBrowser
	^self open: [SystemBrowser openIn: (40 @ 60 extent: 866 @ 468) onClass: OrderedCollection protocol: nil selector: nil]
! !

!RetainedDrawingTest methodsFor: 'tests'!
testDefaultLayout
	| ws browser |
	Tools openDefaultLayout.
	self assert: (self waitFor: [world windows size >= 6]).
	"While the Mandelbrot renders, the Process Browser shows its progress live: wait for it to finish."
	self assert: (self waitFor: [(self windowsOf: MandelbrotView) first content progress = 1] timeout: 20000).
	self settle.
	self assertRetainedDrawingOfAll.
	ws := (self windowsOf: Workspace) first.
	browser := (self windowsOf: SystemBrowser) first.
	self in: ws do: [ws content editor selectFrom: 1 to: 12].
	self in: browser do: [browser content methodList select: browser content methodList items first].
	self settle.
	self assertRetainedDrawingOfAll.
	self assertNoStaleReplays
!
testScrolling
	| w list code |
	w := self openBrowser.
	list := w content classList.
	code := w content code.
	self in: w do: [code text: ((1 to: 80) inject: '' into: [:s :i | s, 'line ', i printString, (String with: Character lf)])].
	#(17 40.5 40.75 3 0) do: [:y |
		self assertRetainedDrawingOf: w after: [list scrollOffset: y. code scrollOffset: y]].
	self assertNoStaleReplays
!
testSelectionGlideMidAnimation
	| w list |
	w := self openBrowser.
	list := w content classList.
	self assert: list items size >= 9.
	#(3 9 5) do: [:i | | glided |
		self assertRetainedDrawingOf: w after: [ | glide |
			list selectionIndex: i.
			glide := list instVarNamed: 'barAnimation'.
			(glided := glide notNil) ifTrue: [self middleOf: glide]].
		self assert: glided.
		self settle.
		self assertRetainedDrawingOf: w].
	self assertNoStaleReplays
!
testProfilerZoomMidAnimation
	| w view entry |
	self fork: [[true] whileTrue: [300 factorial]] named: 'crunch' at: 30.
	(Delay forMilliseconds: 800) wait.
	w := ProfilerView open.
	view := w content.
	[self in: w do: [view stop].
	 self settle.
	 self in: w do: [view refresh].
	 self settle.
	 self assertRetainedDrawingOf: w.
	 entry := view flame entries detect: [:e | (e at: 1) name = 'Integer>>factorial'] ifNone: [view flame entries last].
	 self assertRetainedDrawingOf: w after: [
		view flame zoomTo: (entry at: 1).
		self middleOf: (view flame instVarNamed: 'animation')].
	 self settle.
	 self assertRetainedDrawingOf: w.
	 self assertRetainedDrawingOf: w after: [view flame zoomToDepth: 0. self middleOf: (view flame instVarNamed: 'animation')].
	 self assertRetainedDrawingOf: w after: [view refresh].
	 self assertNoStaleReplays]
		ensure: [w close]
!
testProfilerProcessTerminating
	"A Process the stopped Profiler lists terminates: the list, replayed, draws it as when its rows came."
	| busy w view |
	busy := self fork: [[true] whileTrue: [300 factorial]] named: 'busy' at: 30.
	(Delay forMilliseconds: 300) wait.
	w := ProfilerView open.
	view := w content.
	[self in: w do: [view stop].
	 self settle.
	 self in: w do: [view refresh].
	 self assert: (view processList items anySatisfy: [:row | row first == busy]).
	 busy terminate.
	 self assertRetainedDrawingOf: w after: [view flame invalidate].
	 self assertNoStaleReplays]
		ensure: [w close]
! !
