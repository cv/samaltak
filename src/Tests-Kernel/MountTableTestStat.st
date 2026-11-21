Object subclass: #MountTableTestStat
	instanceVariableNames: 'data reads'
	classVariableNames: ''
	package: 'Tests-Kernel'!

MountTableTestStat comment: 'I am a file (data its bytes) or a directory (data nil) of MountTableTestVolume, and its stat: modified at 1700000000 s; reads counts readFrom:count:.'!

!MountTableTestStat methodsFor: 'accessing'!
setData: aByteArrayOrNil
	data := aByteArrayOrNil.
	reads := 0
!
isDirectory
	^data isNil
!
size
	^data isNil ifTrue: [0] ifFalse: [data size]
!
modificationTime
	^1700000000000000
!
readFrom: offset count: n
	reads := reads + 1.
	^data copyFrom: offset + 1 to: (offset + n min: data size)
!
reads
	^reads
! !

!MountTableTestStat class methodsFor: 'instance creation'!
data: aByteArrayOrNil
	^self new setData: aByteArrayOrNil
! !
