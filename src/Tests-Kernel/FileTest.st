TestCase subclass: #FileTest
	instanceVariableNames: 'dir'
	classVariableNames: ''
	package: 'Tests-Kernel'!

FileTest comment: 'Tests File, FileStream and Directory against a scratch directory in /tmp (TestCase>>scratchDirectory).'!

!FileTest methodsFor: 'running'!
setUp
	dir := self scratchDirectory
! !

!FileTest methodsFor: 'tests'!
testWriteReadDelete
	| path |
	path := dir / 'hello.txt'.
	self deny: (File exists: path).
	File writeText: 'Hello, World!!' to: path.
	self assert: (File exists: path).
	self assert: (File isFile: path).
	self assert: (File sizeOf: path) = 13.
	self assert: (File readText: path) = 'Hello, World!!'.
	self assert: (File modificationTime: path) > 0.
	File delete: path.
	self deny: (File exists: path).
	self should: [File readText: path] raise: FileDoesNotExist
!
testBinary
	| path bytes |
	path := dir / 'data.bin'.
	bytes := (0 to: 255) asByteArray , ((1 to: 10000) collect: [:i | i \\ 251]) asByteArray.
	File writeBytes: bytes to: path.
	self assert: (File readBytes: path) = bytes.
	self assert: (File sizeOf: path) = bytes size
!
testUTF8
	| path text |
	path := dir / 'utf8.txt'.
	text := 'héllo ', (String with: (Character value: 955)), ' wörld'.
	File writeText: text to: path.
	self assert: (File readText: path) = text.
	self assert: (File sizeOf: path) = text utf8Encoded size.
	FileStream readOnlyFileNamed: path do: [:s |
		self assert: (s next: 2) = 'hé'.
		self assert: s position = 3]
!
testStreamOperations
	| path |
	path := dir / 'lines.txt'.
	FileStream newFileNamed: path do: [:s |
		s nextPutAll: 'one'; nextPut: Character lf; nextPutAll: 'two'; nextPut: Character lf; print: 3].
	self should: [FileStream newFileNamed: path] raise: FileExists.
	FileStream readOnlyFileNamed: path do: [:s |
		self assert: s size = 9.
		self assert: s nextLine = 'one'.
		self assert: s peek = $t.
		self assert: s nextLine = 'two'.
		self deny: s atEnd.
		self assert: s upToEnd = '3'.
		self assert: s atEnd.
		self assert: s next isNil.
		s position: 4.
		self assert: (s upTo: Character lf) = 'two'].
	FileStream fileNamed: path do: [:s |
		s setToEnd.
		s nextPutAll: 'xyz'.
		s position: 0.
		s nextPutAll: 'ONE'].
	self assert: (File readText: path) = ('ONE', (String with: Character lf), 'two', (String with: Character lf), '3xyz').
	(FileStream appendingFileNamed: path) nextPutAll: '!!'; close.
	self assert: ((FileStream readOnlyFileNamed: path) contentsAndClose endsWith: 'xyz!!')
!
testRenameAndDirectories
	| a b sub |
	a := dir / 'a.txt'.
	b := dir / 'b.txt'.
	File writeText: 'x' to: a.
	File rename: a to: b.
	self deny: (File exists: a).
	self assert: (File readText: b) = 'x'.
	sub := dir / 'sub'.
	Directory create: sub.
	self assert: (Directory exists: sub).
	self assert: (File isDirectory: sub).
	self assert: (Directory entries: dir) = #('b.txt' 'sub').
	self assert: (Directory fileNames: dir) = #('b.txt').
	self assert: (Directory directoryNames: dir) = #('sub').
	self assert: Directory current notEmpty.
	self should: [Directory entries: dir / 'missing'] raise: FileError
!
testPaths
	self assert: 'a' / 'b' = 'a/b'.
	self assert: 'a/' / 'b' = 'a/b'.
	self assert: (File baseName: '/x/y/z.st') = 'z.st'.
	self assert: (File directoryOf: '/x/y/z.st') = '/x/y'.
	self assert: (File extensionOf: 'z.tar.gz') = 'gz'.
	self assert: (File extensionOf: 'Makefile') = ''
!
testClosedStream
	| s |
	s := FileStream forceNewFileNamed: dir / 'c.txt'.
	s close.
	self assert: s isClosed.
	self should: [s nextPutAll: 'x'] raise: FileError
! !
