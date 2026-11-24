ToolPane subclass: #VMRebuilder
	instanceVariableNames: 'output rebuildButton status process lock pending phase started timer'
	classVariableNames: ''
	package: 'Tools'!

VMRebuilder comment: 'I rebuild the VM from the image''s own Lowtalk (VM-Core and VM-Platform as the System Browser shows them, edits included) and restart the image on it:

1. VMTranslator translates the VM for this CPU into <dir>/gen; <dir> is build/vm beside the source directory (SourceFiler, --source-dir), never the checked-in vm/gen.
2. make (vm/Makefile of the current directory) compiles it into <dir>/build/samaltak, its output streaming into my window; the binary is then renamed to <dir>/samaltak, so a VM running from there keeps its own file.
3. The image is saved in place, the screen fades to black (World>>leave) and the VM''s process execs <dir>/samaltak on it with the image''s arguments, the control port pinned (File primExec:): same pid, standard streams and port, so a samaltak-ctl session carries on. The image resumes as from any snapshot (behind the restart splash), this window too, and logs how long it took.

	VMRebuilder openAndRebuild'!

!VMRebuilder methodsFor: 'initialization'!
initialize
	| toolbar |
	super initialize.
	lock := Semaphore forMutualExclusion.
	pending := WriteStream on: String new.
	phase := 'idle'.
	rebuildButton := Button label: 'Rebuild & reboot' action: [self rebuild].
	rebuildButton name: 'rebuild'; tooltip: 'translate the VM to C, compile it, save the image and restart it on the new VM'.
	status := Label text: phase font: #smallItalic.
	status color: #ink3; align: #right.
	toolbar := Row with: (Array
		with: (rebuildButton sizeToContent; yourself)
		with: (status flex: 1; yourself)).
	toolbar spacing: 6; padding: (6 @ 4 corner: 8 @ 4); fixed: 29.
	output := ToolTextEditor new name: 'output'; title: 'output'; readOnly: true; highlighting: false; yourself.
	self addAll: (Array with: toolbar with: (self pane: output title: 'translate · make · save · exec'))
!
minimumWindowExtent
	^320 @ 160
! !

!VMRebuilder methodsFor: 'accessing'!
output
	^output text
!
phase
	^phase
!
isRunning
	^process notNil and: [process isTerminated not]
! !

!VMRebuilder methodsFor: 'rebuilding'!
rebuild
	"Rebuild and reboot in a Process of its own (my window's Process)."
	self isRunning ifTrue: [^Tools toast: 'The VM is being rebuilt'].
	timer isNil ifTrue: [timer := self every: 100 do: [self update]].
	output text: ''.
	process := [self rebuildAndReboot] forkAt: Processor userBackgroundPriority named: 'VM rebuild'
!
rebuildAndReboot
	| vm |
	started := Time utcMicroseconds.
	vm := [self build: self class buildDirectory] on: Error do: [:e | e return: (self fail: e messageText)].
	vm isNil ifFalse: [self reboot: vm]
