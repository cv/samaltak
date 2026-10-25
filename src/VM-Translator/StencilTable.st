Object subclass: #StencilTable
	instanceVariableNames: 'object compiler stencils code entries relocs symbols symbolIndex data dataRelocs sectionBases'
	classVariableNames: ''
	package: 'VM-Translator'!

StencilTable comment: 'I make the copy-and-patch stencil table (C, compiled into the VM) of the object file cc made of the stencils (a MachObjectFile): per stencil its code and its holes, the relocations JitStencilCompiler patches when it copies the code (kind, offset, target, addend); the VM''s functions and data the stencils use (their addresses); the object''s data sections, copied once into the code cache.

Relocations (constants of the compiler class, JitStencilCompiler): RELOC_BRANCH (b, bl: a continuation, _JIT_NEXT ..., or a VM function), RELOC_GOT_PAIR (adrp and ldr of a GOT load, at offset and offset2: a hole _JIT_A ... or the address of a VM symbol; JitStencilCompiler relaxes them to movz, movk, adr, adrp and add as the value allows), RELOC_GOT_PAGE and RELOC_GOT_PAGEOFF (a GOT load that is not one adrp with one ldr), RELOC_PAGE and RELOC_PAGEOFF (adrp and add or a load: an address in the data; offset2 the load''s scale). Targets: TARGET_HOLE, TARGET_CONT, TARGET_SYMBOL (an index into the symbols), TARGET_DATA (the addend is the offset in the data).

	(StencilTable object: aMachObjectFile compiler: JitStencilCompiler stencils: #(''stencil_add'' ...) names: #(''add'' ...)) cSource'!

!StencilTable class methodsFor: 'instance creation'!
object: aMachObjectFile compiler: aClass stencils: cNames names: names
	^self new setObject: aMachObjectFile compiler: aClass stencils: cNames names: names
! !

!StencilTable methodsFor: 'initialization'!
setObject: aMachObjectFile compiler: aClass stencils: cNames names: names
	object := aMachObjectFile.
	compiler := aClass.
	stencils := cNames with: names collect: [:c :n | c -> n].
	code := WriteStream on: (ByteArray new: 4096).
	entries := OrderedCollection new.
	relocs := OrderedCollection new.
	symbols := OrderedCollection new.
	symbolIndex := Dictionary new.
	dataRelocs := OrderedCollection new.
	self readData.
	self readStencils
! !

!StencilTable methodsFor: 'reading'!
constant: aString
	^compiler classPool at: aString asSymbol ifAbsent: [self error: compiler name , ' has no constant ' , aString]
!
isData: aSection
	^aSection segment ~= '__DWARF' and: [(#('__text' '__compact_unwind' '__eh_frame') includes: aSection name) not]
!
readData
	"The data sections, one after the other at their alignment (at most 16: the code cache copy is 16-aligned)."
	| out |
	out := WriteStream on: (ByteArray new: 256).
	sectionBases := Dictionary new.
	object sections do: [:s |
		(self isData: s) ifTrue: [
			s align > 16 ifTrue: [self error: s printString , ' wants an alignment above 16'].
			[out position \\ s align = 0] whileFalse: [out nextPut: 0].
			sectionBases at: s number put: out position.
			out nextPutAll: s bytes]].
	data := out contents.
	object sections do: [:s | (self isData: s) ifTrue: [self readDataRelocationsOf: s]]
!
readDataRelocationsOf: aSection
	"64-bit pointers in the data: to the data or to the VM."
	aSection relocations do: [:r |
		| target id addend v |
		(r type = 0 and: [r length = 3]) ifFalse: [self error: 'unsupported relocation in ' , aSection printString , ': ' , r printString].
		v := aSection bytes uint32At: r address + 1.
		v := v + ((aSection bytes uint32At: r address + 5) bitShift: 32).
		r isExtern
			ifTrue: [
				r symbol isUndefined
					ifTrue: [target := self constant: 'TARGET_SYMBOL'. id := self symbolId: r symbol. addend := v]
					ifFalse: [target := self constant: 'TARGET_DATA'. id := 0. addend := (self dataOffsetOf: r symbol) + v]]
			ifFalse: [
				target := self constant: 'TARGET_DATA'.
				id := 0.
				addend := (sectionBases at: r index ifAbsent: [self error: 'a pointer into ' , (object sectionNumbered: r index) printString]) + v - (object sectionNumbered: r index) address].
		dataRelocs add: (Array with: (sectionBases at: aSection number) + r address with: target with: id with: addend)]
!
dataOffsetOf: aSymbol
	| s |
	s := object sectionNumbered: aSymbol section.
	^(sectionBases at: s number ifAbsent: [self error: aSymbol name , ' is not in the data']) + aSymbol value - s address
!
symbolId: aMachSymbol
	"The index of a VM function or variable the stencils use."
	| name |
	name := aMachSymbol name.
	(name beginsWith: '_') ifFalse: [self error: 'unexpected symbol ' , name].
	^symbolIndex at: name ifAbsent: [
		symbols add: (name copyFrom: 2 to: name size).
		symbolIndex at: name put: symbols size - 1]
!
readStencils
	"Every stencil function's code and relocations; the text holds nothing else."
	| text defined starts |
	text := object section: '__TEXT' named: '__text'.
	text isNil ifTrue: [^self error: 'no __text section'].
	defined := Dictionary new.
	object symbols do: [:s |
		(s isDefined and: [s isExternal and: [s isDebug not and: [s section = text number]]]) ifTrue: [
			(s name beginsWith: '_stencil_') ifFalse: [self error: 'the stencils'' text defines ' , s name].
			defined at: (s name copyFrom: 2 to: s name size) put: s value - text address]].
	defined size = stencils size ifFalse: [self error: 'the object file has ' , defined size printString , ' stencils, not ' , stencils size printString].
	starts := (defined values asSortedCollection: [:a :b | a <= b]) asArray.
	(starts isEmpty not and: [starts first = 0]) ifFalse: [self error: 'code before the first stencil'].
	stencils do: [:assoc |
		| start end |
		start := defined at: assoc key ifAbsent: [self error: 'no stencil ' , assoc key].
		end := starts detect: [:a | a > start] ifNone: [text size].
		self readStencil: assoc value from: start to: end in: text]
!
readStencil: aName from: start to: end in: text
	| first raw pending |
	first := relocs size.
	entries add: (Array with: code position with: end - start with: first with: 0 with: aName).
	start to: end - 1 do: [:i | code nextPut: (text bytes at: i + 1)].
	raw := OrderedCollection new.
	pending := 0.
	(text relocations asSortedCollection: [:a :b | a address <= b address]) do: [:r |
		(r address >= start and: [r address < end]) ifTrue: [
			r type = 10
				ifTrue: [pending := r addend]
				ifFalse: [
					raw add: (Array with: r with: r address - start with: pending).
					pending := 0]]].
	self convert: raw text: text start: start.
	(entries last) at: 4 put: relocs size - first
!
convert: raw text: text start: start
	"Pair adrp and ldr of each GOT load where they are one of each for a symbol and register."
	| gotPages gotOffs done |
	gotPages := raw select: [:e | (e at: 1) type = 5].
	gotOffs := raw select: [:e | (e at: 1) type = 6].
	done := IdentitySet new.
	gotPages do: [:p |
		| rd mine adrps |
		rd := (text wordAt: (p at: 1) address) bitAnd: 31.
		adrps := gotPages select: [:q | (q at: 1) symbol == (p at: 1) symbol and: [((text wordAt: (q at: 1) address) bitAnd: 31) = rd]].
		mine := gotOffs select: [:o | (o at: 1) symbol == (p at: 1) symbol and: [(((text wordAt: (o at: 1) address) bitShift: -5) bitAnd: 31) = rd]].
		(adrps size = 1 and: [mine size = 1 and: [((text wordAt: (mine first at: 1) address) bitAnd: 16rFFC00000) = 16rF9400000]]) ifTrue: [
			done add: p; add: mine first.
			self add: 'RELOC_GOT_PAIR' at: (p at: 2) and: (mine first at: 2) for: (p at: 1) symbol addend: (p at: 3)]].
	(raw asSortedCollection: [:a :b | (a at: 2) <= (b at: 2)]) do: [:e |
		(done includes: e) ifFalse: [self convert: e text: text]].
	self sortLast
!
convert: e text: text
	| r type |
	r := e at: 1.
	type := r type.
	r isExtern ifFalse: [^self error: 'a section-relative ' , r typeName , ' in the stencils'].
	type = 2 ifTrue: [^self add: 'RELOC_BRANCH' at: (e at: 2) and: 0 for: r symbol addend: (e at: 3)].
	type = 5 ifTrue: [^self add: 'RELOC_GOT_PAGE' at: (e at: 2) and: 0 for: r symbol addend: (e at: 3)].
	type = 6 ifTrue: [^self add: 'RELOC_GOT_PAGEOFF' at: (e at: 2) and: 0 for: r symbol addend: (e at: 3)].
	type = 3 ifTrue: [^self add: 'RELOC_PAGE' at: (e at: 2) and: 0 for: r symbol addend: (e at: 3)].
	type = 4 ifTrue: [^self add: 'RELOC_PAGEOFF' at: (e at: 2) and: (self scaleOf: (text wordAt: r address)) for: r symbol addend: (e at: 3)].
	self error: 'unsupported relocation in the stencils: ' , r printString
!
scaleOf: anInstruction
	"log2 of the access size of the instruction a PAGEOFF12 relocates: 0 for add, the size of a load or store."
	| size |
	(anInstruction bitAnd: 16r7F800000) = 16r11000000 ifTrue: [^0].
	(anInstruction bitAnd: 16r3B000000) = 16r39000000 ifFalse: [^self error: 'PAGEOFF12 on an unexpected instruction'].
	size := anInstruction bitShift: -30.
	(((anInstruction bitShift: -26) bitAnd: 1) = 1 and: [size = 0 and: [((anInstruction bitShift: -23) bitAnd: 1) = 1]]) ifTrue: [^4].
	^size
!
add: aKind at: offset and: offset2 for: aSymbol addend: addend
	"One relocation of the current stencil."
	| target id |
	(aSymbol name beginsWith: '__JIT_')
		ifTrue: [
			| key |
			key := aSymbol name copyFrom: 7 to: aSymbol name size.
			(compiler classPool includesKey: ('HOLE_' , key) asSymbol)
				ifTrue: [target := self constant: 'TARGET_HOLE'. id := self constant: 'HOLE_' , key]
				ifFalse: [target := self constant: 'TARGET_CONT'. id := self constant: 'CONT_' , key]]
		ifFalse: [
			aSymbol isUndefined
				ifTrue: [target := self constant: 'TARGET_SYMBOL'. id := self symbolId: aSymbol]
				ifFalse: [
					target := self constant: 'TARGET_DATA'.
					id := 0.
					^relocs add: (Array with: offset with: ((self constant: aKind) bitOr: (target bitShift: 8)) with: offset2 with: (self dataOffsetOf: aSymbol) + addend)]].
	relocs add: (Array with: offset with: (((self constant: aKind) bitOr: (target bitShift: 8)) bitOr: (id bitShift: 16)) with: offset2 with: addend)
!
sortLast
	"The current stencil's relocations by offset."
	| first mine |
	first := (entries last) at: 3.
	mine := (relocs copyFrom: first + 1 to: relocs size) asSortedCollection: [:a :b | (a at: 1) <= (b at: 1)].
	relocs removeLast: relocs size - first.
	relocs addAll: mine
! !

!StencilTable methodsFor: 'printing'!
cSource
	"The table as C (the stencil table file of vm/gen)."
	| s |
	s := WriteStream on: String new.
	s nextPutAll: '#include "samaltak.h"'; lf; lf.
	s nextPutAll: 'const int32_t jit_stencil_counts[] = {'; print: entries size; nextPutAll: ', '; print: relocs size; nextPutAll: ', '; print: symbols size;
		nextPutAll: ', '; print: data size; nextPutAll: ', '; print: dataRelocs size; nextPutAll: '};'; lf; lf.
	s nextPutAll: '/* the stencils'' code */'; lf.
	self printBytes: code contents named: 'jit_stencil_code' on: s.
	s nextPutAll: '/* per stencil: offset, size, first relocation, relocations */'; lf.
	s nextPutAll: 'const uint32_t jit_stencils[] = {'; lf.
	entries do: [:e |
		s nextPutAll: '    '; print: (e at: 1); nextPutAll: ', '; print: (e at: 2); nextPutAll: ', '; print: (e at: 3); nextPutAll: ', '; print: (e at: 4);
			nextPutAll: ', /* '; nextPutAll: (e at: 5); nextPutAll: ' */'; lf].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: '/* per relocation: offset, kind | target << 8 | id << 16, offset2, addend */'; lf.
	s nextPutAll: 'const uint32_t jit_stencil_relocs[] = {'; lf.
	relocs do: [:r | s nextPutAll: '    '. r do: [:v | s print: (v bitAnd: 16rFFFFFFFF)] separatedBy: [s nextPutAll: ', ']. s nextPut: $,; lf].
	relocs isEmpty ifTrue: [s nextPutAll: '    0'; lf].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: 'const char *const jit_stencil_names[] = {'; lf.
	entries do: [:e | s nextPutAll: '    "'; nextPutAll: (e at: 5); nextPutAll: '",'; lf].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: '/* the VM''s functions and variables the stencils use */'; lf.
	s nextPutAll: 'const uint64_t jit_stencil_symbols[] = {'; lf.
	symbols do: [:n | s nextPutAll: '    (uint64_t)(uintptr_t)&'; nextPutAll: n; nextPut: $,; lf].
	symbols isEmpty ifTrue: [s nextPutAll: '    0'; lf].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: 'const char *const jit_stencil_symbol_names[] = {'; lf.
	symbols do: [:n | s nextPutAll: '    "'; nextPutAll: n; nextPutAll: '",'; lf].
	symbols isEmpty ifTrue: [s nextPutAll: '    ""'; lf].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: '/* the data sections */'; lf.
	self printBytes: data named: 'jit_stencil_data' on: s.
	s nextPutAll: '/* per pointer in the data: offset, target << 8 | id << 16, addend */'; lf.
	s nextPutAll: 'const uint32_t jit_stencil_data_relocs[] = {'; lf.
	dataRelocs do: [:r |
		s nextPutAll: '    '; print: (r at: 1); nextPutAll: ', '; print: ((r at: 2) bitShift: 8) + ((r at: 3) bitShift: 16); nextPutAll: ', '; print: ((r at: 4) bitAnd: 16rFFFFFFFF); nextPut: $,; lf].
	dataRelocs isEmpty ifTrue: [s nextPutAll: '    0'; lf].
	s nextPutAll: '};'; lf.
	^s contents
!
printBytes: aByteArray named: aString on: s
	s nextPutAll: 'const uint8_t '; nextPutAll: aString; nextPutAll: '[] = {'.
	aByteArray doWithIndex: [:b :i |
		i \\ 16 = 1 ifTrue: [s lf; nextPutAll: '   '].
		s nextPutAll: ' 0x'; nextPutAll: ((b printStringBase: 16) asLowercase padLeftTo: 2 with: $0); nextPut: $,].
	aByteArray isEmpty ifTrue: [s lf; nextPutAll: '    0'].
	s lf; nextPutAll: '};'; lf; lf
! !
