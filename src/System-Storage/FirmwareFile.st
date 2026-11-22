Object subclass: #FirmwareFile
	instanceVariableNames: 'volume file name size position writable'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareFile comment: 'I am a file of a FirmwareFileSystem, open (its EFI_FILE_PROTOCOL: file), as FirmwareFileSystem>>open:mode: answers me to MountTable: FileStream holds me where it holds a platform handle, and File''s handle primitives send me their operations (readInto:startingAt:count:, writeFrom:startingAt:count:, size, position, position:, flush, close). I keep the position and the size myself (writes past the end grow it); each read or write sets the firmware''s position first. Writing a file opened to read signals FileError.'!

!FirmwareFile methodsFor: 'initialization'!
setVolume: aVolume file: aFile name: aPath size: anInteger writable: aBoolean
	volume := aVolume.
	file := aFile.
	name := aPath.
	size := anInteger.
	position := 0.
	writable := aBoolean
! !

!FirmwareFile methodsFor: 'accessing'!
name
	^name
!
name: aPath
	"The path errors name (MountTable gives the whole one)."
	name := aPath
!
size
	^size
!
position
	^position
!
position: anInteger
	position := anInteger max: 0.
	^self
!
isWritable
	^writable
! !

!FirmwareFile methodsFor: 'reading and writing'!
readInto: aByteArray startingAt: start count: count
	"Read up to count bytes into aByteArray at start; answer how many (0 at the end)."
	| n done |
	self checkOpen.
	done := 0.
	[done < count and: [position < size]] whileTrue: [
		n := volume read: file at: position into: aByteArray startingAt: start + done count: (count - done min: size - position) path: name.
		n = 0 ifTrue: [^done].
		position := position + n.
		done := done + n].
	^done
!
writeFrom: aByteArray startingAt: start count: count
	"Write count bytes of aByteArray from start at my position; answer how many."
	| n |
	self checkOpen.
	writable ifFalse: [^FileError signal: 'File not open for writing: ', name path: name].
	n := volume write: file at: position from: aByteArray startingAt: start count: count path: name.
	position := position + n.
	size := size max: position.
	^n
!
flush
	file isNil ifFalse: [volume flush: file path: name]
!
close
	| f |
	file isNil ifTrue: [^self].
	f := file.
	file := nil.
	volume closeFile: f path: name
! !

!FirmwareFile methodsFor: 'private'!
checkOpen
	file isNil ifTrue: [^FileError signal: 'File is closed: ', name path: name]
! !

!FirmwareFile methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FirmwareFile('; nextPutAll: name; nextPut: $)
! !

!FirmwareFile class methodsFor: 'instance creation'!
on: aVolume handle: aFile name: aPath size: anInteger writable: aBoolean
	^self new setVolume: aVolume file: aFile name: aPath size: anInteger writable: aBoolean
! !
