JitCompiler subclass: #JitStencilCompiler
	instanceVariableNames: 'table libc threaded opened codeStart pcLabels deferred deferredPcs deferredCount slowStencils slowLabels slowNext slowJumps slowValues slowCount resumePcs resumeDepths resumeCount values copySlots slotValues slotCount patchSites patchSlots patchKinds patchCount exitSyncLabel exitPlainLabel returnLabel failed gotBase symbolTargets dataBase exitSyncGlue returnGlue'
	classVariableNames: 'CONT_EXIT CONT_EXIT_SYNC CONT_JUMP CONT_NEXT CONT_RETURN CONT_SLOW HOLE_A HOLE_B HOLE_C HOLE_COUNT HOLE_INFO HOLE_PC HOLE_SITE HOLE_VALUE RELOC_BRANCH RELOC_GOT_PAGE RELOC_GOT_PAGEOFF RELOC_GOT_PAIR RELOC_PAGE RELOC_PAGEOFF STC_MAX_PATCHES STC_MAX_SLOTS STC_MAX_SLOW STC_MAX_SLOW_VALUES STC_MAX_SYMBOLS ST_ADD ST_ADD_OPERANDS ST_ADD_OPERANDS_INTO ST_BASIC_AT ST_BASIC_AT_PUT ST_BASIC_SIZE ST_BIT_AND ST_BIT_OR ST_BRANCH ST_BRANCH_BACK ST_BRANCH_IF ST_CLASS_OF ST_CLOSURE ST_COMPARE ST_COMPARE_JUMP_FALSE ST_COMPARE_JUMP_TRUE ST_COMPARE_OPERANDS ST_COMPARE_OPERANDS_JUMP_FALSE ST_COMPARE_OPERANDS_JUMP_TRUE ST_COUNT ST_DIVIDE ST_DUP ST_ENTRY ST_FLOAT_OPERATION ST_FLOOR_DIVIDE ST_IDENTICAL ST_IDENTICAL_JUMP_FALSE ST_IDENTICAL_JUMP_TRUE ST_MAKE_ARRAY ST_MODULO ST_MULTIPLY ST_OUTER_TEMP ST_POINT_COORDINATE ST_POP ST_POP_STORE_LITERAL_VARIABLE_X ST_POP_STORE_TEMP ST_POP_STORE_TEMP_X ST_PUSH_CONSTANT ST_PUSH_FALSE ST_PUSH_INST_VAR ST_PUSH_INST_VAR_X ST_PUSH_LITERAL ST_PUSH_LITERAL_VARIABLE ST_PUSH_LITERAL_VARIABLE_X ST_PUSH_LITERAL_X ST_PUSH_NIL ST_PUSH_ONE ST_PUSH_SELF ST_PUSH_TEMP ST_PUSH_TEMP_X ST_PUSH_TRUE ST_PUSH_ZERO ST_RETURN_SELF ST_RETURN_TOP ST_SEND ST_SPECIAL_SEND ST_STORE_INST_VAR_X ST_STORE_LITERAL_VARIABLE_X ST_STORE_TEMP_X ST_SUBTRACT ST_SUBTRACT_OPERANDS ST_SUBTRACT_OPERANDS_INTO ST_TO_INTERPRETER TARGET_CONT TARGET_DATA TARGET_HOLE TARGET_SYMBOL'
	package: 'VM-Jit'!

JitStencilCompiler comment: 'The copy-and-patch compiler (--jit stencil) and the call-threading compiler (--jit threaded): the same choice of stencils (JitStencils) for every instruction, emitted two ways. Copy-and-patch copies each stencil''s code (JitStencilTable, what cc made of it when the VM was translated) and patches its holes: operands relaxed from GOT loads to movz, movk, adr or adrp and add (or loaded from a literal slot after the method), continuations to the next instruction (a trailing branch to it elided, a trailing return replaced by the epilogue), the jump target or the out-of-line code, calls of the VM directly or through veneers. Call threading emits a bl of each stencil''s function in the VM, its holes in x0-x7, then branches on the continuation it answers. Dispatch is gone in both; only copy-and-patch also has the code inline.

The conventions of both (docs/jit.md): x20-x22 as for every compiler, x23 the top of the operand stack, x24 the frame (x19 is the frame where the shared conventions need it: entries, calls of compiled code, returns, exits; a copied stencil may use x19 itself). A method or block starts with the prologue, sets x23 and x24 and runs the entry stencil (an interrupt check); the interpreter resumes a frame at out-of-line code that sets them and jumps in. Superinstructions are their pushes and their special selector; a comparison followed by a conditional jump is one stencil (the jump''s own code out of line, for the slow path and resumption); slow paths (Floats, sends) are stencils out of line, after the method. No values stay in registers between instructions.'!

!JitStencilCompiler class methodsFor: 'declaring'!
declarations
	^#((table JitStencilTable) (libc LibC) (threaded bool) (opened bool) (codeStart uint64_t)
		(pcLabels 'int32_t[ANA_MAX]') (deferred 'uint8_t[ANA_MAX]') (deferredPcs 'int32_t[STC_MAX_SLOW]') (deferredCount int32_t)
		(slowStencils 'int32_t[STC_MAX_SLOW]') (slowLabels 'int32_t[STC_MAX_SLOW]') (slowNext 'int32_t[STC_MAX_SLOW]') (slowJumps 'int32_t[STC_MAX_SLOW]')
		(slowValues 'uint64_t[STC_MAX_SLOW_VALUES]') (slowCount int32_t)
		(resumePcs 'int32_t[STC_MAX_SLOW]') (resumeDepths 'int32_t[STC_MAX_SLOW]') (resumeCount int32_t)
		(values 'uint64_t[8]') (copySlots 'int32_t[8]')
		(slotValues 'uint64_t[STC_MAX_SLOTS]') (slotCount int32_t)
		(patchSites 'uint64_t[STC_MAX_PATCHES]') (patchSlots 'int32_t[STC_MAX_PATCHES]') (patchKinds 'uint8_t[STC_MAX_PATCHES]') (patchCount int32_t)
		(exitSyncLabel int32_t) (exitPlainLabel int32_t) (returnLabel int32_t) (failed bool)
		(gotBase uint64_t) (symbolTargets 'uint64_t[STC_MAX_SYMBOLS]') (dataBase uint64_t)
		(exitSyncGlue uint64_t) (returnGlue uint64_t))
