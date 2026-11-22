Object subclass: #FirmwareBlockDeviceTestStub
	instanceVariableNames: 'disk partition store'
	classVariableNames: ''
	package: 'Tests-Storage'!

FirmwareBlockDeviceTestStub comment: 'A FirmwareBlockDevice as FirmwareBlockDevice withoutImageStores: sees one: a device path (its disk''s bytes, then a partition node for a partition), whether it is a partition, whether it starts with the store''s superblock.'!

!FirmwareBlockDeviceTestStub class methodsFor: 'instance creation'!
path: diskBytes partition: aNumberOrNil
	^self new setDisk: diskBytes partition: aNumberOrNil
! !

!FirmwareBlockDeviceTestStub methodsFor: 'initialization'!
setDisk: diskBytes partition: aNumberOrNil
	disk := diskBytes.
	partition := aNumberOrNil.
	store := false
!
beStore
	store := true
! !

!FirmwareBlockDeviceTestStub methodsFor: 'accessing'!
devicePath
	partition isNil ifTrue: [^disk].
	^disk, (ByteArray with: 4 with: 1 with: 8 with: 0), (ByteArray with: partition with: 0 with: 0 with: 0)
!
diskPath
	^disk
!
isLogicalPartition
	^partition notNil
!
isImageStore
	^store
! !
