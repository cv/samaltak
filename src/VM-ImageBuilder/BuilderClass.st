Object subclass: #BuilderClass
	instanceVariableNames: 'name superclassName kind instanceVariables classVariables package sourcePackage file line comment classInstanceVariables allInstVarNames metaInstVarNames instSpec format oop metaOop pool methods classMethods metaclass builder'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

BuilderClass comment: 'A class of the image being built, as ImageBuilder and the compiler see it: its definition, its layout (instance variables, format), its objects in the new image (oop, metaOop), its class variables (BuilderBindings) and compiled methods. The compiler asks me allInstVarNames and bindingOf:, as it would ask a class; my metaclass answers for class-side methods.'!

Object subclass: #BuilderMetaclass
	instanceVariableNames: 'thisClass'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

BuilderMetaclass comment: 'The class side of a BuilderClass, for compiling class-side methods.'!

Object subclass: #BuilderBinding
	instanceVariableNames: 'key value oop'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

BuilderBinding comment: 'A global or class variable of the image being built: its name, its value (an oop of the new image, or nil until known) and its Association there (oop). Compiled methods refer to it as a literal variable.'!

!BuilderClass methodsFor: 'initialization'!
setName: aString superclassName: superString kind: aSymbol instanceVariables: ivars classVariables: cvars package: pkg sourcePackage: srcPkg file: aFile line: aLine
	name := aString.
	superclassName := superString.
	kind := aSymbol.
	instanceVariables := ivars asArray.
	classVariables := cvars asArray.
	package := pkg.
	sourcePackage := srcPkg.
	file := aFile.
	line := aLine.
	classInstanceVariables := #().
	pool := Dictionary new.
	methods := Dictionary new.
	classMethods := Dictionary new.
	metaclass := BuilderMetaclass new setThisClass: self
!
builder: anImageBuilder
	builder := anImageBuilder
! !

!BuilderClass methodsFor: 'accessing'!
name
	^name
!
superclassName
	^superclassName
!
kind
	^kind
!
instanceVariables
	^instanceVariables
!
classVariables
	^classVariables
!
package
	^package
!
sourcePackage
	^sourcePackage
!
file
	^file
!
line
	^line
!
comment
	^comment
!
comment: aString
	comment := aString
!
classInstanceVariables
	^classInstanceVariables
!
classInstanceVariables: anArray
	classInstanceVariables := anArray asArray
!
allInstVarNames
	^allInstVarNames
!
allInstVarNames: anArray
	allInstVarNames := anArray
!
metaInstVarNames
	^metaInstVarNames
!
metaInstVarNames: anArray
	metaInstVarNames := anArray
!
instSpec
	^instSpec
!
instSpec: anInteger
	instSpec := anInteger
!
format
	^format
!
format: anInteger
	format := anInteger
!
oop
	^oop
!
oop: anInteger
	oop := anInteger
!
metaOop
	^metaOop
!
metaOop: anInteger
	metaOop := anInteger
!
pool
	"Class variable name -> BuilderBinding."
	^pool
!
methods
	"Selector -> compiled method oop."
	^methods
!
classMethods
	^classMethods
!
metaclass
	^metaclass
!
isMeta
	^false
!
isContextClass
	"As Behavior>>isContextClass."
	| s |
	name = 'Context' ifTrue: [^true].
	s := builder superOf: self.
	^s notNil and: [s isContextClass]
!
theNonMetaClass
	^self
! !

!BuilderClass methodsFor: 'compiling'!
bindingOf: aSymbol
	"Class variables (mine and inherited), then globals."
	^builder bindingOf: aSymbol asString from: self
! !

!BuilderClass methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'BuilderClass('; nextPutAll: name; nextPut: $)
! !

!BuilderMetaclass methodsFor: 'accessing'!
setThisClass: aBuilderClass
	thisClass := aBuilderClass
!
thisClass
	^thisClass
!
theNonMetaClass
	^thisClass
!
name
	^thisClass name , ' class'
!
allInstVarNames
	^thisClass metaInstVarNames
!
isMeta
	^true
!
isContextClass
	^false
!
oop
	^thisClass metaOop
!
bindingOf: aSymbol
	^thisClass bindingOf: aSymbol
! !

!BuilderBinding class methodsFor: 'instance creation'!
key: aString value: anOop
	^self new setKey: aString value: anOop
! !

!BuilderBinding methodsFor: 'accessing'!
setKey: aString value: anOop
	key := aString.
	value := anOop
!
key
	^key
!
value
	^value
!
value: anOop
	value := anOop
!
oop
	^oop
!
oop: anInteger
	oop := anInteger
! !

!BuilderBinding methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'BuilderBinding('; nextPutAll: key; nextPut: $)
! !

CodeGenerator subclass: #BuilderCodeGenerator
	instanceVariableNames: 'builder'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

BuilderCodeGenerator comment: 'The compiler, compiling for the image being built: globals and class variables are its BuilderBindings (undeclared names are reported and bound in its Undeclared), primitive names are numbered as the VM sources (the <vmPrimitive:name:> methods) number them.'!

!BuilderCodeGenerator methodsFor: 'accessing'!
builder: anImageBuilder
	builder := anImageBuilder
! !

!BuilderCodeGenerator methodsFor: 'variables'!
lookupVariable: aVariableNode
	builder noteNode: aVariableNode.
	^super lookupVariable: aVariableNode
!
globalBindingOf: aString
	^builder bindingOf: aString inMethod: methodNode class: targetClass
!
primitiveNumberFor: anIntegerOrString
	anIntegerOrString isNil ifTrue: [^0].
	anIntegerOrString isInteger ifTrue: [^anIntegerOrString].
	^builder primitiveNumberOf: anIntegerOrString asString ifAbsent: [
		self error: 'Unknown primitive ''' , anIntegerOrString asString , '''' at: methodNode start]
! !
