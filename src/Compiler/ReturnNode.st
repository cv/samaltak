ParseNode subclass: #ReturnNode
	instanceVariableNames: 'value'
	classVariableNames: ''
	package: 'Compiler'!

!ReturnNode class methodsFor: 'instance creation'!
value: aNode start: startInteger stop: stopInteger
	^self new setValue: aNode; start: startInteger stop: stopInteger
! !

!ReturnNode methodsFor: 'accessing'!
value
	^value
!
setValue: aNode
	value := aNode
! !

!ReturnNode methodsFor: 'testing'!
isReturn
	^true
! !

!ReturnNode methodsFor: 'code generation'!
emitEffect: aCodeGenerator
	aCodeGenerator emitReturn: self
!
emitValue: aCodeGenerator
	"Control never continues; account for the value an expression would have left."
	aCodeGenerator emitReturn: self.
	aCodeGenerator encoder push
! !
