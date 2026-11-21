TestCase subclass: #Ext4MountTest
	instanceVariableNames: 'saved volume'
	classVariableNames: ''
	package: 'Tests-Storage'!

Ext4MountTest comment: 'Tests File, FileStream and Directory over an Ext4Volume mounted in a MountTable (as FirmwareVolumes mounts them on UEFI), on the ext4 image with 4 KiB blocks of Ext4VolumeTest''s fixtures (tests/storage/ext4_fixtures.sh): every directory lists and every file reads (a large one its ends) as the tree it was made of does on the host (the FIFO left out), through symbolic links too (an absolute one from the volume''s root); FileStream seeks; writes fail.'!

!Ext4MountTest methodsFor: 'running'!
fixtureDirectory
	^(File directoryOf: Smalltalk vm imagePath) / 'ext4-fixtures'
!
mountPoint
	^'/samaltak-ext4-mount-test'
!
setUp
	| run |
	saved := File mountTable.
	run := OSProcess run: (OSProcess commandFor: {'tests/storage/ext4_fixtures.sh'. self fixtureDirectory}).
	run succeeded ifFalse: [^self fail: 'tests/storage/ext4_fixtures.sh failed (exit ', run exitCode printString, '): ', run errorOutput].
	volume := Ext4Volume onFile: self fixtureDirectory / 'ext4-4k.img'.
	File mountTable: (MountTable new mount: volume at: self mountPoint; yourself)
!
tearDown
	File mountTable: saved.
	volume isNil ifFalse: [volume close]
! !

!Ext4MountTest methodsFor: 'helpers'!
compare: aRelativePath
	"The mounted aRelativePath against the tree's, and below it if it is a directory."
	| host mounted hostStat names |
	host := self fixtureDirectory / 'tree' / aRelativePath.
	mounted := self mountPoint / aRelativePath.
	hostStat := File stat: host.
	self assert: ((File stat: mounted) first: 2) equals: (hostStat first: 2).
	hostStat first ifFalse: [^self].
	hostStat second ifFalse: [
		self assert: (File sizeOf: mounted) equals: hostStat third.
		^self assert: (self sample: mounted) = (self sample: host) description: aRelativePath].
	names := Directory entries: host.
	aRelativePath isEmpty ifTrue: [names := (names copyWith: 'lost+found') asSortedCollection asArray].
	self assert: (Directory entries: mounted) equals: names.
	(names reject: [:n | n = 'special' or: [n = 'lost+found']]) do: [:n | | path |
		path := aRelativePath isEmpty ifTrue: [n] ifFalse: [aRelativePath / n].
		"An absolute link is from the volume's root, on the host from /: testSymbolicLinks."
		path = 'links/absolute' ifFalse: [self compare: path]]
! !

!Ext4MountTest methodsFor: 'helpers'!
sample: aPath
	"The file's bytes; of one over 2 MB (the tree has sparse files of GBs) its first and last 64 KB."
	^FileStream readOnlyFileNamed: aPath do: [:s |
		s binary.
		s size <= 2097152
			ifTrue: [s upToEnd]
			ifFalse: [(s next: 65536), (s position: s size - 65536; next: 65536)]]
! !

!Ext4MountTest methodsFor: 'tests'!
testTreeReadsAsOnTheHost
	self compare: ''
!
testSymbolicLinks
	self assert: (File readText: self mountPoint / 'links/fast') equals: 'Hello, ext4!!', (String with: Character lf).
	self assert: (File readText: self mountPoint / 'links/absolute') equals: (File readText: self mountPoint / 'hello.txt').
	self assert: (File readText: self mountPoint / 'links/chain') equals: (File readText: self mountPoint / 'hello.txt').
	self assert: (File isDirectory: self mountPoint / 'links/dirlink').
	self assert: (Directory entries: self mountPoint / 'links/dirlink') equals: (Directory entries: self mountPoint / 'dir').
	self deny: (File exists: self mountPoint / 'links/dangling').
	self deny: (File exists: self mountPoint / 'links/loop1').
	self should: [File readText: self mountPoint / 'links/loop1'] raise: FileError
!
testSeeking
	| host |
	host := File readBytes: self fixtureDirectory / 'tree/sizes/1000000'.
	FileStream readOnlyFileNamed: self mountPoint / 'sizes/1000000' do: [:s |
		s binary.
		#(0 4095 4096 8191 8192 524287 999990 1000000) do: [:position |
			s position: position.
			self assert: (s next: 20) equals: (host copyFrom: position + 1 to: (position + 20 min: host size))].
		self assert: s atEnd]
!
testReadOnly
	self should: [File writeText: 'x' to: self mountPoint / 'hello.txt'] raise: FileError.
	self should: [Directory create: self mountPoint / 'new'] raise: FileError.
	self should: [File delete: self mountPoint / 'hello.txt'] raise: FileError.
	self assert: (File exists: self mountPoint / 'hello.txt')
! !
