ToolPane subclass: #ProcessBrowser
	instanceVariableNames: 'table stack source debugButton suspendButton terminateButton countLabel lastCpu lastTime cpu stackKey'
	classVariableNames: ''
	package: 'Tools'!

ProcessBrowser comment: 'I am the Process Browser (prototypes/1-classic/tools.js openProcessBrowser): a live table of every Process (priority, name — with a window glyph for a window''s Process —, state, and CPU share from Process>>cpuMicroseconds deltas), refreshed four times a second; below, the selected Process''s stack (its real suspendedContext chain) and the source of the selected frame with its current expression marked.

Debug opens a debugger on the Process (Tools debugProcess:), Suspend / Resume and Terminate act on it; the window system''s own Processes (above user priority) are refused. Double-click a row to debug it. While I refresh I am the running Process; a runnable Process that used CPU since the last refresh is shown running (time-sliced), one that did not is ready.'!

!ProcessBrowser methodsFor: 'initialization'!
initialize
	super initialize.
	cpu := IdentityDictionary new.
	lastCpu := IdentityDictionary new.
	lastTime := Time microsecondClockValue.
	self build
!
build
	| toolbar bottom |
	debugButton := Button label: 'Debug' action: [self debugSelected].
	debugButton name: 'debug'; tooltip: 'interrupt or suspend it and open a debugger'.
	suspendButton := Button label: 'Suspend' action: [self toggleSuspend].
	suspendButton name: 'suspend'.
	terminateButton := Button label: 'Terminate' action: [self terminateSelected].
	terminateButton name: 'terminate'.
	countLabel := Label text: '' font: #smallItalic.
	countLabel color: #ink3; align: #right.
	toolbar := Row with: (Array
		with: (debugButton sizeToContent; yourself)
		with: (suspendButton sizeToContent; yourself)
		with: (terminateButton sizeToContent; yourself)
		with: (countLabel flex: 1; yourself)
		with: ((Label text: '■ live' font: #uiBold) align: #right; fixed: 40; yourself)).
	toolbar spacing: 6; padding: (6 @ 4 corner: 8 @ 4); fixed: 29.
	table := TableView new name: 'processes'; title: 'Processes'; yourself.
	table
		addColumn: (TableColumn title: '' width: 8 draw: [:canvas :rect :p :inverted | self drawStateSquareOn: canvas in: rect for: p inverted: inverted]);
		addColumn: ((TableColumn title: 'Pri' width: 24 text: [:p | p priority printString]) align: #right; remoteKey: 'pri'; yourself);
		addColumn: ((TableColumn title: 'Process' flex: 1 text: [:p | p name ifNil: ['a Process']])
			drawBlock: [:canvas :rect :p :inverted | self drawNameOn: canvas in: rect for: p inverted: inverted]; yourself);
		addColumn: ((TableColumn title: 'State' width: 74 text: [:p | self stateOf: p])
			styleBlock: [:p | self stateStyleOf: p]; remoteKey: ''; yourself);
		addColumn: ((TableColumn title: 'CPU' width: 84 draw: (TableView barCell: [:p | (self cpuOf: p) / 100.0] text: [:p | ((self cpuOf: p) printShowingDecimalPlaces: 1), '%']))
			textBlock: [:p | ((self cpuOf: p) printShowingDecimalPlaces: 1), '%']; remoteKey: 'cpu'; yourself).
	table
		labelBlock: [:p | p name ifNil: ['a Process']];
		remoteNameBlock: [:p | p name ifNil: ['process']];
		onSelect: [:p | self processSelected: p];
		onDoubleClick: [:p | self debugSelected];
		itemMenuBlock: [:p | self menuFor: p].
	stack := ListView new name: 'stack'; title: 'Stack'; yourself.
	stack labelBlock: [:ctx | self labelOf: ctx]; onSelect: [:ctx | self showFrame: ctx].
	source := ToolTextEditor new name: 'source'; title: 'source'; readOnly: true; methodMode: true; yourself.
	bottom := Row with: (Array
		with: ((self pane: stack title: 'Stack') percent: 44)
		with: source).
	bottom separators: true; percent: 34.
	self addAll: (Array with: toolbar with: table with: Splitter new with: bottom)
!
minimumWindowExtent
	^400 @ 240
! !

!ProcessBrowser methodsFor: 'accessing'!
table
	^table
!
selectedProcess
	^table selection
!
stackList
	^stack
!
selectProcess: aProcess
	(table items includes: aProcess) ifFalse: [self refresh].
	table select: aProcess
! !

!ProcessBrowser methodsFor: 'sampling'!
refresh
	"Re-read every Process (my window's Process, 4 Hz)."
	| now dt procs |
	now := Time microsecondClockValue.
	dt := now - lastTime max: 1.
	procs := Processor allProcesses.
	cpu := IdentityDictionary new.
	procs do: [:p |
		| t |
		t := p cpuMicroseconds.
		cpu at: p put: ((t - (lastCpu at: p ifAbsent: [t])) * 100.0 / dt min: 100.0).
		lastCpu at: p put: t].
	(lastCpu keys reject: [:p | procs includes: p]) do: [:p | lastCpu removeKey: p].
	lastTime := now.
	table items: (procs asSortedCollection: [:a :b | self process: a sortsBefore: b]) asArray.
	table selection isNil ifTrue: [self selectFirstWindowProcess].
	self updateButtons.
	self updateStack
!
cpuOf: aProcess
	^cpu at: aProcess ifAbsent: [0.0]
!
process: a sortsBefore: b
	"Priority, highest first; at the same priority Processes without a window (do-its, forks) by name, then windows in the order they were opened. Short-lived Processes (a window's after:do: timers, remote-control requests) come last, so the rows above them do not jump while they come and go."
	| wa wb ta tb |
	ta := self isTransient: a.
	tb := self isTransient: b.
	ta = tb ifFalse: [^tb].
	a priority = b priority ifFalse: [^a priority > b priority].
	"At the same priority, a window's do-its and forks before the windows (they are what is running)."
	(a window isNil) = (b window isNil) ifFalse: [^a window isNil].
	wa := self windowNumberOf: a.
	wb := self windowNumberOf: b.
	wa = wb ifFalse: [^wa < wb].
	^(a name ifNil: ['']) <= (b name ifNil: [''])
!
isTransient: aProcess
	| n |
	n := aProcess name ifNil: [''].
	^(n beginsWith: 'timer for ') or: [(n beginsWith: 'remote request') or: [n = 'remote eval']]
!
windowNumberOf: aProcess
	| w name |
	w := aProcess window.
	(w isNil or: [(w respondsTo: #remoteName) not]) ifTrue: [^SmallInteger maxVal].
	name := w remoteName ifNil: [^SmallInteger maxVal - 1].
	^Integer readFrom: (name copyFrom: 2 to: name size) ifFail: [SmallInteger maxVal - 1]
!
selectFirstWindowProcess
	"Select the first window's Process; the list starts at the top (the few system Processes, then the windows)."
	| first |
	first := table items detect: [:p | p window notNil] ifNone: [table items isEmpty ifTrue: [^self] ifFalse: [table items first]].
	table selection: first.
	table scrollOffset: 0
!
stateOf: aProcess
	aProcess == Processor idleProcess ifTrue: [^'idle'].
	aProcess isActiveProcess ifTrue: [^'running'].
	aProcess isTerminated ifTrue: [^'terminated'].
	aProcess isSuspended ifTrue: [^'suspended'].
	aProcess isWaiting ifTrue: [^'waiting'].
	((self cpuOf: aProcess) > 0.5 or: [self isBusyWindowProcess: aProcess]) ifTrue: [^'running'].
	^'ready'
!
isBusyWindowProcess: aProcess
	^aProcess window notNil and: [(aProcess window respondsTo: #isBusy) and: [aProcess window isBusy]]
!
isBusy: aProcess
	"Running or ready and using the CPU (not my own refreshing)."
	aProcess isActiveProcess ifTrue: [^false].
	^(self stateOf: aProcess) = 'running'
!
stateStyleOf: aProcess
	| s |
	s := self stateOf: aProcess.
	s = 'running' ifTrue: [^(self isBusy: aProcess) ifTrue: [#(#bold #accent)] ifFalse: [#bold]].
	s = 'suspended' ifTrue: [^#bold].
	^#(#italic #muted)
! !

!ProcessBrowser methodsFor: 'drawing'!
drawStateSquareOn: aCanvas in: aRect for: aProcess inverted: inverted
	| theme r s fg bg |
	theme := self theme.
	s := self stateOf: aProcess.
	r := aRect left @ (aRect top + (aRect height - 6 / 2)) extent: 6 @ 6.
	fg := inverted ifTrue: [theme paper] ifFalse: [theme ink].
	bg := inverted ifTrue: [theme ink] ifFalse: [theme paper].
	s = 'running' ifTrue: [
		^aCanvas fillRect: r color: ((self isBusy: aProcess) & inverted not ifTrue: [theme ultramarine] ifFalse: [fg])].
	s = 'suspended' ifTrue: [
		aCanvas strokeRect: (r outsetBy: 2) color: fg width: 1.
		^aCanvas fillRect: r color: fg].
	aCanvas fillRect: r color: bg.
	aCanvas strokeRect: r color: (s = 'ready' & inverted not ifTrue: [theme ultramarine] ifFalse: [fg]) width: 1
!
drawNameOn: aCanvas in: aRect for: aProcess inverted: inverted
	| theme fg x name font extra |
	"The rows show the Processes' live state (CPU, state, progress) whenever drawn."
	aCanvas noteVolatile.
	theme := self theme.
	fg := inverted ifTrue: [theme paper] ifFalse: [theme ink].
	x := aRect left.
	aProcess window notNil ifTrue: [
		| g |
		g := x @ (aRect top + (aRect height - 9 / 2)) rounded extent: 11 @ 9.
		aCanvas strokeRect: g color: fg width: 1.
		aCanvas fillRect: (g left @ (g top + 2) extent: g width @ 1) color: fg.
		x := x + 17].
	name := aProcess name ifNil: ['a Process'].
	font := theme font: #ui.
	aCanvas clip: aRect during: [
		aCanvas drawString: name in: (x @ aRect top corner: aRect corner) font: font color: fg align: #left.
		extra := self noteFor: aProcess.
		extra isNil ifFalse: [
			aCanvas drawString: extra in: ((x + (font widthOf: name) + 6) @ aRect top corner: aRect corner)
				font: (theme font: #smallItalic) color: (inverted ifTrue: [theme color: #inverseMuted] ifFalse: [theme muted]) align: #left]]
!
noteFor: aProcess
	"A short note after the name: a busy window's progress (or what it is doing), a do-it's or fork's progress (181/400, in the Debugger)."
	| w |
	aProcess isActiveProcess ifTrue: [^'this browser'].
	w := aProcess window.
	(w notNil and: [(w respondsTo: #isBusy) and: [w isBusy]]) ifTrue: [
		^(w content respondsTo: #progressText)
			ifTrue: [w content progressText ifNil: [w busyLabel ifNil: ['busy']]]
			ifFalse: [w busyLabel ifNil: ['busy']]].
	^CodeEvaluator progressOf: aProcess
! !

!ProcessBrowser methodsFor: 'stack'!
labelOf: aContext
	"Class(MethodClass)>>selector; the top frame of a Process that was just woken has no pc yet (it is not dead)."
	| s |
	s := aContext printString.
	(s endsWith: ' (dead)') ifTrue: [s := s allButLast: 7].
	^s
!
framesOf: aProcess
	| ctx |
	aProcess isNil ifTrue: [^#()].
	aProcess isTerminated ifTrue: [^#()].
	ctx := aProcess isActiveProcess ifTrue: [thisContext] ifFalse: [aProcess suspendedContext].
	ctx isNil ifTrue: [^#()].
	^ctx stackOfSize: 40
!
processSelected: aProcess
	stackKey := nil.
	self updateButtons.
	self updateStack
!
updateStack
	"Show the selected Process's frames; keep the selected frame while the chain is the same."
	| frames key index |
	frames := self framesOf: table selection.
	key := frames collect: [:ctx | ctx method].
	key = stackKey
		ifTrue: [
			index := stack selectionIndex.
			stack items: frames.
			stack selectionIndex: index.
			index > 0 ifTrue: [self showFrame: (frames at: index)]]
		ifFalse: [
			stackKey := key.
			stack items: frames.
			frames isEmpty
				ifTrue: [stack selectionIndex: 0. source text: '']
				ifFalse: [stack selectionIndex: 1. self showFrame: frames first]]
!
showFrame: aContext
	| text interval isTop |
	aContext isNil ifTrue: [^self].
	text := aContext sourceCode ifNil: ['"no source"'].
	text = source text ifFalse: [source text: text].
	isTop := stack items notEmpty and: [stack items first == aContext].
	interval := [aContext sourceIntervalAsTop: isTop] on: Error do: [:e | e return: nil].
	interval isNil
		ifTrue: [source pcMark: nil]
		ifFalse: [
			(source pcMark notNil and: [source pcMark interval = interval]) ifFalse: [source pcMark: interval]]
! !

!ProcessBrowser methodsFor: 'actions'!
updateButtons
	| p system |
	p := table selection.
	system := p isNil or: [Tools isSystemProcess: p].
	suspendButton label: ((p notNil and: [p isSuspended]) ifTrue: ['Resume'] ifFalse: ['Suspend']).
	suspendButton name: ((p notNil and: [p isSuspended]) ifTrue: ['resume'] ifFalse: ['suspend']).
	debugButton enabled: system not.
	suspendButton enabled: system not.
	terminateButton enabled: system not.
	countLabel text: table items size printString, ' processes · ', (table items count: [:each | self isBusy: each]) printString, ' busy'
!
debugSelected
	| p |
	p := table selection.
	p isNil ifTrue: [^self].
	p isActiveProcess ifTrue: [^Tools toast: 'The Process Browser cannot debug itself'].
	Tools debugProcess: p.
	self refresh
!
toggleSuspend
	| p |
	p := table selection.
	p isNil ifTrue: [^self].
	(Tools isSystemProcess: p) ifTrue: [^Tools toast: 'Suspending ''', p name, ''' would freeze the system. Refused.'].
	p isActiveProcess ifTrue: [^Tools toast: 'The Process Browser cannot suspend itself'].
	p isSuspended
		ifTrue: [p resume]
		ifFalse: [
			p isWaiting ifTrue: [^Tools toast: '''', p name, ''' is waiting; Debug interrupts it'].
			p suspend].
	self refresh
!
terminateSelected
	| p w |
	p := table selection.
	p isNil ifTrue: [^self].
	(Tools isSystemProcess: p) ifTrue: [^Tools toast: '''', (p name ifNil: ['a Process']), ''' is part of the runtime and cannot be terminated.'].
	p isActiveProcess ifTrue: [^Tools toast: 'The Process Browser cannot terminate itself'].
	w := p window.
	(w notNil and: [w respondsTo: #close])
		ifTrue: [w close]
		ifFalse: [p terminate].
	table selection: nil.
	self refresh
!
menuFor: aProcess
	| m |
	aProcess isNil ifTrue: [^nil].
	m := Menu title: 'Process ''', (aProcess name ifNil: ['a Process']), ''''.
	m add: 'debug' action: [self debugSelected].
	m add: (aProcess isSuspended ifTrue: ['resume'] ifFalse: ['suspend']) action: [self toggleSuspend].
	m add: 'terminate' action: [self terminateSelected].
	m addSeparator.
	(m add: 'bring window to front' action: [aProcess window focus]) enabled: aProcess window notNil.
	m add: 'inspect process' action: [Tools inspect: aProcess near: self window].
	^m
!
startRefreshing
	self refresh.
	self every: 250 do: [self refresh]
! !

!ProcessBrowser class methodsFor: 'opening'!
openIn: aRectangle
	| browser window |
	browser := self new.
	window := browser openIn: aRectangle title: 'Process Browser'.
	window do: [browser startRefreshing].
	^window
!
open
	| existing |
	existing := Tools windowOf: self.
	existing isNil ifFalse: [existing focus. ^existing].
	^self openIn: (Tools placeAt: nil extent: 530 @ 340)
!
openSelecting: aProcess
	| window |
	window := self open.
	window do: [window content selectProcess: aProcess].
	^window
!
initialize
	ToolsMenu register: 'Process Browser' order: 40 action: [:point |
		| existing |
		existing := Tools windowOf: self.
		existing isNil
			ifTrue: [self openIn: (Tools placeAt: point extent: 530 @ 340)]
			ifFalse: [existing focus]]
! !
