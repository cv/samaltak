TestCase subclass: #Ext4VolumeTest
	instanceVariableNames: 'volumes'
	classVariableNames: ''
	package: 'Tests-Storage'!

Ext4VolumeTest comment: 'Tests Ext4Volume on images that e2fsprogs makes of a tree of files (tests/storage/ext4_fixtures.sh, into ext4-fixtures beside the image; a missing e2fsprogs fails every test with the script''s message): in every variant (1, 2, 4 and 64 KiB blocks, ext2 and ext3 block maps, 32- and 64-bit, with and without metadata_csum, 128-byte inodes, inline data, meta_bg) every file''s type, permissions, owner, links, size, time, bytes and link target and every directory''s names against what the host sees (manifest.txt and the tree); then times, links, sparse files, htree, and damaged or unsupported file systems (PatchedBlockDevice).'!

!Ext4VolumeTest methodsFor: 'accessing'!
timeLimitMilliseconds
	^180000
!
fixtureDirectory
	^(File directoryOf: Smalltalk vm imagePath) / 'ext4-fixtures'
!
variants
	"Answer the variants' names, from variants.txt."
	^(File readText: self fixtureDirectory / 'variants.txt') lines collect: [:line | (line substrings: ' ') first]
!
volume: aVariant
	| volume |
	volume := Ext4Volume onFile: self fixtureDirectory / (aVariant, '.img').
	volumes add: volume.
	^volume
!
treePath: aPath
	^self fixtureDirectory / 'tree' / aPath
!
manifest
	"Answer the manifest's entries: {path. type. mode. uid. gid. size. links. mtime. link target}."
	^((File readText: self fixtureDirectory / 'manifest.txt') lines reject: [:line | line isEmpty])
		collect: [:line | (line splitOn: (String with: Character tab)) asArray]
! !

!Ext4VolumeTest methodsFor: 'running'!
setUp
	| run |
	volumes := OrderedCollection new.
	run := OSProcess run: (OSProcess commandFor: {'tests/storage/ext4_fixtures.sh'. self fixtureDirectory}).
	run succeeded ifFalse: [self fail: 'tests/storage/ext4_fixtures.sh failed (exit ', run exitCode printString, '): ', run errorOutput]
!
tearDown
	volumes do: [:each | each close]
! !

!Ext4VolumeTest methodsFor: 'tests - variants'!
testExt4With4KiBBlocks
	self checkVariant: 'ext4-4k'
!
testExt4With1KiBBlocks
	self checkVariant: 'ext4-1k'
!
testExt4With64KiBBlocks
	self checkVariant: 'ext4-64k'
!
testExt4Without64bitWithGdtCsum
	self checkVariant: 'ext4-32bit'
!
testExt4WithSmallInodes
	self checkVariant: 'ext4-small-inodes'
!
testExt4WithInlineData
	self checkVariant: 'ext4-inline'
!
testExt4WithMetaBg
	self checkVariant: 'ext4-metabg'
!
testExt3
	self checkVariant: 'ext3-4k'
!
testExt2
	self checkVariant: 'ext2-1k'
!
testExt2WithoutFileTypes
	self checkVariant: 'ext2-2k-nofiletype'
!
testEveryVariantIsTested
	self assert: self variants asSortedCollection asArray
		equals: #('ext2-1k' 'ext2-2k-nofiletype' 'ext3-4k' 'ext4-1k' 'ext4-32bit' 'ext4-4k' 'ext4-64k' 'ext4-inline' 'ext4-metabg' 'ext4-small-inodes')
! !

!Ext4VolumeTest methodsFor: 'tests'!
testSuperblock
	| volume |
	volume := self volume: 'ext4-4k'.
	self assert: volume label equals: 'fixture-ext4-4k'.
	self assert: volume uuid equals: '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0'.
	self assert: volume blockSize equals: 4096.
	self assert: volume blockCount equals: 96 * 1024 // 4.
	self assert: volume inodeSize equals: 256.
	self assert: volume descriptorSize equals: 64.
	self assert: volume warnings isEmpty.
	#('has_journal' 'extent' '64bit' 'flex_bg' 'metadata_csum' 'huge_file' 'dir_nlink' 'extra_isize' 'dir_index' 'filetype' 'sparse_super' 'large_file')
		do: [:each | self assert: (volume hasFeature: each) description: each].
	self deny: (volume hasFeature: 'inline_data').
	volume := self volume: 'ext2-2k-nofiletype'.
	self assert: volume blockSize equals: 2048.
	self assert: volume inodeSize equals: 128.
	self assert: volume descriptorSize equals: 32.
	self deny: volume hasFileTypes.
	self assert: ((volume directoryEntriesAt: '/') allSatisfy: [:each | each fileType isNil])
