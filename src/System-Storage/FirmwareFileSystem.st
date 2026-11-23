Object subclass: #FirmwareFileSystem
	instanceVariableNames: 'firmware handle fs root lock buffer info infoBytes label readOnly'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareFileSystem comment: 'I am a volume the firmware has a file system driver for (EFI_SIMPLE_FILE_SYSTEM_PROTOCOL, UEFI 2.10, 13.4; its files EFI_FILE_PROTOCOL, 13.5): on UEFI that is FAT, the EFI system partition and USB sticks. FirmwareVolumes mounts me in File''s MountTable, readable and writable: I answer the volume protocol (stat:, entriesAt:) and the writing one (open:mode:, delete:, rename:to:, createDirectory:), paths absolute within me (/ is my root; on the medium \ separates names, case-insensitively). A file opened on me is a FirmwareFile (an open EFI_FILE_PROTOCOL).

Errors are FileError with the firmware''s reason: FileDoesNotExist (EFI_NOT_FOUND), Read-only file system (EFI_WRITE_PROTECTED, or the volume says it is read-only), No space left on device (EFI_VOLUME_FULL), Permission denied (EFI_ACCESS_DENIED), ... The firmware''s calls go through one buffer outside the heap (bufferSize at a time) under my lock. My handles are the firmware''s: they do not survive a snapshot (FirmwareVolumes mounts afresh at each start).

	FirmwareFileSystem all collect: [:v | v label -> v freeSpace]'!

!FirmwareFileSystem class methodsFor: 'guids'!
simpleFileSystemGuid
	"EFI_SIMPLE_FILE_SYSTEM_PROTOCOL"
	^'964e5b22-6459-11d2-8e39-00a0c969723b'
!
fileInfoGuid
	"EFI_FILE_INFO_ID"
	^'09576e92-6d3f-11d2-8e39-00a0c969723b'
!
fileSystemInfoGuid
	"EFI_FILE_SYSTEM_INFO_ID"
	^'09576e93-6d3f-11d2-8e39-00a0c969723b'
! !

