CLibrary subclass: #JitStencilTable
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitStencilTable comment: 'The stencils of JitStencils as the translator made them (vm/gen/jit_stencils_table.c, jit_stencils_threaded.c, StencilTable): for copy-and-patch each stencil''s code and relocations (four words each: offset, kind | target << 8 | id << 16, second offset, addend), the addresses and names of the VM''s functions and variables they use, the object file''s data sections and their pointers; for call threading each stencil''s function, the holes it takes and the continuations it answers. Not simulated.'!

!JitStencilTable class methodsFor: 'declaring'!
headers
	^#('"jit_stencils.h"')
! !

!JitStencilTable methodsFor: 'tables'!
counts
	"stencils, relocations, symbols, data bytes, data relocations; simulated: none"
	<cVariable: 'const int32_t *jit_stencil_counts'>
	^self memory pointerTo: (CTypeRegistry default at: 'int32_t') at: (self memory allocate: 20)
!
code
	<cVariable: 'const uint8_t *jit_stencil_code'>
	^self error: 'the stencil table is not simulated'
!
stencils
	"per stencil: offset in code, size, first relocation, relocations, keep"
	<cVariable: 'const uint32_t *jit_stencils'>
	^self error: 'the stencil table is not simulated'
!
relocations
	<cVariable: 'const uint32_t *jit_stencil_relocs'>
	^self error: 'the stencil table is not simulated'
!
names
	<cVariable: 'const char **jit_stencil_names'>
	^self error: 'the stencil table is not simulated'
!
symbols
	<cVariable: 'const uint64_t *jit_stencil_symbols'>
	^self error: 'the stencil table is not simulated'
!
symbolNames
	<cVariable: 'const char **jit_stencil_symbol_names'>
	^self error: 'the stencil table is not simulated'
!
data
	<cVariable: 'const uint8_t *jit_stencil_data'>
	^self error: 'the stencil table is not simulated'
!
dataRelocations
	"per pointer in the data: offset, target << 8 | id << 16, addend"
	<cVariable: 'const uint32_t *jit_stencil_data_relocs'>
	^self error: 'the stencil table is not simulated'
!
threadedFunctions
	<cVariable: 'const uint64_t *jit_threaded_fns'>
	^self error: 'the stencil table is not simulated'
!
threadedHoles
	<cVariable: 'const uint32_t *jit_threaded_holes'>
	^self error: 'the stencil table is not simulated'
!
threadedContinuations
	<cVariable: 'const uint32_t *jit_threaded_conts'>
	^self error: 'the stencil table is not simulated'
! !
