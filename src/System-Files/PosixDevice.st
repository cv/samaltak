Object subclass: #PosixDevice
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Files'!

PosixDevice comment: 'I am the devices of a POSIX host (Linux, macOS) for drivers in Smalltalk (the device primitives, PlatformDevices in the VM, docs/platform.md): open(2), close(2), ioctl(2), mmap(2), munmap(2) on raw file descriptors, all on my class side.

	open: path flags: anInteger	-> fd (flags: my O_ constants, or-ed; nothing is added, so pass O_CLOEXEC)
	close: fd
	ioctl: fd request: anInteger argument: anInteger	-> ioctl''s result (argument: an Integer, or the address of memory outside the heap, Machine allocate:, that the call reads or fills)
	mmap: length protection: p flags: f fd: fd offset: off	-> the address of the mapping (read and write it with Machine uint32At: and its siblings)
	munmap: address length: n

A call that fails signals an OSError with its errno and strerror''s text; one that cannot be made (a bad argument, or no operating system: on UEFI every call fails) an OSError whose errno is nil. The constants (O_RDWR O_CLOEXEC ... PROT_READ PROT_WRITE MAP_SHARED, the requests FIONREAD TIOCGWINSZ TIOCSWINSZ) are the host''s values, asked of the VM at each use (they differ between Linux and macOS; an image moves between them); without devices, Linux''s. isAvailable answers whether there are devices.

The VM does not track descriptors or mappings: close and unmap what you open and map (ensure:). Misused (a wrong address or length), I crash the VM like a driver in C would.'!

!PosixDevice class methodsFor: 'primitives'!
primConstants
	<primitive: 'deviceConstants'>
	^nil
!
primOpen: path flags: anInteger
	<primitive: 'deviceOpen'>
	^nil
!
primClose: fd
	<primitive: 'deviceClose'>
	^nil
!
primIoctl: fd request: request argument: argument
	<primitive: 'deviceIoctl'>
	^nil
!
primMmap: length protection: p flags: f fd: fd offset: offset
	<primitive: 'deviceMap'>
	^nil
!
primMunmap: address length: n
	<primitive: 'deviceUnmap'>
	^nil
! !

!PosixDevice class methodsFor: 'private'!
check: result call: what path: aPath
	"result, if the call was made and succeeded; else signal the OSError."
	result isNil ifTrue: [
		^OSError
			signal: what, ': ', (self isAvailable ifTrue: ['bad arguments'] ifFalse: [File lastError])
			errno: nil
			path: aPath].
	result < 0 ifTrue: [^OSError signal: File lastError errno: result negated path: aPath].
	^result
!
constant: index
	^(self primConstants ifNil: [#(0 1 2 16r80000 16r800 16r100 1 2 1 2 16r541B 16r5413 16r5414)]) at: index
! !

!PosixDevice class methodsFor: 'devices'!
isAvailable
	"Has the VM devices of an operating system (not on UEFI)?"
	^self primConstants notNil
!
open: path flags: anInteger
	"A file descriptor of path opened with the open flags anInteger (and mode 8r644 where they create it)."
	^self check: (self primOpen: path flags: anInteger) call: 'open' path: path
!
close: fd
	self check: (self primClose: fd) call: 'close' path: nil
!
ioctl: fd request: request argument: argument
	"ioctl's result; argument is an Integer, or the address of memory it reads or fills (Machine allocate:)."
	^self check: (self primIoctl: fd request: request argument: argument) call: 'ioctl' path: nil
!
mmap: length protection: p flags: f fd: fd offset: offset
	"The address of length bytes of fd from offset (a multiple of the page size) mapped with protection p (PROT_READ, PROT_WRITE) and flags f (MAP_SHARED, MAP_PRIVATE)."
	^self check: (self primMmap: length protection: p flags: f fd: fd offset: offset) call: 'mmap' path: nil
!
munmap: address length: n
	self check: (self primMunmap: address length: n) call: 'munmap' path: nil
! !

!PosixDevice class methodsFor: 'constants'!
O_RDONLY
	^self constant: 1
!
O_WRONLY
	^self constant: 2
!
O_RDWR
	^self constant: 3
!
O_CLOEXEC
	^self constant: 4
!
O_NONBLOCK
	^self constant: 5
!
O_NOCTTY
	^self constant: 6
!
PROT_READ
	^self constant: 7
!
PROT_WRITE
	^self constant: 8
!
MAP_SHARED
	^self constant: 9
!
MAP_PRIVATE
	^self constant: 10
!
FIONREAD
	"The bytes waiting to be read (an int at the argument's address)."
	^self constant: 11
!
TIOCGWINSZ
	"A terminal's size into a struct winsize (rows, columns, x and y pixels: 4 uint16s) at the argument's address."
	^self constant: 12
!
TIOCSWINSZ
	^self constant: 13
! !
