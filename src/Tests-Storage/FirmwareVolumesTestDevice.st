BlockDevice subclass: #FirmwareVolumesTestDevice
	instanceVariableNames: 'bytes blockSize'
	classVariableNames: ''
	package: 'Tests-Storage'!

FirmwareVolumesTestDevice comment: 'I am a block device in memory for FirmwareVolumesTest.'!

!FirmwareVolumesTestDevice methodsFor: 'accessing'!
setBytes: aByteArray blockSize: n
	bytes := aByteArray.
	blockSize := n
!
blockSize
	^blockSize
!
blockCount
	^bytes size // blockSize
!
read: count blocksAt: lba
	^bytes copyFrom: lba * blockSize + 1 to: lba + count * blockSize
! !

!FirmwareVolumesTestDevice class methodsFor: 'instance creation'!
bytes: aByteArray blockSize: n
	^self new setBytes: aByteArray blockSize: n
! !
