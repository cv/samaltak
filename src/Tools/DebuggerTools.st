Object subclass: #DebuggerTools
	instanceVariableNames: ''
	classVariableNames: 'ShieldBlock'
	package: 'Tools'!

DebuggerTools comment: 'I connect the debugging engine (DebugSession, System-Debugging) to the UI. install makes every unhandled error, halt, breakpoint, watchpoint, doesNotUnderstand: and user interrupt in any Process open a window: DebugSession openerBlock (called in a new Process once the faulting Process is suspended) and Window errorHandler (errors in a window''s own Process). Breakpoints and watchpoints only stop user Processes: the window system''s Processes (windows, compositor, input dispatcher, timers) are ignored (shieldUIProcesses), so a breakpoint on Integer>>gcd: stops a do-it, not the layout code that reduces Fractions. Breakpoints and watchpoints and debugProcess: sessions open the full Debugger, everything else a Notifier. Without a running World the opener behaves like the kernel default: it reports the error on stderr and terminates the Process.

I also describe a session for the windows (titleFor:, messageFor:, iconKindFor:) and register the Breakpoints window with the core tools (Tools registerOpener: #breakpoints, ToolsMenu ''Breakpoints…'').'!

!DebuggerTools class methodsFor: 'class initialization'!
initialize
	self install.
	self registerWithTools
! !

!DebuggerTools class methodsFor: 'installing'!
install
	DebugSession openerBlock: [:session | DebuggerTools open: session].
	Desktop windowErrorHandler: [:exception :window | DebuggerTools handleError: exception in: window].
	Breakpoint removeListener: self shieldBlock; addListener: self shieldBlock.
	Watchpoint removeListener: self shieldBlock; addListener: self shieldBlock.
	Breakpoint ignoreProcessesSatisfying: [:process | DebuggerTools isUIProcess: process]
!
uninstall
	DebugSession openerBlock: nil.
	Desktop windowErrorHandler: nil.
	Breakpoint removeListener: self shieldBlock.
	Watchpoint removeListener: self shieldBlock.
	Breakpoint processFilter: nil
!
shieldBlock
	^ShieldBlock ifNil: [ShieldBlock := [:changed | DebuggerTools shieldUIProcesses]]
!
shieldUIProcesses
	"Breakpoints and watchpoints stop user Processes (do-its, forked computations), never the window system''s: every window''s Process and every Process above user priority (compositor, input dispatcher, timers) is ignored. Done whenever a breakpoint or watchpoint changes; the process filter set by install also ignores Processes started later, before their first hit is counted."
	Processor allProcesses do: [:each |
		((self isUIProcess: each) and: [(Breakpoint isIgnoring: each) not]) ifTrue: [Breakpoint ignoreProcess: each]]
!
isUIProcess: aProcess
	^aProcess window notNil or: [aProcess priority > Processor userSchedulingPriority]
!
registerWithTools
	Tools registerOpener: #breakpoints with: [:arg | BreakpointsBrowser open].
	ToolsMenu register: 'Breakpoints…' description: 'breakpoints · watchpoints' group: #tools order: 70
		action: [:point | BreakpointsBrowser open]
! !

!DebuggerTools class methodsFor: 'opening'!
open: aSession
	"The DebugSession opener: show aSession (its Process is suspended). Breakpoints and watchpoints never stop the UI's own Processes (see shieldUIProcesses): such a Process is ignored from now on and resumed."
	self hasWorld ifFalse: [^self reportHeadless: aSession].
	((#(#breakpoint #watchpoint) includes: aSession kind) and: [(self isUIProcess: aSession process) and: [(self isTargeted: aSession) not]]) ifTrue: [
		Breakpoint ignoreProcess: aSession process.
		^aSession proceed].
	^Breakpoint ignoreDuring: [
		(self opensDebuggerDirectly: aSession)
			ifTrue: [Debugger openOn: aSession]
			ifFalse: [Notifier openOn: aSession]]
!
isTargeted: aSession
	"Whether the breakpoint or watchpoint that stopped aSession's process deliberately acts in the window system's processes (its scope)."
	| point |
	point := aSession breakpoint ifNil: [aSession watchpoint].
	^point notNil and: [point isTargeted]
!
opensDebuggerDirectly: aSession
	^#(#breakpoint #watchpoint #suspended) includes: aSession kind
!
hasWorld
	^Desktop isRunning
!
reportHeadless: aSession
	| text |
	text := String new: 400 streamContents: [:s |
		s nextPutAll: 'Error: '; nextPutAll: aSession label asString; nextPut: Character lf.
		s nextPutAll: 'Process: '; nextPutAll: aSession process name asString; nextPut: Character lf.
		(aSession stackOfSize: 40) do: [:each | s print: each; nextPut: Character lf]].
	Smalltalk vm stderrWrite: text.
	aSession abandon
!
handleError: anException in: aWindow
	"Window errorHandler: an error in aWindow's Process. A breakpoint or watchpoint hit is ignored (window Processes are never stopped by them, see shieldUIProcesses) unless it targets them (its scope): then aWindow's Process is debugged, also a debugger's. The debugging tools' own windows report errors and restart their event loop; any other window's Process is suspended and debugged."
	((anException isKindOf: BreakpointHalt) or: [anException isKindOf: WatchpointHit]) ifTrue: [
		(self isTargetedHit: anException) ifTrue: [^DebugSession handleUnhandledError: anException].
		Breakpoint ignoreProcess: Processor activeProcess.
		^nil].
	(self isDebuggerWindow: aWindow) ifTrue: [
		aWindow reportError: anException.
		^aWindow restartProcess].
	^DebugSession handleUnhandledError: anException
!
isTargetedHit: aHalt
	| point |
	point := (aHalt isKindOf: BreakpointHalt) ifTrue: [aHalt breakpoint] ifFalse: [aHalt watchpoint].
	^point notNil and: [point isTargeted]
!
isDebuggerWindow: aWindow
	| content |
	content := aWindow content.
	^(content isKindOf: Debugger) or: [(content isKindOf: Notifier) or: [content isKindOf: BreakpointsBrowser]]
!
restartWindowOf: aProcess
	"Give aProcess's window, if open, a fresh event loop."
	^self restartWindow: aProcess window
!
restartWindow: aWindowOrNil
	"After abandoning a window's Process (which then forgets its window: read it before): give the window a fresh event loop."
	(aWindowOrNil notNil and: [aWindowOrNil isOpen]) ifTrue: [aWindowOrNil restartProcess]
!
boundsFor: anExtent
	"Where a debugging window of anExtent opens: offset from the active window, else cascading."
	| world near origin desk |
	world := Desktop current.
	desk := world desktopBounds.
	near := world activeWindow.
	origin := near isNil
		ifTrue: [world nextWindowPosition: anExtent]
		ifFalse: [near bounds origin + (56 @ 34)].
	origin := ((origin x min: desk right - anExtent x - 8) max: desk left + 8)
		@ ((origin y min: desk bottom - anExtent y - 8) max: desk top + 4).
	^origin extent: anExtent
!
clamp: aRectangle
	"aRectangle moved (and shrunk if needed) onto the desktop."
	| desk extent origin |
	desk := Desktop current desktopBounds.
	extent := (aRectangle width min: desk width - 16) @ (aRectangle height min: desk height - 8).
	origin := ((aRectangle left min: desk right - extent x - 8) max: desk left + 8)
		@ ((aRectangle top min: desk bottom - extent y - 4) max: desk top + 4).
	^origin extent: extent
!
ignore: aWindow
	"The debugger's window Process never stops at breakpoints."
	aWindow process isNil ifFalse: [Breakpoint ignoreProcess: aWindow process]
! !

!DebuggerTools class methodsFor: 'describing'!
iconKindFor: aSession
	| k |
	k := aSession kind.
	k == #breakpoint ifTrue: [^#break].
	k == #watchpoint ifTrue: [^#watch].
	k == #halt ifTrue: [^#halt].
	k == #interrupt ifTrue: [^#interrupt].
	k == #suspended ifTrue: [^#interrupt].
	^#error
!
titleFor: aSession
	| k ex |
	k := aSession kind.
	ex := aSession exception.
	k == #breakpoint ifTrue: [^'Breakpoint: ', aSession breakpoint locationDescription].
	k == #watchpoint ifTrue: [^'ModificationForbidden → ', aSession watchpoint label].
	k == #dnu ifTrue: [^aSession label].
	k == #interrupt ifTrue: [^'User interrupt'].
	k == #suspended ifTrue: [^'Process ', aSession process name printString].
	k == #halt ifTrue: [^(ex isNil or: [ex class == Halt]) ifTrue: ['Halt'] ifFalse: [ex class name asString]].
	^ex isNil ifTrue: [aSession label] ifFalse: [ex class name asString]
!
messageFor: aSession
	| k ex ctx bp |
	k := aSession kind.
	ex := aSession exception.
	ctx := aSession interruptedContext.
	k == #breakpoint ifTrue: [
		bp := aSession breakpoint.
		^(self sendTextOf: ex context), ' — ', (self modeText: bp), ', hit ', bp hits printString, '×. Image-side: the method was recompiled with a break at entry.'].
	k == #watchpoint ifTrue: [
		^(self storeTextOf: ex in: ctx), ' — the object is read-only while watched; Proceed retries the store.'].
	k == #dnu ifTrue: [
		^(self short: ex receiver), ' doesNotUnderstand: #', ex message selector, ' — Create defines it; Proceed then resends the message.'].
	k == #interrupt ifTrue: [
		^'Process ', aSession process name printString, ' was interrupted', (ctx isNil ifTrue: [''] ifFalse: [' in ', ctx printString]), ' — Proceed continues it.'].
	k == #suspended ifTrue: [
		^'Suspended for debugging', (ctx isNil ifTrue: [''] ifFalse: [' in ', ctx printString]), ' — Proceed resumes it.'].
	k == #halt ifTrue: [
		^(self statementTextOf: ctx in: aSession), (ctx isNil ifTrue: [''] ifFalse: [' — in ', ctx printString])].
	^self errorTextOf: ex in: aSession
