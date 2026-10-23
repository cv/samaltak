ParseNode subclass: #MethodNode
	instanceVariableNames: 'selector arguments temporaries pragmas primitive errorCodeVariable body source isDoIt'
	classVariableNames: ''
	package: 'Compiler'!

MethodNode comment: 'I am the root of a parsed method or do-it. primitive is nil, an Integer or a primitive name; errorCodeVariable is the VariableNode of <primitive: ... error: ec>.'!

!MethodNode methodsFor: 'accessing'!
selector
	^selector
!
selector: aSymbol
	selector := aSymbol
!
arguments
	^arguments
!
arguments: anArray
	arguments := anArray
!
temporaries
	^temporaries
!
temporaries: anArray
	temporaries := anArray
!
pragmas
	pragmas isNil ifTrue: [pragmas := OrderedCollection new].
	^pragmas
!
addPragma: aPragmaNode
	self pragmas add: aPragmaNode
!
primitive
	^primitive
!
primitive: anIntegerOrString
	primitive := anIntegerOrString
!
errorCodeVariable
	^errorCodeVariable
!
errorCodeVariable: aVariableNode
	errorCodeVariable := aVariableNode
!
body
	^body
!
body: aSequenceNode
	body := aSequenceNode
!
source
	^source
!
source: aString
	source := aString
!
isDoIt
	^isDoIt == true
!
beDoIt
	isDoIt := true
! !