!
initialize
	"Holes and continuations (JitStencils' hole: and continuations; HOLE_COUNT at most 8; a threaded stencil's SITE is its return address), the stencil table's relocations, the stencils' indices (initializeStencils)."
	HOLE_PC := 0.
	HOLE_A := 1.
	HOLE_B := 2.
	HOLE_INFO := 3.
	HOLE_VALUE := 4.
	HOLE_C := 5.
	HOLE_SITE := 6.
	HOLE_COUNT := 7.
	CONT_NEXT := 0.
	CONT_JUMP := 1.
	CONT_SLOW := 2.
	CONT_EXIT_SYNC := 3.
	CONT_EXIT := 4.
	CONT_RETURN := 5.
	RELOC_BRANCH := 1.
	RELOC_GOT_PAIR := 2.
	RELOC_GOT_PAGE := 3.
	RELOC_GOT_PAGEOFF := 4.
	RELOC_PAGE := 5.
	RELOC_PAGEOFF := 6.
	TARGET_HOLE := 1.
	TARGET_CONT := 2.
	TARGET_SYMBOL := 3.
	TARGET_DATA := 4.
	STC_MAX_SLOW := 16384.
	STC_MAX_SLOW_VALUES := STC_MAX_SLOW * 8.
	STC_MAX_SLOTS := 4096.
	STC_MAX_PATCHES := 8192.
	STC_MAX_SYMBOLS := 256.
	self initializeStencils
!
initializeStencils
	"ST_NAME: the table index of JitStencils>>name (of its first case); ST_COUNT. JitStencils, loaded after me, runs this again."
	| s i |
	s := Smalltalk at: #JitStencils ifAbsent: [^self].
	i := 0.
	s stencilSelectors do: [:sel |
		| cases |
		self classVarNamed: 'ST_' , (LowtalkNames snake: sel) asUppercase put: i.
		cases := s casesOf: sel.
		i := i + (cases last - cases first) + 1].
	ST_COUNT := i
! !

!JitStencilCompiler methodsFor: 'opening'!
open
	"What all stencil code shares, generated into the code cache when it is opened (it survives flushes): a GOT and veneers for the VM's functions and variables the stencils use, the stencils' data, the exit and return glue. Answer whether it fit. Without the stencils (simulated) nothing is compiled."
	<c: 'bool jit_stencils_open(void)'>
	| start ns nd a off |
	opened := false.
	(table counts at: 0) = ST_COUNT ifFalse: [^true].
	ns := table counts at: 2.
	ns > STC_MAX_SYMBOLS ifTrue: [^false].
	start := cache top.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: false.
	(asm pc bitAnd: 7) ~= 0 ifTrue: [asm nop].
	gotBase := asm pc.
	0 to: ns - 1 do: [:i | asm emit64: (table symbols at: i)].
	0 to: ns - 1 do: [:i |
		symbolTargets at: i put: ((self reaches: (table symbols at: i)) ifTrue: [table symbols at: i] ifFalse: [asm pc]).
		asm ldr: X16 label: (asm labelAt: gotBase + (8 * i)).
		asm br: X16].
	[(asm pc bitAnd: 15) ~= 0] whileTrue: [asm nop].
	nd := (table counts at: 3) asUInt64.
	dataBase := asm skip: ((nd + 3) bitClear: 3).
	dataBase ~= 0 ifTrue: [
		libc memcpy: (self cCoerce: dataBase to: 'void *') from: table data size: nd.
		0 to: (table counts at: 4) - 1 do: [:i |
			off := table dataRelocations at: 3 * i.
			a := self target: (((table dataRelocations at: 3 * i + 1) >> 8) bitAnd: 255) id: (table dataRelocations at: 3 * i + 1) >> 16 addend: (table dataRelocations at: 3 * i + 2) asInt32.
			self uint64At: dataBase + off put: a]].
	exitSyncGlue := asm pc.
	asm mov: X19 with: X24.
	asm b: (asm labelAt: stubs exitSyncAddress).
	returnGlue := asm pc.
	self emitReturnFrom: X24.
	asm finish = ASM_OK ifFalse: [
		cache endWriting.
		^false].
	cache allocate: asm codeSize.
	cache endWritingFrom: start size: asm codeSize.
	opened := true.
	^true
!
reaches: anAddress
	"A bl anywhere in the code cache reaches anAddress."
	^((anAddress - cache start) asInt64 between: -16r7FFFFFF and: 16r7FFFFFF) and: [(anAddress - cache limit) asInt64 between: -16r7FFFFFF and: 16r7FFFFFF]
!
target: aTarget id: id addend: addend
	"The address a relocation of the data means."
	aTarget = TARGET_SYMBOL ifTrue: [^(table symbols at: id) + addend].
	^dataBase + addend
!
emitReturnFrom: aRegister
	asm comment: 'return: x19 := the caller''s frame, pop x29/x30'.
	asm sub: X19 with: aRegister imm: self frameBytes.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret
! !

