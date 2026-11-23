WidgetTestCase subclass: #ListViewTest
	instanceVariableNames: 'list selected'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

ListViewTest comment: 'I drive a ListView with clicks, keys, type-ahead and the wheel, and check the selection, the notifications, scrolling, the gliding bar, the inverted / boxed selection pixels and the remote-control rows.'!

!ListViewTest methodsFor: 'running'!
setUp
	super setUp.
	selected := OrderedCollection new.
	list := ListView new
		title: 'Packages';
		name: 'packages';
		items: #('Tools' 'UI-Widgets' 'UI-Windows' 'Graphics-Canvas' 'Graphics-GPU' 'Kernel-Objects' 'Kernel-Numbers' 'Kernel-Processes');
		rightBlock: [:each | (each copyUpTo: $-) = each ifTrue: [nil] ifFalse: [each copyUpTo: $-]];
		onSelect: [:item | selected add: item];
		yourself.
	self open: list extent: 240 @ 100
!
rowCenter: index
	^(list rowRect: index) center
! !

!ListViewTest methodsFor: 'tests'!
testClickSelectsAndNotifies
	self click: (self rowCenter: 3).
	self assert: list selection equals: 'UI-Windows'.
	self assert: selected asArray equals: #('UI-Windows').
	self assert: window keyboardFocus == list.
	self click: (self rowCenter: 3).
	self assert: selected size equals: 1
!
testDoubleClick
	| opened |
	list onDoubleClick: [:item | opened := item].
	self click: (self rowCenter: 2) count: 2.
	self assert: opened equals: 'UI-Widgets'
!
testKeyboardNavigation
	list focus.
	self key: #down.
	self assert: list selectionIndex equals: 1.
	self key: #down; key: #down.
	self assert: list selectionIndex equals: 3.
	self key: #up.
	self assert: list selectionIndex equals: 2.
	self key: #end.
	self assert: list selectionIndex equals: 8.
	self key: #down.
	self assert: list selectionIndex equals: 8.
	self key: #home.
	self assert: list selectionIndex equals: 1.
	self key: #pageDown.
	self assert: list selectionIndex > 3.
	self assert: selected size equals: 7
!
testTypeAhead
	list focus.
	self type: 'k'.
	self assert: list selection equals: 'Kernel-Objects'.
	self type: 'ernel-n'.
	self assert: list selection equals: 'Kernel-Numbers'.
	list resetTypeAhead.
	self type: 'g'.
	self assert: list selection equals: 'Graphics-Canvas'
!
testScrollKeepsSelectionVisible
	list focus.
	self key: #end.
	self assert: list scrollOffset > 0.
	self assert: (list isRowVisible: 8).
	self key: #home.
	self assert: list scrollOffset equals: 0
!
testWheelScrolls
	self wheel: 50 @ 50 by: -1.
	self assert: list scrollOffset equals: 40.
	self wheel: 50 @ 50 by: -10.
	self assert: list scrollOffset equals: list contentHeight - 100.
	self assert: list children first isVisible
!
testSelectionGlides
	list selectionIndex: 1.
	window keepAnimations.
	list selectionIndex: 3.
	self assert: list barTop equals: (list rowTop: 1).
	window runAnimationsAt: 0.5.
	self assert: (list barTop between: (list rowTop: 1) + 1 and: (list rowTop: 3) - 1).
	window finishAnimations.
	self assert: list barTop equals: (list rowTop: 3)
!
testFocusedSelectionIsInverted
	| form r |
	list focus.
	list selectionIndex: 2.
	form := self render.
	r := list rowRect: 2.
	self assertBlackAt: (r left + 3) @ (r top + 2) in: form.
	self assert: (self fractionDarkIn: r of: form) > 0.6.
	r := list rowRect: 4.
	self assert: (self fractionDarkIn: r of: form) < 0.2
!
testUnfocusedSelectionIsBoxed
	| form r |
	list selectionIndex: 2.
	window keyboardFocus: nil.
	form := self render.
	r := list rowRect: 2.
	self assertBlackAt: (r left + 0.5) @ (r top + 9) in: form.
	self assertBlackAt: (r left + 40) @ (r top + 0.5) in: form.
	self assertWhiteAt: (r left + 3) @ (r top + 3) in: form
!
testHeaderRowsAreNotSelectable
	list items: #('#Kernel' 'Object' 'Number' '#Graphics' 'Canvas').
	list headerBlock: [:each | each first = $#].
	list labelBlock: [:each | each first = $# ifTrue: [each allButFirst] ifFalse: [each]].
	list focus.
	self key: #down.
	self assert: list selection equals: 'Object'.
	self key: #down; key: #down.
	self assert: list selection equals: 'Canvas'.
	self click: (self rowCenter: 1).
	self assert: list selection equals: 'Canvas'.
	self assert: (list remoteChildren first remoteRole) equals: #head
!
testItemsKeepSelection
	list selection: 'Kernel-Objects'.
	list items: #('Kernel-Objects' 'Tools').
	self assert: list selectionIndex equals: 1.
	list items: #('Tools').
	self assert: list selection isNil
!
testContextMenuSelectsRow
	| menuFor |
	list itemMenuBlock: [:item | menuFor := item. (Menu new) add: 'browse' action: []; yourself].
	self rightClick: (self rowCenter: 4).
	self assert: menuFor equals: 'Graphics-Canvas'.
	self assert: list selection equals: 'Graphics-Canvas'.
	self assert: window world lastMenu notNil.
	self assert: (window world lastMenu menu itemLabeled: 'browse') notNil
!
testRemoteProtocol
	| rows |
	list selection: 'UI-Windows'.
	self assert: list remoteRole equals: #list.
	self assert: list remoteLabel equals: 'Packages'.
	self assert: list remoteName equals: 'packages'.
	self assert: (list remoteState includes: 'sel="UI-Windows"').
	self assert: (list remoteState includes: 'n=8').
	rows := list remoteChildren.
	self assert: rows size equals: 8.
	self assert: (rows at: 3) remoteLabel equals: 'UI-Windows'.
	self assert: (rows at: 3) remoteState equals: #(#selected).
	self assert: (rows at: 3) remoteClickPoint equals: (list localToScreen: (list rowRect: 3) center).
	self assert: (rows at: 8) remoteBounds isNil.
	self assert: (rows at: 8) remoteClickPoint notNil.
	self assert: (list isRowVisible: 8)
!
testLayerChipCell
	| form |
	list items: #(5 4 3).
	list rightBlock: nil.
	list cellBlock: (ListView layerChipCell: [:n | n]).
	form := self render.
	self assert: (self inkIn: (8 @ 3 extent: 14 @ 14) of: form) > 50
!
testDrawingIsProportionalToVisibleRows
	| big canvas t0 t1 best |
	big := ListView new items: ((1 to: 5000) collect: [:i | 'item ', i printString]).
	self open: big extent: 240 @ 400.
	"The best of five draws: a loaded machine (a gate's other VMs) can stall one for longer than drawing the visible rows takes; drawing all 5000 is slow every time."
	best := nil.
	5 timesRepeat: [
		canvas := Canvas extent: 240 @ 400 scale: 2.
		t0 := Time millisecondClock.
		big drawOn: canvas.
		t1 := Time millisecondClock.
		best := best isNil ifTrue: [t1 - t0] ifFalse: [best min: t1 - t0]].
	self assert: best < 50 description: 'the best of five draws took ', best printString, ' ms'.
	self assert: canvas vertexCount < 20000
! !
