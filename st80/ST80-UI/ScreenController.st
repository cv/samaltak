Object subclass: #ScreenController
	instanceVariableNames: 'windows drag offset outline process'
	classVariableNames: 'Current'
	package: 'ST80-UI'!

ScreenController comment: 'I am the desk: the grey screen, the windows on it front to back (the first is the active one), and the loop that runs them (run): take the input events, step the windows, flush the frame, sleep. A click activates the window under it, which comes to the front; a drag on a title tab moves a window, its outline following the pointer; keys go to the active window.'!

Smalltalk at: #Display put: nil!

Smalltalk at: #Transcript put: nil!

!ScreenController class methodsFor: 'running'!
open
	"Open the screen and run the desk (never returns)."
	Smalltalk at: #Display put: DisplayScreen new.
	(Display open: 640 @ 400) ifFalse: [
		Transcript show: 'No display: the Smalltalk-80 guest runs in the VM Simulator.'; cr.
		^Smalltalk quit: 1].
	Current := self new.
	Current openWindows.
	Transcript show: 'Smalltalk-80 on ' , Smalltalk vmBanner , ', ' , self classCount printString , ' classes'; cr.
	Current run
!
current
	^Current
!
classCount
	| n |
	n := 0.
	Smalltalk allClassesDo: [:c | n := n + 1].
	^n
! !

!ScreenController methodsFor: 'windows'!
openWindows
	"The Workspace, the Transcript and the ball, in cells of the font."
	| cell |
	cell := Display cell.
	windows := OrderedCollection new.
	windows add: (SystemView
		title: 'Workspace'
		frame: (16 @ 40 extent: (44 * cell x + 8) @ (14 * cell y + 6))
		view: (TextView text: self class workspaceText)).
	windows add: (SystemView
		title: 'System Transcript'
		frame: (346 @ 40 extent: (40 * cell x + 8) @ (8 * cell y + 6))
		view: Transcript).
	windows add: (SystemView
		title: Smalltalk vmBanner
		frame: (346 @ (64 + (9 * cell y)) extent: (40 * cell x + 8) @ (380 - (64 + (9 * cell y))))
		view: BallView new).
	self arrange; displayAll
!
activeWindow
	^windows isNil ifTrue: [nil] ifFalse: [windows first]
!
arrange
	"The windows moved or changed places: tell each whether one in front of it overlaps it."
	windows doWithIndex: [:w :i |
		w covered: ((windows first: i - 1) anySatisfy: [:front | front bounds intersects: w bounds])]
!
activate: aWindow
	| old |
	old := windows first.
	windows remove: aWindow.
	windows addFirst: aWindow.
	self arrange.
	old displayTab.
	aWindow display
!
displayAll
	Display grey: Display bounds.
	windows reverseDo: [:w | w display]
!
redisplay: aWindow
	"Draw aWindow and the windows in front of it."
	(windows indexOf: aWindow) to: 1 by: -1 do: [:i | (windows at: i) display]
! !

!ScreenController methodsFor: 'running'!
process
	^process
!
run
	"Every 10 ms the input events, every other time a step of the windows (the animation: 50 frames a second), then the frame and sleep. An error goes to the Transcript and the loop goes on."
	| event wake next ticks |
	process := Processor activeProcess.
	wake := Semaphore new.
	next := Time millisecondClockValue.
	ticks := 0.
	[[[(event := Display nextEvent) notNil] whileTrue: [self dispatch: event].
	  (ticks := ticks + 1) odd ifTrue: [windows do: [:w | w step]].
	  Display flush.
	  next := next + 10 max: Time millisecondClockValue.
	  self signal: wake atMilliseconds: next.
	  wake wait] repeat]
		on: Error
		do: [:e |
			Transcript show: e class name , ': ' , e messageText; cr.
			e retry]
!
signal: aSemaphore atMilliseconds: anInteger
	<primitive: 'signalAtMilliseconds'>
	^self primitiveFailed
! !

!ScreenController methodsFor: 'events'!
dispatch: anEvent
	| type p |
	type := anEvent at: 1.
	p := (anEvent at: 2) @ (anEvent at: 3).
	type = 1 ifTrue: [^self mouseDown: p].
	type = 3 ifTrue: [^self mouseMove: p].
	type = 2 ifTrue: [^self mouseUp: p].
	type = 4 ifTrue: [^windows first key: (anEvent at: 4) modifiers: (anEvent at: 5)]
!
mouseDown: aPoint
	| w |
	w := windows detect: [:each | each containsPoint: aPoint] ifNone: [^self].
	w == windows first ifFalse: [self activate: w].
	(w tab containsPoint: aPoint) ifTrue: [
		drag := w.
		offset := aPoint - w frame origin.
		outline := w frame.
		^self reverseOutline].
	w mouseDown: aPoint
!
mouseMove: aPoint
	drag isNil ifTrue: [^self].
	self reverseOutline.
	outline := outline translateBy: aPoint - offset - outline origin.
	self reverseOutline
!
mouseUp: aPoint
	drag isNil ifTrue: [^self].
	self reverseOutline.
	drag moveTo: outline origin.
	drag := nil.
	self arrange; displayAll
!
reverseOutline
	"Reverse the outline's edges (twice restores them)."
	Display reverse: (outline origin extent: outline width @ 1).
	Display reverse: (outline left @ (outline bottom - 1) extent: outline width @ 1).
	Display reverse: (outline left @ (outline top + 1) extent: 1 @ (outline height - 2)).
	Display reverse: ((outline right - 1) @ (outline top + 1) extent: 1 @ (outline height - 2))
! !

!ScreenController class methodsFor: 'settings'!
workspaceText
	^'"Smalltalk-80, running on the simulated VM.
Click a line, then cmd-P prints it,
cmd-D does it."
3 + 4
(1 to: 10) inject: 0 into: [:a :b | a + b]
#(3 1 2) asSortedCollection asArray
Smalltalk vmBanner
Transcript show: ''Hello''; cr
'
! !
