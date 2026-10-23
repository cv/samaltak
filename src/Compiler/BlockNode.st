ParseNode subclass: #BlockNode
	instanceVariableNames: 'arguments temporaries body'
	classVariableNames: ''
	package: 'Compiler'!

!BlockNode class methodsFor: 'instance creation'!
arguments: argArray temporaries: tempArray body: aSequenceNode start: startInteger stop: stopInteger
	^self new setArguments: argArray temporaries: tempArray body: aSequenceNode; start: startInteger stop: stopInteger
! !

!BlockNode methodsFor: 'accessing'!
arguments
	^arguments
!
temporaries
	^temporaries
!
body
	^body
!
statements
	^body statements
!
setArguments: argArray temporaries: tempArray body: aSequenceNode
	arguments := argArray.
	temporaries := tempArray.
	body := aSequenceNode
! !

!BlockNode methodsFor: 'testing'!
isBlock
	^true
!
isBlockWithArguments: anInteger
	^arguments size = anInteger
! !

!BlockNode methodsFor: 'code generation'!
emitValue: aCodeGenerator
	aCodeGenerator emitClosure: self
! !
