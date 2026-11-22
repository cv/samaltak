TestCase subclass: #MountTableTest
	instanceVariableNames: 'saved volume big'
	classVariableNames: ''
	package: 'Tests-Kernel'!

MountTableTest comment: 'Tests MountTable and VolumeFile, and File, FileStream and Directory over them, with a volume in memory (MountTableTestVolume) mounted at a path the platform does not have; the platform''s mount table (on UEFI FirmwareVolumes''s) is put back afterwards.'!

!MountTableTest methodsFor: 'running'!
setUp
	saved := File mountTable.
	big := ((1 to: 20000) collect: [:i | i * 7 \\ 256]) asByteArray.
	volume := MountTableTestVolume new.
	volume file: '/hello.txt' text: 'Hello, ', (String with: (Character value: 955)), '!!'.
	volume directory: '/docs'.
	volume file: '/docs/big.bin' bytes: big.
	volume directory: '/docs/deep'.
	volume file: '/docs/deep/note.txt' text: 'deep'.
	File mountTable: (MountTable new mount: volume at: self root; yourself)
!
tearDown
	File mountTable: saved
!
root
	^'/samaltak-mount-test'
! !

!MountTableTest methodsFor: 'tests'!
testStatAndEntries
	self assert: (File isDirectory: self root).
	self assert: (Directory entries: self root) = #('docs' 'hello.txt').
	self assert: (Directory entries: self root / 'docs') = #('big.bin' 'deep').
	self assert: (Directory fileNames: self root / 'docs') = #('big.bin').
	self assert: (Directory directoryNames: self root / 'docs') = #('deep').
	self assert: (File isFile: self root / 'hello.txt').
	self assert: (File sizeOf: self root / 'docs/big.bin') = 20000.
	self assert: (File modificationTime: self root / 'hello.txt') = 1700000000000000.
	self deny: (File exists: self root / 'missing').
	self assert: (Directory allFilesUnder: self root / 'docs') = {self root / 'docs/big.bin'. self root / 'docs/deep/note.txt'}
!
testRead
	self assert: (File readText: self root / 'hello.txt') = ('Hello, ', (String with: (Character value: 955)), '!!').
	self assert: (File readBytes: self root / 'docs/big.bin') = big.
	self assert: (File lineCountOf: self root / 'hello.txt') = 0
!
testStreamPositioning
	FileStream readOnlyFileNamed: self root / 'docs/big.bin' do: [:s |
		s binary.
		self assert: s size = 20000.
		s position: 19990.
		self assert: (s next: 100) = (big copyFrom: 19991 to: 20000).
		self assert: s atEnd.
		s position: 8190.
		self assert: (s next: 5) = (big copyFrom: 8191 to: 8195).
		self assert: s position = 8195.
		s skip: -5.
		self assert: s next = (big at: 8191)].
	FileStream readOnlyFileNamed: self root / 'hello.txt' do: [:s |
		self assert: s next = $H.
		self assert: (s upTo: $!!) = ('ello, ', (String with: (Character value: 955)))]
!
testReadsInChunks
	"A FileStream reads a volume in its buffer's chunks, not a byte at a time."
	File readBytes: self root / 'docs/big.bin'.
	self assert: (volume stat: '/docs/big.bin') reads <= 4
!
testDotAndDotDot
	"Resolved by name, before the volume sees the path: .. of the mount point is the directory it is in."
	self assert: (File readText: self root / 'docs/./deep/../deep/note.txt') = 'deep'.
	self assert: (File readText: self root / '../samaltak-mount-test/hello.txt') = (File readText: self root / 'hello.txt').
	self assert: (File mountTableFor: self root / '..') isNil
!
testErrors
	self should: [File readText: self root / 'missing'] raise: FileDoesNotExist.
	self should: [Directory entries: self root / 'missing'] raise: FileDoesNotExist.
	self should: [Directory entries: self root / 'hello.txt'] raise: FileError.
	self should: [File readText: self root / 'docs'] raise: FileError
!
testReadOnly
	| check |
	check := [:block | self should: block raise: FileError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'Read-only file system: ')]].
	check value: [File writeText: 'x' to: self root / 'new.txt'].
	check value: [File writeText: 'x' to: self root / 'hello.txt'].
	check value: [FileStream fileNamed: self root / 'hello.txt'].
	check value: [File delete: self root / 'hello.txt'].
	check value: [File rename: self root / 'hello.txt' to: self root / 'bye.txt'].
	check value: [Directory create: self root / 'new'].
	self assert: (File readText: self root / 'docs/deep/note.txt') = 'deep'
