ParseNode subclass: #LiteralNode
	instanceVariableNames: 'value'
	classVariableNames: ''
	package: 'Compiler'!

LiteralNode comment: 'I am a literal: number, character, string, symbol, true, false, nil, literal array or byte array.'!

!LiteralNode class methodsFor: 'instance creation'!
value: anObject start: startInteger stop: stopInteger
	^self new setValue: anObject; start: startInteger stop: stopInteger
! !

!LiteralNode methodsFor: 'accessing'!
value
	^value
!
setValue: anObject
	value := anObject
! !

!LiteralNode methodsFor: 'testing'!
isLiteral
	^true
! !

!LiteralNode methodsFor: 'code generation'!
emitEffect: aCodeGenerator
!
emitValue: aCodeGenerator
	aCodeGenerator encoder pushLiteral: value
! !
