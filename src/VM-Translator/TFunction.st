Object subclass: #TSlot
	instanceVariableNames: 'explicit value constant adopted low high generic'
	classVariableNames: ''
	package: 'VM-Translator'!

CFunctionType subclass: #TSignature
	instanceVariableNames: 'translator names functions dependents slots result unified forward'
	classVariableNames: ''
	package: 'VM-Translator'!

TSlot comment: 'I am a parameter or the result of a TSignature: an explicit type if one is given, else the join of the values passed, else, for literals only, the join of their own types: a literal adapts to any other value it joins with. Pointers join to void * when they are unrelated (generic) and then stay that; a void * value adapts to a pointer type.'!

!TSlot methodsFor: 'accessing'!
type
	"My type so far: explicit, the join of the values, or (once the literals are all there is: adoptConstant) the join of the literals; nil if there is nothing yet."
	^explicit ifNil: [value ifNil: [adopted == true ifTrue: [constant] ifFalse: [nil]]]
!
explicit: aCType
	explicit := aCType
!
isExplicit
	^explicit notNil
! !

!TSlot methodsFor: 'inferring'!
note: aCType adaptive: isAdaptive literal: anIntegerOrNil registry: aRegistry
	"Answer whether the value joins with what I have."
	explicit notNil ifTrue: [^true].
	isAdaptive
		ifTrue: [
			constant := constant isNil ifTrue: [aCType] ifFalse: [self joinConstant: constant with: aCType].
			anIntegerOrNil notNil ifTrue: [
				low := low isNil ifTrue: [anIntegerOrNil] ifFalse: [low min: anIntegerOrNil].
				high := high isNil ifTrue: [anIntegerOrNil] ifFalse: [high max: anIntegerOrNil]]]
		ifFalse: [
			value isNil
				ifTrue: [value := aCType]
				ifFalse: [value := (self join: value with: aCType registry: aRegistry) ifNil: [^false]]].
	^self widenForLiterals: aRegistry
!
adoptConstant
	"Nothing but literals: their own type, for good. Answer whether that was news."
	(constant notNil and: [value isNil and: [explicit isNil and: [adopted ~~ true]]]) ifFalse: [^false].
	adopted := true.
	^true
!
widenForLiterals: aRegistry
	"A literal that does not fit the values' type (-1 and unsigned values) widens it to one that holds both."
	| outlier joined |
	(value notNil and: [value isInteger and: [low notNil]]) ifFalse: [^true].
	(value includes: low) ifFalse: [outlier := low].
	(value includes: high) ifFalse: [outlier := high].
	outlier isNil ifTrue: [^true].
	joined := self join: value with: (aRegistry at: ((outlier between: -16r80000000 and: 16r7FFFFFFF)
		ifTrue: ['int']
		ifFalse: [outlier <= 16r7FFFFFFFFFFFFFFF ifTrue: ['int64_t'] ifFalse: ['uint64_t']])) registry: aRegistry.
	joined isNil ifTrue: [^false].
	value := joined.
	^true
!
absorb: aTSlot registry: aRegistry
	aTSlot type isNil ifTrue: [^self].
	value isNil ifTrue: [value := aTSlot type. ^self].
	value := (self join: value with: aTSlot type registry: aRegistry) ifNil: [value]
!
join: a with: b registry: aRegistry
	"The narrowest C type both convert to without loss; a function pointer's signature unifies; nil if there is none."
	(a isInteger and: [b isInteger]) ifTrue: [^self joinInteger: a with: b registry: aRegistry].
	(a isFloat and: [b isFloat]) ifTrue: [^a size >= b size ifTrue: [a] ifFalse: [b]].
	(a isBool and: [b isBool]) ifTrue: [^a].
	(a isPointer and: [b isPointer]) ifTrue: [^self joinPointer: a with: b registry: aRegistry].
	^a = b ifTrue: [a] ifFalse: [nil]
!
joinInteger: a with: b registry: aRegistry
	| signed unsigned |
	a isSigned = b isSigned ifTrue: [
		a size = b size ifTrue: [^b name = 'oop' ifTrue: [b] ifFalse: [a]].
		^a size > b size ifTrue: [a] ifFalse: [b]].
	a isSigned ifTrue: [signed := a. unsigned := b] ifFalse: [signed := b. unsigned := a].
	signed size > unsigned size ifTrue: [^signed].
	unsigned size < 8 ifTrue: [^aRegistry at: 'int64_t'].
	^nil
