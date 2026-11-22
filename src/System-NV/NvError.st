Error subclass: #NvError
	instanceVariableNames: 'status'
	classVariableNames: ''
	package: 'System-NV'!

NvError comment: 'I am signaled when the NVIDIA resource manager (RM) refuses a call: status is its NV_STATUS code (0 is NV_OK), messageText says what failed and the status''s name (NvRm statusName:). A failing ioctl itself signals the error PosixDevice signals.'!

!NvError methodsFor: 'accessing'!
status
	^status
!
status: anInteger
	status := anInteger
! !

!NvError class methodsFor: 'signaling'!
signal: aString status: anInteger
	^self new status: anInteger; signal: aString, ': ', (NvRm statusName: anInteger)
! !
