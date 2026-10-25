Object subclass: #VMTranslator
	instanceVariableNames: 'registry moduleClasses modules externs functions errors headerName'
	classVariableNames: ''
	package: 'VM-Translator'!

VMTranslator comment: 'I translate Lowtalk modules (docs/lowtalk.md) into C: one header with the constants, types, globals and prototypes, and one C file per module.

	(VMTranslator modules: VMTranslator vmModules header: ''samaltak'') writeTo: ''vm/gen''.
	VMTranslator generateVM	"what make translate runs"

Errors (TranslationError) name the method and quote the source; translate collects them all before it fails.'!

Error subclass: #TranslationError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Translator'!

!VMTranslator class methodsFor: 'instance creation'!
modules: aCollectionOfClasses header: aString
	^self new setModules: aCollectionOfClasses header: aString
! !

!VMTranslator class methodsFor: 'the VM'!
vmModules
	^VMModule vmModules
!
generateVM
	"Translate the VM into vm/gen (the C the build compiles)."
	^self generateVMInto: 'vm/gen'
!
generateVMInto: aDirectory
	^(self modules: self vmModules header: 'samaltak') writeTo: aDirectory
! !

!VMTranslator methodsFor: 'initialization'!
setModules: aCollection header: aString
	moduleClasses := aCollection asArray.
	headerName := aString.
	CTypeRegistry reset.
	registry := CTypeRegistry default.
	modules := IdentityDictionary new.
	externs := Dictionary new.
	errors := OrderedCollection new
! !

!VMTranslator methodsFor: 'accessing'!
registry
	^registry
!
moduleFor: aClass
	^modules at: aClass ifAbsent: [modules at: aClass put: (TModule on: aClass translator: self)]
!
translatedModules
	^moduleClasses collect: [:c | self moduleFor: c]
!
lookup: aSelector in: aTModule
	"The TFunction for aSelector seen from aTModule: its own, then its superclasses' up to VMModule."
	| c |
	c := aTModule moduleClass.
	[c notNil and: [c includesBehavior: VMModule]] whileTrue: [
		(c includesSelector: aSelector) ifTrue: [^(self moduleFor: c) functionAt: aSelector].
		c := c superclass].
	^nil
!
externFor: aSelector library: aLibraryClass
	^externs at: aLibraryClass name , '>>' , aSelector ifAbsent: [
		externs at: aLibraryClass name , '>>' , aSelector put: (TExtern library: aLibraryClass selector: aSelector translator: self)]
!
constantNamed: aString in: aClass ifAbsent: aBlock
	"A class variable of aClass or a superclass."
	| sym |
	sym := aString asSymbol.
	aClass withAllSuperclasses do: [:c |
		(c classPool includesKey: sym) ifTrue: [^c classPool at: sym]].
	^aBlock value
!
errors
	^errors
! !

!VMTranslator methodsFor: 'errors'!
error: aString
	^TranslationError signal: aString
!
error: aString in: aTFunctionOrNil node: aNodeOrNil
	| s |
	s := WriteStream on: String new.
	aTFunctionOrNil notNil ifTrue: [s print: aTFunctionOrNil; nextPutAll: ': '].
	s nextPutAll: aString.
	(aNodeOrNil notNil and: [aTFunctionOrNil notNil and: [aNodeOrNil start notNil]]) ifTrue: [
		s nextPutAll: ' in: '; nextPutAll: (self snippetOf: aNodeOrNil in: aTFunctionOrNil)].
	^TranslationError signal: s contents
!
snippetOf: aNode in: aTFunction
	| src |
	src := aTFunction ast source.
	^((src copyFrom: (aNode start max: 1) to: (aNode stop min: src size)) copyReplaceAll: (String with: Character lf) with: ' ')
! !

!VMTranslator methodsFor: 'translating'!
translate
	"Answer the files: an OrderedCollection of name -> contents. Signals a TranslationError listing every error."
	| cFunctions stencils files |
	cFunctions := OrderedCollection new.
	stencils := OrderedCollection new.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			f isFunction ifTrue: [
				[cFunctions add: ((TCodeGenerator translator: self) generate: f)]
					on: TranslationError
					do: [:e | errors add: e messageText. e return: nil]]].
		m moduleClass stencilCompiler notNil ifTrue: [stencils add: m -> (self stencilsOf: m)]].
	errors notEmpty ifTrue: [^TranslationError signal: (errors inject: '' into: [:acc :e | acc , e , (String with: Character lf)])].
	files := OrderedCollection new.
	files add: headerName , '.h' -> (self header: cFunctions).
	self translatedModules do: [:m |
		m moduleClass stencilCompiler isNil ifTrue: [
			files add: m cFileName , '.c' -> (self cFileFor: m functions: (cFunctions select: [:f | f function module == m]))]].
	stencils do: [:each | files addAll: (self stencilFilesFor: each key stencils: each value header: files first value)].
	(self primitives notEmpty) ifTrue: [files add: 'primitive_entries.c' -> self primitiveTableFile].
	files add: 'sources.mk' -> self sourcesMakefile.
	^files
