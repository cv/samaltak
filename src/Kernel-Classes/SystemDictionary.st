Dictionary subclass: #SystemDictionary
	instanceVariableNames: ''
	classVariableNames: 'ErrorDepth MainAction MainProcess PackageList Packages RunningTests ShutDownList StartUpList Stage2Steps UnhandledErrorHandler VM'
	package: 'Kernel-Classes'!

SystemDictionary comment: 'I am Smalltalk, the dictionary of global variables (Symbol -> Association; every class is a global). I also answer system-wide questions (all classes, packages, implementors and senders) and give access to the VM. Startup, snapshots and command-line handling are in System-Support.'!

!SystemDictionary methodsFor: 'accessing'!
at: aKey put: anObject
	"Define a global. A reference compiled before the global existed lives in Undeclared; adopt that Association so the reference sees the value."
	| assoc undeclared |
	assoc := self associationAt: aKey ifAbsent: [nil].
	assoc isNil ifFalse: [assoc value: anObject. ^anObject].
	undeclared := self undeclared.
	assoc := undeclared isNil ifFalse: [undeclared associationAt: aKey ifAbsent: [nil]].
	assoc isNil
		ifTrue: [assoc := Association key: aKey value: anObject]
		ifFalse: [
			undeclared removeKey: aKey.
			assoc value: anObject].
	self add: assoc.
	^anObject
!
undeclared
	"Answer the Dictionary of references to globals that do not exist yet."
	| assoc |
	assoc := self associationAt: #Undeclared ifAbsent: [nil].
	^assoc isNil ifTrue: [nil] ifFalse: [assoc value]
!
classNamed: aString
	"Answer the class (or metaclass, for 'Foo class') named aString, or nil."
	| name meta value |
	name := aString asString.
	meta := name endsWith: ' class'.
	meta ifTrue: [name := name copyFrom: 1 to: name size - 6].
	value := self at: name asSymbol ifAbsent: [^nil].
	value isBehavior ifFalse: [^nil].
	^meta ifTrue: [value class] ifFalse: [value]
!
vm
	"Answer the VirtualMachine, the facade for VM primitives."
	VM isNil ifTrue: [VM := VirtualMachine new].
	^VM
! !

!SystemDictionary methodsFor: 'classes'!
allClasses
	"Answer all classes (not metaclasses), sorted by name."
	| result |
	result := OrderedCollection new.
	self allClassesDo: [:c | result add: c].
	^(result asSortedCollection: [:a :b | a name <= b name]) asArray
!
allClassesDo: aBlock
	self associationsDo: [:assoc |
		| value |
		value := assoc value.
		(value isBehavior and: [value isMeta not and: [value name == assoc key]])
			ifTrue: [aBlock value: value]]
!
allClassesAndMetaclasses
	| result |
	result := OrderedCollection new.
	self allBehaviorsDo: [:b | result add: b].
	^result asArray
!
allBehaviorsDo: aBlock
	"Evaluate aBlock for every class and metaclass."
	self allClassesDo: [:c | aBlock value: c; value: c class]
!
classNames
	^(self allClasses collect: [:c | c name]) asArray
!
hasClassNamed: aString
	^(self classNamed: aString) notNil
!
rootClasses
	^self allClasses select: [:c | c superclass isNil]
! !

!SystemDictionary methodsFor: 'packages'!
packages
	"Answer the Packages in load order."
	Packages isNil ifTrue: [self initializePackages].
	^Packages
!
packageNamed: aString
	^self packages detect: [:p | p name = aString] ifNone: [Package named: aString layer: nil]
!
initializePackages
	"PackageList is set by the bootstrapper: an Array of {name. layer} in packages.txt order."
	| list known |
	list := OrderedCollection new.
	(PackageList ifNil: [#()]) do: [:pair | list add: (Package named: pair first layer: pair last)].
	known := list collect: [:p | p name].
	self allClassesDo: [:c |
		(c packageName notNil and: [(known includes: c packageName) not]) ifTrue: [
			list add: (Package named: c packageName layer: nil).
			known add: c packageName]].
	Packages := list asArray
!
addPackageNamed: aString layer: anInteger
	| existing |
	existing := self packages detect: [:p | p name = aString] ifNone: [nil].
	existing isNil ifFalse: [existing layer: anInteger. ^existing].
	existing := Package named: aString layer: anInteger.
	Packages := Packages copyWith: existing.
	^existing
! !

!SystemDictionary methodsFor: 'queries'!
allMethodsDo: aBlock
	"Evaluate aBlock for every CompiledMethod in the system."
	self allBehaviorsDo: [:b | b methodsDo: aBlock]
!
implementorsOf: aSelector
	"Answer the methods implementing aSelector."
	| result |
	result := OrderedCollection new.
	self allBehaviorsDo: [:b |
		(b includesSelector: aSelector) ifTrue: [result add: (b compiledMethodAt: aSelector)]].
	^result asArray
!
sendersOf: aSelector
	"Answer the methods sending aSelector."
	| result |
	result := OrderedCollection new.
	self allMethodsDo: [:m | (m sendsSelector: aSelector) ifTrue: [result add: m]].
	^result asArray
!
referencesTo: aGlobalName
	"Answer the methods referring to the global (or class variable) named aGlobalName."
	| result |
	result := OrderedCollection new.
	self allMethodsDo: [:m |
		(m literals anySatisfy: [:lit | lit class == Association and: [lit key == aGlobalName]])
			ifTrue: [result add: m]].
	^result asArray
! !

!SystemDictionary methodsFor: 'printing'!
printOn: aStream
	self == Smalltalk
		ifTrue: [aStream nextPutAll: 'Smalltalk']
		ifFalse: [super printOn: aStream]
! !
