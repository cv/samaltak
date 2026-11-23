UIWindowsTestCase subclass: #DamageCompositionTest
	instanceVariableNames: 'check elapsed'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

DamageCompositionTest comment: 'Tests damage-limited composition (docs/graphics-damage.md) with DamageCheck running: every frame drawn in part and every layer rendered in part is compared with drawing it whole, through typing into a window, dragging, raising, opening and closing windows, menus and toasts; a World that changes nothing presents nothing; DamageCheck forcesFull draws every frame whole.'!

!DamageCompositionTest methodsFor: 'running'!
setUp
	super setUp.
	check := DamageCheck start
!
tearDown
	DamageCheck stop ifNotNil: [:c | Transcript show: testSelector, ' ', c report; cr].
	DamageCheck forcesFull: false.
	super tearDown
! !

!DamageCompositionTest methodsFor: 'support'!
assertNoMismatches
	self assert: check mismatches = 0 description: check report
!
presentedDuring: aBlock
	"How many frames were presented while aBlock ran and the World settled; elapsed: how long that took (ms)."
	| before t0 |
	before := world compositor presentedCount.
	t0 := Time millisecondClockValue.
	aBlock value.
	self settle.
	elapsed := Time millisecondClockValue - t0.
	^world compositor presentedCount - before
!
readouts
	"How many frames the top bar's readout, refreshed twice a second, may have presented in the last presentedDuring: (more frames take longer on a loaded machine)."
	^elapsed // 500 + 1
! !

!DamageCompositionTest methodsFor: 'tests'!
testUnchangedWorldPresentsNothing
	"At most the top bar's readout, refreshed twice a second, rides along."
	| v n |
	v := RecordingTestView new color: Color ultramarine; yourself.
	self open: v title: 'Blue' at: (100 @ 100 extent: 300 @ 200).
	n := self presentedDuring: [world waitForFrames: 5].
	self assert: n <= self readouts description: n printString, ' frames presented in ', elapsed printString, ' ms'.
	n := self presentedDuring: [v invalidate. world waitForFrames: 3].
	self assert: n <= self readouts description: n printString, ' frames presented in ', elapsed printString, ' ms'
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
testOpaqueWindowAboveHidesDamage
	"Lines streamed into a window under an opaque one damage nothing of the screen where that one covers them; uncovered, they do."
	| a b hidden |
	a := self open: (DamageTestView new color: Color white; yourself) title: 'Under' at: (100 @ 100 extent: 400 @ 300).
	b := self open: (RecordingTestView new color: Color ultramarine; yourself) title: 'Over' at: (60 @ 60 extent: 500 @ 250).
	self settle.
	hidden := self presentedDuring: [
		1 to: 4 do: [:i |
			a content add: 'hidden line ', i printString.
			self settle]].
	self assert: a layer lastDamage notNil description: 'the window under was rendered in part'.
	"At most the top bar's readout, refreshed twice a second."
	self assert: hidden <= (self readouts max: 2) description: hidden printString, ' frames presented in ', elapsed printString, ' ms'.
	b close.
	self settle.
	self assert: (self presentedDuring: [a content add: 'seen line']) > 0.
	self assert: check frames > 3.
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