!JitStencilCompiler methodsFor: 'compiling'!
compile: m threaded: aBoolean
	"Emit m's code at the assembler's pc (BytecodeAnalysis has analyzed it): copies of the stencils, or calls of the threaded ones. Answer whether every reachable instruction got its code."
	<c: 'bool jit_stencil_compile(oop m, bool threaded)'>
	| n pc |
	opened ifFalse: [^false].
	threaded := aBoolean.
	failed := false.
	codeStart := asm pc.
	n := analysis size.
	0 to: n - 1 do: [:i |
		pcLabels at: i put: -1.
		deferred at: i put: 0].
	slowCount := 0.
	deferredCount := 0.
	resumeCount := 0.
	slotCount := 0.
	patchCount := 0.
	exitSyncLabel := asm newLabel.
	exitPlainLabel := asm newLabel.
	returnLabel := asm newLabel.
	pc := 0.
	[pc < n] whileTrue: [
		(analysis isStart: pc)
			ifTrue: [
				(deferred at: pc) = 0 ifTrue: [(self emitAt: pc asInt32) ifFalse: [^false]].
				pc := pc + (analysis lengthAt: pc)]
			ifFalse: [pc := pc + 1]].
	0 to: deferredCount - 1 do: [:i |
		pc := deferredPcs at: i.
		(self emitAt: pc asInt32) ifFalse: [^false].
		asm b: (self labelFor: pc + (analysis lengthAt: pc))].
	0 to: slowCount - 1 do: [:i | self emitSlowPath: i].
	0 to: resumeCount - 1 do: [:i | self emitResumption: i].
	threaded ifTrue: [
		asm bind: exitSyncLabel.
		asm comment: 'leave to the interpreter at the stored pc'.
		asm b: (asm labelAt: exitSyncGlue).
		asm bind: exitPlainLabel.
		asm comment: 'leave to the interpreter (the runtime made the frames canonical)'.
		asm b: (asm labelAt: stubs exitPlainAddress).
		asm bind: returnLabel.
		self emitReturnFrom: X24].
	self emitSlots.
	^failed not
!
labelFor: pc
	(pcLabels at: pc) < 0 ifTrue: [pcLabels at: pc put: asm newLabel].
	^pcLabels at: pc
!
defer: pc
	"The previous instruction consumed the one at pc: its own code goes out of line (slow paths and the interpreter continue there)."
	deferredCount >= STC_MAX_SLOW ifTrue: [^false].
	self labelFor: pc.
	self labelFor: pc + (analysis lengthAt: pc).
	deferred at: pc put: 1.
	deferredPcs at: deferredCount put: pc.
	deferredCount := deferredCount + 1.
	^true
!
emitAt: pc
	"The code of the instruction at pc."
	<c: 'bool stc_emit_at(int32_t pc)'>
	| op d |
	op := analysis byteAt: pc.
	d := analysis depthAt: pc.
	0 to: HOLE_COUNT - 1 do: [:i | values at: i put: 0].
	values at: HOLE_PC put: pc asUInt64.
	(pc = 0 or: [analysis isBlockStart: pc])
		ifTrue: [(self emitEntry: pc depth: d) ifFalse: [^false]]
		ifFalse: [
			((analysis isTarget: pc) or: [analysis isResume: pc]) ifTrue: [self labelFor: pc].
			(pcLabels at: pc) >= 0 ifTrue: [asm bind: (pcLabels at: pc)].
			(analysis isResume: pc) ifTrue: [(self resumeAt: pc depth: d) ifFalse: [^false]]].
	asm bytecode: pc.
	^self instruction: op at: pc depth: d
!
emitEntry: pc depth: d
	"A method's or block's prologue; its resumption point (start) follows, setting x23 and x24, then the entry stencil."
	| entry |
	entry := asm pc.
	self emitPrologue.
	asm pc - entry = runtime prologueBytes asUInt64 ifFalse: [^false].
	runtime noteResume: pc at: asm pc - codeStart.
	self emitState: d.
	(self use: ST_ENTRY) ifFalse: [^false].
	asm bind: (self labelFor: pc).
	^true
!
emitState: d
	"x24 := the frame, x23 := the top of its d slots."
	asm comment: 'x24 := the frame, x23 := the top of the stack'.
	asm mov: X24 with: X19.
	(8 * (d - 1) between: -4095 and: 4095)
		ifTrue: [asm add: X23 with: X20 imm: 8 * (d - 1)]
		ifFalse: [
			asm mov: X16 imm: (8 * (d - 1)) asUInt64.
			asm add: X23 with: X20 with: X16]
!
resumeAt: pc depth: d
	"The interpreter may continue the frame at pc: out of line, code that sets x23 and x24 and jumps here."
	resumeCount >= STC_MAX_SLOW ifTrue: [^false].
	resumePcs at: resumeCount put: pc.
	resumeDepths at: resumeCount put: d.
	resumeCount := resumeCount + 1.
	^true
!
emitResumption: i
	runtime noteResume: (resumePcs at: i) at: asm pc - codeStart.
	asm comment: 'the interpreter resumes pc %d here' with: (resumePcs at: i).
	self emitState: (resumeDepths at: i).
	asm b: (self labelFor: (resumePcs at: i))
!
slow: s next: nextLabel jump: jumpLabel
	"Out of line, after the method: stencil s with the current holes, continuing at nextLabel. Answer its label (-1 if there are too many)."
	<c: 'int32_t stc_slow(int32_t s, int32_t next, int32_t jump)'>
	| l |
	slowCount >= STC_MAX_SLOW ifTrue: [^-1].
	l := asm newLabel.
	slowStencils at: slowCount put: s.
	slowLabels at: slowCount put: l.
	slowNext at: slowCount put: nextLabel.
	slowJumps at: slowCount put: jumpLabel.
	0 to: HOLE_COUNT - 1 do: [:h | slowValues at: 8 * slowCount + h put: (values at: h)].
	slowCount := slowCount + 1.
	^l
!
emitSlowPath: i
	asm bind: (slowLabels at: i).
	0 to: HOLE_COUNT - 1 do: [:h | values at: h put: (slowValues at: 8 * i + h)].
	asm bytecode: (values at: HOLE_PC) asInt64.
	(self use: (slowStencils at: i) next: (slowNext at: i) jump: (slowJumps at: i) slow: -1) ifFalse: [failed := true]
! !

