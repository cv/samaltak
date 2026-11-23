WidgetTestCase subclass: #MenuViewTest
	instanceVariableNames: 'menu view chosen'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

MenuViewTest comment: 'I check the Menu model and MenuView: keyboard navigation skipping headers, separators and disabled items, type-ahead, choosing by key and click (the view closes first), escape, hover highlight, check marks, remote rows, and the inverted highlight pixels.'!

!MenuViewTest methodsFor: 'running'!
setUp
	super setUp.
	chosen := nil.
	menu := (Menu title: 'World')
		addHeader: 'open…';
		add: 'System Browser' action: [chosen := #browser];
		add: 'Workspace' action: [chosen := #workspace];
		add: 'Profiler' description: 'samples · frames' action: [chosen := #profiler];
		addSeparator;
		add: 'User interrupt' key: '⌘.' action: [chosen := #interrupt];
		yourself.
	(menu add: 'Disabled' action: [chosen := #disabled]) enabled: false.
	menu add: 'Halos' checked: true action: [chosen := #halos].
	view := menu asMenuView.
	self open: view extent: view preferredExtent.
	view focus.
	window world openMenu: view at: 0 @ 0
! !

!MenuViewTest methodsFor: 'tests'!
testKeyboardNavigation
	self key: #down.
	self assert: view highlightedItem label equals: 'System Browser'.
	self key: #down; key: #down; key: #down.
	self assert: view highlightedItem label equals: 'User interrupt'.
	self key: #down.
	self assert: view highlightedItem label equals: 'Halos'.
	self key: #down.
	self assert: view highlightedItem label equals: 'System Browser'.
	self key: #up.
	self assert: view highlightedItem label equals: 'Halos'.
	self key: #return.
	self assert: chosen equals: #halos.
	self assert: view isClosed.
	self assert: window world menus isEmpty
!
testTypeAheadAndEscape
	self type: 'p'.
	self assert: view highlightedItem label equals: 'Profiler'.
	self key: #escape.
	self assert: view isClosed.
	self assert: chosen isNil
!
testClickAndHover
	| r |
	r := view itemRect: 3.
	self move: r center.
	self assert: view highlightIndex equals: 3.
	self click: r center.
	self assert: chosen equals: #workspace
!
testChoosingInUnhostedSubmenuClosesItsParent
	"Without overlays: the stand-in World hosts neither menu in one."
	| sub |
	menu add: 'More' submenu: (Menu new add: 'Deep' action: [chosen := #deep]; yourself).
	self click: (view itemRect: menu items size) center.
	sub := window world lastMenu.
	sub chooseLabeled: 'Deep'.
	self assert: chosen equals: #deep.
	self assert: sub isClosed.
	self assert: view isClosed
!
testReleaseWithoutPressDoesNotChoose
	self up: (view itemRect: 3) center.
	self assert: chosen isNil.
	self deny: view isClosed
!
testReleaseBesideTheMenuDoesNotChoose
	"A press in the menu captures the pointer: a release beside it, at an item's height (over a submenu), chooses nothing."
	| r |
	r := view itemRect: 3.
	self down: r center.
	self up: (view width + 20) @ r center y.
	self assert: chosen isNil.
	self deny: view isClosed
!
testDisabledItemsAreSkippedAndInert
	| r |
	r := view itemRect: 7.
	self click: r center.
	self assert: chosen isNil.
	self deny: view isClosed
!
testPreferredExtentFitsItems
	| e |
	e := view preferredExtent.
	self assert: e x >= 210.
	self assert: e y equals: (view itemTops last + 21 + 3 + 1)
!
testItemsInsetAlikeAtTopAndBottom
	"Between the frame (or the title's rule) and the first item as much space as between the last item and the frame: with a title and without."
	| untitled v |
	self assert: view itemTops first equals: 1 + view titleHeight + 3.
	untitled := Menu new add: 'Agent' action: []; add: 'Quit' action: []; yourself.
	v := untitled asMenuView.
	self assert: v itemTops first - 1 equals: 3.
	self assert: v preferredExtent y - 1 - ((v itemTops last) + (v heightOf: untitled items last)) equals: 3
!
testRemoteRows
	| rows |
	rows := view remoteChildren.
	self assert: view remoteRole equals: #menu.
	self assert: view remoteLabel equals: 'World'.
	self assert: rows first remoteRole equals: #head.
	self assert: (rows collect: [:each | each remoteLabel]) asArray
		equals: #('open…' 'System Browser' 'Workspace' 'Profiler' 'User interrupt' 'Disabled' 'Halos').
	self assert: ((rows at: 4) remoteState includes: 'desc="samples · frames"').
	self assert: ((rows at: 5) remoteState includes: 'key="⌘."').
	self assert: ((rows at: 6) remoteState includes: #disabled).
	self assert: ((rows at: 7) remoteState includes: #checked)
!
testHighlightIsInverted
	| form r |
	view highlightIndex: 2.
	form := self render.
	r := view itemRect: 2.
	self assert: (self fractionDarkIn: r of: form) > 0.6.
	r := view itemRect: 3.
	self assert: (self fractionDarkIn: r of: form) < 0.2
! !
