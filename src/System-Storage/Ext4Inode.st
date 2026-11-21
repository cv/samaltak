Object subclass: #Ext4Inode
	instanceVariableNames: 'volume number bytes'
	classVariableNames: ''
	package: 'System-Storage'!

Ext4Inode comment: 'I am an inode of an Ext4Volume, as stat: answers it: my bytes as on disk, decoded on demand.

Stat: number, mode, permissions (mode bitAnd: 8r7777), fileType (#file #directory #symlink #charDevice #blockDevice #fifo #socket), isDirectory, isRegularFile, isSymlink, size, uid, gid, nlink, blocks (512-byte units, as st_blocks), flags, generation; atime, mtime, ctime (seconds since 1970, signed, with the extra epoch bits) and atimeNanoseconds etc. (0 without the extra fields), crtime (nil without them), modificationTime (UTC microseconds, as File modificationTime:).
Contents: readFrom: offset count: n (a ByteArray, shorter at the end of the file), contents, linkTarget (a symbolic link''s, a String), directoryEntries (Ext4DirectoryEntry objects in their order on disk, . and .. included).
Mapping: runsFrom: firstBlock count: n answers {logical block. physical block or nil. block count} runs; nil is a hole or an uninitialized extent, which read as zeros. Extent trees (any depth) and ext2/3 block maps (direct, indirect, double, triple) map; inline data lives in my i_block and my system.data extended attribute.'!

!Ext4Inode methodsFor: 'accessing'!
volume
	^volume
!
number
	^number
!
bytes
	"Answer the inode as on disk. Do not change it."
	^bytes
!
mode
	^bytes uint16At: 16r00 + 1
!
permissions
	^self mode bitAnd: 8r7777
!
fileType
	"Answer #file, #directory, #symlink, #charDevice, #blockDevice, #fifo, #socket or #unknown."
	^#(#fifo #charDevice #unknown #directory #unknown #blockDevice #unknown #file #unknown #symlink #unknown #socket #unknown #unknown #unknown)
		at: (self mode bitShift: -12) ifAbsent: [#unknown]
!
isDirectory
	^(self mode bitShift: -12) = 4
!
isRegularFile
	^(self mode bitShift: -12) = 8
!
isFile
	^self isRegularFile
!
isSymlink
	^(self mode bitShift: -12) = 10
!
size
	"Answer the size in bytes."
	^(bytes uint32At: 16r04 + 1) + ((bytes uint32At: 16r6C + 1) bitShift: 32)
!
uid
	^(bytes uint16At: 16r02 + 1) + ((bytes uint16At: 16r78 + 1) bitShift: 16)
!
gid
	^(bytes uint16At: 16r18 + 1) + ((bytes uint16At: 16r7A + 1) bitShift: 16)
!
nlink
	"Answer the number of hard links (1 for a directory with more than 65000 subdirectories, dir_nlink)."
	^bytes uint16At: 16r1A + 1
!
flags
	^bytes uint32At: 16r20 + 1
!
generation
	^bytes uint32At: 16r64 + 1
!
fileAcl
	"Answer the block of my extended attributes, 0 if none."
	^(bytes uint32At: 16r68 + 1) + ((bytes uint16At: 16r76 + 1) bitShift: 32)
!
blocks
	"Answer the space allocated to me in 512-byte units, as st_blocks."
	| n |
	n := self rawBlocks.
	(volume hasHugeFiles and: [(self flags bitAnd: 16r40000) ~= 0]) ifTrue: [n := n * (volume blockSize // 512)].
	^n
!
extraSize
	"Answer i_extra_isize: the bytes of extra fields after the first 128."
	bytes size > 128 ifFalse: [^0].
	^bytes uint16At: 16r80 + 1
! !

!Ext4Inode methodsFor: 'times'!
atime
	^self secondsAt: 16r08 extraAt: 16r8C
!
atimeNanoseconds
	^self nanosecondsAt: 16r8C
!
ctime
	^self secondsAt: 16r0C extraAt: 16r84
!
ctimeNanoseconds
	^self nanosecondsAt: 16r84
!
mtime
	"Answer the modification time in seconds since 1970 (UTC)."
	^self secondsAt: 16r10 extraAt: 16r88
!
mtimeNanoseconds
	^self nanosecondsAt: 16r88
!
crtime
	"Answer the creation time in seconds since 1970, nil if the inode has no room for it."
	(self hasExtraField: 16r90) ifFalse: [^nil].
	^self secondsAt: 16r90 extraAt: 16r94
!
crtimeNanoseconds
	^self nanosecondsAt: 16r94
!
modificationTime
	"Answer the modification time in microseconds since 1970 (UTC), as File modificationTime:."
	^self mtime * 1000000 + (self mtimeNanoseconds // 1000)
! !

!Ext4Inode methodsFor: 'testing'!
usesExtents
	^(self flags bitAnd: 16r80000) ~= 0
!
hasInlineData
	^(self flags bitAnd: 16r10000000) ~= 0
!
isHashIndexed
	"Whether I am a directory with an htree index."
	^(self flags bitAnd: 16r1000) ~= 0
!
isEncrypted
	^(self flags bitAnd: 16r800) ~= 0
!
isCasefolded
	^(self flags bitAnd: 16r40000000) ~= 0
!
isFastSymlink
	"Whether my target is in i_block: a symbolic link with no blocks but its extended attribute block's, as the kernel decides."
	| attributeBlocks |
	(self isSymlink and: [self hasInlineData not]) ifFalse: [^false].
	attributeBlocks := self fileAcl = 0 ifTrue: [0] ifFalse: [volume blockSize // 512].
	^self rawBlocks - attributeBlocks = 0
! !

!Ext4Inode methodsFor: 'reading'!
readFrom: offset count: anInteger
	"Answer a ByteArray with at most anInteger bytes from offset (0-based) on: fewer at my end, none past it. Holes and uninitialized extents read as zeros; each contiguous run of blocks is one device read."
	| count result blockSize first last |
	(offset >= 0 and: [anInteger >= 0]) ifFalse: [^self error: 'Negative offset or count'].
	self checkReadable.
	count := (anInteger min: self size - offset) max: 0.
	result := ByteArray new: count.
	count = 0 ifTrue: [^result].
	self hasInlineData ifTrue: [
		| data |
		data := self inlineData.
		data size >= (offset + count) ifFalse: [^volume corrupt: 'inline data shorter than inode ', number printString].
		^result replaceFrom: 1 to: count with: data startingAt: offset + 1; yourself].
	blockSize := volume blockSize.
	first := offset // blockSize.
	last := offset + count - 1 // blockSize.
	(self runsFrom: first count: last - first + 1) do: [:run | | from to |
		(run at: 2) isNil ifFalse: [
			from := (run at: 1) * blockSize max: offset.
			to := (run at: 1) + (run at: 3) * blockSize min: offset + count.
			volume readBytes: to - from at: (run at: 2) * blockSize + (from - ((run at: 1) * blockSize))
				into: result startingAt: from - offset + 1]].
	^result
!
contents
	^self readFrom: 0 count: self size
!
linkTarget
	"Answer the target of this symbolic link, a String."
	| size |
	self isSymlink ifFalse: [^FileError signal: 'Not a symbolic link: inode ', number printString path: self printString].
	self checkReadable.
	size := self size.
	self isFastSymlink ifTrue: [
		size > 60 ifTrue: [^volume corrupt: 'fast symbolic link of ', size printString, ' bytes in inode ', number printString].
		^(bytes copyFrom: 16r28 + 1 to: 16r28 + size) utf8Decoded].
	^(self readFrom: 0 count: size) utf8Decoded
!
directoryEntries
	"Answer my entries as Ext4DirectoryEntry objects, in their order on disk, . and .. included. An htree's index blocks hold no entries (their fake entries have inode 0), so reading every block reads its leaves."
	| entries data blockSize |
	self isDirectory ifFalse: [^FileError signal: 'Not a directory: inode ', number printString path: self printString].
	self checkReadable.
	entries := OrderedCollection new.
	self hasInlineData ifTrue: [
		data := self inlineData.
		entries
			add: (Ext4DirectoryEntry rawName: '.' inodeNumber: number fileTypeCode: (volume hasFileTypes ifTrue: [2]));
			add: (Ext4DirectoryEntry rawName: '..' inodeNumber: (data uint32At: 1) fileTypeCode: (volume hasFileTypes ifTrue: [2])).
		self addEntriesFrom: data start: 4 stop: 60 into: entries.
		self addEntriesFrom: data start: 60 stop: data size into: entries.
		^entries].
	data := self contents.
	blockSize := volume blockSize.
	0 to: data size - 1 by: blockSize do: [:start |
		self addEntriesFrom: data start: start stop: (start + blockSize min: data size) into: entries].
	^entries
! !

!Ext4Inode methodsFor: 'mapping'!
runsFrom: firstBlock count: n
	"Answer {logical block. physical block or nil. count} for the n logical blocks from firstBlock on, in order, contiguous runs merged; nil for a hole or an uninitialized extent."
	| runs |
	runs := OrderedCollection new.
	n <= 0 ifTrue: [^runs].
	self usesExtents
		ifTrue: [self addExtentRunsFrom: firstBlock to: firstBlock + n into: runs]
		ifFalse: [self addMappedRunsFrom: firstBlock to: firstBlock + n into: runs].
	^runs
! !

!Ext4Inode methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an Ext4Inode('; print: number; space; nextPutAll: self fileType; space; print: self size; nextPutAll: ' bytes)'
! !

!Ext4Inode methodsFor: 'private'!
setVolume: aVolume number: anInteger bytes: aByteArray
	volume := aVolume.
	number := anInteger.
	bytes := aByteArray
!
rawBlocks
	| n |
	n := bytes uint32At: 16r1C + 1.
	volume hasHugeFiles ifTrue: [n := n + ((bytes uint16At: 16r74 + 1) bitShift: 32)].
	^n
!
hasExtraField: offset
	"Whether the 4-byte extra field at offset is within i_extra_isize."
	^offset + 4 <= (128 + self extraSize)
!
secondsAt: offset extraAt: extraOffset
	| seconds |
	seconds := bytes uint32At: offset + 1.
	seconds >= 16r80000000 ifTrue: [seconds := seconds - 16r100000000].
	(self hasExtraField: extraOffset) ifTrue: [seconds := seconds + (((bytes uint32At: extraOffset + 1) bitAnd: 3) bitShift: 32)].
	^seconds
!
nanosecondsAt: extraOffset
	(self hasExtraField: extraOffset) ifFalse: [^0].
	^(bytes uint32At: extraOffset + 1) bitShift: -2
!
checkReadable
	self isEncrypted ifTrue: [^FileError signal: 'Encrypted (ext4 encryption is not supported): inode ', number printString path: self printString]
!
inlineData
	"Answer my inline data: the 60 bytes of i_block, then the value of my system.data extended attribute."
	^(bytes copyFrom: 16r28 + 1 to: 16r28 + 60), self inlineDataAttribute
!
inlineDataAttribute
	"Answer the value of the extended attribute system.data among those in the inode after its extra fields (empty if none)."
	| start entries pos nameLength valueOffset valueSize |
	start := 128 + self extraSize.
	(start + 4 <= bytes size and: [(bytes uint32At: start + 1) = 16rEA020000]) ifFalse: [^ByteArray new].
	entries := start + 4.
	pos := entries.
	[pos + 16 <= bytes size and: [(bytes uint32At: pos + 1) ~= 0]] whileTrue: [
		nameLength := bytes at: pos + 1.
		((bytes at: pos + 2) = 7 and: [nameLength = 4 and: [pos + 20 <= bytes size and: [(bytes copyFrom: pos + 17 to: pos + 20) asString = 'data']]]) ifTrue: [
			valueOffset := bytes uint16At: pos + 3.
			valueSize := bytes uint32At: pos + 9.
			entries + valueOffset + valueSize <= bytes size ifFalse: [^volume corrupt: 'inline data beyond inode ', number printString].
			^bytes copyFrom: entries + valueOffset + 1 to: entries + valueOffset + valueSize].
		pos := pos + (16 + nameLength + 3 // 4 * 4)].
	^ByteArray new
!
addEntriesFrom: data start: start stop: stop into: entries
	"Add the entries in the bytes start..stop - 1 (0-based) of data, a block or inline data; skip those of inode 0 (free space, an htree's index, a checksum tail) and a block of zeros (a hole)."
	| pos inode recordLength nameLength |
	pos := start.
	[pos + 8 <= stop] whileTrue: [
		inode := data uint32At: pos + 1.
		recordLength := volume decodeRecordLength: (data uint16At: pos + 5).
		(pos = start and: [inode = 0 and: [(data uint16At: pos + 5) = 0 and: [volume blockSize < 65536]]]) ifTrue: [^self].
		nameLength := data at: pos + 7.
		(recordLength >= 8 and: [recordLength \\ 4 = 0 and: [pos + recordLength <= stop and: [nameLength + 8 <= recordLength]]])
			ifFalse: [^volume corrupt: 'bad directory entry at ', pos printString, ' in inode ', number printString].
		inode = 0 ifFalse: [
			entries addLast: (Ext4DirectoryEntry
				rawName: (data copyFrom: pos + 9 to: pos + 8 + nameLength) asString
				inodeNumber: inode
				fileTypeCode: (volume hasFileTypes ifTrue: [data at: pos + 8]))].
		pos := pos + recordLength]
!
addRun: logical physical: physical count: count into: runs
	"Add a run, merged into the last if it continues it."
	| last |
	count <= 0 ifTrue: [^self].
	physical isNil ifFalse: [volume checkBlock: physical count: count].
	runs isEmpty ifFalse: [
		last := runs last.
		((last at: 1) + (last at: 3) = logical and: [
			(last at: 2) isNil
				ifTrue: [physical isNil]
				ifFalse: [physical notNil and: [(last at: 2) + (last at: 3) = physical]]])
					ifTrue: [^last at: 3 put: (last at: 3) + count]].
	runs addLast: (Array with: logical with: physical with: count)
!
addExtentRunsFrom: low to: high into: runs
	"Add the runs of the logical blocks low..high - 1 from my extent tree: the leaf for a block, then its extents, then the gap to the next leaf's first block, and so on."
	| block leaf node base nextKey count entry start length uninitialized end before |
	block := low.
	[block < high] whileTrue: [
		before := block.
		leaf := self extentLeafFor: block.
		node := leaf at: 1.
		base := leaf at: 2.
		nextKey := leaf at: 3.
		count := node uint16At: base + 2 + 1.
		0 to: count - 1 do: [:i |
			block < high ifTrue: [
				entry := base + 12 + (i * 12).
				start := node uint32At: entry + 1.
				length := node uint16At: entry + 4 + 1.
				uninitialized := length > 32768.
				uninitialized ifTrue: [length := length - 32768].
				start + length > block ifTrue: [
					start > block ifTrue: [
						end := start min: high.
						self addRun: block physical: nil count: end - block into: runs.
						block := end].
					block < high ifTrue: [
						end := start + length min: high.
						self addRun: block
							physical: (uninitialized ifFalse: [(node uint32At: entry + 8 + 1) + ((node uint16At: entry + 6 + 1) bitShift: 32) + (block - start)])
							count: end - block
							into: runs.
						block := end]]]].
		"Past the leaf's last extent: a hole up to the next leaf's first block (if it is not here already), or to the end."
		(block < high and: [nextKey isNil or: [nextKey > block]]) ifTrue: [
			end := nextKey isNil ifTrue: [high] ifFalse: [nextKey min: high].
			self addRun: block physical: nil count: end - block into: runs.
			block := end].
		block = before ifTrue: [^volume corrupt: 'extent tree out of order in inode ', number printString]]
!
extentLeafFor: aBlock
	"Answer {node bytes. offset of its header. first block of the next leaf or nil} for the leaf of my extent tree whose range holds aBlock: at each index node the last entry starting at or before it (or the first)."
	| node base depth nextKey count low high middle entry child |
	node := bytes.
	base := 16r28.
	nextKey := nil.
	depth := self checkExtentHeader: node at: base depth: nil.
	[depth > 0] whileTrue: [
		count := node uint16At: base + 2 + 1.
		count = 0 ifTrue: [^volume corrupt: 'empty extent index in inode ', number printString].
		low := 0.
		high := count - 1.
		[low < high] whileTrue: [
			middle := low + high + 1 // 2.
			(node uint32At: base + 12 + (middle * 12) + 1) <= aBlock ifTrue: [low := middle] ifFalse: [high := middle - 1]].
		low + 1 < count ifTrue: [nextKey := node uint32At: base + 12 + ((low + 1) * 12) + 1].
		entry := base + 12 + (low * 12).
		child := (node uint32At: entry + 4 + 1) + ((node uint16At: entry + 8 + 1) bitShift: 32).
		volume checkBlock: child count: 1.
		node := volume metadataBlock: child.
		base := 0.
		depth := self checkExtentHeader: node at: 0 depth: depth - 1].
	^Array with: node with: base with: nextKey
!
checkExtentHeader: node at: base depth: expectedDepth
	"Answer the depth of the extent node at base in node, after checking its header."
	| entries max depth |
	(node uint16At: base + 1) = 16rF30A ifFalse: [^volume corrupt: 'bad extent header in inode ', number printString].
	entries := node uint16At: base + 2 + 1.
	max := node uint16At: base + 4 + 1.
	depth := node uint16At: base + 6 + 1.
	(entries <= max and: [base + 12 + (max * 12) <= node size and: [depth <= 5 and: [expectedDepth isNil or: [depth = expectedDepth]]]])
		ifFalse: [^volume corrupt: 'bad extent node in inode ', number printString].
	^depth
!
addMappedRunsFrom: low to: high into: runs
	"Add the runs of the logical blocks low..high - 1 from my ext2/3 block map: 12 direct blocks, then an indirect, a double and a triple indirect block."
	| pointers base span |
	pointers := volume blockSize // 4.
	low to: (high min: 12) - 1 do: [:i |
		self addRun: i physical: (self nonZero: (bytes uint32At: 16r28 + (i * 4) + 1)) count: 1 into: runs].
	base := 12.
	span := pointers.
	1 to: 3 do: [:level |
		(low < (base + span) and: [high > base]) ifTrue: [
			self addMappedRunsFrom: (low max: base) to: (high min: base + span)
				pointer: (bytes uint32At: 16r28 + ((11 + level) * 4) + 1) level: level base: base into: runs].
		base := base + span.
		span := span * pointers].
	high > base ifTrue: [self addRun: (low max: base) physical: nil count: high - (low max: base) into: runs]
!
addMappedRunsFrom: low to: high pointer: aBlock level: level base: base into: runs
	"Add the runs of low..high - 1 from the subtree at aBlock, level levels of indirection above the data, whose first logical block is base. A 0 pointer is a hole for its whole subtree."
	| block span |
	aBlock = 0 ifTrue: [^self addRun: low physical: nil count: high - low into: runs].
	level = 0 ifTrue: [^self addRun: low physical: aBlock count: 1 into: runs].
	volume checkBlock: aBlock count: 1.
	block := volume metadataBlock: aBlock.
	span := (volume blockSize // 4) raisedTo: level - 1.
	low - base // span to: high - 1 - base // span do: [:i | | childBase |
		childBase := base + (i * span).
		self addMappedRunsFrom: (low max: childBase) to: (high min: childBase + span)
			pointer: (block uint32At: i * 4 + 1) level: level - 1 base: childBase into: runs]
!
nonZero: aBlock
	^aBlock = 0 ifTrue: [nil] ifFalse: [aBlock]
! !