!
testTimes
	"debugfs set /times/nanos to 2021-03-04 05:06:07.123456789 (crtime nanoseconds 1) and /times/future 16r10 seconds with epoch bits 1: 2106; without extra fields only the seconds remain."
	#('ext4-4k' 'ext4-1k' 'ext4-inline' 'ext3-4k' 'ext4-64k') do: [:variant | | volume nanos future |
		volume := self volume: variant.
		nanos := volume stat: '/times/nanos'.
		self assert: nanos mtime equals: 16r6040DB3F.
		self assert: nanos mtimeNanoseconds equals: 123456789.
		self assert: nanos modificationTime equals: 16r6040DB3F * 1000000 + 123456.
		self assert: nanos crtimeNanoseconds equals: 1.
		self assert: nanos crtime notNil.
		future := volume stat: '/times/future'.
		self assert: future mtime equals: 16r100000010.
		self assert: future mtimeNanoseconds equals: 0].
	#('ext4-small-inodes' 'ext2-1k') do: [:variant | | inode |
		inode := (self volume: variant) stat: '/hello.txt'.
		self assert: inode crtime isNil.
		self assert: inode mtimeNanoseconds equals: 0.
		self assert: inode mtime equals: 981201906]
!
testOwnerAbove65535
	self variants do: [:variant | | inode |
		inode := (self volume: variant) stat: '/owner/high-uid'.
		self assert: inode uid equals: 100000.
		self assert: inode gid equals: 70000]
!
testSymbolicLinks
	self variants do: [:variant | | volume |
		volume := self volume: variant.
		self assert: (volume lstat: '/links/fast') isFastSymlink.
		self deny: (volume lstat: '/links/slow') isFastSymlink.
		self assert: (volume contentsOf: '/links/fast') asString equals: 'Hello, ext4!!', (String with: Character lf).
		self assert: (volume contentsOf: '/links/slow') asString equals: 'at the end of a slow link', (String with: Character lf).
		self assert: (volume contentsOf: '/links/chain') equals: (volume contentsOf: '/hello.txt').
		self assert: (volume contentsOf: '/links/absolute') equals: (volume contentsOf: '/hello.txt').
		self assert: (volume contentsOf: '/links/dirlink/sub/deeper/file.txt') asString equals: 'deep', (String with: Character lf).
		self assert: (volume stat: '/links/through') number equals: (volume stat: '/dir/sub/deeper') number.
		self assert: (volume entriesAt: '/links/dirlink') equals: (volume entriesAt: '/dir').
		self assert: (volume stat: '/links/chain') isRegularFile.
		self assert: (volume lstat: '/links/chain') isSymlink.
		self assert: (volume readLink: '/links/chain') equals: 'fast'.
		self should: [volume readLink: '/hello.txt'] raise: FileError.
		self should: [volume stat: '/links/dangling'] raise: FileDoesNotExist.
		self assert: (volume lstat: '/links/dangling') isSymlink.
		#('/links/loop1' '/links/self' '/links/loop2/x') do: [:path |
			self should: [volume stat: path] raise: FileError withExceptionDo: [:e |
				self assert: (e messageText includesSubstring: 'Too many levels of symbolic links').
				self assert: e path equals: path]].
		self assert: (volume lstat: '/links/loop1') isSymlink]
!
testPathResolution
	| volume deep |
	volume := self volume: 'ext4-4k'.
	deep := (volume stat: '/dir/sub/deeper/file.txt') number.
	#('dir/sub/deeper/file.txt' '//dir///sub/deeper/file.txt' '/dir/./sub/../sub/deeper/./file.txt' '/../../dir/sub/deeper/file.txt' '/dir/a/../b/../sub/deeper/file.txt')
		do: [:path | self assert: (volume stat: path) number equals: deep].
	#('/' '' '.' '..' '/..' '/dir/..') do: [:path | self assert: (volume stat: path) number equals: 2].
	self should: [volume stat: '/nope'] raise: FileDoesNotExist withExceptionDo: [:e |
		self assert: e path equals: '/nope'.
		self assert: e messageText equals: 'No such file: /nope'].
	self should: [volume stat: '/dir/nope/file.txt'] raise: FileDoesNotExist.
	self should: [volume stat: '/hello.txt/x'] raise: FileError withExceptionDo: [:e |
		self deny: (e isKindOf: FileDoesNotExist).
		self assert: (e messageText beginsWith: 'Not a directory')].
	self should: [volume read: '/dir' from: 0 count: 10] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'Is a directory')].
	self should: [volume entriesAt: '/hello.txt'] raise: FileError.
	self should: [volume read: '/special/fifo' from: 0 count: 10] raise: FileError.
	self assert: (volume stat: '/special/fifo') fileType equals: #fifo.
	self assert: (volume exists: '/dir/sub').
	self assert: (volume isDirectory: '/dir/sub').
	self deny: (volume isFile: '/dir/sub').
	self assert: (volume isFile: '/links/fast').
	self deny: (volume exists: '/links/dangling').
	self deny: (volume exists: '/links/loop1').
	self assert: (volume entriesAt: '/emptydir') isEmpty.
	self assert: (volume contentsOf: '/empty') isEmpty
