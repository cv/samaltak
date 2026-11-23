!SDLPlatform methodsFor: 'FFI - files'!
ffiFilePosition: h
	<function>
	<approvedFFI: 505 symbol: 'platform_files_position' arguments: #(3) result: 3>
	<var: #h type: 'int64_t'>
	<returns: 'int64_t'>
	^files position: h asInt32
!
ffiFileSize: h
	<function>
	<approvedFFI: 504 symbol: 'platform_files_size' arguments: #(3) result: 3>
	<var: #h type: 'int64_t'>
	<returns: 'int64_t'>
	^files size: h asInt32
!
ffiFileRead: h into: buf count: n
	<function>
	<approvedFFI: 502 symbol: 'platform_files_read' arguments: #(3 9) result: 3>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	^files read: h asInt32 into: buf count: n
!
ffiFileWrite: h from: buf count: n
	<function>
	<approvedFFI: 503 symbol: 'platform_files_write' arguments: #(3 8) result: 3>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	^files write: h asInt32 bytes: buf count: n
!
ffiFileClose: h
	<function>
	<approvedFFI: 501 symbol: 'platform_files_close' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^(files close: h asInt32) ifTrue: [1] ifFalse: [0]
!
ffiFileSeek: h to: pos
	<function>
	<approvedFFI: 506 symbol: 'platform_files_seek' arguments: #(3 3) result: 1>
	<var: #h type: 'int64_t'>
	<var: #pos type: 'int64_t'>
	<returns: 'int32_t'>
	^(pos >= 0 and: [files seek: h asInt32 to: pos]) ifTrue: [1] ifFalse: [0]
!
ffiFileFlush: h
	<function>
	<approvedFFI: 507 symbol: 'platform_files_flush' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^(files flush: h asInt32) ifTrue: [1] ifFalse: [0]
!
ffiFileOpen: bytes size: n mode: mode
	<function>
	<approvedFFI: 500 symbol: 'platform_files_open' arguments: #(8 3) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #mode type: 'int64_t'>
	<returns: 'int32_t'>
	| p h |
	p := self ffiFilePath: bytes size: n.
	h := p isNull ifTrue: [0] ifFalse: [files open: p mode: mode asInt32].
	libc free: p.
	^h asInt32
!
ffiFileDelete: bytes size: n
	<function>
	<approvedFFI: 508 symbol: 'platform_files_delete' arguments: #(8) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| p ok |
	p := self ffiFilePath: bytes size: n.
	ok := p notNull and: [files delete: p].
	libc free: p.
	^ok ifTrue: [1] ifFalse: [0]
!
ffiFileDirCreate: bytes size: n
	<function>
	<approvedFFI: 512 symbol: 'platform_files_dir_create' arguments: #(8) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| p ok |
	p := self ffiFilePath: bytes size: n.
	ok := p notNull and: [files dirCreate: p].
	libc free: p.
	^ok ifTrue: [1] ifFalse: [0]
!
ffiFileMkfifo: bytes size: n
	<function>
	<approvedFFI: 514 symbol: 'platform_files_mkfifo' arguments: #(8) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| p ok |
	p := self ffiFilePath: bytes size: n.
	ok := p notNull and: [files mkfifo: p].
	libc free: p.
	^ok ifTrue: [1] ifFalse: [0]
!
ffiFileRename: from size: m to: to size: n
	<function>
	<approvedFFI: 509 symbol: 'platform_files_rename' arguments: #(8 8) result: 1>
	<var: #from type: 'const uint8_t *'>
	<var: #m type: 'uint64_t'>
	<var: #to type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| a b ok |
	a := self ffiFilePath: from size: m.
	b := self ffiFilePath: to size: n.
	ok := a notNull and: [b notNull and: [files rename: a to: b]].
	libc free: b.
	libc free: a.
	^ok ifTrue: [1] ifFalse: [0]
!
ffiFileStat: bytes size: n into: out size: cap
	"One stat, with fixed wire layout: two byte flags, then two signed LE64 words."
	<function>
	<approvedFFI: 510 symbol: 'platform_files_stat' arguments: #(8 9) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| p st ok size mtime |
	cap ~= 18 ifTrue: [^0].
	p := self ffiFilePath: bytes size: n.
	p isNull ifTrue: [^0].
	st := self local: 'pf_stat'.
	ok := files stat: p into: st.
	libc free: p.
	ok ifFalse: [^0].
	out at: 0 put: ((st exists ifTrue: [1] ifFalse: [0]) asUInt8).
	out at: 1 put: ((st isDir ifTrue: [1] ifFalse: [0]) asUInt8).
	size := st fileSize asUInt64.
	mtime := st mtimeUs asUInt64.
	0 to: 7 do: [:i |
		out at: i + 2 put: (size >> (i * 8)) asUInt8.
		out at: i + 10 put: (mtime >> (i * 8)) asUInt8].
	^1
!
ffiFilePath: bytes size: n
	<function>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'char *'>
	^nativeCountedText copyTerminated: bytes size: n
! !

!SDLPlatform methodsFor: 'FFI - owned file names'!
ffiDirEntries: bytes size: n receipt: out size: cap
	<function>
	<approvedFFI: 511 symbol: 'platform_files_dir_entries' arguments: #(8 9) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| row p count names |
	row := files ownedNamesRoom: out capacity: cap.
	row isNull ifTrue: [^0].
	p := self ffiFilePath: bytes size: n.
	p isNull ifTrue: [^0].
	count := self local: 'int'.
	names := files dirEntries: p count: count.
	libc free: p.
	names isNull ifTrue: [^0].
	files ownedNamesPublish: row names: names count: count value asUInt32 receipt: out.
	^1
!
ffiCwdReceipt: out size: cap
	<function>
	<approvedFFI: 513 symbol: 'platform_files_cwd' arguments: #(9) result: 1>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| row path names |
	row := files ownedNamesRoom: out capacity: cap.
	row isNull ifTrue: [^0].
	path := files cwd.
	path isNull ifTrue: [^0].
	names := self cCoerce: (libc malloc: (self sizeof: 'char *')) to: 'char **'.
	names isNull ifTrue: [
		libc free: path.
		common setError: 'out of memory'.
		^0].
	names at: 0 put: path.
	files ownedNamesPublish: row names: names count: 1 asUInt32 receipt: out.
	^1
!
ffiOwnedNameSize: ticket index: index
	<function>
	<approvedFFI: 1511 symbol: 'platform_files_name_size' arguments: #(4 2) result: 3>
	<var: #ticket type: 'uint64_t'>
	<var: #index type: 'uint32_t'>
	<returns: 'int64_t'>
	| p n |
	p := files ownedName: ticket at: index.
	p isNull ifTrue: [^-1].
	n := libc strlen: p.
	n > 16r7FFFFFFF8 asUInt64 ifTrue: [^-1].
	^n asInt64
!
ffiOwnedNameCopy: ticket index: index into: out size: cap
	<function>
	<approvedFFI: 1512 symbol: 'platform_files_name_copy' arguments: #(4 2 9) result: 1>
	<var: #ticket type: 'uint64_t'>
	<var: #index type: 'uint32_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| p |
	p := files ownedName: ticket at: index.
	(p isNull or: [(libc strlen: p) ~= cap]) ifTrue: [^0].
	cap ~= 0 ifTrue: [libc memcpy: out from: p size: cap].
	^1
!
ffiOwnedNameRelease: ticket
	<function>
	<approvedFFI: 1513 symbol: 'platform_files_name_release' arguments: #(4) result: 1>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	^files releaseOwnedNames: ticket
! !
