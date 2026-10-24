Object subclass: #Tools
	instanceVariableNames: ''
	classVariableNames: 'CrunchCount Openers'
	package: 'Tools'!

Tools comment: 'I am the facade of the development tools (layer 5): I open them, cross-link them, arrange the default desktop and implement the World menu''s commands. Everything is on my class side.

	Tools browseClass: Integer selector: #gcd:.
	Tools inspect: 3 @ 4.
	Tools openWorkspaceWith: ''3 + 4''.
	Tools openProcessBrowser.
	Tools registerOpener: #profiler with: [:arg | ...].	"tools of other packages"
	Tools open: #breakpoints.

On a normal start (UIWindows startupAction:) I open the default layout of the prototype: Workspace, Transcript, Process Browser, Mandelbrot, an Inspector and the System Browser, each a Window with its own Process. There I also install the World menu (ToolsMenu) and the user interrupt (⌘.: interrupt the busiest user Process).'!

!Tools class methodsFor: 'class initialization'!
initialize
	Openers isNil ifTrue: [Openers := Dictionary new].
	CrunchCount := 0.
	Desktop startupAction: [Tools startUp]
! !

!Tools class methodsFor: 'startup'!
startUp
	"The startup action: the World menu, ⌘., and the default desktop."
	self installHooks.
	self installFallbackOpener.
	self openDefaultLayout
!
installHooks
	"The World menu on a desk click (ToolsMenu) and the user interrupt (⌘.: the busiest user Process). Installed when the desktop starts, so the window system's own tests keep its defaults."
	Desktop worldMenuBuilder: [:world :point | ToolsMenu worldMenuAt: point].
	Desktop helpHandler: [:world | Tools showHelp].
	Desktop userInterruptHandler: [:window :world |
		[Tools userInterrupt] forkAt: Processor userInterruptPriority named: 'user interrupt']
!
installFallbackOpener
	"Without the Debugger, unhandled errors open a simple notifier."
	DebugSession openerBlock isNil ifTrue: [
		DebugSession openerBlock: [:session | ToolsNotifier openOn: session]]
!
banner
	| packages classes |
	packages := Smalltalk packages size.
	classes := Smalltalk allClasses size.
	^'Samaltak 0.1 · Smalltalk-80', (String with: Character lf),
		self imageName, ' · ', packages printString, ' packages · ', classes printString, ' classes · 6 layers', (String with: Character lf),
		'green threads, preempted at safepoints', (String with: Character lf)
