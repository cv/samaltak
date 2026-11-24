Object subclass: #File
	instanceVariableNames: ''
	classVariableNames: 'Mounts ReadCall WriteCall CloseCall SeekCall FlushCall OpenCall DeleteCall DirCreateCall MkfifoCall RenameCall StatCall DirEntriesCall CwdCall NameSizeCall NameCopyCall NameReleaseCall SpawnCall ProcessWaitCall ExecCall'
	package: 'System-Files'!

File comment: 'I am the facade for the platform''s file primitives; everything is on my class side. Paths are Strings (UTF-8 on the OS side), joined with /. Handles are SmallIntegers owned by FileStream. Failures signal FileError with the platform''s reason.

A mount table (File mountTable:, a MountTable) takes over the paths it covers: they are its volumes'' (stat:, open:mode:, Directory entries:), and a file opened on one is a VolumeFile where a handle would be, which the handle primitives'' fallbacks (they fail for it) send the operation to. On UEFI, which has no files of its own, FirmwareVolumes installs one that covers every path; on an operating system there is none unless one is set (tests, an ext4 image mounted in a directory), and paths it does not cover are the platform''s.'!

!File class methodsFor: 'testing'!
exists: aPath
	^(self stat: aPath) first
!
isDirectory: aPath
	^(self stat: aPath) second
!
isFile: aPath
	| st |
	st := self stat: aPath.
	^st first and: [st second not]
! !

!File class methodsFor: 'accessing'!
stat: aPath
	"Answer {exists. isDirectory. size. modification time in UTC microseconds}."
	(self mountTableFor: aPath) ifNotNil: [:mounts | ^mounts stat: aPath].
	^self primStat: aPath
!
sizeOf: aPath
	| st |
	st := self stat: aPath.
	st first ifFalse: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
	^st third
!
modificationTime: aPath
	"Answer the modification time in microseconds since 1970 (UTC)."
	| st |
	st := self stat: aPath.
	st first ifFalse: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
	^st fourth
! !

!File class methodsFor: 'reading and writing'!
readBytes: aPath
	"Answer the whole file as a ByteArray."
	^(FileStream readOnlyFileNamed: aPath) binary; contentsAndClose
!
readText: aPath
	"Answer the whole file decoded from UTF-8, without a leading byte order mark (U+FEFF)."
	| text |
	text := (FileStream readOnlyFileNamed: aPath) contentsAndClose.
	^(text notEmpty and: [text first value = 16rFEFF]) ifTrue: [text allButFirst] ifFalse: [text]
!
writeBytes: aByteArray to: aPath
	"Replace the file's contents with aByteArray."
	FileStream forceNewFileNamed: aPath do: [:s | s binary; nextPutAll: aByteArray]
!
writeText: aString to: aPath
	"Replace the file's contents with aString, UTF-8 encoded."
	FileStream forceNewFileNamed: aPath do: [:s | s nextPutAll: aString]
!
writeSecret: aString to: aPath
	"Replace the file with aString, UTF-8 encoded, as a file only its owner may read and write (mode 600, whatever mode it had), written whole or not at all: a new file next to it, renamed over it."
	| tmp |
	tmp := aPath, '.tmp'.
	self deleteIfExists: tmp.
	FileStream forceNewPrivateFileNamed: tmp do: [:s | s nextPutAll: aString].
	self rename: tmp to: aPath
!
lineCountOf: aPath
	"Answer the number of line feeds in the file, as wc -l counts lines."
	^(self readBytes: aPath) occurrencesOf: 10
! !

!File class methodsFor: 'file operations'!
delete: aPath
	(self mountTableFor: aPath) ifNotNil: [:mounts | ^mounts delete: aPath].
	(self primDelete: aPath) isNil ifTrue: [^self signalErrorFor: aPath]
!
deleteIfExists: aPath
	(self exists: aPath) ifTrue: [self delete: aPath]
!
rename: oldPath to: newPath
	(self mountTableFor: oldPath) ifNotNil: [:mounts | ^mounts rename: oldPath to: newPath].
	(self mountTableFor: newPath) ifNotNil: [:mounts | ^mounts rename: oldPath to: newPath].
	(self primRename: oldPath to: newPath) isNil ifTrue: [^self signalErrorFor: oldPath]
! !

