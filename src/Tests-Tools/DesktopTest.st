ToolsTestCase subclass: #DesktopTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

DesktopTest comment: 'I test the desktop as a whole: the default layout (six tools, each with its own Process, in the prototype''s order), the World menu and its registry, Run long computation (a real ''crunch'' Process), the Process Browser listing the Mandelbrot''s Process as running while it renders, clicks queued while the Mandelbrot window is busy, the user interrupt, the help overlay and Arrange windows.'!

!DesktopTest methodsFor: 'support'!
openLayout
	Tools openDefaultLayout.
	self assert: (self waitFor: [world windows size >= 6]).
	self settle
!
mandelbrot
	^(self windowsOf: MandelbrotView) first
! !

!DesktopTest methodsFor: 'tests'!
testDefaultLayout
	| titles processes |
	self openLayout.
	titles := (world windows reverse collect: [:w | w title]) asArray.
	self assert: titles equals: #('Workspace' 'Transcript' 'Process Browser' 'Mandelbrot' 'Inspector: an Array' 'System Browser: Window').
	self assert: ((world windows reverse collect: [:w | w remoteName]) asArray) equals: #('w1' 'w2' 'w3' 'w4' 'w5' 'w6').
	processes := world windows collect: [:w | w process].
	self assert: (processes asIdentitySet size) equals: 6.
	world windows do: [:w | self assert: w process name equals: w title].
	self assert: world activeWindow title equals: 'System Browser: Window'.
	self assert: (world activeWindow content code text beginsWith: 'open').
	self assert: ((self windowsOf: Workspace) first content text includesSubstring: '48 gcd: 18').
	self assert: ((self windowsOf: TranscriptView) first content text includesSubstring: 'Samaltak 0.1').
	self assert: (self windowsOf: Inspector) first content object equals: {3/4. 3@4. 'text'. #sym. $c. 2 raisedTo: 100}
!
testWorldMenu
	| menu labels overlay |
	menu := ToolsMenu worldMenuAt: 100 @ 100.
	labels := (menu items select: [:i | i isItem]) collect: [:i | i label].
	#('System Browser' 'Workspace' 'Transcript' 'Process Browser' 'Mandelbrot' 'Run long computation' 'User interrupt' 'Arrange windows' 'Save image' 'Help…' 'Quit')
		do: [:each | self assert: (labels includes: each) description: each].
	self assert: (labels indexOf: 'System Browser') < (labels indexOf: 'Mandelbrot').
	ToolsMenu register: 'Test tool' description: 'test' order: 55 action: [:p | nil].
	[labels := ((ToolsMenu worldMenuAt: nil) items select: [:i | i isItem]) collect: [:i | i label].
	 self assert: (labels indexOf: 'Test tool') = ((labels indexOf: 'Mandelbrot') + 1)]
		ensure: [ToolsMenu unregister: 'Test tool'].
	"A click on the desk opens it."
	self click: 720 @ 450.
	self assert: (self waitFor: [world overlays notEmpty]).
	overlay := world overlays last.
	self assert: overlay content menu title equals: 'World'.
	overlay close
!
testSlowMotionMenuItem
	| item |
	item := [((ToolsMenu worldMenuAt: nil) items select: [:i | i isItem]) detect: [:i | i label = 'Slow motion']].
	self deny: item value isChecked.
	[item value run.
	 self assert: Desktop animationTimeScale equals: 10.
	 self assert: item value isChecked.
	 item value run.
	 self assert: Desktop animationTimeScale equals: 1.
	 self deny: item value isChecked]
		ensure: [Desktop animationTimeScale: 1]
!
testRunLongComputation
	| before crunch |
	before := Processor allProcesses asIdentitySet.
	self click: 720 @ 450.
	self assert: (self waitFor: [world overlays notEmpty]).
	self in: world overlays last do: [world overlays last content chooseLabeled: 'Run long computation'].
	"The menu action drops the Process Tools runLongComputation answers: take the new one."
	self assert: (self waitFor: [
		crunch := Processor allProcesses detect: [:p | (before includes: p) not and: [(p name ifNil: ['']) beginsWith: 'crunch']] ifNone: [nil].
		crunch notNil]).
	self track: crunch.
	self assert: crunch priority equals: Processor userBackgroundPriority.
	self assert: (self waitFor: [(self windowsOf: ProcessBrowser) notEmpty]) description: 'the Process Browser opens'
!
testProcessBrowserShowsTheMandelbrotRunning
	| mb pb state |
	self openLayout.
	mb := self mandelbrot.
	self in: mb do: [mb content after: 0 do: [mb content render]].
	self assert: (self waitFor: [mb content isRendering]).
	pb := (self windowsOf: ProcessBrowser) first.
	"The interval the CPU column measures."
	(Delay forMilliseconds: 100) wait.
	state := self in: pb do: [pb content refresh. pb content stateOf: mb process].
	self assert: mb content isRendering.
	self assert: state equals: 'running'.
	self assert: (pb content table items includes: mb process).
	self assert: (self in: pb do: [pb content cpuOf: mb process]) > 5.
	self assert: mb isBusy
!
testMandelbrotQueuesClicksWhileBusy
	| mb view point iterations |
	mb := self open: [MandelbrotView openIn: (900 @ 500 extent: 324 @ 306) delay: 1].
	view := mb content.
	self assert: (self waitFor: [view isRendering]).
	iterations := view maxIterations.
	point := (mb content widgetNamed: 'view') localToScreen: 100 @ 100.
	self click: point.
	self click: point + (10 @ 10).
	self assert: (self waitFor: [view queuedClicks = 2] timeout: 4000) description: 'the two clicks are not counted as queued'.
	self assert: (self waitFor: [view maxIterations = (iterations + 180)] timeout: 30000) description: 'both queued clicks zoom'.
	self assert: view zoomFactor equals: 9
!
testUserInterruptStopsTheBusyProcess
	| busy |
	busy := self fork: [[true] whileTrue: [100 factorial]] named: 'tools test busy' at: 40.
	self assert: (self waitFor: [busy cpuMicroseconds > 0]) description: 'the busy process did not start'.
	self assert: Tools userInterrupt == busy.
	self assert: (self waitFor: [busy isSuspended]) description: 'the busy process was not stopped'.
	self assert: (self waitFor: [(self windowsOf: Notifier) notEmpty]) description: 'no notifier on the busy process'
!
testHelpOverlay
	Tools showHelp.
	self assert: (self waitFor: [world overlays anySatisfy: [:o | o content isKindOf: ToolsHelpView]]).
	self assert: ToolsHelpView isShowing.
	Tools showHelp.
	self assert: (self waitFor: [ToolsHelpView isShowing not])
!
testArrangeWindows
	| browser |
	self openLayout.
	browser := (self windowsOf: SystemBrowser) first.
	browser bounds: (300 @ 300 extent: 600 @ 400).
	Tools arrangeWindows.
	self assert: browser bounds equals: (Tools layoutRect: #browser)
! !