!FirmwareFileSystem class methodsFor: 'finding'!
all
	"The firmware's file systems, in its order; none without a firmware."
	| firmware |
	firmware := Firmware current.
	firmware isNil ifTrue: [^#()].
	^((firmware handlesSupporting: self simpleFileSystemGuid)
		collect: [:h | self firmware: firmware handle: h]) select: [:v | v notNil]
!
firmware: aFirmware handle: aHandle
	"The file system on aHandle, or nil if it has none or its volume does not open."
	| p |
	p := aFirmware protocol: self simpleFileSystemGuid on: aHandle.
	p isNil ifTrue: [^nil].
	^self new setFirmware: aFirmware handle: aHandle fileSystem: p
! !

!FirmwareFileSystem class methodsFor: 'constants'!
bufferSize
	^256 * 1024
!
statusNames
	"EFI_STATUS error codes (the low bits) -> what a FileError says."
	^Dictionary new
		at: 2 put: 'Invalid argument';
		at: 3 put: 'Operation not supported';
		at: 5 put: 'Buffer too small';
		at: 7 put: 'Input/output error';
		at: 8 put: 'Read-only file system';
		at: 9 put: 'Out of firmware memory';
		at: 10 put: 'File system corrupted';
		at: 11 put: 'No space left on device';
		at: 12 put: 'No medium';
		at: 13 put: 'Medium changed';
		at: 14 put: 'No such file or directory';
		at: 15 put: 'Permission denied';
		yourself
! !

!FirmwareFileSystem methodsFor: 'initialization'!
setFirmware: aFirmware handle: aHandle fileSystem: aProtocol
	firmware := aFirmware.
	handle := aHandle.
	fs := aProtocol.
	lock := Semaphore forMutualExclusion.
	root := firmware outWord: [:p | Machine call: (firmware function: fs at: 8) with: fs with: p].
	root isNil ifTrue: [^nil].
	buffer := Machine allocate: self class bufferSize.
	infoBytes := 4096.
	info := Machine allocate: infoBytes + 8.
	self readFileSystemInfo
! !

!FirmwareFileSystem methodsFor: 'accessing'!
handle
	^handle
!
label
	"The volume's label (trailing spaces dropped), nil if it has none."
	^label
!
isReadOnly
	"Is the volume (or its medium) read-only?"
	^readOnly
!
freeSpace
	"Bytes free, as the firmware says now."
	^lock critical: [
		self readFileSystemInfo.
		Machine uint64At: info + 8 + 24]
!
volumeSize
	^lock critical: [
		self readFileSystemInfo.
		Machine uint64At: info + 8 + 16]
!
isBootVolume
	"Has it samaltak.args in its root (the volume the VM was loaded from)?"
	^[(self stat: '/samaltak.args') isDirectory not] on: FileError do: [:e | e return: false]
!
bufferAddress
	^buffer
!
lock
	^lock
!
description
	^'a FirmwareFileSystem(', (label ifNil: ['no label']), ')'
!
printOn: aStream
	aStream nextPutAll: self description
! !

!FirmwareFileSystem methodsFor: 'volume'!
stat: aPath
	"The file or directory at aPath: a FirmwareFileStat; FileDoesNotExist if there is none."
	^lock critical: [| file |
		file := self openFile: aPath mode: 1 attributes: 0.
		[self statOf: file path: aPath] ensure: [self close: file]]
!
entriesAt: aPath
	"The names in the directory aPath."
	^lock critical: [| dir names |
		dir := self openFile: aPath mode: 1 attributes: 0.
		[| n |
			(self fileInfoOf: dir) isDirectory ifFalse: [^FileError signal: 'Not a directory: ', aPath path: aPath].
			names := OrderedCollection new.
			[n := self readEntryOf: dir path: aPath.
			 n > 0] whileTrue: [names add: (self ucs2At: info + 8 + 80 max: n - 80 // 2)].
			names asArray] ensure: [self close: dir]]
! !

!FirmwareFileSystem methodsFor: 'writing'!
open: aPath mode: mode
	"A FirmwareFile on aPath: mode 0 to read, 1 to read and write (created if missing), 2 to append, 3 created or truncated. Mode 4 (a private file, File writeSecret:to:) is refused: the firmware's FAT has no permissions, so the file could not be kept from other users."
	mode = 4 ifTrue: [^FileError signal: 'A firmware (FAT) volume has no permissions, so it cannot hold a private file: ', aPath path: aPath].
	^lock critical: [| file st |
		mode = 0
			ifTrue: [file := self openFile: aPath mode: 1 attributes: 0]
			ifFalse: [
				self checkWritable: aPath.
				file := self openFile: aPath mode: 16r8000000000000003 attributes: 0].
		[st := self statOf: file path: aPath.
		 st isDirectory ifTrue: [FileError signal: 'Is a directory: ', aPath path: aPath].
		 (mode = 3 and: [st size > 0]) ifTrue: [self truncate: file path: aPath]]
			on: Error do: [:e | self close: file. e pass].
		(FirmwareFile on: self handle: file name: aPath size: (mode = 3 ifTrue: [0] ifFalse: [st size]) writable: mode ~= 0)
			position: (mode = 2 ifTrue: [st size] ifFalse: [0]);
			yourself]
!
delete: aPath
	"Delete the file or empty directory aPath."
	(self isRoot: aPath) ifTrue: [^FileError signal: 'Is a mount point: ', aPath path: aPath].
	^lock critical: [| file st status |
		self checkWritable: aPath.
		file := self openFile: aPath mode: 3 attributes: 0.
		st := [self statOf: file path: aPath] on: Error do: [:e | self close: file. e pass].
		status := Machine call: (firmware function: file at: 24) with: file.
		(firmware isError: status) ifTrue: [self check: status path: aPath].
		status = 0 ifFalse: [
			FileError signal: (st isDirectory ifTrue: ['Directory not empty: '] ifFalse: ['Cannot delete: ']), aPath path: aPath].
		self]
!
rename: oldPath to: newPath
	"Rename or move oldPath to newPath (on me); a file at newPath is replaced, a directory there is an error."
	| target |
	((self isRoot: oldPath) or: [self isRoot: newPath]) ifTrue: [^FileError signal: 'Is a mount point: ', oldPath path: oldPath].
	target := [self stat: newPath] on: FileDoesNotExist do: [:e | e return: nil].
	target notNil ifTrue: [
		target isDirectory ifTrue: [^FileExists signal: 'File exists: ', newPath path: newPath].
		(self stat: oldPath) isDirectory ifTrue: [^FileError signal: 'Not a directory: ', newPath path: newPath].
		(self sameFile: oldPath as: newPath) ifFalse: [self delete: newPath]].
	^lock critical: [| file name size status |
		self checkWritable: oldPath.
		file := self openFile: oldPath mode: 3 attributes: 0.
		[self fileInfoOf: file.
		 name := '\', ((self componentsOf: newPath) inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc, '\', each]]).
		 size := 80 + (2 * (name size + 1)).
		 size > infoBytes ifTrue: [^FileError signal: 'File name too long: ', newPath path: newPath].
		 Machine uint64At: info + 8 put: size.
		 name doWithIndex: [:c :i | Machine uint16At: info + 8 + 80 + (2 * (i - 1)) put: (c value min: 16rFFFD)].
		 Machine uint16At: info + 8 + 80 + (2 * name size) put: 0.
		 status := Machine call: (firmware function: file at: 72) with: file with: (firmware guid: self class fileInfoGuid) with: size with: info + 8.
		 self check: status path: oldPath]
			ensure: [self close: file].
		self]
!
createDirectory: aPath
	(self isRoot: aPath) ifTrue: [^FileExists signal: 'File exists: ', aPath path: aPath].
	([self stat: aPath] on: FileDoesNotExist do: [:e | e return: nil]) ifNotNil: [:st |
		^FileExists signal: 'File exists: ', aPath path: aPath].
	^lock critical: [
		self checkWritable: aPath.
		self close: (self openFile: aPath mode: 16r8000000000000003 attributes: 16r10).
		self]
! !

!FirmwareFileSystem methodsFor: 'files'!
read: aFile at: position into: aByteArray startingAt: start count: count path: aPath
	"Up to count bytes of the open file aFile from position into aByteArray at start; answer how many (0 at its end)."
	^lock critical: [| n size |
		self check: (Machine call: (firmware function: aFile at: 56) with: aFile with: position) path: aPath.
		n := count min: self class bufferSize.
		size := info.
		Machine uint64At: size put: n.
		self check: (Machine call: (firmware function: aFile at: 32) with: aFile with: size with: buffer) path: aPath.
		n := Machine uint64At: size.
		n > 0 ifTrue: [Machine copy: n from: buffer at: 0 to: aByteArray at: start - 1].
		n]
!
write: aFile at: position from: aByteArray startingAt: start count: count path: aPath
	"count bytes of aByteArray from start into the open file aFile at position; answer how many."
	| done |
	done := 0.
	[done < count] whileTrue: [
		lock critical: [| n size status |
			n := count - done min: self class bufferSize.
			Machine copy: n from: aByteArray at: start - 1 + done to: buffer at: 0.
			self check: (Machine call: (firmware function: aFile at: 56) with: aFile with: position + done) path: aPath.
			size := info.
			Machine uint64At: size put: n.
			status := Machine call: (firmware function: aFile at: 40) with: aFile with: size with: buffer.
			self check: status path: aPath.
			(Machine uint64At: size) = 0 ifTrue: [FileError signal: 'No space left on device: ', aPath path: aPath].
			done := done + (Machine uint64At: size)]].
	^done
!
flush: aFile path: aPath
	^lock critical: [self check: (Machine call: (firmware function: aFile at: 80) with: aFile) path: aPath]
!
close: aFile
	"Close (EFI_FILE_PROTOCOL.Close: it writes what is pending)."
	^Machine call: (firmware function: aFile at: 16) with: aFile
!
closeFile: aFile path: aPath
	^lock critical: [self check: (self close: aFile) path: aPath]
! !

!FirmwareFileSystem methodsFor: 'private'!
readFileSystemInfo
	"EFI_FILE_SYSTEM_INFO of the root into info (at info + 8); label and readOnly from it."
	| size status |
	size := info.
	Machine uint64At: size put: infoBytes.
	status := Machine call: (firmware function: root at: 64) with: root with: (firmware guid: self class fileSystemInfoGuid) with: size with: info + 8.
	(firmware isError: status) ifTrue: [
		label := nil.
		readOnly := false.
		^self].
	readOnly := (Machine uint8At: info + 8 + 8) ~= 0.
	label := self ucs2At: info + 8 + 36 max: infoBytes - 36 // 2.
	[label notEmpty and: [label last = $ ]] whileTrue: [label := label allButLast].
	label isEmpty ifTrue: [label := nil]
!
openFile: aPath mode: mode attributes: attributes
	"EFI_FILE_PROTOCOL.Open from the root: the new file's protocol; FileError if it cannot."
	| name file status |
	name := self ucs2Path: aPath.
	file := Machine allocate: 8.
	[Machine uint64At: file put: 0.
	 status := Machine call: (firmware function: root at: 8) with: root with: file with: name with: mode with: attributes.
	 self check: status path: aPath.
	 ^Machine uint64At: file]
		ensure: [Machine free: name. Machine free: file]
!
statOf: aFile path: aPath
	^(self fileInfoOf: aFile) path: aPath
!
fileInfoOf: aFile
	"EFI_FILE_INFO of aFile into info (at info + 8): a FirmwareFileStat."
	| size |
	size := info.
	Machine uint64At: size put: infoBytes.
	self check: (Machine call: (firmware function: aFile at: 64) with: aFile with: (firmware guid: self class fileInfoGuid) with: size with: info + 8) path: '?'.
	^FirmwareFileStat volume: self
		size: (Machine uint64At: info + 8 + 8)
		attributes: (Machine uint64At: info + 8 + 72)
		modificationTime: (self microsecondsOfTimeAt: info + 8 + 56)
!
readEntryOf: aDirectory path: aPath
	"The next entry of the open directory into info (at info + 8); answer its size (0 at the end), past . and .."
	| size n name |
	[size := info.
	 Machine uint64At: size put: infoBytes.
	 self check: (Machine call: (firmware function: aDirectory at: 32) with: aDirectory with: size with: info + 8) path: aPath.
	 n := Machine uint64At: size.
	 n = 0 ifTrue: [^0].
	 name := self ucs2At: info + 8 + 80 max: 3.
	 name = '.' or: [name = '..']] whileTrue.
	^n
!
truncate: aFile path: aPath
	"Set the open file's size to 0 (SetInfo with FileSize 0)."
	self fileInfoOf: aFile.
	Machine uint64At: info + 8 + 8 put: 0.
	self check: (Machine call: (firmware function: aFile at: 72) with: aFile with: (firmware guid: self class fileInfoGuid) with: (Machine uint64At: info + 8) with: info + 8) path: aPath
!
checkWritable: aPath
	readOnly ifTrue: [FileError signal: 'Read-only file system: ', aPath path: aPath]
!
check: status path: aPath
	"Signal the FileError of an error status."
	| code text |
	(firmware isError: status) ifFalse: [^status].
	code := status bitAnd: 16rFFFF.
	text := self class statusNames at: code ifAbsent: ['Firmware error 16r', (status printString: 16)].
	code = 14 ifTrue: [^FileDoesNotExist signal: text, ': ', aPath path: aPath].
	^FileError signal: text, ': ', aPath path: aPath
!
componentsOf: aPath
	^(aPath subStrings: '/') reject: [:n | n isEmpty or: [n = '.']]
!
isRoot: aPath
	^(self componentsOf: aPath) isEmpty
!
sameFile: aPath as: anotherPath
	"Do the paths name the same file (FAT: case-insensitively)?"
	^(self componentsOf: aPath) asArray = (self componentsOf: anotherPath) asArray
		or: [((self componentsOf: aPath) collect: [:n | n asLowercase]) asArray = ((self componentsOf: anotherPath) collect: [:n | n asLowercase]) asArray]
!
ucs2Path: aPath
	"aPath as a NUL-terminated UCS-2 file name from the root (\ separated), in memory outside the heap (free it)."
	| comps name p |
	comps := self componentsOf: aPath.
	name := comps isEmpty ifTrue: ['\'] ifFalse: [comps inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc, '\', each]]].
	p := Machine allocate: name size + 1 * 2.
	name doWithIndex: [:c :i | Machine uint16At: p + (2 * (i - 1)) put: (c value min: 16rFFFD)].
	Machine uint16At: p + (2 * name size) put: 0.
	^p
!
ucs2At: anAddress max: n
	"The NUL-terminated UCS-2 string at anAddress, at most n characters."
	^String streamContents: [:s | | i c |
		i := 0.
		[i < n and: [(c := Machine uint16At: anAddress + (2 * i)) ~= 0]] whileTrue: [
			s nextPut: (Character value: c).
			i := i + 1]]
!
microsecondsOfTimeAt: anAddress
	"An EFI_TIME (local time unless its TimeZone is given; FAT's has none) in UTC microseconds since 1970."
	| year month day seconds zone |
	year := Machine uint16At: anAddress.
	month := Machine uint8At: anAddress + 2.
	day := Machine uint8At: anAddress + 3.
	(year < 1970 or: [month < 1 or: [month > 12 or: [day < 1]]]) ifTrue: [^0].
	seconds := (self daysFromCivil: year month: month day: day) * 86400
		+ ((Machine uint8At: anAddress + 4) * 3600) + ((Machine uint8At: anAddress + 5) * 60) + (Machine uint8At: anAddress + 6).
	zone := Machine uint16At: anAddress + 12.
	zone >= 16r8000 ifTrue: [zone := zone - 16r10000].
	zone = 2047 ifFalse: [seconds := seconds + (zone * 60)].
	^seconds * 1000000 + ((Machine uint32At: anAddress + 8) // 1000)
!
daysFromCivil: y month: m day: d
	"Days since 1970-01-01 of a proleptic Gregorian date."
	| yy era yoe doy doe |
	yy := m <= 2 ifTrue: [y - 1] ifFalse: [y].
	era := yy // 400.
	yoe := yy - (era * 400).
	doy := (153 * (m > 2 ifTrue: [m - 3] ifFalse: [m + 9]) + 2) // 5 + d - 1.
	doe := yoe * 365 + (yoe // 4) - (yoe // 100) + doy.
	^era * 146097 + doe - 719468
! !
