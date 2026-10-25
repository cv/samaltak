TestCase subclass: #StencilTableTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

StencilTableTest comment: 'MachObjectFile and StencilTable on an object file cc makes of a small stencil with every kind of relocation the stencils may have: a continuation and a VM function (BRANCH26), a hole and a VM variable (GOT loads, paired by the compiler''s hints), a constant in a literal section and an address with an offset (PAGE21, PAGEOFF12, ADDEND), a pointer in the data (UNSIGNED). JitStencilRuntimeTest runs the real ones.'!

!StencilTableTest methodsFor: 'helpers'!
source
	^'#include <stdint.h>
typedef uint64_t oop;
extern char _JIT_A[];
extern void __attribute__((preserve_none)) _JIT_NEXT(oop *fp);
extern uint64_t vm_function(double d);
extern uint64_t vm_variable;
static uint64_t local[8] = {1, 2, 3, 4, 5, 6, 7, 8};
uint64_t *pointers[] = {&local[2]};
__attribute__((preserve_none)) void stencil_sample(oop *fp)
{
    uint64_t *p = (uint64_t *)fp[2];
    fp[0] = vm_function((double)fp[1] * 2.718281828) + (uint64_t)(uintptr_t)_JIT_A + vm_variable + *pointers[0];
    p[0] = (uint64_t)(uintptr_t)&local[5];
    __attribute__((musttail)) return _JIT_NEXT(fp);
}
'
!
object
	| dir build |
	dir := self scratchDirectory.
	File writeText: self source to: dir , '/sample.c'.
	build := OSProcess run: 'cc ' , VMTranslator new stencilCFlags , ' -c -o sample.o sample.c 2>&1' in: dir.
	self assert: build succeeded description: [build output].
	^MachObjectFile fromBytes: (File readBytes: dir , '/sample.o')
!
constant: aString
	^JitStencilCompiler classPool at: aString asSymbol
! !

!StencilTableTest methodsFor: 'tests'!
testObjectFile
	| object text types |
	object := self object.
	text := object section: '__TEXT' named: '__text'.
	self assert: text notNil.
	self assert: (object symbols anySatisfy: [:s | s name = '_stencil_sample' and: [s isDefined and: [s isExternal]]]).
	self assert: (object symbols anySatisfy: [:s | s name = '__JIT_A' and: [s isUndefined]]).
	types := (text relocations collect: [:r | r typeName]) asSet.
	#('BRANCH26' 'PAGE21' 'PAGEOFF12' 'GOT_LOAD_PAGE21' 'GOT_LOAD_PAGEOFF12' 'ADDEND') do: [:t | self assert: (types includes: t) description: t].
	self assert: (object sections anySatisfy: [:s | s relocations anySatisfy: [:r | r typeName = 'UNSIGNED']]).
	self assert: object gotLoadPairs notEmpty
!
testTable
	| object table c |
	object := self object.
	table := StencilTable object: object compiler: JitStencilCompiler stencils: #('stencil_sample') names: #('sample').
	c := table cSource.
	self assert: (c includesSubstring: 'const int32_t jit_stencil_counts[] = {1, ').
	self assert: (c includesSubstring: '(uint64_t)(uintptr_t)&vm_function').
	self assert: (c includesSubstring: '(uint64_t)(uintptr_t)&vm_variable').
	self assert: (c includesSubstring: '"sample"').
	#('RELOC_BRANCH' 'RELOC_GOT_PAIR' 'RELOC_PAGE' 'RELOC_PAGEOFF') do: [:k |
		self assert: (table relocations anySatisfy: [:r | ((r at: 2) bitAnd: 255) = (self constant: k)]) description: k].
	self assert: (table relocations anySatisfy: [:r | ((r at: 2) >> 8 bitAnd: 255) = (self constant: 'TARGET_HOLE') and: [(r at: 2) >> 16 = (self constant: 'HOLE_A')]]).
	self assert: (table relocations anySatisfy: [:r | ((r at: 2) >> 8 bitAnd: 255) = (self constant: 'TARGET_CONT') and: [(r at: 2) >> 16 = (self constant: 'CONT_NEXT')]]).
	self assert: table dataRelocations notEmpty
! !
