ToolPane subclass: #Terminal
	instanceVariableNames: 'view command directory pty ioProcess lock pending pendingSize offset feeding feedAnimation outbox drained'
	classVariableNames: ''
	package: 'Tools'!

Terminal comment: 'I am a Terminal window: a program (by default a login shell, $SHELL -l, in the directory holding the image''s sources) on a pseudo-terminal (PseudoTerminal), shown and typed into through a TerminalView.

My I/O Process (''Terminal pty'', priority 40) waits on the pty''s Semaphore, reads the program''s output in slices of 16 KB into a queue and sends what the user typed; when more than 1 MB is queued it stops reading until my window caught up, so a program printing without end is slowed down to what the screen can show. My window''s Process interprets the queue: at once when output arrives after a pause, then once per compositor frame (a frame animation) for at most 10 ms, so the screen is redrawn at most once per frame and the window stays responsive.

	Tools openTerminal.
	Terminal openOn: #(''/bin/sh'') in: ''/tmp''.

When the program ends I show its exit status; closing the window hangs it up.'!

!Terminal methodsFor: 'initialization'!
initialize
	super initialize.
	view := TerminalView new.
	lock := Semaphore forMutualExclusion.
	pending := OrderedCollection new.
	pendingSize := 0.
	offset := 0.
	feeding := false.
	outbox := OrderedCollection new.
	drained := Semaphore new.
	self add: view
!
command: anArray directory: aPathOrNil
	command := anArray.
	directory := aPathOrNil
!
minimumWindowExtent
	^200 @ 80
! !

!Terminal methodsFor: 'accessing'!
view
	^view
!
screen
	^view screen
!
pty
	^pty
!
command
	^command
!
ioProcess
	^ioProcess
!
isRunning
	^pty notNil and: [pty isRunning]
! !

!Terminal methodsFor: 'running'!
start
	"Start the program on a pty of my view's size (in my window's Process)."
	view onSend: [:bytes | self send: bytes].
	view onResize: [:rows :cols | pty isNil ifFalse: [pty rows: rows columns: cols]].
	view onTitle: [:title | self windowTitle: (title isEmpty ifTrue: [self class title] ifFalse: [self class title, ' — ', title])].
	pty := [PseudoTerminal spawn: command environment: nil directory: directory rows: view screen rows columns: view screen cols]
		on: Error do: [:e | e return: nil].
	pty isNil ifTrue: [
		self showMessage: 'Cannot start ', command first, ': ', File lastError.
		^self].
	ioProcess := [self runIO] newProcess.
	ioProcess priority: Processor userSchedulingPriority; name: 'Terminal pty'.
	self window isNil ifFalse: [ioProcess window: self window].
	ioProcess resume
!
runIO
	"The I/O Process: read output into the queue, send the outbox, wait on the pty's Semaphore."
	| buffer n |
	buffer := ByteArray new: 16384.
	[pty isOpen] whileTrue: [
		self flushOutbox.
		n := pty readInto: buffer.
		n isNil
			ifTrue: [pty semaphore waitTimeoutMSecs: 1000]
			ifFalse: [
				n = 0 ifTrue: [^self programEnded].
				self received: (buffer copyFrom: 1 to: n).
				[pendingSize > self class maxPending and: [pty isOpen]] whileTrue: [
					self flushOutbox.
					drained waitTimeoutMSecs: 50]]]
!
received: bytes
	"The I/O Process: queue output; have my window interpret it unless it is already doing so."
	| post w |
	w := self window.
	lock critical: [
		pending addLast: bytes.
		pendingSize := pendingSize + bytes size.
		post := feeding not.
		feeding := true].
	(post and: [w notNil]) ifTrue: [w do: [self feed]]
!
feed
	"My window's Process: interpret the queued output now; if more keeps coming, once per frame."
	self interpretFor: self class frameBudget.
	lock critical: [pending isEmpty ifTrue: [feeding := false]].
	(feeding and: [feedAnimation isNil and: [self window notNil]]) ifTrue: [
		feedAnimation := self window requestAnimationFrames: [:ms | self feedFrame]]
!
feedFrame
	"A frame of the feed animation: answer whether to go on."
	self interpretFor: self class frameBudget.
	lock critical: [pending isEmpty ifTrue: [feeding := false]].
	feeding ifTrue: [^true].
	feedAnimation := nil.
	^false
!
interpretFor: milliseconds
	"Interpret queued output in slices of 4 KB until it is all done or milliseconds have passed; then update the view once."
	| deadline chunk n any |
	deadline := Time millisecondClockValue + milliseconds.
	any := false.
	[chunk := lock critical: [pending isEmpty ifTrue: [nil] ifFalse: [pending first]].
	 chunk notNil] whileTrue: [
		n := chunk size - offset min: 4096.
		view feed: chunk from: offset + 1 to: offset + n.
		any := true.
		offset := offset + n.
		offset >= chunk size ifTrue: [
			offset := 0.
			lock critical: [
				pending removeFirst.
				pendingSize := pendingSize - chunk size].
			drained signal].
		Time millisecondClockValue >= deadline ifTrue: [
			view afterOutput.
			^self]].
	any ifTrue: [view afterOutput]
!
pendingSize
	^pendingSize
