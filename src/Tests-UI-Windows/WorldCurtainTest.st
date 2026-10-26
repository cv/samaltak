UIWindowsTestCase subclass: #WorldCurtainTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

WorldCurtainTest comment: 'Tests what covers the screen while the image comes and goes: the restart splash hides the desktop until its windows are composited (and for its minimum time), the fade to black before the VM goes away.'!

!WorldCurtainTest methodsFor: 'tests'!
testRestartSplashCoversTheDesktopUntilItIsComposited
	| w form t0 |
	w := self open: (RecordingTestView new color: Color ultramarine; yourself) title: 'Blue' at: (100 @ 100 extent: 300 @ 200).
	t0 := Time millisecondClockValue.
	world showRestartSplash.
	self deny: world isSettled.
	form := self screenshot.
	self deny: (self rgbAt: w contentOrigin + (50 @ 50) in: form) = #(27 58 140).
	"the splash's box, white, in the middle of the screen"
	self assertColor: Color white at: (world extent / 2) rounded + (100 @ 0) in: form.
	self assert: (self waitFor: [world curtain isNil] timeout: 5000) description: 'the splash did not end'.
	self assert: Time millisecondClockValue - t0 >= WorldCurtain minimumMilliseconds.
	self assertColor: Color ultramarine at: w contentOrigin + (50 @ 50) in: self screenshot
!
testLeavingFadesToBlack
	| curtain |
	curtain := WorldCurtain leaving: world.
	self deny: curtain isBlack.
	(Delay forMilliseconds: WorldCurtain fadeMilliseconds + 20) wait.
	self assert: curtain isBlack.
	self deny: curtain isDone
! !
