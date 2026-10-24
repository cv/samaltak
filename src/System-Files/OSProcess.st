Object subclass: #OSProcess
	instanceVariableNames: 'command directory pid exitCode output errorOutput outputPath errorPath'
	classVariableNames: 'NextId'
	package: 'System-Files'!

OSProcess comment: 'I run an external program through /bin/sh and capture its exit code, standard output and standard error (redirected into temporary files, read and deleted when it ends). Waiting polls with a Delay, so only the waiting Process blocks.

	(OSProcess run: ''wc -l vm/gen/*.c'') output.
	OSProcess outputOf: ''gst vm/tests/bench/suite-gst.st''.
	(OSProcess run: ''make -s'' in: ''vm'') exitCode.
	OSProcess run: (OSProcess commandFor: #(''ls'' ''-l'' ''a file''))	"arguments quoted for the shell"

Output is decoded from UTF-8. A non-zero exit code is not an error: ask succeeded.'!

!OSProcess methodsFor: 'accessing'!
command
	^command
!
directory
	^directory
!
pid
	^pid
!
exitCode
	"Answer the exit status (128 + signal number when killed by a signal), or nil while running."
	^exitCode
!
output
	"Answer what the program wrote to standard output (nil while running)."
	^output
!
errorOutput
	"Answer what the program wrote to standard error (nil while running)."
	^errorOutput
!
outputSoFar
	"Answer what the program has written to standard output up to now."
	output isNil ifFalse: [^output].
	(outputPath isNil or: [(File exists: outputPath) not]) ifTrue: [^''].
	^File readText: outputPath
!
succeeded
	^exitCode = 0
!
isRunning
	pid isNil ifTrue: [^false].
	exitCode isNil ifTrue: [self poll].
	^exitCode isNil
! !

!OSProcess methodsFor: 'running'!
start
	"Start the program. Answer self."
	| script |
	pid isNil ifFalse: [^self error: 'already started'].
	outputPath := self class temporaryPath: 'out'.
	errorPath := self class temporaryPath: 'err'.
	script := String new: 100 streamContents: [:s |
		directory isNil ifFalse: [s nextPutAll: 'cd '; nextPutAll: (self class quote: directory); nextPutAll: ' && '].
		s nextPutAll: '( '; nextPutAll: command; nextPutAll: ' ) >'; nextPutAll: (self class quote: outputPath);
			nextPutAll: ' 2>'; nextPutAll: (self class quote: errorPath); nextPutAll: ' </dev/null'].
	pid := File primSpawn: {'/bin/sh'. '-c'. script}.
	pid isNil ifTrue: [^FileError signal: 'Cannot start /bin/sh: ', File lastError path: '/bin/sh'].
	^self
!
wait
	"Wait until the program has ended, then answer self with exitCode, output and errorOutput set."
	| ms |
	ms := 1.
	[self poll] whileFalse: [
		(Delay forMilliseconds: ms) wait.
		ms := ms * 2 min: 50].
	^self
!
terminate
	"Send SIGTERM to the program."
	self isRunning ifTrue: [(self class new setCommand: 'kill ', pid printString directory: nil) start; wait]
! !

!OSProcess methodsFor: 'private'!
setCommand: aString directory: aPathOrNil
	command := aString.
	directory := aPathOrNil
!
poll
	"Answer true once the program has ended (collecting its results)."
	| status |
	exitCode isNil ifFalse: [^true].
	status := File primWait: pid blocking: false.
	status isNil ifTrue: [^false].
	output := self readAndDelete: outputPath.
	errorOutput := self readAndDelete: errorPath.
	exitCode := status.
	^true
!
readAndDelete: aPath
	| text |
	(File exists: aPath) ifFalse: [^''].
	text := File readText: aPath.
	File delete: aPath.
	^text
! !

!OSProcess methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an OSProcess('; print: command.
	exitCode isNil
		ifTrue: [aStream nextPutAll: (pid isNil ifTrue: [' not started'] ifFalse: [' running'])]
		ifFalse: [aStream nextPutAll: ' exit '; print: exitCode].
	aStream nextPut: $)
! !

!OSProcess class methodsFor: 'running'!
command: aString
	"Answer an unstarted OSProcess for the shell command aString."
	^self new setCommand: aString directory: nil
!
run: aString
	"Run the shell command aString in the VM's working directory; answer the finished OSProcess."
	^(self command: aString) start; wait
!
run: aString in: aDirectory
	"Run the shell command aString in aDirectory; answer the finished OSProcess."
	^(self new setCommand: aString directory: aDirectory) start; wait
!
outputOf: aString
	"Run the shell command aString and answer its standard output."
	^(self run: aString) output
! !

!OSProcess class methodsFor: 'shell'!
quote: aString
	"Answer aString as one single-quoted shell word."
	^String new: aString size + 2 streamContents: [:s |
		s nextPut: $'.
		aString do: [:c | c = $' ifTrue: [s nextPutAll: '''\'''''] ifFalse: [s nextPut: c]].
		s nextPut: $']
!
commandFor: anArrayOfStrings
	"Answer a shell command running the program anArrayOfStrings first with the remaining arguments, each passed verbatim."
	^String new: 100 streamContents: [:s |
		anArrayOfStrings do: [:arg | s nextPutAll: (self quote: arg)] separatedBy: [s space]]
! !

!OSProcess class methodsFor: 'private'!
temporaryPath: aSuffix
	"Answer a fresh file path in $TMPDIR (or /tmp), unique to this run of the VM."
	| tmp |
	tmp := (Smalltalk vm getenv: 'TMPDIR') ifNil: ['/tmp'].
	NextId := (NextId ifNil: [0]) + 1.
	^tmp / ('samaltak-', Time utcMicroseconds printString, '-', NextId printString, '.', aSuffix)
! !
