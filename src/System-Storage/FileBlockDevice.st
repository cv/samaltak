BlockDevice subclass: #FileBlockDevice
	instanceVariableNames: 'path handle blockSize blockCount'
	classVariableNames: ''
	package: 'System-Storage'!

FileBlockDevice comment: 'I am a disk image file on the host as a read-only BlockDevice (System-Files'' primitives, so not on UEFI): FileBlockDevice on: ''build/disk.img'' (512-byte blocks) or on: path blockSize: n. A trailing partial block is not on the device. Reads go straight from the file into the caller''s ByteArray. Close me when done; one that is garbage collected open is closed by the finalization process (WeakRegistry).'!

!FileBlockDevice methodsFor: 'accessing'!
path
	^path
!
blockSize
	^blockSize
!
blockCount
	^blockCount
! !

!FileBlockDevice methodsFor: 'reading'!
read: count blocksAt: lba into: aByteArray startingAt: index
	| wanted done n |
	handle isNil ifTrue: [^FileError signal: 'Device is closed: ', path path: path].
	self checkBlocks: count at: lba.
	wanted := count * blockSize.
	(index >= 1 and: [index + wanted - 1 <= aByteArray size]) ifFalse: [^self error: 'Buffer too small'].
	(File primSeek: handle to: lba * blockSize) isNil ifTrue: [^File signalErrorFor: path].
	done := 0.
	[done < wanted] whileTrue: [
		n := File primRead: handle into: aByteArray startingAt: index + done count: wanted - done.
		n isNil ifTrue: [^File signalErrorFor: path].
		n = 0 ifTrue: [^FileError signal: 'Unexpected end of file: ', path path: path].
		done := done + n].
	^aByteArray
! !

!FileBlockDevice methodsFor: 'closing'!
close
	handle isNil ifTrue: [^self].
	File primClose: handle.
	handle := nil.
	WeakRegistry default remove: self
!
finalize
	"I am the executor of a collected FileBlockDevice (its shallow copy): close the file."
	self close
! !

!FileBlockDevice methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FileBlockDevice('; nextPutAll: path; nextPut: $)
! !

!FileBlockDevice methodsFor: 'private'!
setPath: aPath blockSize: anInteger
	| size |
	(anInteger isInteger and: [anInteger > 0]) ifFalse: [^self error: 'Bad block size: ', anInteger printString].
	path := aPath.
	blockSize := anInteger.
	handle := File primOpen: aPath mode: 0.
	handle isNil ifTrue: [
		^(File exists: aPath)
			ifTrue: [File signalErrorFor: aPath]
			ifFalse: [FileDoesNotExist signal: 'No such file: ', aPath path: aPath]].
	size := File primSize: handle.
	size isNil ifTrue: [File primClose: handle. handle := nil. ^File signalErrorFor: aPath].
	blockCount := size // blockSize.
	WeakRegistry default add: self executor: self shallowCopy
! !

!FileBlockDevice class methodsFor: 'instance creation'!
on: aPath
	"Answer a device of 512-byte blocks reading the file aPath."
	^self on: aPath blockSize: 512
!
on: aPath blockSize: anInteger
	^self new setPath: aPath blockSize: anInteger
! !
