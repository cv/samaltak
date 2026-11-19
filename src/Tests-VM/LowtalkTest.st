TestCase subclass: #LowtalkTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

LowtalkTest comment: 'Lowtalk programs run the same as Smalltalk (VMSimulation) and as C (VMTranslator, then cc).'!

!LowtalkTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!LowtalkTest methodsFor: 'helpers'!
compileAndRun: moduleClasses header: aString arguments: anArray
	"Translate moduleClasses into my scratch directory, compile with cc and run; answer the finished OSProcess."
	| dir build |
	dir := self scratchDirectory.
	(VMTranslator modules: moduleClasses header: aString) writeTo: dir.
	build := OSProcess run: 'cc -std=gnu11 -O1 -Wall -Wextra -Wno-unused-parameter -Wno-unused-label -Werror -o program *.c 2>&1' in: dir.
	self assert: build succeeded description: [build output].
	^OSProcess run: (OSProcess commandFor: (Array with: dir , '/program') , anArray) in: dir
!
sampleOutput
	^'sum=55
counter=5
table=49
squares=140
chain=66
distance=3
fib=6765
clamp=255
case=19
overflow=-1
nooverflow=42
wrap=-5
untag=-3
twice=42
hash=167703939
loop=9
same=2
counted=6
'
! !

