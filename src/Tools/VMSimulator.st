ToolPane subclass: #VMSimulator
	instanceVariableNames: 'arguments output runButton st80Button debugButton rebuildButton status simulation process lock pending started timer screen screenPane outputPane'
	classVariableNames: ''
	package: 'Tools'!

VMSimulator comment: 'I run the VM itself as Smalltalk: the Lowtalk sources of VM-Core (the same code the C build is translated from) in a VMSimulation, on an image, with a command line. Output appears as the simulated VM writes it; Debug stops the simulated VM''s Process in a debugger, showing the interpreter''s own methods (Interpreter>>interpret, the bytecode handlers, the GC) as they run.

The default command line boots the VM tests'' mini kernel image (built from vm/tests/mini with ImageBuilder at each run) as a guest that prints a line a second with what the VM calls itself (VMMain>>banner): edit that method in the System Browser and the next line shows it. The status shows how many bytecodes the simulated interpreter ran, and how fast. Rebuild & reboot does the same to the image itself (VMRebuilder).

Smalltalk-80 boots the guest of st80/ instead (this image''s kernel and compiler, and a small UI, built at each run): once it opens the VM''s guest display, my screen pane (a GuestScreen) shows it and takes the pointer and the keys, and the status adds its frame time and input latency. Its animation''s title is VMMain>>banner too.'!

!VMSimulator methodsFor: 'initialization'!
initialize
	| toolbar |
	super initialize.
	lock := Semaphore forMutualExclusion.
	pending := WriteStream on: String new.
	arguments := ToolTextEditor new name: 'arguments'; title: 'command line'; highlighting: false; yourself.
	arguments text: self class defaultArguments.
	runButton := Button label: 'Run' action: [self run].
	runButton name: 'run'; tooltip: 'run the simulated VM with this command line'.
	debugButton := Button label: 'Debug' action: [self debug].
	debugButton name: 'debug'; tooltip: 'stop the simulated VM in a debugger'.
	st80Button := Button label: 'Smalltalk-80' action: [self runSmalltalk80].
	st80Button name: 'st80'; tooltip: 'boot the Smalltalk-80 guest: a Workspace, the Transcript and an animation on the guest display'.
	rebuildButton := Button label: 'Rebuild & reboot' action: [VMRebuilder openAndRebuild].
	rebuildButton name: 'rebuild'; tooltip: 'translate the VM to C, compile it and restart this image on it'.
	status := Label text: 'not running' font: #smallItalic.
	status color: #ink3; align: #right.
	toolbar := Row with: (Array
		with: (runButton sizeToContent; yourself)
		with: (st80Button sizeToContent; yourself)
		with: (debugButton sizeToContent; yourself)
		with: (rebuildButton sizeToContent; yourself)
		with: (status flex: 1; yourself)).
	toolbar spacing: 6; padding: (6 @ 4 corner: 8 @ 4); fixed: 29.
	output := ToolTextEditor new name: 'output'; title: 'output'; readOnly: true; highlighting: false; yourself.
	screen := GuestScreen new name: 'screen'; yourself.
	screen onOpen: [self showScreen].
	screenPane := self pane: screen title: 'Guest display'.
	screenPane visible: false.
	outputPane := self pane: output title: 'Output'.
	self addAll: (Array with: toolbar with: ((self pane: arguments title: 'command line') fixed: 52) with: screenPane with: outputPane)
!
minimumWindowExtent
	^320 @ 200
! !

!VMSimulator methodsFor: 'accessing'!
output
	^output text
!
screen
	^screen
!
simulation
	^simulation
!
process
	^process
!
isRunning
	^process notNil and: [process isTerminated not]
! !

!VMSimulator methodsFor: 'running'!
commandLine
	^arguments text substrings
!
run
	"Start the simulated VM in its own Process (stopping one still running), below the windows' priority."
	| argv |
	self stop.
	argv := self commandLine.
	output text: ''.
	simulation := nil.
	status text: 'starting'.
	process := [self runSimulation: argv] newProcess.
	process priority: Processor userBackgroundPriority; name: 'Simulated VM'.
	process resume.
	timer isNil ifTrue: [timer := self every: 100 do: [self update]]
!
runSmalltalk80
	arguments text: self class st80Arguments.
	self run
