Object subclass: #CTypeRegistry
	instanceVariableNames: 'types constants tokens position parsed parsedLiterals'
	classVariableNames: 'Default'
	package: 'VM-Lowtalk'!

CTypeRegistry comment: 'I know the C types of the VM: the built-in ones, typedefs declared by CLibrary classes, and the structs (VMStruct and ExternStruct subclasses, by class name and by C name). I parse C type names and function prototypes:

	CTypeRegistry default parse: ''void (*)(void)''.
	CTypeRegistry default parsePrototype: ''void *memcpy(void *dst, const void *src, size_t n)''	"{name. CFunctionType}"

Array sizes may name constants (''oop[CSTACK_SLOTS]''): class variables of VMConstants and of the VM''s classes. The default registry is rebuilt by reset (VMTranslator and VMSimulation do so when they start).'!

!CTypeRegistry class methodsFor: 'accessing'!
default
	Default isNil ifTrue: [Default := self new initializeFromImage].
	^Default
!
reset
	Default := nil
! !

!CTypeRegistry methodsFor: 'initialization'!
initialize
	types := Dictionary new.
	constants := Dictionary new.
	self addBuiltins
!
addBuiltins
	| add |
	add := [:aName :size :signed | types at: aName put: (CIntegerType named: aName size: size signed: signed)].
	types at: 'void' put: CVoidType new.
	types at: 'bool' put: CBoolType new.
	types at: '_Bool' put: (types at: 'bool').
	add value: 'char' value: 1 value: true.
	add value: 'signed char' value: 1 value: true.
	add value: 'unsigned char' value: 1 value: false.
	add value: 'short' value: 2 value: true.
	add value: 'unsigned short' value: 2 value: false.
	add value: 'int' value: 4 value: true.
	add value: 'unsigned' value: 4 value: false.
	add value: 'long' value: 8 value: true.
	add value: 'unsigned long' value: 8 value: false.
	add value: 'long long' value: 8 value: true.
	add value: 'unsigned long long' value: 8 value: false.
	#(8 16 32 64) do: [:bits |
		add value: 'int' , bits printString , '_t' value: bits // 8 value: true.
		add value: 'uint' , bits printString , '_t' value: bits // 8 value: false].
	add value: 'size_t' value: 8 value: false.
	add value: 'ssize_t' value: 8 value: true.
	add value: 'intptr_t' value: 8 value: true.
	add value: 'uintptr_t' value: 8 value: false.
	add value: 'ptrdiff_t' value: 8 value: true.
	add value: 'off_t' value: 8 value: true.
	add value: 'time_t' value: 8 value: true.
	add value: 'pid_t' value: 4 value: true.
	add value: 'oop' value: 8 value: false.
	add value: 'atomic_int' value: 4 value: true.
	types at: 'atomic_bool' put: (CBoolType named: 'atomic_bool').
	types at: 'float' put: (CFloatType named: 'float' size: 4).
	types at: 'double' put: (CFloatType named: 'double' size: 8)