!
writeTo: aDirectory
	"Write the C files into aDirectory; answer their names."
	| files |
	files := self translate.
	(File exists: aDirectory) ifFalse: [Directory create: aDirectory].
	files do: [:each | File writeText: each value to: aDirectory , '/' , each key].
	^files collect: [:each | each key]
! !

!VMTranslator methodsFor: 'printing C'!
banner
	^'/* Generated by VMTranslator from the Lowtalk sources (docs/lowtalk.md). Do not edit. */'
!
structClasses
	| structs |
	structs := OrderedCollection new.
	VMStruct allSubclasses do: [:c |
		(c isExtern not and: [c ~~ ExternStruct and: [self isTranslatedPackage: c packageName]]) ifTrue: [structs add: c]].
	^self sortStructs: structs
!
isTranslatedPackage: aString
	^moduleClasses anySatisfy: [:m | m packageName = aString]
!
sortStructs: aCollection
	"Structs that contain others by value come after them."
	| sorted visit visiting |
	sorted := OrderedCollection new.
	visiting := Set new.
	visit := nil.
	visit := [:c |
		(sorted includes: c) ifFalse: [
			(visiting includes: c) ifTrue: [self error: 'struct cycle at ' , c name].
			visiting add: c.
			c ctype fields do: [:f |
				| t |
				t := f type.
				[t isArray] whileTrue: [t := t element].
				(t isStruct and: [aCollection includes: t structClass]) ifTrue: [visit value: t structClass]].
			sorted add: c]].
	(aCollection asSortedCollection: [:a :b | a name <= b name]) do: [:c | visit value: c].
	^sorted
!
constants
	"Every class variable of VMConstants and the modules, name -> value, sorted by name."
	| all |
	all := Dictionary new.
	(Array with: VMConstants) , self moduleClassesWithSuperclasses , self structClasses asArray do: [:c |
		c classPool keysAndValuesDo: [:k :v | (v isInteger or: [v isFloat]) ifTrue: [all at: k asString put: v]]].
	^(all associations asSortedCollection: [:a :b | a key <= b key]) asArray
!
moduleClassesWithSuperclasses
	| all |
	all := OrderedCollection new.
	moduleClasses do: [:c |
		c withAllSuperclasses do: [:each | ((each inheritsFrom: VMModule) and: [(all includes: each) not]) ifTrue: [all add: each]]].
	^all asArray