!File class methodsFor: 'mounting'!
mountTable
	"The MountTable that takes over the paths it covers, or nil."
	^Mounts
!
mountTable: aMountTableOrNil
	Mounts := aMountTableOrNil
!
mountTableFor: aPath
	"The mount table if it covers aPath, else nil (the platform's)."
	^(Mounts notNil and: [Mounts covers: aPath]) ifTrue: [Mounts] ifFalse: [nil]
!
open: aPath mode: mode
	"A handle for FileStream: the platform's (nil if it cannot open aPath), or a mounted volume's VolumeFile (it signals FileError if it cannot)."
	(self mountTableFor: aPath) ifNotNil: [:mounts | ^mounts open: aPath mode: mode].
	^self primOpen: aPath mode: mode
! !

!File class methodsFor: 'paths'!
join: aPath with: aName
	"Answer aPath / aName with exactly one separator."
	aPath isEmpty ifTrue: [^aName].
	(aName notEmpty and: [aName first = $/]) ifTrue: [^aName].
	^(aPath last = $/ ifTrue: [aPath] ifFalse: [aPath, '/']), aName
!
baseName: aPath
	"Answer the last component of aPath."
	| i |
	i := aPath lastIndexOf: $/.
	^aPath copyFrom: i + 1 to: aPath size
!
directoryOf: aPath
	"Answer aPath without its last component ('.' if there is none)."
	| i |
	i := aPath lastIndexOf: $/.
	i = 0 ifTrue: [^'.'].
	i = 1 ifTrue: [^'/'].
	^aPath copyFrom: 1 to: i - 1
!
extensionOf: aPath
	| name i |
	name := self baseName: aPath.
	i := name lastIndexOf: $..
	i <= 1 ifTrue: [^''].
	^name copyFrom: i + 1 to: name size
! !

!File class methodsFor: 'errors'!
lastError
	"Answer the platform's description of the last failure."
	^self primLastError ifNil: ['unknown error']
!
signalErrorFor: aPath
	^FileError signal: self lastError path: aPath
! !

