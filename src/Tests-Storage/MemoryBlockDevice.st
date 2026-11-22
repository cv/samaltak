BlockDevice subclass: #MemoryBlockDevice
	instanceVariableNames: 'bytes blockSize flushes'
	classVariableNames: ''
	package: 'Tests-Storage'!

MemoryBlockDevice comment: 'I am a writable disk in a ByteArray, for tests of what writes disks (GptDisk, SamaltakInstaller): MemoryBlockDevice blocks: 131072 size: 512. flushes counts flush.'!

!MemoryBlockDevice class methodsFor: 'instance creation'!
blocks: n size: bs
	^self on: (ByteArray new: n * bs) blockSize: bs
!
on: aByteArray blockSize: bs
	^self new setBytes: aByteArray blockSize: bs
! !

!MemoryBlockDevice methodsFor: 'initialization'!
setBytes: aByteArray blockSize: bs
	bytes := aByteArray.
	blockSize := bs.
	flushes := 0
! !

!MemoryBlockDevice methodsFor: 'accessing'!
bytes
	^bytes
!
blockSize
	^blockSize
!
blockCount
	^bytes size // blockSize
!
isReadOnly
	^false
!
flushes
	^flushes
! !

!MemoryBlockDevice methodsFor: 'reading and writing'!
read: count blocksAt: lba into: aByteArray startingAt: index
	self checkBlocks: count at: lba.
	aByteArray replaceFrom: index to: index + (count * blockSize) - 1 with: bytes startingAt: lba * blockSize + 1.
	^aByteArray
!
write: count blocksAt: lba from: aByteArray startingAt: index
	self checkBlocks: count at: lba.
	bytes replaceFrom: lba * blockSize + 1 to: (lba + count) * blockSize with: aByteArray startingAt: index.
	^aByteArray
!
flush
	flushes := flushes + 1
! !
