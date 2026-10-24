TestCase subclass: #PseudoTerminalTest
	instanceVariableNames: 'pty'
	classVariableNames: ''
	package: 'Tests-Kernel'!

PseudoTerminalTest comment: 'I test PseudoTerminal with real child processes: output and exit status, the terminal size and resizing, environment and directory, writing (the echo comes back), hanging up on close, release when garbage collected, and handles that are dead after an image restart.'!

!PseudoTerminalTest methodsFor: 'running'!
tearDown
	pty isNil ifFalse: [pty close]
! !

!PseudoTerminalTest methodsFor: 'support'!
spawn: argv
	^pty := PseudoTerminal spawn: argv environment: nil directory: nil rows: 24 columns: 80
!
outputUntil: aString
	"Read until the output contains aString, the end, or 10 s; answer the output."
	| buffer out n deadline |
	buffer := ByteArray new: 4096.
	out := WriteStream on: (ByteArray new: 256).
	deadline := Time millisecondClockValue + 10000.
	[(out contents asString includesSubstring: aString) or: [Time millisecondClockValue > deadline]] whileFalse: [
		n := pty readInto: buffer.
		n isNil
			ifTrue: [pty semaphore waitTimeoutMSecs: 200]
			ifFalse: [
				n = 0 ifTrue: [^out contents asString].
				out nextPutAll: (buffer first: n)]].
	^out contents asString
!
ptys
	^Smalltalk vm platformHandleCounts at: #ptys ifAbsent: [0]
! !

!PseudoTerminalTest methodsFor: 'tests'!
testOutputAndExitStatus
	self spawn: #('sh' '-c' 'printf "hi\nthere"; exit 3').
	self assert: pty pid > 0.
	self assert: (self outputUntil: 'end of output never printed') equals: 'hi', (String with: Character cr with: Character lf), 'there'.
	self assert: pty waitForExit equals: 3.
	self deny: pty isRunning.
	self assert: (pty readInto: (ByteArray new: 10)) equals: 0
!
testSizeAndResize
	| out |
	self spawn: #('sh' '-c' 'stty size; read x; stty size').
	self assert: ((self outputUntil: '24 80') includesSubstring: '24 80').
	pty rows: 30 columns: 100.
	pty nextPutAll: 'go', (String with: Character cr).
	out := self outputUntil: '30 100'.
	self assert: (out includesSubstring: '30 100') description: out
!
testEnvironmentAndDirectory
	| out |
	pty := PseudoTerminal spawn: #('sh' '-c' 'printf "[$FOO $TERM]"; pwd') environment: #('PATH=/bin:/usr/bin' 'FOO=bar') directory: '/' rows: 24 columns: 80.
	out := self outputUntil: (String with: Character lf).
	self assert: (out includesSubstring: '[bar xterm-256color]') description: out.
	self assert: (out endsWith: ']/', (String with: Character cr with: Character lf)) description: out
!
testInheritedEnvironmentGetsTerm
	| out |
	self spawn: #('sh' '-c' 'printf "[$TERM]"').
	out := self outputUntil: ']'.
	self assert: out equals: '[xterm-256color]'
!
testWriteIsEchoed
	| crlf out |
	crlf := String with: Character cr with: Character lf.
	self spawn: #('cat').
	self assert: (pty nextPutAll: 'hello ü', (String with: Character cr)).
	out := self outputUntil: ('hello ü', crlf, 'hello ü', crlf) utf8Encoded asString.
	self assert: out asByteArray utf8Decoded equals: 'hello ü', crlf, 'hello ü', crlf.
	self assert: pty isRunning
!
testCloseHangsUpTheChild
	| count |
	self spawn: #('cat').
	self assert: pty isRunning.
	count := self ptys.
	pty close.
	self deny: pty isOpen.
	self assert: self ptys < count.
	self assert: (pty readInto: (ByteArray new: 4)) equals: 0.
	self assert: (pty write: 'x' from: 1 count: 1) equals: 0
!
testCollectedTerminalIsClosed
	| registry count |
	registry := WeakArray with: (PseudoTerminal spawn: #('cat') environment: nil directory: nil rows: 24 columns: 80).
	count := self ptys.
	Smalltalk vm garbageCollect.
	self assert: (registry at: 1) isNil.
	self assert: (self waitFor: [self ptys < count]) description: 'the collected pty was not closed'
!
testDeadAfterRestart
	| handle |
	self spawn: #('sh' '-c' 'exit 0').
	handle := pty instVarNamed: 'handle'.
	PseudoTerminal startUp: true.
	[self deny: pty isOpen.
	 self assert: (pty readInto: (ByteArray new: 4)) equals: 0.
	 self assert: pty exitStatus isNil]
		ensure: [PseudoTerminal primClose: handle]
!
testUnknownProgramFails
	self should: [self spawn: #('/nonexistent/program')] raise: FileError
! !
