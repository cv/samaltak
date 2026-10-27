UIWindowsTestCase subclass: #WidgetsInWindowTest
	instanceVariableNames: 'list editor header window chosen opened'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

WidgetsInWindowTest comment: 'I run widgets in a real Window of a hidden World (real Process, real input path, real compositor): clicks select list rows (a double click needs the same row and at most 5 points between the presses), injected text and keys edit a TextEditor, ⌘Z undoes, a right-click opens the editor''s menu in an overlay whose item runs in the window''s Process, the caret blinks on the window''s timer, and the remote-control snapshot shows the widget refs.'!

!WidgetsInWindowTest methodsFor: 'running'!
setUp
	super setUp.
	chosen := OrderedCollection new.
	opened := OrderedCollection new.
	header := PaneHeader title: 'Packages' right: 'by layer'.
	list := ListView new title: 'Packages'; name: 'packages';
		items: #('Tools' 'UI-Widgets' 'UI-Windows' 'Graphics-Canvas');
		onSelect: [:item | chosen add: item];
		onDoubleClick: [:item | opened add: item];
		yourself.
	editor := TextEditor new title: 'code'; name: 'code'; yourself.
	editor text: 'foo'.
	window := self open: (Column with: {header. list fixed: 100. editor}) title: 'Widgets' at: (100 @ 100 extent: 400 @ 300)
!
tearDown
	Animation timeScale: 1.
	super tearDown
!
screenPoint: aLocalPoint of: aWidget
	^aWidget screenPointFrom: aLocalPoint
!
rowPoint: index
	^self screenPoint: (list rowRect: index) center of: list
! !

!WidgetsInWindowTest methodsFor: 'tests'!
testClickSelectsRowInWindowProcess
	| shot r p |
	r := list rowRect: 3.
	self click: (self screenPoint: r center of: list).
	self assert: list selection equals: 'UI-Windows'.
	self assert: chosen asArray equals: #('UI-Windows').
	self assert: window keyboardFocus == list.
	self settle.
	shot := self screenshot.
	p := self screenPoint: (r left + 3) @ (r top + 3) of: list.
	self assertColor: Color black at: p in: shot
!
testQuickClicksOnTwoRowsAreSingleClicks
	"4 points apart across the border of rows 2 and 3, a press the platform counts as a further click."
	| a b |
	a := self screenPoint: (list rowRect: 2) bottomLeft + (40 @ -2) of: list.
	b := a + (0 @ 4).
	self click: a platformCount: 1; click: b platformCount: 2.
	self assert: opened isEmpty.
	self assert: chosen asArray equals: #('UI-Widgets' 'UI-Windows').
	self click: b platformCount: 3.
	self assert: opened asArray equals: #('UI-Windows')
!
testQuickClicksOnTheSameRowDoubleClick
	self click: (self rowPoint: 2) platformCount: 1; click: (self rowPoint: 2) + (4 @ 0) platformCount: 2.
	self assert: opened asArray equals: #('UI-Widgets')
!
testClicksMoreThan5PointsApartAreSingleClicks
	self click: (self rowPoint: 2) platformCount: 1; click: (self rowPoint: 2) + (6 @ 0) platformCount: 2.
	self assert: opened isEmpty
!
testSlowClicksAreSingleClicks
	"After its double-click interval the platform counts a press as a new click."
	self click: (self rowPoint: 2) platformCount: 1; click: (self rowPoint: 2) platformCount: 1.
	self assert: opened isEmpty
!
testTypingAndUndo
	self click: (self screenPoint: 30 @ 10 of: editor).
	self assert: window keyboardFocus == editor.
	editor caret: 3.
	self type: 'bar'.
	self assert: editor text equals: 'foobar'.
	self key: $z modifiers: 8.
	self settle.
	self assert: editor text equals: 'foo'.
	self key: #left modifiers: 0.
	self settle.
	self assert: editor caret equals: 2
!
testEditorMenuRunsInWindow
	| ran overlay item |
	editor onDoIt: [:t :r | ran := Processor activeProcess].
	self rightClick: (self screenPoint: 30 @ 10 of: editor).
	overlay := world overlays detect: [:each | each content isKindOf: MenuView] ifNone: [nil].
	self assert: overlay notNil.
	item := overlay content items detect: [:each | each label = 'do it'].
	self click: (overlay content screenPointFrom: (overlay content itemRect: (overlay content items indexOf: item)) center).
	self settle.
	self assert: ran == window process.
	self assert: (world overlays noneSatisfy: [:each | each content isKindOf: MenuView])
!
testCaretBlinksOnWindowTimer
	| before |
	self click: (self screenPoint: 30 @ 10 of: editor).
	before := editor isCaretOn.
	self assert: (self waitFor: [editor isCaretOn ~= before] timeout: 2000) description: 'the caret did not blink'
!
testCaretBlinkSlowsDownInSlowMotion
	| before |
	self click: (self screenPoint: 30 @ 10 of: editor).
	Animation timeScale: 10.
	window sync: [editor restartBlink].
	before := editor isCaretOn.
	"530 ms between blinks, 5.3 s in slow motion"
	(Delay forMilliseconds: 1500) wait.
	self assert: editor isCaretOn equals: before.
	Animation timeScale: 1.
	window sync: [editor restartBlink].
	self assert: (self waitFor: [editor isCaretOn ~= before] timeout: 2000) description: 'the caret did not blink'
!
testRemoteSnapshot
	| snapshot text |
	list selection: 'Tools'.
	snapshot := RemoteSnapshot root: world refTable: RemoteRefTable new.
	text := snapshot renderDepth: 5 bounds: false maxItems: 100.
	self assert: (text includesSubstring: '.packages "Packages" sel="Tools" n=4').
	self assert: (text includesSubstring: '.code "code" lines=1').
	self assert: (text includesSubstring: 'header ').
	self assert: ((snapshot find: 'graphics-canvas') anySatisfy: [:node | node role = 'item'])
!
testScrollPaneReplaysMovedContent
	"Scrolling moves the content: rows that stay in view replay what they drew (moved by whole device pixels), and the window draws as if drawn anew, also between rows and at fractional offsets."
	| pane rows w kept |
	rows := (1 to: 40) collect: [:i | (Label text: 'row ', i printString) fixed: 20; yourself].
	pane := ScrollPane new content: (Column with: rows); yourself.
	w := self open: pane title: 'Scrolling' at: (520 @ 100 extent: 300 @ 260).
	self assert: w retainedDrawingMismatch isNil.
	#(30 37.5 37.75 120 0) do: [:offset |
		kept := w sync: [ | before |
			before := (rows at: 9) instVarNamed: 'drawing'.
			pane scrollOffset: offset.
			w contentDisplayListFresh: false.
			((rows at: 9) instVarNamed: 'drawing') == before].
		offset = 37.5 ifTrue: [self assert: kept description: 'row 9 was drawn again'].
		self assert: w retainedDrawingMismatch isNil description: 'scrolled to ', offset printString].
	w close
! !