!
testReadAtOffsets
	| volume host size |
	host := File readBytes: (self treePath: 'sizes/1000000').
	self variants do: [:variant |
		volume := self volume: variant.
		size := host size.
		#(0 1 511 512 1023 1024 1025 4095 4096 4097 65535 65536 65537 999999 1000000 1000001 5000000) do: [:offset |
			#(0 1 2 1000 4096 70000 2000000) do: [:count | | expected |
				expected := offset >= size
					ifTrue: [ByteArray new]
					ifFalse: [host copyFrom: offset + 1 to: (offset + count min: size)].
				self assert: (volume read: '/sizes/1000000' from: offset count: count) = expected
					description: variant, ' at ', offset printString, ' count ', count printString]]]
!
testSparseFiles
	self variants do: [:variant | | volume huge runs prealloc |
		volume := self volume: variant.
		huge := volume stat: '/huge'.
		self assert: huge size equals: 5 * 1073741824.
		self assert: (huge readFrom: 0 count: 4) asString equals: 'head'.
		self assert: (huge readFrom: 4294967296 - 3 count: 12) asString equals: 'across 4 GiB'.
		self assert: (huge readFrom: 4294967296 - 4 count: 14) equals: #[0], 'across 4 GiB' asByteArray, #[0].
		self assert: (huge readFrom: 5 * 1073741824 - 9 count: 100) asString equals: 'the end!!!!'.
		self assert: (huge readFrom: 2147483648 count: 100000) equals: (ByteArray new: 100000).
		runs := huge runsFrom: 0 count: 5 * 1073741824 // volume blockSize.
		self assert: (runs count: [:each | (each at: 2) notNil]) <= 4.
		self assert: huge blocks < 1000.
		prealloc := volume stat: '/prealloc'.
		self assert: (prealloc readFrom: 4096 count: 61440 - 4096) equals: (ByteArray new: 61440 - 4096).
		(prealloc usesExtents and: [volume blockSize <= 4096]) ifTrue: [
			self assert: ((prealloc runsFrom: 0 count: 65536 // volume blockSize) collect: [:each | (each at: 2) isNil]) asArray
				equals: #(false true false)]]
!
testExtentTreeDepth
	| depth |
	depth := [:variant | ((self volume: variant) stat: '/fragmented') bytes uint16At: 16r28 + 6 + 1].
	self assert: (depth value: 'ext4-4k') equals: 1.
	self assert: (depth value: 'ext4-1k') equals: 2
!
testHashIndexedDirectory
	self variants do: [:variant | | volume many names |
		volume := self volume: variant.
		many := volume stat: '/many'.
		self assert: many isHashIndexed equals: (volume hasFeature: 'dir_index').
		names := volume entriesAt: '/many'.
		self assert: names size equals: 2000.
		self assert: names equals: (Directory entries: (self treePath: 'many')).
		names do: [:each | self assert: (volume stat: '/many/', each) isRegularFile].
		self assert: (volume contentsOf: '/many/entry-0010') asString equals: 'entry 10', (String with: Character lf)]
!
testHardLinks
	self variants do: [:variant | | volume one |
		volume := self volume: variant.
		one := volume stat: '/hard/one'.
		self assert: one nlink equals: 3.
		self assert: (volume stat: '/hard/two') number equals: one number.
		self assert: (volume stat: '/dir/three') number equals: one number]
!
testUnicodeNames
	| volume |
	volume := self volume: 'ext4-4k'.
	self assert: (volume entriesAt: '/unicode') equals: (Directory entries: (self treePath: 'unicode')).
	self assert: ((volume entriesAt: '/unicode') includes: 'h', (String with: (Character value: 16rE9)), 'llo w', (String with: (Character value: 16rF6)), 'rld.txt').
	self assert: (volume contentsOf: '/unicode/emoji-', (String with: (Character value: 16r1F600))) asString equals: 'smile', (String with: Character lf).
	self assert: (volume isDirectory: '/unicode/', (String withAll: ((#(16r395 16r3BB 16r3BB 16r3B7 16r3BD 16r3B9 16r3BA 16r3AC) collect: [:each | Character value: each]))))
!
testDirectoryEntries
	| volume entries |
	volume := self volume: 'ext4-4k'.
	entries := volume directoryEntriesAt: '/links'.
	self assert: (entries detect: [:each | each name = 'fast']) fileType equals: #symlink.
	entries := volume directoryEntriesAt: '/'.
	self assert: (entries detect: [:each | each name = 'dir']) fileType equals: #directory.
	self assert: (entries detect: [:each | each name = 'dir']) isDirectory.
	self assert: (entries detect: [:each | each name = 'hello.txt']) fileType equals: #file.
	self assert: (entries detect: [:each | each name = 'hello.txt']) inodeNumber equals: (volume stat: '/hello.txt') number.
	self deny: (entries anySatisfy: [:each | each isDotOrDotDot]).
	self assert: (volume stat: '/many-dirs') nlink equals: 12
! !

!Ext4VolumeTest methodsFor: 'tests - refused and damaged'!
testNotExt4
	| device |
	device := FileBlockDevice on: (self treePath: 'large.bin').
	[self should: [Ext4Volume on: device] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'bad magic number')]] ensure: [device close]
!
testUnsupportedFeatures
	#(#(16r1 'compression') #(16r8 'journal_dev') #(16r1000 'dirdata') #(16r80000000 'unknown incompatible features 16r80000000')) do: [:bitAndName | | device |
		device := self patched: 'ext4-32bit'.
		device at: 1024 + 16r60 putUint32: ((device uint32At: 1024 + 16r60) bitOr: bitAndName first).
		self should: [Ext4Volume on: device] raise: FileError withExceptionDo: [:e |
			self assert: (e messageText includesSubstring: 'unsupported features: ', bitAndName last) description: e messageText]].
	self should: [Ext4Volume on: ((self patched: 'ext4-32bit') at: 1024 + 16r18 putUint32: 7; yourself)] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'blocks of 2^17 bytes')].
	self should: [Ext4Volume on: ((self patched: 'ext4-32bit') at: 1024 + 16r4C putUint32: 2; yourself)] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'revision 2')]
!
testJournalNeedsRecovery
	| device volume |
	device := self patched: 'ext4-32bit'.
	device at: 1024 + 16r60 putUint32: ((device uint32At: 1024 + 16r60) bitOr: 4).
	volume := Ext4Volume on: device.
	self assert: volume warnings size equals: 1.
	self assert: (volume warnings first includesSubstring: 'journal needs recovery').
	self assert: (volume contentsOf: '/hello.txt') asString equals: 'Hello, ext4!!', (String with: Character lf)
!
testSuperblockChecksum
	| device |
	device := self patched: 'ext4-4k'.
	device at: 1024 + 16r78 put: $X value.
	self should: [Ext4Volume on: device] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'checksum')].
	self assert: (Crc32c checksumOf: '123456789' asByteArray) equals: 16rE3069283.
	self assert: (Crc32c checksumOf: (ByteArray new: 32)) equals: 16r8A9136AA
