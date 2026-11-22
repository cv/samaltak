TestCase subclass: #ToolsTestCase
	instanceVariableNames: 'world breakpoints watchpoints'
	classVariableNames: ''
	package: 'Tests-Tools'!

ToolsTestCase comment: 'I am the abstract superclass of the tools'' integration tests: each test runs a real World on a hidden 1440×900 host window, opens real tool windows (each with its own Process), drives them with injected platform events (the path real and remote input take) or with the widgets'' own protocol run in the window''s Process (Window>>sync:), and checks the real effects: compiled methods, Breakpoints, Watchpoints, Processes. Source writing is off unless a test points SourceFiler at a scratch copy. What a test replaces (World current, SourceFiler default, the World menu and interrupt handler) comes back after it, and only the breakpoints and watchpoints it set are removed.'!

!ToolsTestCase methodsFor: 'running'!
setUp
	self keep: #current of: World.
	self replace: #default of: SourceFiler with: (SourceFiler new sourceDirectory: nil; yourself).
	self keep: #worldMenuBuilder of: World.
	self keep: #userInterruptHandler of: World.
	breakpoints := Breakpoint all.
	watchpoints := Watchpoint all.
	Tools installHooks.
	world := World openHidden: 1440 @ 900
!
tearDown
	[self removeBreakpoints.
	 self terminateForkedProcesses.
	 self terminateDoIts]
		ensure: [world isNil ifFalse: [world stop]]
!
removeBreakpoints
	"Remove the breakpoints and watchpoints this test set; those the image had before it stay."
	breakpoints isNil ifTrue: [^self].
	(Breakpoint all reject: [:each | breakpoints includes: each]) do: [:each | each remove].
	(Watchpoint all reject: [:each | watchpoints includes: each]) do: [:each | each unwatch]
!
timeLimitMilliseconds
	^60000
! !

!ToolsTestCase methodsFor: 'support'!
settle
	world waitUntilSettled: 3000
!
terminateDoIts
	"Terminate the do-its still running in the windows' evaluators and the Processes they forked or adopted (e.g. the World menu's crunch)."
	world isNil ifTrue: [^self].
	world windows do: [:w |
		(w content respondsTo: #evaluator) ifTrue: [
			(w content evaluator running asArray, w content evaluator children asArray) do: [:p | p terminate]]]
!
open: aBlock
	"Evaluate aBlock (which opens a window) and answer the new window."
	| w |
	w := aBlock value.
	self assert: (self waitFor: [w isOpen]) description: 'the window did not open'.
	"What opening queued has run (a window animating every frame may never have an empty queue)."
	w sync: [].
	^w
!
windowTitled: aString
	^world windows detect: [:w | w title = aString] ifNone: [nil]
!
windowsOf: aClass
	^world windows select: [:w | w content isKindOf: aClass]
!
in: aWindow do: aBlock
	"Run aBlock in aWindow's Process and answer its value."
	^aWindow sync: aBlock
!
inject: type at: aPoint button: button count: count modifiers: mods
	DisplayWindow injectEvent: {type. nil. aPoint x. aPoint y. button. mods. count. world displayWindow windowId}
!
moveTo: aPoint
	self inject: 1 at: aPoint button: 0 count: nil modifiers: 0
!
click: aPoint
	self moveTo: aPoint.
	self inject: 2 at: aPoint button: 1 count: 1 modifiers: 0.
	self inject: 3 at: aPoint button: 1 count: 1 modifiers: 0
!
click: aPoint platformCount: n
	"A click the platform counted as the nth of a multi-click (within its double-click interval)."
	self moveTo: aPoint.
	self inject: 2 at: aPoint button: 1 count: n modifiers: 0.
	self inject: 3 at: aPoint button: 1 count: n modifiers: 0
!
key: aKey modifiers: mods
	| code |
	code := UIEvent keyCodeFor: aKey.
	self inject: 5 at: 0 @ 0 button: code count: false modifiers: mods.
	self inject: 6 at: 0 @ 0 button: code count: false modifiers: mods
!
type: aString
	"Type aString (a text event) into the active window's focus."
	DisplayWindow injectEvent: {7. nil. 0. 0. 0. 0. aString. world displayWindow windowId}
!
commandModifier
	"The platform's command modifier bit (⌘ on macOS)."
	^8
!
screenPointOf: aWidget at: aLocalPoint
	^aWidget localToScreen: aLocalPoint
!
openWorkspaceWith: aString
	^self open: [Workspace openOn: aString in: (100 @ 100 extent: 600 @ 300) focus: true]
!
evaluate: aString in: aWorkspaceWindow mode: aSymbol
	"Select aString in the workspace and run do it / print it / inspect it as ⌘D / ⌘P / ⌘I do."
	| ws |
	ws := aWorkspaceWindow content.
	self in: aWorkspaceWindow do: [
		| i |
		i := ws editor text indexOfSubCollection: aString.
		self assert: i > 0 description: 'text not in the workspace'.
		ws editor selectFrom: i to: i + aString size - 1.
		aSymbol == #do ifTrue: [ws editor doIt].
		aSymbol == #print ifTrue: [ws editor printIt].
		aSymbol == #inspect ifTrue: [ws editor inspectIt]].
	self assert: (self waitFor: [ws evaluator running isEmpty]) description: 'the do-it did not finish'.
	self assert: (self waitFor: [aWorkspaceWindow queue isEmpty]) description: 'the window did not settle'.
	^ws
!
markTexts: aStyle in: anEditor
	^(anEditor marksStyled: aStyle) collect: [:m | anEditor text copyFrom: m start + 1 to: m stop]
! !

!ToolsTestCase class methodsFor: 'testing'!
isAbstract
	^self == ToolsTestCase
! !
