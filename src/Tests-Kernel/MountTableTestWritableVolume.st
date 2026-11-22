MountTableTestVolume subclass: #MountTableTestWritableVolume
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

MountTableTestWritableVolume comment: 'I am a MountTableTestVolume that can be written, with the writing protocol of MountTable''s volumes (open:mode:, delete:, rename:to:, createDirectory:), as FirmwareFileSystem has it: a file opened on me is a MountTableTestFile.'!

!MountTableTestWritableVolume methodsFor: 'writing'!
open: aPath mode: mode
	| st |
	st := nodes at: aPath ifAbsent: [
		mode = 0 ifTrue: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
		(nodes includesKey: (self parentOf: aPath)) ifFalse: [^FileDoesNotExist signal: 'No such directory: ', aPath path: aPath].
		nodes at: aPath put: (MountTableTestStat data: ByteArray new)].
	st isDirectory ifTrue: [^FileError signal: 'Is a directory: ', aPath path: aPath].
	mode = 3 ifTrue: [st bytes: ByteArray new].
	^MountTableTestFile on: st name: aPath position: (mode = 2 ifTrue: [st size] ifFalse: [0]) writable: mode ~= 0
!
delete: aPath
	| st |
	st := self stat: aPath.
	(st isDirectory and: [(self entriesAt: aPath) notEmpty]) ifTrue: [^FileError signal: 'Directory not empty: ', aPath path: aPath].
	nodes removeKey: aPath
!
rename: oldPath to: newPath
	(self stat: oldPath) isDirectory ifTrue: [^FileError signal: 'Not supported here: ', oldPath path: oldPath].
	(nodes includesKey: (self parentOf: newPath)) ifFalse: [^FileDoesNotExist signal: 'No such directory: ', newPath path: newPath].
	nodes at: newPath put: (nodes removeKey: oldPath)
!
createDirectory: aPath
	(nodes includesKey: aPath) ifTrue: [^FileExists signal: 'File exists: ', aPath path: aPath].
	self directory: aPath
! !

!MountTableTestWritableVolume methodsFor: 'private'!
parentOf: aPath
	| i |
	i := aPath lastIndexOf: $/.
	^i <= 1 ifTrue: ['/'] ifFalse: [aPath copyFrom: 1 to: i - 1]
! !