!
testEncryptedFile
	| device volume number |
	volume := self volume: 'ext4-32bit'.
	number := (volume stat: '/hello.txt') number.
	device := self patched: 'ext4-32bit'.
	device at: (volume byteOffsetOfInode: number) + 16r20 putUint32: ((volume stat: '/hello.txt') flags bitOr: 16r800).
	volume := Ext4Volume on: device.
	volumes add: volume.
	self assert: (volume stat: '/hello.txt') isEncrypted.
	self should: [volume contentsOf: '/hello.txt'] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'Encrypted')]
!
testCorruptExtentHeader
	| device volume number |
	device := self patched: 'ext4-32bit'.
	volume := self volume: 'ext4-32bit'.
	number := (volume stat: '/large.bin') number.
	device at: (volume byteOffsetOfInode: number) + 16r28 put: 0.
	volume := Ext4Volume on: device.
	volumes add: volume.
	self should: [volume read: '/large.bin' from: 0 count: 10] raise: FileError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'bad extent header')]
! !

!Ext4VolumeTest methodsFor: 'tests - block devices'!
testFileBlockDevice
	| device host |
	host := File readBytes: (self treePath: 'sizes/1000000').
	device := FileBlockDevice on: (self treePath: 'sizes/1000000').
	[self assert: device blockSize equals: 512.
	 self assert: device blockCount equals: 1000000 // 512.
	 self assert: (device read: 3 blocksAt: 7) equals: (host copyFrom: 7 * 512 + 1 to: 10 * 512).
	 #(#(0 1) #(1 511) #(511 2) #(100 5000) #(512 512) #(999 100000) #(0 999936)) do: [:each |
		self assert: (device readBytes: each last at: each first) equals: (host copyFrom: each first + 1 to: each first + each last)].
	 self should: [device read: 1 blocksAt: 1000000 // 512] raise: FileError.
	 self should: [device readBytes: 2 at: 999935] raise: FileError.
	 self assert: device isReadOnly]
		ensure: [device close].
	self should: [device read: 1 blocksAt: 0] raise: FileError.
	self should: [FileBlockDevice on: (self treePath: 'no such image')] raise: FileDoesNotExist.
	device := FileBlockDevice on: (self treePath: 'sizes/1000000') blockSize: 4096.
	[self assert: device blockCount equals: 244.
	 self assert: (device readBytes: 10 at: 4090) equals: (host copyFrom: 4091 to: 4100)] ensure: [device close]