!
send: bytes
	"What the user typed (any Process): write it now if the pty takes it, else leave the rest to the I/O Process."
	| rest n |
	pty isNil ifTrue: [^self].
	lock critical: [
		rest := bytes.
		outbox isEmpty ifTrue: [
			n := pty write: bytes from: 1 count: bytes size.
			(n notNil and: [n > 0]) ifTrue: [rest := bytes copyFrom: n + 1 to: bytes size]].
		rest isEmpty ifFalse: [outbox addLast: rest]].
	rest isEmpty ifFalse: [pty semaphore signal]
!
flushOutbox
	"The I/O Process: write what is waiting, as far as the pty takes it."
	lock critical: [
		[outbox notEmpty and: [pty isOpen]] whileTrue: [ | bytes n |
			bytes := outbox first.
			n := pty write: bytes from: 1 count: bytes size.
			(n isNil or: [n = 0]) ifTrue: [^self].
			n = bytes size
				ifTrue: [outbox removeFirst]
				ifFalse: [outbox at: 1 put: (bytes copyFrom: n + 1 to: bytes size)]]]
!
programEnded
	"The I/O Process: the program closed the terminal."
	| status w deadline |
	deadline := Time millisecondClockValue + 2000.
	[(status := pty exitStatus) isNil and: [Time millisecondClockValue < deadline]] whileTrue: [(Delay forMilliseconds: 10) wait].
	w := self window.
	w isNil ifFalse: [w do: [self showExit: status]]
!
showExit: status
	"My window's Process: the program ended."
	self interpretFor: 1000.
	view exitStatus: status.
	self showMessage: (status = 0 | status isNil
		ifTrue: ['[Process completed]']
		ifFalse: ['[Process exited with status ', status printString, ']']).
	pty close
!
showMessage: aString
	| crlf bytes |
	crlf := String with: Character cr with: Character lf.
	view screen col > 1 ifTrue: [view feed: crlf asByteArray from: 1 to: 2].
	bytes := (crlf, aString, crlf) utf8Encoded.
	view feed: bytes from: 1 to: bytes size.
	view afterOutput
!
windowClosed
	"Hang the program up and end my I/O Process."
	| p |
	feedAnimation isNil ifFalse: [feedAnimation stop. feedAnimation := nil].
	pty isNil ifFalse: [pty close].
	p := ioProcess.
	ioProcess := nil.
	(p notNil and: [p isTerminated not and: [p ~~ Processor activeProcess]]) ifTrue: [p terminate]
! !

!Terminal methodsFor: 'remote control'!
remoteKind
	^#terminal
! !

!Terminal class methodsFor: 'settings'!
title
	^'Terminal'
!
frameBudget
	"Milliseconds of output interpretation per frame."
	^10
!
maxPending
	"Bytes of output queued before the I/O Process stops reading."
	^1048576
! !

!Terminal class methodsFor: 'opening'!
open
	"A login shell in the repository holding the image's sources."
	^self openOn: self loginShellCommand in: self repositoryDirectory at: nil
!
openAt: aPointOrNil
	^self openOn: self loginShellCommand in: self repositoryDirectory at: aPointOrNil
!
openOn: argv in: aDirectory
	^self openOn: argv in: aDirectory at: nil
!
openOn: argv in: aDirectory at: aPointOrNil
	"Run argv on a new 80 × 24 Terminal window in aDirectory; answer the window."
	| terminal extent |
	terminal := self new command: argv asArray directory: aDirectory.
	extent := (terminal view preferredExtentForRows: 24 cols: 80) + (2 @ 24).
	^self open: terminal in: (Tools placeAt: aPointOrNil extent: extent)
!
open: aTerminal in: aRectangle
	| window |
	window := aTerminal openIn: aRectangle title: self title.
	window do: [
		aTerminal start.
		aTerminal view focus].
	^window
!
loginShellCommand
	| shell |
	shell := Smalltalk vm getenv: 'SHELL'.
	(shell isNil or: [shell isEmpty]) ifTrue: [shell := '/bin/sh'].
	^Array with: shell with: '-l'
!
repositoryDirectory
	"The directory that holds the image's sources (src/packages.txt): the image's, or one or two above (build/, build/term/); else the VM's working directory."
	| image dir |
	image := Smalltalk vm imagePath.
	image isNil ifFalse: [
		dir := File directoryOf: (self absolutePath: image).
		3 timesRepeat: [
			(File exists: dir, '/src/packages.txt') ifTrue: [^dir].
			dir := File directoryOf: dir]].
	^Directory current
!
absolutePath: aPath
	"aPath made absolute (against the working directory), without . and .. components."
	| parts result |
	parts := ((aPath beginsWith: '/') ifTrue: [aPath] ifFalse: [Directory current, '/', aPath]) subStrings: '/'.
	result := OrderedCollection new.
	parts do: [:each |
		each = '..'
			ifTrue: [result isEmpty ifFalse: [result removeLast]]
			ifFalse: [(each isEmpty or: [each = '.']) ifFalse: [result addLast: each]]].
	^String new: aPath size streamContents: [:s | result do: [:each | s nextPut: $/; nextPutAll: each]]
!
initialize
	ToolsMenu register: 'Terminal' description: '$SHELL -l' order: 45 action: [:point | self openAt: point].
	Tools registerOpener: #terminal with: [:argOrNil | self open]
! !
