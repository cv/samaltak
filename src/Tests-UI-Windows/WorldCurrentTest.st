UIWindowsTestCase subclass: #WorldCurrentTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

WorldCurrentTest comment: 'Tests World current while Worlds come and go, as they do when tests run in a live image: a World that stops while current gives back the World current before it that still runs (also when Worlds stop out of order), a stopped World is never made current, and when none is current (or it stopped) windows open in the running World instead of failing with "No World to open in".'!

!WorldCurrentTest methodsFor: 'tests'!
testStoppingTheCurrentWorldGivesBackThePrevious
	| b |
	self assert: World current identicalTo: world.
	b := World openHidden: 400 @ 300.
	[self assert: World current identicalTo: b] ensure: [b stop].
	self assert: World current identicalTo: world
!
testWorldsStoppedOutOfOrder
	| b c |
	b := World openHidden: 400 @ 300.
	c := World openHidden: 400 @ 300.
	[b stop.
	 self assert: World current identicalTo: c.
	 c stop.
	 self assert: World current identicalTo: world]
		ensure: [b stop. c stop]
!
testAStoppedWorldIsNeverCurrent
	| b |
	b := World openHidden: 400 @ 300.
	b stop.
	World current: b.
	self assert: World current identicalTo: world.
	self assert: b isStopped
!
testNoCurrentWorldFallsBackToTheRunningOne
	World current: nil.
	self assert: World current identicalTo: world
!
testWindowsOpenInTheRunningWorld
	| b w |
	b := World openHidden: 400 @ 300.
	b stop.
	w := Window new title: 'late'; content: RecordingTestView new; bounds: (100 @ 100 extent: 200 @ 150); yourself.
	w openIn: b.
	self assert: w world identicalTo: world.
	self assert: (world windows includes: w).
	World current: nil.
	w := Window new title: 'later'; content: RecordingTestView new; bounds: (120 @ 120 extent: 200 @ 150); yourself.
	w open.
	self assert: w world identicalTo: world
! !
