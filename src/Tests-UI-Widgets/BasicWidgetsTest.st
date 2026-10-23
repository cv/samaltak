WidgetTestCase subclass: #BasicWidgetsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

BasicWidgetsTest comment: 'I check the simple widgets and layout: rows and columns with fixed, flex and percent sizes, separators, labels, buttons (frame, inversion while pressed, click action, disabled), toggle groups and tabs, pane headers, status bars, splitters, scroll panes.'!

!BasicWidgetsTest methodsFor: 'layout'!
testRowLayout
	| a b c row |
	a := Widget new fixed: 50.
	b := Widget new flex: 1.
	c := Widget new flex: 3.
	row := Row with: {a. b. c}.
	self open: row extent: 250 @ 40.
	self assert: a bounds equals: (0 @ 0 corner: 50 @ 40).
	self assert: b bounds equals: (50 @ 0 corner: 100 @ 40).
	self assert: c bounds equals: (100 @ 0 corner: 250 @ 40)
!
testColumnPercentAndSeparators
	| a b col |
	a := Widget new percent: 25.
	b := Widget new.
	col := (Column with: {a. b}) separators: true; yourself.
	self open: col extent: 100 @ 201.
	self assert: a bounds equals: (0 @ 0 corner: 100 @ 50).
	self assert: b bounds equals: (0 @ 51 corner: 100 @ 201)
!
testSeparatorIsDrawn
	| col form |
	col := (Column with: {Widget new fixed: 20. Widget new}) separators: true; yourself.
	self open: col extent: 60 @ 60.
	form := self render.
	self assertBlackAt: 30 @ 20.5 in: form.
	self assertWhiteAt: 30 @ 19.5 in: form.
	self assertWhiteAt: 30 @ 21.5 in: form
!
testHitTestingAndRemoteFlattening
	| list button row |
	list := Label text: 'left'.
	button := Button label: 'OK'.
	row := Row with: {list. Column with: {button}}.
	self open: row extent: 200 @ 20.
	self assert: (row viewAt: 150 @ 10) == button.
	self assert: (row viewAt: 10 @ 10) == list.
	self assert: (row remoteChildren collect: [:each | each remoteRole]) asArray equals: #(#label #button)
! !

!BasicWidgetsTest methodsFor: 'buttons'!
testButtonClickRunsActionAndInvertsWhilePressed
	| clicks button form |
	clicks := 0.
	button := Button label: 'Debug' action: [clicks := clicks + 1].
	self open: (Row with: {button fixed: 80. Widget new}) extent: 200 @ 20.
	form := self render.
	self assertBlackAt: 0.5 @ 10 in: form.
	self assertWhiteAt: 3 @ 10 in: form.
	self down: 40 @ 10.
	self assert: button isPressed.
	form := self render.
	self assertBlackAt: 3 @ 10 in: form.
	self up: 40 @ 10.
	self assert: clicks equals: 1.
	self deny: button isPressed.
	form := self render.
	self assertWhiteAt: 3 @ 10 in: form
!
testButtonReleaseOutsideDoesNotClick
	| clicks button |
	clicks := 0.
	button := Button label: 'Debug' action: [clicks := clicks + 1].
	self open: (Row with: {button fixed: 80. Widget new}) extent: 200 @ 20.
	self down: 40 @ 10.
	self up: 150 @ 10.
	self assert: clicks equals: 0
