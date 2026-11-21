Object subclass: #Ext4Volume
	instanceVariableNames: 'device superblock blockSize blocksCount inodesCount inodesPerGroup blocksPerGroup firstDataBlock groupCount inodeSize descriptorSize compat incompat roCompat inodeTables blockCache blockCacheOrder blockCacheLimit inodeCache directoryCache warnings'
	classVariableNames: ''
	package: 'System-Storage'!

Ext4Volume comment: 'I read an ext2, ext3 or ext4 file system on a BlockDevice whose offset 0 is the start of the file system (docs/storage.md). Read-only.

	volume := Ext4Volume on: (FileBlockDevice on: ''disk.img'').     "or Ext4Volume onFile: ''disk.img''"
	volume label. volume uuid. volume features. volume warnings.
	volume stat: ''/etc/passwd''          an Ext4Inode: mode, permissions, fileType, isDirectory, isRegularFile, isSymlink, size, uid, gid, nlink, atime/mtime/ctime/crtime (seconds) and their Nanoseconds, modificationTime (UTC µs, as File''s)
	volume lstat: path                   the same, not following a symbolic link at the end
	volume exists: path. volume isDirectory: path. volume isFile: path.
	volume entriesAt: ''/etc''             the names, sorted, without . and ..
	volume directoryEntriesAt: ''/etc''    Ext4DirectoryEntry objects (name, inodeNumber, fileType) in their order on disk, without . and ..
	volume read: path from: offset count: n      a ByteArray: at most n bytes from offset (fewer at the end of the file)
	volume contentsOf: path
	volume readLink: path                 the target of a symbolic link, a String

An Ext4Inode reads by itself too (readFrom:count:, contents, linkTarget, directoryEntries), so a reader can resolve a path once. Paths are Strings, UTF-8 on disk, absolute or relative to the root; . and .. and symbolic links resolve as the kernel does (at most 40 links a lookup). A missing file signals FileDoesNotExist, everything else FileError (System-Files), as the hosted File does; so does mounting what I cannot read.

Supported: revisions 0 and 1, blocks of 1 to 64 KiB, 32- and 64-byte group descriptors (64bit), meta_bg, flex_bg, sparse_super and sparse_super2, 128- to block-size inodes with their extra fields (nanosecond and post-2038 times), extent trees of any depth with uninitialized extents (zeros), ext2/3 direct and indirect blocks up to triple, holes (zeros), large and huge files, linear and hash-indexed directories (an htree is read as its leaf blocks), with and without file types, inline data, fast and slow symbolic links. metadata_csum: the superblock''s checksum is verified, the rest is not. A journal that needs recovery, or a file system with errors, mounts with a warning (warnings, and the Transcript): what the journal holds is not replayed. Refused at mount: compression, dirdata, an external journal device, unknown incompatible features; refused per file: encrypted files and directories. Lookups in a casefolded directory try the exact name, then compare lowercased names.

The group descriptors'' inode tables, the last metadata blocks read (inodes, directories, extent and indirect blocks: 4 MB), inodes and directories'' name tables are cached; file data are not: a read maps the blocks it needs to runs and reads each contiguous run in one device call straight into the result.'!

!Ext4Volume methodsFor: 'accessing'!
device
	^device
!
blockSize
	^blockSize
!
blockCount
	^blocksCount
!
inodeCount
	^inodesCount
!
inodeSize
	^inodeSize
!
groupCount
	^groupCount
!
descriptorSize
	^descriptorSize
!
superblock
	"Answer the superblock's 1024 bytes."
	^superblock
!
warnings
	"Answer what I found wrong but could read anyway (Strings)."
	^warnings asArray
!
label
	"Answer the volume name (s_volume_name)."
	| bytes end |
	bytes := superblock copyFrom: 16r78 + 1 to: 16r78 + 16.
	end := bytes indexOf: 0.
	end = 0 ifTrue: [end := bytes size + 1].
	^(bytes copyFrom: 1 to: end - 1) utf8Decoded
