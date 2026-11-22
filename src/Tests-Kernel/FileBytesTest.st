TestCase subclass: #FileBytesTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

FileBytesTest comment: 'Tests for FileBytes: it reads as the ByteArray of the file does, reads only the pages touched, and notices a changed file.'!

!FileBytesTest methodsFor: 'tests'!
testReadsLikeTheFilesBytes
	| path bytes paged |
	path := self scratchDirectory / 'data.bin'.
	bytes := ByteArray new: 10000.
	1 to: bytes size do: [:i | bytes at: i put: i * 7 \\ 256].
	(FileStream newFileNamed: path) binary; nextPutAll: bytes; close.
	paged := FileBytes on: path.
	self assert: paged size equals: 10000.
	self assert: paged residentSize equals: 0.
	self assert: (paged at: 1) equals: (bytes at: 1).
	self assert: (paged at: 4097) equals: (bytes at: 4097).
	self assert: (paged at: 10000) equals: (bytes at: 10000).
	self assert: (paged uint16BigEndianAt: 4096) equals: (bytes uint16BigEndianAt: 4096).
	self assert: (paged int16BigEndianAt: 200) equals: (bytes int16BigEndianAt: 200).
	self assert: (paged uint32BigEndianAt: 8190) equals: (bytes uint32BigEndianAt: 8190).
	self assert: (paged copyFrom: 4000 to: 4200) equals: (bytes copyFrom: 4000 to: 4200).
	self assert: paged residentSize equals: 10000.
	self assert: paged contents equals: bytes.
	self should: [paged at: 10001] raise: Error
!
testReadsOnlyThePagesTouched
	| path paged |
	path := self scratchDirectory / 'big.bin'.
	(FileStream newFileNamed: path) binary; nextPutAll: (ByteArray new: 100000); close.
	paged := FileBytes on: path.
	paged at: 50000.
	self assert: paged residentSize equals: 4096
!
testNoticesAChangedFile
	| path paged |
	path := self scratchDirectory / 'changing.bin'.
	(FileStream newFileNamed: path) binary; nextPutAll: (ByteArray new: 10); close.
	paged := FileBytes on: path.
	(Delay forMilliseconds: 20) wait.
	(FileStream forceNewFileNamed: path) binary; nextPutAll: (ByteArray new: 20); close.
	self should: [paged at: 1] raise: Error
! !
