TestCase subclass: #CrashReportTest
	instanceVariableNames: 'dir'
	classVariableNames: ''
	package: 'Tests-Debugging'!

CrashReportTest comment: 'Tests CrashReport: a report of a caught error written into a directory of its own (samaltak-crash-1.txt, then -2), with the error, the Process, the VM, the heap and the stack; the time''s text.'!

!CrashReportTest methodsFor: 'running'!
setUp
	dir := (File mountTable notNil and: [File mountTable coversEverything])
		ifTrue: ['/esp/samaltak-crash-report-test']
		ifFalse: ['/tmp/samaltak-crash-report-test-', Time utcMicroseconds printString]
!
tearDown
	(File isDirectory: dir) ifTrue: [
		(Directory entries: dir) do: [:n | File delete: (File join: dir with: n)].
		[File delete: dir] on: FileError do: [:e | e return: nil]]
! !

!CrashReportTest methodsFor: 'tests'!
testWrite
	| report path text |
	(File mountTable notNil and: [File mountTable coversEverything and: [(File isDirectory: '/esp') not]]) ifTrue: [^self].
	report := [1 / 0] on: ZeroDivide do: [:e | e return: (CrashReport exception: e context: e signalerContext process: Processor activeProcess)].
	path := report writeIn: dir.
	self assert: (File baseName: path) = 'samaltak-crash-1.txt'.
	self assert: (File baseName: (report writeIn: dir)) = 'samaltak-crash-2.txt'.
	text := File readText: path.
	self assert: (text beginsWith: 'Samaltak error report').
	self assert: (text includesSubstring: 'error: ZeroDivide').
	self assert: (text includesSubstring: 'process: ').
	self assert: (text includesSubstring: 'heap: limit ').
	self assert: (text includesSubstring: 'Smalltalk stack:').
	self assert: (text includesSubstring: 'CrashReportTest>>testWrite')
!
testTimeText
	self assert: (CrashReport timeTextOf: 0) = '1970-01-01 00:00:00'.
	self assert: (CrashReport timeTextOf: 1700000000 * 1000000) = '2023-11-14 22:13:20'.
	self assert: (CrashReport timeTextOf: 951782400 * 1000000) = '2000-02-29 00:00:00'
! !
