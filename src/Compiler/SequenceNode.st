ParseNode subclass: #SequenceNode
	instanceVariableNames: 'statements'
	classVariableNames: ''
	package: 'Compiler'!

!SequenceNode class methodsFor: 'instance creation'!
statements: anArray start: startInteger stop: stopInteger
	^self new setStatements: anArray; start: startInteger stop: stopInteger
! !

!SequenceNode methodsFor: 'accessing'!
statements
	^statements
!
setStatements: anArray
	statements := anArray
! !
