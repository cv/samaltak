Object subclass: #BlockDevice
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Storage'!

BlockDevice comment: 'I am a device of fixed-size blocks, numbered from 0 (logical block addresses): a disk, a partition, a disk image. Abstract; subclasses answer blockSize and blockCount and implement at least one of read:blocksAt: and read:blocksAt:into:startingAt: (each is defined by the other here, so implementing neither recurses).

	blockSize                                   bytes a block (512, 4096, ...)
	blockCount                                  blocks on the device
	size                                        bytes on the device
	isReadOnly                                  true unless a subclass can write
	read: count blocksAt: lba                   a ByteArray of count blocks
	read: count blocksAt: lba into: bytes startingAt: index    the same into bytes, answering bytes
	readBytes: count at: byteOffset             count bytes at any byte offset (whole blocks are read; one device call for the aligned middle)
	readBytes: count at: byteOffset into: bytes startingAt: index
	close                                       release what the device holds

Reading outside the device signals FileError. FileBlockDevice reads a disk image file on the host (System-Files); FirmwareBlockDevice reads the firmware''s Block I/O on UEFI.'!

!BlockDevice methodsFor: 'accessing'!
blockSize
	"Answer the number of bytes a block."
	^self subclassResponsibility
!
blockCount
	"Answer the number of blocks."
	^self subclassResponsibility
!
size
	"Answer the number of bytes on the device."
	^self blockSize * self blockCount
!
isReadOnly
	^true
! !

!BlockDevice methodsFor: 'reading'!
read: count blocksAt: lba
	"Answer a ByteArray with count blocks from block lba on."
	| bytes |
	bytes := ByteArray new: count * self blockSize.
	self read: count blocksAt: lba into: bytes startingAt: 1.
	^bytes
!
read: count blocksAt: lba into: aByteArray startingAt: index
	"Read count blocks from block lba on into aByteArray from index on; answer aByteArray."
	aByteArray replaceFrom: index to: index + (count * self blockSize) - 1 with: (self read: count blocksAt: lba) startingAt: 1.
	^aByteArray
!
readBytes: count at: byteOffset
	"Answer a ByteArray with the count bytes from byteOffset (0-based) on."
	^self readBytes: count at: byteOffset into: (ByteArray new: count) startingAt: 1
!
readBytes: count at: byteOffset into: aByteArray startingAt: index
	"Read the count bytes from byteOffset (0-based) on into aByteArray from index on; answer aByteArray. A partial block at either end is read on its own, the whole blocks between in one call."
	| bs pos dst remaining n block |
	count = 0 ifTrue: [^aByteArray].
	self checkBytes: count at: byteOffset.
	bs := self blockSize.
	pos := byteOffset.
	dst := index.
	remaining := count.
	(pos \\ bs ~= 0 or: [remaining < bs]) ifTrue: [
		n := bs - (pos \\ bs) min: remaining.
		block := self read: 1 blocksAt: pos // bs.
		aByteArray replaceFrom: dst to: dst + n - 1 with: block startingAt: pos \\ bs + 1.
		pos := pos + n.
		dst := dst + n.
		remaining := remaining - n].
	n := remaining // bs.
	n > 0 ifTrue: [
		self read: n blocksAt: pos // bs into: aByteArray startingAt: dst.
		pos := pos + (n * bs).
		dst := dst + (n * bs).
		remaining := remaining - (n * bs)].
	remaining > 0 ifTrue: [
		block := self read: 1 blocksAt: pos // bs.
		aByteArray replaceFrom: dst to: dst + remaining - 1 with: block startingAt: 1].
	^aByteArray
! !

!BlockDevice methodsFor: 'closing'!
close
	"Release what the device holds."
! !

!BlockDevice methodsFor: 'private'!
checkBlocks: count at: lba
	"Signal FileError unless the count blocks from lba on are on the device."
	(count >= 0 and: [lba >= 0 and: [lba + count <= self blockCount]]) ifFalse: [
		^FileError signal: 'Blocks ', lba printString, '+', count printString, ' are not on ', self printString path: self printString]
!
checkBytes: count at: byteOffset
	(count >= 0 and: [byteOffset >= 0 and: [byteOffset + count <= self size]]) ifFalse: [
		^FileError signal: 'Bytes ', byteOffset printString, '+', count printString, ' are not on ', self printString path: self printString]
! !
