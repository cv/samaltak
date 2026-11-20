VMPlatformModule subclass: #UefiNoIO
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiNoIO comment: 'Files, processes, TLS and pseudo-terminals on UEFI: none (in place of PlatformFiles, PlatformPtys, PlatformTLS and PosixIO; sockets are UefiSockets''). Every call fails with the error ''not on UEFI''; the image works without them (docs/uefi.md).'!

!UefiNoIO class methodsFor: 'declaring'!
targetOS
	^#uefi
!
replaces
	^{PlatformFiles. PlatformPtys. PlatformTLS. PosixIO}
!
isSimulated
	^false
! !

!UefiNoIO methodsFor: 'unsupported'!
strerror: code
	<function>
	<var: #code type: 'int'>
	<returns: 'char *'>
	^'not on UEFI'
!
close: f
	<function>
	<var: #f type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
cwd
	<function>
	<returns: 'char *'>
	common setError: 'not on UEFI'.
	^self null
!
delete: aPath
	<function>
	<var: #aPath type: 'char *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
dirCreate: aPath
	<function>
	<var: #aPath type: 'char *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
dirEntries: aPath count: n
	<function>
	<var: #aPath type: 'char *'>
	<var: #n type: 'int *'>
	<returns: 'char **'>
	common setError: 'not on UEFI'.
	^self null
!
exec: aArgv
	<function>
	<var: #aArgv type: 'char **'>
	common setError: 'not on UEFI'
!
flush: f
	<function>
	<var: #f type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
foreground: p
	<function>
	<var: #p type: 'int32_t'>
	<returns: 'pid_t'>
	common setError: 'not on UEFI'.
	^-1
!
handleCount
	<function>
	<returns: 'int32_t'>
	^0
!
handshake: h
	<function>
	<var: #h type: 'int32_t'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^-1
!
mkfifo: aPath
	<function>
	<var: #aPath type: 'char *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
open: aPath mode: aMode
	<function>
	<var: #aPath type: 'char *'>
	<var: #aMode type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
position: f
	<function>
	<var: #f type: 'int32_t'>
	<returns: 'off_t'>
	common setError: 'not on UEFI'.
	^-1
!
processWait: aPid block: aBlock status: aStatus done: aDone
	<function>
	<var: #aPid type: 'int64_t'>
	<var: #aBlock type: 'bool'>
	<var: #aStatus type: 'int *'>
	<var: #aDone type: 'bool *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
read: f into: buf count: n
	<function>
	<var: #f type: 'int32_t'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
!
recv: s into: buf count: n
	<function>
	<var: #s type: 'int32_t'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
!
rename: from to: to
	<function>
	<var: #from type: 'char *'>
	<var: #to type: 'char *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
resize: p rows: rows columns: cols
	<function>
	<var: #p type: 'int32_t'>
	<var: #rows type: 'int32_t'>
	<var: #cols type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
seek: f to: pos
	<function>
	<var: #f type: 'int32_t'>
	<var: #pos type: 'int64_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
semaphores: s read: readIndex write: writeIndex
	<function>
	<var: #s type: 'int32_t'>
	<var: #readIndex type: 'int32_t'>
	<var: #writeIndex type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
send: s bytes: buf count: n
	<function>
	<var: #s type: 'int32_t'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
!
size: f
	<function>
	<var: #f type: 'int32_t'>
	<returns: 'off_t'>
	common setError: 'not on UEFI'.
	^-1
!
spawn: aArgv
	<function>
	<var: #aArgv type: 'char **'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
!
spawn: aArgv environment: envp directory: cwd rows: rows columns: cols pid: pidOut
	<function>
	<var: #aArgv type: 'char **'>
	<var: #envp type: 'char **'>
	<var: #cwd type: 'char *'>
	<var: #rows type: 'int32_t'>
	<var: #cols type: 'int32_t'>
	<var: #pidOut type: 'int64_t *'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
start: s host: hostName
	<function>
	<var: #s type: 'int32_t'>
	<var: #hostName type: 'char *'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
stat: aPath into: s
	<function>
	<var: #aPath type: 'char *'>
	<var: #s type: 'pf_stat *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
wait: p block: aBlock status: aStatus done: aDone
	<function>
	<var: #p type: 'int32_t'>
	<var: #aBlock type: 'bool'>
	<var: #aStatus type: 'int *'>
	<var: #aDone type: 'bool *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
write: f bytes: buf count: n
	<function>
	<var: #f type: 'int32_t'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
! !
