ToolPane subclass: #ProcessBrowser
	instanceVariableNames: 'table stack source debugButton suspendButton terminateButton countLabel lastSample cpu shownCpu shownMeters states rawStates rowKeys rows stackKey meters refresher frozen'
	classVariableNames: ''
	package: 'Tools'!

ProcessBrowser comment: 'I am the Process Browser (prototypes/1-classic/tools.js openProcessBrowser): a live table of every Process (priority, name — with a window glyph for a window''s Process —, state, and CPU share from Process>>cpuMicroseconds deltas, read once a second), refreshed four times a second; above it a LoadMeters row with the load of each core the VM uses and of the GPU: cpu, the VM''s own core (every Process but the idle one, with the GC and the JIT: a Process''s CPU is its share of this core), jit, the core the background compiler runs on (VMStatistics>>optBackgroundMicroseconds: its jobs'' time, counted as each ends), and gpu, the frames'' GPU time (GPUTimer>>totalMicroseconds); the toolbar sums the cores'' load (0.25 cores: a quarter of one core''s time). The application processors'' raster bands (CpuWorkers) are not measured by the VM: they show only as GPU time. below, the selected Process''s stack (its real suspendedContext chain) and the source of the selected frame with its current expression marked.

An idle browser presents (almost) nothing: the readings (a Process''s CPU, the meters) are taken once a second and change on the screen only when they moved by a visible step (shown:for:in:), a flip between ready and waiting shows once it held at two refreshes, and the table, the meters and the stack are drawn again only when what they show changed.

Debug opens a debugger on the Process (Tools debugProcess:), Suspend / Resume and Terminate act on it; the window system''s own Processes (above user priority) are refused. Double-click a row to debug it. While I refresh I am the running Process; a runnable Process that used CPU since the last refresh is shown running (time-sliced), one that did not is ready.'!

