Object subclass: #MountTableTestFile
	instanceVariableNames: 'stat name position writable'
	classVariableNames: ''
	package: 'Tests-Kernel'!

MountTableTestFile comment: 'I am a file of MountTableTestWritableVolume, open: what a writable volume answers to open:mode: (as FirmwareFile), over its MountTableTestStat''s bytes.'!

!MountTableTestFile methodsFor: 'initialization'!
setStat: aStat name: aPath position: anInteger writable: aBoolean
	stat := aStat.
	name := aPath.
	position := anInteger.
	writable := aBoolean
! !

!MountTableTestFile methodsFor: 'accessing'!
size
	^stat size
!
position
	^position
!
position: anInteger
	position := anInteger
! !

!MountTableTestFile methodsFor: 'reading and writing'!
readInto: aByteArray startingAt: start count: count
	| n |
	n := (stat size - position min: count) max: 0.
	aByteArray replaceFrom: start to: start + n - 1 with: stat bytes startingAt: position + 1.
	position := position + n.
	^n
!
writeFrom: aByteArray startingAt: start count: count
	| bytes |
	writable ifFalse: [^FileError signal: 'File not open for writing: ', name path: name].
	bytes := stat bytes.
	position + count > bytes size ifTrue: [bytes := (ByteArray new: position + count) replaceFrom: 1 to: bytes size with: bytes startingAt: 1; yourself].
	bytes replaceFrom: position + 1 to: position + count with: aByteArray startingAt: start.
	stat bytes: bytes.
	position := position + count.
	^count
!
flush
!
close
	stat := nil
! !

!MountTableTestFile class methodsFor: 'instance creation'!
on: aStat name: aPath position: anInteger writable: aBoolean
	^self new setStat: aStat name: aPath position: anInteger writable: aBoolean
! !
