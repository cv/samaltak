TestCase subclass: #DebuggerUITest
	instanceVariableNames: 'world previous savedOpener savedErrorHandler savedRegistry savedPointer savedWindowId cleanups'
	classVariableNames: ''
	package: 'Tests-Tools-Debugger'!

DebuggerUITest comment: 'End-to-end tests of the debugging tools in a real World on a hidden host window: code runs in a workspace (the core tools'' Workspace when loaded, else DebuggerTestWorkspace) in its own ''Workspace doIt'' Process, every interaction is real input injected through remote control (clicks and keys on refs like @w4.over, @w4.context.evaluator, @menu.integer), and the tests check the live Debugger, Notifier and Breakpoints windows and the debugged Processes. The walkthrough scenarios: a breakpoint on Integer>>gcd:, stepping Over by statements, a temporary''s value, a + b printed in the frame, Proceed; 3 zork, Create in Integer, edit and accept, Proceed; a watchpoint on p := 3 @ 4 hit by a forked mover, Unwatch, Proceed.'!

!DebuggerUITest methodsFor: 'running'!
setUp
	cleanups := OrderedCollection new.
	previous := World current.
	savedOpener := DebugSession openerBlock.
	savedErrorHandler := Window errorHandler.
	world := World openHidden: 1440 @ 900.
	savedRegistry := RemoteControl registryState.
	savedPointer := RemoteInputDevice default pointer.
	savedWindowId := RemoteInputDevice default windowId.
	UIRemote installOn: world.
	DebuggerTools install.
	world waitUntilSettled: 3000
!
tearDown
	self trackDoIts.
	world windows copy do: [:each | each close].
	world waitUntilSettled: 2000.
	self terminateForkedProcesses.
	cleanups reverseDo: [:each | [each value] on: Error do: [:e | e return: nil]].
	UIRemote uninstall.
	RemoteControl registryState: savedRegistry.
	RemoteInputDevice default pointer: savedPointer; windowId: savedWindowId.
	world stop.
	World current: previous.
	DebugSession openerBlock: savedOpener.
	Window errorHandler: savedErrorHandler
!
timeLimitMilliseconds
	^60000
! !

!DebuggerUITest methodsFor: 'remote control'!
remote: aCommand with: pairs
	| request response |
	request := Dictionary new.
	request at: 'cmd' put: aCommand.
	pairs do: [:each | request at: each key put: each value].
	"Remote input reduces Fractions (Integer>>gcd:): never stop at the tests' own breakpoints here."
	response := Breakpoint ignoreDuring: [RemoteControl dispatch: (RemoteRequest on: request)].
	self assert: (response at: 'ok') description: aCommand, ' ', pairs printString, ' failed: ', (response at: 'error' ifAbsent: ['?']) asString.
	^response
!
click: aRef
	^self remote: 'click' with: {'target' -> aRef}
!
rightClick: aRef
	^self remote: 'click' with: {'target' -> aRef. 'button' -> 'right'}
!
type: aString in: aRef
	^self remote: 'type' with: {'target' -> aRef. 'text' -> aString}
!
key: aCombo in: aRef
	^self remote: 'key' with: {'target' -> aRef. 'combo' -> aCombo}
!
select: aSpec in: aRef
	^self remote: 'select' with: {'target' -> aRef. 'spec' -> aSpec}
!
ref: aWindow at: aString
	^'@', aWindow remoteName, aString
! !

!DebuggerUITest methodsFor: 'support'!
waitFor: aBlock description: aString
	self assert: (self waitFor: aBlock timeout: 10000) description: 'timed out waiting for ', aString
