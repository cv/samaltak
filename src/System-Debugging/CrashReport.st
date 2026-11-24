Object subclass: #CrashReport
	instanceVariableNames: 'title exception frames process'
	classVariableNames: ''
	package: 'System-Debugging'!

CrashReport comment: 'I am a report of an error in a Process, written on request (the Notifier''s and the Debugger''s Save report; the stack is taken when I am made) to samaltak-crash-<n>.txt, the first n not taken, in CrashReport directory, XDG state samaltak (~/.local/state/samaltak). It says what the error was, the Process, the time (UTC) and the uptime, the VM, the image''s base commit, the heap''s statistics and the stack (each frame''s printString, at most maxFrames).

	(CrashReport forSession: aDebugSession) write	"the path"
	[1 / 0] on: ZeroDivide do: [:e | (CrashReport exception: e context: e signalerContext process: Processor activeProcess) write]'!

!CrashReport class methodsFor: 'instance creation'!
exception: anException context: aContext process: aProcess
	^self new setTitle: nil exception: anException context: aContext process: aProcess
!
forSession: aDebugSession
	"The report of a stopped Process (its exception, if any, and where it stopped)."
	^self new setTitle: aDebugSession label exception: aDebugSession exception context: aDebugSession interruptedContext process: aDebugSession process
! !

!CrashReport class methodsFor: 'accessing'!
directory
	"Where reports go: XDG state samaltak."
	^XDG state: 'samaltak'
!
nextPathIn: aDirectory
	"samaltak-crash-<n>.txt in aDirectory, the first n not taken."
	| n |
	n := 1.
	[File exists: (File join: aDirectory with: 'samaltak-crash-', n printString, '.txt')] whileTrue: [n := n + 1].
	^File join: aDirectory with: 'samaltak-crash-', n printString, '.txt'
!
maxFrames
	^200
! !

!CrashReport methodsFor: 'initialization'!
setTitle: aString exception: anException context: aContext process: aProcess
	title := aString.
	exception := anException.
	frames := self frameLinesFrom: aContext.
	process := aProcess
! !

!CrashReport methodsFor: 'writing'!
write
	"Write me in CrashReport directory; answer the path."
	^self writeIn: self class directory
!
writeIn: aDirectory
	| path |
	Directory ensureExists: aDirectory.
	path := self class nextPathIn: aDirectory.
	File writeText: self text to: path.
	^path
! !

!CrashReport methodsFor: 'text'!
text
	^String streamContents: [:s | self printOn: s]
!
printOn: aStream
	| lf stats commit ms |
	lf := String with: Character lf.
	aStream nextPutAll: 'Samaltak error report'; nextPutAll: lf.
	aStream nextPutAll: 'error: '; nextPutAll: self errorText; nextPutAll: lf.
	title isNil ifFalse: [aStream nextPutAll: 'stopped: '; nextPutAll: title asString; nextPutAll: lf].
	process isNil ifFalse: [
		aStream nextPutAll: 'process: '; print: process name; nextPutAll: ' at priority '; print: process priority; nextPutAll: lf].
	aStream nextPutAll: 'time: '; nextPutAll: (self class timeTextOf: Time utcMicroseconds); nextPutAll: ' UTC'; nextPutAll: lf.
	ms := Time millisecondClockValue.
	aStream nextPutAll: 'uptime: '; print: ms // 1000; nextPut: $.; nextPutAll: (ms \\ 1000 printPaddedWith: $0 to: 3); nextPutAll: ' s'; nextPutAll: lf.
	commit := (Smalltalk at: #SourceFiler ifAbsent: [nil]) ifNotNil: [:filer | filer baseCommit].
	aStream nextPutAll: 'vm: '; nextPutAll: (Smalltalk vm banner ifNil: ['?']) asString;
		nextPutAll: (Machine hasFirmware ifTrue: [', UEFI'] ifFalse: [', hosted']);
		nextPutAll: ', image at '; nextPutAll: (commit ifNil: ['an unknown commit']); nextPutAll: lf.
	stats := Smalltalk vm statistics.
	aStream nextPutAll: 'heap: limit '; print: stats maxHeapBytes // 1048576; nextPutAll: ' MB, old space '; print: stats oldBytesUsed // 1048576;
		nextPutAll: ' MB, allocated '; print: stats bytesAllocated // 1048576; nextPutAll: ' MB in all, ';
		print: stats scavenges; nextPutAll: ' scavenges, '; print: stats fullGCs; nextPutAll: ' full GCs'; nextPutAll: lf.
	aStream nextPutAll: lf; nextPutAll: 'Smalltalk stack:'; nextPutAll: lf.
	frames do: [:line | aStream nextPutAll: line; nextPutAll: lf]
!
errorText
	exception isNil ifTrue: [^title ifNil: ['none']].
	^exception class name, ': ', ([exception messageText asString] on: Error do: [:e | e return: '(no message)'])
!
frameLinesFrom: aContext
	"A line per frame from aContext down, at most maxFrames, then how many more (taken when I am made: the frames may not live on)."
	^Array streamContents: [:s | self frameLinesFrom: aContext do: [:line | s nextPut: line]]
!
frameLinesFrom: aContext do: aBlock
	| ctx n |
	ctx := aContext.
	n := 0.
	[ctx notNil] whileTrue: [
		n < self class maxFrames ifTrue: [aBlock value: ([ctx printString] on: Error do: [:e | e return: '(a frame that does not print)'])].
		n := n + 1.
		ctx := ctx sender].
	n > self class maxFrames ifTrue: [aBlock value: '... ', (n - self class maxFrames) printString, ' more frames']
! !

!CrashReport class methodsFor: 'private'!
timeTextOf: utcMicroseconds
	"yyyy-mm-dd hh:mm:ss of UTC microseconds since 1970."
	| seconds days z era doe yoe y doy mp d m |
	seconds := utcMicroseconds // 1000000.
	days := seconds // 86400.
	z := days + 719468.
	era := z // 146097.
	doe := z - (era * 146097).
	yoe := doe - (doe // 1460) + (doe // 36524) - (doe // 146096) // 365.
	y := yoe + (era * 400).
	doy := doe - ((365 * yoe) + (yoe // 4) - (yoe // 100)).
	mp := (5 * doy) + 2 // 153.
	d := doy - ((153 * mp) + 2 // 5) + 1.
	m := mp < 10 ifTrue: [mp + 3] ifFalse: [mp - 9].
	m <= 2 ifTrue: [y := y + 1].
	^String streamContents: [:s |
		s print: y; nextPut: $-;
			nextPutAll: (m printPaddedWith: $0 to: 2); nextPut: $-;
			nextPutAll: (d printPaddedWith: $0 to: 2); nextPut: $ ;
			nextPutAll: (seconds \\ 86400 // 3600 printPaddedWith: $0 to: 2); nextPut: $:;
			nextPutAll: (seconds \\ 3600 // 60 printPaddedWith: $0 to: 2); nextPut: $:;
			nextPutAll: (seconds \\ 60 printPaddedWith: $0 to: 2)]
! !