!
initializeFromImage
	"Add the constants, structs and library typedefs of the image's VM classes."
	self addConstantsOf: (Smalltalk at: #VMConstants).
	(Smalltalk at: #VMModule ifAbsent: [nil]) ifNotNil: [:c | c withAllSubclasses do: [:each |
		self addConstantsOf: each.
		(each class includesSelector: #typedefs) ifTrue: [self addTypedefsOf: each]]].
	(Smalltalk at: #CLibrary ifAbsent: [nil]) ifNotNil: [:c |
		c allSubclasses do: [:each | self addConstantsOf: each. self addTypedefsOf: each]].
	(Smalltalk at: #VMStruct ifAbsent: [nil]) ifNotNil: [:c |
		c allSubclasses do: [:each | self addConstantsOf: each. each == ExternStruct ifFalse: [self addStruct: each]]]
!
addConstantsOf: aClass
	aClass classPool keysAndValuesDo: [:k :v | v isInteger ifTrue: [constants at: k asString put: v]]
!
addTypedefsOf: aLibraryClass
	"typedefs answers #((name kind) ...): kind is a C type name, or #opaque."
	aLibraryClass typedefs do: [:each |
		(each at: 2) == #opaque
			ifTrue: [types at: (each at: 1) asString put: (COpaqueType named: (each at: 1) asString)]
			ifFalse: [types at: (each at: 1) asString put: (CTypedefType named: (each at: 1) asString for: (self parse: (each at: 2)))]]
!
addStruct: aStructClass
	| type |
	type := CStructType forClass: aStructClass registry: self.
	types at: aStructClass name asString put: type.
	types at: type name put: type
! !

!CTypeRegistry methodsFor: 'accessing'!
at: aString
	^types at: aString ifAbsent: [self error: 'unknown C type ' , aString]
!
at: aString ifAbsent: aBlock
	^types at: aString ifAbsent: aBlock
!
at: aString put: aCType
	types at: aString put: aCType
!
constantAt: aString ifAbsent: aBlock
	^constants at: aString ifAbsent: aBlock
!
structTypes
	^(types values select: [:t | t isStruct]) asSet
! !

!CTypeRegistry methodsFor: 'parsing'!
parse: aStringOrSymbol
	"Answer the CType named by a C abstract declarator. Cached by the string object first (the simulation passes the same literals again and again), then by its contents."
	parsedLiterals isNil ifTrue: [parsedLiterals := IdentityDictionary new. parsed := Dictionary new].
	^parsedLiterals at: aStringOrSymbol ifAbsent: [
		parsedLiterals at: aStringOrSymbol put: (parsed at: aStringOrSymbol asString ifAbsent: [
			parsed at: aStringOrSymbol asString put: (self parseUncached: aStringOrSymbol)])]
!
parseUncached: aStringOrSymbol
	| decl |
	self tokenize: aStringOrSymbol asString.
	decl := self parseDeclaratorOn: self parseSpecifiers.
	self expectEnd: aStringOrSymbol.
	^decl at: 2
!
parseDeclaration: aString
	"Answer {name. type} for a C declaration such as 'oop cstack[64]'."
	| decl |
	self tokenize: aString.
	decl := self parseDeclaratorOn: self parseSpecifiers.
	self expectEnd: aString.
	^decl
!
parsePrototype: aString
	"Answer {name. CFunctionType} for a C function prototype."
	| decl |
	decl := self parseDeclaration: aString.
	((decl at: 1) isNil or: [(decl at: 2) isFunction not]) ifTrue: [
		self error: 'not a function prototype: ' , aString].
	^decl
! !

!CTypeRegistry methodsFor: 'private'!
tokenize: aString
	| s out c word |
	s := ReadStream on: aString.
	out := OrderedCollection new.
	[s atEnd] whileFalse: [
		c := s next.
		(c isLetter or: [c = $_])
			ifTrue: [
				word := WriteStream on: String new.
				word nextPut: c.
				[s atEnd not and: [s peek isLetter or: [s peek isDigit or: [s peek = $_]]]] whileTrue: [word nextPut: s next].
				out add: word contents]
			ifFalse: [
				c isDigit
					ifTrue: [
						word := WriteStream on: String new.
						word nextPut: c.
						[s atEnd not and: [s peek isLetter or: [s peek isDigit]]] whileTrue: [word nextPut: s next].
						out add: (Number readFrom: (self cNumber: word contents))]
					ifFalse: [
						c = $.
							ifTrue: [
								(s next: 2) = '..' ifFalse: [self error: 'bad C type: ' , aString].
								out add: '...']
							ifFalse: [(c isSeparator) ifFalse: [out add: (String with: c)]]]]].
	tokens := out asArray.
	position := 1
!
cNumber: aString
	"C integer literal → Smalltalk syntax."
	| s |
	s := aString asLowercase.
	[s notEmpty and: [s last = $u or: [s last = $l]]] whileTrue: [s := s allButLast].
	(s beginsWith: '0x') ifTrue: [^'16r' , (s allButFirst: 2) asUppercase].
	^s
!
peek
	^position <= tokens size ifTrue: [tokens at: position] ifFalse: [nil]
!
peekAt: anInteger
	^position + anInteger - 1 <= tokens size ifTrue: [tokens at: position + anInteger - 1] ifFalse: [nil]
!
next
	| t |
	t := self peek.
	position := position + 1.
	^t
!
expect: aString
	self next = aString ifFalse: [self error: 'expected ' , aString , ' in C type ' , (tokens inject: '' into: [:a :t | a , ' ' , t printString])]
!
expectEnd: aString
	position <= tokens size ifTrue: [self error: 'unexpected ' , self peek printString , ' in C type ' , aString asString]
!
isTypeWord: aString
	aString isString ifFalse: [^false].
	^(#('const' 'volatile' 'struct' 'unsigned' 'signed' 'long' 'short' 'int' 'char' 'static' 'extern') includes: aString)
		or: [types includesKey: aString]
!
parseSpecifiers
	"Answer the base type of a declaration's specifiers."
	| words t |
	words := OrderedCollection new.
	[(t := self peek) notNil and: [self isTypeWord: t]] whileTrue: [
		self next.
		t = 'struct'
			ifTrue: [words add: 'struct ' , self next]
			ifFalse: [(#('const' 'volatile' 'static' 'extern') includes: t) ifFalse: [words add: t]].
		"a typedef name or struct ends the specifiers unless signedness or size words follow"
		((types includesKey: t) and: [(#('unsigned' 'signed' 'long' 'short' 'int' 'char') includes: t) not]) ifTrue: [
			[(t := self peek) = 'const' or: [t = 'volatile']] whileTrue: [self next].
			^self baseTypeFor: words]].
	words isEmpty ifTrue: [self error: 'C type expected at ' , self peek printString].
	^self baseTypeFor: words
!
baseTypeFor: words
	| key |
	key := words inject: '' into: [:acc :w | acc isEmpty ifTrue: [w] ifFalse: [acc , ' ' , w]].
	key = 'unsigned int' ifTrue: [key := 'unsigned'].
	key = 'signed' ifTrue: [key := 'int'].
	key = 'signed int' ifTrue: [key := 'int'].
	(key endsWith: ' int') ifTrue: [(types includesKey: (key allButLast: 4)) ifTrue: [key := key allButLast: 4]].
	(key beginsWith: 'struct ') ifTrue: [^types at: key ifAbsent: [types at: key put: (COpaqueType named: key)]].
	^types at: key ifAbsent: [self error: 'unknown C type ' , key]
!
parseDeclaratorOn: aBaseType
	"Answer {name or nil. type}."
	| type inner suffixStart decl |
	type := aBaseType.
	[self peek = '*'] whileTrue: [
		self next.
		type := CPointerType to: type.
		[self peek = 'const' or: [self peek = 'volatile']] whileTrue: [self next]].
	(self peek = '(' and: [(self peekAt: 2) = '*' or: [(self peekAt: 2) = '(']])
		ifTrue: [
			self next.
			inner := position.
			self skipToClosingParen.
			type := self parseSuffixesOn: type.
			suffixStart := position.
			position := inner.
			decl := self parseDeclaratorOn: type.
			self expect: ')'.
			position := suffixStart.
			^decl].
	(self peek isString and: [self peek notEmpty and: [self peek first isLetter or: [self peek first = $_]]])
		ifTrue: [decl := self next]
		ifFalse: [decl := nil].
	^Array with: decl with: (self parseSuffixesOn: type)
!
skipToClosingParen
	| depth |
	depth := 1.
	[depth > 0] whileTrue: [
		| t |
		t := self next.
		t isNil ifTrue: [self error: 'unbalanced parentheses in C type'].
		t = '(' ifTrue: [depth := depth + 1].
		t = ')' ifTrue: [depth := depth - 1]]
!
parseSuffixesOn: aType
	| suffixes type |
	suffixes := OrderedCollection new.
	[self peek = '[' or: [self peek = '(']] whileTrue: [
		self next = '['
			ifTrue: [suffixes add: (Array with: #array with: self parseArraySize). self expect: ']']
			ifFalse: [suffixes add: (Array with: #function with: self parseParameters)]].
	type := aType.
	suffixes reverseDo: [:each |
		(each at: 1) == #array
			ifTrue: [type := CArrayType of: type count: (each at: 2)]
			ifFalse: [type := CFunctionType returning: type parameters: ((each at: 2) at: 1) names: ((each at: 2) at: 2) variadic: ((each at: 2) at: 3)]].
	^type
!
parseArraySize
	| t |
	t := self next.
	t isInteger ifTrue: [^t].
	^constants at: t ifAbsent: [self error: 'unknown array size ' , t printString]
!
parseParameters
	"After '(': answer {types. names. variadic}."
	| ptypes names variadic decl |
	ptypes := OrderedCollection new.
	names := OrderedCollection new.
	variadic := false.
	self peek = ')' ifTrue: [self next. ^Array with: #() with: #() with: false].
	(self peek = 'void' and: [(self peekAt: 2) = ')']) ifTrue: [self next; next. ^Array with: #() with: #() with: false].
	[self peek = '...'
		ifTrue: [self next. variadic := true]
		ifFalse: [
			decl := self parseDeclaratorOn: self parseSpecifiers.
			(decl at: 2) isArray ifTrue: [decl at: 2 put: (decl at: 2) decayed].
			ptypes add: (decl at: 2).
			names add: ((decl at: 1) ifNil: ['p' , ptypes size printString])].
	 self peek = ','] whileTrue: [self next].
	self expect: ')'.
	^Array with: ptypes asArray with: names asArray with: variadic
! !
