ToolPane subclass: #VMSimulator
	instanceVariableNames: 'arguments output runButton debugButton rebuildButton status simulation process lock pending started timer'
	classVariableNames: ''
	package: 'Tools'!

VMSimulator comment: 'I run the VM itself as Smalltalk: the Lowtalk sources of VM-Core (the same code the C build is translated from) in a VMSimulation, on an image, with a command line. Output appears as the simulated VM writes it; Debug stops the simulated VM''s Process in a debugger, showing the interpreter''s own methods (Interpreter>>interpret, the bytecode handlers, the GC) as they run.

The default command line boots the VM tests'' mini kernel image (built from vm/tests/mini with ImageBuilder at each run) as a guest that prints a line a second with what the VM calls itself (VMMain>>banner): edit that method in the System Browser and the next line shows it. The status shows how many bytecodes the simulated interpreter ran, and how fast. Rebuild & reboot does the same to the image itself (VMRebuilder).'!

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
	rebuildButton := Button label: 'Rebuild & reboot' action: [VMRebuilder openAndRebuild].
	rebuildButton name: 'rebuild'; tooltip: 'translate the VM to C, compile it and restart this image on it'.
	status := Label text: 'not running' font: #smallItalic.
	status color: #ink3; align: #right.
	toolbar := Row with: (Array
		with: (runButton sizeToContent; yourself)
		with: (debugButton sizeToContent; yourself)
		with: (rebuildButton sizeToContent; yourself)
		with: (status flex: 1; yourself)).
	toolbar spacing: 6; padding: (6 @ 4 corner: 8 @ 4); fixed: 29.
	output := ToolTextEditor new name: 'output'; title: 'output'; readOnly: true; highlighting: false; yourself.
	self addAll: (Array with: toolbar with: ((self pane: arguments title: 'command line') fixed: 52) with: (self pane: output title: 'Output'))
!
minimumWindowExtent
	^320 @ 200
! !

!VMSimulator methodsFor: 'accessing'!
output
	^output text
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
runSimulation: argv
	| image sim code |
	code := [
		image := argv detect: [:a | a endsWith: '.image'] ifNone: [nil].
		image = self class miniImagePath ifTrue: [ImageBuilder buildFrom: 'vm/tests/mini' to: image].
		sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName = 'VM-Core']).
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
		ifFalse: [(process isSuspended ifTrue: ['stopped'] ifFalse: ['running']) , ', ' , ((simulation microsecondClock - started) // 1000000) printString , ' s']) , ', ' , self speed
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
defaultArguments
	^'--eden 1 --max-heap 64 ' , self miniImagePath , ' --headless Guest'
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
