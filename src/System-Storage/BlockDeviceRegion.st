BlockDevice subclass: #BlockDeviceRegion
	instanceVariableNames: 'device first count'
	classVariableNames: ''
	package: 'System-Storage'!

BlockDeviceRegion comment: 'I am count blocks of another BlockDevice from block first on, as a device of their own: a partition of a disk whose new table the firmware has not read yet (the installer''s image store). Reads and writes outside me signal FileError before they reach the disk, so a writer of a partition cannot touch its neighbours.

	BlockDeviceRegion on: disk first: partition firstLba count: partition blockCount'!

!BlockDeviceRegion class methodsFor: 'instance creation'!
on: aBlockDevice first: firstBlock count: blocks
	(firstBlock >= 0 and: [blocks >= 0 and: [firstBlock + blocks <= aBlockDevice blockCount]]) ifFalse: [
		^FileError signal: 'Blocks ', firstBlock printString, '+', blocks printString, ' are not on ', aBlockDevice printString path: aBlockDevice printString].
	^self new setDevice: aBlockDevice first: firstBlock count: blocks
! !

!BlockDeviceRegion methodsFor: 'initialization'!
setDevice: aBlockDevice first: firstBlock count: blocks
	device := aBlockDevice.
	first := firstBlock.
	count := blocks
! !

!BlockDeviceRegion methodsFor: 'accessing'!
device
	^device
!
first
	^first
!
blockSize
	^device blockSize
!
blockCount
	^count
!
isReadOnly
	^device isReadOnly
! !

!BlockDeviceRegion methodsFor: 'reading and writing'!
read: n blocksAt: lba into: aByteArray startingAt: index
	self checkBlocks: n at: lba.
	^device read: n blocksAt: first + lba into: aByteArray startingAt: index
!
write: n blocksAt: lba from: aByteArray startingAt: index
	self checkBlocks: n at: lba.
	^device write: n blocksAt: first + lba from: aByteArray startingAt: index
!
flush
	device flush
! !

!BlockDeviceRegion methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a BlockDeviceRegion('; print: first; nextPutAll: '+'; print: count; nextPutAll: ' of '; print: device; nextPut: $)
! !