!
joinPointer: a with: b registry: aRegistry
	(a target isFunction and: [b target isFunction]) ifTrue: [
		(a target isKindOf: TSignature) ifTrue: [a target unifyWith: b target. ^a].
		(b target isKindOf: TSignature) ifTrue: [b target unifyWith: a target. ^b].
		^a = b ifTrue: [a] ifFalse: [nil]].
	generic == true ifTrue: [^a].
	a target isVoid ifTrue: [^b].
	b target isVoid ifTrue: [^a].
	a = b ifTrue: [^a].
	(a target sameAs: b target) ifTrue: [^b target isConst ifTrue: [b] ifFalse: [a]].
	generic := true.
	^aRegistry parse: 'void *'
!
joinConstant: a with: b
	"Literals of two types: the wider, a float over an integer."
	(a isFloat and: [b isFloat not]) ifTrue: [^a].
	(b isFloat and: [a isFloat not]) ifTrue: [^b].
	(a isInteger and: [b isInteger]) ifTrue: [
		a size = b size ifTrue: [^a isSigned ifTrue: [b] ifFalse: [a]].
		^a size > b size ifTrue: [a] ifFalse: [b]].
	^a
! !

!TSignature class methodsFor: 'instance creation'!
names: anArray translator: aTranslator
	^self basicNew setNames: anArray translator: aTranslator
! !

!TSignature methodsFor: 'initialization'!
setNames: anArray translator: aTranslator
	translator := aTranslator.
	names := anArray.
	functions := OrderedCollection new.
	dependents := OrderedCollection new.
	slots := anArray collect: [:n | TSlot new].
	result := TSlot new.
	unified := OrderedCollection new.
	self refresh