!
typedefs
	| all |
	all := OrderedCollection new.
	self moduleClassesWithSuperclasses do: [:c | ((self isPlatformClass: c) not and: [c class includesSelector: #typedefs]) ifTrue: [all addAll: c typedefs]].
	^all
!
header: cFunctions
	| s guard included |
	s := WriteStream on: String new.
	guard := headerName asUppercase , '_H'.
	s nextPutAll: self banner; lf.
	s nextPutAll: '#ifndef '; nextPutAll: guard; lf; nextPutAll: '#define '; nextPutAll: guard; lf; lf.
	included := Set new.
	#('<stdatomic.h>' '<stdbool.h>' '<stddef.h>' '<stdint.h>' '<string.h>') do: [:h | self include: h on: s seen: included].
	self coreLibraries do: [:lib | lib headers do: [:h | self include: h on: s seen: included]].
	self platform: [self platformLibraries do: [:lib | lib headers do: [:h | self include: h on: s seen: included]]] on: s.
	s lf; nextPutAll: 'typedef uint64_t oop;'; lf.
	self typedefs do: [:td |
		s nextPutAll: 'typedef '; nextPutAll: ((registry parse: (td at: 2)) declare: (td at: 1) asString); nextPut: $;; lf].
	self platform: [
		self platformTypedefs do: [:td |
			s nextPutAll: 'typedef '; nextPutAll: ((registry parse: (td at: 2)) declare: (td at: 1) asString); nextPut: $;; lf]] on: s.
	s lf.
	self constants do: [:c |
		s nextPutAll: '#define '; nextPutAll: c key; space.
		c value isInteger
			ifTrue: [s nextPutAll: (CConst value: c value type: (registry at: ((c value between: -16r80000000 and: 16r7FFFFFFF) ifTrue: ['int'] ifFalse: [c value > 16r7FFFFFFFFFFFFFFF ifTrue: ['uint64_t'] ifFalse: ['int64_t']]))) cString]
			ifFalse: [s print: c value].
		s lf].
	s lf.
	self structClasses do: [:c | (self isPlatformClass: c) ifFalse: [s nextPutAll: 'typedef struct '; nextPutAll: c ctype name; space; nextPutAll: c ctype name; nextPut: $;; lf]].
	self platform: [self structClasses do: [:c | (self isPlatformClass: c) ifTrue: [s nextPutAll: 'typedef struct '; nextPutAll: c ctype name; space; nextPutAll: c ctype name; nextPut: $;; lf]]] on: s.
	s lf.
	self structClasses do: [:c | (self isPlatformClass: c) ifFalse: [self printStruct: c on: s]].
	self platform: [self structClasses do: [:c | (self isPlatformClass: c) ifTrue: [self printStruct: c on: s]]] on: s.
	(self primitives notEmpty) ifTrue: [
		s nextPutAll: 'extern '; nextPutAll: (registry at: 'PrimitiveEntry') name; nextPutAll: ' vm_primitive_table[];'; lf.
		s nextPutAll: 'extern int vm_primitive_count;'; lf; lf].
	#(false true) do: [:platform |
		self platform: [
			(self translatedModules select: [:m | (self isPlatformModule: m) = platform]) do: [:m |
				(m globals values asSortedCollection: [:a :b | a name <= b name]) do: [:g |
					(g isModuleReference not and: [g isRegister not and: [g isUsedOutside]]) ifTrue: [
						s nextPutAll: 'extern '; nextPutAll: (g type declare: g cName); nextPut: $;; lf]]]]
			if: platform on: s].
	s lf.
	#(false true) do: [:platform |
		self platform: [
			cFunctions do: [:f |
				(f function isStatic not and: [(self isPlatformModule: f function module) = platform]) ifTrue: [
					s nextPutAll: f declaration; nextPut: $;; lf]]]
			if: platform on: s].
	(modules values select: [:m | m moduleClass isInterface]) do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			(f isFunction and: [(cFunctions anySatisfy: [:g | g function cName = f cName]) not]) ifTrue: [
				s nextPutAll: (f functionType prototypeNamed: f cName); nextPut: $;; lf]]].
	s lf; nextPutAll: self helpers.
	s lf; nextPutAll: '#endif'; lf.
	^s contents
!
include: aHeader on: aStream seen: aSet
	"An #include line (once), or a preprocessor line as it is."
	aHeader first = $# ifTrue: [^aStream nextPutAll: aHeader; lf].
	(aSet includes: aHeader) ifTrue: [^self].
	aSet add: aHeader.
	aStream nextPutAll: '#include '; nextPutAll: aHeader; lf
!
platform: aBlock on: aStream
	self platform: aBlock if: true on: aStream
!
platform: aBlock if: aBoolean on: aStream
	"What only the platform layer needs is left out of a headless build (no SDL headers there)."
	aBoolean ifTrue: [aStream nextPutAll: '#ifndef SAMALTAK_NO_PLATFORM'; lf].
	aBlock value.
	aBoolean ifTrue: [aStream nextPutAll: '#endif'; lf]
!
isPlatformClass: aClass
	^aClass packageName = 'VM-Platform'
!
librariesOf: aCollectionOfTModules
	| libs |
	libs := Set new.
	aCollectionOfTModules do: [:m |
		m globals do: [:g | (g isModuleReference and: [g referencedModule inheritsFrom: CLibrary]) ifTrue: [libs add: g referencedModule]]].
	^libs
!
coreLibraries
	^((self librariesOf: (self translatedModules reject: [:m | self isPlatformModule: m])) asSortedCollection: [:a :b | a name <= b name]) asArray
!
platformLibraries
	| core |
	core := self coreLibraries.
	^(((self librariesOf: (self translatedModules select: [:m | self isPlatformModule: m])) reject: [:lib | core includes: lib])
		asSortedCollection: [:a :b | a name <= b name]) asArray
