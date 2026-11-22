Object subclass: #GptDisk
	instanceVariableNames: 'device blockSize primary backup entries partitions tableProblem backupProblem'
	classVariableNames: ''
	package: 'System-Storage'!

GptDisk comment: 'I read and carefully change the GUID partition table of a BlockDevice (UEFI 2.10, 5.3): the protective MBR, the primary header (block 1) and its entry array, the backup header (the last block) and its array. on: reads and checks them all: signature, header and entry CRCs (Crc32), each header''s own block, that both copies hold the same entries, that the partitions lie in the usable blocks. A damaged primary copy signals GptError; anything else wrong makes me read-only (problems says what).

Changes are made in memory (addPartition:type:first:last:) until write, which writes the backup''s entries and header first, flushes, then the primary''s, flushes, and reads both back. I never move, resize or remove a partition; I add one only in usable blocks no partition overlaps. freeAtEnd is the space after the last partition, aligned to 1 MB.

	| gpt | gpt := GptDisk on: aBlockDevice.
	gpt partitions.
	gpt freeAtEnd                                    "#(first last) or nil"
	gpt addPartition: ''samaltak-image'' type: GptDisk imageStoreType first: 411648 last: 1435647.
	gpt write'!

!GptDisk class methodsFor: 'instance creation'!
on: aBlockDevice
	"The table of aBlockDevice, checked; GptError if there is none or its primary copy is damaged."
	^self new setDevice: aBlockDevice; read; yourself
! !

!GptDisk class methodsFor: 'types'!
efiSystemType
	^'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
!
imageStoreType
	"make usb-image's and the installer's type for a UefiImageStore partition."
	^'5aa3a57f-0f7e-4c2b-9b5e-53414d53544f'
!
linuxFilesystemType
	^'0fc63daf-8483-4772-8e79-3d69d8477de4'
!
typeNames
	^Dictionary new
		at: self efiSystemType put: 'EFI system';
		at: self imageStoreType put: 'Samaltak image store';
		at: self linuxFilesystemType put: 'Linux filesystem';
		at: '0657fd6d-a4ab-43c4-84e5-0933c84b4f4f' put: 'Linux swap';
		at: 'e6d6d379-f507-44c2-a23c-238f2a3df928' put: 'Linux LVM';
		at: 'a19d880f-05fc-4d3b-a006-743f0f84911e' put: 'Linux RAID';
		at: 'b921b045-1df0-41c3-af44-4c6f280d3fae' put: 'Linux root (arm64)';
		at: '4f68bce3-e8cd-4db1-96e7-fbcaf984b709' put: 'Linux root (x86-64)';
		at: 'bc13c2ff-59e6-4262-a352-b275fd6f7172' put: 'Linux extended boot';
		at: 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7' put: 'Microsoft basic data';
		at: 'e3c9e316-0b5c-4db8-817d-f92df00215ae' put: 'Microsoft reserved';
		at: '21686148-6449-6e6f-744e-656564454649' put: 'BIOS boot';
		yourself
! !

!GptDisk class methodsFor: 'guids'!
guidBytes: aString
	"The 16 bytes on disk of the GUID 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' (its first three fields little-endian)."
	| hex bytes value |
	hex := (aString reject: [:c | c = $-]) asUppercase.
	hex size = 32 ifFalse: [^self error: 'Not a GUID: ', aString].
	value := [:from :to | Integer readFrom: (hex copyFrom: from to: to) base: 16].
	bytes := ByteArray new: 16.
	bytes uint32At: 1 put: (value value: 1 value: 8).
	bytes uint16At: 5 put: (value value: 9 value: 12).
	bytes uint16At: 7 put: (value value: 13 value: 16).
	0 to: 7 do: [:i | bytes at: 9 + i put: (value value: 17 + (2 * i) value: 18 + (2 * i))].
	^bytes
!
guidString: bytes
	"The text of the 16 GUID bytes on disk."
	| hex |
	hex := [:value :digits | (value printString: 16) asLowercase padLeftTo: digits with: $0].
	^String streamContents: [:s |
		s nextPutAll: (hex value: (bytes uint32At: 1) value: 8); nextPut: $-;
			nextPutAll: (hex value: (bytes uint16At: 5) value: 4); nextPut: $-;
			nextPutAll: (hex value: (bytes uint16At: 7) value: 4); nextPut: $-.
		9 to: 16 do: [:i |
			i = 11 ifTrue: [s nextPut: $-].
			s nextPutAll: (hex value: (bytes at: i) value: 2)]]
