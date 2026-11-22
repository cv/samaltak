Object subclass: #FirmwareFileStat
	instanceVariableNames: 'volume path size attributes modificationTime'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareFileStat comment: 'What a FirmwareFileSystem says of a file or directory (its EFI_FILE_INFO): size, attributes (EFI_FILE_DIRECTORY 16r10, EFI_FILE_READ_ONLY 1, ...), modificationTime in UTC microseconds; readFrom:count: reads its bytes (the volume protocol of MountTable).'!

!FirmwareFileStat methodsFor: 'initialization'!
setVolume: aVolume size: anInteger attributes: bits modificationTime: us
	volume := aVolume.
	size := anInteger.
	attributes := bits.
	modificationTime := us
!
path: aPath
	path := aPath
! !

!FirmwareFileStat methodsFor: 'accessing'!
isDirectory
	^(attributes bitAnd: 16r10) ~= 0
!
isReadOnly
	^(attributes bitAnd: 1) ~= 0
!
size
	^self isDirectory ifTrue: [0] ifFalse: [size]
!
attributes
	^attributes
!
modificationTime
	^modificationTime
!
readFrom: offset count: n
	"Up to n of my bytes from the 0-based offset."
	^(volume open: path mode: 0) in: [:f |
		[| bytes got |
			f position: offset.
			bytes := ByteArray new: n.
			got := f readInto: bytes startingAt: 1 count: n.
			got = n ifTrue: [bytes] ifFalse: [bytes copyFrom: 1 to: got]] ensure: [f close]]
! !

!FirmwareFileStat class methodsFor: 'instance creation'!
volume: aVolume size: anInteger attributes: bits modificationTime: us
	^self new setVolume: aVolume size: anInteger attributes: bits modificationTime: us
! !