!File class methodsFor: 'primitives'!
primOpen: path mode: mode
	"mode: 0 read, 1 read/write (created if missing), 2 append, 3 create/truncate, 4 create/truncate, created with mode 600. Answer a handle or nil."
	| binding bytes result |
	binding := OpenCall ifNil: [OpenCall := PlatformFFI bind: #(call 'platform' 'platform_files_open' (bytesWithLength i64) i32)].
	binding isNil ifTrue: [^nil].
	bytes := PlatformFFI osTextBytes: path.
	bytes isNil ifTrue: [^nil].
	result := binding tryInvoke2: {bytes. 1. bytes size} with: mode.
	result == false ifTrue: [^nil].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
primClose: h
	"A handle that is not an Integer is a VolumeFile (open:mode:): it does the operation."
	| binding result |
	h isInteger ifFalse: [^h close].
	binding := CloseCall ifNil: [CloseCall := PlatformFFI bind: #(call 'platform' 'platform_files_close' (i64) i32)].
	binding isNil ifTrue: [^nil].
	result := binding tryInvoke1: h.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primRead: h into: bytes startingAt: start count: count
	"Answer the number of bytes read (0 at the end of the file), or nil."
	| binding result |
	h isInteger ifFalse: [^h readInto: bytes startingAt: start count: count].
	bytes class == ByteArray ifFalse: [
		^PlatformIOBuffer readInto: bytes start: start count: count failure: nil
			using: [:slice | self primRead: h into: slice startingAt: 1 count: count]].
	binding := ReadCall ifNil: [ReadCall := PlatformFFI bind: #(call 'platform' 'platform_files_read' (i64 writableBytesWithLength) i64)].
	binding isNil ifTrue: [^nil].
	result := binding tryInvoke2: h with: {bytes. start. count}.
	result == false ifTrue: [^nil].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
primWrite: h from: bytes startingAt: start count: count
	| binding result |
	h isInteger ifFalse: [^h writeFrom: bytes startingAt: start count: count].
	bytes class == ByteArray ifFalse: [
		| slice |
		slice := PlatformIOBuffer writeSliceFrom: bytes start: start count: count.
		slice isNil ifTrue: [^nil].
		^self primWrite: h from: slice startingAt: 1 count: count].
	binding := WriteCall ifNil: [WriteCall := PlatformFFI bind: #(call 'platform' 'platform_files_write' (i64 bytesWithLength) i64)].
	binding isNil ifTrue: [^nil].
	result := binding tryInvoke2: h with: {bytes. start. count}.
	result == false ifTrue: [^nil].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
primSize: h
	<ffiSite>
	| result |
	h isInteger ifFalse: [^h size].
	result := (self ffiSite: #(call 'platform' 'platform_files_size' (i64) nonNegativeI64)) tryInvoke1: h.
	result == false ifTrue: [^nil].
	^result
!
primPosition: h
	<ffiSite>
	| result |
	h isInteger ifFalse: [^h position].
	result := (self ffiSite: #(call 'platform' 'platform_files_position' (i64) nonNegativeI64)) tryInvoke1: h.
	result == false ifTrue: [^nil].
	^result
!
primSeek: h to: position
	| binding result |
	h isInteger ifFalse: [^h position: position].
	binding := SeekCall ifNil: [SeekCall := PlatformFFI bind: #(call 'platform' 'platform_files_seek' (i64 i64) i32)].
	binding isNil ifTrue: [^nil].
	result := binding tryInvoke2: h with: position.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primFlush: h
	| binding result |
	h isInteger ifFalse: [^h flush].
	binding := FlushCall ifNil: [FlushCall := PlatformFFI bind: #(call 'platform' 'platform_files_flush' (i64) i32)].
	binding isNil ifTrue: [^nil].
	result := binding tryInvoke1: h.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primDelete: path
	| binding bytes result |
	binding := DeleteCall ifNil: [DeleteCall := PlatformFFI bind: #(call 'platform' 'platform_files_delete' (bytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	bytes := PlatformFFI osTextBytes: path.
	bytes isNil ifTrue: [^nil].
	result := binding tryInvoke1: {bytes. 1. bytes size}.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primRename: oldPath to: newPath
	| binding a b result |
	binding := RenameCall ifNil: [RenameCall := PlatformFFI bind: #(call 'platform' 'platform_files_rename' (bytesWithLength bytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	a := PlatformFFI osTextBytes: oldPath.
	b := PlatformFFI osTextBytes: newPath.
	(a isNil or: [b isNil]) ifTrue: [^nil].
	result := binding tryInvoke2: {a. 1. a size} with: {b. 1. b size}.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primStat: path
	| binding bytes out result |
	binding := StatCall ifNil: [StatCall := PlatformFFI bind: #(call 'platform' 'platform_files_stat' (bytesWithLength writableBytesWithLength) i32)].
	binding isNil ifTrue: [^self missingStat].
	bytes := PlatformFFI osTextBytes: path.
	bytes isNil ifTrue: [^self missingStat].
	out := ByteArray new: 18.
	result := binding tryInvoke2: {bytes. 1. bytes size} with: {out. 1. out size}.
	result == false ifTrue: [^self missingStat].
	result = 0 ifTrue: [^self missingStat].
	^{out first ~= 0. out second ~= 0. FFIWire int64At: 3 in: out. FFIWire int64At: 11 in: out}
!
missingStat
	^Array with: false with: false with: 0 with: 0
!
primDirEntries: path
	| binding bytes result |
	binding := DirEntriesCall ifNil: [DirEntriesCall := PlatformFFI bind: #(call 'platform' 'platform_files_dir_entries' (bytesWithLength writableBytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	bytes := PlatformFFI osTextBytes: path.
	bytes isNil ifTrue: [^nil].
	result := self captureNames: [:receipt | binding tryInvoke2: {bytes. 1. bytes size} with: receipt].
	result == false ifTrue: [^nil].
	^result
!
primDirCreate: path
	| binding bytes result |
	binding := DirCreateCall ifNil: [DirCreateCall := PlatformFFI bind: #(call 'platform' 'platform_files_dir_create' (bytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	bytes := PlatformFFI osTextBytes: path.
	bytes isNil ifTrue: [^nil].
	result := binding tryInvoke1: {bytes. 1. bytes size}.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primMkfifo: path
	| binding bytes result |
	binding := MkfifoCall ifNil: [MkfifoCall := PlatformFFI bind: #(call 'platform' 'platform_files_mkfifo' (bytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	bytes := PlatformFFI osTextBytes: path.
	bytes isNil ifTrue: [^nil].
	result := binding tryInvoke1: {bytes. 1. bytes size}.
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primCwd
	| binding result |
	binding := CwdCall ifNil: [CwdCall := PlatformFFI bind: #(call 'platform' 'platform_files_cwd' (writableBytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	result := self captureNames: [:receipt | binding tryInvoke1: receipt].
	result == false ifTrue: [^nil].
	^result ifNotNil: [result first]
!
primLastError
	^WindowPlatformFFI lastError
!
primSpawn: argv
	"Start argv first (looked up in PATH) with the other Strings as arguments, sharing the VM's standard streams. Answer its pid or nil."
	| binding request result |
	binding := SpawnCall ifNil: [
		SpawnCall := PlatformFFI bind: #(call 'platform' 'platform_process_spawn' (bytesWithLength) i64)].
	binding isNil ifTrue: [^nil].
	request := ProcessLaunchRecord arguments: argv.
	request isNil ifTrue: [^nil].
	result := binding tryInvoke1: {request. 1. request size}.
	(result == false or: [result <= 0]) ifTrue: [^nil].
	^result
!
primWait: pid blocking: aBoolean
	"Answer the exit status of the child pid (128 + signal number if killed), nil while it runs (aBoolean false); fail: nil."
	| binding out result |
	(aBoolean == true or: [aBoolean == false]) ifFalse: [^nil].
	binding := ProcessWaitCall ifNil: [
		ProcessWaitCall := PlatformFFI bind: #(call 'platform' 'platform_process_wait' (i64 i32 writableBytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	out := ByteArray new: 5.
	result := binding tryInvoke3: pid with: (aBoolean ifTrue: [1] ifFalse: [0]) with: {out. 1. out size}.
	(result = 1 and: [out first = 1]) ifFalse: [^nil].
	^FFIWire int32At: 2 in: out
!
primExec: argv
	"Replace the VM's process by argv first (looked up in PATH) with the other Strings as arguments: same pid and standard streams, all other descriptors closed. Answers nil only if that failed."
	| binding request |
	binding := ExecCall ifNil: [
		ExecCall := PlatformFFI bind: #(call 'platform' 'platform_process_exec' (bytesWithLength) i32)].
	binding isNil ifTrue: [^nil].
	request := ProcessLaunchRecord arguments: argv.
	request isNil ifTrue: [^nil].
	binding tryInvoke1: {request. 1. request size}.
	^nil
! !

!File class methodsFor: 'FFI name results'!
captureNames: producer
	"An immutable native observation. Size and copy only read that observation. Never enumerate or getcwd twice."
	| size copy release receipt ticket status names count bytes length |
	size := NameSizeCall ifNil: [NameSizeCall := PlatformFFI bind: #(call 'platform' 'platform_files_name_size' (u64 u32) i64)].
	copy := NameCopyCall ifNil: [NameCopyCall := PlatformFFI bind: #(call 'platform' 'platform_files_name_copy' (u64 u32 writableBytesWithLength) i32)].
	release := NameReleaseCall ifNil: [NameReleaseCall := PlatformFFI bind: #(call 'platform' 'platform_files_name_release' (u64) i32)].
	(size isNil or: [copy isNil or: [release isNil]]) ifTrue: [^false].
	receipt := ByteArray new: 12.
	[
		status := producer value: {receipt. 1. 12}.
		status == false ifTrue: [^false].
		status = 0 ifTrue: [^nil].
		ticket := FFIWire uint64At: 1 in: receipt.
		count := FFIWire uint32At: 9 in: receipt.
		names := Array new: count.
		1 to: count do: [:i |
			length := size tryInvoke2: ticket with: i - 1.
			(length == false or: [length < 0]) ifTrue: [^nil].
			bytes := ByteArray new: length.
			(copy tryInvoke3: ticket with: i - 1 with: {bytes. 1. length}) = 1 ifFalse: [^nil].
			names at: i put: (PlatformFFI textFromBytes: bytes)].
		^names
	] ensure: [
		ticket := FFIWire uint64At: 1 in: receipt.
		ticket = 0 ifFalse: [
			(release tryInvoke1: ticket) == false ifTrue: [FFIError signal: 'File name result release rejected']]]
! !
