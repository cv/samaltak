ParseNode subclass: #AssignmentNode
	instanceVariableNames: 'variable value'
	classVariableNames: ''
	package: 'Compiler'!

!AssignmentNode class methodsFor: 'instance creation'!
variable: aVariableNode value: aNode start: startInteger stop: stopInteger
	^self new setVariable: aVariableNode value: aNode; start: startInteger stop: stopInteger
! !

!AssignmentNode methodsFor: 'accessing'!
variable
	^variable
!
value
	^value
!
setVariable: aVariableNode value: aNode
	variable := aVariableNode.
	value := aNode
! !

!AssignmentNode methodsFor: 'testing'!
isAssignment
	^true
! !

!AssignmentNode methodsFor: 'code generation'!
emitEffect: aCodeGenerator
	aCodeGenerator emitAssignment: self forValue: false
!
emitValue: aCodeGenerator
	aCodeGenerator emitAssignment: self forValue: true
! !
