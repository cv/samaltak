Object subclass: #VMTranslator
	instanceVariableNames: 'registry moduleClasses modules externs functions errors headerName queue queued'
	classVariableNames: ''
	package: 'VM-Translator'!

VMTranslator comment: 'I translate Lowtalk modules (docs/lowtalk.md) into C: one header with the constants, types, globals and prototypes, and one C file per module.

	(VMTranslator modules: VMTranslator vmModules header: ''samaltak'') writeTo: ''vm/gen''.
	VMTranslator generateVM	"what make translate runs"

The C functions take their names from their selectors (assignCNames) and their signatures from their callers and returns (inferSignatures, TSignature).

Errors (TranslationError) name the method and quote the source; translate collects them all before it fails.

One vm/gen serves every OS: a module or C library whose targetOS is #darwin or #linux has its headers, prototypes and C file guarded by the OS''s predefined macro (targetOSes), and sources.mk lists its file under that OS (VM_CORE_SOURCES_LINUX ...), so the build picks the OS''s implementation of each interface. A module for every OS may not use one OS''s library or module.'!

Error subclass: #TranslationError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Translator'!

!VMTranslator class methodsFor: 'instance creation'!
modules: aCollectionOfClasses header: aString
	^self new setModules: aCollectionOfClasses header: aString
! !

!VMTranslator class methodsFor: 'operating systems'!
targetOSes
	"#(os predefinedMacro makeSuffix): the operating systems a module or library can be for (targetOS), the C macro that is defined there, the suffix of their source lists in sources.mk (uname -s, upper case)."
	^#((darwin '__APPLE__' 'DARWIN') (linux '__linux__' 'LINUX'))
!
guardFor: anOS
	^((self targetOSes detect: [:e | (e at: 1) = anOS] ifNone: [self error: 'no such target OS: ' , anOS printString]) at: 2)
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
	self initializeConstants.
	CTypeRegistry reset.
	registry := CTypeRegistry default.
	modules := IdentityDictionary new.
	externs := Dictionary new.
	errors := OrderedCollection new
!
initializeConstants
	"The constants I write are the class variables the modules' class-side initialize methods set: run those again, superclasses first, each once, so an edited one (e.g. GarbageCollector's TENURE_AGE) is what I translate."
	| done |
	done := IdentitySet new.
	moduleClasses do: [:module |
		module withAllSuperclasses reverseDo: [:c |
			((c == VMConstants or: [c inheritsFrom: VMConstants]) and: [(done includes: c) not]) ifTrue: [
				done add: c.
				(c class includesSelector: #initialize) ifTrue: [c initialize]]]]
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
	| cFunctions files |
	cFunctions := OrderedCollection new.
	self checkTargetOSes.
	self assignCNames.
	self inferSignatures.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			f isFunction ifTrue: [
				[cFunctions add: ((TCodeGenerator translator: self inferring: false) generate: f)]
					on: TranslationError
					do: [:e | errors add: e messageText. e return: nil]]]].
	errors notEmpty ifTrue: [^TranslationError signal: (errors inject: '' into: [:acc :e | acc , e , (String with: Character lf)])].
	files := OrderedCollection new.
	files add: headerName , '.h' -> (self header: cFunctions).
	self translatedModules do: [:m |
		files add: m cFileName , '.c' -> (self cFileFor: m functions: (cFunctions select: [:f | f function module == m]))].
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
!
inferSignatures
	"Every function's signature (TSignature): generate the functions as far as what is known allows (TCodeGenerator inferring), a function again whenever a signature it depends on changes, until none changes; the smallest first, since most of them return what a big caller wants to know. A function with parameters waits for a caller. Then literals alone give their own types, which may start another round. Answer how many generations it took."
	| count |
	queue := SortedCollection sortBlock: [:a :b | a ast source size <= b ast source size].
	queued := IdentitySet new.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			(f isFunction and: [f parametersKnown]) ifTrue: [self enqueue: f]]].
	count := 0.
	[[queue isEmpty] whileFalse: [
		| f |
		f := queue removeFirst.
		queued remove: f.
		count := count + 1.
		count > 20000 ifTrue: [^self error: 'the signatures do not settle'].
		(TCodeGenerator translator: self inferring: true) generate: f].
	 self adoptConstants] whileTrue.
	queue := nil.
	^count
!
adoptConstants
	"Signatures that have seen nothing but literals take their types now; answer whether any did (the queue has work then)."
	| any |
	any := false.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			(f isFunction and: [f signature adoptConstants]) ifTrue: [any := true]]].
	^any
