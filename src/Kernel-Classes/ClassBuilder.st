Object subclass: #ClassBuilder
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Classes'!

ClassBuilder comment: 'I create and redefine classes at run time (the bootstrapper builds the seed classes itself). A new class gets a fresh Metaclass. Redefining a class keeps its identity: I change it in place, recompile its methods and those of its subclasses when instance variables move, and migrate live instances with becomeForward:.'!

!ClassBuilder methodsFor: 'building'!
superclass: aClass subclass: aSymbol instanceVariableNames: ivarString classVariableNames: cvarString package: aString type: aType
	"Answer the class named aSymbol with the given definition, creating or redefining it."
	| ivars cvars existing |
	ivars := ivarString substrings asArray.
	cvars := cvarString substrings collect: [:each | each asSymbol].
	self validateName: aSymbol instanceVariables: ivars superclass: aClass.
	existing := Smalltalk at: aSymbol ifAbsent: [nil].
	(existing notNil and: [existing isBehavior not]) ifTrue: [
		^self error: aSymbol, ' is already a global and not a class'].
	existing isNil
		ifTrue: [existing := self newClassNamed: aSymbol superclass: aClass instanceVariables: ivars type: aType]
		ifFalse: [self redefine: existing superclass: aClass instanceVariables: ivars type: aType].
	self setClassVariables: cvars of: existing.
	existing package: aString.
	SystemChanges classDefined: existing.
	^existing
!
newClassNamed: aSymbol superclass: aClass instanceVariables: ivars type: aType
	| meta class |
	meta := Metaclass basicNew.
	meta
		superclass: (aClass isNil ifTrue: [Class] ifFalse: [aClass class])
		methodDictionary: MethodDictionary new
		format: (aClass isNil ifTrue: [Class format] ifFalse: [aClass class format]).
	meta setInstanceVariables: #().
	class := meta basicNew.
	class
		superclass: aClass
		methodDictionary: MethodDictionary new
		format: (self formatFor: ivars superclass: aClass type: aType).
	class setInstanceVariables: ivars.
	class setName: aSymbol.
	class setSubclasses: #().
	class classPool: Dictionary new.
	meta thisClass: class.
	aClass isNil ifFalse: [aClass addSubclass: class].
	Smalltalk at: aSymbol put: class.
	^class
!
redefine: aClass superclass: newSuperclass instanceVariables: ivars type: aType
	| newFormat oldNames |
	newFormat := self formatFor: ivars superclass: newSuperclass type: aType.
	oldNames := aClass allInstVarNames.
	(aClass superclass == newSuperclass
		and: [aClass format = newFormat
		and: [aClass instVarNames asArray = ivars]])
			ifTrue: [^aClass].
	aClass superclass == newSuperclass ifFalse: [
		aClass superclass isNil ifFalse: [aClass superclass removeSubclass: aClass].
		newSuperclass isNil ifFalse: [newSuperclass addSubclass: aClass].
		aClass superclass: newSuperclass.
		aClass class superclass: (newSuperclass isNil ifTrue: [Class] ifFalse: [newSuperclass class]).
		"Cached lookups of any selector may have found a method of the old superclasses."
		aClass flushCache].
	aClass setInstanceVariables: ivars.
	self reshape: aClass format: newFormat oldInstVarNames: oldNames
!
reshape: aClassDescription instanceVariableNames: aString
	"Change the instance variables aClassDescription itself defines (class-side ones for a metaclass)."
	| ivars oldNames |
	ivars := aString substrings asArray.
	aClassDescription instVarNames asArray = ivars ifTrue: [^aClassDescription].
	oldNames := aClassDescription allInstVarNames.
	aClassDescription setInstanceVariables: ivars.
	self
		reshape: aClassDescription
		format: (self formatWithSpec: aClassDescription instSpec size: aClassDescription allInstVarNames size)
		oldInstVarNames: oldNames.
	^aClassDescription
!
reshape: aClass format: newFormat oldInstVarNames: oldNames
	"aClass has new instance variables; fix its format, its instances, its subclasses and recompile."
	| oldInstances |
	oldInstances := aClass allInstances.
	aClass format: newFormat.
	self migrate: oldInstances of: aClass from: oldNames.
	aClass recompile.
	aClass subclasses do: [:sub |
		self
			reshape: sub
			format: (self formatWithSpec: sub instSpec size: aClass instSize + sub instVarNames size)
			oldInstVarNames: (oldNames, sub instVarNames) asArray]
