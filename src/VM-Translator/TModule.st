Object subclass: #TModule
	instanceVariableNames: 'moduleClass globals functions registers'
	classVariableNames: ''
	package: 'VM-Translator'!

TModule comment: 'I am a VMModule subclass as the translator sees it: its declared variables (TGlobals, C globals or interpreter registers) and its methods (TFunctions).'!

!TModule class methodsFor: 'instance creation'!
on: aModuleClass translator: aTranslator
	^self new setClass: aModuleClass translator: aTranslator
! !

!TModule methodsFor: 'initialization'!
setClass: aModuleClass translator: aTranslator
	moduleClass := aModuleClass.
	registers := aModuleClass registers collect: [:each | each asString].
	globals := Dictionary new.
	moduleClass == VMModule ifFalse: [self declareGlobalsIn: aTranslator].
	functions := Dictionary new.
	moduleClass selectors do: [:sel |
		((moduleClass ~~ VMModule or: [((moduleClass compiledMethodAt: sel) pragmas ifNil: [#()]) anySatisfy: [:p | p selector == #intrinsic]])
			and: [aTranslator includesMethod: (moduleClass compiledMethodAt: sel)])
				ifTrue: [functions at: sel put: (TFunction module: self selector: sel translator: aTranslator)]]
!
declareGlobalsIn: aTranslator
	"My declarations and the module connections my abstract superclasses declare."
	moduleClass allDeclarations do: [:decl |
		| name g |
		name := (decl at: 1) asString.
		(moduleClass allInstVarNames includes: name) ifFalse: [
			aTranslator error: 'declared variable ' , name , ' is not an instance variable of ' , moduleClass name].
		g := TGlobal module: self declaration: decl translator: aTranslator.
		((moduleClass instVarNames includes: name) or: [g isModuleReference]) ifFalse: [
			aTranslator error: moduleClass name , ': only module connections may be inherited (' , name , ')'].
		globals at: name put: g].
	moduleClass instVarNames do: [:name |
		(globals includesKey: name) ifFalse: [aTranslator error: moduleClass name , ' declares no type for ' , name]]
! !

!TModule methodsFor: 'accessing'!
moduleClass
	^moduleClass
!
name
	^moduleClass name
!
cFileName
	^moduleClass cFileName
!
globals
	^globals
!
globalNamed: aString
	^globals at: aString ifAbsent: [nil]
!
functions
	^functions
!
functionAt: aSymbol
	^functions at: aSymbol ifAbsent: [nil]
!
isRegister: aString
	^registers includes: aString
!
registers
	^registers
!
headerIncludes
	^moduleClass respondsTo: #headers
! !

!TModule methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'TModule('; nextPutAll: self name; nextPut: $)
! !

Object subclass: #TGlobal
	instanceVariableNames: 'module name cName type typeName initialValue referencedModule isRegister usedOutside'
	classVariableNames: ''
	package: 'VM-Translator'!

TGlobal comment: 'I am a declared instance variable of a module: a C global (static unless another module uses it), an interpreter register (a local of the interpreter function), or a connection to another module or library (no C at all).'!

!TGlobal class methodsFor: 'instance creation'!
module: aTModule declaration: anArray translator: aTranslator
	^self new setModule: aTModule declaration: anArray translator: aTranslator
! !

!TGlobal methodsFor: 'initialization'!
setModule: aTModule declaration: anArray translator: aTranslator
	| ref |
	module := aTModule.
	name := (anArray at: 1) asString.
	typeName := (anArray at: 2) asString.
	initialValue := anArray size > 2 ifTrue: [anArray at: 3] ifFalse: [nil].
	isRegister := aTModule isRegister: name.
	usedOutside := false.
	ref := Smalltalk at: typeName asSymbol ifAbsent: [nil].
	(ref isBehavior and: [(ref inheritsFrom: VMModule) or: [ref inheritsFrom: CLibrary]])
		ifTrue: [referencedModule := aTranslator implementationOf: ref. ^self].
	cName := LowtalkNames snake: name.
	type := aTranslator registry parse: typeName
! !

!TGlobal methodsFor: 'accessing'!
name
	^name
!
cName
	^cName
!
type
	^type
!
module
	^module
!
initialValue
	^initialValue
!
referencedModule
	"The VMModule or CLibrary subclass I connect to (for an arch interface, its subclass for the CPU translated for), or nil."
	^referencedModule
!
isModuleReference
	^referencedModule notNil
!
isRegister
	^isRegister
!
noteUsedFrom: aTModule
	aTModule == module ifFalse: [usedOutside := true]
!
isUsedOutside
	^usedOutside
! !

!TGlobal methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'TGlobal('; nextPutAll: name; nextPutAll: ' '; nextPutAll: typeName; nextPut: $)
! !
