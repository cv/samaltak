ToolPane subclass: #VMSimulator
	instanceVariableNames: 'arguments output runButton debugButton status simulation process lock pending started'
	classVariableNames: ''
	package: 'Tools'!

VMSimulator comment: 'I run the VM itself as Smalltalk: the Lowtalk sources of VM-Core (the same code the C build is translated from) in a VMSimulation, on an image, with a command line. Output appears as the simulated VM writes it; Debug stops the simulated VM''s Process in a debugger, showing the interpreter''s own methods (Interpreter>>interpret, the bytecode handlers, the GC) as they run.

The default command line runs the VM tests'' mini kernel image (built from vm/tests/mini with ImageBuilder the first time) on its Arith test.'!

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
	status := Label text: 'not running' font: #smallItalic.
	status color: #ink3; align: #right.
	toolbar := Row with: (Array
		with: (runButton sizeToContent; yourself)
		with: (debugButton sizeToContent; yourself)
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
	"Start the simulated VM in its own Process (stopping one still running)."
	| argv image |
	self stop.
	argv := self commandLine.
	image := argv detect: [:a | a endsWith: '.image'] ifNone: [nil].
	(image notNil and: [(File exists: image) not and: [image = self class miniImagePath]]) ifTrue: [
		status text: 'building the mini kernel image…'.
		ImageBuilder buildFrom: 'vm/tests/mini' to: image].
	output text: ''.
	simulation := VMSimulation modules: (VMModule vmModules select: [:c | c packageName = 'VM-Core']).
	simulation onOutput: [:text | lock critical: [pending nextPutAll: text]].
	started := Time millisecondClockValue.
	status text: 'running'.
	process := [self runSimulation: argv] newProcess.
	process priority: Processor userBackgroundPriority; name: 'Simulated VM'.
	process resume.
	self every: 100 do: [self update]
!
runSimulation: argv
	| code |
	code := [simulation runMain: VMMain arguments: (Array with: 'samaltak') , argv asArray]
		on: Error
		do: [:e | e return: e messageText].
	lock critical: [pending nextPutAll: (String with: Character lf) , '[' , (code isInteger ifTrue: ['exit ' , code printString] ifFalse: [code asString]) , ' after ' , ((Time millisecondClockValue - started) / 1000.0 printShowingDecimalPlaces: 1) , ' s]']
!
update
	"My window's Process: append what the simulation wrote, show its state."
	| text |
	text := lock critical: [| t | t := pending contents. pending := WriteStream on: String new. t].
	text isEmpty ifFalse: [output appendText: text].
	process isNil ifTrue: [^self].
	status text: (process isTerminated
		ifTrue: ['done']
		ifFalse: [(process isSuspended ifTrue: ['stopped'] ifFalse: ['running']) , ', ' , ((Time millisecondClockValue - started) // 1000) printString , ' s'])
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
	^'--eden 1 --max-heap 64 ' , self miniImagePath , ' --headless Arith'
! !

!VMSimulator class methodsFor: 'opening'!
openAt: aPointOrNil
	| tool |
	tool := self new.
	^tool openIn: (Tools placeAt: aPointOrNil extent: 560 @ 380) title: 'VM Simulator'
!
open
	^self openAt: nil
!
initialize
	ToolsMenu register: 'VM Simulator' description: 'the VM, run as Smalltalk' order: 48 action: [:point | self openAt: point]
! !