!
errorTextOf: anException in: aSession
	| text stmt |
	text := anException isNil ifTrue: [''] ifFalse: [[anException messageText asString] on: Error do: [:e | e return: '']].
	stmt := self statementTextOf: aSession interruptedContext in: aSession.
	(text isEmpty or: [text = anException class name asString]) ifTrue: [
		^stmt isEmpty ifTrue: ['error'] ifFalse: [stmt, ' — error']].
	^text
!
statementTextOf: aContext in: aSession
	| s |
	aContext isNil ifTrue: [^''].
	s := [aSession selectedSourceOf: aContext] on: Error do: [:e | e return: ''].
	^self oneLine: s max: 60
!
modeText: aBreakpoint
	| m |
	m := aBreakpoint mode.
	m == #once ifTrue: [^'break once (now removed)'].
	m == #condition ifTrue: [^'conditional: ', aBreakpoint expression].
	m == #log ifTrue: [^'logpoint'].
	^'breakpoint'
!
sendTextOf: aContext
	"48 gcd: 18"
	| sel args |
	aContext isNil ifTrue: [^''].
	sel := aContext selector.
	args := aContext arguments.
	^String new: 40 streamContents: [:s |
		s nextPutAll: (self short: aContext receiver).
		args isEmpty
			ifTrue: [s space; nextPutAll: sel]
			ifFalse: [
				(sel first isLetter)
					ifTrue: [
						sel keywords doWithIndex: [:k :i |
							s space; nextPutAll: k; space; nextPutAll: (self short: (args at: i))]]
					ifFalse: [s space; nextPutAll: sel; space; nextPutAll: (self short: args first)]]]