!ProcessBrowser methodsFor: 'initialization'!
initialize
	super initialize.
	cpu := IdentityDictionary new.
	shownCpu := IdentityDictionary new.
	shownMeters := Dictionary new.
	states := IdentityDictionary new.
	rawStates := IdentityDictionary new.
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
	meters := LoadMeters new.
	meters name: 'load'; padding: (8 @ 0 corner: 0 @ 0); fixed: 20;
		tooltip: 'cpu: the VM''s core (every Process, the GC, the JIT) · jit: the background compiler''s core · gpu: the frames'' GPU time. A Process''s CPU is its share of the VM''s core.'.
	table := TableView new name: 'processes'; title: 'Processes'; yourself.
	table
		addColumn: (TableColumn title: '' width: 8 draw: [:canvas :rect :p :inverted | self drawStateSquareOn: canvas in: rect for: p inverted: inverted]);
		addColumn: ((TableColumn title: 'Pri' width: 24 text: [:p | ((self rowOf: p) at: 1) printString]) align: #right; remoteKey: 'pri'; yourself);
		addColumn: ((TableColumn title: 'Process' flex: 1 text: [:p | p name ifNil: ['a Process']])
			drawBlock: [:canvas :rect :p :inverted | self drawNameOn: canvas in: rect for: p inverted: inverted]; yourself);
		addColumn: ((TableColumn title: 'State' width: 74 text: [:p | (self rowOf: p) at: 4])
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
	self addAll: (Array with: toolbar with: meters with: table with: Splitter new with: bottom)
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
	"Re-read every Process (my window's Process, 4 Hz), and once a second their CPU (readingsOf:at:). The table is drawn again only when a row shows something else, and laid out again only when the Processes or their order changed."
	| now procs |
	frozen == true ifTrue: [^self].
	now := Time microsecondClockValue.
	procs := Processor allProcesses.
	(lastSample isNil or: [now - lastSample first >= 1000000]) ifTrue: [self readingsOf: procs at: now].
	self show: procs
!
show: procs
	"The rows of procs, their states as updateStatesOf: has them, the buttons and the stack."
	| sorted keys |
	self updateStatesOf: procs.
	sorted := (procs asSortedCollection: [:a :b | self process: a sortsBefore: b]) asArray.
	keys := sorted collect: [:p | self rowKeyOf: p].
	(table items notNil and: [table items = sorted])
		ifTrue: [keys = rowKeys ifFalse: [table invalidate]]
		ifFalse: [table items: sorted].
	rowKeys := keys.
	rows := IdentityDictionary new.
	sorted with: keys do: [:p :k | rows at: p put: k].
	table selection isNil ifTrue: [self selectFirstWindowProcess].
	self updateButtons.
	self updateStack
!
readingsOf: procs at: now
	"The CPU of each Process and the load of the cores and the GPU since the last reading (about a second), shown in visible steps."
	| times stats sample dt raw |
	times := IdentityDictionary new.
	procs do: [:p | times at: p put: p cpuMicroseconds].
	stats := Smalltalk vm statistics.
	sample := Array with: now with: times with: stats optBackgroundMicroseconds with: self gpuMicroseconds with: stats jitCompileMicroseconds.
	dt := lastSample isNil ifTrue: [1] ifFalse: [now - lastSample first max: 1].
	raw := IdentityDictionary new.
	procs do: [:p |
		| before |
		before := lastSample isNil ifTrue: [times at: p] ifFalse: [(lastSample at: 2) at: p ifAbsent: [times at: p]].
		raw at: p put: ((times at: p) - before * 100.0 / dt min: 100.0)].
	(shownCpu keys reject: [:p | times includesKey: p]) do: [:p | shownCpu removeKey: p].
	cpu := IdentityDictionary new.
	procs do: [:p | cpu at: p put: (self shown: (raw at: p) for: p in: shownCpu)].
	meters isNil ifFalse: [self updateMeters: raw sample: sample dt: dt jobs: stats optBackgroundJobs].
	lastSample := sample
!
shown: new for: key in: aDictionary
	"The reading to show for key (a percent, or nil: not measured): the new one when it moved from the one shown by a visible step (a point, or a fifth of the reading for large ones) or came to zero; else the one shown, so readings that only jitter stay still."
	| old |
	old := aDictionary at: key ifAbsent: [^aDictionary at: key put: new].
	(new isNil or: [old isNil]) ifTrue: [^aDictionary at: key put: new].
	((new - old) abs >= (old abs / 5 max: 1.0) or: [new = 0 and: [old ~= 0]]) ifTrue: [^aDictionary at: key put: new].
	^old
!
updateStatesOf: procs
	"The state each row shows: a flip between ready and waiting (a Process caught as its timer fired) once it held at two refreshes, the others at once."
	| raw |
	raw := IdentityDictionary new.
	procs do: [:p |
		| s old |
		s := self stateOf: p.
		raw at: p put: s.
		old := states at: p ifAbsent: [nil].
		states at: p put: ((old notNil and: [(self isQuiet: s) and: [(self isQuiet: old) and: [(rawStates at: p ifAbsent: [nil]) ~= s]]])
			ifTrue: [old]
			ifFalse: [s])].
	rawStates := raw.
	(states keys reject: [:p | raw includesKey: p]) do: [:p | states removeKey: p]
!
isQuiet: aState
	^aState = 'ready' or: [aState = 'waiting']
!
shownStateOf: aProcess
	^states at: aProcess ifAbsent: [self stateOf: aProcess]
!
rowKeyOf: aProcess
	"What a row shows of aProcess, read at a refresh: priority, name, whether it has a window, state, busy, note, CPU. The rows are drawn from it (rowOf:), so a redraw between refreshes draws what a replay would, and refresh draws the table again when it changes."
	^(Array new: 7)
		at: 1 put: aProcess priority;
		at: 2 put: (aProcess name ifNil: ['a Process']);
		at: 3 put: aProcess window notNil;
		at: 4 put: (self shownStateOf: aProcess);
		at: 5 put: (self isBusy: aProcess);
		at: 6 put: (self noteFor: aProcess);
		at: 7 put: ((self cpuOf: aProcess) printShowingDecimalPlaces: 1);
		yourself
!
rowOf: aProcess
	^(rows isNil ifFalse: [rows at: aProcess ifAbsent: [nil]]) ifNil: [self rowKeyOf: aProcess]
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
	| row s |
	row := self rowOf: aProcess.
	s := row at: 4.
	s = 'running' ifTrue: [^(row at: 5) ifTrue: [#(#bold #accent)] ifFalse: [#bold]].
	s = 'suspended' ifTrue: [^#bold].
	^#(#italic #muted)
!
updateMeters: raw sample: sample dt: dt jobs: jobs
	"The load of each core the VM uses and of the GPU since the last reading (lastSample; sample is this one's), from the Processes' raw CPU: the VM's core is every Process but the idle one (with the GC and the JIT); the background compiler runs on a core of its own. Shown in visible steps, as the CPU column."
	| list |
	list := self
		loadsOver: dt
		processes: raw
		compile: (lastSample isNil ifTrue: [0] ifFalse: [(sample at: 5) - (lastSample at: 5)])
		background: (jobs > 0 ifTrue: [lastSample isNil ifTrue: [0] ifFalse: [(sample at: 3) - (lastSample at: 3)]])
		gpu: ((lastSample isNil or: [(lastSample at: 4) isNil or: [(sample at: 4) isNil]]) ifFalse: [(sample at: 4) - (lastSample at: 4)]).
	meters meters: (list collect: [:each | each key -> (self shown: each value for: each key in: shownMeters)])
!
loadsOver: dt processes: percents compile: compileUs background: backgroundUsOrNil gpu: gpuUsOrNil
	"The meters' label -> percent over dt µs, each at most 100. cpu, the VM's core: the Processes' shares (percents: Process -> percent of dt; their CPU time is the VM thread's, the GC's included), but the idle one's, and the JIT's compiling on that thread, which is charged to no Process (compileUs). jit, the background compiler's core, if it ran at all (backgroundUsOrNil: the time its jobs took, counted when each ends; nil: none ran). gpu: the frames' GPU time (gpuUsOrNil; nil: not measured, a dash)."
	| list busy |
	busy := percents keys inject: 0.0 into: [:sum :p | p == Processor idleProcess ifTrue: [sum] ifFalse: [sum + (percents at: p)]].
	list := OrderedCollection new.
	list add: 'cpu' -> (busy + (compileUs * 100.0 / dt) min: 100.0).
	backgroundUsOrNil isNil ifFalse: [list add: 'jit' -> (backgroundUsOrNil * 100.0 / dt min: 100.0)].
	list add: 'gpu' -> (gpuUsOrNil isNil ifFalse: [gpuUsOrNil * 100.0 / dt min: 100.0]).
	^list asArray
!
gpuMicroseconds
	"The GPU time of the frames presented so far (GPUTimer), nil without a compositor that measures it."
	| compositor timer |
	compositor := [Tools world compositor] on: Error do: [:e | e return: nil].
	compositor isNil ifTrue: [^nil].
	timer := compositor gpuTimer.
	(timer isNil or: [(timer respondsTo: #totalMicroseconds) not]) ifTrue: [^nil].
	^timer totalMicroseconds
!
coresBusy
	"How many cores' worth of time the VM used (its own core and the background compiler's)."
	meters isNil ifTrue: [^0.0].
	^(meters meters inject: 0.0 into: [:sum :each | (each key ~= 'gpu' and: [each value notNil]) ifTrue: [sum + each value] ifFalse: [sum]]) / 100.0
! !

!ProcessBrowser methodsFor: 'drawing'!
drawStateSquareOn: aCanvas in: aRect for: aProcess inverted: inverted
	| theme r s fg bg |
	theme := self theme.
	s := (self rowOf: aProcess) at: 4.
	r := aRect left @ (aRect top + (aRect height - 6 / 2)) extent: 6 @ 6.
	fg := inverted ifTrue: [theme paper] ifFalse: [theme ink].
	bg := inverted ifTrue: [theme ink] ifFalse: [theme paper].
	s = 'running' ifTrue: [
		^aCanvas fillRect: r color: (((self rowOf: aProcess) at: 5) & inverted not ifTrue: [theme ultramarine] ifFalse: [fg])].
	s = 'suspended' ifTrue: [
		aCanvas strokeRect: (r outsetBy: 2) color: fg width: 1.
		^aCanvas fillRect: r color: fg].
	aCanvas fillRect: r color: bg.
	aCanvas strokeRect: r color: (s = 'ready' & inverted not ifTrue: [theme ultramarine] ifFalse: [fg]) width: 1
!
drawNameOn: aCanvas in: aRect for: aProcess inverted: inverted
	| theme fg x name font extra row |
	row := self rowOf: aProcess.
	theme := self theme.
	fg := inverted ifTrue: [theme paper] ifFalse: [theme ink].
	x := aRect left.
	(row at: 3) ifTrue: [
		| g |
		g := x @ (aRect top + (aRect height - 9 / 2)) rounded extent: 11 @ 9.
		aCanvas strokeRect: g color: fg width: 1.
		aCanvas fillRect: (g left @ (g top + 2) extent: g width @ 1) color: fg.
		x := x + 17].
	name := row at: 2.
	font := theme font: #ui.
	aCanvas clip: aRect during: [
		aCanvas drawString: name in: (x @ aRect top corner: aRect corner) font: font color: fg align: #left.
		extra := row at: 6.
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
	"Show the selected Process's frames; keep the selected frame while the chain is the same, and draw the list again only when its frames changed."
	| frames key index |
	frames := self framesOf: table selection.
	(self frames: frames are: stack items) ifTrue: [
		index := stack selectionIndex.
		index > 0 ifTrue: [self showFrame: (frames at: index)].
		^self].
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
frames: anArray are: items
	"Whether the stack list shows exactly these contexts."
	(items isNil or: [items size ~= anArray size]) ifTrue: [^false].
	1 to: anArray size do: [:i | (anArray at: i) == (items at: i) ifFalse: [^false]].
	^true
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
	countLabel text: table items size printString, ' processes · ', (table items count: [:each | self isBusy: each]) printString, ' busy · ', (self coresBusy printShowingDecimalPlaces: 2), ' cores'
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
	refresher := self every: 250 do: [self refresh]
!
freezeReadings
	"Stop refreshing and show fixed readings where I show the machine's load: no CPU for any Process, the meters at 0, and the Processes as at a moment when none of them was ready to run, if there is one within 5 s (Tools freezeReadouts). In my window's Process, as a refresh."
	| w |
	refresher isNil ifFalse: [refresher cancel. refresher := nil].
	w := self window.
	w isNil ifTrue: [^self freezeNow].
	w sync: [self freezeNow]
!
freezeNow
	| tries |
	frozen := true.
	cpu := IdentityDictionary new.
	meters isNil ifFalse: [meters meters: {'cpu' -> 0.0. 'jit' -> 0.0. 'gpu' -> 0.0}].
	tries := 0.
	[states := IdentityDictionary new.
	 self show: Processor allProcesses.
	 (rows anySatisfy: [:row | (row at: 4) = 'ready']) and: [(tries := tries + 1) < 50]] whileTrue: [(Delay forMilliseconds: 100) wait]
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
