Object subclass: #VolumeFile
	instanceVariableNames: 'file name size position'
	classVariableNames: ''
	package: 'System-Files'!

VolumeFile comment: 'I am a file of a mounted volume opened for reading (MountTable>>open:mode:): FileStream holds me where it holds a platform handle, and File''s handle primitives send me their operations. file is what the volume''s stat: answered (an Ext4Inode), which reads its bytes (readFrom:count:), name the path it was opened as; size is its size when it was opened (volumes are read-only). Writing signals FileError.'!

!VolumeFile methodsFor: 'initialization'!
setFile: aStat name: aPath
	file := aStat.
	name := aPath.
	size := aStat size.
	position := 0
! !

!VolumeFile methodsFor: 'accessing'!
file
	^file
!
name
	^name
!
size
	^size
!
position
	^position
!
position: anInteger
	position := anInteger.
	^self
! !

!VolumeFile methodsFor: 'reading and writing'!
readInto: aByteArray startingAt: start count: count
	"Read up to count bytes into aByteArray at start; answer how many (0 at the end)."
	| n bytes |
	file isNil ifTrue: [^FileError signal: 'File is closed: ', name path: name].
	n := (size - position min: count) max: 0.
	n = 0 ifTrue: [^0].
	bytes := file readFrom: position count: n.
	aByteArray replaceFrom: start to: start + bytes size - 1 with: bytes startingAt: 1.
	position := position + bytes size.
	^bytes size
!
writeFrom: aByteArray startingAt: start count: count
	^FileError signal: 'Read-only file system: ', name path: name
!
flush
	^self
!
close
	file := nil
! !

!VolumeFile methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a VolumeFile('; nextPutAll: name; nextPut: $)
! !

!VolumeFile class methodsFor: 'instance creation'!
on: aStat name: aPath
	^self new setFile: aStat name: aPath
! !