!
uuid
	"Answer the file system's UUID as a String, e.g. '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0'."
	| hex |
	hex := '0123456789abcdef'.
	^String new: 36 streamContents: [:s |
		1 to: 16 do: [:i | | b |
			(#(5 7 9 11) includes: i) ifTrue: [s nextPut: $-].
			b := superblock at: 16r68 + i.
			s nextPut: (hex at: b // 16 + 1); nextPut: (hex at: b \\ 16 + 1)]]
!
features
	"Answer the names of the features the file system has, as mke2fs -O names them (has_journal, extent, 64bit, ...)."
	| names |
	names := OrderedCollection new.
	{compat -> self class compatibleFeatures. incompat -> self class incompatibleFeatures. roCompat -> self class readOnlyCompatibleFeatures}
		do: [:flagsAndNames |
			flagsAndNames value do: [:bitAndName |
				(flagsAndNames key bitAnd: bitAndName first) ~= 0 ifTrue: [names add: bitAndName last]]].
	^names asArray
!
hasFeature: aName
	^self features includes: aName
!
hasFileTypes
	"Whether directory entries carry their file's type (filetype)."
	^(incompat bitAnd: 16r2) ~= 0
!
hasHugeFiles
	^(roCompat bitAnd: 16r8) ~= 0
! !

!Ext4Volume methodsFor: 'files'!
stat: aPath
	"Answer the Ext4Inode of aPath, following symbolic links."
	^self resolve: aPath followLast: true
!
lstat: aPath
	"Answer the Ext4Inode of aPath; a symbolic link at its end is not followed."
	^self resolve: aPath followLast: false
!
exists: aPath
	^[self stat: aPath. true] on: FileError do: [:e | e return: false]
!
isDirectory: aPath
	^[(self stat: aPath) isDirectory] on: FileError do: [:e | e return: false]
!
isFile: aPath
	^[(self stat: aPath) isRegularFile] on: FileError do: [:e | e return: false]
!
entriesAt: aPath
	"Answer the names in the directory aPath (without . and ..), sorted."
	^((self directoryEntriesAt: aPath) collect: [:each | each name]) asSortedCollection asArray
!
directoryEntriesAt: aPath
	"Answer the Ext4DirectoryEntry objects of the directory aPath (without . and ..), in their order on disk."
	| inode |
	inode := self stat: aPath.
	inode isDirectory ifFalse: [^FileError signal: 'Not a directory: ', aPath path: aPath].
	self checkReadable: inode path: aPath.
	^(inode directoryEntries reject: [:each | each isDotOrDotDot]) asArray
!
read: aPath from: offset count: anInteger
	"Answer a ByteArray with at most anInteger bytes of the file aPath from offset (0-based) on: fewer at its end, none past it."
	| inode |
	inode := self stat: aPath.
	inode isDirectory ifTrue: [^FileError signal: 'Is a directory: ', aPath path: aPath].
	inode isRegularFile ifFalse: [^FileError signal: 'Not a regular file: ', aPath path: aPath].
	self checkReadable: inode path: aPath.
	^inode readFrom: offset count: anInteger
!
contentsOf: aPath
	"Answer the whole file aPath as a ByteArray."
	^self read: aPath from: 0 count: (self stat: aPath) size
!
readLink: aPath
	"Answer the target of the symbolic link aPath, a String."
	| inode |
	inode := self lstat: aPath.
	inode isSymlink ifFalse: [^FileError signal: 'Not a symbolic link: ', aPath path: aPath].
	self checkReadable: inode path: aPath.
	^inode linkTarget
!
rootDirectory
	^self inode: 2
!
inode: aNumber
	"Answer the Ext4Inode numbered aNumber."
	| position block offset bytes |
	inodeCache at: aNumber ifPresent: [:inode | ^inode].
	position := self byteOffsetOfInode: aNumber.
	block := position // blockSize.
	self checkBlock: block count: 1.
	offset := position \\ blockSize.
	bytes := (self metadataBlock: block) copyFrom: offset + 1 to: offset + inodeSize.
	inodeCache size >= 4096 ifTrue: [inodeCache := Dictionary new].
	^inodeCache at: aNumber put: (Ext4Inode new setVolume: self number: aNumber bytes: bytes)
!
byteOffsetOfInode: aNumber
	"Answer where the inode numbered aNumber is on the device, in bytes: in its group's inode table."
	| index |
	(aNumber isInteger and: [aNumber between: 1 and: inodesCount]) ifFalse: [^self corrupt: 'no inode ', aNumber printString].
	index := aNumber - 1.
	^(self inodeTableOfGroup: index // inodesPerGroup) * blockSize + (index \\ inodesPerGroup * inodeSize)
! !

!Ext4Volume methodsFor: 'closing'!
close
	"Close the device."
	device close
! !

!Ext4Volume methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an Ext4Volume('; print: self label; space; print: blocksCount; nextPutAll: ' blocks of '; print: blockSize; nextPut: $)
! !

!Ext4Volume methodsFor: 'path resolution'!
resolve: aPath followLast: aBoolean
	"Answer the inode aPath names, from the root; symbolic links on the way are followed, at its end if aBoolean."
	| components current links name child target |
	components := OrderedCollection new.
	components addAll: (aPath subStrings: '/').
	current := self rootDirectory.
	links := 0.
	[components isEmpty] whileFalse: [
		name := components removeFirst.
		name = '.' ifFalse: [
			current isDirectory ifFalse: [^FileError signal: 'Not a directory: ', aPath path: aPath].
			self checkReadable: current path: aPath.
			child := self lookup: name in: current.
			child isNil ifTrue: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
			(child isSymlink and: [aBoolean or: [components notEmpty]])
				ifTrue: [
					(links := links + 1) > self class maxSymbolicLinks ifTrue: [
						^FileError signal: 'Too many levels of symbolic links: ', aPath path: aPath].
					self checkReadable: child path: aPath.
					target := child linkTarget.
					target isEmpty ifTrue: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
					components addAllFirst: (target subStrings: '/').
					target first = $/ ifTrue: [current := self rootDirectory]]
				ifFalse: [current := child]]].
	^current
!
lookup: aName in: aDirectory
	"Answer the inode aName (a String) names in aDirectory, or nil."
	| number folded |
	number := (self nameTableOf: aDirectory) at: aName utf8Encoded asString ifAbsent: [nil].
	(number isNil and: [aDirectory isCasefolded]) ifTrue: [
		folded := aName asLowercase.
		aDirectory directoryEntries do: [:each | (number isNil and: [each name asLowercase = folded]) ifTrue: [number := each inodeNumber]]].
	^number isNil ifTrue: [nil] ifFalse: [self inode: number]
!
nameTableOf: aDirectory
	"Answer a Dictionary from the names in aDirectory (their UTF-8 bytes as a ByteString) to inode numbers."
	| table |
	directoryCache at: aDirectory number ifPresent: [:cached | ^cached].
	table := Dictionary new.
	aDirectory directoryEntries do: [:each | table at: each rawName put: each inodeNumber].
	directoryCache size >= 256 ifTrue: [directoryCache := Dictionary new].
	^directoryCache at: aDirectory number put: table
!
checkReadable: anInode path: aPath
	anInode isEncrypted ifTrue: [^FileError signal: 'Encrypted (ext4 encryption is not supported): ', aPath path: aPath]
! !

!Ext4Volume methodsFor: 'blocks'!
metadataBlock: aNumber
	"Answer the bytes of the block aNumber, through the cache of recently read metadata blocks. Do not change them."
	| bytes |
	bytes := blockCache at: aNumber ifAbsent: [nil].
	bytes isNil ifFalse: [^bytes].
	self checkBlock: aNumber count: 1.
	bytes := device readBytes: blockSize at: aNumber * blockSize.
	blockCacheOrder size >= blockCacheLimit ifTrue: [blockCache removeKey: blockCacheOrder removeFirst].
	blockCacheOrder addLast: aNumber.
	^blockCache at: aNumber put: bytes
!
readBytes: count at: byteOffset into: aByteArray startingAt: index
	"Read count bytes from byteOffset of the file system on into aByteArray from index on: one device call."
	^device readBytes: count at: byteOffset into: aByteArray startingAt: index
!
checkBlock: aNumber count: count
	(aNumber >= 0 and: [aNumber + count <= blocksCount]) ifFalse: [
		^self corrupt: 'blocks ', aNumber printString, '+', count printString, ' are beyond its end (', blocksCount printString, ' blocks)']
!
decodeRecordLength: anInteger
	"Answer the length of a directory entry from its rec_len field (which, in 64 KiB blocks, encodes 65536 as 65535 or 0 and keeps bits 16 and 17 in its low bits)."
	blockSize < 65536 ifTrue: [^anInteger].
	(anInteger = 65535 or: [anInteger = 0]) ifTrue: [^blockSize].
	^(anInteger bitAnd: 65532) + ((anInteger bitAnd: 3) bitShift: 16)
!
corrupt: aString
	^FileError signal: 'Corrupt ext4 file system: ', aString path: device printString
! !

!Ext4Volume methodsFor: 'group descriptors'!
inodeTableOfGroup: aGroup
	"Answer the first block of aGroup's inode table, from its group descriptor."
	| perBlock bytes offset table |
	(aGroup between: 0 and: groupCount - 1) ifFalse: [^self corrupt: 'no group ', aGroup printString].
	(inodeTables at: aGroup + 1) ifNotNil: [:cached | ^cached].
	perBlock := blockSize // descriptorSize.
	bytes := self metadataBlock: (self descriptorBlock: aGroup // perBlock).
	offset := aGroup \\ perBlock * descriptorSize.
	table := bytes uint32At: offset + 16r08 + 1.
	descriptorSize >= 64 ifTrue: [table := table + ((bytes uint32At: offset + 16r28 + 1) bitShift: 32)].
	self checkBlock: table count: 1.
	^inodeTables at: aGroup + 1 put: table
!
descriptorBlock: anIndex
	"Answer the block of the anIndex-th block of group descriptors: after the superblock, or with meta_bg from s_first_meta_bg on in the first group of its meta group, after that group's backup superblock if it has one."
	| group superblocks |
	((incompat bitAnd: 16r10) = 0 or: [anIndex < (superblock uint32At: 16r104 + 1)]) ifTrue: [^firstDataBlock + 1 + anIndex].
	group := anIndex * (blockSize // descriptorSize).
	superblocks := (self groupHasSuperblock: group) ifTrue: [1] ifFalse: [0].
	(blockSize = 1024 and: [anIndex = 0 and: [firstDataBlock = 0]]) ifTrue: [superblocks := superblocks + 1].
	^group * blocksPerGroup + firstDataBlock + superblocks
!
groupHasSuperblock: aGroup
	"Whether aGroup starts with a copy of the superblock: with sparse_super2 groups 0 and s_backup_bgs; with sparse_super 0, 1 and the powers of 3, 5 and 7; else all."
	aGroup = 0 ifTrue: [^true].
	(compat bitAnd: 16r200) ~= 0 ifTrue: [
		^aGroup = (superblock uint32At: 16r24C + 1) or: [aGroup = (superblock uint32At: 16r250 + 1)]].
	((roCompat bitAnd: 16r1) = 0 or: [aGroup = 1]) ifTrue: [^true].
	#(3 5 7) do: [:base | | power |
		power := base.
		[power < aGroup] whileTrue: [power := power * base].
		power = aGroup ifTrue: [^true]].
	^false
! !

!Ext4Volume methodsFor: 'private'!
setDevice: aBlockDevice
	| revision logBlockSize is64 state |
	device := aBlockDevice.
	warnings := OrderedCollection new.
	device size < 2048 ifTrue: [^self refuse: 'the device is too small'].
	superblock := device readBytes: 1024 at: 1024.
	(superblock uint16At: 16r38 + 1) = 16rEF53 ifFalse: [^self refuse: 'no ext2/3/4 superblock (bad magic number)'].
	revision := superblock uint32At: 16r4C + 1.
	revision > 1 ifTrue: [^self refuse: 'unknown revision ', revision printString].
	logBlockSize := superblock uint32At: 16r18 + 1.
	logBlockSize > 6 ifTrue: [^self refuse: 'blocks of 2^', (logBlockSize + 10) printString, ' bytes (1 to 64 KiB are supported)'].
	blockSize := 1024 bitShift: logBlockSize.
	revision = 0
		ifTrue: [compat := incompat := roCompat := 0]
		ifFalse: [
			compat := superblock uint32At: 16r5C + 1.
			incompat := superblock uint32At: 16r60 + 1.
			roCompat := superblock uint32At: 16r64 + 1].
	self checkFeatures.
	is64 := (incompat bitAnd: 16r80) ~= 0.
	blocksCount := superblock uint32At: 16r04 + 1.
	is64 ifTrue: [blocksCount := blocksCount + ((superblock uint32At: 16r150 + 1) bitShift: 32)].
	inodesCount := superblock uint32At: 16r00 + 1.
	firstDataBlock := superblock uint32At: 16r14 + 1.
	blocksPerGroup := superblock uint32At: 16r20 + 1.
	inodesPerGroup := superblock uint32At: 16r28 + 1.
	(blocksPerGroup = 0 or: [inodesPerGroup = 0 or: [firstDataBlock >= blocksCount]]) ifTrue: [^self corrupt: 'bad superblock'].
	inodeSize := revision = 0 ifTrue: [128] ifFalse: [superblock uint16At: 16r58 + 1].
	(inodeSize >= 128 and: [inodeSize <= blockSize and: [inodeSize isPowerOfTwo]]) ifFalse: [
		^self corrupt: 'inodes of ', inodeSize printString, ' bytes'].
	descriptorSize := is64 ifTrue: [superblock uint16At: 16rFE + 1] ifFalse: [32].
	(descriptorSize >= (is64 ifTrue: [64] ifFalse: [32]) and: [descriptorSize <= blockSize and: [descriptorSize isPowerOfTwo]]) ifFalse: [
		^self corrupt: 'group descriptors of ', descriptorSize printString, ' bytes'].
	groupCount := blocksCount - firstDataBlock + blocksPerGroup - 1 // blocksPerGroup.
	(roCompat bitAnd: 16r400) ~= 0 ifTrue: [self verifySuperblockChecksum].
	(incompat bitAnd: 16r4) ~= 0 ifTrue: [self warn: 'the journal needs recovery: the changes it holds are not replayed, so recent ones may be missing'].
	state := superblock uint16At: 16r3A + 1.
	(state bitAnd: 2) ~= 0 ifTrue: [self warn: 'errors were found on the file system: it needs e2fsck'].
	device size < (blocksCount * blockSize) ifTrue: [self warn: 'the device is smaller than the file system'].
	inodeTables := Array new: groupCount.
	blockCache := Dictionary new.
	blockCacheOrder := OrderedCollection new.
	blockCacheLimit := 4194304 // blockSize max: 64.
	inodeCache := Dictionary new.
	directoryCache := Dictionary new
!
checkFeatures
	| unsupported names |
	unsupported := incompat bitClear: self class supportedIncompatibleFeatures.
	unsupported = 0 ifTrue: [^self].
	names := OrderedCollection new.
	self class incompatibleFeatures do: [:bitAndName |
		(unsupported bitAnd: bitAndName first) ~= 0 ifTrue: [
			names add: bitAndName last.
			unsupported := unsupported bitClear: bitAndName first]].
	unsupported ~= 0 ifTrue: [names add: 'unknown incompatible features 16r', (unsupported printString: 16)].
	^self refuse: 'unsupported features: ', (names inject: '' into: [:all :each | all isEmpty ifTrue: [each] ifFalse: [all, ', ', each]])
!
verifySuperblockChecksum
	| type |
	type := superblock at: 16r175 + 1.
	type = 1 ifFalse: [^self refuse: 'metadata checksums of unknown type ', type printString].
	(Crc32c update: 16rFFFFFFFF bytes: superblock from: 1 to: 16r3FC) = (superblock uint32At: 16r3FC + 1)
		ifFalse: [^self corrupt: 'the superblock''s checksum is wrong']
!
refuse: aString
	^FileError signal: 'Cannot read this ext4 file system: ', aString path: device printString
!
warn: aString
	warnings add: aString.
	Transcript show: 'Ext4Volume on ', device printString, ': ', aString; cr
! !

!Ext4Volume class methodsFor: 'instance creation'!
on: aBlockDevice
	"Answer the file system that starts at offset 0 of aBlockDevice; signal FileError if it is none I can read."
	^self new setDevice: aBlockDevice
!
onFile: aPath
	"Answer the file system in the disk image file aPath (hosted)."
	^self on: (FileBlockDevice on: aPath)
! !

!Ext4Volume class methodsFor: 'constants'!
maxSymbolicLinks
	"Answer how many symbolic links one lookup follows at most, as Linux."
	^40
!
supportedIncompatibleFeatures
	"filetype, needs_recovery (a warning), meta_bg, extent, 64bit, mmp, flex_bg, ea_inode, metadata_csum_seed, large_dir, inline_data, encrypt (files refused), casefold."
	^16r2 + 16r4 + 16r10 + 16r40 + 16r80 + 16r100 + 16r200 + 16r400 + 16r2000 + 16r4000 + 16r8000 + 16r10000 + 16r20000
!
compatibleFeatures
	^#(#(16r1 'dir_prealloc') #(16r2 'imagic_inodes') #(16r4 'has_journal') #(16r8 'ext_attr') #(16r10 'resize_inode') #(16r20 'dir_index') #(16r40 'lazy_bg') #(16r80 'exclude_inode') #(16r100 'exclude_bitmap') #(16r200 'sparse_super2') #(16r400 'fast_commit') #(16r800 'stable_inodes') #(16r1000 'orphan_file'))
!
incompatibleFeatures
	^#(#(16r1 'compression') #(16r2 'filetype') #(16r4 'needs_recovery') #(16r8 'journal_dev') #(16r10 'meta_bg') #(16r40 'extent') #(16r80 '64bit') #(16r100 'mmp') #(16r200 'flex_bg') #(16r400 'ea_inode') #(16r1000 'dirdata') #(16r2000 'metadata_csum_seed') #(16r4000 'large_dir') #(16r8000 'inline_data') #(16r10000 'encrypt') #(16r20000 'casefold'))
!
readOnlyCompatibleFeatures
	^#(#(16r1 'sparse_super') #(16r2 'large_file') #(16r8 'huge_file') #(16r10 'uninit_bg') #(16r20 'dir_nlink') #(16r40 'extra_isize') #(16r80 'snapshot') #(16r100 'quota') #(16r200 'bigalloc') #(16r400 'metadata_csum') #(16r800 'replica') #(16r1000 'read-only') #(16r2000 'project') #(16r4000 'shared_blocks') #(16r8000 'verity') #(16r10000 'orphan_present'))
! !