!
enqueue: aTFunction
	"To be generated (again): only inside inferSignatures, and only functions of the modules I translate."
	queue isNil ifTrue: [^self].
	((aTFunction isFunction and: [moduleClasses identityIncludes: aTFunction module moduleClass]) and: [(queued includes: aTFunction) not]) ifTrue: [
		queued add: aTFunction.
		queue add: aTFunction]
! !

!VMTranslator methodsFor: 'names'!
assignCNames
	"Every function's C name: the first keyword of its selector in snake case (TFunction>>baseName); one that another function or a C library, global, local or type name claims too takes its module's name in front, and if that still clashes (same module, same first keyword) its whole selector. An interface and its implementations are one function."
	| functions names reserved |
	self moduleClassesWithSuperclasses do: [:c | self moduleFor: c].
	functions := self functionsSorted reject: [:f | f interface notNil].
	names := IdentityDictionary new.
	functions do: [:f | names at: f put: f baseName].
	reserved := self reservedCNames.
	#(moduleQualifiedName fullyQualifiedName) do: [:qualified |
		| counts |
		counts := Bag withAll: names values.
		functions do: [:f |
			((reserved includes: (names at: f)) or: [(counts occurrencesOf: (names at: f)) > 1])
				ifTrue: [names at: f put: (f perform: qualified)]]].
	(Set withAll: names values) size = functions size ifFalse: [^self error: 'two functions have the same C name'].
	modules do: [:m |
		m functions do: [:f |
			f isFunction ifTrue: [f cName: (names at: (f interface ifNil: [f]))]]]
!
functionsSorted
	"Every function, translated or an interface's, in a stable order."
	| all |
	all := OrderedCollection new.
	(modules values asSortedCollection: [:a :b | a name <= b name]) do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			f isFunction ifTrue: [all add: f]]].
	^all
!
reservedCNames
	"The names a function may not take: C library names and what the system headers declare, globals, the names of types, and every name a local in the modules' code goes by (a local would hide the function)."
	| names |
	names := Set withAll: #('ops' 'local' 'stop' 'v' 'memset' 'vm_primitive_table' 'vm_primitive_count' 'system' 'semaphore_signal' 'semaphore_wait').
	names addAll: registry typeNames.
	CLibrary allSubclasses do: [:lib |
		lib selectors do: [:sel |
			| m |
			m := lib compiledMethodAt: sel.
			(m pragmas notNil and: [m pragmas anySatisfy: [:p | #(#c: #cVariable: #cMacro:) includes: p selector]]) ifTrue: [
				names add: (self externFor: sel library: lib) cName]]].
	modules do: [:m |
		m globals do: [:g | g isModuleReference ifFalse: [names add: g cName]].
		m functions do: [:f | names addAll: f localNames]].
	^names
! !

!VMTranslator methodsFor: 'operating systems'!
checkTargetOSes
	"A module may use the libraries and modules of every OS and of its own."
	self translatedModules do: [:m |
		| os |
		os := m moduleClass targetOS.
		m globals do: [:g |
			| other |
			(g isModuleReference and: [(other := g referencedModule targetOS) notNil and: [other ~= os]]) ifTrue: [
				errors add: m name , ': ' , g name , ' is ' , g referencedModule name , ', for ' , other , ' only, but ' , m name , ' is for ' , (os ifNil: ['every OS'])]]].
	errors notEmpty ifTrue: [^TranslationError signal: (errors inject: '' into: [:acc :e | acc , e , (String with: Character lf)])]
!
osGroups: aCollection key: aKeyBlock do: anEmitBlock on: aStream
	"anEmitBlock on the elements for every OS, then on each OS's under its guard. aKeyBlock answers an element's targetOS."
	(aCollection select: [:e | (aKeyBlock value: e) isNil]) do: anEmitBlock.
	self class targetOSes do: [:spec |
		| own |
		own := aCollection select: [:e | (aKeyBlock value: e) = (spec at: 1)].
		own notEmpty ifTrue: [
			aStream nextPutAll: '#ifdef '; nextPutAll: (spec at: 2); lf.
			own do: anEmitBlock.
			aStream nextPutAll: '#endif'; lf]]
!
includeLibraries: aCollection on: aStream seen: aSet
	"The headers of the libraries for every OS, then each OS's under its guard. What an OS's libraries include stays unseen, so that a later library for every OS still includes it."
	(aCollection select: [:lib | lib targetOS isNil]) do: [:lib | lib headers do: [:h | self include: h on: aStream seen: aSet]].
	self class targetOSes do: [:spec |
		| own seen |
		own := aCollection select: [:lib | lib targetOS = (spec at: 1)].
		own notEmpty ifTrue: [
			seen := aSet copy.
			aStream nextPutAll: '#ifdef '; nextPutAll: (spec at: 2); lf.
			own do: [:lib | lib headers do: [:h | self include: h on: aStream seen: seen]].
			aStream nextPutAll: '#endif'; lf]]
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
	self includeLibraries: self coreLibraries on: s seen: included.
	self platform: [self includeLibraries: self platformLibraries on: s seen: included] on: s.
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
			self osGroups: (self translatedModules select: [:m | (self isPlatformModule: m) = platform]) key: [:m | m moduleClass targetOS] do: [:m |
				(m globals values asSortedCollection: [:a :b | a name <= b name]) do: [:g |
					(g isModuleReference not and: [g isRegister not and: [g isUsedOutside]]) ifTrue: [
						s nextPutAll: 'extern '; nextPutAll: (g type declare: g cName); nextPut: $;; lf]]] on: s]
			if: platform on: s].
	s lf.
	#(false true) do: [:platform |
		self platform: [
			self osGroups: (cFunctions select: [:f | f function isStatic not and: [(self isPlatformModule: f function module) = platform]])
				key: [:f | f function module moduleClass targetOS]
				do: [:f | s nextPutAll: f declaration; nextPut: $;; lf]
				on: s]
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
	aTModule moduleClass targetOS notNil ifTrue: [s nextPutAll: '#ifdef '; nextPutAll: (self class guardFor: aTModule moduleClass targetOS); lf; lf].
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
	aTModule moduleClass targetOS notNil ifTrue: [s nextPutAll: '#endif'; lf].
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
		| p platform os |
		p := f primitive.
		platform := self isPlatformModule: f module.
		os := f module moduleClass targetOS.
		platform ifTrue: [s nextPutAll: '#ifndef SAMALTAK_NO_PLATFORM'; lf].
		os notNil ifTrue: [s nextPutAll: '#ifdef '; nextPutAll: (self class guardFor: os); lf].
		s nextPutAll: '    {'; print: (p at: 1); nextPutAll: ', '; print: ((p at: 3) ifTrue: [1] ifFalse: [0]) + ((p at: 4) ifTrue: [2] ifFalse: [0]);
			nextPutAll: ', '; nextPutAll: (CConst value: (p at: 2) type: nil) cString; nextPutAll: ', '; nextPutAll: f cName; nextPutAll: '},'; lf.
		os notNil ifTrue: [s nextPutAll: '#endif'; lf].
		platform ifTrue: [s nextPutAll: '#endif'; lf]].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: 'int vm_primitive_count = sizeof vm_primitive_table / sizeof vm_primitive_table[0];'; lf.
	^s contents
