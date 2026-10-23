TestCase subclass: #ClassTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ClassTest comment: 'Tests reflection on classes, metaclasses and methods, and creating, changing and removing classes at run time.'!

!ClassTest methodsFor: 'running'!
tearDown
	#(#KernelTestTemporary #KernelTestTemporarySub) do: [:name |
		(Smalltalk at: name ifAbsent: [nil]) ifNotNil: [:c | c removeFromSystem]]
! !

!ClassTest methodsFor: 'tests'!
testMetaclassStructure
	self assert: 3 class class class == Metaclass.
	self assert: Metaclass class class == Metaclass.
	self assert: Object class superclass == ProtoObject class.
	self assert: ProtoObject class superclass == Class.
	self assert: Point class thisClass == Point.
	self assert: Point class isMeta.
	self deny: Point isMeta.
	self assert: Point class name = 'Point class'.
	self assert: Point name == #Point.
	self assert: Point printString = 'Point'.
	self assert: Point class printString = 'Point class'
!
testHierarchy
	self assert: (SmallInteger inheritsFrom: Number).
	self deny: (Number inheritsFrom: SmallInteger).
	self assert: (SmallInteger includesBehavior: SmallInteger).
	self assert: (Integer subclasses includes: SmallInteger).
	self assert: (Number allSubclasses includes: LargeNegativeInteger).
	self assert: (SmallInteger allSuperclasses includes: Magnitude).
	self assert: SmallInteger allSuperclasses last == ProtoObject.
	self assert: (Integer withAllSubclasses includes: Integer)
!
testInstanceVariables
	self assert: Point instVarNames asArray = #('x' 'y').
	self assert: Association allInstVarNames asArray = #('key' 'value').
	self assert: Point instSize = 2.
	self assert: Array isVariable.
	self assert: ByteArray isBytes.
	self assert: Bitmap isWords.
	self assert: Context isVariable.
	self assert: Context instSize = 6.
	self deny: Point isVariable.
	self assert: SmallInteger isImmediateClass.
	self assert: Class allInstVarNames asArray = #('superclass' 'methodDict' 'format' 'instanceVariables' 'organization' 'subclasses' 'name' 'classPool' 'sharedPools' 'package' 'comment')
!
testMethods
	| m |
	self assert: (Point includesSelector: #x).
	self deny: (Point includesSelector: #printString).
	self assert: (Point selectors includes: #x:).
	m := Point >> #x.
	self assert: m selector == #x.
	self assert: m methodClass == Point.
	self assert: m printString = 'Point>>x'.
	self assert: m numArgs = 0.
	self assert: m isQuick.
	self assert: (Point sourceCodeAt: #x) notNil.
	self assert: ((Point sourceCodeAt: #x) beginsWith: 'x').
	self assert: (Point >> #x:) numArgs = 1.
	self assert: ((Object >> #printString) sendsSelector: #printOn:).
	self assert: ((SmallInteger >> #+) primitive) > 0.
	self assert: (SmallInteger >> #+) primitiveName = 'intAdd'.
	self assert: ((BlockClosure >> #ensure:) primitive) = VMConstants primEnsureMarker.
	self assert: ((Smalltalk implementorsOf: #printOn:) includes: Object >> #printOn:).
	self assert: ((Smalltalk sendersOf: #printOn:) includes: Object >> #printString)
!
testOrganization
	self assert: (Point categories includes: 'accessing').
	self assert: ((Point selectorsInCategory: 'accessing') includes: #x).
	self assert: (Point categoryOfSelector: #x) = 'accessing'.
	self assert: Point category = 'Kernel-Objects'.
	self assert: Point package name = 'Kernel-Objects'.
	self assert: Point package layer = 0.
	self assert: Point comment notEmpty
!
testCreateClass
	| class instance |
	class := Object subclass: #KernelTestTemporary
		instanceVariableNames: 'a b'
		classVariableNames: 'Shared'
		package: 'Tests-Kernel'.
	self assert: (Smalltalk at: #KernelTestTemporary) == class.
	self assert: class superclass == Object.
	self assert: class class thisClass == class.
	self assert: class instVarNames asArray = #('a' 'b').
	self assert: class classVarNames asArray = #(#Shared).
	self assert: class category = 'Tests-Kernel'.
	self assert: (Object subclasses includes: class).
	instance := class new.
	self assert: instance class == class.
	self assert: (instance instVarAt: 1) isNil.
	self assert: class instanceCount = 1.
	self assert: class name == #KernelTestTemporary.
	self assert: (Smalltalk classNamed: 'KernelTestTemporary') == class.
	class removeFromSystem.
	self deny: (Smalltalk includesKey: #KernelTestTemporary).
	self deny: (Object subclasses includes: class)
!
testVariableClass
	| class instance |
	class := Object variableSubclass: #KernelTestTemporary
		instanceVariableNames: 'tag'
		classVariableNames: ''
		package: 'Tests-Kernel'.
	instance := class new: 3.
	self assert: instance basicSize = 3.
	instance basicAt: 2 put: #two.
	self assert: (instance basicAt: 2) == #two.
	self assert: class instSpec = VMConstants fFixvar
!
testCompileAndRedefine
	| class sub instance |
	(Smalltalk includesKey: #Compiler) ifFalse: [^self skip: 'no compiler'].
	class := Object subclass: #KernelTestTemporary
		instanceVariableNames: 'a'
		classVariableNames: ''
		package: 'Tests-Kernel'.
	class compile: 'a ^a' classified: 'accessing'.
	class compile: 'a: x a := x' classified: 'accessing'.
	self assert: (class includesSelector: #a:).
	self assert: (class categoryOfSelector: #a) = 'accessing'.
	sub := class subclass: #KernelTestTemporarySub
		instanceVariableNames: 'c'
		classVariableNames: ''
		package: 'Tests-Kernel'.
	sub compile: 'c ^c' classified: 'accessing'.
	sub compile: 'c: x c := x' classified: 'accessing'.
	instance := sub new a: 1; c: 3; yourself.
	self assert: instance a = 1.
	self assert: instance c = 3.
	Object subclass: #KernelTestTemporary
		instanceVariableNames: 'z a'
		classVariableNames: ''
		package: 'Tests-Kernel'.
	self assert: (Smalltalk at: #KernelTestTemporary) == class.
	self assert: class instVarNames asArray = #('z' 'a').
	self assert: sub allInstVarNames asArray = #('z' 'a' 'c').
	self assert: instance a = 1.
	self assert: instance c = 3.
	self assert: (instance instVarAt: 1) isNil.
	class removeSelector: #a.
	self deny: (class includesSelector: #a).
	self should: [instance a] raise: MessageNotUnderstood
! !
