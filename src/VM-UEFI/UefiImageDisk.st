Object subclass: #UefiImageDisk
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiImageDisk comment: 'I write an image store (UefiImageStore) with an image in slot 0: the superblock, slot 0''s header with sequence 1, the image at 1 MB. Copied to the start of a partition or a disk at least twice the image''s size plus 1 MB (make uefi extends it to UEFI_DISK_MB), it is where the VM on UEFI loads disk: from and snapshots to.

	UefiImageDisk new write: ''build/samaltak.image'' to: ''build/uefi/image.disk'''!

!UefiImageDisk methodsFor: 'writing'!
write: imagePath to: diskPath
	| image out |
	image := File readBytes: imagePath.
	out := ByteArray new: 16r100000 + image size.
	out replaceFrom: 1 to: 8 with: 'SAMSTORE' asByteArray startingAt: 1.
	out replaceFrom: 4097 to: 4104 with: 'SAMSLOT1' asByteArray startingAt: 1.
	self put64: 1 into: out at: 4105.
	self put64: image size into: out at: 4113.
	self put64: (UefiImageStore slotCheckOf: 1 length: image size) into: out at: 4121.
	out replaceFrom: 16r100001 to: out size with: image startingAt: 1.
	File writeBytes: out to: diskPath.
	^diskPath
!
put64: anInteger into: aByteArray at: index
	0 to: 7 do: [:i | aByteArray at: index + i put: ((anInteger bitShift: -8 * i) bitAnd: 255)]
! !
