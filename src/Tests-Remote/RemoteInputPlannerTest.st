TestCase subclass: #RemoteInputPlannerTest
	instanceVariableNames: 'planner'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteInputPlannerTest comment: 'Tests the event sequences RemoteInputPlanner produces (event format and codes from vm/platform/README.md).'!

!RemoteInputPlannerTest methodsFor: 'running'!
setUp
	planner := RemoteInputPlanner new
! !

!RemoteInputPlannerTest methodsFor: 'tests'!
testClickWithoutPointer
	| plan events |
	plan := planner click: 100 @ 50.
	self assert: plan types equals: #(1 2 3).
	events := plan events.
	self assert: (events allSatisfy: [:e | e size = 8]).
	self assert: (events at: 2) equals: {2. nil. 100.0. 50.0. 1. 0. 1. nil}.
	self assert: (events at: 3) equals: {3. nil. 100.0. 50.0. 1. 0. 1. nil}.
	self assert: planner pointer equals: 100 @ 50
!
testDoubleAndRightClick
	| plan |
	planner pointer: 10 @ 10.
	plan := planner click: 10 @ 10 button: 1 count: 2 modifiers: 0.
	self assert: plan types equals: #(2 3 2 3).
	self assert: (plan events collect: [:e | e at: 7]) equals: #(1 1 2 2).
	plan := planner click: 10 @ 10 button: 3 count: 1 modifiers: 9.
	self assert: (plan events collect: [:e | e at: 5]) equals: #(3 3).
	self assert: (plan events collect: [:e | e at: 6]) equals: #(9 9)
!
testTravel
	| plan moves |
	planner pointer: 0 @ 0; windowId: 7.
	plan := planner click: 160 @ 80.
	moves := plan events select: [:e | e first = 1].
	"100 ms of travel, a move every 16 ms (the prototype's pointer glides 0.1 s)"
	self assert: moves size equals: 6.
	self assert: ((moves last at: 3) @ (moves last at: 4)) equals: 160.0 @ 80.0.
	self assert: ((moves collect: [:e | e at: 3]) asArray isSortedBy: [:a :b | a <= b]).
	self assert: (moves first at: 3) < 20.
	self assert: plan duration >= 80.
	self assert: (plan events allSatisfy: [:e | (e at: 8) = 7])
!
testDrag
	| plan types down up heldMoves |
	planner pointer: 0 @ 0; travelMilliseconds: 64; dragMilliseconds: 64.
	plan := planner drag: 10 @ 10 to: 110 @ 60 modifiers: 0.
	types := plan types.
	down := types indexOf: 2.
	up := types indexOf: 3.
	self assert: down > 1.
	self assert: up equals: types size.
	heldMoves := (plan events copyFrom: down + 1 to: up - 1).
	self assert: heldMoves size equals: 4.
	self assert: (heldMoves allSatisfy: [:e | e first = 1 and: [(e at: 5) = 1]]).
	self assert: ((plan events at: down) at: 3) equals: 10.0.
	self assert: ((plan events at: up) at: 3) equals: 110.0.
	self assert: ((plan events at: up) at: 4) equals: 60.0
!
testKeyCombo
	| plan events |
	plan := planner keyCombo: 'Meta+p'.
	events := plan events.
	self assert: plan types equals: #(5 5 6 6).
	self assert: ((events collect: [:e | e at: 5]) asArray) equals: {16r400000E3. 112. 112. 16r400000E3}.
	self assert: ((events collect: [:e | e at: 6]) asArray) equals: #(8 8 8 0).
	plan := planner keyCombo: 'Shift+Meta+Z'.
	self assert: plan types equals: #(5 5 5 6 6 6).
	self assert: ((plan events at: 3) at: 5) equals: 122.
	self assert: ((plan events at: 3) at: 6) equals: 9
!
testKeyTypesText
	| plan |
	plan := planner keyCombo: 'a'.
	self assert: plan types equals: #(5 7 6).
	self assert: ((plan events at: 2) at: 7) equals: 'a'.
	plan := planner keyCombo: 'Shift+a'.
	self assert: plan types equals: #(5 5 7 6 6).
	self assert: ((plan events at: 3) at: 7) equals: 'A'.
	plan := planner keyCombo: 'Escape'.
	self assert: plan types equals: #(5 6).
	self assert: ((plan events at: 1) at: 5) equals: 27.
	self assert: ((planner keyCombo: 'Down') events first at: 5) equals: 16r40000051.
	self assert: ((planner keyCombo: 'F5') events first at: 5) equals: 16r4000003E.
	self assert: ((planner keyCombo: 'Meta++') events at: 2) equals: {5. nil. 0.0. 0.0. 43. 8. false. nil}.
	self assert: ((planner keyCombo: 'Meta+.') events at: 2) equals: {5. nil. 0.0. 0.0. 46. 8. false. nil}.
	self assert: ((planner keyCombo: '+') types) equals: #(5 7 6)
!
testKeyErrors
	self should: [planner keyCombo: 'Hyper+a'] raise: RemoteError.
	self should: [planner keyCombo: 'Meta+Nope'] raise: RemoteError.
	self should: [planner keyCombo: ''] raise: RemoteError.
	self assert: (RemoteInputPlanner modifiersFrom: 'Shift+Meta') equals: 9.
	self assert: (RemoteInputPlanner modifiersFrom: nil) equals: 0.
	self assert: (RemoteInputPlanner modifiersFrom: 'ctrl+ALT') equals: 6
!
testTypeText
	| plan |
	plan := planner typeText: 'ab', (String with: Character lf), 'c'.
	self assert: plan types equals: #(7 7 5 6 7).
	self assert: ((plan events collect: [:e | e at: 7]) asArray) equals: {'a'. 'b'. false. false. 'c'}.
	self assert: ((plan events at: 3) at: 5) equals: 13.
	self assert: (plan steps collect: [:s | s first]) asArray equals: #(0 8 8 0 8).
	self assert: (planner typeText: '') isEmpty
!
testScroll
	| plan |
	plan := planner scroll: 5 @ 6 delta: 0 @ -3 modifiers: 0.
	self assert: plan types equals: #(1 4).
	self assert: (plan events last at: 7) equals: 0.0 @ -3.0
!
testDevicePlaysThroughInjector
	| device events |
	events := OrderedCollection new.
	device := RemoteInputDevice new injector: [:e | events add: e]; settleMilliseconds: 0; yourself.
	self assert: (device play: (device planner click: 30 @ 40)).
	self assert: (events collect: [:e | e first]) asArray equals: #(1 2 3).
	self assert: device pointer equals: 30.0 @ 40.0.
	events removeAll.
	device play: (device planner keyCombo: 'Escape').
	self assert: (events collect: [:e | e first]) asArray equals: #(5 6)
! !