!
formatWithSpec: spec size: instSize
	"Fixed-pointer classes switch between spec 0 and 1 with their size."
	spec <= VMConstants fFixed ifTrue: [
		^((instSize = 0 ifTrue: [VMConstants fEmpty] ifFalse: [VMConstants fFixed]) bitShift: VMConstants clsSpecShift) + instSize].
	^(spec bitShift: VMConstants clsSpecShift) + instSize
!
migrate: oldInstances of: aClass from: oldNames
	"Replace each old instance with a new one of the new shape, copying fields by name."
	| newNames |
	oldInstances isEmpty ifTrue: [^self].
	newNames := aClass allInstVarNames.
	oldInstances do: [:old |
		| new |
		new := aClass isVariable
			ifTrue: [aClass basicNew: old basicSize]
			ifFalse: [aClass basicNew].
		newNames doWithIndex: [:n :i |
			| oldIndex |
			oldIndex := oldNames indexOf: n.
			oldIndex > 0 ifTrue: [new instVarAt: i put: (old instVarAt: oldIndex)]].
		aClass isVariable ifTrue: [
			1 to: old basicSize do: [:i | new basicAt: i put: (old basicAt: i)]].
		old becomeForward: new]
! !

!ClassBuilder methodsFor: 'private'!
formatFor: ivars superclass: aClass type: aType
	"Answer the format word for instances: (instSpec << 16) | instSize."
	| instSize superSpec spec |
	instSize := (aClass isNil ifTrue: [0] ifFalse: [aClass instSize]) + ivars size.
	superSpec := aClass isNil ifTrue: [VMConstants fEmpty] ifFalse: [aClass instSpec].
	aType == #normal ifTrue: [
		spec := superSpec >= VMConstants fVar
			ifTrue: [
				superSpec >= VMConstants fImmediate
					ifTrue: [
						ivars isEmpty ifFalse: [self error: 'Bits classes cannot have named instance variables'].
						superSpec]
					ifFalse: [
						(superSpec = VMConstants fVar and: [instSize > 0]) ifTrue: [VMConstants fFixvar] ifFalse: [superSpec]]]
			ifFalse: [instSize = 0 ifTrue: [VMConstants fEmpty] ifFalse: [VMConstants fFixed]]].
	aType == #variable ifTrue: [spec := instSize = 0 ifTrue: [VMConstants fVar] ifFalse: [VMConstants fFixvar]].
	aType == #weak ifTrue: [spec := VMConstants fWeak].
	aType == #immediate ifTrue: [spec := VMConstants fImmediate].
	(#(#bytes #words #doubleWords) includes: aType) ifTrue: [
		instSize = 0 ifFalse: [self error: 'Bits classes cannot have named instance variables'].
		spec := aType == #bytes
			ifTrue: [VMConstants fBytes]
			ifFalse: [aType == #words ifTrue: [VMConstants fW32] ifFalse: [VMConstants fW64]]].
	spec isNil ifTrue: [self error: 'Unknown class type ', aType printString].
	^(spec bitShift: VMConstants clsSpecShift) + instSize
!
setClassVariables: names of: aClass
	| pool |
	pool := aClass classPool.
	names do: [:n | (pool includesKey: n) ifFalse: [pool add: (Association key: n value: nil)]].
	pool keys do: [:n | (names includes: n) ifFalse: [pool removeKey: n]]
!
validateName: aSymbol instanceVariables: ivars superclass: aClass
	(aSymbol isSymbol and: [aSymbol notEmpty and: [aSymbol first isUppercase]])
		ifFalse: [^self error: 'Class names must be capitalized Symbols'].
	ivars do: [:n |
		(n first isLetter and: [n allSatisfy: [:c | c isAlphaNumeric or: [c = $_]]])
			ifFalse: [^self error: 'Bad instance variable name: ', n].
		(aClass notNil and: [aClass allInstVarNames includes: n])
			ifTrue: [^self error: n, ' is already defined in a superclass']]
! !
