VMPlatformModule subclass: #UefiNoIO
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiNoIO comment: 'Files, processes, sockets, TLS and pseudo-terminals on UEFI: none (in place of PlatformFiles, PlatformSockets, PlatformPtys, PlatformTLS and PosixIO). Every call fails with the error ''not on UEFI''; the image works without them (docs/uefi.md).'!

!UefiNoIO class methodsFor: 'declaring'!
targetOS
	^#uefi
!
replaces
	^{PlatformFiles. PlatformSockets. PlatformPtys. PlatformTLS. PosixIO}
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
accept: s wouldBlock: wouldBlock
	<function>
	<var: #s type: 'int32_t'>
	<var: #wouldBlock type: 'bool *'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
add: fd kind: aKind pointer: ptr
	<function>
	<var: #fd type: 'int'>
	<var: #aKind type: 'int'>
	<var: #ptr type: 'void *'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
anyArmed
	<function>
	<returns: 'bool'>
	^false
!
armRead: h
	<function>
	<var: #h type: 'int32_t'>
	common setError: 'not on UEFI'
!
armWrite: h when: armed
	<function>
	<var: #h type: 'int32_t'>
	<var: #armed type: 'bool'>
	common setError: 'not on UEFI'
!
close: f
	<function>
	<var: #f type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
close: h kind: aKind
	<function>
	<var: #h type: 'int32_t'>
	<var: #aKind type: 'int'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
connect: aHost port: aPort
	<function>
	<var: #aHost type: 'char *'>
	<var: #aPort type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
connected: s
	<function>
	<var: #s type: 'int32_t'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^-1
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
fdGet: h kind: aKind
	<function>
	<var: #h type: 'int32_t'>
	<var: #aKind type: 'int'>
	<returns: 'pf_obj *'>
	common setError: 'not on UEFI'.
	^self null
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
listen: aHost port: aPort backlog: backlog
	<function>
	<var: #aHost type: 'char *'>
	<var: #aPort type: 'int32_t'>
	<var: #backlog type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
localPort: s
	<function>
	<var: #s type: 'int32_t'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^-1
!
lookup: hostName
	<function>
	<var: #hostName type: 'char *'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
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
poll: timeoutMs
	<function>
	<var: #timeoutMs type: 'int'>
	common setError: 'not on UEFI'
!
pollFds: pollfds max: max
	<function>
	<var: #pollfds type: 'void *'>
	<var: #max type: 'int'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^-1
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
ptyHandleCount
	<function>
	<returns: 'int32_t'>
	^0
!
ptyRead: p into: buf count: n
	<function>
	<var: #p type: 'int32_t'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
!
ptySemaphores: p read: readIndex write: writeIndex
	<function>
	<var: #p type: 'int32_t'>
	<var: #readIndex type: 'int32_t'>
	<var: #writeIndex type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
ptyWrite: p bytes: buf count: n
	<function>
	<var: #p type: 'int32_t'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-1
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
semaphores: h kind: aKind read: readIndex write: writeIndex
	<function>
	<var: #h type: 'int32_t'>
	<var: #aKind type: 'int'>
	<var: #readIndex type: 'int32_t'>
	<var: #writeIndex type: 'int32_t'>
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
