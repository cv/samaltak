Object subclass: #GlslShader
	instanceVariableNames: 'tokens at scopes structs functions globals block blockVariable inputs output current loops switches usesDiscard called'
	classVariableNames: 'Reserved'
	package: 'Graphics-Shaders'!

GlslShader comment: 'I am a GLSL fragment shader, parsed and type-checked: the subset of GLSL 4.50 Samaltak''s fragment shaders use (FragmentShader: its prelude, then a main writing the output; uniforms in one block). Scalars, vectors, matrices, structures and arrays of them; swizzles; GLSL''s operators and implicit conversions; the built-in functions of GlslBuiltins; functions (overloaded, in, out and inout parameters); if, for, while, do, switch, break, continue, return, discard; constants and global variables; the inputs uv and size, gl_FragCoord, one vec4 output. What is not GLSL or is outside the subset is a ShaderError at its line and column, like a compiler''s first error.

	GlslShader parse: aString     "or a ShaderError"

GlslCudaWriter writes me as CUDA C++. I keep structs (in order), globals (GlslVariables at the top level, in order: constants, variables, inputs, the output, the block''s members), the uniform block (a structure type) and its instance, functions (name -> GlslFunctions) and their order.'!

!GlslShader methodsFor: 'accessing'!
structs
	^structs
!
globals
	^globals
!
block
	"The uniform block's type (a structure whose fields are its members), nil if there is none."
	^block
!
blockVariable
	^blockVariable
!
uniformSize
	"The bytes of the uniform block (std140)."
	^block isNil ifTrue: [0] ifFalse: [block std140Size]
!
functions
	"Every function in the order defined."
	^functions inject: OrderedCollection new into: [:all :each | all addAll: each; yourself]
!
definedFunctions
	| all |
	all := OrderedCollection new.
	functions do: [:each | each do: [:f | f body isNil ifFalse: [all add: f]]].
	^(all asSortedCollection: [:a :b | a line < b line or: [a line = b line and: [a column <= b column]]]) asArray
