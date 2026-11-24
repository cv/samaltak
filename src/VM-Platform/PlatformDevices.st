VMPlatformModule subclass: #PlatformDevices
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformDevices comment: 'Devices of the operating system as drivers in Smalltalk reach them (the device primitives of PlatformPrimitives, PosixDevice in the image): open(2) with the caller''s flags, close(2), ioctl(2) with a word (an integer or an address of Machine memory), pread(2) and pwrite(2) at an offset, read(2) and write(2) where the offset is negative (evdev, which refuses pread), mmap(2) of a descriptor (or anonymous memory) and munmap(2). The descriptors are raw (not in a handle table): the image owns them. Each answers its result, or minus errno where the call failed, the error string set to the call''s strerror. constants: fills the host''s values of the flags and requests the image names (they differ between Linux and macOS). On UEFI, VM-UEFI''s UefiNoIO replaces me: every call answers PF_NO_DEVICES, and the primitive fails.'!

!PlatformDevices methodsFor: 'devices'!
failed: what
	"Minus errno, the error string set to what: its strerror."
	<function>
	<var: #what type: 'char *'>
	<returns: 'int64_t'>
	| e |
	e := posixIO errno.
	common failOS: what code: e.
	^0 - e asInt64
!
deviceOpen: path flags: flags
	"open(path, flags, 0644) -> the descriptor, or minus errno."
	<function>
	<var: #path type: 'char *'>
	<var: #flags type: 'int32_t'>
	<returns: 'int64_t'>
	| fd |
	[fd := posixIO open: path flags: flags mode: 8r644.
	 fd < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	fd < 0 ifTrue: [
		fd := posixIO errno.
		common failOS: 'open' path: path code: fd.
		^0 - fd asInt64].
	^fd asInt64
!
deviceClose: fd
	"close(fd) -> 0, or minus errno (EINTR counts as closed)."
	<function>
	<var: #fd type: 'int32_t'>
	<returns: 'int64_t'>
	((posixIO close: fd) < 0 and: [posixIO errno ~= posixIO EINTR]) ifTrue: [^self failed: 'close'].
	^0
!
deviceIoctl: fd request: request argument: argument
	"ioctl(fd, request, argument) -> its result, or minus errno; retried on EINTR."
	<function>
	<var: #fd type: 'int32_t'>
	<var: #request type: 'uint64_t'>
	<var: #argument type: 'uint64_t'>
	<returns: 'int64_t'>
	| r |
	[r := posixProcesses ioctl: fd request: request argument: (self cCoerce: argument to: 'void *').
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [^self failed: 'ioctl'].
	^r asInt64
!
deviceMap: length protection: prot flags: flags fd: fd offset: offset
	"mmap(NULL, length, prot, flags, fd, offset) -> the address, or minus errno."
	<function>
	<var: #length type: 'uint64_t'>
	<var: #prot type: 'int32_t'>
	<var: #flags type: 'int32_t'>
	<var: #fd type: 'int32_t'>
	<var: #offset type: 'int64_t'>
	<returns: 'int64_t'>
	| p |
	p := posix mmap: self null length: length protection: prot flags: flags file: fd offset: offset.
	p = posix MAP_FAILED ifTrue: [^self failed: 'mmap'].
	^(self cCoerce: p to: 'int64_t')
!
deviceRead: fd address: address count: n offset: offset
	"pread(fd, address, n, offset), or read(fd, address, n) for a negative offset -> the bytes read, or minus errno; retried on EINTR."
	<function>
	<var: #fd type: 'int32_t'>
	<var: #address type: 'uint64_t'>
	<var: #n type: 'uint64_t'>
	<var: #offset type: 'int64_t'>
	<returns: 'int64_t'>
	| r |
	[r := offset < 0
		ifTrue: [posixIO read: fd into: (self cCoerce: address to: 'void *') count: n]
		ifFalse: [posixProcesses pread: fd into: (self cCoerce: address to: 'void *') count: n offset: offset].
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [^self failed: (offset < 0 ifTrue: ['read'] ifFalse: ['pread'])].
	^r asInt64
!
deviceWrite: fd address: address count: n offset: offset
	"pwrite(fd, address, n, offset), or write(fd, address, n) for a negative offset -> the bytes written, or minus errno; retried on EINTR."
	<function>
	<var: #fd type: 'int32_t'>
	<var: #address type: 'uint64_t'>
	<var: #n type: 'uint64_t'>
	<var: #offset type: 'int64_t'>
	<returns: 'int64_t'>
	| r |
	[r := offset < 0
		ifTrue: [posixIO write: fd bytes: (self cCoerce: address to: 'void *') count: n]
		ifFalse: [posixProcesses pwrite: fd from: (self cCoerce: address to: 'void *') count: n offset: offset].
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [^self failed: (offset < 0 ifTrue: ['write'] ifFalse: ['pwrite'])].
	^r asInt64
!
deviceUnmap: address length: length
	"munmap(address, length) -> 0, or minus errno."
	<function>
	<var: #address type: 'uint64_t'>
	<var: #length type: 'uint64_t'>
	<returns: 'int64_t'>
	(posix munmap: (self cCoerce: address to: 'void *') length: length) < 0 ifTrue: [^self failed: 'munmap'].
	^0
!
deviceConstants: v
	"The host's O_RDONLY O_WRONLY O_RDWR O_CLOEXEC O_NONBLOCK O_NOCTTY PROT_READ PROT_WRITE MAP_SHARED MAP_PRIVATE FIONREAD TIOCGWINSZ TIOCSWINSZ MAP_ANON into v (PF_DEVICE_CONSTANTS); answer whether there are devices."
	<function>
	<var: #v type: 'int64_t *'>
	<returns: 'bool'>
	v at: 0 put: posixIO O_RDONLY.
	v at: 1 put: posixIO O_WRONLY.
	v at: 2 put: posixIO O_RDWR.
	v at: 3 put: posixIO O_CLOEXEC.
	v at: 4 put: posixIO O_NONBLOCK.
	v at: 5 put: posixIO O_NOCTTY.
	v at: 6 put: posix PROT_READ.
	v at: 7 put: posix PROT_WRITE.
	v at: 8 put: posix MAP_SHARED.
	v at: 9 put: posix MAP_PRIVATE.
	v at: 10 put: posixProcesses FIONREAD asInt64.
	v at: 11 put: posixProcesses TIOCGWINSZ asInt64.
	v at: 12 put: posixProcesses TIOCSWINSZ asInt64.
	v at: 13 put: posix MAP_ANON.
	^true
! !
