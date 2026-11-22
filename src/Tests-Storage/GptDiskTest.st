TestCase subclass: #GptDiskTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Storage'!

GptDiskTest comment: 'GptDisk on MemoryBlockDevices: a fresh table read back, partitions added to both copies (CRCs checked by reading back), the free space at the end, overlaps and full tables refused, damaged or misplaced backups making the table read-only, a damaged primary refused, 4 KB blocks.'!

!GptDiskTest methodsFor: 'helpers'!
disk
	"64 MB of 512-byte blocks with an empty GPT."
	| d |
	d := MemoryBlockDevice blocks: 131072 size: 512.
	GptDisk format: d.
	^d
! !

!GptDiskTest methodsFor: 'tests'!
testFormatReadsBack
	| g |
	g := GptDisk on: self disk.
	self assert: g partitions isEmpty.
	self assert: g isEditable.
	self assert: g firstUsable equals: 34.
	self assert: g lastUsable equals: 131072 - 34.
	self assert: g entryCount equals: 128.
	self assert: g freeAtEnd equals: #(2048 129023)
!
testAddPartitionToBothCopies
	| d g p again |
	d := self disk.
	g := GptDisk on: d.
	p := g addPartition: 'EFI' type: GptDisk efiSystemType first: 2048 last: 4095.
	self assert: p number equals: 1.
	g write.
	self assert: d flushes >= 2.
	again := GptDisk on: d.
	self assert: again isEditable.
	self assert: again partitions size equals: 1.
	self assert: again partitions first name equals: 'EFI'.
	self assert: again partitions first isEfiSystem.
	self assert: again partitions first uniqueGuid equals: p uniqueGuid.
	self assert: again freeAtEnd equals: #(4096 129023)
!
testFreeAtEndIsAligned
	| d g |
	d := self disk.
	g := GptDisk on: d.
	g addPartition: 'a' type: GptDisk linuxFilesystemType first: 2048 last: 5000.
	g write.
	self assert: (GptDisk on: d) freeAtEnd equals: #(6144 129023).
	g := GptDisk on: d.
	g addPartition: 'b' type: GptDisk linuxFilesystemType first: 6144 last: 131038.
	g write.
	self assert: (GptDisk on: d) freeAtEnd isNil
!
testRefusesOverlapAndUnusableBlocks
	| g |
	g := GptDisk on: self disk.
	g addPartition: 'a' type: GptDisk linuxFilesystemType first: 2048 last: 4095.
	self should: [g addPartition: 'b' type: GptDisk linuxFilesystemType first: 4000 last: 8191] raise: GptError.
	self should: [g addPartition: 'c' type: GptDisk linuxFilesystemType first: 10 last: 100] raise: GptError.
	self should: [g addPartition: 'd' type: GptDisk linuxFilesystemType first: 8192 last: 131072] raise: GptError
!
testRefusesWhenNoEntryIsFree
	| g |
	g := GptDisk on: self disk.
	1 to: 128 do: [:i | g addPartition: 'p' type: GptDisk linuxFilesystemType first: 512 * i + 2048 last: 512 * i + 2148].
	self should: [g addPartition: 'one more' type: GptDisk linuxFilesystemType first: 512 * 130 + 2048 last: 512 * 130 + 2148] raise: GptError
!
testDamagedBackupMakesItReadOnly
	| d g |
	d := self disk.
	d bytes at: 131071 * 512 + 20 put: 16r5A.
	g := GptDisk on: d.
	self deny: g isEditable.
	self assert: (g problems first includesSubstring: 'backup').
	self should: [g addPartition: 'a' type: GptDisk linuxFilesystemType first: 2048 last: 4095] raise: GptError
!
testDifferentBackupEntriesMakeItReadOnly
	| d |
	d := self disk.
	d bytes at: (131072 - 33) * 512 + 1 put: 1.
	self deny: (GptDisk on: d) isEditable
!
testBackupNotAtTheEndMakesItReadOnly
	| small big g |
	small := self disk.
	big := MemoryBlockDevice blocks: 2 * 131072 size: 512.
	big bytes replaceFrom: 1 to: small bytes size with: small bytes startingAt: 1.
	g := GptDisk on: big.
	self deny: g isEditable.
	self assert: (g problems first includesSubstring: 'sgdisk -e')
!
testDamagedPrimaryIsRefused
	| d |
	d := self disk.
	d bytes at: 512 + 40 put: 16r77.
	self should: [GptDisk on: d] raise: GptError.
	d := self disk.
	d bytes at: 1024 + 5 put: 16r77.
	self should: [GptDisk on: d] raise: GptError.
	self should: [GptDisk on: (MemoryBlockDevice blocks: 1000 size: 512)] raise: GptError
!
testNoProtectiveMbrMakesItReadOnly
	| d |
	d := self disk.
	d bytes at: 447 + 4 put: 16r83.
	self deny: (GptDisk on: d) isEditable
!
testFourKilobyteBlocks
	| d g |
	d := MemoryBlockDevice blocks: 16384 size: 4096.
	g := GptDisk format: d.
	self assert: g firstUsable equals: 6.
	self assert: g freeAtEnd first equals: 256.
	g addPartition: 'x' type: GptDisk imageStoreType first: 256 last: 511.
	g write.
	self assert: (GptDisk on: d) partitions first isImageStore
!
testGuidsAndNames
	| bytes p |
	bytes := GptDisk guidBytes: 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'.
	self assert: bytes equals: #[16r28 16r73 16r2A 16rC1 16r1F 16rF8 16rD2 16r11 16rBA 16r4B 16r00 16rA0 16rC9 16r3E 16rC9 16r3B].
	self assert: (GptDisk guidString: bytes) equals: GptDisk efiSystemType.
	self assert: ((GptDisk randomGuidBytes at: 8) bitShift: -4) equals: 4.
	p := GptPartition number: 3 type: bytes unique: GptDisk randomGuidBytes first: 10 last: 19 name: 'samaltak-image'.
	p := GptPartition number: 3 bytes: (p entryBytes: 128).
	self assert: p name equals: 'samaltak-image'.
	self assert: p blockCount equals: 10.
	self assert: p typeName equals: 'EFI system'
! !
