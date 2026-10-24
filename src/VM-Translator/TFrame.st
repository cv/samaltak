Object subclass: #TFrame
	instanceVariableNames: 'kind function module parent env resultVar exitLabel valueWanted returnType bytecode returnCount'
	classVariableNames: ''
	package: 'VM-Translator'!

TFrame comment: 'I am a method being translated: the C function itself (#function), an inline expansion (#inline), a bytecode handler (#handler) or a label of the interpreter loop (#label). Returns inside me (also from blocks defined in me) go where my kind says. bytecode is the constant bytecode of a specialized handler.'!

!TFrame class methodsFor: 'instance creation'!
kind: aSymbol function: aTFunction module: aTModule parent: aTFrame
	^self new setKind: aSymbol function: aTFunction module: aTModule parent: aTFrame
! !

!TFrame methodsFor: 'initialization'!
setKind: aSymbol function: aTFunction module: aTModule parent: aTFrame
	kind := aSymbol.
	function := aTFunction.
	module := aTModule.
	parent := aTFrame.
	env := TEnv parent: nil.
	valueWanted := false.
	returnCount := 0
! !

!TFrame methodsFor: 'accessing'!
kind
	^kind
!
function
	^function
!
module
	^module
!
parent
	^parent
!
env
	^env
!
resultVar
	^resultVar
!
resultVar: aCVarRef
	resultVar := aCVarRef
!
exitLabel
	^exitLabel
!
exitLabel: aString
	exitLabel := aString
!
valueWanted
	^valueWanted
!
valueWanted: aBoolean
	valueWanted := aBoolean
!
returnType
	^returnType
!
returnType: aCType
	returnType := aCType
!
bytecode
	"The constant bytecode of the specialized handler I am in (or expand into), or nil."
	bytecode notNil ifTrue: [^bytecode].
	^parent isNil ifTrue: [nil] ifFalse: [parent bytecode]
!
bytecode: anInteger
	bytecode := anInteger
!
noteReturn
	returnCount := returnCount + 1
!
returnCount
	^returnCount
!
isInterpreterFrame
	^kind == #handler or: [kind == #label]
! !

Object subclass: #TEnv
	instanceVariableNames: 'bindings parent'
	classVariableNames: ''
	package: 'VM-Translator'!

!TEnv class methodsFor: 'instance creation'!
parent: aTEnvOrNil
	^self new setParent: aTEnvOrNil
! !

!TEnv methodsFor: 'initialization'!
setParent: aTEnvOrNil
	parent := aTEnvOrNil.
	bindings := Dictionary new
! !

!TEnv methodsFor: 'accessing'!
at: aString put: aTBinding
	^bindings at: aString put: aTBinding
!
lookup: aString
	^bindings at: aString ifAbsent: [parent isNil ifTrue: [nil] ifFalse: [parent lookup: aString]]
!
child
	^TEnv parent: self
! !

Object subclass: #TBinding
	instanceVariableNames: 'kind cName type expression blockNode frame env'
	classVariableNames: ''
	package: 'VM-Translator'!

TBinding comment: 'What a name means in a TEnv: a C local (#local: cName, type, maybe not known before the first assignment), a substituted argument of an inline expansion (#expr), or a block argument of an inline expansion (#block: the BlockNode with the frame and environment it was written in).'!

!TBinding class methodsFor: 'instance creation'!
local: aString type: aCTypeOrNil
	^self new setKind: #local; setCName: aString type: aCTypeOrNil
!
expression: aCExpr
	^self new setKind: #expr; setExpression: aCExpr
!
block: aBlockNode frame: aTFrame env: aTEnv
	^self new setKind: #block; setBlock: aBlockNode frame: aTFrame env: aTEnv
! !

!TBinding methodsFor: 'initialization'!
setKind: aSymbol
	kind := aSymbol
!
setCName: aString type: aCType
	cName := aString.
	type := aCType
!
setExpression: aCExpr
	expression := aCExpr
!
setBlock: aBlockNode frame: aTFrame env: aTEnv
	blockNode := aBlockNode.
	frame := aTFrame.
	env := aTEnv
! !

!TBinding methodsFor: 'accessing'!
kind
	^kind
!
cName
	^cName
!
type
	^type
!
type: aCType
	type := aCType
!
expression
	^expression
!
blockNode
	^blockNode
!
frame
	^frame
!
env
	^env
!
isBlock
	^kind == #block
!
reference
	^CVarRef name: cName type: type
! !