!JitStencilCompiler methodsFor: 'instructions'!
instruction: op at: pc depth: d
	"Choose the stencils of the instruction at pc, set their holes, emit them."
	| next |
	next := pc + (analysis lengthAt: pc).
	op < 16r10 ifTrue: [^self pushTemp: op].
	op < 16r20 ifTrue: [^self pushInstVar: op - 16r10].
	op < 16r40 ifTrue: [^self pushLiteral: op - 16r20].
	op < 16r60 ifTrue: [^self pushLiteralVariable: op - 16r40].
	op < 16r68 ifTrue: [^self popStoreTemp: op - 16r60].
	op = 16r70 ifTrue: [^self use: ST_PUSH_SELF].
	op = 16r71 ifTrue: [^self use: ST_PUSH_TRUE].
	op = 16r72 ifTrue: [^self use: ST_PUSH_FALSE].
	op = 16r73 ifTrue: [^self use: ST_PUSH_NIL].
	op = 16r74 ifTrue: [^self use: ST_PUSH_ZERO].
	op = 16r75 ifTrue: [^self use: ST_PUSH_ONE].
	(op = 16r76 or: [op = 16r7C]) ifTrue: [^self use: ST_TO_INTERPRETER].
	op = 16r77 ifTrue: [^self use: ST_DUP].
	op = 16r78 ifTrue: [^self use: ST_POP].
	(op = 16r79 or: [op = 16r7B]) ifTrue: [^self use: ST_RETURN_TOP].
	op = 16r7A ifTrue: [^self use: ST_RETURN_SELF].
	op = 16r80 ifTrue: [^self pushTemp: (analysis byteAt: pc + 1)].
	op = 16r81 ifTrue: [^self pushInstVar: (analysis byteAt: pc + 1)].
	op = 16r82 ifTrue: [^self pushLiteral: (analysis byteAt: pc + 1)].
	op = 16r83 ifTrue: [^self pushLiteralVariable: (analysis byteAt: pc + 1)].
	op = 16r84 ifTrue: [^self use: ST_STORE_TEMP_X a: (analysis byteAt: pc + 1)].
	op = 16r85 ifTrue: [^self use: ST_STORE_INST_VAR_X a: (analysis byteAt: pc + 1)].
	(op = 16r86 or: [op = 16r89]) ifTrue: [
		(analysis byteAt: pc + 1) >= analysis numLiterals ifTrue: [^false].
		^self use: (op = 16r86 ifTrue: [ST_STORE_LITERAL_VARIABLE_X] ifFalse: [ST_POP_STORE_LITERAL_VARIABLE_X]) a: (analysis byteAt: pc + 1)].
	op = 16r87 ifTrue: [^self popStoreTemp: (analysis byteAt: pc + 1)].
	(op >= 16r8A and: [op <= 16r8C]) ifTrue: [
		values at: HOLE_B put: (analysis byteAt: pc + 2).
		^self use: ST_OUTER_TEMP + (op - 16r8A) a: (analysis byteAt: pc + 1)].
	(op = 16r8D or: [op = 16r8E or: [op >= 16rC0 and: [op < 16rF0]]]) ifTrue: [
		values at: HOLE_INFO put: (op >= 16rC0
			ifTrue: [((((op - 16rC0) >> 4) asInt64 bitOr: 1 << 8) bitOr: (op bitAnd: 15) asInt64 << 16)]
			ifFalse: [(((analysis byteAt: pc + 2) bitOr: 3 << 8) bitOr: (analysis byteAt: pc + 1) asInt64 << 16) bitOr: (op = 16r8E ifTrue: [1 << 24] ifFalse: [0])]) asUInt64.
		^self use: ST_SEND].
	op = 16r8F ifTrue: [^self use: ST_CLOSURE jump: (self labelFor: pc + 6 + (((analysis byteAt: pc + 4) asInt64 << 8) bitOr: (analysis byteAt: pc + 5)))].
	op = 16r90 ifTrue: [^self jumpTo: (analysis jumpTargetAt: pc) next: next].
	(op = 16r91 or: [op = 16r92]) ifTrue: [^self use: ST_BRANCH_IF + (op - 16r91) jump: (self branchLabelFor: (analysis jumpTargetAt: pc))].
	op = 16r93 ifTrue: [^self pushConstant: (self tagged: (analysis int16At: pc + 1))].
	op = 16r94 ifTrue: [^self use: ST_MAKE_ARRAY a: (analysis byteAt: pc + 1)].
	((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [^self superinstruction: pc depth: d].
	(op >= 16rA0 and: [op < 16rC0]) ifTrue: [^self special: op - 16rA0 at: pc].
	^false
!
pushTemp: i
	i < 16 ifTrue: [^self use: ST_PUSH_TEMP + i].
	^self use: ST_PUSH_TEMP_X a: i
!
pushInstVar: i
	i < 16 ifTrue: [^self use: ST_PUSH_INST_VAR + i].
	^self use: ST_PUSH_INST_VAR_X a: i
!
pushLiteral: i
	i >= analysis numLiterals ifTrue: [^false].
	i < 32 ifTrue: [^self use: ST_PUSH_LITERAL + i].
	^self use: ST_PUSH_LITERAL_X a: i
!
pushLiteralVariable: i
	i >= analysis numLiterals ifTrue: [^false].
	i < 32 ifTrue: [^self use: ST_PUSH_LITERAL_VARIABLE + i].
	^self use: ST_PUSH_LITERAL_VARIABLE_X a: i
!
popStoreTemp: i
	i < 8 ifTrue: [^self use: ST_POP_STORE_TEMP + i].
	^self use: ST_POP_STORE_TEMP_X a: i
!
pushConstant: v
	v = (self tagged: 0) ifTrue: [^self use: ST_PUSH_ZERO].
	v = (self tagged: 1) ifTrue: [^self use: ST_PUSH_ONE].
	values at: HOLE_VALUE put: v.
	^self use: ST_PUSH_CONSTANT
!
jumpTo: t next: next
	"An unconditional jump; a backward one checks for interrupts (synced at its target)."
	(analysis isLoopHead: t) ifTrue: [
		values at: HOLE_PC put: t asUInt64.
		^self use: ST_BRANCH_BACK jump: (self labelFor: t)].
	t = next ifTrue: [^true].
	^self use: ST_BRANCH jump: (self labelFor: t)
!
branchLabelFor: t
	"Where a conditional jump to t goes: t, or for a loop head an interrupt check out of line first."
	| saved l |
	(analysis isLoopHead: t) ifFalse: [^self labelFor: t].
	saved := values at: HOLE_PC.
	values at: HOLE_PC put: t asUInt64.
	l := self slow: ST_BRANCH_BACK next: -1 jump: (self labelFor: t).
	values at: HOLE_PC put: saved.
	l < 0 ifTrue: [failed := true].
	^l
!
superinstruction: pc depth: d
	"push temp a, push temp / literal / SmallInteger b, then a special selector (at depth d + 2, synced at this pc). With arith + - < > <= >= read the operands where they are (fused, as for special:at:, with a following pop into a temp or conditional jump); else the pushes, then the special selector."
	| op a b source k |
	op := analysis byteAt: pc.
	a := analysis byteAt: pc + 1.
	b := analysis byteAt: pc + 2.
	k := analysis specialIndexOf: analysis bytecodes + pc.
	source := (op = 16r97 or: [op >= 16r9A and: [op < 16rA0]])
		ifTrue: [0]
		ifFalse: [(op = 16r98 or: [op >= 16rF0 and: [op < 16rF6]]) ifTrue: [1] ifFalse: [2]].
	(runtime arith and: [k <= 5 and: [source ~= 1 or: [b < analysis numLiterals]]]) ifTrue: [
		values at: HOLE_A put: a.
		source = 2
			ifTrue: [values at: HOLE_VALUE put: (self tagged: b asInt8)]
			ifFalse: [values at: HOLE_B put: b].
		^self operands: k source: source at: pc].
	(self pushTemp: a) ifFalse: [^false].
	(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]])
		ifTrue: [(self pushTemp: b) ifFalse: [^false]]
		ifFalse: [
			(op = 16r98 or: [op >= 16rF0 and: [op < 16rF6]])
				ifTrue: [(self pushLiteral: b) ifFalse: [^false]]
				ifFalse: [(self pushConstant: (self tagged: b asInt8)) ifFalse: [^false]]].
	^self special: (analysis specialIndexOf: analysis bytecodes + pc) at: pc
