Object subclass: #FirmwareVolumes
	instanceVariableNames: ''
	classVariableNames: 'Problems'
	package: 'System-Storage'!

FirmwareVolumes comment: 'I give File, FileStream and Directory the machine''s ext4 volumes on UEFI, which has no files of its own: at each start there I install a MountTable that covers every path (File mountTable:), read-only, and on its first use look for the volumes: every disk and partition of the firmware (FirmwareBlockDevice all, so never the disk with the image) whose superblock has ext4''s magic is an Ext4Volume.

Layout: each volume at /mnt/<name>, in the firmware''s order of its devices, and the first one also at / (so /etc/hostname is the first volume''s and /mnt lists them all). <name> is the volume''s label, else its GPT partition''s name, else volume<n> (n counting the volumes from 1); a / or control character becomes _, and a name taken already gets -2, -3, .... On an operating system I install nothing (and drop a table from UEFI that a snapshot brought along).

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
	"Mount the ext4 volumes of the firmware's block devices."
	| found |
	Problems := OrderedCollection new.
	found := OrderedCollection new.
	FirmwareBlockDevice all do: [:device |
		[(self isExt4: device) ifTrue: [| volume |
			volume := Ext4Volume on: device.
			found add: volume -> (volume label ifEmpty: [device partitionName])]]
			on: Error do: [:e | Problems add: device printString, ': ', e messageText. e return: nil]].
	self mount: found asArray on: aMountTable
!
mount: volumesAndNames on: aMountTable
	"Mount the volumes (volume -> name or nil) on aMountTable: each at /mnt/<name>, the first also at /."
	| points |
	points := self mountPointsFor: (volumesAndNames collect: [:each | each value]).
	volumesAndNames isEmpty ifFalse: [aMountTable mount: volumesAndNames first key at: '/'].
	volumesAndNames with: points do: [:each :point | aMountTable mount: each key at: point]
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