!
build: aDirectory
	"Translate and compile the VM in aDirectory; answer the new binary's path, or nil."
	| t make shown |
	phase := 'translating'.
	t := Time millisecondClockValue.
	self line: 'translate VM-Core and VM-Platform to C in ', aDirectory, '/gen'.
	OSProcess run: 'mkdir -p ', (OSProcess quote: aDirectory).
	(Smalltalk at: #VMTranslator) generateVMInto: aDirectory, '/gen' for: Smalltalk vm jitArchitecture.
	self line: '  ', (self secondsSince: t), ' s'.
	phase := 'compiling'.
	t := Time millisecondClockValue.
	self line: 'make'.
	make := (OSProcess command: (self class makeCommandIn: aDirectory)) start.
	shown := 0.
	[make isRunning] whileTrue: [
		shown := self show: make outputSoFar from: shown.
		(Delay forMilliseconds: 50) wait].
	self show: make outputSoFar from: shown.
	make succeeded ifFalse: [^self fail: 'make failed (exit ', make exitCode printString, ')'].
	File rename: aDirectory, '/build/samaltak' to: aDirectory, '/samaltak'.
	self line: 'built ', aDirectory, '/samaltak in ', (self secondsSince: t), ' s'.
	^aDirectory, '/samaltak'
!
reboot: aVMPath
	"Save the image, then have the VM's process exec aVMPath on it. Continues here in the new VM."
	| path t0 resumed |
	path := Smalltalk vm imagePath.
	phase := 'rebooting'.
	self line: 'save ', (path copyAfterLast: $/), ', exec the new VM'.
	t0 := Time utcMicroseconds.
	resumed := Smalltalk snapshot: path.
	resumed ifTrue: [
		phase := 'rebooted'.
		^self line: 'rebooted in ', (self secondsSinceUtc: t0), ' s (all: ', (self secondsSinceUtc: started), ' s), the VM says: ', (Smalltalk vm banner ifNil: ['nothing'])].
	Desktop current ifNotNil: [:world | world leave].
	(File primExec: (Array with: aVMPath with: path), self class restartArguments) isNil ifTrue: [
		Desktop current ifNotNil: [:world | world stay].
		self fail: 'exec failed: ', File lastError]
!
fail: aString
	phase := 'failed'.
	self line: aString.
	^nil
! !

!VMRebuilder methodsFor: 'output'!
line: aString
	"Any Process."
	lock critical: [pending nextPutAll: aString; nextPut: Character lf]
!
show: aString from: anIndex
	"Log what aString (output so far) has after anIndex; answer its size."
	aString size > anIndex ifTrue: [lock critical: [pending nextPutAll: (aString copyFrom: anIndex + 1 to: aString size)]].
	^aString size max: anIndex
!
update
	"My window's Process: append what was logged, show the phase."
	| text |
	text := lock critical: [| t | t := pending contents. pending := WriteStream on: String new. t].
	text isEmpty ifFalse: [output appendText: text].
	status text: ((self isRunning and: [phase ~= 'rebooted'])
		ifTrue: [phase, ', ', (self secondsSinceUtc: started), ' s']
		ifFalse: [phase])
!
secondsSince: aMillisecondClockValue
	^(Time millisecondClockValue - aMillisecondClockValue) / 1000.0 printShowingDecimalPlaces: 1
!
secondsSinceUtc: aUtcMicroseconds
	^(Time utcMicroseconds - aUtcMicroseconds) / 1000000.0 printShowingDecimalPlaces: 1
! !

!VMRebuilder class methodsFor: 'settings'!
buildDirectory
	"build/vm beside the source directory (the current directory's without one)."
	| src |
	src := SourceFiler default sourceDirectory.
	src isNil ifTrue: [^Directory current, '/build/vm'].
	(src beginsWith: '/') ifFalse: [src := Directory current, '/', src].
	^(File directoryOf: src), '/build/vm'
!
makeCommandIn: aDirectory
	"vm/Makefile of the current directory, run in aDirectory (with gen/ there), terse, niced: the compilers must not take the CPU from the VM's vsync and UI."
	| vm |
	vm := Directory current, '/vm/'.
	^'nice -n 10 make -C ', (OSProcess quote: aDirectory), ' -f ', (OSProcess quote: vm, 'Makefile'), ' PGO_PROFILE=', (OSProcess quote: vm, 'pgo.profdata'), ' BRIEF=1 -j8 2>&1'
!
restartArguments
	"The image's arguments, with the control server's port pinned (--control-port 0 picks any): its clients find the image again."
	| args i |
	args := Smalltalk vm arguments copy.
	i := args indexOf: '--control-port'.
	(ControlServer current notNil and: [i > 0 and: [i < args size]]) ifTrue: [
		args at: i + 1 put: ControlServer current port printString].
	^args
! !

!VMRebuilder class methodsFor: 'opening'!
openAt: aPointOrNil
	| tool |
	tool := self new.
	tool openIn: (Tools placeAt: aPointOrNil extent: 620 @ 360) title: 'VM Rebuild'.
	^tool
!
openAndRebuild
	"Open a window and rebuild and reboot (in the window's Process)."
	| tool |
	tool := self openAt: nil.
	tool window after: 1 do: [tool rebuild].
	^tool
! !
