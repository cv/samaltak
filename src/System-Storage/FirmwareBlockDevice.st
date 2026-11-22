BlockDevice subclass: #FirmwareBlockDevice
	instanceVariableNames: 'firmware handle blockIo devicePath partition buffer bufferBytes lock'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareBlockDevice comment: 'I am a disk or a partition of the machine on UEFI, read through the firmware''s Block I/O protocol (UEFI 2.10, 13.9): the firmware has a handle for each disk its drivers (NVMe, virtio, USB mass storage, AHCI) found, and a child handle for each GPT or MBR partition on one (isLogicalPartition). I only read: a read goes through a buffer outside the object heap aligned to the medium''s IoAlign, at most bufferBytes at a time. The medium (blockSize, blockCount, isReadOnly, isRemovable, mediaId) is read from the firmware at each use, so a changed medium shows. A partition''s table entry comes from its EFI_PARTITION_INFO_PROTOCOL (partitionType #gpt, #mbr or #other, partitionName and partitionTypeGuid of a GPT entry, mbrType of an MBR one), its number from its device path (partitionNumber); description is the firmware''s text of the device path, e.g. PciRoot(0x0)/Pci(0x2,0x0)/NVMe(0x1,...)/HD(1,GPT,...).

FirmwareBlockDevice all answers every disk and partition with a medium except the image store (UefiImageStore: a disk or partition that starts with SAMSTORE), the disk it is a partition of, and the partitions of a whole disk that is one: nothing here reads past their first block. The other partitions of a store''s disk are there (make usb-image puts an ext4 volume next to the store on the boot stick). On an operating system there are none. Read errors signal FileError. My memory and handles are the firmware''s: they do not survive a snapshot (FirmwareVolumes mounts afresh at each start).

	FirmwareBlockDevice all collect: [:d | d printString]'!

!FirmwareBlockDevice class methodsFor: 'guids'!
blockIoGuid
	"EFI_BLOCK_IO_PROTOCOL"
	^'964e5b21-6459-11d2-8e39-00a0c969723b'
!
devicePathGuid
	"EFI_DEVICE_PATH_PROTOCOL"
	^'09576e91-6d3f-11d2-8e39-00a0c969723b'
!
partitionInfoGuid
	"EFI_PARTITION_INFO_PROTOCOL"
	^'8cf2f62c-bc9b-4821-808d-ec9ec421a1a0'
!
devicePathToTextGuid
	"EFI_DEVICE_PATH_TO_TEXT_PROTOCOL"
	^'8b843e20-8132-4852-90cc-551a4e4a7f1c'
! !

