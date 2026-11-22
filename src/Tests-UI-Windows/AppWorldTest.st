UIWindowsTestCase subclass: #AppWorldTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

AppWorldTest comment: 'Tests AppWorld and AppWindow on a hidden host window: the window fills the host window without chrome, gets events at its own coordinates, there is no top bar, frames are presented only when something changed, and closing the last window ends the (hidden) world.'!

!AppWorldTest methodsFor: 'running'!
setUp
	previous := World current.
	world := AppWorld openExtent: 300 @ 200 title: 'App test' hidden: true
! !

!AppWorldTest methodsFor: 'support'!
openApp: aView
	| w |
	w := AppWindow new title: 'App'; content: aView; yourself.
	w openIn: world.
	self settle.
	^w
! !

!AppWorldTest methodsFor: 'tests'!
testWindowFillsTheHostWindowWithoutChrome
	| w form |
	w := self openApp: (RecordingTestView new color: (Color r: 1 g: 0 b: 0); yourself).
	self assert: w bounds equals: (0 @ 0 extent: 300 @ 200).
	self assert: w contentBounds equals: w bounds.
	self assert: w content bounds equals: (0 @ 0 extent: 300 @ 200).
	self deny: world showsTopBar.
	self assert: world topBar height equals: 0.
	form := self screenshot.
	#(1 1 298 1 1 198 298 198 150 100) pairsDo: [:x :y |
		self assertColor: (Color r: 1 g: 0 b: 0) at: x @ y in: form]
!
testEventsArriveInContentCoordinates
	| view w |
	view := RecordingTestView new.
	w := self openApp: view.
	self click: 10 @ 12.
	self assert: ((view eventsOfType: #down) collect: [:e | e position]) asArray equals: (Array with: 10 @ 12).
	self assert: (w zoneAt: 1 @ 1) equals: #content.
	self assert: (w zoneAt: 400 @ 1) isNil
!
testPresentsOnlyWhatChanged
	| view w frames |
	view := RecordingTestView new color: Color white; yourself.
	w := self openApp: view.
	self deny: world presentsContinuously.
	frames := world compositor frameCount.
	(Delay forMilliseconds: 200) wait.
	self assert: world compositor frameCount equals: frames.
	w sync: [view color: (Color r: 0 g: 0 b: 1)].
	w invalidate.
	self settle.
	self assert: world compositor frameCount > frames.
	self assertColor: (Color r: 0 g: 0 b: 1) at: 150 @ 100 in: self screenshot
!
testClosingTheLastWindowEndsTheWorld
	| w |
	w := self openApp: RecordingTestView new.
	self assert: world isRunning.
	w close.
	self assert: (self waitFor: [world isRunning not]).
	world := nil
! !
