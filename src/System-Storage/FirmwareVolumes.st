Object subclass: #FirmwareVolumes
	instanceVariableNames: ''
	classVariableNames: 'Problems'
	package: 'System-Storage'!

FirmwareVolumes comment: 'I give File, FileStream and Directory the machine''s volumes on UEFI, which has no files of its own: at each start there I install a MountTable that covers every path (File mountTable:), and on its first use look for the volumes: every disk and partition of the firmware (FirmwareBlockDevice all, so never the image store or its disk) whose superblock has ext4''s magic is an Ext4Volume, read-only; every file system the firmware has a driver for (FirmwareFileSystem all: FAT, the EFI system partition and USB sticks) is readable and writable.

Layout: the boot volume (the FAT file system with samaltak.args: the EFI system partition the VM was loaded from, where crash reports go: docs/uefi.md) at /esp; each other volume at /mnt/<name>, the ext4 ones first, in the firmware''s order of its devices, and the first ext4 one also at / (so /etc/hostname is the first ext4 volume''s and /mnt lists the others). <name> is the volume''s label, else its GPT partition''s name (ext4), else volume<n> (n counting the volumes from 1); a / or control character becomes _, and a name taken already gets -2, -3, .... On an operating system I install nothing (and drop a table from UEFI that a snapshot brought along).

	FirmwareVolumes mounts		"(File mountTable mounts) the mount points -> their volumes"
	FirmwareVolumes problems	"devices with ext4''s magic that did not mount, and why"'!

!FirmwareVolumes class methodsFor: 'system startup'!
initialize
	Smalltalk addToStartUpList: self
!
startUp: resuming
	Machine hasFirmware
		ifTrue: [File mountTable: self newMountTable]
		ifFalse: [(File mountTable notNil and: [File mountTable coversEverything]) ifTrue: [File mountTable: nil]]
! !

!FirmwareVolumes class methodsFor: 'accessing'!
newMountTable
	"A table of every path, which mounts the firmware's ext4 volumes on its first use."
	^MountTable new coversEverything: true; loader: [:table | self mountOn: table]; yourself
!
mounts
	^File mountTable isNil ifTrue: [#()] ifFalse: [File mountTable mounts]
!
problems
	^Problems ifNil: [#()]
! !

!FirmwareVolumes class methodsFor: 'mounting'!
mountOn: aMountTable
	"Mount the ext4 volumes of the firmware's block devices and its file systems."
	| found fileSystems boot |
	Problems := OrderedCollection new.
	found := OrderedCollection new.
	FirmwareBlockDevice all do: [:device |
		[(self isExt4: device) ifTrue: [| volume |
			volume := Ext4Volume on: device.
			found add: volume -> (volume label ifEmpty: [device partitionName])]]
			on: Error do: [:e | Problems add: device printString, ': ', e messageText. e return: nil]].
	fileSystems := [FirmwareFileSystem all] on: Error do: [:e | Problems add: 'file systems: ', e messageText. e return: #()].
	boot := fileSystems detect: [:each | each isBootVolume] ifNone: [nil].
	self mount: found asArray
		fileSystems: ((fileSystems reject: [:each | each == boot]) collect: [:each | each -> each label]) asArray
		boot: boot
		on: aMountTable
!
mount: volumesAndNames on: aMountTable
	"Mount the volumes (volume -> name or nil) on aMountTable: each at /mnt/<name>, the first also at /."
	self mount: volumesAndNames fileSystems: #() boot: nil on: aMountTable
!
mount: volumesAndNames fileSystems: fileSystemsAndNames boot: aVolumeOrNil on: aMountTable
	"Mount the boot volume at /esp, and the volumes, then the file systems (volume -> name or nil) each at /mnt/<name>, the first volume also at /."
	| all points |
	all := volumesAndNames, fileSystemsAndNames.
	points := self mountPointsFor: (all collect: [:each | each value]).
	volumesAndNames isEmpty ifFalse: [aMountTable mount: volumesAndNames first key at: '/'].
	aVolumeOrNil isNil ifFalse: [aMountTable mount: aVolumeOrNil at: '/esp'].
	all with: points do: [:each :point | aMountTable mount: each key at: point]
!
mountPointsFor: names
	"The mount points of volumes with these names (Strings, or nil for none), in order."
	| taken |
	taken := Set new.
	^(1 to: names size) collect: [:i | | name candidate n |
		name := self safeName: (names at: i).
		name isNil ifTrue: [name := 'volume', i printString].
		candidate := name.
		n := 1.
		[taken includes: candidate] whileTrue: [
			n := n + 1.
			candidate := name, '-', n printString].
		taken add: candidate.
		'/mnt/', candidate]
!
safeName: aStringOrNil
	"aString as one path component (/ and control characters _), or nil if nothing is left."
	| name |
	aStringOrNil isNil ifTrue: [^nil].
	name := aStringOrNil collect: [:c | (c = $/ or: [c value < 32]) ifTrue: [$_] ifFalse: [c]].
	(name isEmpty or: [name = '.' or: [name = '..']]) ifTrue: [^nil].
	^name
! !

!FirmwareVolumes class methodsFor: 'probing'!
superblockOf: aBlockDevice
	"The 1024 bytes of an ext4 superblock, at byte 1024 of the device, or nil if it is too small."
	aBlockDevice size < 2048 ifTrue: [^nil].
	^aBlockDevice readBytes: 1024 at: 1024
!
isExt4: aBlockDevice
	"Has aBlockDevice the superblock of an ext2, ext3 or ext4 file system (its magic 16rEF53 and a block size of 1 to 64 KB)?"
	| sb |
	sb := self superblockOf: aBlockDevice.
	sb isNil ifTrue: [^false].
	^(sb at: 57) + ((sb at: 58) << 8) = 16rEF53
		and: [((sb at: 25) + ((sb at: 26) << 8) + ((sb at: 27) << 16) + ((sb at: 28) << 24)) <= 6]
! !