!
addFunction: aTFunction
	"A function I type: its <var:type:> and <returns:> pragmas are explicit types."
	functions add: aTFunction.
	aTFunction arguments doWithIndex: [:a :i |
		(aTFunction declaredTypeOf: a) ifNotNil: [:t | (slots at: i) explicit: (translator registry parse: t)]].
	(aTFunction pragmaAt: #returns:) ifNotNil: [:p | result explicit: (translator registry parse: p first)].
	self refresh
! !

!TSignature methodsFor: 'accessing'!
root
	^forward isNil ifTrue: [self] ifFalse: [forward root]
!
functions
	^functions
!
dependents
	^dependents
!
addDependent: aTFunction
	"aTFunction's code depends on me: it runs again when I change."
	(dependents identityIncludes: aTFunction) ifFalse: [dependents add: aTFunction]
!
parameterTypeAt: anInteger
	"nil while nothing is known about it."
	^(slots at: anInteger) type
!
slots
	^slots
!
result
	^result
! !

!TSignature methodsFor: 'inferring'!
noteArgument: anInteger type: aCType adaptive: aBoolean literal: v
	"Answer whether the type joins with the other arguments."
	^self note: aCType adaptive: aBoolean literal: v in: (slots at: anInteger)
!
noteResultType: aCType adaptive: aBoolean literal: v
	^self note: aCType adaptive: aBoolean literal: v in: result
!
note: aCType adaptive: aBoolean literal: v in: aTSlot
	| before ok |
	before := aTSlot type.
	ok := aTSlot note: aCType adaptive: aBoolean literal: v registry: translator registry.
	(ok and: [aTSlot type ~= before]) ifTrue: [self changed: aTSlot].
	^ok
!
adoptConstants
	"Whichever slots have only literals take their own type; answer whether any did."
	| any |
	any := false.
	slots do: [:s | s adoptConstant ifTrue: [any := true. self changed: s]].
	result adoptConstant ifTrue: [any := true. self changed: result].
	^any
!
changed: aTSlot
	"A parameter's type runs my functions again (they use it), a result's those who call me."
	self refresh.
	aTSlot == result
		ifTrue: [dependents do: [:f | translator enqueue: f]]
		ifFalse: [functions do: [:f | translator enqueue: f]]
!
refresh
	"Print what is known (unknown parameters print as void)."
	| void |
	void := translator registry at: 'void'.
	self setReturnType: (result type ifNil: [void]) parameterTypes: (slots collect: [:s | s type ifNil: [void]]) names: names variadic: false.
	unified do: [:s | s setReturnType: returnType parameterTypes: parameterTypes names: names variadic: false]
!
unifyWith: aSignature
	"The functions behind a function pointer take one signature: that of a C library or a typedef (a plain CFunctionType), or the joined one of two inferred signatures."
	| me |
	me := self root.
	(aSignature isKindOf: TSignature) ifFalse: [^me adopt: aSignature].
	aSignature root == me ifTrue: [^self].
	aSignature root forwardTo: me.
	me absorb: aSignature root
!
forwardTo: aTSignature
	forward := aTSignature
!
absorb: aTSignature
	aTSignature functions do: [:f | functions add: f].
	aTSignature dependents do: [:f | self addDependent: f].
	aTSignature slots with: slots do: [:s :mine | mine absorb: s registry: translator registry].
	result absorb: aTSignature result registry: translator registry.
	unified add: aTSignature.
	unified addAll: aTSignature unified.
	self refresh.
	functions do: [:f | translator enqueue: f].
	dependents do: [:f | translator enqueue: f]
!
unified
	^unified
!
adopt: aCFunctionType
	aCFunctionType parameterTypes doWithIndex: [:t :i | (slots at: i) explicit: t].
	result explicit: aCFunctionType returnType.
	self refresh.
	functions do: [:f | translator enqueue: f].
	dependents do: [:f | translator enqueue: f]
! !

Object subclass: #TFunction
	instanceVariableNames: 'module selector method ast pragmas kind cName interface signature bytecodes specialize primitive callers addressTaken generated assignmentCounts readNames'
	classVariableNames: ''
	package: 'VM-Translator'!

TFunction comment: 'I am a method of a module as the translator sees it. kind:
	#function	a C function (<function>, <export>, <noreturn>, a primitive or a method of an interface): its signature is inferred (TSignature)
	#inline	expanded at every call (any other method)
	#handler	a bytecode handler of the interpreter loop (<bytecode: n>, <bytecodes: #(first last)>)
	#label	a goto target in the interpreter loop (<label>)
	#dispatchLoop	where the interpreter function starts dispatching (<dispatchLoop>)
	#dispatch	re-dispatch on a bytecode (<dispatch>)
	#currentBytecode	the bytecode being executed (<currentBytecode>)
	#intrinsic	a Lowtalk primitive of VMModule (<intrinsic>)'!

!TFunction class methodsFor: 'instance creation'!
module: aTModule selector: aSymbol translator: aTranslator
	^self new setModule: aTModule selector: aSymbol translator: aTranslator
! !

!TFunction methodsFor: 'initialization'!
setModule: aTModule selector: aSymbol translator: aTranslator
	module := aTModule.
	selector := aSymbol.
	method := aTModule moduleClass compiledMethodAt: aSymbol.
	callers := Set new.
	addressTaken := false.
	generated := false.
	pragmas := Dictionary new.
	method source isNil ifTrue: [^aTranslator error: self printString , ' has no source'].
	ast := Parser new parseMethod: method source.
	ast pragmas do: [:p | pragmas at: p selector put: p arguments].
	self classifyIn: aTranslator
!
classifyIn: aTranslator
	(pragmas includesKey: #intrinsic) ifTrue: [^kind := #intrinsic].
	(pragmas includesKey: #dispatchLoop) ifTrue: [^kind := #dispatchLoop].
	(pragmas includesKey: #dispatch) ifTrue: [^kind := #dispatch].
	(pragmas includesKey: #currentBytecode) ifTrue: [^kind := #currentBytecode].
	(pragmas includesKey: #label) ifTrue: [
		kind := #label.
		^cName := LowtalkNames functionNameFor: selector].
	(pragmas includesKey: #bytecode:) ifTrue: [bytecodes := Array with: (pragmas at: #bytecode:) first].
	(pragmas includesKey: #bytecodes:) ifTrue: [
		| range |
		range := (pragmas at: #bytecodes:) first.
		bytecodes := range isEmpty ifTrue: [#()] ifFalse: [((range at: 1) to: (range at: 2)) asArray]].
	(pragmas includesKey: #bytecodeList:) ifTrue: [bytecodes := (pragmas at: #bytecodeList:) first].
	bytecodes notNil ifTrue: [
		kind := #handler.
		specialize := pragmas includesKey: #specialize.
		^cName := 'op_' , (LowtalkNames functionNameFor: selector)].
	(pragmas includesKey: #vmPrimitive:name:) ifTrue: [
		| args |
		args := pragmas at: #vmPrimitive:name:.
		primitive := Array with: (args at: 1) with: (args at: 2) with: (pragmas includesKey: #leaf) with: (pragmas includesKey: #notTryable) not.
		^self beFunctionIn: aTranslator].
	((#(#function #export #noreturn) anySatisfy: [:p | pragmas includesKey: p]) or: [module moduleClass isInterface]) ifTrue: [^self beFunctionIn: aTranslator].
	kind := #inline
!
beFunctionIn: aTranslator
	kind := #function.
	cName := self baseName.
	interface := self interfaceIn: aTranslator.
	signature := interface isNil
		ifTrue: [TSignature names: (self arguments collect: [:a | LowtalkNames snake: a]) translator: aTranslator]
		ifFalse: [interface signature].
	signature addFunction: self
!
interfaceIn: aTranslator
	"The interface function I implement (the same C function, so one name and one signature), or nil."
	| c |
	c := module moduleClass superclass.
	[c notNil and: [c includesBehavior: VMModule]] whileTrue: [
		(c isInterface and: [c includesSelector: selector]) ifTrue: [^(aTranslator moduleFor: c) functionAt: selector].
		c := c superclass].
	^nil
!
baseName
	"My selector's first keyword in snake case (main:argv: is C's main)."
	selector = #main:argv: ifTrue: [^'main'].
	^LowtalkNames functionNameFor: selector
! !

!TFunction methodsFor: 'accessing'!
module
	^module
!
selector
	^selector
!
ast
	^ast
!
arguments
	^ast arguments collect: [:each | each name]
!
temporaries
	^ast temporaries collect: [:each | each name]
!
statements
	^ast body statements
!
kind
	^kind
!
cName
	^cName
!
functionType
	^signature root
!
signature
	^signature root
!
interface
	"The function of the interface I implement, or nil."
	^interface
!
cName: aString
	cName := aString
!
returnType
	^signature root returnType
!
parameterTypeAt: anInteger
	"nil while nothing is known about it."
	^signature root parameterTypeAt: anInteger
!
parametersKnown
	"Whether my parameter types are given (none, or all explicit), so that I need no caller to be generated."
	| slots |
	slots := signature root slots.
	^slots allSatisfy: [:s | s isExplicit]
!
bytecodes
	^bytecodes
!
isSpecialized
	^specialize == true
!
isRange
	"<bytecodes: #(first last)>: single-bytecode handlers take precedence."
	^pragmas includesKey: #bytecodes:
!
primitive
	"{number. name. isLeaf. isTryable} or nil"
	^primitive
!
pragmaAt: aSymbol
	^pragmas at: aSymbol ifAbsent: [nil]
!
hasPragma: aSymbol
	^pragmas includesKey: aSymbol
!
declaredTypeOf: aString
	"The type given by <var: #name type: 'T'>, or nil."
	ast pragmas do: [:p |
		(p selector == #var:type: and: [(p arguments at: 1) asString = aString]) ifTrue: [^p arguments at: 2]].
	^nil
!
isInline
	^kind == #inline
!
isFunction
	^kind == #function
!
isAccessor
	"^var, or var := arg (with an optional ^self), of one of my module's variables."
	| stmts s |
	stmts := self statements.
	(stmts isEmpty or: [stmts size > 2]) ifTrue: [^false].
	s := stmts first.
	stmts size = 2 ifTrue: [(stmts last isReturn and: [stmts last value isSelf]) ifFalse: [^false]].
	(stmts size = 1 and: [s isReturn and: [s value isVariable]]) ifTrue: [
		^(module globalNamed: s value name) notNil].
	^s isAssignment and: [s value isVariable and: [
		(module globalNamed: s variable name) notNil and: [self arguments includes: s value name]]]
! !

!TFunction methodsFor: 'naming'!
moduleQualifiedName
	"baseName with my module's C name in front."
	^module cFileName , '_' , self baseName
!
fullyQualifiedName
	"With every keyword of my selector."
	| s |
	s := selector copyReplaceAll: ':' with: '_'.
	(s endsWith: '_') ifTrue: [s := s allButLast].
	^module cFileName , '_' , (LowtalkNames snake: s)
!
localNames
	"What my code calls its locals in C, for the names no function may take."
	| names |
	self analyze.
	names := Set new.
	self arguments do: [:a | names add: (LowtalkNames snake: a)].
	readNames do: [:n | names add: (LowtalkNames snake: n)].
	assignmentCounts keysDo: [:n | names add: (LowtalkNames snake: n)].
	^names
! !

!TFunction methodsFor: 'analysis'!
assignmentCountOf: aString
	"How often my source assigns aString (in blocks too)."
	self analyze.
	^assignmentCounts at: aString ifAbsent: [0]
!
reads: aString
	"Whether my source reads aString (in blocks too)."
	self analyze.
	^readNames includes: aString
!
analyze
	assignmentCounts notNil ifTrue: [^self].
	assignmentCounts := Dictionary new.
	readNames := Set new.
	self analyze: ast body
!
analyze: aNode
	aNode isNil ifTrue: [^self].
	aNode isVariable ifTrue: [^readNames add: aNode name].
	(aNode isKindOf: SequenceNode) ifTrue: [^aNode statements do: [:s | self analyze: s]].
	aNode isAssignment ifTrue: [
		assignmentCounts at: aNode variable name put: (assignmentCounts at: aNode variable name ifAbsent: [0]) + 1.
		^self analyze: aNode value].
	aNode isMessage ifTrue: [
		self analyze: aNode receiver.
		^aNode arguments do: [:a | self analyze: a]].
	aNode isCascade ifTrue: [
		self analyze: aNode receiver.
		^aNode messages do: [:m | m arguments do: [:a | self analyze: a]]].
	aNode isBlock ifTrue: [^self analyze: aNode body].
	aNode isReturn ifTrue: [^self analyze: aNode value].
	(aNode isKindOf: BraceNode) ifTrue: [^aNode elements do: [:e | self analyze: e]]
! !

!TFunction methodsFor: 'linking'!
noteCalledFrom: aTModule
	callers add: aTModule
!
noteAddressTaken
	addressTaken := true
!
isStatic
	"Whether no other module calls me (then I am static in my module's C file)."
	primitive notNil ifTrue: [^false].
	cName = 'main' ifTrue: [^false].
	addressTaken ifTrue: [^(callers allSatisfy: [:m | m == module])].
	(self hasPragma: #export) ifTrue: [^false].
	^callers allSatisfy: [:m | m == module]
!
generated
	^generated
!
generated: aBoolean
	generated := aBoolean
! !

!TFunction methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: module name; nextPutAll: '>>'; nextPutAll: selector
! !

Object subclass: #TExtern
	instanceVariableNames: 'library selector kind cName type noReturn'
	classVariableNames: ''
	package: 'VM-Translator'!

TExtern comment: 'I am a C function, variable or macro a CLibrary declares (<c:>, <cVariable:>, <cMacro:>).'!

!TExtern class methodsFor: 'instance creation'!
library: aLibraryClass selector: aSymbol translator: aTranslator
	^self new setLibrary: aLibraryClass selector: aSymbol translator: aTranslator
! !

!TExtern methodsFor: 'initialization'!
setLibrary: aLibraryClass selector: aSymbol translator: aTranslator
	| m decl |
	library := aLibraryClass.
	selector := aSymbol.
	m := aLibraryClass lookupSelector: aSymbol.
	m isNil ifTrue: [^aTranslator error: aLibraryClass name , ' does not declare ' , aSymbol].
	noReturn := (self pragma: #noreturn of: m) notNil.
	(self pragma: #c: of: m) ifNotNil: [:p |
		decl := aTranslator registry parsePrototype: p arguments first.
		kind := #function.
		cName := decl at: 1.
		type := decl at: 2.
		^self].
	(self pragma: #cVariable: of: m) ifNotNil: [:p |
		decl := aTranslator registry parseDeclaration: p arguments first.
		kind := #variable.
		cName := decl at: 1.
		type := decl at: 2.
		^self].
	(self pragma: #cMacro: of: m) ifNotNil: [:p |
		decl := aTranslator registry parseDeclaration: p arguments first.
		kind := #macro.
		cName := decl at: 1.
		type := decl at: 2.
		^self].
	aTranslator error: aLibraryClass name , '>>' , aSymbol , ' is not a C declaration (<c:>, <cVariable:> or <cMacro:>)'
! !

!TExtern methodsFor: 'private'!
pragma: aSymbol of: aCompiledMethod
	^(aCompiledMethod pragmas ifNil: [#()]) detect: [:p | p selector == aSymbol] ifNone: [nil]
! !

!TExtern methodsFor: 'accessing'!
kind
	^kind
!
isNoReturn
	^noReturn
!
cName
	^cName
!
type
	^type
!
library
	^library
! !