!
operands: k source: source at: pc
	"A superinstruction's + - < > <= >= (k) of temp A and its operand (source: temp, literal, SmallInteger) where they are; a following pop into a temp or conditional jump is fused."
	| next j s fs t |
	next := pc + (analysis lengthAt: pc).
	values at: HOLE_INFO put: (self specialInfo: pc).
	fs := ST_FLOAT_OPERATION + k.
	(runtime fuse and: [analysis isStart: next]) ifTrue: [
		j := analysis byteAt: next.
		(k >= 2 and: [j = 16r91 or: [j = 16r92]]) ifTrue: [
			(self defer: next) ifFalse: [^false].
			s := (j = 16r91 ifTrue: [ST_COMPARE_OPERANDS_JUMP_TRUE] ifFalse: [ST_COMPARE_OPERANDS_JUMP_FALSE]) + ((k - 2) * 3) + source.
			^self use: s next: -1 jump: (self branchLabelFor: (analysis jumpTargetAt: next)) slow: (self slow: fs next: (self labelFor: next) jump: -1)].
		(k < 2 and: [(j >= 16r60 and: [j < 16r68]) or: [j = 16r87]]) ifTrue: [
			t := j = 16r87 ifTrue: [analysis byteAt: next + 1] ifFalse: [j - 16r60].
			(self defer: next) ifFalse: [^false].
			values at: HOLE_C put: t.
			s := (k = 0 ifTrue: [ST_ADD_OPERANDS_INTO] ifFalse: [ST_SUBTRACT_OPERANDS_INTO]) + source.
			^self use: s next: -1 jump: -1 slow: (self slow: fs next: (self labelFor: next) jump: -1)]].
	s := k >= 2
		ifTrue: [ST_COMPARE_OPERANDS + ((k - 2) * 3) + source]
		ifFalse: [(k = 0 ifTrue: [ST_ADD_OPERANDS] ifFalse: [ST_SUBTRACT_OPERANDS]) + source].
	^self use: s next: -1 jump: -1 slow: (self slow: fs next: (self labelFor: next) jump: -1)
!
specialInfo: pc
	"send:info:site:'s info for the special selector the instruction at pc sends."
	| k |
	k := analysis specialIndexOf: analysis bytecodes + pc.
	^((((((analysis specialArgc: k) asInt64 bitOr: (analysis lengthAt: pc) asInt64 << 8) bitOr: k asInt64 << 16) bitOr: 2 << 24)
		bitOr: (analysis pushesOf: analysis bytecodes + pc) asInt64 << 25)) asUInt64