!
isPlatformModule: aTModule
	^aTModule moduleClass packageName = 'VM-Platform'
!
sourcesMakefile
	"Which generated files make which VM: the core, then one platform implementation (headless, or the platform layer); each followed by its files for one OS only (VM_CORE_SOURCES_LINUX: the build adds those of its uname -s)."
	| s lists kind |
	lists := Dictionary new.
	self translatedModules do: [:m |
		kind := (self isPlatformModule: m)
			ifTrue: ['VM_PLATFORM_SOURCES']
			ifFalse: [(m moduleClass inheritsFrom: PlatformInterface) ifTrue: ['VM_HEADLESS_SOURCES'] ifFalse: ['VM_CORE_SOURCES']].
		m moduleClass targetOS notNil ifTrue: [
			kind := kind , '_' , ((self class targetOSes detect: [:spec | (spec at: 1) = m moduleClass targetOS]) at: 3)].
		(lists at: kind ifAbsentPut: [OrderedCollection new]) add: m cFileName , '.c'].
	self primitives notEmpty ifTrue: [(lists at: 'VM_CORE_SOURCES' ifAbsentPut: [OrderedCollection new]) add: 'primitive_entries.c'].
	s := WriteStream on: String new.
	s nextPutAll: '# Generated by VMTranslator. Do not edit.'; lf.
	#('VM_CORE_SOURCES' 'VM_HEADLESS_SOURCES' 'VM_PLATFORM_SOURCES') do: [:var |
		(Array with: var) , (self class targetOSes collect: [:spec | var , '_' , (spec at: 3)]) do: [:name |
			s nextPutAll: name; nextPutAll: ' :='.
			((lists at: name ifAbsent: [#()]) asSortedCollection: [:a :b | a <= b]) do: [:f | s nextPutAll: ' '; nextPutAll: f].
			s lf]].
	^s contents
! !
