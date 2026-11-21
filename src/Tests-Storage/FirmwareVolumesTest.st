TestCase subclass: #FirmwareVolumesTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Storage'!

FirmwareVolumesTest comment: 'Tests FirmwareVolumes'' probing and layout with block devices in memory (FirmwareVolumesTestDevice), and FirmwareBlockDevice where there is no firmware.'!

!FirmwareVolumesTest methodsFor: 'helpers'!
deviceWithLabel: aString blockSize: n
	"A device of 64 KB whose superblock at byte 1024 has ext4's magic and the label."
	| bytes |
	bytes := ByteArray new: 65536.
	bytes at: 1024 + 57 put: 16r53; at: 1024 + 58 put: 16rEF.
	bytes at: 1024 + 25 put: 2.
	bytes replaceFrom: 1024 + 121 to: 1024 + 120 + aString utf8Encoded size with: aString utf8Encoded startingAt: 1.
	^FirmwareVolumesTestDevice bytes: bytes blockSize: n
! !

!FirmwareVolumesTest methodsFor: 'tests'!
testProbe
	#(512 1024 4096) do: [:n | self assert: (FirmwareVolumes isExt4: (self deviceWithLabel: 'root' blockSize: n))].
	self deny: (FirmwareVolumes isExt4: (FirmwareVolumesTestDevice bytes: (ByteArray new: 65536) blockSize: 512)).
	self deny: (FirmwareVolumes isExt4: (FirmwareVolumesTestDevice bytes: (ByteArray new: 1024) blockSize: 512))
!
testMountPoints
	self assert: (FirmwareVolumes mountPointsFor: #('root' nil 'data' 'root' '' 'a/b' '..' 'root'))
		= #('/mnt/root' '/mnt/volume2' '/mnt/data' '/mnt/root-2' '/mnt/volume5' '/mnt/a_b' '/mnt/volume7' '/mnt/root-3')
!
testLayout
	"The first volume at / and each at /mnt/<name>."
	| table a b |
	a := Object new.
	b := Object new.
	table := MountTable new coversEverything: true; yourself.
	FirmwareVolumes mount: {a -> 'root'. b -> nil} on: table.
	self assert: (table mounts collect: [:m | m key]) = #('/' '/mnt/root' '/mnt/volume2').
	self assert: (table volumeAt: '/') == a.
	self assert: (table volumeAt: '/mnt/volume2') == b.
	table := MountTable new coversEverything: true; yourself.
	FirmwareVolumes mount: #() on: table.
	self assert: table mounts isEmpty.
	self assert: (table entries: '/') isEmpty
!
testNoFirmware
	Machine hasFirmware ifTrue: [^self].
	self assert: FirmwareBlockDevice all = #()
!
testInstalledOnFirmware
	"On UEFI every path is the mount table's."
	self assert: (File mountTable notNil and: [File mountTable coversEverything]) = Machine hasFirmware
! !