!
special: k at: pc
	"Special selector k (the instruction at pc, its operands on the stack): inline for SmallIntegers, Arrays, Points and identity (arith), the rest out of line; a comparison followed by a conditional jump branches directly (fuse)."
	| next j s fs |
	next := pc + (analysis lengthAt: pc).
	values at: HOLE_INFO put: (self specialInfo: pc).
	(runtime arith or: [k = 19 or: [k = 20]]) ifFalse: [^self use: ST_SPECIAL_SEND].
	fs := k <= 9 ifTrue: [ST_FLOAT_OPERATION + k] ifFalse: [ST_SPECIAL_SEND].
	((k >= 2 and: [k <= 7]) or: [k = 19 or: [k = 20]]) ifTrue: [
		(runtime fuse and: [(analysis isStart: next) and: [(analysis byteAt: next) = 16r91 or: [(analysis byteAt: next) = 16r92]]]) ifTrue: [
			(self defer: next) ifFalse: [^false].
			j := (analysis byteAt: next) = 16r91.
			s := k >= 19
				ifTrue: [(j ifTrue: [ST_IDENTICAL_JUMP_TRUE] ifFalse: [ST_IDENTICAL_JUMP_FALSE]) + (k - 19)]
				ifFalse: [(j ifTrue: [ST_COMPARE_JUMP_TRUE] ifFalse: [ST_COMPARE_JUMP_FALSE]) + (k - 2)].
			^self use: s next: -1 jump: (self branchLabelFor: (analysis jumpTargetAt: next))
				slow: (k >= 19 ifTrue: [-1] ifFalse: [self slow: fs next: (self labelFor: next) jump: -1])].
		k >= 19 ifTrue: [^self use: ST_IDENTICAL + (k - 19)].
		^self use: ST_COMPARE + (k - 2) next: -1 jump: -1 slow: (self slow: fs next: (self labelFor: next) jump: -1)].
	s := -1.
	k = 0 ifTrue: [s := ST_ADD].
	k = 1 ifTrue: [s := ST_SUBTRACT].
	k = 8 ifTrue: [s := ST_MULTIPLY].
	k = 9 ifTrue: [s := ST_DIVIDE].
	k = 10 ifTrue: [s := ST_MODULO].
	k = 13 ifTrue: [s := ST_FLOOR_DIVIDE].
	k = 14 ifTrue: [s := ST_BIT_AND].
	k = 15 ifTrue: [s := ST_BIT_OR].
	k = 16 ifTrue: [s := ST_BASIC_AT].
	k = 17 ifTrue: [s := ST_BASIC_AT_PUT].
	k = 18 ifTrue: [s := ST_BASIC_SIZE].
	(k = 27 or: [k = 28]) ifTrue: [s := ST_POINT_COORDINATE + (k - 27)].
	k = 29 ifTrue: [s := ST_CLASS_OF].
	s < 0 ifTrue: [^self use: ST_SPECIAL_SEND].
	^self use: s next: -1 jump: -1 slow: (self slow: fs next: (self labelFor: next) jump: -1)
! !

!JitStencilCompiler methodsFor: 'emitting'!
tagged: v
	"The SmallInteger v."
	^((v asInt64 << 1) bitOr: 1) asUInt64
!
use: s
	^self use: s next: -1 jump: -1 slow: -1
!
use: s a: a
	values at: HOLE_A put: a asUInt64.
	^self use: s next: -1 jump: -1 slow: -1
!
use: s jump: jumpLabel
	^self use: s next: -1 jump: jumpLabel slow: -1
!
use: s next: nextLabel jump: jumpLabel slow: slowLabel
	"Stencil s with the holes in values; its continuations: nextLabel (-1: the code that follows), jumpLabel, slowLabel."
	<c: 'bool stc_use(int32_t s, int32_t next, int32_t jump, int32_t slow)'>
	asm comment: (table names at: s).
	threaded ifTrue: [^self call: s next: nextLabel jump: jumpLabel slow: slowLabel].
	^self copy: s next: nextLabel jump: jumpLabel slow: slowLabel
!
copy: s next: nextLabel jump: jumpLabel slow: slowLabel
	"Copy stencil s's code and patch it. A trailing branch to the next instruction is left out, a trailing branch to the return replaced by the epilogue."
	| off size first n r last trailing start end k continues |
	off := table stencils at: 4 * s.
	size := (table stencils at: 4 * s + 1) asInt64.
	first := (table stencils at: 4 * s + 2) asInt64.
	n := (table stencils at: 4 * s + 3) asInt64.
	trailing := -1.
	continues := false.
	0 to: n - 1 do: [:i |
		r := table relocations + (4 * (first + i)).
		((r at: 1) bitAnd: 16rFFFF) = (RELOC_BRANCH bitOr: TARGET_CONT << 8) ifTrue: [
			(r at: 1) >> 16 = CONT_NEXT ifTrue: [continues := true].
			((r at: 0) = (size - 4) and: [(r at: 1) >> 16 = CONT_NEXT or: [(r at: 1) >> 16 = CONT_RETURN]]) ifTrue: [trailing := ((r at: 1) >> 16) asInt32]]].
	last := trailing >= 0 ifTrue: [first + n - 1] ifFalse: [first + n].
	start := asm pc.
	(self emitCode: table code + off size: (trailing >= 0 ifTrue: [size - 4] ifFalse: [size]) relocations: first to: last) ifFalse: [^false].
	end := asm pc.
	values at: HOLE_SITE put: start.
	0 to: 7 do: [:i | copySlots at: i put: -1].
	k := first.
	[k < last] whileTrue: [
		(self patch: table relocations + (4 * k) at: start next: end jump: jumpLabel slow: slowLabel) ifFalse: [failed := true].
		k := k + 1].
	trailing = CONT_RETURN ifTrue: [self emitReturnFrom: X24].
	(continues and: [nextLabel >= 0]) ifTrue: [asm b: nextLabel].
	^true
!
emitCode: src size: n relocations: first to: last
	"The stencil's code at pc; with notes word by word, each hole and continuation commented."
	| dst k |
	asm noting ifFalse: [
		dst := asm skip: n.
		dst = 0 ifTrue: [^false].
		libc memcpy: (self cCoerce: dst to: 'void *') from: src size: n asUInt64.
		^true].
	k := first.
	0 to: n - 4 by: 4 do: [:o |
		[k < last and: [(table relocations at: 4 * k) < o]] whileTrue: [k := k + 1].
		(k < last and: [(table relocations at: 4 * k) = o]) ifTrue: [self noteRelocation: table relocations + (4 * k)].
		asm emit: (self uint32At: src + o)].
	^asm failed not