!
main
	^(functions at: 'main' ifAbsent: [#()]) detect: [:f | f params isEmpty] ifNone: [nil]
!
output
	^output
!
inputs
	^inputs
!
usesDiscard
	^usesDiscard == true
! !

!GlslShader methodsFor: 'parsing'!
parse: aString
	tokens := GlslLexer tokenize: aString.
	at := 1.
	structs := OrderedCollection new.
	functions := Dictionary new.
	globals := OrderedCollection new.
	inputs := OrderedCollection new.
	loops := 0. switches := 0.
	called := IdentitySet new.
	scopes := OrderedCollection with: Dictionary new.
	(self declare: (GlslVariable name: 'gl_FragCoord' type: (GlslType named: 'vec4') storage: #builtin at: tokens first)) cuda: 'gl_c.gl_FragCoord'.
	(self declare: (GlslVariable name: 'gl_FrontFacing' type: GlslType bool storage: #builtin at: tokens first)) cuda: 'true'.
	[self peek kind == #eof] whileFalse: [self external].
	self main isNil ifTrue: [self error: 'no function void main()' at: self peek].
	(self main body isNil) ifTrue: [self error: 'main is declared but not defined' at: self main].
	output isNil ifTrue: [self error: 'no output: declare one, as FragmentShader''s prelude does (layout(location = 0) out vec4 fragColor;)' at: self main].
	functions do: [:each | each do: [:f |
		(f body isNil and: [called includes: f]) ifTrue: [self error: f signature, ' is called but not defined' at: f]]]
!
external
	| quals type nameToken |
	(self accept: ';') ifTrue: [^self].
	(self peekIs: 'precision') ifTrue: [[self accept: ';'] whileFalse: [self next]. ^self].
	quals := self qualifiers.
	((quals includes: #uniform) and: [self peek kind == #ident and: [(self peek: 1) is: '{']]) ifTrue: [^self uniformBlock].
	type := self typeSpecifier.
	type isNil ifTrue: [self error: 'expected a declaration, not ', self describePeek at: self peek].
	(self accept: ';') ifTrue: [
		type isStruct ifFalse: [self error: 'a declaration needs a name' at: self peek].
		^self].
	nameToken := self expectIdentifier.
	(self peekIs: '(') ifTrue: [
		quals isEmpty ifFalse: [self error: 'a function takes no qualifiers' at: nameToken].
		^self function: type name: nameToken].
	self globalDeclaration: type qualifiers: quals name: nameToken
!
qualifiers
	"The storage and other qualifiers before a type (layout's arguments are ignored)."
	| q |
	q := Set new.
	[| t |
	t := self peek.
	t kind == #ident and: [#('const' 'uniform' 'in' 'out' 'inout' 'flat' 'smooth' 'noperspective' 'centroid' 'sample' 'highp' 'mediump' 'lowp' 'invariant' 'precise' 'layout' 'readonly' 'writeonly' 'coherent' 'volatile' 'restrict') includes: t text]]
		whileTrue: [| t |
			t := self next.
			t text = 'layout'
				ifTrue: [| depth |
					self expect: '('.
					depth := 1.
					[depth > 0] whileTrue: [| x |
						x := self next.
						x kind == #eof ifTrue: [self error: 'unterminated layout' at: t].
						(x is: '(') ifTrue: [depth := depth + 1].
						(x is: ')') ifTrue: [depth := depth - 1]]]
				ifFalse: [q add: t text asSymbol]].
	^q
!
uniformBlock
	| nameToken members type inst |
	nameToken := self next.
	block isNil ifFalse: [self error: 'only one uniform block: its members are the uniforms (binding 0)' at: nameToken].
	self expect: '{'.
	members := OrderedCollection new.
	[self accept: '}'] whileFalse: [| t |
		self qualifiers.
		t := self typeSpecifier.
		t isNil ifTrue: [self error: 'expected a member of the uniform block, not ', self describePeek at: self peek].
		[| n mt |
		n := self expectIdentifier.
		mt := self arraySuffix: t.
		mt isArray & mt length isNil ifTrue: [self error: 'a uniform array needs a size' at: n].
		(members anySatisfy: [:m | m key = n text]) ifTrue: [self error: 'two members named ', n text at: n].
		members add: n text -> mt.
		self accept: ','] whileTrue.
		self expect: ';'].
	type := (GlslType struct: nameToken text fields: members asArray) beBlock; yourself.
	block := type.
	self peek kind == #ident
		ifTrue: [| n |
			n := self next.
			(self peekIs: '[') ifTrue: [self error: 'an array of uniform blocks is not supported' at: self peek].
			inst := self declare: (GlslVariable name: n text type: type storage: #block at: n).
			inst cuda: 'gl_c.u'.
			blockVariable := inst.
			globals add: inst]
		ifFalse: [
			members do: [:m | | v |
				v := self declare: (GlslVariable name: m key type: m value storage: #uniform at: nameToken).
				v offset: (type std140OffsetOf: m key).
				globals add: v]].
	self expect: ';'
!
globalDeclaration: type qualifiers: quals name: firstName
	| storage nameToken |
	(quals includes: #uniform) ifTrue: [self error: 'uniforms go in the uniform block: layout(set = 3, binding = 0) uniform U { ... };' at: firstName].
	storage := (quals includes: #const) ifTrue: [#const] ifFalse: [
		(quals includes: #in) ifTrue: [#input] ifFalse: [(quals includes: #out) ifTrue: [#output] ifFalse: [#global]]].
	nameToken := firstName.
	[| t v |
	t := self arraySuffix: type.
	v := GlslVariable name: nameToken text type: t storage: storage at: nameToken.
	storage == #input ifTrue: [
		(#('uv' 'size') includes: nameToken text) ifFalse: [self error: 'the inputs are uv and size (FragmentShader''s prelude), not ', nameToken text at: nameToken].
		t = (GlslType named: 'vec2') ifFalse: [self error: nameToken text, ' is a vec2' at: nameToken].
		inputs add: v.
		v cuda: 'gl_c.', nameToken text].
	storage == #output ifTrue: [
		output isNil ifFalse: [self error: 'only one output' at: nameToken].
		t = (GlslType named: 'vec4') ifFalse: [self error: 'the output is a vec4' at: nameToken].
		output := v.
		v cuda: 'gl_c.gl_out'].
	storage == #global ifTrue: [v cuda: 'gl_c.', v cuda].
	storage == #const ifTrue: [v beConst. v cuda: 'gl_k_', v cuda, '()'].
	(self accept: '=')
		ifTrue: [
			(storage == #input or: [storage == #output]) ifTrue: [self error: 'an input or output has no initializer' at: nameToken].
			v init: (self initializer: v)]
		ifFalse: [
			storage == #const ifTrue: [self error: 'a constant needs a value' at: nameToken].
			t isArray & t length isNil ifTrue: [self error: 'an array needs a size' at: nameToken]].
	self declare: v.
	globals add: v.
	(self accept: ',')
		ifTrue: [nameToken := self expectIdentifier. true]
		ifFalse: [false]] whileTrue.
	self expect: ';'
!
initializer: aVariable
	"The initializer of aVariable after its =, converted to its type; an unsized array takes its size from it."
	| e |
	e := self assignment.
	(aVariable type isArray and: [aVariable type length isNil]) ifTrue: [
		(e type isArray and: [e type element = aVariable type element]) ifFalse: [self error: 'cannot initialize ', aVariable type name, ' with ', e type name at: e].
		aVariable type: e type].
	e := self convert: e to: aVariable type.
	(aVariable isConst and: [aVariable type = GlslType int or: [aVariable type = GlslType uint]]) ifTrue: [
		aVariable constValue: (self constantValueOf: e)].
	^e
!
function: type name: nameToken
	| params f existing |
	self expect: '('.
	params := OrderedCollection new.
	((self peekIs: 'void') and: [(self peek: 1) is: ')']) ifTrue: [self next].
	[self accept: ')'] whileFalse: [| q pt pn mode v |
		params isEmpty ifFalse: [self expect: ','].
		q := self qualifiers.
		pt := self typeSpecifier.
		pt isNil ifTrue: [self error: 'expected a parameter type, not ', self describePeek at: self peek].
		pn := self peek kind == #ident ifTrue: [self next] ifFalse: [nil].
		pn notNil ifTrue: [pt := self arraySuffix: pt].
		(pt isArray and: [pt length isNil]) ifTrue: [self error: 'an array parameter needs a size' at: self peek].
		pt isVoid ifTrue: [self error: 'a parameter cannot be void' at: self peek].
		mode := (q includes: #inout) ifTrue: [#inout] ifFalse: [(q includes: #out) ifTrue: [#out] ifFalse: [#in]].
		v := GlslVariable name: (pn ifNil: ['gl_p', params size printString] ifNotNil: [:x | x text]) type: pt storage: #param at: (pn ifNil: [nameToken]).
		v mode: mode.
		(q includes: #const) ifTrue: [v beConst].
		params add: v].
	f := GlslFunction name: nameToken text returnType: type params: params asArray at: nameToken.
	(GlslBuiltins includes: nameToken text) ifTrue: [self error: nameToken text, ' is a built-in function' at: nameToken].
	nameToken text = 'main' ifTrue: [
		(type isVoid and: [params isEmpty]) ifFalse: [self error: 'main is void main()' at: nameToken]].
	existing := (functions at: nameToken text ifAbsent: [#()]) detect: [:g | g paramTypes = f paramTypes] ifNone: [nil].
	existing notNil ifTrue: [
		existing returnType = type ifFalse: [self error: nameToken text, ' was declared returning ', existing returnType name at: nameToken].
		((existing params with: f params collect: [:a :b | a mode = b mode]) allSatisfy: [:x | x])
			ifFalse: [self error: 'the parameters of ', nameToken text, ' differ from its declaration' at: nameToken]].
	(self accept: ';') ifTrue: [
		existing isNil ifTrue: [(functions at: nameToken text ifAbsentPut: [OrderedCollection new]) add: f].
		^self].
	(existing notNil and: [existing body notNil]) ifTrue: [self error: f signature, ' is defined twice' at: nameToken].
	existing notNil ifTrue: [(functions at: nameToken text) remove: existing].
	(functions at: nameToken text ifAbsentPut: [OrderedCollection new]) add: f.
	scopes addLast: Dictionary new.
	f params do: [:p | (p name beginsWith: 'gl_p') ifFalse: [self declare: p]].
	current := f.
	self expect: '{' .
	f body: (self blockBody: (tokens at: at - 1)).
	current := nil.
	scopes removeLast
! !

!GlslShader methodsFor: 'types'!
typeSpecifier
	"The type at the current position (consumed), nil (nothing consumed) if there is none."
	| t type |
	t := self peek.
	t kind == #ident ifFalse: [^nil].
	t text = 'struct' ifTrue: [^self arraySuffix: self structSpecifier].
	type := GlslType named: t text.
	type isNil ifTrue: [type := structs detect: [:s | s name = t text] ifNone: [nil]].
	type isNil ifTrue: [
		(#('sampler2D' 'texture2D' 'image2D' 'double' 'dvec2' 'dvec3' 'dvec4' 'dmat2' 'dmat3' 'dmat4') includes: t text)
			ifTrue: [self error: t text, ' is not supported here' at: t].
		^nil].
	self next.
	^self arraySuffix: type
!
arraySuffix: aType
	"aType, or an array of it if [size] (or [] for a size the initializer gives) follows."
	| n |
	(self peekIs: '[') ifFalse: [^aType].
	self next.
	(self accept: ']') ifTrue: [^self arraySuffix: (GlslType arrayOf: aType length: nil)].
	n := self constantValueOf: self conditional.
	n > 0 ifFalse: [self error: 'an array needs at least one element' at: self peek].
	self expect: ']'.
	^self arraySuffix: (GlslType arrayOf: aType length: n)
!
structSpecifier
	| s nameToken fields |
	self next.
	nameToken := self expectIdentifier.
	(structs anySatisfy: [:x | x name = nameToken text]) | (GlslType named: nameToken text) notNil
		ifTrue: [self error: 'a type ', nameToken text, ' exists already' at: nameToken].
	current isNil ifFalse: [self error: 'structures are declared at the top level here' at: nameToken].
	self expect: '{'.
	fields := OrderedCollection new.
	[self accept: '}'] whileFalse: [| ft |
		self qualifiers.
		ft := self typeSpecifier.
		ft isNil ifTrue: [self error: 'expected a field type, not ', self describePeek at: self peek].
		ft isVoid ifTrue: [self error: 'a field cannot be void' at: self peek].
		[| n t |
		n := self expectIdentifier.
		t := self arraySuffix: ft.
		t isArray & t length isNil ifTrue: [self error: 'a field array needs a size' at: n].
		(fields anySatisfy: [:f | f key = n text]) ifTrue: [self error: 'two fields named ', n text at: n].
		fields add: n text -> t.
		self accept: ','] whileTrue.
		self expect: ';'].
	fields isEmpty ifTrue: [self error: 'a structure needs a field' at: nameToken].
	s := GlslType struct: nameToken text fields: fields asArray.
	structs add: s.
	^s
!
isTypeName: aToken
	aToken kind == #ident ifFalse: [^false].
	aToken text = 'struct' ifTrue: [^true].
	((GlslType named: aToken text) notNil or: [structs anySatisfy: [:s | s name = aToken text]]) ifFalse: [^false].
	^(self lookup: aToken text) isNil
! !

!GlslShader methodsFor: 'scopes'!
declare: aVariable
	(scopes last includesKey: aVariable name) ifTrue: [
		self error: aVariable name, ' is declared twice' at: aVariable].
	(aVariable name beginsWith: 'gl_') & (aVariable storage ~~ #builtin) ifTrue: [self error: 'names starting with gl_ are reserved' at: aVariable].
	scopes last at: aVariable name put: aVariable.
	^aVariable
!
lookup: aString
	scopes reverseDo: [:s | (s at: aString ifAbsent: [nil]) ifNotNil: [:v | ^v]].
	^nil
! !

!GlslShader methodsFor: 'tokens'!
peek
	^tokens at: at
!
peek: n
	^tokens at: (at + n min: tokens size)
!
next
	| t |
	t := tokens at: at.
	at < tokens size ifTrue: [at := at + 1].
	^t
!
peekIs: aString
	^self peek is: aString
!
accept: aString
	(self peekIs: aString) ifFalse: [^false].
	self next.
	^true
!
expect: aString
	(self peekIs: aString) ifFalse: [self error: 'expected ', aString, ' before ', self describePeek at: self peek].
	^self next
!
expectIdentifier
	| t |
	t := self peek.
	(t kind == #ident and: [(self class keywords includes: t text) not]) ifFalse: [self error: 'expected a name, not ', self describePeek at: t].
	^self next
!
describePeek
	| t |
	t := self peek.
	t kind == #eof ifTrue: [^'the end'].
	^'''', t text, ''''
!
error: aString at: aTokenOrNode
	^ShaderError line: aTokenOrNode line column: aTokenOrNode column detail: aString
! !
