Error subclass: #RemoteError
	instanceVariableNames: 'code'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteError comment: 'I am a failed remote-control command. code goes into the response and becomes samaltak-ctl''s exit code: 1 error, 2 not found or timed out, 3 Smalltalk error.'!

!RemoteError methodsFor: 'accessing'!
code
	^code ifNil: [1]
!
code: anInteger
	code := anInteger
! !

!RemoteError class methodsFor: 'signaling'!
signal: aString code: anInteger
	^self new code: anInteger; signal: aString
!
signal: aString
	^self signal: aString code: 1
!
notFound: aString
	^self signal: aString code: 2
!
timeout: aString
	^self signal: aString code: 2
! !
