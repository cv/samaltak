Object subclass: #TFunction
	instanceVariableNames: 'module selector method ast pragmas kind cName functionType bytecodes specialize primitive callers addressTaken generated assignmentCounts readNames'
	classVariableNames: ''
	package: 'VM-Translator'!

TFunction comment: 'I am a method of a module as the translator sees it. kind:
	#function	a C function (<c: ''prototype''>, or a primitive)
	#inline	expanded at every call (no <c:>, or an accessor)
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
	| proto |
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
		kind := #function.
		(pragmas includesKey: #c:)
			ifTrue: [self setPrototype: (pragmas at: #c:) first translator: aTranslator]
			ifFalse: [
				cName := LowtalkNames functionNameFor: selector.
				functionType := CFunctionType returning: CVoidType new parameters: #() names: #() variadic: false].
		^self].
	(pragmas includesKey: #c:) ifTrue: [
		kind := #function.
		^self setPrototype: (pragmas at: #c:) first translator: aTranslator].
	kind := #inline
!
setPrototype: aString translator: aTranslator
	| decl |
	decl := aTranslator registry parsePrototype: aString.
	cName := decl at: 1.
	functionType := decl at: 2.
	functionType parameterTypes size = ast arguments size ifFalse: [
		aTranslator error: self printString , ': the prototype has ' , functionType parameterTypes size printString , ' parameters, the method ' , ast arguments size printString]
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
	^functionType
!
returnType
	^functionType returnType
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