! !

!Ext4VolumeTest methodsFor: 'private'!
patched: aVariant
	| device |
	device := PatchedBlockDevice on: (FileBlockDevice on: self fixtureDirectory / (aVariant, '.img')).
	volumes add: device.
	^device
!
checkVariant: aVariant
	"Compare everything in the image aVariant with the tree it was made of."
	| volume |
	volume := self volume: aVariant.
	self assert: (volume entriesAt: '/') equals: ((Directory entries: self fixtureDirectory / 'tree') copyWith: 'lost+found') asSortedCollection asArray.
	self manifest do: [:entry | self check: entry on: volume variant: aVariant]
!
check: entry on: volume variant: aVariant
	| path inode type what |
	path := '/', (entry at: 1).
	what := [:field | aVariant, ' ', path, ': ', field].
	inode := volume lstat: path.
	type := (entry at: 2) = 'f' ifTrue: [#file] ifFalse: [
		(entry at: 2) = 'd' ifTrue: [#directory] ifFalse: [
			(entry at: 2) = 'l' ifTrue: [#symlink] ifFalse: [
				(entry at: 2) = 'p' ifTrue: [#fifo] ifFalse: [#unknown]]]].
	self assert: inode fileType = type description: (what value: 'type').
	self assert: inode permissions = (Integer readFrom: (entry at: 3) base: 8) description: (what value: 'mode').
	(path beginsWith: '/owner/') ifFalse: [
		self assert: inode uid = (entry at: 4) asInteger description: (what value: 'uid').
		self assert: inode gid = (entry at: 5) asInteger description: (what value: 'gid')].
	self assert: inode nlink = (entry at: 7) asInteger description: (what value: 'links').
	(path beginsWith: '/times/') ifFalse: [
		self assert: inode mtime = ((entry at: 8) copyUpTo: $.) asInteger description: (what value: 'mtime').
		self assert: inode mtimeNanoseconds = 0 description: (what value: 'mtime nanoseconds')].
	type = #directory ifTrue: [
		self assert: (volume entriesAt: path) = (Directory entries: (self treePath: (entry at: 1))) description: (what value: 'entries')].
	type = #symlink ifTrue: [
		self assert: inode size = (entry at: 6) asInteger description: (what value: 'size').
		self assert: (volume readLink: path) = (entry at: 9) description: (what value: 'link target')].
	type = #file ifTrue: [
		self assert: inode size = (entry at: 6) asInteger description: (what value: 'size').
		self checkContentsOf: path size: inode size on: volume description: (what value: 'contents')]
!
checkContentsOf: path size: size on: volume description: aString
	"Small files whole; up to 32 MB in pieces of an odd size; bigger ones (the 5 GiB sparse file) at their edges and their data."
	| hostPath |
	hostPath := self treePath: (path copyFrom: 2 to: path size).
	size <= 100000 ifTrue: [^self assert: (volume contentsOf: path) = (File readBytes: hostPath) description: aString].
	FileStream readOnlyFileNamed: hostPath do: [:stream | | offsets |
		stream binary.
		offsets := size <= 33554432
			ifTrue: [(0 to: size - 1 by: 1000003) asArray]
			ifFalse: [{0. 1073741824. 4294967296 - 500000. size - 500000}].
		offsets do: [:offset |
			stream position: offset.
			self assert: (volume read: path from: offset count: 1000003) = (stream next: 1000003) description: aString, ' at ', offset printString]]
! !
