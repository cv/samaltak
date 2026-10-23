Error subclass: #FileError
	instanceVariableNames: 'path'
	classVariableNames: ''
	package: 'System-Files'!

FileError comment: 'I am signaled when a file operation fails; messageText carries the platform''s reason.'!

!FileError methodsFor: 'accessing'!
path
	^path
!
path: aString
	path := aString
! !

!FileError class methodsFor: 'signaling'!
signal: aString path: aPath
	^self new path: aPath; signal: aString
! !
