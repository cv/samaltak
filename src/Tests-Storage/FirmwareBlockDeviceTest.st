TestCase subclass: #FirmwareBlockDeviceTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Storage'!

FirmwareBlockDeviceTest comment: 'FirmwareBlockDevice withoutImageStores: (what all leaves out) on stubs: the store, its disk and a whole-disk store''s partitions go, the store''s sibling partitions (make usb-image''s ext4 volume) and other disks stay.'!

!FirmwareBlockDeviceTest methodsFor: 'tests'!
testStorePartitionHidesItsDiskNotItsSiblings
	| disk esp store files other kept |
	disk := FirmwareBlockDeviceTestStub path: #[1 1] partition: nil.
	esp := FirmwareBlockDeviceTestStub path: #[1 1] partition: 1.
	store := (FirmwareBlockDeviceTestStub path: #[1 1] partition: 2) beStore.
	files := FirmwareBlockDeviceTestStub path: #[1 1] partition: 3.
	other := FirmwareBlockDeviceTestStub path: #[2 2] partition: nil.
	kept := FirmwareBlockDevice withoutImageStores: {disk. esp. store. files. other}.
	self assert: kept asArray equals: {esp. files. other}
!
testWholeDiskStoreHidesItsPartitions
	| store ghost other kept |
	store := (FirmwareBlockDeviceTestStub path: #[1 1] partition: nil) beStore.
	ghost := FirmwareBlockDeviceTestStub path: #[1 1] partition: 1.
	other := FirmwareBlockDeviceTestStub path: #[2 2] partition: 1.
	kept := FirmwareBlockDevice withoutImageStores: {store. ghost. other}.
	self assert: kept asArray equals: {other}
!
testNoStoreKeepsEverything
	| devices |
	devices := {FirmwareBlockDeviceTestStub path: #[1 1] partition: nil. FirmwareBlockDeviceTestStub path: #[1 1] partition: 1}.
	self assert: (FirmwareBlockDevice withoutImageStores: devices) asArray equals: devices
! !
