UIWindowsTestCase subclass: #WindowManagerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

WindowManagerTest comment: 'Tests the window manager in the InputDispatcher: raise on click, drag by the title bar, resize from edges and corner, close and collapse boxes, double-click to collapse, and that a busy window Process blocks neither dragging nor other windows.'!

!WindowManagerTest methodsFor: 'tests'!
testDragGesture
	| w g |
	w := self open: RecordingTestView new title: 'Drag gesture' at: (100 @ 100 extent: 300 @ 200).
	g := DragGesture window: w grabOffset: 40 @ 10.
	g pointerMoved: 240 @ 160.
	self assert: w bounds equals: (200 @ 150 extent: 300 @ 200).
	g pointerReleased: -1000 @ -1000.
	self assert: w bounds origin equals: -240 @ world topBar height.
	g pointerMoved: 5000 @ 5000.
	self assert: w bounds origin equals: (world extent x - 60) @ (world extent y - 26)
!
testResizeGestures
	| w b g |
	w := self open: RecordingTestView new title: 'Resize gesture' at: (100 @ 100 extent: 300 @ 200).
	b := w bounds.
	g := ResizeGesture window: w zone: #resizeBR start: 0 @ 0 bounds: b.
	g pointerMoved: 50 @ 20.
	self assert: w bounds equals: (b origin extent: 350 @ 220).
	g pointerReleased: -1000 @ -1000.
	self assert: w bounds equals: (b origin extent: w minExtent).
	(ResizeGesture window: w zone: #resizeR start: 0 @ 0 bounds: b) pointerReleased: 30 @ 99.
	self assert: w bounds equals: (b origin extent: 330 @ 200).
	(ResizeGesture window: w zone: #resizeB start: 0 @ 0 bounds: b) pointerReleased: 99 @ 30.
	self assert: w bounds equals: (b origin extent: 300 @ 230).
	(ResizeGesture window: w zone: #resizeL start: 0 @ 0 bounds: b) pointerReleased: -30 @ 99.
	self assert: w bounds equals: ((b left - 30) @ b top corner: b corner).
	(ResizeGesture window: w zone: #resizeL start: 0 @ 0 bounds: b) pointerMoved: 1000 @ 0.
	self assert: w bounds equals: ((b right - w minExtent x) @ b top corner: b corner)
!
testDispatcherRunsGestures
	| w p |
	w := self open: RecordingTestView new title: 'Gestures' at: (100 @ 100 extent: 300 @ 200).
	p := w bounds origin + (40 @ 10).
	self moveTo: p; down: p.
	self settle.
	self assert: (world dispatcher gesture isKindOf: DragGesture).
	self assert: world dispatcher gesture window == w.
	self up: p.
	self settle.
	self assert: world dispatcher gesture isNil.
	p := w bounds bottomRight - (4 @ 4).
	self moveTo: p; down: p.
	self settle.
	self assert: (world dispatcher gesture isKindOf: ResizeGesture).
	self assert: world dispatcher gesture zone equals: #resizeBR.
	self up: p.
	self settle.
	self assert: world dispatcher gesture isNil
!
testClickRaisesAndActivates
	| a b wa wb |
	a := RecordingTestView new.
	b := RecordingTestView new.
	wa := self open: a title: 'Back' at: (100 @ 100 extent: 300 @ 200).
	wb := self open: b title: 'Front' at: (200 @ 150 extent: 300 @ 200).
	self assert: world windows first == wb.
	self click: wa contentOrigin + (10 @ 10).
	self assert: world windows first == wa.
	self assert: world activeWindow == wa.
	self assert: wa isFocused.
	self deny: wb isFocused.
	self assert: wa focusAmount equals: 1.
	self assert: wb focusAmount equals: 0
!
testDragByTitleBar
	| w origin |
	w := self open: RecordingTestView new title: 'Drag me' at: (100 @ 100 extent: 300 @ 200).
	origin := w bounds origin.
	self drag: origin + (40 @ 10) to: origin + (140 @ 60).
	self assert: w bounds origin equals: origin + (100 @ 50).
	self assert: w bounds extent equals: 300 @ 200.
	self assert: (w content eventsOfType: #down) isEmpty
!
testDragIsClampedToTheDesk
	| w |
	w := self open: RecordingTestView new title: 'Clamp' at: (100 @ 100 extent: 300 @ 200).
	self drag: w bounds origin + (40 @ 10) to: 140 @ -50.
	self assert: w bounds top equals: world topBar height
!
testResizeFromCornerAndEdges
	| v w b |
	v := RecordingTestView new.
	w := self open: v title: 'Resize' at: (100 @ 100 extent: 300 @ 200).
	b := w bounds.
	self drag: b bottomRight - (4 @ 4) to: b bottomRight + (96 @ 46).
	self assert: w bounds extent equals: 400 @ 250.
	self assert: w bounds origin equals: b origin.
	self assert: v extent equals: w contentExtent.
	self assert: v layouts >= 2.
	b := w bounds.
	self drag: (b right - 1) @ (b top + 100) to: (b right - 51) @ (b top + 100).
	self assert: w bounds width equals: 350.
	b := w bounds.
	self drag: (b left + 1) @ (b top + 100) to: (b left - 49) @ (b top + 100).
	self assert: w bounds width equals: 400.
	self assert: w bounds left equals: b left - 50.
	self assert: w bounds right equals: b right.
	b := w bounds.
	self drag: (b left + 100) @ (b bottom - 1) to: (b left + 100) @ (b bottom - 101).
	self assert: w bounds height equals: 150.
	self drag: (w bounds right - 3) @ (w bounds bottom - 3) to: 0 @ 0.
	self assert: w bounds extent equals: w minExtent
!
testCloseBox
	| w |
	w := self open: RecordingTestView new title: 'Close me' at: (100 @ 100 extent: 300 @ 200).
	self click: w bounds origin + w closeBoxRect center.
	self assert: w isClosed.
	self deny: (world windows includes: w).
	self assert: w process isTerminated.
	self assert: world closingWindows isEmpty.
	self assert: w layer surface isNil
!
testCollapseBoxAndDoubleClick
	| v w ext |
	v := RecordingTestView new.
	w := self open: v title: 'Collapse' at: (100 @ 100 extent: 300 @ 200).
	ext := w extent.
	self click: w bounds origin + w collapseBoxRect center.
	self assert: w isCollapsed.
	self assert: w extent equals: 300 @ 23.
	self assert: (w zoneAt: w bounds origin + (150 @ 100)) isNil.
	self doubleClick: w bounds origin + (60 @ 10).
	self deny: w isCollapsed.
	self assert: w extent equals: ext.
	self assert: v extent equals: w contentExtent
!
testDoubleClickNeedsTheSameZone
	"Presses 4 points apart, the platform counting them as one multi-click: content, title bar, content."
	| v w content |
	v := RecordingTestView new.
	w := self open: v title: 'Zones' at: (100 @ 100 extent: 300 @ 200).
	content := w bounds origin + (60 @ 25).
	self click: content platformCount: 1; click: content - (0 @ 4) platformCount: 2.
	self deny: w isCollapsed.
	self click: content platformCount: 3.
	self assert: ((v eventsOfType: #down) collect: [:e | e clickCount]) asArray equals: #(1 1)
!
testBusyWindowDoesNotBlockDraggingOrOtherWindows
	| looper busy other ov origin |
	looper := LoopingTestView new.
	busy := self open: looper title: 'Busy' at: (100 @ 100 extent: 300 @ 200).
	ov := RecordingTestView new.
	other := self open: ov title: 'Other' at: (500 @ 100 extent: 300 @ 200).
	self moveTo: busy contentOrigin + (10 @ 10).
	self down: busy contentOrigin + (10 @ 10).
	self up: busy contentOrigin + (10 @ 10).
	self assert: (self waitFor: [looper isLooping]).
	"Busy after 250 ms in one event."
	self assert: (self waitFor: [busy isBusy]).
	self assert: busy processState equals: 'busy'.
	"the busy window stays draggable"
	origin := busy bounds origin.
	self moveTo: origin + (40 @ 10); down: origin + (40 @ 10); moveTo: origin + (90 @ 40); up: origin + (90 @ 40).
	self assert: (self waitFor: [busy bounds origin = (origin + (50 @ 30))]).
	self assert: busy bounds origin equals: origin + (50 @ 30).
	"its queued key events are kept"
	self key: $q modifiers: 0.
	"another window stays live"
	self moveTo: other contentOrigin + (10 @ 10); down: other contentOrigin + (10 @ 10); up: other contentOrigin + (10 @ 10).
	self assert: (self waitFor: [(ov eventsOfType: #up) notEmpty]).
	self assert: (ov eventsOfType: #up) size equals: 1.
	self assert: looper isLooping.
	self assert: world activeWindow == other.
	looper stopLooping.
	self settle.
	self deny: busy isBusy.
	self assert: ((looper eventsOfType: #down) anySatisfy: [:e | e isKey and: [e key = $q]])
!
testNewWindowsCascadeAndGetRemoteNames
	| a b |
	a := self open: RecordingTestView new title: 'One' at: (100 @ 100 extent: 300 @ 200).
	b := self open: RecordingTestView new title: 'Two' at: (100 @ 100 extent: 300 @ 200).
	self assert: a remoteName equals: 'w1'.
	self assert: b remoteName equals: 'w2'.
	self assert: (world windowNamed: 'w1') == a.
	self assert: (world windowNamed: 'Two') == b.
	self assert: (world nextWindowPosition: 300 @ 200) y >= world topBar height
!
testBackgroundCloseDoesNotActivate
	| back front p |
	back := self open: RecordingTestView new title: 'Back' at: (100 @ 100 extent: 300 @ 200).
	front := self open: RecordingTestView new title: 'Front' at: (200 @ 150 extent: 300 @ 200).
	p := back bounds origin + back closeBoxRect center.
	self moveTo: p; down: p.
	self assert: back isOpen.
	self assert: world windows first == front.
	self assert: world activeWindow == front.
	self deny: back isFocused.
	self up: p.
	self settle.
	self assert: back isClosed.
	self assert: world activeWindow == front
! !
