ClassDescription subclass: #Class
	instanceVariableNames: 'subclasses name classPool sharedPools package comment'
	classVariableNames: ''
	package: 'Kernel-Classes'!

Class comment: 'I describe a named class: its subclasses, its class variables (classPool, a Dictionary of Associations shared with the methods that use them), its package and its comment. My field order is fixed by the VM and the bootstrapper.'!

!Class methodsFor: 'accessing'!
name
	^name
!
setName: aSymbol
	name := aSymbol
!
comment
	^comment
!
comment: aString
	comment := aString
!
packageName
	"Answer the name of the package that defines me."
	^package
!
package
	"Answer the Package that defines me."
	^Smalltalk packageNamed: package
!
package: aStringOrPackage
	package := aStringOrPackage isString
		ifTrue: [aStringOrPackage]
		ifFalse: [aStringOrPackage name]
!
category
	^package
!
category: aString
	self package: aString
!
theNonMetaClass
	^self
!
classPool
	classPool isNil ifTrue: [classPool := Dictionary new].
	^classPool
!
classPool: aDictionary
	classPool := aDictionary
!
sharedPools
	^sharedPools ifNil: [#()]
!
sharedPools: aCollection
	sharedPools := aCollection
! !

!Class methodsFor: 'class variables'!
classVarNames
	"Answer the names of my class variables, sorted."
	classPool isNil ifTrue: [^#()].
	^classPool keys asSortedCollection asArray
!
allClassVarNames
	| names |
	names := Set new.
	self withAllSuperclassesDo: [:c | names addAll: c classVarNames].
	^names
!
addClassVarNamed: aString
	| key |
	key := aString asSymbol.
	(self classPool includesKey: key) ifFalse: [classPool add: (Association key: key value: nil)]
!
removeClassVarNamed: aString
	self classPool removeKey: aString asSymbol ifAbsent: []
!
classVarNamed: aString
	^(self classPool associationAt: aString asSymbol) value
!
classVarNamed: aString put: anObject
	^(self classPool associationAt: aString asSymbol) value: anObject
!
bindingOf: aSymbol
	"Answer the Association for aSymbol as seen from my methods: class variables (mine and inherited), then globals."
	self withAllSuperclassesDo: [:c |
		| assoc |
		assoc := c classPool associationAt: aSymbol ifAbsent: [nil].
		assoc isNil ifFalse: [^assoc]].
	^Smalltalk associationAt: aSymbol ifAbsent: [nil]
! !

!Class methodsFor: 'subclasses'!
subclasses
	"Answer my direct subclasses."
	subclasses isNil ifTrue: [
		subclasses := (Smalltalk allClasses select: [:c | c superclass == self]) asArray].
	^subclasses
!
addSubclass: aClass
	(self subclasses includes: aClass) ifFalse: [subclasses := subclasses copyWith: aClass]
!
removeSubclass: aClass
	subclasses := self subclasses copyWithout: aClass
!
setSubclasses: anArray
	subclasses := anArray
! !

!Class methodsFor: 'testing'!
isClass
	^true
! !

!Class methodsFor: 'subclass creation'!
subclass: aSymbol
	^self subclass: aSymbol instanceVariableNames: '' classVariableNames: '' package: self packageName
!
subclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #normal
!
variableSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #variable
!
variableByteSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #bytes
!
variableWordSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #words
!
variableDoubleWordSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #doubleWords
!
weakSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #weak
!
immediateSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	^self buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: #immediate
!
subclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars poolDictionaries: pools category: aString
	"Squeak-compatible form."
	^self subclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
!
buildSubclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString type: aType
	^ClassBuilder new
		superclass: self
		subclass: aSymbol
		instanceVariableNames: ivars
		classVariableNames: cvars
		package: aString
		type: aType
! !

!Class methodsFor: 'removing'!
removeFromSystem
	"Remove me from Smalltalk and from my superclass. Existing instances keep working."
	superclass isNil ifFalse: [superclass removeSubclass: self].
	Smalltalk removeKey: name ifAbsent: []
! !

!Class methodsFor: 'printing'!
overview
	"Answer a summary of me: superclass, package, variables, comment, then the selectors of each method category, instance side and class side."
	^String new: 1000 streamContents: [:s |
		s nextPutAll: self name; nextPutAll: ' (superclass: '; nextPutAll: (superclass ifNil: ['nil'] ifNotNil: [:c | c name]);
			nextPutAll: ', package: '; nextPutAll: (self packageName ifNil: ['none']); nextPut: $).
		#(('instance variables' instVarNames) ('class variables' classVarNames) ('class-side instance variables' classInstVarNames)) do: [:each | | names |
			names := each last == #classInstVarNames ifTrue: [self class instVarNames] ifFalse: [self perform: each last].
			names isEmpty ifFalse: [
				s nextPut: Character lf; nextPutAll: each first; nextPut: $:.
				(names asSortedCollection: [:a :b | a <= b]) do: [:n | s space; nextPutAll: n]]].
		s nextPut: Character lf; nextPutAll: (self comment ifNil: ['(no comment)']).
		(Array with: self with: self class) do: [:b |
			s nextPut: Character lf; nextPutAll: (b isMeta ifTrue: ['class side:'] ifFalse: ['instance side:']).
			b categories do: [:cat |
				s nextPut: Character lf; nextPutAll: '  '; nextPutAll: cat; nextPut: $:.
				((b selectorsInCategory: cat) asSortedCollection: [:x :y | x <= y]) do: [:sel | s space; nextPutAll: sel]]]]
! !