!
testDisabledButton
	| clicks button |
	clicks := 0.
	button := Button label: 'Debug' action: [clicks := clicks + 1].
	button enabled: false.
	self open: button extent: 80 @ 20.
	self click: 40 @ 10.
	self assert: clicks equals: 0.
	self assert: (button remoteState includes: #disabled)
!
testDefaultButtonState
	| button |
	button := (Button label: 'Proceed') beDefault; yourself.
	self assert: button remoteState equals: #(#default).
	self assert: button remoteLabel equals: 'Proceed'.
	self assert: button remoteRole equals: #button
! !

!BasicWidgetsTest methodsFor: 'toggles'!
testToggleGroup
	| group chosen form |
	group := ToggleGroup options: #('instance' '?' 'class') selected: 1.
	group onChange: [:key | chosen := key].
	self open: group extent: 180 @ 18.
	form := self render.
	self assertBlackAt: 30 @ 4 in: form.
	self assertWhiteAt: 150 @ 4 in: form.
	self click: 150 @ 9.
	self assert: chosen equals: 'class'.
	self assert: group selectionIndex equals: 3.
	form := self render.
	self assertWhiteAt: 30 @ 4 in: form.
	self assertBlackAt: 150 @ 4 in: form.
	self assert: ((self remoteChildrenOf: group) collect: [:each | each remoteLabel]) asArray equals: #('instance' '?' 'class').
	self assert: (self remoteChildrenOf: group) last remoteState equals: #(#on).
	self assert: (self remoteChildrenOf: group) last remoteClickPoint equals: (group localToScreen: (group segmentRects at: 3) center)
!
testToggleCrossFade
	| group |
	group := ToggleGroup options: #('a' 'b') selected: 1.
	self open: group extent: 100 @ 18.
	window keepAnimations.
	group choose: 2.
	self assert: (group onAmountAt: 2) equals: 0.
	window runAnimationsAt: 0.5.
	self assert: ((group onAmountAt: 2) between: 0.1 and: 0.99).
	self assert: ((group onAmountAt: 1) between: 0.01 and: 0.9).
	window finishAnimations.
	self assert: (group onAmountAt: 2) equals: 1.
	self assert: (group onAmountAt: 1) equals: 0
!
testTabsAreContentSized
	| tabs rects |
	tabs := Tabs options: #('Tree' 'Flame' 'Frames') selected: 1.
	self open: (Column with: {tabs fixed: 20. Widget new}) extent: 400 @ 100.
	rects := tabs segmentRects.
	self assert: rects first left equals: 0.
	self assert: rects last right < 250.
	self assert: (self remoteChildrenOf: tabs) first remoteRole equals: #tab.
	self assert: (self remoteChildrenOf: tabs) first remoteState equals: #(#selected)
! !

!BasicWidgetsTest methodsFor: 'headers and status'!
testPaneHeader
	| header form |
	header := PaneHeader title: 'Packages' right: 'by layer'.
	self open: (Column with: {header. Widget new}) extent: 240 @ 100.
	self assert: header bounds equals: (0 @ 0 corner: 240 @ 20).
	form := self render.
	self assertBlackAt: 100 @ 19.5 in: form.
	self assert: (self inkIn: (0 @ 0 corner: 80 @ 19) of: form) > 20.
	self assert: (self inkIn: (180 @ 0 corner: 240 @ 19) of: form) > 20.
	self assert: header remoteLabel equals: 'Packages'
!
testStatusBar
	| bar |
	bar := StatusBar new.
	bar add: 'Window>>open' style: #mono; add: '3' style: #chip; add: 'Windows'.
	bar addRight: 'unsaved' style: #pillDirty.
	self open: (Column with: {Widget new. bar}) extent: 400 @ 120.
	self assert: bar bounds equals: (0 @ 100 corner: 400 @ 120).
	self render.
	self assert: bar remoteLabel equals: 'Window>>open 3 Windows unsaved'
! !

!BasicWidgetsTest methodsFor: 'splitter and scrolling'!
testSplitterDrag
	| top split bottom col |
	top := Widget new fixed: 100.
	split := Splitter new.
	bottom := Widget new.
	col := Column with: {top. split. bottom}.
	self open: col extent: 200 @ 300.
	self assert: split bounds equals: (0 @ 100 corner: 200 @ 104).
	self drag: 50 @ 102 to: 50 @ 152.
	self assert: top bounds height equals: 150.
	self assert: bottom bounds top equals: 154.
	self drag: 50 @ 152 to: 50 @ 400.
	self assert: bottom bounds height equals: 40
!
testScrollPane
	| pane content |
	content := Widget new minExtent: 100 @ 1000; yourself.
	pane := ScrollPane new content: content; yourself.
	self open: pane extent: 200 @ 100.
	self assert: pane scrollBar isVisible.
	self assert: content bounds top equals: 0.
	self wheel: 50 @ 50 by: -2.
	self assert: pane scrollOffset equals: 80.
	self assert: content bounds top equals: -80.
	pane scrollOffset: 5000.
	self assert: pane scrollOffset equals: 900.
	pane scrollToShow: (0 @ 10 extent: 10 @ 10).
	self assert: pane scrollOffset equals: 10
! !