!
randomGuidBytes
	"A new random (version 4) GUID's bytes: SecureRandom's where there is entropy, else Random's."
	| bytes |
	bytes := [(Smalltalk at: #SecureRandom ifAbsent: [nil]) ifNotNil: [:c | c default nextBytes: 16]] on: Error do: [:e | e return: nil].
	bytes isNil ifTrue: [| r |
		r := Random seed: Time millisecondClockValue.
		bytes := ByteArray new: 16.
		1 to: 16 do: [:i | bytes at: i put: (r nextInt: 256) - 1]].
	bytes := bytes asByteArray copy.
	bytes at: 8 put: (((bytes at: 8) bitAnd: 16r0F) bitOr: 16r40).
	bytes at: 9 put: (((bytes at: 9) bitAnd: 16r3F) bitOr: 16r80).
	^bytes
! !

!GptDisk class methodsFor: 'formatting'!
format: aBlockDevice
	"Write an empty GPT (a protective MBR, 128 entries) on aBlockDevice, as sgdisk -o does, and answer it read back. For tests and blank disks: it replaces whatever table is there."
	| bs last entryBlocks mbr header entryArray |
	bs := aBlockDevice blockSize.
	last := aBlockDevice blockCount - 1.
	entryBlocks := 128 * 128 + bs - 1 // bs.
	mbr := ByteArray new: bs.
	mbr at: 447 + 2 put: 2; at: 447 + 4 put: 16rEE; at: 447 + 5 put: 16rFF; at: 447 + 6 put: 16rFF; at: 447 + 7 put: 16rFF.
	mbr uint32At: 447 + 8 put: 1.
	mbr uint32At: 447 + 12 put: (last min: 16rFFFFFFFF).
	mbr at: 511 put: 16r55; at: 512 put: 16rAA.
	aBlockDevice write: 1 blocksAt: 0 from: mbr startingAt: 1.
	entryArray := ByteArray new: entryBlocks * bs.
	header := ByteArray new: bs.
	header replaceFrom: 1 to: 8 with: 'EFI PART' asByteArray startingAt: 1.
	header uint32At: 9 put: 16r10000; uint32At: 13 put: 92.
	header uint64At: 41 put: 2 + entryBlocks; uint64At: 49 put: last - entryBlocks - 1.
	header replaceFrom: 57 to: 72 with: self randomGuidBytes startingAt: 1.
	header uint32At: 81 put: 128; uint32At: 85 put: 128; uint32At: 89 put: (Crc32 checksumOf: entryArray from: 1 to: 128 * 128).
	aBlockDevice write: entryBlocks blocksAt: last - entryBlocks from: entryArray startingAt: 1.
	aBlockDevice write: 1 blocksAt: last from: (self header: header at: last alternate: 1 entries: last - entryBlocks) startingAt: 1.
	aBlockDevice write: entryBlocks blocksAt: 2 from: entryArray startingAt: 1.
	aBlockDevice write: 1 blocksAt: 1 from: (self header: header at: 1 alternate: last entries: 2) startingAt: 1.
	aBlockDevice flush.
	^self on: aBlockDevice
!
header: aHeader at: lba alternate: alternateLba entries: entriesLba
	"A copy of the header block aHeader for the copy at lba, its CRC computed."
	| h |
	h := aHeader copy.
	h uint64At: 25 put: lba; uint64At: 33 put: alternateLba; uint64At: 73 put: entriesLba.
	^self withHeaderCrc: h
!
withHeaderCrc: aHeader
	"aHeader (a block) with its CRC field set."
	| size |
	size := aHeader uint32At: 13.
	aHeader uint32At: 17 put: 0.
	aHeader uint32At: 17 put: (Crc32 checksumOf: aHeader from: 1 to: size).
	^aHeader
! !

!GptDisk methodsFor: 'initialization'!
setDevice: aBlockDevice
	device := aBlockDevice.
	blockSize := aBlockDevice blockSize
! !

!GptDisk methodsFor: 'accessing'!
device
	^device
!
blockSize
	^blockSize
!
blockCount
	^device blockCount
!
partitions
	"The partitions in use, by number."
	^partitions
!
partitionNumbered: anInteger
	^partitions detect: [:p | p number = anInteger] ifNone: [nil]
!
efiSystemPartitions
	^partitions select: [:p | p isEfiSystem]
!
firstUsable
	^primary uint64At: 41
!
lastUsable
	^primary uint64At: 49
!
diskGuid
	^primary copyFrom: 57 to: 72
!
backupLba
	^primary uint64At: 33
!
entryCount
	^primary uint32At: 81
!
entrySize
	^primary uint32At: 85
!
alignment
	"Blocks a new partition starts at a multiple of: 1 MB."
	^1048576 // blockSize max: 1
!
lastUsedLba
	"The last block of the last partition, or the block before firstUsable."
	^partitions inject: self firstUsable - 1 into: [:m :p | m max: p lastLba]
!
freeAtEnd
	"#(first last) of the free blocks after the last partition up to lastUsable, starting at a multiple of the alignment and a whole number of alignments long; nil if not one alignment is free."
	| align start n |
	align := self alignment.
	start := (self lastUsedLba + 1 max: self firstUsable) + align - 1 // align * align.
	n := self lastUsable + 1 - start // align * align.
	n <= 0 ifTrue: [^nil].
	^Array with: start with: start + n - 1
! !

!GptDisk methodsFor: 'checking'!
problems
	"What is wrong with the table short of a damaged primary copy (which on: refuses): empty if I may change it."
	| list |
	list := OrderedCollection new.
	tableProblem ifNotNil: [:p | list add: p].
	backupProblem ifNotNil: [:p | list add: p].
	^list asArray
!
isEditable
	^self problems isEmpty
!
checkEditable
	self isEditable ifFalse: [^GptError signal: 'Will not change this partition table: ', self problems first]
! !

!GptDisk methodsFor: 'reading'!
read
	| mbr backupEntries |
	(blockSize >= 512 and: [device blockCount > 67]) ifFalse: [^GptError signal: 'Not a disk for a GPT: ', device printString].
	mbr := device read: 1 blocksAt: 0.
	tableProblem := ((mbr at: 511) = 16r55 and: [(mbr at: 512) = 16rAA and: [(0 to: 3) anySatisfy: [:i | (mbr at: 447 + (16 * i) + 4) = 16rEE]]])
		ifTrue: [nil]
		ifFalse: ['no protective MBR (block 0 has no partition of type EE)'].
	primary := self headerAt: 1 named: 'primary'.
	entries := self entriesOf: primary named: 'primary'.
	partitions := self parsePartitions.
	backupProblem := nil.
	[(primary uint64At: 33) = (device blockCount - 1) ifFalse: [
			GptError signal: 'the backup GPT header is at block ', (primary uint64At: 33) printString, ', not at the last block (', (device blockCount - 1) printString, '): sgdisk -e moves it'].
		backup := self headerAt: (primary uint64At: 33) named: 'backup'.
		(backup uint64At: 33) = 1 ifFalse: [GptError signal: 'the backup GPT header does not point back to block 1'].
		((backup uint32At: 81) = self entryCount and: [(backup uint32At: 85) = self entrySize]) ifFalse: [GptError signal: 'the backup GPT has another entry array'].
		(self entriesEndAt: backup) < (backup uint64At: 25) ifFalse: [GptError signal: 'the backup GPT entries overlap its header'].
		(backup uint64At: 73) > self lastUsable ifFalse: [GptError signal: 'the backup GPT entries overlap the usable blocks'].
		backupEntries := self entriesOf: backup named: 'backup'.
		backupEntries = entries ifFalse: [GptError signal: 'the backup GPT''s entries differ from the primary''s']]
			on: GptError do: [:e | backupProblem := e messageText. e return: nil].
	(tableProblem isNil and: [(self entriesEndAt: primary) >= self firstUsable]) ifTrue: [tableProblem := 'the primary entries overlap the usable blocks'].
	(tableProblem isNil and: [(partitions allSatisfy: [:p | p firstLba >= self firstUsable and: [p lastLba <= self lastUsable and: [p firstLba <= p lastLba]]]) not])
		ifTrue: [tableProblem := 'a partition lies outside the usable blocks'].
	(tableProblem isNil and: [partitions anySatisfy: [:p | partitions anySatisfy: [:q | q ~~ p and: [q overlapsFrom: p firstLba to: p lastLba]]]])
		ifTrue: [tableProblem := 'partitions overlap']
!
headerAt: lba named: aString
	"The checked header block at lba."
	| h size |
	h := device read: 1 blocksAt: lba.
	(h copyFrom: 1 to: 8) = 'EFI PART' asByteArray ifFalse: [^GptError signal: 'no ', aString, ' GPT header (EFI PART) at block ', lba printString].
	size := h uint32At: 13.
	(size between: 92 and: blockSize) ifFalse: [^GptError signal: 'the ', aString, ' GPT header has a bad size'].
	(Crc32 checksumOf: ((h copyFrom: 1 to: size) uint32At: 17 put: 0; yourself)) = (h uint32At: 17)
		ifFalse: [^GptError signal: 'the ', aString, ' GPT header''s CRC is wrong'].
	(h uint64At: 25) = lba ifFalse: [^GptError signal: 'the ', aString, ' GPT header is not for block ', lba printString].
	((h uint32At: 85) >= 128 and: [(h uint32At: 85) \\ 8 = 0 and: [(h uint32At: 81) between: 1 and: 16384]])
		ifFalse: [^GptError signal: 'the ', aString, ' GPT header has a bad entry array'].
	(h uint32At: 81) * (h uint32At: 85) <= (16 * 1048576) ifFalse: [^GptError signal: 'the ', aString, ' GPT entry array is too large'].
	^h
!
entriesOf: aHeader named: aString
	| bytes n blocks |
	n := (aHeader uint32At: 81) * (aHeader uint32At: 85).
	blocks := n + blockSize - 1 // blockSize.
	bytes := (device read: blocks blocksAt: (aHeader uint64At: 73)) copyFrom: 1 to: n.
	(Crc32 checksumOf: bytes) = (aHeader uint32At: 89) ifFalse: [^GptError signal: 'the ', aString, ' GPT entries'' CRC is wrong'].
	^bytes
!
entriesEndAt: aHeader
	"The last block of aHeader's entry array."
	^(aHeader uint64At: 73) + ((aHeader uint32At: 81) * (aHeader uint32At: 85) + blockSize - 1 // blockSize) - 1
!
parsePartitions
	| size |
	size := self entrySize.
	^((1 to: self entryCount)
		collect: [:i | GptPartition number: i bytes: (entries copyFrom: (i - 1) * size + 1 to: i * size)])
		select: [:p | p isUsed]
! !

!GptDisk methodsFor: 'editing'!
addPartition: aName type: aTypeString first: first last: last
	"Add a partition in free usable blocks, in memory only (write writes it); answer it."
	| index p |
	self checkEditable.
	(first >= self firstUsable and: [last <= self lastUsable and: [first <= last]]) ifFalse: [
		^GptError signal: 'Blocks ', first printString, '..', last printString, ' are not all usable (', self firstUsable printString, '..', self lastUsable printString, ')'].
	(partitions detect: [:each | each overlapsFrom: first to: last] ifNone: [nil]) ifNotNil: [:other |
		^GptError signal: 'Blocks ', first printString, '..', last printString, ' overlap partition ', other number printString].
	index := (1 to: self entryCount) detect: [:i | ((entries copyFrom: (i - 1) * self entrySize + 1 to: (i - 1) * self entrySize + 16) allSatisfy: [:b | b = 0])] ifNone: [nil].
	index isNil ifTrue: [^GptError signal: 'No free entry in the partition table'].
	p := GptPartition number: index type: (self class guidBytes: aTypeString) unique: self class randomGuidBytes first: first last: last name: aName.
	entries replaceFrom: (index - 1) * self entrySize + 1 to: index * self entrySize with: (p entryBytes: self entrySize) startingAt: 1.
	partitions := self parsePartitions.
	^p
!
write
	"Write the entries to the backup table, then to the primary one, each header after its entries; then read both back."
	| crc |
	self checkEditable.
	crc := Crc32 checksumOf: entries.
	self writeEntriesAt: (backup uint64At: 73).
	device write: 1 blocksAt: (backup uint64At: 25) from: (self class withHeaderCrc: (backup copy uint32At: 89 put: crc; yourself)) startingAt: 1.
	device flush.
	self writeEntriesAt: (primary uint64At: 73).
	device write: 1 blocksAt: 1 from: (self class withHeaderCrc: (primary copy uint32At: 89 put: crc; yourself)) startingAt: 1.
	device flush.
	self read.
	self isEditable ifFalse: [^GptError signal: 'The table read back is not consistent: ', self problems first]
!
writeEntriesAt: lba
	| blocks bytes |
	blocks := entries size + blockSize - 1 // blockSize.
	bytes := device read: blocks blocksAt: lba.
	bytes replaceFrom: 1 to: entries size with: entries startingAt: 1.
	device write: blocks blocksAt: lba from: bytes startingAt: 1
! !

!GptDisk methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a GptDisk('; print: device; nextPutAll: ', '; print: partitions size; nextPutAll: ' partitions)'
! !