!LowtalkTest methodsFor: 'tests'!
testSampleInSimulation
	| sim |
	sim := VMSimulation modules: {LowtalkSample}.
	self assert: (sim runMain: LowtalkSample arguments: #('sample')) equals: 0.
	self assert: sim stdoutContents equals: self sampleOutput , 'argc=1 sample
'
!
testAnEditedClassInitializeIsTranslated
	"The constants come from the class-side initialize: a translation runs it again, so an edited one counts without running it by hand."
	| original dir |
	original := LowtalkSample class compiledMethodAt: #initialize.
	dir := self scratchDirectory.
	[LowtalkSample class compile: 'initialize TABLE_SIZE := 9' classified: 'declaring'.
	 (VMTranslator modules: {LowtalkSample} header: 'sample') writeTo: dir.
	 self assert: ((File readText: dir , '/sample.h') includesSubstring: '#define TABLE_SIZE 9')]
		ensure: [
			LowtalkSample class addSelector: #initialize withMethod: original.
			LowtalkSample initialize].
	self assert: (LowtalkSample classPool at: #TABLE_SIZE) equals: 8
!
testInlineArgumentsAndSelfComparisons
	"An argument an inline method never reads gets no local (its effects stay); v = v of an integer or a pointer is true."
	| c |
	c := ((VMTranslator modules: {LowtalkSample} header: 'sample') translate detect: [:each | each key = 'lowtalk_sample.c']) value.
	self deny: (c includesSubstring: 'unused').
	self assert: (c includesSubstring: 'counter = counter + 1;
    report("same", 2);')
!
testSignaturesAreInferred
	"A parameter is the join of its call sites (a literal adapts), a function without ^expression is void, <var:type:> and <returns:> override the join."
	| c |
	[LowtalkSample compile: 'widened: x <function> ^x' classified: 'inference'.
	 LowtalkSample compile: 'given: x <function> <var: #x type: ''int16_t''> <returns: ''int32_t''> ^x' classified: 'inference'.
	 LowtalkSample compile: 'caller <function> self widened: 1. self widened: counter. self given: 2' classified: 'inference'.
	 c := ((VMTranslator modules: {LowtalkSample} header: 'sample') translate detect: [:each | each key = 'lowtalk_sample.c']) value.
	 self assert: (c includesSubstring: 'static int64_t widened(int64_t x);').
	 self assert: (c includesSubstring: 'static int32_t given(int16_t x);').
	 self assert: (c includesSubstring: 'static void caller(void);')]
		ensure: [#(#widened: #given: #caller) do: [:sel | LowtalkSample removeSelector: sel]]
!
testAParameterNothingTypesIsAnError
	[LowtalkSample compile: 'lonely: x <function> ^x' classified: 'inference'.
	 self should: [(VMTranslator modules: {LowtalkSample} header: 'sample') translate] raise: TranslationError]
		ensure: [LowtalkSample removeSelector: #lonely:]
!
testAnOSWithoutTheLibraryGetsTheModule
	"Translated for #uefi alone, the library's calls are sends to the module that implements it, and its header is not included."
	| files h c |
	files := (VMTranslator modules: {LowtalkLibraryUser} header: 'os') translate.
	h := (files detect: [:each | each key = 'os.h']) value.
	c := (files detect: [:each | each key = 'lowtalk_library_user.c']) value.
	self assert: (h includesSubstring: '#include <sample_library.h>').
	self assert: (c includesSubstring: 'sample_twice(21)').
	files := (VMTranslator modules: {LowtalkLibraryUser. LowtalkLibraryOnUefi} header: 'os') setOS: #uefi; translate.
	h := (files detect: [:each | each key = 'os.h']) value.
	c := (files detect: [:each | each key = 'lowtalk_library_user.c']) value.
	self deny: (h includesSubstring: 'sample_library.h').
	self assert: (h includesSubstring: 'int twice(int x);').
	self assert: (c includesSubstring: 'return twice(21);')
!
testCallingConventions
	"<abi:> gives a function a calling convention; so does passing it where a function type has one."
	| t c |
	t := CTypeRegistry default parse: 'uint64_t (__attribute__((ms_abi)) *)(uint64_t)'.
	self assert: t target abi equals: 'ms_abi'.
	self assert: t name equals: 'uint64_t (__attribute__((ms_abi)) *)(uint64_t)'.
	[LowtalkSample compile: 'entry: x <export> <abi: ''ms_abi''> <var: #x type: ''int64_t''> ^x' classified: 'abi'.
	 LowtalkSample compile: 'callback: x <function> ^x + 1' classified: 'abi'.
	 LowtalkSample compile: 'calls: fp <function> <var: #fp type: ''int64_t (__attribute__((ms_abi)) *)(int64_t)''> ^fp call: 41' classified: 'abi'.
	 LowtalkSample compile: 'passes <export> ^self calls: (self functionPointer: #callback:)' classified: 'abi'.
	 c := ((VMTranslator modules: {LowtalkSample} header: 'sample') translate detect: [:each | each key = 'lowtalk_sample.c']) value.
	 self assert: (c includesSubstring: '__attribute__((ms_abi)) int64_t entry(int64_t x)').
	 self assert: (c includesSubstring: 'static __attribute__((ms_abi)) int64_t callback(int64_t x);').
	 self assert: (c includesSubstring: 'static int64_t calls(int64_t (__attribute__((ms_abi)) *fp)(int64_t));')]
		ensure: [#(#entry: #callback: #calls: #passes) do: [:sel | LowtalkSample removeSelector: sel]]
!
testVarargBits
	"What a variadic function reads: a double's bits, an integer widened."
	| c |
	self assert: (LowtalkSample new varargBits: 1.5) equals: 1.5 asIEEEBits.
	self assert: (LowtalkSample new varargBits: -1) equals: 16rFFFFFFFFFFFFFFFF.
	[LowtalkSample compile: 'bits: d and: i <export> <var: #d type: ''double''> <var: #i type: ''int32_t''> ^(self varargBits: d) + (self varargBits: i)' classified: 'varargs'.
	 c := ((VMTranslator modules: {LowtalkSample} header: 'sample') translate detect: [:each | each key = 'lowtalk_sample.c']) value.
	 self assert: (c includesSubstring: 'lt_bits_of_double(d) + (uint64_t)i')]
		ensure: [LowtalkSample removeSelector: #bits:and:]
!
testNoModuleMethodHasACPrototype
	"C prototypes are CLibrary's business: the foreign APIs. A VM function is plain Smalltalk."
	VMModule allSubclasses do: [:c |
		c selectors do: [:sel |
			self deny: (((c compiledMethodAt: sel) pragmas ifNil: [#()]) anySatisfy: [:p | p selector == #c:])]]
!
testSampleInC
	| run |
	run := self compileAndRun: {LowtalkSample} header: 'sample' arguments: #().
	self assert: run exitCode equals: 0.
	self assert: (run output copyFrom: 1 to: self sampleOutput size) equals: self sampleOutput.
	self assert: ((run output allButFirst: self sampleOutput size) beginsWith: 'argc=1 ')
! !