!
runSimulation: argv
	| image sim code source ms |
	code := [
		image := argv detect: [:a | a endsWith: '.image'] ifNone: [nil].
		source := image = self class miniImagePath
			ifTrue: ['vm/tests/mini']
			ifFalse: [image = self class st80ImagePath ifTrue: ['st80'] ifFalse: [nil]].
		source isNil ifFalse: [
			ms := Time millisecondsToRun: [ImageBuilder buildFrom: source to: image].
			lock critical: [pending nextPutAll: '[' , source , ' built in ' , ms printString , ' ms]' , (String with: Character lf)]].
		sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
		sim display: screen.
		sim onOutput: [:text | lock critical: [pending nextPutAll: text]].
		started := sim microsecondClock.
		simulation := sim.
		sim runMain: VMMain arguments: (Array with: 'samaltak') , argv asArray]
			on: Error
			do: [:e | e return: e messageText].
	simulation isNil ifTrue: [^lock critical: [pending nextPutAll: '[' , code asString , ']']].
	lock critical: [pending nextPutAll: (String with: Character lf) , '[' , (code isInteger ifTrue: ['exit ' , code printString] ifFalse: [code asString]) , ' after ' , ((simulation microsecondClock - started) / 1000000.0 printShowingDecimalPlaces: 1) , ' s]']
!
update
	"My window's Process: append what the simulation wrote, show its state."
	| text |
	text := lock critical: [| t | t := pending contents. pending := WriteStream on: String new. t].
	text isEmpty ifFalse: [output appendText: text].
	(process isNil or: [simulation isNil]) ifTrue: [^self].
	status text: (process isTerminated
		ifTrue: ['done']
		ifFalse: [(process isSuspended ifTrue: ['stopped'] ifFalse: ['running']) , ', ' , ((simulation microsecondClock - started) // 1000000) printString , ' s']) , ', ' , self speed , self screenSpeed
!
screenSpeed
	"The guest display's frame time (mean / longest of the last ones) and input latency, if it has frames."
	| t |
	t := screen frameTime.
	t isNil ifTrue: [^''].
	^', frame ' , (t first / 1000.0 printShowingDecimalPlaces: 1) , ' / ' , (t last // 1000) printString , ' ms'
		, (screen latency isNil ifTrue: [''] ifFalse: [', input ' , (screen latency // 1000) printString , ' ms'])
!
showScreen
	"The guest opened its display: show it at 1.5 points a pixel if the screen leaves room (the window grows)."
	| want w |
	screen focus.
	screenPane isVisible ifTrue: [^self].
	screenPane visible: true.
	outputPane fixed: 110.
	w := self window.
	w isNil ifTrue: [^self].
	want := screen screenExtent * 3 / 2 + 16 - screen extent.
	want := w bounds extent + ((want x max: 0) @ (want y max: 0)).
	w bounds: (Tools clamp: w bounds origin extent: (want min: w world extent - (16 @ 40)))
!
speed
	"How many bytecodes the simulated interpreter ran, and how many per second of its Process's time."
	| n us |
	n := simulation bytecodes.
	us := process cpuTime.
	^(self class abbreviate: n) , ' bytecodes' , (us < 100000 ifTrue: [''] ifFalse: [' at ' , (self class abbreviate: n * 1000000 // us) , '/s'])
!
debug
	self isRunning ifFalse: [^Tools toast: 'The simulated VM is not running'].
	Tools debugProcess: process
!
stop
	self isRunning ifTrue: [process terminate].
	process := nil
!
windowClosed
	self stop
! !

!VMSimulator class methodsFor: 'settings'!
miniImagePath
	^'/tmp/samaltak-simulator-mini.image'
!
st80ImagePath
	^'/tmp/samaltak-simulator-st80.image'
!
defaultArguments
	^'--eden 1 --max-heap 64 ' , self miniImagePath , ' --headless Guest'
!
st80Arguments
	^'--eden 4 --max-heap 64 ' , self st80ImagePath , ' --headless'
!
abbreviate: anInteger
	anInteger < 10000 ifTrue: [^anInteger printString].
	anInteger < 10000000 ifTrue: [^(anInteger // 1000) printString , 'k'].
	^(anInteger // 1000000) printString , 'M'
! !

!VMSimulator class methodsFor: 'opening'!
openAt: aPointOrNil
	| tool |
	tool := self new.
	^tool openIn: (Tools placeAt: aPointOrNil extent: 640 @ 400) title: 'VM Simulator'
!
open
	^self openAt: nil
!
initialize
	ToolsMenu register: 'VM Simulator' description: 'the VM, run as Smalltalk' order: 48 action: [:point | self openAt: point]
! !
