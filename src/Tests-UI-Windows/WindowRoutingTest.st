UIWindowsTestCase subclass: #WindowRoutingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

WindowRoutingTest comment: 'Tests input routing: pointer events to the window and view under the pointer (local positions, bubbling, capture, hover), keys and text to the keyboard focus of the active window, context menus, cursors, ⌘. and errors in window Processes.'!

!WindowRoutingTest methodsFor: 'tests'!
testPointerGoesToViewUnderPointerWithLocalPosition
	| a b wa wb downs |
	a := RecordingTestView new.
	b := RecordingTestView new.
	wa := self open: a title: 'A' at: (100 @ 100 extent: 300 @ 200).
	wb := self open: b title: 'B' at: (500 @ 100 extent: 300 @ 200).
	self click: wa contentOrigin + (30 @ 40).
	self click: wb contentOrigin + (5 @ 6).
	downs := a eventsOfType: #down.
	self assert: downs size equals: 1.
	self assert: downs first position equals: 30 @ 40.
	self assert: downs first globalPosition equals: wa contentOrigin + (30 @ 40).
	self assert: downs first button equals: 1.
	self assert: ((b eventsOfType: #down) collect: [:e | e position]) asArray equals: (Array with: 5 @ 6).
	self assert: (a eventsOfType: #up) size equals: 1
!
testBubblingAndHitTesting
	| outer inner w down |
	outer := RecordingTestView new.
	inner := RecordingTestView new handles: false; yourself.
	outer addSubview: inner.
	inner bounds: (50 @ 50 extent: 100 @ 60).
	w := self open: outer title: 'Nested' at: (100 @ 100 extent: 400 @ 300).
	self click: w contentOrigin + (60 @ 70).
	self assert: (inner eventsOfType: #down) first position equals: 10 @ 20.
	down := (outer eventsOfType: #down) first.
	self assert: down position equals: 60 @ 70.
	self assert: (w content viewAt: 60 @ 70) == inner.
	self assert: (w content viewAt: 10 @ 10) == outer
!
testPointerCaptureAndHover
	| v w moves |
	v := RecordingTestView new.
	w := self open: v title: 'Capture' at: (100 @ 100 extent: 300 @ 200).
	self moveTo: w contentOrigin + (10 @ 10).
	self down: w contentOrigin + (10 @ 10).
	self moveTo: 900 @ 650.
	self up: 900 @ 650.
	self settle.
	moves := v eventsOfType: #move.
	self assert: (moves anySatisfy: [:e | e position = (900 @ 650 - w contentOrigin)]).
	self assert: (v eventsOfType: #up) last position equals: 900 @ 650 - w contentOrigin.
	self assert: (v eventsOfType: #enter) size >= 1.
	self moveTo: 950 @ 680.
	self settle.
	self assert: (v eventsOfType: #leave) size >= 1
!
testKeyboardFocusFollowsClickedWindow
	| a b wa wb |
	a := RecordingTestView new.
	b := RecordingTestView new.
	wa := self open: a title: 'A' at: (100 @ 100 extent: 300 @ 200).
	wb := self open: b title: 'B' at: (500 @ 100 extent: 300 @ 200).
	self assert: world activeWindow == wb.
	self click: wa contentOrigin + (20 @ 20).
	self assert: world activeWindow == wa.
	self assert: wa keyboardFocus == a.
	self assert: a isFocused.
	self key: $x modifiers: 0.
	self type: 'xy'.
	self assert: ((a eventsOfType: #down) select: [:e | e isKey]) first key equals: $x.
	self assert: (a eventsOfType: #text) first string equals: 'xy'.
	self assert: (b events select: [:e | e isUIEvent and: [e isKey]]) isEmpty.
	self assert: (a events includes: #focusGained).
	self click: wb contentOrigin + (20 @ 20).
	self key: #return modifiers: 1.
	self settle.
	self assert: ((b eventsOfType: #down) select: [:e | e isKey]) first key equals: #return.
	self assert: ((b eventsOfType: #down) select: [:e | e isKey]) first modifiers shift.
	self deny: a isFocused
!
testRightClickAndControlClickAreButtonTwoAndOpenContextMenus
	| v w menu |
	v := RecordingTestView new handles: false; yourself.
	menu := RecordingTestView new color: Color black; yourself.
	menu bounds: (0 @ 0 extent: 120 @ 80).
	v menu: menu.
	w := self open: v title: 'Menus' at: (100 @ 100 extent: 300 @ 200).
	self rightClick: w contentOrigin + (30 @ 30).
	self assert: (v eventsOfType: #down) first button equals: 2.
	self assert: world overlays size equals: 1.
	self assert: world overlays first content == menu.
	self assert: world overlays first invoker == w.
	self assert: world keyTarget == world overlays first.
	self assert: world overlays first bounds origin equals: w contentOrigin + (30 @ 30).
	self click: 900 @ 650.
	self assert: world overlays isEmpty.
	self inject: UIEvent evMouseDown at: w contentOrigin + (40 @ 40) button: 1 count: 1 modifiers: 2.
	self inject: UIEvent evMouseUp at: w contentOrigin + (40 @ 40) button: 1 count: 1 modifiers: 2.
	self settle.
	self assert: (v eventsOfType: #down) last button equals: 2.
	self assert: world overlays size equals: 1
!
testContentCursor
	| v w |
	v := RecordingTestView new cursor: #ibeam; yourself.
	w := self open: v title: 'Cursor' at: (100 @ 100 extent: 300 @ 200).
	self moveTo: w contentOrigin + (50 @ 50).
	self settle.
	self moveTo: w contentOrigin + (51 @ 50).
	self settle.
	self assert: w contentCursor equals: #ibeam.
	self assert: world dispatcher cursor equals: #ibeam.
	self moveTo: w bounds bottomRight - (3 @ 3).
	self settle.
	self assert: world dispatcher cursor equals: #resizeNWSE.
	self moveTo: (w bounds right - 1) @ (w bounds top + 100).
	self settle.
	self assert: world dispatcher cursor equals: #resizeEW
!
testUserInterruptKeyCallsHook
	| saved got |
	saved := World userInterruptHandler.
	[World userInterruptHandler: [:window :aWorld | got := window].
	 self open: RecordingTestView new title: 'Interrupt me' at: (100 @ 100 extent: 300 @ 200).
	 self key: $. modifiers: 8.
	 self settle.
	 self assert: got == world activeWindow]
		ensure: [World userInterruptHandler: saved]
!
testErrorInWindowProcessKeepsWindowAlive
	| v w saved |
	saved := Window errorHandler.
	Window errorHandler: nil.
	v := RecordingTestView new failOnClick: true; yourself.
	w := self open: v title: 'Faulty' at: (100 @ 100 extent: 300 @ 200).
	self click: w contentOrigin + (10 @ 10).
	v failOnClick: false.
	self click: w contentOrigin + (20 @ 20).
	self assert: (v eventsOfType: #down) size equals: 2.
	self assert: w process isTerminated not.
	self assert: (world toasts anySatisfy: [:t | t text includesSubstring: 'click failure']).
	Window errorHandler: saved
!
testTooltipAfterRest
	| v w |
	v := RecordingTestView new tooltip: 'A tip'; yourself.
	w := self open: v title: 'Tips' at: (100 @ 100 extent: 300 @ 200).
	self moveTo: w contentOrigin + (40 @ 40).
	self settle.
	self assert: (self waitFor: [world tooltip notNil]) description: 'no tooltip after resting'.
	world changed.
	self settle.
	self assert: world tooltip notNil.
	self assert: world tooltip text equals: 'A tip'.
	self moveTo: w contentOrigin + (60 @ 60).
	self settle.
	self assert: world tooltip isNil
!
testDesktopClickOpensWorldMenu
	| saved menus got |
	saved := World worldMenuBuilder.
	menus := OrderedCollection new.
	[World worldMenuBuilder: [:aWorld :aPoint |
		got := aPoint.
		menus add: (RecordingTestView new bounds: (0 @ 0 extent: 160 @ 120); yourself).
		menus last].
	 self click: 700 @ 500.
	 self assert: got equals: 700 @ 500.
	 self assert: world overlays size equals: 1.
	 self assert: world overlays first content == menus first.
	 self click: 100 @ 600.
	 self assert: menus size equals: 2.
	 self assert: world overlays size equals: 1.
	 self assert: world overlays first content == menus last]
		ensure: [World worldMenuBuilder: saved. world closeMenus]
!
testDisplayScaleChange
	| v w form |
	v := RecordingTestView new color: Color ultramarine; yourself.
	w := self open: v title: 'Scale' at: (100 @ 100 extent: 300 @ 200).
	[DisplayWindow injectEvent: {UIEvent evDisplayScaleChanged. nil. 1.0. 0. 0. 0. nil. world displayWindow windowId}.
	 self settle.
	 self assert: world displayScale equals: 1.0.
	 self assert: Font deviceScale equals: 1.0.
	 self assert: w layer surface scale equals: 1.0.
	 form := self screenshot.
	 self assertColor: Color ultramarine at: w contentOrigin + (50 @ 50) in: form]
		ensure: [world displayScaleChanged: 2.0. self settle]
!
testDoAndSyncRunInWindowProcess
	| v w p |
	v := RecordingTestView new.
	w := self open: v title: 'Sync' at: (100 @ 100 extent: 300 @ 200).
	p := w sync: [Processor activeProcess].
	self assert: p == w process.
	self assert: p window == w.
	self assert: p name equals: 'Sync'.
	self assert: p priority equals: 40
!
testSyncSignalsTheBlocksErrorInTheCaller
	| w block ex |
	w := self open: RecordingTestView new title: 'Sync errors' at: (100 @ 100 extent: 300 @ 200).
	block := [ZeroDivide new signal: 'boom'].
	ex := [w sync: block] on: ZeroDivide do: [:e | e return: e].
	self assert: ex class equals: ZeroDivide.
	self assert: ex messageText equals: 'boom'.
	self assert: ex signalerContext closure == block.
	self assert: ([w sync: [nil foo]] on: MessageNotUnderstood do: [:e | e return: e message selector]) equals: #foo.
	self assert: ([w sync: [1 / 0]] on: ZeroDivide do: [:e | e retryUsing: [5]]) equals: 5.
	self assert: (w sync: [3 + 4]) equals: 7
!
testQueueItemsDeliverThemselves
	"Blocks, WindowTimers and input events in a window's queue run in its Process (deliverTo:)."
	| v w ran fired origin |
	v := RecordingTestView new.
	w := self open: v title: 'Queue' at: (100 @ 100 extent: 300 @ 200).
	origin := w contentOrigin.
	w enqueue: [ran := Processor activeProcess].
	w enqueue: ((PointerEvent type: #down at: 10 @ 10) globalPosition: origin + (10 @ 10); yourself).
	w enqueue: ((PointerEvent type: #up at: 10 @ 10) globalPosition: origin + (10 @ 10); yourself).
	w enqueue: (KeyEvent type: #down keyCode: 97 key: $a repeat: false modifiers: Modifiers none time: 0).
	w enqueue: (TextEvent string: 'x' modifiers: Modifiers none time: 0).
	w after: 0 do: [fired := Processor activeProcess].
	self assert: (self waitFor: [fired notNil]).
	self settle.
	self assert: ran == w process.
	self assert: fired == w process.
	self assert: (v pointerEvents collect: [:e | e type]) asArray equals: #(#down #up).
	self assert: ((v events select: [:e | e isUIEvent and: [e isKey]]) collect: [:e | e key]) asArray equals: #($a).
	self assert: ((v events select: [:e | e isUIEvent and: [e isText]]) collect: [:e | e string]) asArray equals: #('x')
! !
