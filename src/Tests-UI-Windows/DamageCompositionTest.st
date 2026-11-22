UIWindowsTestCase subclass: #DamageCompositionTest
	instanceVariableNames: 'check'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

DamageCompositionTest comment: 'Tests damage-limited composition (docs/graphics-damage.md) with DamageCheck running: every frame drawn in part and every layer rendered in part is compared with drawing it whole, through typing into a window, dragging, raising, opening and closing windows, menus and toasts; a World that changes nothing presents nothing; DamageCheck forcesFull draws every frame whole.'!

!DamageCompositionTest methodsFor: 'running'!
setUp
	super setUp.
	check := DamageCheck start
!
tearDown
	DamageCheck stop.
	DamageCheck forcesFull: false.
	super tearDown
! !

!DamageCompositionTest methodsFor: 'support'!
assertNoMismatches
	self assert: check mismatches = 0 description: check report
!
presentedDuring: aBlock
	| before |
	before := world compositor presentedCount.
	aBlock value.
	self settle.
	^world compositor presentedCount - before
! !

!DamageCompositionTest methodsFor: 'tests'!
testUnchangedWorldPresentsNothing
	"At most the top bar's readout, refreshed twice a second, rides along."
	| v |
	v := RecordingTestView new color: Color ultramarine; yourself.
	self open: v title: 'Blue' at: (100 @ 100 extent: 300 @ 200).
	self assert: (self presentedDuring: [world waitForFrames: 5]) <= 1.
	self assert: (self presentedDuring: [v invalidate. world waitForFrames: 3]) <= 1
!
testStreamedTextRendersPartOfTheLayer
	| v w |
	v := DamageTestView new.
	w := self open: v title: 'Transcript' at: (100 @ 100 extent: 500 @ 400).
	1 to: 12 do: [:i |
		v add: 'line ', i printString, ' of streamed text'.
		self settle].
	self assert: w layer lastDamage notNil description: 'the last line was rendered in part'.
	self assert: w layer lastDamage area < (500 * 400 / 4).
	self assert: check layers > 5.
	self assert: check frames > 5.
	self assertNoMismatches
!
testDraggingAndRaising
	| a b |
	a := self open: (RecordingTestView new color: Color ultramarine; yourself) title: 'A' at: (100 @ 100 extent: 300 @ 200).
	b := self open: (DamageTestView new color: Color white; yourself) title: 'B' at: (250 @ 180 extent: 300 @ 200).
	b content add: 'over A'.
	self settle.
	self drag: 200 @ 110 to: 500 @ 400.
	self drag: 500 @ 400 to: 480 @ 390.
	self click: 350 @ 360.
	self click: 600 @ 300.
	self assert: check frames > 3.
	self assertNoMismatches
!
testOpenCloseMenusAndToasts
	| a b |
	a := self open: (DamageTestView new color: Color white; yourself) title: 'A' at: (100 @ 100 extent: 300 @ 200).
	b := self open: (RecordingTestView new color: Color ultramarine; yourself) title: 'B' at: (450 @ 150 extent: 300 @ 200).
	world toast: 'Hello'.
	self settle.
	b close.
	self settle.
	self rightClick: 800 @ 600.
	self key: #escape modifiers: 0.
	self settle.
	a content add: 'after'.
	self settle.
	self assertNoMismatches
!
testForcesFullDrawsWhole
	| v |
	DamageCheck forcesFull: true.
	v := DamageTestView new.
	self open: v title: 'Full' at: (100 @ 100 extent: 300 @ 200).
	v add: 'one'.
	self settle.
	self assert: (self presentedDuring: [v add: 'two']) > 0.
	"Nothing drawn in part: nothing to compare."
	self assert: check frames equals: 0.
	self assert: check layers equals: 0
! !
