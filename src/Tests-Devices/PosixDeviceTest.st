TestCase subclass: #PosixDeviceTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Devices'!

PosixDeviceTest comment: 'PosixDevice on a host, without a GPU: ioctl on a file (FIONREAD) and on a pseudo-terminal master (TIOCSWINSZ, TIOCGWINSZ through Machine memory), mmap of a scratch file read and written through Machine, munmap, and the OSErrors (ENOENT, EBADF, ENOTTY, EINVAL, bad arguments). On UEFI (a firmware, no operating system) each test checks instead that every call fails cleanly.'!

!PosixDeviceTest methodsFor: 'private'!
onFirmware
	"On UEFI: no devices, every call signals an OSError without errno."
	| e |
	self deny: PosixDevice isAvailable.
	e := [PosixDevice open: '/dev/null' flags: PosixDevice O_RDWR. nil] on: OSError do: [:x | x return: x].
	self assert: e notNil.
	self assert: e errno isNil.
	self assert: (e messageText includesSubstring: 'not on UEFI').
	self should: [PosixDevice ioctl: 0 request: PosixDevice FIONREAD argument: 0] raise: OSError.
	self should: [PosixDevice mmap: 4096 protection: PosixDevice PROT_READ flags: PosixDevice MAP_SHARED fd: 0 offset: 0] raise: OSError.
	self should: [PosixDevice munmap: 4096 length: 4096] raise: OSError.
	self should: [PosixDevice close: 0] raise: OSError
!
errorOf: aBlock
	^aBlock on: OSError do: [:e | e return: e]
!
openRW: path
	^PosixDevice open: path flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC)
! !

!PosixDeviceTest methodsFor: 'tests'!
testIoctlOnAFile
	| path fd n |
	Machine hasFirmware ifTrue: [^self onFirmware].
	self assert: PosixDevice isAvailable.
	path := self scratchPath: 'data'.
	File writeBytes: (ByteArray new: 100 withAll: 7) to: path.
	fd := self openRW: path.
	n := Machine allocate: 8.
	[self assert: (PosixDevice ioctl: fd request: PosixDevice FIONREAD argument: n) equals: 0.
	self assert: (Machine int32At: n) equals: 100]
		ensure: [Machine free: n. PosixDevice close: fd]
!
testIoctlOnAPseudoTerminal
	"Set a pty master's window size from Machine memory, then read it back into other memory."
	| fd ws got |
	Machine hasFirmware ifTrue: [^self onFirmware].
	fd := PosixDevice open: '/dev/ptmx' flags: ((PosixDevice O_RDWR bitOr: PosixDevice O_NOCTTY) bitOr: PosixDevice O_CLOEXEC).
	ws := Machine allocate: 8.
	got := Machine allocate: 8.
	[Machine uint16At: ws put: 24; uint16At: ws + 2 put: 80.
	self assert: (PosixDevice ioctl: fd request: PosixDevice TIOCSWINSZ argument: ws) equals: 0.
	self assert: (PosixDevice ioctl: fd request: PosixDevice TIOCGWINSZ argument: got) equals: 0.
	self assert: (Machine uint16At: got) equals: 24.
	self assert: (Machine uint16At: got + 2) equals: 80]
		ensure: [Machine free: ws; free: got. PosixDevice close: fd]
!
testMmapOfAFile
	"Map the second 64 KB (a page offset on 4 KB and 64 KB pages) shared, read and write it through Machine."
	| path bytes fd a |
	Machine hasFirmware ifTrue: [^self onFirmware].
	path := self scratchPath: 'mapped'.
	bytes := ByteArray new: 131072.
	bytes at: 65537 put: 16r78; at: 65538 put: 16r56; at: 65539 put: 16r34; at: 65540 put: 16r12.
	File writeBytes: bytes to: path.
	fd := self openRW: path.
	[a := PosixDevice mmap: 65536 protection: (PosixDevice PROT_READ bitOr: PosixDevice PROT_WRITE) flags: PosixDevice MAP_SHARED fd: fd offset: 65536.
	self assert: a > 0.
	self assert: (Machine uint32At: a) equals: 16r12345678.
	Machine uint64At: a + 8 put: 16r0102030405060708.
	Machine bytesAt: a + 65532 put: #[9 8 7 6].
	PosixDevice munmap: a length: 65536]
		ensure: [PosixDevice close: fd].
	bytes := File readBytes: path.
	self assert: (bytes copyFrom: 65545 to: 65552) equals: #[8 7 6 5 4 3 2 1].
	self assert: (bytes copyFrom: 131069 to: 131072) equals: #[9 8 7 6].
	self assert: (bytes copyFrom: 1 to: 4) equals: #[0 0 0 0]
!
testErrors
	| e path fd |
	Machine hasFirmware ifTrue: [^self onFirmware].
	path := self scratchPath: 'absent'.
	e := self errorOf: [self openRW: path].
	self assert: e errno equals: OSError ENOENT.
	self assert: e path equals: path.
	self assert: (e messageText includesSubstring: path).
	self assert: (e isKindOf: FileError).
	e := self errorOf: [PosixDevice close: -1].
	self assert: e errno equals: OSError EBADF.
	e := self errorOf: [PosixDevice ioctl: 1000000 request: PosixDevice FIONREAD argument: 0].
	self assert: e errno equals: OSError EBADF.
	self assert: (e messageText beginsWith: 'ioctl: ').
	File writeBytes: #[1 2 3] to: (self scratchPath: 'file').
	fd := self openRW: (self scratchPath: 'file').
	[e := self errorOf: [PosixDevice ioctl: fd request: PosixDevice TIOCGWINSZ argument: 0].
	self assert: e errno equals: OSError ENOTTY.
	e := self errorOf: [PosixDevice mmap: 0 protection: PosixDevice PROT_READ flags: PosixDevice MAP_SHARED fd: fd offset: 0].
	self assert: e errno equals: OSError EINVAL.
	e := self errorOf: [PosixDevice mmap: 4096 protection: PosixDevice PROT_READ flags: PosixDevice MAP_SHARED fd: fd offset: 1].
	self assert: e errno equals: OSError EINVAL]
		ensure: [PosixDevice close: fd].
	e := self errorOf: [PosixDevice munmap: 4097 length: 4096].
	self assert: e errno equals: OSError EINVAL.
	e := self errorOf: [PosixDevice ioctl: 'x' request: 0 argument: 0].
	self assert: e errno isNil.
	self assert: e messageText equals: 'ioctl: bad arguments'.
	self should: [PosixDevice mmap: -1 protection: 0 flags: 0 fd: 0 offset: 0] raise: OSError
! !