!
trackDoIts
	"Have the workspaces' do-its (and the Processes the core Workspace's do-its forked) terminated after the test."
	world windows do: [:w | | c |
		c := w content.
		(c respondsTo: #evaluator) ifTrue: [(c evaluator running asArray, c evaluator children asArray) do: [:p | self track: p]].
		(c isKindOf: DebuggerTestWorkspace) ifTrue: [c processes do: [:p | self track: p]]]
!
windowOf: aClass
	^world windows detect: [:each | each isOpen and: [each content isKindOf: aClass]] ifNone: [nil]
!
waitForWindowOf: aClass
	self waitFor: [(self windowOf: aClass) notNil] description: 'a ', aClass name, ' window'.
	world waitUntilSettled: 3000.
	^self windowOf: aClass
!
waitUntilReady: aWindow
	self waitFor: [aWindow isBusy not and: [aWindow hasPendingWork not]] description: aWindow title, ' to finish'
!
openWorkspace: aString
	| tools w |
	tools := Smalltalk at: #Tools ifAbsent: [nil].
	w := (tools notNil and: [tools respondsTo: #openWorkspaceWith:])
		ifTrue: [tools openWorkspaceWith: aString]
		ifFalse: [DebuggerTestWorkspace openOn: aString in: world].
	world waitUntilSettled: 3000.
	^w
!
editorOf: aWorkspaceWindow
	^aWorkspaceWindow content widgetNamed: 'text'
!
textOf: aWorkspaceWindow
	^(self editorOf: aWorkspaceWindow) text
!
evaluateLine: anInteger in: aWorkspaceWindow with: aCombo
	| ref |
	ref := self ref: aWorkspaceWindow at: '.text'.
	self click: ref.
	self select: 'line:', anInteger printString in: ref.
	self key: aCombo in: ref
!
pcTextOf: aDebugger
	| interval |
	interval := aDebugger pcInterval.
	interval isNil ifTrue: [^nil].
	^aDebugger sourceEditor text copyFrom: interval first to: interval last
!
breakpointOn: aClass selector: aSymbol
	| bp |
	bp := Breakpoint on: aClass selector: aSymbol.
	cleanups add: [bp remove].
	^bp
!
openDebuggerOnGcd
	"A breakpoint on Integer>>gcd: and 48 gcd: 18 printed in a workspace: answer {workspace window. debugger window}."
	| ws dw |
	self breakpointOn: Integer selector: #gcd:.
	ws := self openWorkspace: '48 gcd: 18'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	dw := self waitForWindowOf: Debugger.
	^Array with: ws with: dw
! !

!DebuggerUITest methodsFor: 'tests'!
testBreakpointStepOverEvaluateProceed
	| pair ws dw d steps |
	pair := self openDebuggerOnGcd.
	ws := pair first.
	dw := pair last.
	d := dw content.
	self assert: dw title equals: 'Debugger — Breakpoint: Integer>>gcd:'.
	self assert: d session process name equals: 'Workspace doIt'.
	self assert: d session process isSuspended.
	self assert: (Breakpoint isIgnoring: dw process).
	self assert: (d headerTitle) equals: 'Breakpoint: Integer>>gcd:'.
	self assert: ((dw content widgetNamed: 'process') text) equals: 'Process ''Workspace doIt'' · suspended'.
	self assert: d stackList selection printString equals: 'SmallInteger(Integer)>>gcd:'.
	self assert: (self pcTextOf: d) equals: 'a := self abs'.
	steps := OrderedCollection new.
	4 timesRepeat: [
		self click: (self ref: dw at: '.over').
		self waitUntilReady: dw.
		steps add: (self pcTextOf: d)].
	self assert: (steps at: 1) equals: 'b := anInteger abs'.
	self assert: ((steps at: 2) beginsWith: '[b = 0] whileFalse: [').
	self assert: ((steps at: 2) endsWith: 'b := r]').
	self assert: (steps at: 3) equals: 'b = 0'.
	self assert: (steps at: 4) equals: 'r := a \\ b'.
	self assert: (d sourceEditor pcMark) style equals: #pc.
	self click: (self ref: dw at: '.context.fields.a').
	self waitUntilReady: dw.
	self assert: d contextInspector valuePane text equals: '48'.
	self type: 'a + b' in: (self ref: dw at: '.context.evaluator').
	self key: 'Meta+p' in: (self ref: dw at: '.context.evaluator').
	self waitUntilReady: dw.
	self assert: d contextInspector evaluator text equals: 'a + b 66'.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [(self textOf: ws) includesSubstring: '48 gcd: 18 6'] description: 'the workspace to print 6'
!
testRetainedDrawingWhileStepping
	"Stepping glides the pc mark: in the middle of the glide and after it, the Debugger drawn as its next redraw would (replaying what did not change) draws like drawing it anew, quad for quad and pixel for pixel; and no replay during the steps differed (View verifyDrawing:)."
	| dw d mismatch |
	View verifyDrawing: true.
	cleanups add: [View verifyDrawing: false].
	dw := self openDebuggerOnGcd last.
	d := dw content.
	self waitUntilReady: dw.
	self assert: dw retainedDrawingMismatch isNil.
	3 timesRepeat: [
		self click: (self ref: dw at: '.over').
		self waitUntilReady: dw.
		mismatch := dw retainedDrawingMismatchAfter: [ | glide |
			glide := d sourceEditor instVarNamed: 'pcAnimation'.
			glide isNil ifFalse: [
				glide startTime isNil ifTrue: [glide startAt: Animation now].
				glide stepAt: glide startTime + (glide duration / 2)]].
		self assert: mismatch isNil description: 'mid-glide: ', mismatch printString.
		world waitUntilSettled: 3000.
		mismatch := dw retainedDrawingMismatch.
		self assert: mismatch isNil description: mismatch printString].
	self assert: View staleDrawings isEmpty description: View staleDrawings size printString, ' replays differed from drawing anew'.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'
!
testDoesNotUnderstandCreateAcceptProceed
	| ws nw dw d |
	cleanups add: [Integer removeSelector: #zork].
	ws := self openWorkspace: '3 zork'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'MessageNotUnderstood: SmallInteger>>#zork'.
	self assert: (nw content buttonNamed: 'create') isVisible.
	self assert: nw content session process isSuspended.
	self click: (self ref: nw at: '.create').
	self waitFor: [world overlays notEmpty] description: 'the Create menu'.
	self click: '@menu.integer'.
	dw := self waitForWindowOf: Debugger.
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	d := dw content.
	self waitUntilReady: dw.
	self assert: dw title equals: 'Debugger — MessageNotUnderstood: SmallInteger>>#zork'.
	self assert: (Integer includesSelector: #zork).
	self deny: (Object includesSelector: #zork).
	self assert: d stackList selection printString equals: 'SmallInteger(Integer)>>zork'.
	self assert: d sourceEditor selectedText equals: 'self shouldBeImplemented'.
	self type: 'self * 100' in: (self ref: dw at: '.source').
	self key: 'Meta+s' in: (self ref: dw at: '.source').
	self waitUntilReady: dw.
	self assert: (d sourceEditor text endsWith: '^self * 100').
	self assert: d note equals: 'accepted · frame restarted'.
	self assert: (Integer >> #zork) sourceCode equals: d sourceEditor text.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [(self textOf: ws) includesSubstring: '3 zork 300'] description: 'the workspace to print 300'
!
testWatchpointUnwatchProceed
	| ws iw dw d point before |
	before := Transcript contents size.
	cleanups add: [Watchpoint all do: [:each | (each object isKindOf: Point) ifTrue: [each unwatch]]].
	ws := self openWorkspace: 'p := 3 @ 4
[5 timesRepeat: [p x: p x + 1. Transcript show: p printString; cr]] forkNamed: ''mover'''.
	(Smalltalk at: #Inspector ifAbsent: [nil]) notNil
		ifTrue: [
			"The core tools' Inspector: ⌘I, then Halt on write on the field x."
			self evaluateLine: 1 in: ws with: 'Meta+i'.
			self waitFor: [(world windows detect: [:w | w title beginsWith: 'Inspector'] ifNone: [nil]) notNil] description: 'an Inspector'.
			iw := world windows detect: [:w | w title beginsWith: 'Inspector'].
			world waitUntilSettled: 3000.
			self rightClick: (self ref: iw at: '.fields.x').
			self waitFor: [world overlays notEmpty] description: 'the field menu'.
			self click: '@menu.halt-on-write']
		ifFalse: [
			self evaluateLine: 1 in: ws with: 'Meta+d'.
			self waitFor: [(ws content bindings at: #p ifAbsent: [nil]) notNil] description: 'p'.
			Watchpoint on: (ws content bindings at: #p) value instVarNamed: 'x'].
	self waitFor: [Watchpoint all anySatisfy: [:each | each object = (3 @ 4)]] description: 'the watchpoint'.
	point := (Watchpoint all detect: [:each | each object = (3 @ 4)]) object.
	self assert: point isReadOnlyObject.
	self evaluateLine: 2 in: ws with: 'Meta+d'.
	dw := self waitForWindowOf: Debugger.
	d := dw content.
	self assert: dw title equals: 'Debugger — ModificationForbidden → watchpoint on #x'.
	self assert: d session process name equals: 'mover'.
	self track: d session process.
	self assert: d stackList selection printString equals: '[] in UndefinedObject>>DoIt'.
	self assert: (self pcTextOf: d) equals: 'p x: p x + 1'.
	"The stack starts at the refused store's signal; the do-it's block frame is editable."
	self assert: d stackList items first printString equals: 'ModificationForbidden(Exception)>>signal'.
	self assert: (d stackList items includes: d session process suspendedContext).
	self deny: d sourceEditor isReadOnly.
	self assert: (d buttonNamed: 'unwatch') isVisible.
	self click: (self ref: dw at: '.unwatch').
	self waitUntilReady: dw.
	self deny: (d buttonNamed: 'unwatch') isVisible.
	self deny: point isReadOnlyObject.
	self assert: (Watchpoint forObject: point) isEmpty.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [point x = 8] description: 'the mover to finish'.
	self waitFor: [((Transcript contents copyFrom: before + 1 to: Transcript contents size) includesSubstring: '8@4')] description: 'the mover''s output'.
	self assert: ((Transcript contents copyFrom: before + 1 to: Transcript contents size) includesSubstring: '4@4')
!
testErrorNotifierAbandon
	| ws nw process |
	ws := self openWorkspace: '1/0'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'ZeroDivide'.
	self deny: (nw content buttonNamed: 'create') isVisible.
	process := nw content session process.
	self assert: process isSuspended.
	self click: (self ref: nw at: '.abandon').
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	self assert: process isTerminated.
	self assert: (self windowOf: Debugger) isNil
!
testNotifierDebugOpensDebuggerAndCloseAbandons
	| ws nw dw d process |
	ws := self openWorkspace: 'nil foo'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	process := nw content session process.
	self click: (self ref: nw at: '.debug').
	dw := self waitForWindowOf: Debugger.
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	d := dw content.
	self assert: d session == nw content session.
	self assert: d stackList selection printString equals: 'UndefinedObject>>DoIt'.
	self assert: (d stackList items first printString beginsWith: 'UndefinedObject(ProtoObject)>>doesNotUnderstand:') description: d stackList items printString.
	self assert: (self pcTextOf: d) equals: 'nil foo'.
	self assert: (d buttonNamed: 'create') isVisible.
	self click: (self ref: dw at: '.close').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [process isTerminated] description: 'the Process to be abandoned'
!
testFullStackIntoRestartRunToHere
	| dw d frames full |
	dw := self openDebuggerOnGcd last.
	d := dw content.
	frames := d stackList items size.
	self assert: d stackList items last == #more.
	self click: (self ref: dw at: '.full-stack').
	self waitUntilReady: dw.
	full := d session fullStack size.
	self assert: d stackList items size equals: full.
	self assert: (d buttonNamed: 'full-stack') isOn.
	self click: (self ref: dw at: '.full-stack').
	self waitUntilReady: dw.
	self assert: d stackList items size equals: frames.
	self click: (self ref: dw at: '.into').
	self waitUntilReady: dw.
	self assert: (d session interruptedContext selector) equals: #abs.
	self assert: d stackList selection == d session interruptedContext.
	self assert: (d stackList items second printString) equals: 'SmallInteger(Integer)>>gcd:'.
	self click: (self ref: dw at: '.stack.smallinteger-integer-gcd').
	self waitUntilReady: dw.
	self click: (self ref: dw at: '.restart').
	self waitUntilReady: dw.
	self assert: d session interruptedContext printString equals: 'SmallInteger(Integer)>>gcd:'.
	self assert: (self pcTextOf: d) equals: 'a := self abs'.
	self assert: d note equals: 'restarted'.
	self select: 'b = 0' in: (self ref: dw at: '.source').
	self click: (self ref: dw at: '.run-to-here').
	self waitUntilReady: dw.
	self assert: (self pcTextOf: d) equals: 'b = 0'.
	self assert: ((d contextInspector fields items detect: [:f | f name = 'b']) value) equals: 18
!
testBreakpointsWindow
	| bp point wp bw b list |
	bp := self breakpointOn: Integer selector: #lcm:.
	point := 10 @ 20.
	wp := Watchpoint on: point instVarNamed: 'y'.
	cleanups add: [wp unwatch].
	BreakpointsBrowser open.
	bw := self waitForWindowOf: BreakpointsBrowser.
	b := bw content.
	list := b list.
	self assert: (list items includes: bp).
	self assert: (list items includes: wp).
	self assert: ((list items collect: [:each | b titleOf: each]) includes: 'Integer>>lcm:').
	self click: (self ref: bw at: '.breakpoints.integer-lcm').
	self waitUntilReady: bw.
	self assert: list selection == bp.
	self click: (self ref: bw at: '.toggle').
	self waitUntilReady: bw.
	self deny: bp isEnabled.
	self assert: ((b descriptionOf: bp) includesSubstring: 'disabled').
	3 lcm: 4.
	self assert: bp hits equals: 0.
	self click: (self ref: bw at: '.remove').
	self waitUntilReady: bw.
	self deny: bp isInstalled.
	self deny: (list items includes: bp).
	self assert: (list items includes: wp).
	BreakpointsBrowser open.
	self assert: (world windows select: [:each | each content isKindOf: BreakpointsBrowser]) size equals: 1
!
testWindowErrorOpensNotifierOnWindowProcess
	| view w nw old |
	view := DebuggerTestFaultyView new.
	w := Window new title: 'Faulty'; content: view; bounds: (100 @ 100 extent: 300 @ 200); yourself.
	w openIn: world.
	world waitUntilSettled: 3000.
	old := w process.
	self click: (self ref: w at: '.faulty').
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'ZeroDivide'.
	self assert: nw content session process == old.
	self assert: old isSuspended.
	self click: (self ref: nw at: '.abandon').
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	self assert: old isTerminated.
	self assert: w isOpen.
	self deny: w process == old.
	self deny: w process isTerminated
! !