!
noteRelocation: r
	| target id |
	target := ((r at: 1) >> 8) bitAnd: 255.
	id := (r at: 1) >> 16.
	target = TARGET_SYMBOL ifTrue: [^asm comment: (table symbolNames at: id)].
	target = TARGET_DATA ifTrue: [^asm comment: 'the stencils'' data'].
	target = TARGET_HOLE ifTrue: [
		id = HOLE_PC ifTrue: [^asm comment: 'hole PC: %d' with: (values at: id) asInt64].
		id = HOLE_A ifTrue: [^asm comment: 'hole A: %d' with: (values at: id) asInt64].
		id = HOLE_B ifTrue: [^asm comment: 'hole B: %d' with: (values at: id) asInt64].
		id = HOLE_INFO ifTrue: [^asm comment: 'hole INFO: %d' with: (values at: id) asInt64].
		id = HOLE_SITE ifTrue: [^asm comment: 'hole SITE: this code''s address'].
		id = HOLE_C ifTrue: [^asm comment: 'hole C: %d' with: (values at: id) asInt64].
		^asm comment: 'hole VALUE: %d' with: (values at: id) asInt64].
	id = CONT_NEXT ifTrue: [^asm comment: 'continue: the next instruction'].
	id = CONT_JUMP ifTrue: [^asm comment: 'continue: the jump target'].
	id = CONT_SLOW ifTrue: [^asm comment: 'continue: out of line'].
	id = CONT_EXIT_SYNC ifTrue: [^asm comment: 'leave to the interpreter at the stored pc'].
	id = CONT_EXIT ifTrue: [^asm comment: 'leave to the interpreter'].
	asm comment: 'return'
!
patch: r at: start next: end jump: jumpLabel slow: slowLabel
	"Relocation r of a copy at start (end: where the next instruction's code is)."
	| kind target id addend site v |
	kind := (r at: 1) bitAnd: 255.
	target := ((r at: 1) >> 8) bitAnd: 255.
	id := ((r at: 1) >> 16) asInt32.
	addend := (r at: 3) asInt32.
	site := start + (r at: 0).
	kind = RELOC_BRANCH ifTrue: [
		target = TARGET_SYMBOL ifTrue: [^asm patchBranchAt: site to: (symbolTargets at: id) + addend].
		target ~= TARGET_CONT ifTrue: [^false].
		id = CONT_NEXT ifTrue: [^asm patchBranchAt: site to: end].
		id = CONT_JUMP ifTrue: [^jumpLabel >= 0 and: [asm branchAt: site to: jumpLabel]].
		id = CONT_SLOW ifTrue: [^slowLabel >= 0 and: [asm branchAt: site to: slowLabel]].
		id = CONT_EXIT_SYNC ifTrue: [^asm patchBranchAt: site to: exitSyncGlue].
		id = CONT_EXIT ifTrue: [^asm patchBranchAt: site to: stubs exitPlainAddress].
		^asm patchBranchAt: site to: returnGlue].
	target = TARGET_SYMBOL ifTrue: [
		v := gotBase + (8 * id).
		kind = RELOC_GOT_PAIR ifTrue: [^(asm patchBranchAt: site to: v) and: [self pageOffsetAt: start + (r at: 2) to: v scale: 3]].
		kind = RELOC_GOT_PAGE ifTrue: [^asm patchBranchAt: site to: v].
		kind = RELOC_GOT_PAGEOFF ifTrue: [^self pageOffsetAt: site to: v scale: 3].
		^false].
	target = TARGET_DATA ifTrue: [
		v := dataBase + addend.
		kind = RELOC_PAGE ifTrue: [^asm patchBranchAt: site to: v].
		kind = RELOC_PAGEOFF ifTrue: [^self pageOffsetAt: site to: v scale: (r at: 2) asInt32].
		^false].
	target ~= TARGET_HOLE ifTrue: [^false].
	v := (values at: id) + addend.
	kind = RELOC_GOT_PAIR ifTrue: [^self relax: v at: site and: start + (r at: 2)].
	kind = RELOC_GOT_PAGE ifTrue: [^self slot: (self copySlotFor: id value: v) at: site kind: 0].
	kind = RELOC_GOT_PAGEOFF ifTrue: [^self slot: (self copySlotFor: id value: v) at: site kind: 1].
	^false
!
pageOffsetAt: site to: address scale: k
	"The low 12 bits of address into the add, load or store at site (scaled by its access size)."
	| w lo |
	lo := address bitAnd: 16rFFF.
	(lo bitAnd: (1 << k) - 1) = 0 ifFalse: [^false].
	w := self uint32At: site.
	self uint32At: site put: ((w bitClear: 16r3FFC00) bitOr: (lo >> k) << 10).
	^true
