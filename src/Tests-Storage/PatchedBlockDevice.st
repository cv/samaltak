BlockDevice subclass: #PatchedBlockDevice
	instanceVariableNames: 'device patches'
	classVariableNames: ''
	package: 'Tests-Storage'!

PatchedBlockDevice comment: 'I read another BlockDevice with some of its bytes replaced (patches: byte offset -> byte), for tests of damaged and unsupported file systems.'!

!PatchedBlockDevice methodsFor: 'accessing'!
blockSize
	^device blockSize
!
blockCount
	^device blockCount
!
at: byteOffset put: aByte
	patches at: byteOffset put: aByte
!
at: byteOffset putUint32: anInteger
	0 to: 3 do: [:i | patches at: byteOffset + i put: ((anInteger bitShift: i * -8) bitAnd: 255)]
!
uint32At: byteOffset
	"Answer the patched little-endian 32-bit word at byteOffset."
	^(self readBytes: 4 at: byteOffset) uint32At: 1
! !

!PatchedBlockDevice methodsFor: 'reading'!
read: count blocksAt: lba into: aByteArray startingAt: index
	| start stop |
	device read: count blocksAt: lba into: aByteArray startingAt: index.
	start := lba * self blockSize.
	stop := start + (count * self blockSize).
	patches keysAndValuesDo: [:offset :byte |
		(offset >= start and: [offset < stop]) ifTrue: [aByteArray at: index + offset - start put: byte]].
	^aByteArray
! !

!PatchedBlockDevice methodsFor: 'closing'!
close
	device close
! !

!PatchedBlockDevice methodsFor: 'private'!
setDevice: aBlockDevice
	device := aBlockDevice.
	patches := Dictionary new
! !

!PatchedBlockDevice class methodsFor: 'instance creation'!
on: aBlockDevice
	^self new setDevice: aBlockDevice
! !
