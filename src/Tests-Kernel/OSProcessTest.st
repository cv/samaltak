TestCase subclass: #OSProcessTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

OSProcessTest comment: 'Tests OSProcess (external programs through /bin/sh) and the File/Directory helpers it is used with.'!

!OSProcessTest methodsFor: 'tests'!
testAnyRunningWhileAProgramRuns
	| p |
	self deny: OSProcess anyRunning.
	p := (OSProcess command: 'sleep 30') start.
	self assert: OSProcess anyRunning.
	p terminate; wait.
	self deny: OSProcess anyRunning
!
testOutputAndExitCode
	| p |
	p := OSProcess run: 'printf ''hello\nworld\n''; printf oops >&2; exit 3'.
	self assert: p output equals: 'hello
world
'.
	self assert: p errorOutput equals: 'oops'.
	self assert: p exitCode equals: 3.
	self deny: p succeeded.
	self deny: p isRunning.
	self assert: (OSProcess outputOf: 'echo $((6 * 7))') equals: '42
'
!
testQuotedArguments
	| odd |
	odd := 'it''s "a" $HOME `x` \ ', (String with: (Character value: 955)).
	self assert: (OSProcess outputOf: (OSProcess commandFor: {'printf'. '%s|%s'. odd. 'b c'})) equals: odd, '|b c'
!
testRunInDirectory
	| dir |
	dir := self scratchDirectory.
	File writeText: 'a
b
c
' to: dir / 'three.txt'.
	self assert: (OSProcess run: 'wc -l < three.txt' in: dir) output trimBoth equals: '3'.
	self assert: (File lineCountOf: dir / 'three.txt') equals: 3
!
testAllFilesUnder
	| dir |
	dir := self scratchDirectory.
	Directory create: dir / 'sub'.
	File writeText: 'x' to: dir / 'a.c'.
	File writeText: 'y' to: dir / 'sub' / 'b.st'.
	self assert: (Directory allFilesUnder: dir) equals: {dir / 'a.c'. dir / 'sub' / 'b.st'}
!
testWaitingBlocksOnlyTheWaiter
	| count p |
	count := 0.
	self fork: [[true] whileTrue: [count := count + 1. (Delay forMilliseconds: 5) wait]].
	p := OSProcess run: 'sleep 0.3'.
	self assert: p succeeded.
	self assert: count > 5
!
testTerminate
	| p |
	p := (OSProcess command: 'exec sleep 10') start.
	self assert: p isRunning.
	p terminate.
	p wait.
	self assert: p exitCode equals: 128 + 15
!
testTemporaryFilesAreDeleted
	| p |
	p := OSProcess run: 'echo hi'.
	self deny: (File exists: (p instVarNamed: 'outputPath')).
	self deny: (File exists: (p instVarNamed: 'errorPath'))
! !