!
testWritableVolume
	"A volume with the writing protocol: written, appended to, overwritten in place, truncated, renamed, deleted; a rename stays on one volume; the read-only volume stays read-only."
	| p |
	p := '/samaltak-mount-rw'.
	File mountTable mount: (MountTableTestWritableVolume new directory: '/d'; yourself) at: p.
	File writeText: 'hello' to: p / 'a.txt'.
	self assert: (File readText: p / 'a.txt') = 'hello'.
	FileStream withStream: (FileStream appendingFileNamed: p / 'a.txt') do: [:s | s nextPutAll: ' world'].
	FileStream fileNamed: p / 'a.txt' do: [:s | s position: 6. s nextPutAll: 'W'].
	self assert: (File readText: p / 'a.txt') = 'hello World'.
	self assert: (File sizeOf: p / 'a.txt') = 11.
	File rename: p / 'a.txt' to: p / 'd/b.txt'.
	self deny: (File exists: p / 'a.txt').
	self assert: (File readText: p / 'd/b.txt') = 'hello World'.
	File writeText: 'x' to: p / 'd/b.txt'.
	self assert: (File readText: p / 'd/b.txt') = 'x'.
	self should: [File rename: p / 'd/b.txt' to: self root / 'b.txt'] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'Cannot move to another volume: ')].
	self should: [File writeText: 'x' to: p / 'missing/c.txt'] raise: FileDoesNotExist.
	self should: [File delete: p / 'd'] raise: FileError.
	Directory create: p / 'e'.
	self should: [Directory create: p / 'e'] raise: FileExists.
	File delete: p / 'd/b.txt'.
	File delete: p / 'd'.
	self assert: (Directory entries: p) = #('e').
	self should: [File writeText: 'x' to: self root / 'new.txt'] raise: FileError
!
testOverlay
	"Only the paths under a mount point are the table's."
	self assert: (File mountTableFor: self root / 'x') notNil.
	self assert: (File mountTableFor: self root) notNil.
	self assert: (File mountTableFor: '/tmp') isNil.
	self assert: (File mountTableFor: '/samaltak-mount-testing') isNil.
	self assert: (File mountTableFor: 'relative/path') isNil.
	self assert: (File mountTableFor: self root / '../tmp') isNil
!
testCoversEverything
	"As on UEFI: every path is the table's, relative ones from /; the directories above mount points list them, with a volume's own entries."
	| t other |
	other := MountTableTestVolume new.
	other file: '/x' text: 'x'.
	t := MountTable new coversEverything: true; yourself.
	self assert: (t stat: '/') = #(true true 0 0).
	self assert: (t entries: '/') = #().
	self assert: (t covers: 'any/relative/path').
	self assert: t currentDirectory = '/'.
	t mount: volume at: '/'.
	t mount: other at: '/mnt/other'.
	t mount: volume at: '/mnt/first'.
	self assert: (t mounts collect: [:m | m key]) = #('/' '/mnt/first' '/mnt/other').
	self assert: (t volumeAt: '/mnt/other') == other.
	self assert: (t entries: '/') = #('docs' 'hello.txt' 'mnt').
	self assert: (t entries: '/mnt') = #('first' 'other').
	self assert: (t entries: '/mnt/other') = #('x').
	self assert: (t stat: '/mnt') = #(true true 0 0).
	self assert: (t stat: 'docs/big.bin') second not.
	self assert: (t stat: '/mnt/first/docs/big.bin') third = 20000.
	self assert: (t stat: '/mnt/other/hello.txt') first not.
	t unmount: '/mnt/other'.
	self assert: (t entries: '/mnt') = #('first')
!
testLoaderRunsOnce
	| t count |
	count := 0.
	t := MountTable new loader: [:table | count := count + 1. table mount: volume at: '/v']; yourself.
	self assert: count = 0.
	self assert: (t covers: '/v/hello.txt').
	self assert: (t entries: '/v/docs') = #('big.bin' 'deep').
	self assert: count = 1
! !