!
platformTypedefs
	| all |
	all := OrderedCollection new.
	self moduleClassesWithSuperclasses do: [:c | ((self isPlatformClass: c) and: [c class includesSelector: #typedefs]) ifTrue: [all addAll: c typedefs]].
	^all
!
helpers
	^'static inline uint64_t lt_bits_of_double(double d)
{
    uint64_t b;
    memcpy(&b, &d, 8);
    return b;
}

static inline double lt_double_from_bits(uint64_t b)
{
    double d;
    memcpy(&d, &b, 8);
    return d;
}
'
!
printStruct: aStructClass on: s
	| ctype |
	ctype := aStructClass ctype.
	ctype fields do: [:f |
		((VMStruct canUnderstand: f name asSymbol) or: [VMStruct canUnderstand: (f name , ':') asSymbol]) ifTrue: [
			self error: aStructClass name , ': the field ' , f name , ' would hide a method of VMStruct in the simulator']].
	s nextPutAll: 'struct '; nextPutAll: ctype name; nextPutAll: ' {'; lf.
	aStructClass fields do: [:spec |
		(spec at: 1) == #union
			ifTrue: [
				s nextPutAll: '    union {'; lf.
				spec allButFirst do: [:m |
					s nextPutAll: '        '; nextPutAll: ((registry parse: (m at: 2)) declare: (aStructClass cNameOfField: (m at: 1))); nextPut: $;; lf].
				s nextPutAll: '    };'; lf]
			ifFalse: [
				s nextPutAll: '    '; nextPutAll: ((registry parse: (spec at: 2)) declare: (aStructClass cNameOfField: (spec at: 1))); nextPut: $;; lf]].
	s nextPutAll: '};'; lf.
	s nextPutAll: '_Static_assert(sizeof('; nextPutAll: ctype name; nextPutAll: ') == '; print: ctype size;
		nextPutAll: ', "the simulator lays out '; nextPutAll: aStructClass name; nextPutAll: ' as C does");'; lf; lf
!
cFileFor: aTModule functions: cFunctions
	| s globals |
	s := WriteStream on: String new.
	s nextPutAll: self banner; lf.
	s nextPutAll: '/* '; nextPutAll: aTModule name; nextPutAll: ' ('; nextPutAll: aTModule moduleClass packageName; nextPutAll: ') */'; lf.
	(aTModule moduleClass class includesSelector: #cPreamble) ifTrue: [s nextPutAll: aTModule moduleClass cPreamble; lf].
	s nextPutAll: '#include "'; nextPutAll: headerName; nextPutAll: '.h"'; lf; lf.
	globals := (aTModule globals values select: [:g | g isModuleReference not and: [g isRegister not]])
		asSortedCollection: [:a :b | a name <= b name].
	globals do: [:g |
		g isUsedOutside ifFalse: [s nextPutAll: 'static '].
		s nextPutAll: (g type declare: g cName).
		g initialValue notNil ifTrue: [s nextPutAll: ' = '; nextPutAll: (self initializer: g initialValue type: g type)].
		s nextPut: $;; lf].
	globals isEmpty ifFalse: [s lf].
	cFunctions do: [:f |
		f function isStatic ifTrue: [s nextPutAll: 'static '; nextPutAll: f declaration; nextPut: $;; lf]].
	(cFunctions anySatisfy: [:f | f function isStatic]) ifTrue: [s lf].
	cFunctions do: [:f |
		s nextPutAll: '/* '; nextPutAll: f function printString; nextPutAll: ' */'; lf.
		f printOn: s.
		s lf].
	^s contents
!
initializer: aLiteral type: aCType
	aLiteral isArray ifTrue: [
		^String new: 100 streamContents: [:s |
			s nextPut: ${.
			aLiteral do: [:v | s nextPutAll: (self initializer: v type: aCType element)] separatedBy: [s nextPutAll: ', '].
			s nextPut: $}]].
	aLiteral isSymbol ifTrue: [^aLiteral asString].
	aLiteral isString ifTrue: [^(CConst value: aLiteral type: aCType) cString].
	(aLiteral == true or: [aLiteral == false]) ifTrue: [^aLiteral printString].
	aLiteral isFloat ifTrue: [^(CConst value: aLiteral type: aCType) cString].
	^(CConst value: aLiteral type: aCType) cString
! !

!VMTranslator methodsFor: 'primitives'!
primitives
	"The primitive functions, sorted by number."
	| all |
	all := OrderedCollection new.
	self translatedModules do: [:m |
		m functions do: [:f | f primitive notNil ifTrue: [all add: f]]].
	^(all asSortedCollection: [:a :b | (a primitive at: 1) <= (b primitive at: 1)]) asArray
!
primitiveTableFile
	"The platform layer's rows are left out of a headless build (SAMALTAK_NO_PLATFORM)."
	| s |
	s := WriteStream on: String new.
	s nextPutAll: self banner; lf.
	s nextPutAll: '#include "'; nextPutAll: headerName; nextPutAll: '.h"'; lf; lf.
	s nextPutAll: (registry at: 'PrimitiveEntry') name; nextPutAll: ' vm_primitive_table[] = {'; lf.
	self primitives do: [:f |
		| p platform |
		p := f primitive.
		platform := self isPlatformModule: f module.
		platform ifTrue: [s nextPutAll: '#ifndef SAMALTAK_NO_PLATFORM'; lf].
		s nextPutAll: '    {'; print: (p at: 1); nextPutAll: ', '; print: ((p at: 3) ifTrue: [1] ifFalse: [0]) + ((p at: 4) ifTrue: [2] ifFalse: [0]);
			nextPutAll: ', '; nextPutAll: (CConst value: (p at: 2) type: nil) cString; nextPutAll: ', '; nextPutAll: f cName; nextPutAll: '},'; lf.
		platform ifTrue: [s nextPutAll: '#endif'; lf]].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: 'int vm_primitive_count = sizeof vm_primitive_table / sizeof vm_primitive_table[0];'; lf.
	^s contents
!
isPlatformModule: aTModule
	^aTModule moduleClass packageName = 'VM-Platform'
!
sourcesMakefile
	"Which generated files make which VM: the core, then one platform implementation (headless, or the platform layer)."
	| s core headless platform |
	core := OrderedCollection new.
	headless := OrderedCollection new.
	platform := OrderedCollection new.
	self translatedModules do: [:m |
		| name |
		name := m cFileName , '.c'.
		m moduleClass stencilCompiler notNil
			ifTrue: [core add: m cFileName , '_table.c'; add: m cFileName , '_threaded.c']
			ifFalse: [
				(self isPlatformModule: m)
					ifTrue: [platform add: name]
					ifFalse: [(m moduleClass inheritsFrom: PlatformInterface) ifTrue: [headless add: name] ifFalse: [core add: name]]]].
	self primitives notEmpty ifTrue: [core add: 'primitive_entries.c'].
	s := WriteStream on: String new.
	s nextPutAll: '# Generated by VMTranslator. Do not edit.'; lf.
	#('VM_CORE_SOURCES' 'VM_HEADLESS_SOURCES' 'VM_PLATFORM_SOURCES') with: (Array with: core with: headless with: platform) do: [:var :list |
		s nextPutAll: var; nextPutAll: ' :='.
		(list asSortedCollection: [:a :b | a <= b]) do: [:f | s nextPutAll: ' '; nextPutAll: f].
		s lf].
	^s contents
! !

!VMTranslator methodsFor: 'stencils'!
stencilsOf: aTModule
	"Every copy of every stencil of aTModule (JitStencils), translated, in table order."
	| result compiler index |
	result := OrderedCollection new.
	compiler := aTModule moduleClass stencilCompiler.
	index := 0.
	aTModule moduleClass stencilSelectors do: [:sel |
		| f cases |
		f := aTModule functionAt: sel.
		cases := f stencilCases.
		(compiler classPool at: ('ST_' , (LowtalkNames snake: sel) asUppercase) asSymbol ifAbsent: [nil]) = index ifFalse: [
			errors add: compiler name , ' has no ST_' , (LowtalkNames snake: sel) asUppercase , ' = ' , index printString , ' (initializeStencils)'].
		(cases first to: cases last) do: [:c |
			[result add: ((TCodeGenerator translator: self) generateStencil: f case: c)]
				on: TranslationError
				do: [:e | errors add: e messageText. e return: nil].
			index := index + 1]].
	^result
!
threadedHoleParametersOf: aTModule
	"The holes a threaded stencil takes as parameters, after the state (x25 on): the compiler's first HOLE_PARAMETERS. SITE is the call's return address, VALUE goes where A does."
	| compiler |
	compiler := aTModule moduleClass stencilCompiler.
	^(((compiler classPool keys select: [:k | (k beginsWith: 'HOLE_') and: [(compiler classPool at: k) < (compiler classPool at: #HOLE_PARAMETERS)]])
		asSortedCollection: [:a :b | (compiler classPool at: a) <= (compiler classPool at: b)]) collect: [:k | k copyFrom: 6 to: k size]) asArray
!
stencilRegistersOf: aTModule
	"The machine registers of the stencils' registers, in order: preserve_none passes its first arguments in x20-x28."
	^(1 to: aTModule registers size) collect: [:i | 'x' , (19 + i) printString]
!
stencilFilesFor: aTModule stencils: aCollection header: headerText
	"The stencil files of aTModule: the copy-and-patch source (cc compiles it now, it is not part of the VM), the table read back from the object file, the threaded stencils, and the header declaring the tables."
	| name source h table |
	name := aTModule cFileName.
	h := self stencilHeaderFor: aTModule.
	source := self stencilSourceFor: aTModule stencils: aCollection threaded: false.
	table := self stencilTableFor: aTModule stencils: aCollection source: source header: headerText stencilHeader: h.
	^OrderedCollection new
		add: name , '.h' -> h;
		add: name , '.c' -> source;
		add: name , '_table.c' -> table;
		add: name , '_threaded.c' -> (self stencilSourceFor: aTModule stencils: aCollection threaded: true);
		yourself
!
stencilHeaderFor: aTModule
	| s |
	s := WriteStream on: String new.
	s nextPutAll: self banner; lf.
	s nextPutAll: '/* The stencil tables (JitStencilTable): '; nextPutAll: aTModule cFileName; nextPutAll: '_table.c, '; nextPutAll: aTModule cFileName; nextPutAll: '_threaded.c */'; lf.
	s nextPutAll: '#include <stdint.h>'; lf.
	#('const int32_t jit_stencil_counts[]' 'const uint8_t jit_stencil_code[]' 'const uint32_t jit_stencils[]' 'const uint32_t jit_stencil_relocs[]'
		'const char *const jit_stencil_names[]' 'const uint64_t jit_stencil_symbols[]' 'const char *const jit_stencil_symbol_names[]'
		'const uint8_t jit_stencil_data[]' 'const uint32_t jit_stencil_data_relocs[]'
		'const uint64_t jit_threaded_fns[]' 'const uint32_t jit_threaded_holes[]' 'const uint32_t jit_threaded_conts[]')
		do: [:d | s nextPutAll: 'extern '; nextPutAll: d; nextPut: $;; lf].
	^s contents
!
stencilState: aTModule
	"name -> C type of the stencils' registers, in order."
	^aTModule registers collect: [:r | (aTModule globalNamed: r) cName -> (aTModule globalNamed: r) type]
!
stencilSourceFor: aTModule stencils: aCollection threaded: aBoolean
	"The stencils as C: for copy-and-patch, holes are the addresses of extern symbols and continuations musttail calls of extern functions (what the compiler patches); threaded, holes are parameters and continuations musttail calls of a return (ret) that leaves the state in the stencils' registers and the continuation in the next one."
	| s state regs compiler names params |
	s := WriteStream on: String new.
	state := self stencilState: aTModule.
	regs := self stencilRegistersOf: aTModule.
	compiler := aTModule moduleClass stencilCompiler.
	s nextPutAll: self banner; lf.
	aBoolean
		ifTrue: [
			s nextPutAll: '/* '; nextPutAll: aTModule name; nextPutAll: ' ('; nextPutAll: aTModule moduleClass packageName;
				nextPutAll: '): the threaded stencils, called by machine code (--jit threaded). */'; lf]
		ifFalse: [
			s nextPutAll: '/* '; nextPutAll: aTModule name; nextPutAll: ' ('; nextPutAll: aTModule moduleClass packageName;
				nextPutAll: '): the copy-and-patch stencils. cc compiles them when the VM is translated; '; nextPutAll: aTModule cFileName; nextPutAll: '_table.c is what it made of them. Not part of the VM. */'; lf].
	s nextPutAll: '#include "'; nextPutAll: headerName; nextPutAll: '.h"'; lf; lf.
	params := self threadedHoleParametersOf: aTModule.
	s nextPutAll: '#define JIT_STENCIL_FN __attribute__((preserve_none))'; lf.
	s nextPutAll: '#define JIT_ARGS '.
	state do: [:a | s nextPutAll: (a value declare: a key)] separatedBy: [s nextPutAll: ', '].
	aBoolean ifTrue: [params do: [:h | s nextPutAll: ', uint64_t hole_'; nextPutAll: h]].
	s lf.
	aBoolean
		ifTrue: [
			s nextPutAll: '#define JIT_HOLE(name) JIT_HOLE_##name'; lf.
			params do: [:h | s nextPutAll: '#define JIT_HOLE_'; nextPutAll: h; nextPutAll: ' hole_'; nextPutAll: h; lf].
			s nextPutAll: '#define JIT_HOLE_SITE ((uint64_t)(uintptr_t)__builtin_return_address(0))'; lf.
			s nextPutAll: '#define JIT_HOLE_VALUE hole_A'; lf.
			s nextPutAll: '#define JIT_TAIL(name) __attribute__((musttail)) return jit_threaded_return('.
			state do: [:a | s nextPutAll: a key. s nextPutAll: ', '].
			s nextPutAll: 'CONT_##name'.
			params allButFirst do: [:h | s nextPutAll: ', hole_'; nextPutAll: h].
			s nextPut: $); lf]
		ifFalse: [
			s nextPutAll: '#define JIT_HOLE(name) ((uint64_t)(uintptr_t)_JIT_##name)'; lf.
			s nextPutAll: '#define JIT_TAIL(name) __attribute__((musttail)) return _JIT_##name('.
			state do: [:a | s nextPutAll: a key] separatedBy: [s nextPutAll: ', '].
			s nextPut: $); lf].
	s nextPutAll: (self stencilCallMacro: aTModule); lf.
	aBoolean
		ifTrue: [
			s nextPutAll: '/* the continuation: back to the machine code, the state in '; nextPutAll: regs first; nextPut: $-; nextPutAll: regs last;
				nextPutAll: ', the continuation (CONT_...) in x'; print: 20 + state size; nextPutAll: ' */'; lf.
			s nextPutAll: '__attribute__((preserve_none, naked)) static void jit_threaded_return(JIT_ARGS)'; lf; nextPutAll: '{'; lf.
			s nextPutAll: '    __asm__ volatile("ret");'; lf; nextPutAll: '}'; lf; lf]
		ifFalse: [
			names := ((compiler classPool keys select: [:k | k beginsWith: 'HOLE_']) reject: [:k | k = #HOLE_COUNT]) asSortedCollection asArray.
			s nextPutAll: 'extern char '.
			names do: [:k | s nextPutAll: '_JIT_'; nextPutAll: (k copyFrom: 6 to: k size); nextPutAll: '[]'] separatedBy: [s nextPutAll: ', '].
			s nextPut: $;; lf.
			names := (compiler classPool keys select: [:k | k beginsWith: 'CONT_']) asSortedCollection asArray.
			s nextPutAll: 'extern JIT_STENCIL_FN void '.
			names do: [:k | s nextPutAll: '_JIT_'; nextPutAll: (k copyFrom: 6 to: k size); nextPutAll: '(JIT_ARGS)'] separatedBy: [s nextPutAll: ', '].
			s nextPut: $;; lf; lf].
	aCollection do: [:st | st threaded: aBoolean. st printOn: s. s lf].
	aCollection do: [:st | st threaded: false].
	aBoolean ifFalse: [^s contents].
	s nextPutAll: 'const uint64_t jit_threaded_fns[] = {'; lf.
	aCollection do: [:st | st threaded: true. s nextPutAll: '    (uint64_t)(uintptr_t)&'; nextPutAll: st cName; nextPut: $,; lf. st threaded: false].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: '/* the holes each takes (bits HOLE_...), the continuations it answers (bits CONT_...) */'; lf.
	s nextPutAll: 'const uint32_t jit_threaded_holes[] = {'.
	aCollection doWithIndex: [:st :i | i \\ 16 = 1 ifTrue: [s lf; nextPutAll: '   ']. s space; print: st context holeMask; nextPut: $,].
	s lf; nextPutAll: '};'; lf; lf.
	s nextPutAll: 'const uint32_t jit_threaded_conts[] = {'.
	aCollection doWithIndex: [:st :i | i \\ 16 = 1 ifTrue: [s lf; nextPutAll: '   ']. s space; print: st context continuationMask; nextPut: $,].
	s lf; nextPutAll: '};'; lf.
	^s contents
!
stencilCallMacro: aTModule
	"JIT_CALL(entry): call compiled code with the frame in x19 and the state in its register, keeping sp and fr (the fourth and fifth registers) on the native stack meanwhile, then reload fp from the frame. The callee clobbers every other register."
	| state regs s clobbers |
	state := self stencilState: aTModule.
	regs := self stencilRegistersOf: aTModule.
	s := WriteStream on: String new.
	clobbers := OrderedCollection new.
	(0 to: 15) do: [:i | clobbers add: 'x' , i printString].
	clobbers add: 'x17'; add: 'x19'; add: (regs at: 1); add: (regs at: 2); add: 'x25'; add: 'x26'; add: 'x27'; add: 'x28'; add: 'x30'.
	(0 to: 31) do: [:i | clobbers add: 'v' , i printString].
	clobbers add: 'cc'; add: 'memory'.
	s nextPutAll: '#define JIT_CALL(entry) do { \'; lf.
	#(3 4 5) do: [:i |
		s tab; nextPutAll: 'register '; nextPutAll: ((state at: i) value declare: 'call_' , (state at: i) key); nextPutAll: ' __asm__("'; nextPutAll: (regs at: i);
			nextPutAll: '") = '; nextPutAll: (state at: i) key; nextPutAll: '; \'; lf].
	s tab; nextPutAll: 'register uint64_t call_entry __asm__("x16") = (entry); \'; lf.
	s tab; nextPutAll: '__asm__ volatile("mov x19, '; nextPutAll: (regs at: 5); nextPutAll: '\n\tstp '; nextPutAll: (regs at: 4); nextPutAll: ', '; nextPutAll: (regs at: 5);
		nextPutAll: ', [sp, #-16]!!\n\tblr x16\n\tldp '; nextPutAll: (regs at: 4); nextPutAll: ', '; nextPutAll: (regs at: 5); nextPutAll: ', [sp], #16" \'; lf.
	s tab; tab; nextPutAll: ': "+r"(call_' , (state at: 4) key , '), "+r"(call_' , (state at: 5) key , '), "+r"(call_entry) : "r"(call_' , (state at: 3) key , ') : '.
	clobbers do: [:c | s nextPut: $"; nextPutAll: c; nextPut: $"] separatedBy: [s nextPutAll: ', '].
	s nextPutAll: '); \'; lf.
	#(4 5) do: [:i | s tab; nextPutAll: (state at: i) key; nextPutAll: ' = call_'; nextPutAll: (state at: i) key; nextPutAll: '; \'; lf].
	s tab; nextPutAll: (state at: 1) key; nextPutAll: ' = '; nextPutAll: (state at: 5) key; nextPutAll: '->fp; \'; lf.
	s nextPutAll: '} while (0)'.
	^s contents
!
stencilCFlags
	"How cc compiles the copy-and-patch stencils: optimized, without unwind tables, stack protector, jump tables or outlined code, so that each stencil is one piece of code on its own."
	^'-O2 -std=gnu11 -DSAMALTAK_NO_PLATFORM -D_DARWIN_C_SOURCE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector -fno-jump-tables -mllvm -enable-machine-outliner=never'
!
stencilTableFor: aTModule stencils: aCollection source: source header: headerText stencilHeader: h
	"Compile the stencils with cc and read the object file: the table as C."
	| dir run object table s |
	dir := OSProcess temporaryPath: 'stencils'.
	(OSProcess run: 'mkdir -p ' , (OSProcess quote: dir)) succeeded ifFalse: [^self error: 'cannot make ' , dir].
	[File writeText: headerText to: dir , '/' , headerName , '.h'.
	 File writeText: h to: dir , '/' , aTModule cFileName , '.h'.
	 File writeText: source to: dir , '/' , aTModule cFileName , '.c'.
	 run := OSProcess run: 'cc ' , self stencilCFlags , ' -I' , (OSProcess quote: dir) , ' -c -o ' , (OSProcess quote: dir , '/stencils.o') , ' ' , (OSProcess quote: dir , '/' , aTModule cFileName , '.c').
	 run succeeded ifFalse: [^self error: 'cc could not compile the stencils: ' , run errorOutput].
	 object := MachObjectFile fromBytes: (File readBytes: dir , '/stencils.o')]
		ensure: [OSProcess run: 'rm -r ' , (OSProcess quote: dir)].
	table := StencilTable object: object compiler: aTModule moduleClass stencilCompiler stencils: (aCollection collect: [:st | st cName]) names: (aCollection collect: [:st | st stencilName]).
	s := WriteStream on: String new.
	s nextPutAll: self banner; lf.
	s nextPutAll: '/* The copy-and-patch stencils (JitStencilTable): what cc '; nextPutAll: self stencilCFlags; nextPutAll: ' made of '; nextPutAll: aTModule cFileName;
		nextPutAll: '.c, read from the object file (MachObjectFile, StencilTable). */'; lf.
	s nextPutAll: table cSource.
	^s contents
! !