!
storeTextOf: aWatchpointHit in: aContext
	"3@4 x: 4"
	| mod obj field |
	mod := aWatchpointHit modification.
	obj := mod object.
	(aContext notNil and: [aContext receiver == obj and: [aContext selector numArgs = 1 and: [aContext selector first isLetter]]])
		ifTrue: [^(self short: obj), ' ', aContext selector, ' ', (self short: mod newValue)].
	field := aWatchpointHit watchpoint fieldName.
	^(self short: obj), ' ', (field isNil ifTrue: ['at: ', mod fieldIndex printString] ifFalse: [field]), ' := ', (self short: mod newValue)
!
short: anObject
	^self oneLine: ([anObject printStringLimitedTo: 80] on: Error do: [:e | e return: 'an object']) max: 30
!
oneLine: aString max: anInteger
	| s |
	s := aString asString copyReplaceAll: (String with: Character lf) with: ' '.
	s := s copyReplaceAll: (String with: Character tab) with: ' '.
	[s includesSubstring: '  '] whileTrue: [s := s copyReplaceAll: '  ' with: ' '].
	s size > anInteger ifTrue: [s := (s first: anInteger - 1), '…'].
	^s
!
processStateOf: aProcess
	aProcess isNil ifTrue: [^''].
	aProcess isTerminated ifTrue: [^'terminated'].
	aProcess isSuspended ifTrue: [^'suspended'].
	(aProcess isActiveProcess or: [aProcess isRunnable]) ifTrue: [^'running'].
	^'waiting'
! !
