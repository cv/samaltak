ParseNode subclass: #VariableNode
	instanceVariableNames: 'name'
	classVariableNames: ''
	package: 'Compiler'!

!VariableNode class methodsFor: 'instance creation'!
name: aString start: startInteger stop: stopInteger
	^self new setName: aString; start: startInteger stop: stopInteger
! !

!VariableNode methodsFor: 'accessing'!
name
	^name
!
setName: aString
	name := aString
! !

!VariableNode methodsFor: 'testing'!
isSelf
	^name = 'self'
!
isSuper
	^name = 'super'
!
isVariable
	^true
! !

!VariableNode methodsFor: 'code generation'!
emitValue: aCodeGenerator
	aCodeGenerator emitVariable: self
! !
