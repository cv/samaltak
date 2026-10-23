ParseNode subclass: #BraceNode
	instanceVariableNames: 'elements'
	classVariableNames: ''
	package: 'Compiler'!

!BraceNode class methodsFor: 'instance creation'!
elements: anArray start: startInteger stop: stopInteger
	^self new setElements: anArray; start: startInteger stop: stopInteger
! !

!BraceNode methodsFor: 'accessing'!
elements
	^elements
!
setElements: anArray
	elements := anArray
! !

!BraceNode methodsFor: 'code generation'!
emitValue: aCodeGenerator
	aCodeGenerator emitBrace: self
! !