!
relax: v at: a1 and: a2
	"An adrp (a1) and ldr rt, [rn] (a2) that load v from a GOT: the shortest code that puts v into rt instead (movz, movn, movk, adr, adrp and add), else a load from a literal slot after the method."
	| ldr rt rn d |
	ldr := self uint32At: a2.
	rt := (ldr bitAnd: 31) asUInt64.
	rn := ((ldr >> 5) bitAnd: 31) asUInt64.
	v < 16r10000 ifTrue: [^self put: 16rD503201F at: a1 and: ((16rD2800000 bitOr: v << 5) bitOr: rt) at: a2].
	v bitInvert64 < 16r10000 ifTrue: [^self put: 16rD503201F at: a1 and: ((16r92800000 bitOr: v bitInvert64 << 5) bitOr: rt) at: a2].
	rt = rn ifTrue: [
		v < 16r100000000 ifTrue: [
			^self put: ((16rD2800000 bitOr: (v bitAnd: 16rFFFF) << 5) bitOr: rt) at: a1 and: ((16rF2A00000 bitOr: (v >> 16) << 5) bitOr: rt) at: a2].
		v >> 32 = 16rFFFFFFFF ifTrue: [
			^self put: ((16r92800000 bitOr: (v bitInvert64 bitAnd: 16rFFFF) << 5) bitOr: rt) at: a1 and: ((16rF2A00000 bitOr: ((v >> 16) bitAnd: 16rFFFF) << 5) bitOr: rt) at: a2]].
	d := (v - a2) asInt64.
	(d between: -16r100000 and: 16rFFFFF) ifTrue: [
		^self put: 16rD503201F at: a1 and: (((16r10000000 bitOr: (d bitAnd: 3) asUInt64 << 29) bitOr: ((d >> 2) bitAnd: 16r7FFFF) asUInt64 << 5) bitOr: rt) at: a2].
	d := (((v bitClear: 16rFFF) - (a1 bitClear: 16rFFF)) asInt64) >> 12.
	(d between: -16r100000 and: 16rFFFFF) ifTrue: [
		self uint32At: a2 put: (((16r91000000 bitOr: (v bitAnd: 16rFFF) << 10) bitOr: rn << 5) bitOr: rt).
		^asm patchBranchAt: a1 to: v].
	d := self slotFor: v.
	^(self slot: d at: a1 kind: 0) and: [self slot: d at: a2 kind: 1]
!
put: w1 at: a1 and: w2 at: a2
	self uint32At: a1 put: w1.
	self uint32At: a2 put: w2.
	^true
!
copySlotFor: id value: v
	"The literal slot of hole id in this copy (GOT loads the compiler did not pair)."
	(copySlots at: id) < 0 ifTrue: [copySlots at: id put: (self slotFor: v)].
	^copySlots at: id
!
slotFor: v
	"A literal slot after the method holding v; -1 if there are too many."
	slotCount >= STC_MAX_SLOTS ifTrue: [^-1].
	slotValues at: slotCount put: v.
	slotCount := slotCount + 1.
	^slotCount - 1
!
slot: i at: site kind: k
	"The adrp (k 0) or ldr (1) at site loads from slot i, once the slots are placed."
	(i < 0 or: [patchCount >= STC_MAX_PATCHES]) ifTrue: [^false].
	patchSites at: patchCount put: site.
	patchSlots at: patchCount put: i.
	patchKinds at: patchCount put: k asUInt8.
	patchCount := patchCount + 1.
	^true
!
emitSlots
	"The literal slots, after the method's code."
	| base a |
	slotCount = 0 ifTrue: [^self].
	(asm pc bitAnd: 7) ~= 0 ifTrue: [asm nop].
	base := asm pc.
	0 to: slotCount - 1 do: [:i | asm emit64: (slotValues at: i)].
	asm failed ifTrue: [^self].
	0 to: patchCount - 1 do: [:i |
		a := base + (8 * (patchSlots at: i)).
		(patchKinds at: i) = 0
			ifTrue: [(asm patchBranchAt: (patchSites at: i) to: a) ifFalse: [failed := true]]
			ifFalse: [(self pageOffsetAt: (patchSites at: i) to: a scale: 3) ifFalse: [failed := true]]]
!
call: s next: nextLabel jump: jumpLabel slow: slowLabel
	"A bl of stencil s's threaded function, its holes in x0-x7 in the order of their ids (SITE is the return address), then a branch on the continuation it answers in x0."
	| holes conts others first fn r |
	holes := table threadedHoles at: s.
	r := 0.
	0 to: HOLE_COUNT - 1 do: [:h |
		(((holes >> h) bitAnd: 1) ~= 0 and: [h ~= HOLE_SITE]) ifTrue: [
			asm mov: X0 + r imm: (values at: h).
			r := r + 1]].
	fn := table threadedFunctions at: s.
	(self reaches: fn)
		ifTrue: [asm bl: (asm labelAt: fn)]
		ifFalse: [
			asm comment: 'out of bl''s reach: the address pc-relative'.
			asm adrp: X16 label: (asm labelAt: fn).
			asm add: X16 with: X16 imm: (fn bitAnd: 16rFFF).
			asm blr: X16].
	conts := table threadedContinuations at: s.
	others := conts bitClear: 1 << CONT_NEXT.
	(others ~= 0 and: [(others bitAnd: others - 1) = 0 and: [(conts bitAnd: 1 << CONT_NEXT) ~= 0]])
		ifTrue: [
			asm comment: 'not 0: where the stencil continues'.
			0 to: 7 do: [:c | (others >> c bitAnd: 1) ~= 0 ifTrue: [asm cbnz: X0 to: (self labelOfContinuation: c jump: jumpLabel slow: slowLabel)]]]
		ifFalse: [
			first := true.
			0 to: 7 do: [:c |
				(others >> c bitAnd: 1) ~= 0 ifTrue: [
					((others >> (c + 1)) = 0 and: [(conts bitAnd: 1 << CONT_NEXT) = 0])
						ifTrue: [asm b: (self labelOfContinuation: c jump: jumpLabel slow: slowLabel)]
						ifFalse: [
							first ifTrue: [asm comment: 'the continuation the stencil answers'].
							first := false.
							asm cmp: X0 imm: c.
							asm b: (self labelOfContinuation: c jump: jumpLabel slow: slowLabel) if: COND_EQ]]]].
	((conts bitAnd: 1 << CONT_NEXT) ~= 0 and: [nextLabel >= 0]) ifTrue: [asm b: nextLabel].
	^true
!
labelOfContinuation: c jump: jumpLabel slow: slowLabel
	c = CONT_JUMP ifTrue: [
		jumpLabel < 0 ifTrue: [failed := true. ^returnLabel].
		^jumpLabel].
	c = CONT_SLOW ifTrue: [
		slowLabel < 0 ifTrue: [failed := true. ^returnLabel].
		^slowLabel].
	c = CONT_EXIT_SYNC ifTrue: [^exitSyncLabel].
	c = CONT_EXIT ifTrue: [^exitPlainLabel].
	^returnLabel
! !
