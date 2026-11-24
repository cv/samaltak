FileError subclass: #OSError
	instanceVariableNames: 'errno'
	classVariableNames: ''
	package: 'System-Files'!

OSError comment: 'I am signaled when a call of the operating system fails (PosixDevice): errno is its error number (nil where the call could not be made at all: bad arguments, or no operating system, as on UEFI), messageText the call and strerror''s text ("ioctl: Inappropriate ioctl for device"), path the file it was about, if any. The error numbers on my class side are the same on Linux and macOS.'!

!OSError methodsFor: 'accessing'!
errno
	^errno
!
errno: anInteger
	errno := anInteger
! !

!OSError class methodsFor: 'signaling'!
signal: aString errno: anInteger path: aPath
	^self new errno: anInteger; path: aPath; signal: aString
! !

!OSError class methodsFor: 'error numbers'!
ENOENT
	^2
!
EBADF
	^9
!
EAGAIN
	"Linux's (macOS's is 35): a non-blocking descriptor has nothing now."
	^11
!
ENOMEM
	^12
!
EACCES
	^13
!
EFAULT
	^14
!
EBUSY
	^16
!
EEXIST
	^17
!
ENODEV
	^19
!
EINVAL
	^22
!
ENOTTY
	^25
! !