!
openDefaultLayout
	"The prototype's desktop (prototypes/1-classic/main.js boot), in the same order so the window refs match (@w1 Workspace … @w6 System Browser)."
	| ws |
	Transcript clear.
	Transcript show: self banner.
	ws := self try: [Workspace openOn: self workspaceText in: (self layoutRect: #workspace) focus: false].
	self try: [TranscriptView openIn: (self layoutRect: #transcript)].
	self try: [ProcessBrowser openIn: (self layoutRect: #procs)].
	self try: [MandelbrotView openIn: (self layoutRect: #mandel) delay: 400].
	self try: [Inspector openOn: (Compiler evaluate: self inspectorDemo) in: (self layoutRect: #inspector)
		bindings: (ws isNil ifTrue: [nil] ifFalse: [ws content bindings])].
	self try: [(SystemBrowser openIn: (self layoutRect: #browser) onClass: Desktop windowClass protocol: (Desktop windowClass categoryOfSelector: #open) selector: #open) focus].
	^ws
!
try: aBlock
	"Startup must open what it can: report a failing tool and go on."
	^aBlock on: Error do: [:e |
		Transcript show: 'Tools: ', e messageText asString; cr.
		e return: nil]
!
inspectorDemo
	^'{3/4. 3@4. ''text''. #sym. $c. 2 raisedTo: 100}'
!
workspaceText
	"The prototype's workspace text (main.js WORKSPACE_TEXT), verbatim."
	^'"Put the cursor on a line or select an expression, then
 ⌘D do it · ⌘P print it · ⌘I inspect it · right-click for the menu."

"Green thread: fork a busy Process. Drag windows and type while it runs. ⌘. interrupts."
[1 to: 300 do: [:i | 999 factorial. Transcript show: ''.'']] forkNamed: ''crunch''

100 factorial
(1 to: 20) select: [:i | i isPrime]
3/4 + (1/4)
(3/4) + (1/3)
3 @ 4 + 1
Transcript show: ''hello, Samaltak''; cr
#(3 1 4 1 5 9 2 6) asSortedCollection
''hello world'' asUppercase reversed
{3/4. 3@4. ''text''. #sym. $c. 2 raisedTo: 100}

"Errors open a notifier; syntax errors are marked inline."
1/0
3 zork  "⌘P, Debug, then Create defines #zork"
(3 + 4

"Debugger. Breakpoint: Browser, Integer, gcd:, click the gutter dot. Then ⌘P:"
48 gcd: 18
| sum | sum := 0. 1 to: 5 do: [:i | i = 3 ifTrue: [self halt]. sum := sum + (i * i)]. sum
#(3 1 4) inject: 0 into: [:acc :each | each = 1 ifTrue: [self halt]. acc + each]
"Watchpoint: ⌘I on p, right-click x, Halt on write; then fork the mover."
p := 3 @ 4
[5 timesRepeat: [p x: p x + 1. Transcript show: p printString; cr]] forkNamed: ''mover''
'
! !

!Tools class methodsFor: 'layout'!
world
	^Desktop current
!
isRunning
	^Desktop isRunning
!
layoutRect: aSymbol
	"The prototype's window frame for aSymbol (main.js layoutFor), scaled to the World."
	| r ext top sx sy |
	r := self defaultFrames at: aSymbol.
	ext := self world isNil ifTrue: [1440 @ 900] ifFalse: [self world extent].
	top := self world isNil ifTrue: [27] ifFalse: [self world topBar height].
	sx := ext x / 1440.
	sy := ext y - top / (900 - 30).
	^((r at: 1) * sx) rounded @ (top + ((r at: 2) - 30 * sy)) rounded
		extent: ((r at: 3) * sx) rounded @ ((r at: 4) * sy) rounded
!
defaultFrames
	| d |
	d := Dictionary new.
	d at: #browser put: #(18 44 866 468);
		at: #procs put: #(898 44 524 366);
		at: #transcript put: #(898 424 524 140);
		at: #workspace put: #(18 526 690 358);
		at: #inspector put: #(684 572 404 312);
		at: #mandel put: #(1098 578 324 306).
	^d
!
arrangeWindows
	"Put the first window of each default tool back into its default frame."
	| kinds |
	kinds := Array
		with: SystemBrowser -> #browser with: ProcessBrowser -> #procs with: TranscriptView -> #transcript
		with: Workspace -> #workspace with: Inspector -> #inspector with: MandelbrotView -> #mandel.
	kinds do: [:pair |
		(self windowsOf: pair key) isEmpty ifFalse: [
			| w |
			w := (self windowsOf: pair key) first.
			w isCollapsed ifTrue: [w expand].
			w bounds: (self layoutRect: pair value)]]
!
placeAt: aPointOrNil extent: anExtent
	"A frame of anExtent for a window opened by a click at aPointOrNil (the World menu), kept on the screen."
	| world origin |
	world := self world.
	world isNil ifTrue: [^100 @ 100 extent: anExtent].
	aPointOrNil isNil ifTrue: [^(world nextWindowPosition: anExtent) extent: anExtent].
	origin := aPointOrNil - (30 @ 10).
	^(self clamp: origin extent: anExtent)
!
placeNear: aWindowOrNil extent: anExtent
	"A frame of anExtent near aWindowOrNil (offset down and right), or a cascading one."
	| world |
	world := self world.
	(aWindowOrNil isNil or: [world isNil]) ifTrue: [^self placeAt: nil extent: anExtent].
	^self clamp: aWindowOrNil bounds origin + (60 @ 60) extent: anExtent
!
clamp: aPoint extent: anExtent
	| world x y |
	world := self world.
	world isNil ifTrue: [^aPoint extent: anExtent].
	x := (aPoint x min: world extent x - anExtent x - 8) max: 8.
	y := (aPoint y min: world extent y - anExtent y - 8) max: world topBar height + 8.
	^x @ y extent: anExtent
!
windowsOf: aToolClass
	"The open windows whose content is a aToolClass, front to back."
	self world isNil ifTrue: [^#()].
	^self world windows select: [:w | w content isKindOf: aToolClass]
!
windowOf: aToolClass
	| ws |
	ws := self windowsOf: aToolClass.
	^ws isEmpty ifTrue: [nil] ifFalse: [ws first]
! !

!Tools class methodsFor: 'opening'!
registerOpener: aSymbol with: aBlock
	"Let other tool packages open their tools by name (Tools open: #breakpoints)."
	Openers isNil ifTrue: [Openers := Dictionary new].
	Openers at: aSymbol put: aBlock
!
unregisterOpener: aSymbol
	Openers isNil ifFalse: [Openers removeKey: aSymbol ifAbsent: [nil]]
!
hasOpener: aSymbol
	^Openers notNil and: [Openers includesKey: aSymbol]
!
open: aSymbol
	^self open: aSymbol with: nil
!
open: aSymbol with: anObject
	| block |
	block := Openers isNil ifTrue: [nil] ifFalse: [Openers at: aSymbol ifAbsent: [nil]].
	block isNil ifTrue: [
		self toast: 'No ', aSymbol, ' tool in this image'.
		^nil].
	^block cull: anObject
!
browseClass: aClass
	^SystemBrowser openOnClass: aClass selector: nil
!
browseClass: aClass selector: aSymbol
	^SystemBrowser openOnClass: aClass selector: aSymbol
!
browseMethod: aCompiledMethod
	^SystemBrowser openOnClass: aCompiledMethod methodClass selector: aCompiledMethod selector
!
browse: anObject
	"Browse a class, a method, or the class of anObject."
	anObject isBehavior ifTrue: [^self browseClass: anObject].
	(anObject isKindOf: CompiledMethod) ifTrue: [^self browseMethod: anObject].
	^self browseClass: anObject class
!
sendersOf: aSymbol
	^MethodBrowser openSendersOf: aSymbol
!
implementorsOf: aSymbol
	^MethodBrowser openImplementorsOf: aSymbol
!
inspect: anObject
	^self inspect: anObject near: nil
!
inspect: anObject near: aWindowOrNil
	^Inspector openOn: anObject near: aWindowOrNil
!
openWorkspace
	^Workspace openOn: Workspace freshText in: (self placeAt: nil extent: 560 @ 300) focus: true
!
openWorkspaceWith: aString
	^Workspace openOn: aString in: (self placeAt: nil extent: 560 @ 300) focus: true
!
openTranscript
	^TranscriptView openIn: (self placeAt: nil extent: 520 @ 210)
!
openProcessBrowser
	^ProcessBrowser open
!
openProcessBrowserSelecting: aProcess
	^ProcessBrowser openSelecting: aProcess
!
openMandelbrot
	^MandelbrotView openIn: (self placeAt: nil extent: 330 @ 300) delay: 50
!
openTerminal
	^Terminal open
! !

!Tools class methodsFor: 'processes'!
isSystemProcess: aProcess
	"Processes the tools do not stop: the VM's and the window system's own (above user priority), and the idle process."
	aProcess isNil ifTrue: [^true].
	aProcess == Processor idleProcess ifTrue: [^true].
	^aProcess priority > Processor userSchedulingPriority or: [aProcess priority <= 1]
!
debugProcess: aProcess
	"Open a debugger on aProcess (the Process Browser's Debug): interrupt it if it waits, else suspend it."
	(self isSystemProcess: aProcess) ifTrue: [
		^self toast: 'Debugging ''', (aProcess name ifNil: ['a Process']), ''' would stop the world. Refused.'].
	aProcess isTerminated ifTrue: [^self toast: 'The process has terminated'].
	aProcess == Processor activeProcess ifTrue: [^self toast: 'A process cannot debug itself'].
	aProcess isWaiting ifTrue: [^aProcess interrupt].
	DebugSession openerBlock isNil ifTrue: [^self toast: 'No debugger installed'].
	^DebugSession open: (DebugSession debugProcess: aProcess)
!
cpuSample
	"An IdentityDictionary Process -> cpuMicroseconds of every live process."
	| d |
	d := IdentityDictionary new.
	Processor allProcesses do: [:p | d at: p put: p cpuMicroseconds].
	^d
!
userInterrupt
	"⌘. : interrupt the user Process that used the most CPU in the last 150 ms (the active window's, if it is busy)."
	| before after best bestDelta active |
	before := self cpuSample.
	(Delay forMilliseconds: 150) wait.
	after := self cpuSample.
	active := self world isNil ifTrue: [nil] ifFalse: [self world activeWindow].
	best := nil.
	bestDelta := 0.
	after keysAndValuesDo: [:p :t |
		| delta |
		((self isSystemProcess: p) or: [p == Processor activeProcess or: [p isSuspended or: [p isTerminated]]]) ifFalse: [
			delta := t - (before at: p ifAbsent: [0]).
			(active notNil and: [active process == p and: [delta > 1000]]) ifTrue: [delta := delta * 10].
			delta > bestDelta ifTrue: [best := p. bestDelta := delta]]].
	(best isNil or: [bestDelta < 2000]) ifTrue: [^self toast: 'User interrupt: no busy Process to interrupt'].
	self toast: 'User interrupt: ', best printString.
	best interrupt.
	^best
!
crunchSource: aName
	"The prototype's long computation (main.js runCrunch; 4000 factorial takes as long here as its 1000 factorial), as a background job (priority 30): user windows stay snappy."
	^'[1 to: 400 do: [:i | 4000 factorial. i \\ 40 = 0 ifTrue: [Transcript show: i printString; show: '' '']]] forkAt: Processor userBackgroundPriority named: ', aName printString
!
runLongComputation
	"Fork ''crunch'': real work in the background (priority 30), shown in the Process Browser and the Profiler."
	| name process source |
	CrunchCount := (CrunchCount ifNil: [0]) + 1.
	name := CrunchCount = 1 ifTrue: ['crunch'] ifFalse: ['crunch ', CrunchCount printString].
	source := self crunchSource: name.
	process := Compiler evaluate: source.
	"Shown as the Workspace's, like a fork evaluated there: its footer and title bar follow it."
	(self windowsOf: Workspace) ifNotEmpty: [:ws | ws first do: [ws first content evaluator adopt: process source: source]].
	self toast: 'Forked ', process printString, ' — drag windows, type, it keeps going'.
	(self windowsOf: ProcessBrowser) isEmpty ifTrue: [self openProcessBrowser].
	^process
! !

!Tools class methodsFor: 'image'!
imageName
	| path |
	path := Smalltalk vm imagePath ifNil: ['samaltak.image'].
	^path copyAfterLast: $/
!
saveImage
	"Snapshot the image in place (in a Process of its own). When the saved image is started later, its desktop resumes as it was (UIWindows startUp:) and this Process continues here; without a display it starts like a fresh image."
	| path t0 resumed ms size |
	path := Smalltalk vm imagePath.
	path isNil ifTrue: [^self toast: 'No image path'].
	t0 := Time millisecondClockValue.
	resumed := Smalltalk snapshot: path.
	resumed == true ifTrue: [
		Desktop isRunning ifFalse: [^Smalltalk processCommandLine].
		^self toast: self imageName, ' resumed'].
	ms := Time millisecondClockValue - t0.
	size := [File sizeOf: path] on: Error do: [:e | e return: nil].
	"Breakpoints (e.g. on Integer>>gcd:) must not stop the toast's arithmetic."
	Breakpoint ignoreDuring: [
		self toast: self imageName, ' saved', (size isNil ifTrue: [''] ifFalse: [' — ', (size / 1048576.0 printShowingDecimalPlaces: 1), ' MB']),
			', ', (ms / 1000.0 printShowingDecimalPlaces: 2), ' s']
!
quit
	Smalltalk quit: 0
! !

!Tools class methodsFor: 'ui services'!
toast: aString
	self world isNil ifFalse: [self world toast: aString]
!
showHelp
	^ToolsHelpView open
!
request: aPrompt initialAnswer: aString then: aBlock
	"Ask for a line of text in a small dialog; evaluate aBlock with the answer (not when cancelled)."
	^RequestDialog prompt: aPrompt initialAnswer: aString then: aBlock
! !