!FirmwareBlockDevice class methodsFor: 'finding'!
all
	"The firmware's disks and partitions with a medium, in its order, but the image store, the disk it is on and, if it is a whole disk, its partitions; none without a firmware."
	| firmware devices |
	firmware := Firmware current.
	firmware isNil ifTrue: [^#()].
	devices := (firmware handlesSupporting: self blockIoGuid)
		collect: [:h | self firmware: firmware handle: h].
	devices := devices select: [:d | d notNil and: [d isMediaPresent and: [d blockSize > 0]]].
	^self withoutImageStores: devices
!
withoutImageStores: devices
	"devices without the image stores among them, the disks a store is a partition of, and the partitions of a disk that is a store."
	| stores hidden |
	stores := devices select: [:d | d isImageStore].
	hidden := OrderedCollection new.
	stores do: [:d | hidden add: d devicePath; add: d diskPath].
	^(devices reject: [:d | (hidden includes: d devicePath) or: [stores anySatisfy: [:s | s isLogicalPartition not and: [s devicePath = d diskPath]]]]) asArray
!
firmware: aFirmware handle: aHandle
	"The device behind aHandle, or nil if it has no Block I/O."
	^(aFirmware protocol: self blockIoGuid on: aHandle) ifNotNil: [:bio | self new setFirmware: aFirmware handle: aHandle blockIo: bio]
! !

!FirmwareBlockDevice methodsFor: 'initialization'!
setFirmware: aFirmware handle: aHandle blockIo: anAddress
	firmware := aFirmware.
	handle := aHandle.
	blockIo := anAddress.
	lock := Semaphore forMutualExclusion.
	devicePath := (firmware protocol: self class devicePathGuid on: handle)
		ifNil: [ByteArray new]
		ifNotNil: [:p | self devicePathBytesAt: p].
	partition := firmware protocol: self class partitionInfoGuid on: handle
! !

!FirmwareBlockDevice methodsFor: 'medium'!
media
	"EFI_BLOCK_IO_MEDIA."
	^Machine uint64At: blockIo + 8
!
mediaId
	^Machine uint32At: self media
!
isRemovable
	^(Machine uint8At: self media + 4) ~= 0
!
isMediaPresent
	^(Machine uint8At: self media + 5) ~= 0
!
isLogicalPartition
	"Is this a partition of a disk (the firmware's child of the disk's handle)?"
	^(Machine uint8At: self media + 6) ~= 0
!
isReadOnly
	"Is the medium write-protected? (I never write.)"
	^(Machine uint8At: self media + 7) ~= 0
!
blockSize
	^Machine uint32At: self media + 12
!
ioAlign
	"The alignment the medium needs of a buffer, in bytes (0 and 1: none)."
	^Machine uint32At: self media + 16
!
blockCount
	^(Machine uint64At: self media + 24) + 1
!
byteSize
	^self blockCount * self blockSize
! !

!FirmwareBlockDevice methodsFor: 'reading'!
read: count blocksAt: lba into: bytes startingAt: index
	"Read count blocks from block lba on into bytes from index on; answer bytes."
	| size done n status |
	self checkBlocks: count at: lba.
	size := self blockSize.
	count = 0 ifTrue: [^bytes].
	lock critical: [
		self ensureBuffer.
		done := 0.
		[done < count] whileTrue: [
			n := count - done min: bufferBytes // size.
			status := Machine call: (Machine uint64At: blockIo + 24) with: blockIo with: self mediaId with: lba + done with: n * size with: buffer.
			(firmware isError: status) ifTrue: [
				^FileError signal: 'Block I/O failed (status 16r', (status printString: 16), ') reading block ', (lba + done) printString, ' of ', self description path: self description].
			Machine copy: n * size from: buffer at: 0 to: bytes at: index - 1 + (done * size).
			done := done + n]].
	^bytes
!
bufferSize
	"The most one firmware call reads."
	^256 * 1024
!
ensureBuffer
	"A buffer outside the heap of whole blocks, aligned as the medium needs; kept."
	| align raw |
	buffer notNil ifTrue: [^self].
	align := self ioAlign max: 8.
	bufferBytes := self bufferSize // self blockSize max: 1.
	bufferBytes := bufferBytes * self blockSize.
	raw := Machine allocate: bufferBytes + align.
	buffer := raw + align - 1 // align * align
! !

!FirmwareBlockDevice methodsFor: 'identifying'!
handle
	^handle
!
devicePath
	"The bytes of my device path, its nodes up to (not with) its end node."
	^devicePath
!
diskPath
	"The device path of the disk I am on (mine without its partition node)."
	| i |
	i := 1.
	[i + 3 <= devicePath size] whileTrue: [| len |
		((devicePath at: i) = 4 and: [(devicePath at: i + 1) between: 1 and: 2]) ifTrue: [^devicePath copyFrom: 1 to: i - 1].
		len := (devicePath at: i + 2) + ((devicePath at: i + 3) * 256).
		len < 4 ifTrue: [^devicePath].
		i := i + len].
	^devicePath
!
partitionNumber
	"The number of my partition on its disk (from 1; GPT entry or MBR slot), or nil for a whole disk."
	| i |
	i := 1.
	[i + 7 <= devicePath size] whileTrue: [| len |
		((devicePath at: i) = 4 and: [(devicePath at: i + 1) = 1]) ifTrue: [
			^(devicePath at: i + 4) + ((devicePath at: i + 5) << 8) + ((devicePath at: i + 6) << 16) + ((devicePath at: i + 7) << 24)].
		len := (devicePath at: i + 2) + ((devicePath at: i + 3) * 256).
		len < 4 ifTrue: [^nil].
		i := i + len].
	^nil
!
partitionType
	"#gpt or #mbr for a partition the firmware describes, #other, or nil without the partition information."
	partition isNil ifTrue: [^nil].
	^#(#other #mbr #gpt) at: ((Machine uint32At: partition + 4) min: 2) + 1
!
partitionName
	"A GPT partition's name, else nil."
	self partitionType == #gpt ifFalse: [^nil].
	^self class utf16At: partition + 16 + 56 maxCharacters: 36
!
partitionTypeGuid
	"A GPT partition's type GUID as text (Linux file systems: 0fc63daf-8483-4772-8e79-3d69d8477de4), else nil."
	self partitionType == #gpt ifFalse: [^nil].
	^self class guidAt: partition + 16
!
mbrType
	"An MBR partition's type byte (16r83: Linux), else nil."
	self partitionType == #mbr ifFalse: [^nil].
	^Machine uint8At: partition + 16 + 4
!
description
	"The firmware's text for my device path, or the bytes in hex without its protocol for that."
	| toText text |
	toText := firmware locateProtocol: self class devicePathToTextGuid.
	(toText isNil or: [devicePath isEmpty]) ifTrue: [^'device path ', devicePath hex].
	text := lock critical: [| path |
		path := Machine allocate: devicePath size + 4.
		Machine bytesAt: path put: devicePath.
		Machine bytesAt: path + devicePath size put: #[16r7F 16rFF 4 0].
		[| p | p := Machine call: (Machine uint64At: toText + 8) with: path with: 0 with: 0.
		p = 0 ifTrue: [nil] ifFalse: [[self class utf16At: p maxCharacters: 4096] ensure: [firmware freePool: p]]]
			ensure: [Machine free: path]].
	^text ifNil: ['device path ', devicePath hex]
!
isImageStore
	"Does the medium start with UefiImageStore's superblock? (Only its first block is read.)"
	^[((self read: 1 blocksAt: 0) copyFrom: 1 to: 8) = 'SAMSTORE' asByteArray] on: FileError do: [:e | e return: false]
! !

!FirmwareBlockDevice methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FirmwareBlockDevice('; nextPutAll: self description; nextPutAll: ', '; print: self blockCount; nextPutAll: ' x '; print: self blockSize.
	self partitionName ifNotNil: [:n | n isEmpty ifFalse: [aStream nextPutAll: ', '; print: n]].
	aStream nextPut: $)
! !

!FirmwareBlockDevice methodsFor: 'private'!
devicePathBytesAt: anAddress
	"The nodes of the device path at anAddress up to its end node (at most 4 KB)."
	| p len |
	p := anAddress.
	[(Machine uint8At: p) ~= 16r7F and: [p - anAddress < 4096]] whileTrue: [
		len := Machine uint16At: p + 2.
		len < 4 ifTrue: [^Machine bytesAt: anAddress count: p - anAddress].
		p := p + len].
	^Machine bytesAt: anAddress count: p - anAddress
! !

!FirmwareBlockDevice class methodsFor: 'private'!
utf16At: anAddress maxCharacters: n
	"The UCS-2 text at anAddress up to its NUL or n characters."
	^String streamContents: [:s |
		0 to: n - 1 do: [:i | | c |
			c := Machine uint16At: anAddress + (2 * i).
			c = 0 ifTrue: [^s contents].
			s nextPut: (Character value: c)]]
!
guidAt: anAddress
	"The EFI_GUID at anAddress as text."
	| hex |
	hex := [:value :digits | (value printString: 16) asLowercase padLeftTo: digits with: $0].
	^String streamContents: [:s |
		s nextPutAll: (hex value: (Machine uint32At: anAddress) value: 8); nextPut: $-;
			nextPutAll: (hex value: (Machine uint16At: anAddress + 4) value: 4); nextPut: $-;
			nextPutAll: (hex value: (Machine uint16At: anAddress + 6) value: 4); nextPut: $-.
		8 to: 15 do: [:i |
			i = 10 ifTrue: [s nextPut: $-].
			s nextPutAll: (hex value: (Machine uint8At: anAddress + i) value: 2)]]
! !
