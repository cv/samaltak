WidgetTestCase subclass: #MoreWidgetsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

MoreWidgetsTest comment: 'I check the TableView (columns, header strip, rows, remote rows), KeyValueList, Sparkline, ProgressStripe, BusyIndicator and ToastView, and a whole browser-like tree through the remote-control snapshot.'!

!MoreWidgetsTest methodsFor: 'support'!
processes
	^{
		#(80 'timer interrupt watcher' 'waiting' 0.0 1001).
		#(70 'compositor (vsync)' 'waiting' 0.021 1002).
		#(40 'Workspace' 'running' 0.5 1415)}
!
processTable
	| table |
	table := TableView new title: 'Processes'; name: 'processes'; yourself.
	table addColumn: (TableColumn title: '' width: 6 draw: (TableView squareDotCell: [:p | (p at: 3) = 'running'])).
	table addColumn: ((TableColumn title: 'Pri' width: 24 text: [:p | (p at: 1) printString]) align: #right; remoteKey: 'pri'; yourself).
	table addColumn: (TableColumn title: 'Process' flex: 1 text: [:p | p at: 2]).
	table addColumn: ((TableColumn title: 'State' width: 60 text: [:p | p at: 3]) styleBlock: [:p | #italic]; remoteKey: ''; yourself).
	table addColumn: ((TableColumn title: 'CPU' width: 90 draw: (TableView barCell: [:p | p at: 4] text: [:p | ((p at: 4) * 100 printShowingDecimalPlaces: 1), '%'])) remoteKey: nil; yourself).
	table labelBlock: [:p | p at: 2]; remoteNameBlock: [:p | (p at: 5) printString].
	table items: self processes.
	^table
! !

!MoreWidgetsTest methodsFor: 'tests'!
testTableColumnsAndRemoteRows
	| table rows rects form |
	table := self processTable.
	self open: table extent: 400 @ 120.
	rects := table columnRectsFor: 400.
	self assert: rects size equals: 5.
	self assert: (rects at: 1) first equals: 8.
	self assert: (rects at: 5) last equals: 392.
	self assert: (table rowRect: 1) top equals: table headerHeight + 1.
	rows := table remoteChildren.
	self assert: (rows at: 2) remoteRole equals: #row.
	self assert: (rows at: 2) remoteLabel equals: 'compositor (vsync)'.
	self assert: (rows at: 2) remoteName equals: '1002'.
	self assert: (rows at: 2) remoteState equals: #('pri=70' 'waiting').
	self click: (table rowRect: 3) center.
	self assert: table selection last equals: 1415.
	form := self render.
	self assertBlackAt: 200 @ (table headerHeight - 0.5) in: form.
	self assert: (self fractionDarkIn: (table rowRect: 3) of: form) > 0.5
!
testTableBarCellFills
	| table form r rects |
	table := self processTable.
	self open: table extent: 400 @ 120.
	form := self render.
	rects := table columnRectsFor: 400.
	r := table rowRect: 3.
	"the CPU track of the 50% row: filled on its left part, empty on its right part"
	self assertBlackAt: ((rects at: 5) first + 10) @ r center y in: form.
	self assertWhiteAt: ((rects at: 5) first + 40) @ r center y in: form
!
testKeyValueList
	| kv |
	kv := KeyValueList new.
	kv items: {'self' -> #(1 2 3). 'class' -> Array. 'size' -> 3}.
	self open: kv extent: 200 @ 100.
	self assert: (kv labelOf: kv items first) equals: 'self'.
	self assert: (kv rightTextOf: kv items first) equals: '#(1 2 3)'.
	self assert: (kv rightTextOf: kv items last) equals: '3'.
	self render
!
testSparkline
	| spark form clicked |
	spark := Sparkline new values: #(4 8 16 2); reference: 8; highlight: 3; yourself.
	spark onClick: [:i | clicked := i].
	self open: spark extent: 40 @ 20.
	form := self render.
	self assertBlackAt: 5 @ 18 in: form.
	self assert: ((self rgbAt: 25 @ 17 in: form) at: 3) > 100.
	self assertWhiteAt: 5 @ 3 in: form.
	self click: 35 @ 10.
	self assert: clicked equals: 4.
	self assert: (spark remoteState includes: 'n=4')
!
testProgressStripe
	| bar form |
	bar := ProgressStripe new.
	self open: bar extent: 100 @ 4.
	bar fraction: 0.5.
	form := self render.
	self assert: ((self rgbAt: 25 @ 2 in: form) at: 1) < 60.
	self assertWhiteAt: 75 @ 2 in: form.
	bar fraction: nil; active: true.
	form := self render.
	self assert: (self inkIn: (0 @ 0 corner: 100 @ 4) of: form) > 100.
	self assert: bar remoteState equals: #(#busy)
!
testBusyIndicatorAndToast
	| busy toast row form |
	busy := BusyIndicator new fixed: 12.
	toast := ToastView new fixed: 200.
	row := Row with: {busy. toast}.
	self open: row extent: 212 @ 30.
	busy active: true.
	toast show: 'Nothing to accept here'.
	self assert: toast isVisible.
	self assert: toast opacity equals: 1.
	form := self render.
	self assert: (self inkIn: (0 @ 9 corner: 12 @ 21) of: form) > 10.
	self assert: (self fractionDarkIn: (20 @ 5 corner: 190 @ 20) of: form) > 0.3.
	window fireTimers.
	self deny: toast isVisible
!
testBrowserSnapshot
	| packages classes code status root text snapshot |
	packages := ListView new title: 'Packages'; name: 'packages'; items: #('Kernel-Objects' 'Kernel-Numbers'); yourself.
	classes := ListView new title: 'Classes'; name: 'classes'; items: #('Object' 'Boolean'); yourself.
	code := TextEditor new title: 'code'; name: 'code'; yourself.
	code text: 'printOn: aStream'.
	code onAccept: [:t | true].
	status := StatusBar new name: 'status'; yourself.
	status text: 'Object>>printOn:'.
	root := Column with: {
		(Row with: {packages. classes. (ToggleGroup options: #('instance' '?' 'class') selected: 1) name: 'side'; yourself}) fixed: 120; yourself.
		code.
		status}.
	self open: root extent: 500 @ 300.
	packages select: 'Kernel-Numbers'.
	snapshot := RemoteSnapshot root: window world refTable: RemoteRefTable new.
	text := snapshot renderDepth: 5 bounds: false maxItems: 100.
	self assert: (text includesSubstring: 'list @w1.packages "Packages" sel="Kernel-Numbers" n=2').
	self assert: (text includesSubstring: 'item @w1.packages.kernel-numbers "Kernel-Numbers" selected').
	self assert: (text includesSubstring: 'button @w1.side.instance "instance" on').
	self assert: (text includesSubstring: 'editor @w1.code "code" lines=1 caret=0 dirty=false').
	self assert: (text includesSubstring: '| printOn: aStream').
	self assert: (text includesSubstring: 'status @w1.status "Object>>printOn:"').
	self assert: (snapshot resolve: '@w1.classes.boolean') notNil.
	self assert: (snapshot resolve: '@w1.classes.boolean') widget remoteClickPoint
		equals: (classes localToScreen: (classes rowRect: 2) center)
! !
