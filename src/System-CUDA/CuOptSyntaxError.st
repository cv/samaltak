Error subclass: #CuOptSyntaxError
	instanceVariableNames: 'line'
	classVariableNames: ''
	package: 'System-CUDA'!

CuOptSyntaxError comment: 'I am signaled when CuOptProgram cannot read a program''s text: line is the line it stopped at, messageText says why.'!

!CuOptSyntaxError methodsFor: 'accessing'!
line
	^line
!
line: anInteger
	line := anInteger
! !
