Error subclass: #SyntaxError
	instanceVariableNames: 'position source'
	classVariableNames: ''
	package: 'Compiler'!

SyntaxError comment: 'I am signaled by the compiler. position is the 1-based index into source where the problem was detected; messageText says what is wrong.'!

!SyntaxError methodsFor: 'accessing'!
position
	^position
!
position: anInteger
	position := anInteger
!
source
	^source
!
source: aString
	source := aString
! !

!SyntaxError class methodsFor: 'signaling'!
signal: aString at: anInteger in: sourceString
	^self new
		position: anInteger;
		source: sourceString;
		signal: aString
! !
