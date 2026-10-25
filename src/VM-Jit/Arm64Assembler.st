Arm64Module subclass: #Arm64Assembler
	instanceVariableNames: 'asmStart asmPc asmLimit asmError asmLabelCount asmLabels asmLabelFixups asmFixupCount asmFixupSites asmFixupNext asmUnresolved asmNoting asmNoteCount asmNoteOffsets asmNoteTexts asmNoteArgs'
	classVariableNames: 'ASM_MAX_FIXUPS ASM_MAX_LABELS ASM_MAX_NOTES'
	package: 'VM-Jit'!

Arm64Assembler comment: 'I write arm64 instructions into a code buffer: beginAt:limit:, then one message per instruction, operands in assembly order (asm add: X0 with: X1 imm: 12), then finish (the error code, ASM_OK if all went well). The instruction methods are inline, so with constant operands each is a store of a constant word.

Labels: newLabel, bind:, labelAt: anAddress (a label bound to an address outside the code, e.g. a runtime routine); branches to labels not bound yet are patched when they are. An immediate, offset or branch distance that does not encode sets the error (the first sticks; the code must not be run); the encoders logicalImmediate:width: and fmovImmediate: answer -1 for values that do not encode.

Notes, for annotated disassembly: with recordNotes: true, comment: (and comment:with:, a printf format and an integer) and bytecode: record what the code at pc does and which bytecode it implements; otherwise they cost a test of a flag.

Patching: patchBranchAt:to: and branchTargetAt: (b, bl, b.cond, cbz, cbnz, tbz, tbnz, ldr literal, adr, adrp); mov:imm64: emits a fixed movz/movk sequence that patchMov64At:value: rewrites and mov64At: reads.'!

!Arm64Assembler class methodsFor: 'declaring'!
declarations
	^#((asmStart uint64_t) (asmPc uint64_t) (asmLimit uint64_t) (asmError int32_t) (asmLabelCount int32_t) (asmLabels 'uint64_t[ASM_MAX_LABELS]') (asmLabelFixups 'int32_t[ASM_MAX_LABELS]') (asmFixupCount int32_t) (asmFixupSites 'uint64_t[ASM_MAX_FIXUPS]') (asmFixupNext 'int32_t[ASM_MAX_FIXUPS]') (asmUnresolved int32_t) (asmNoting bool) (asmNoteCount int32_t) (asmNoteOffsets 'uint32_t[ASM_MAX_NOTES]') (asmNoteTexts 'const char *[ASM_MAX_NOTES]') (asmNoteArgs 'int64_t[ASM_MAX_NOTES]'))
!
initialize
	ASM_MAX_LABELS := 4096.
	ASM_MAX_FIXUPS := 16384.
	ASM_MAX_NOTES := 8192
! !

!Arm64Assembler methodsFor: 'buffer'!
beginAt: start limit: limit
	"Assemble into [start, limit); forget all labels."
	<c: 'void asm_begin(uint64_t start, uint64_t limit)'>
	<export>
	asmStart := start.
	asmPc := start.
	asmLimit := limit.
	asmError := ASM_OK.
	asmLabelCount := 0.
	asmFixupCount := 0.
	asmUnresolved := 0.
	asmNoteCount := 0
!
finish
	"Answer the error code: ASM_OK unless something did not encode, the buffer filled up or a label used was not bound."
	<c: 'int32_t asm_finish(void)'>
	<export>
	asmUnresolved > 0 ifTrue: [self fail: ASM_ERR_LABEL].
	^asmError
!
pc
	"The address of the next instruction."
	^asmPc
!
codeStart
	^asmStart
!
codeSize
	^asmPc - asmStart
!
errorCode
	^asmError
!
failed
	^asmError ~= ASM_OK
!
isOK: aCode
	^aCode = ASM_OK
!
isFull: aCode
	"aCode (finish's answer) says the buffer filled up."
	^aCode = ASM_ERR_FULL
!
fail: aCode
	asmError = ASM_OK ifTrue: [asmError := aCode]
!
emit: aWord
	"Append an instruction (or a data word)."
	asmPc < asmLimit
		ifTrue: [
			self uint32At: asmPc put: aWord.
			asmPc := asmPc + 4]
		ifFalse: [self fail: ASM_ERR_FULL]
!
emit64: aValue
	"Append a 64-bit data word (little-endian), e.g. a literal for ldr:label:."
	self emit: (aValue bitAnd: 16rFFFFFFFF).
	self emit: aValue asUInt64 >> 32
!
skip: n
	"The next n bytes (a multiple of 4) are code or data the caller writes: answer their address, 0 if there is no room."
	| a |
	a := asmPc.
	asmLimit - asmPc < n asUInt64 ifTrue: [
		self fail: ASM_ERR_FULL.
		^0 asUInt64].
	asmPc := asmPc + n.
	^a
! !

!Arm64Assembler methodsFor: 'labels'!
newLabel
	<c: 'int32_t asm_new_label(void)'>
	<export>
	asmLabelCount >= ASM_MAX_LABELS ifTrue: [
		self fail: ASM_ERR_LABEL.
		^0].
	asmLabels at: asmLabelCount put: 0.
	asmLabelFixups at: asmLabelCount put: -1.
	asmLabelCount := asmLabelCount + 1.
	^asmLabelCount - 1
!
labelAt: anAddress
	"A label bound to anAddress."
	<c: 'int32_t asm_label_at(uint64_t address)'>
	<export>
	| label |
	label := self newLabel.
	asmLabels at: label put: anAddress.
	^label
!
bind: aLabel
	"Bind aLabel to the next instruction and patch the branches to it."
	<c: 'void asm_bind(int32_t label)'>
	<export>
	| f |
	asmLabels at: aLabel put: asmPc.
	f := asmLabelFixups at: aLabel.
	[f >= 0] whileTrue: [
		(asmFixupSites at: f) < asmPc ifTrue: [self patchBranchAt: (asmFixupSites at: f) to: asmPc].
		asmUnresolved := asmUnresolved - 1.
		f := asmFixupNext at: f].
	asmLabelFixups at: aLabel put: -1
!
addressOf: aLabel
	"The address aLabel is bound to, 0 if it is not bound yet."
	^asmLabels at: aLabel
!
targetOf: aLabel
	"The address of aLabel for an instruction at pc; if aLabel is not bound yet, pc, patched when it is bound."
	<c: 'uint64_t asm_target_of(int32_t label)'>
	<export>
	| a |
	a := asmLabels at: aLabel.
	a ~= 0 ifTrue: [^a].
	asmFixupCount >= ASM_MAX_FIXUPS ifTrue: [
		self fail: ASM_ERR_LABEL.
		^asmPc].
	asmFixupSites at: asmFixupCount put: asmPc.
	asmFixupNext at: asmFixupCount put: (asmLabelFixups at: aLabel).
	asmLabelFixups at: aLabel put: asmFixupCount.
	asmFixupCount := asmFixupCount + 1.
	asmUnresolved := asmUnresolved + 1.
	^asmPc
!
fixup: site to: aLabel
	"The branch at site goes to aLabel, patched when it is bound."
	asmFixupCount >= ASM_MAX_FIXUPS ifTrue: [
		self fail: ASM_ERR_LABEL.
		^false].
	asmFixupSites at: asmFixupCount put: site.
	asmFixupNext at: asmFixupCount put: (asmLabelFixups at: aLabel).
	asmLabelFixups at: aLabel put: asmFixupCount.
	asmFixupCount := asmFixupCount + 1.
	asmUnresolved := asmUnresolved + 1.
	^true
!
branchAt: site to: aLabel
	"Point the branch at site (before pc, written by the caller) to aLabel: now if it is bound, else when it is. Answer whether it reaches."
	<c: 'bool asm_branch_at(uint64_t site, int32_t label)'>
	<export>
	| a |
	a := asmLabels at: aLabel.
	a ~= 0 ifTrue: [^self patchBranchAt: site to: a].
	^self fixup: site to: aLabel
! !

!Arm64Assembler methodsFor: 'notes'!
noting
	"Whether notes are recorded."
	^asmNoting
!
recordNotes: aBoolean
	"Record comment: and bytecode: notes from now on (or not); forget those recorded."
	<c: 'void asm_record_notes(bool on)'>
	<export>
	asmNoting := aBoolean.
	asmNoteCount := 0
!
comment: aString
	"Say what the code from pc on does."
	asmNoting ifTrue: [self note: aString value: 0]
!
comment: aFormat with: anInteger
	"A comment with an integer, formatted when the code is disassembled ('spill stack slot %d')."
	asmNoting ifTrue: [self note: aFormat value: anInteger]
!
bytecode: aPc
	"The code of the bytecode at aPc starts at pc."
	asmNoting ifTrue: [self note: self null value: aPc]
!
note: aString value: anInteger
	"Record (pc - start, aString, anInteger); aString is NULL for a bytecode."
	<c: 'void asm_note(const char *text, int64_t value)'>
	<export>
	asmNoteCount < ASM_MAX_NOTES ifTrue: [
		asmNoteOffsets at: asmNoteCount put: (asmPc - asmStart) asUInt32.
		asmNoteTexts at: asmNoteCount put: aString.
		asmNoteArgs at: asmNoteCount put: anInteger.
		asmNoteCount := asmNoteCount + 1]
!
noteCount
	^asmNoteCount
!
noteOffsetAt: i
	^asmNoteOffsets at: i
!
noteTextAt: i
	^asmNoteTexts at: i
!
noteValueAt: i
	^asmNoteArgs at: i
! !

!Arm64Assembler methodsFor: 'fields'!
rd: rd rn: rn
	^((rn bitAnd: 31) asUInt64 << 5) bitOr: (rd bitAnd: 31)
!
rd: rd rn: rn rm: rm
	^(((rm bitAnd: 31) asUInt64 << 16) bitOr: ((rn bitAnd: 31) asUInt64 << 5)) bitOr: (rd bitAnd: 31)
!
sf: aRegister
	"Bit 31 of a 64-bit (X) instruction."
	^(aRegister bitAnd: REG_W) = 0 ifTrue: [16r80000000] ifFalse: [0]
!
bits: aRegister
	^(aRegister bitAnd: REG_W) = 0 ifTrue: [64] ifFalse: [32]
!
isSP: aRegister
	^(aRegister bitAnd: REG_SP) ~= 0
!
isD: aRegister
	^(aRegister bitAnd: REG_D) ~= 0
!
zr: aRegister
	"The zero register of aRegister's width."
	^(aRegister bitAnd: REG_W) bitOr: 31
!
offsetTo: target bits: n
	"(target - pc) / 4 as an n-bit field."
	| off |
	off := (target - asmPc) asInt64 >> 2.
	(off between: (1 << (n - 1)) negated and: (1 << (n - 1)) - 1) ifFalse: [
		self fail: ASM_ERR_RANGE.
		^0].
	^off bitAnd: (1 << n) - 1
! !

!Arm64Assembler methodsFor: 'add and subtract'!
addSub: op rd: rd rn: rn imm: imm
	"op: 0 add, 16r40000000 sub, plus 16r20000000 to set the flags. A negative imm flips add and sub; one above 4095 needs lsl #12."
	| neg v o |
	neg := imm < 0.
	v := neg ifTrue: [imm negated] ifFalse: [imm].
	o := neg ifTrue: [op bitXor: 16r40000000] ifFalse: [op].
	v <= 4095 ifTrue: [^self emit: (((16r11000000 bitOr: (self sf: rd)) bitOr: o) bitOr: ((v asUInt64 << 10) bitOr: (self rd: rd rn: rn)))].
	((v bitAnd: 4095) = 0 and: [v <= 16rFFF000]) ifTrue: [
		^self emit: (((16r11400000 bitOr: (self sf: rd)) bitOr: o) bitOr: (((v >> 12) asUInt64 << 10) bitOr: (self rd: rd rn: rn)))].
	self fail: ASM_ERR_IMMEDIATE
!
addSub: op rd: rd rn: rn rm: rm shift: type amount: n
	"Shifted register; with SP only lsl, as an extended register."
	((self isSP: rd) or: [self isSP: rn]) ifTrue: [
		type = SHIFT_LSL ifFalse: [^self fail: ASM_ERR_OPERAND].
		^self addSub: op rd: rd rn: rn rm: rm extend: ((rd bitAnd: REG_W) = 0 ifTrue: [EXT_UXTX] ifFalse: [EXT_UXTW]) amount: n].
	(type = SHIFT_ROR or: [n >= (self bits: rd)]) ifTrue: [^self fail: ASM_ERR_OPERAND].
	self emit: (((16r0B000000 bitOr: (self sf: rd)) bitOr: op) bitOr: (((type asUInt64 << 22) bitOr: (n asUInt64 << 10)) bitOr: (self rd: rd rn: rn rm: rm)))
!
addSub: op rd: rd rn: rn rm: rm extend: ext amount: n
	(n between: 0 and: 4) ifFalse: [^self fail: ASM_ERR_OPERAND].
	self emit: (((16r0B200000 bitOr: (self sf: rd)) bitOr: op) bitOr: ((((ext bitAnd: 7) asUInt64 << 13) bitOr: (n asUInt64 << 10)) bitOr: (self rd: rd rn: rn rm: rm)))
!
add: rd with: rn imm: imm
	self addSub: 0 rd: rd rn: rn imm: imm
!
adds: rd with: rn imm: imm
	self addSub: 16r20000000 rd: rd rn: rn imm: imm
!
sub: rd with: rn imm: imm
	self addSub: 16r40000000 rd: rd rn: rn imm: imm
!
subs: rd with: rn imm: imm
	self addSub: 16r60000000 rd: rd rn: rn imm: imm
!
cmp: rn imm: imm
	self addSub: 16r60000000 rd: (self zr: rn) rn: rn imm: imm
!
cmn: rn imm: imm
	self addSub: 16r20000000 rd: (self zr: rn) rn: rn imm: imm
!
add: rd with: rn with: rm
	self addSub: 0 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
adds: rd with: rn with: rm
	self addSub: 16r20000000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
sub: rd with: rn with: rm
	self addSub: 16r40000000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
subs: rd with: rn with: rm
	self addSub: 16r60000000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
cmp: rn with: rm
	self addSub: 16r60000000 rd: (self zr: rn) rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
cmn: rn with: rm
	self addSub: 16r20000000 rd: (self zr: rn) rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
neg: rd with: rm
	self addSub: 16r40000000 rd: rd rn: (self zr: rd) rm: rm shift: SHIFT_LSL amount: 0
!
negs: rd with: rm
	self addSub: 16r60000000 rd: rd rn: (self zr: rd) rm: rm shift: SHIFT_LSL amount: 0
!
add: rd with: rn with: rm shift: type amount: n
	self addSub: 0 rd: rd rn: rn rm: rm shift: type amount: n
!
adds: rd with: rn with: rm shift: type amount: n
	self addSub: 16r20000000 rd: rd rn: rn rm: rm shift: type amount: n
!
sub: rd with: rn with: rm shift: type amount: n
	self addSub: 16r40000000 rd: rd rn: rn rm: rm shift: type amount: n
!
subs: rd with: rn with: rm shift: type amount: n
	self addSub: 16r60000000 rd: rd rn: rn rm: rm shift: type amount: n
!
cmp: rn with: rm shift: type amount: n
	self addSub: 16r60000000 rd: (self zr: rn) rn: rn rm: rm shift: type amount: n
!
cmn: rn with: rm shift: type amount: n
	self addSub: 16r20000000 rd: (self zr: rn) rn: rn rm: rm shift: type amount: n
!
add: rd with: rn with: rm extend: ext amount: n
	self addSub: 0 rd: rd rn: rn rm: rm extend: ext amount: n
!
adds: rd with: rn with: rm extend: ext amount: n
	self addSub: 16r20000000 rd: rd rn: rn rm: rm extend: ext amount: n
!
sub: rd with: rn with: rm extend: ext amount: n
	self addSub: 16r40000000 rd: rd rn: rn rm: rm extend: ext amount: n
!
subs: rd with: rn with: rm extend: ext amount: n
	self addSub: 16r60000000 rd: rd rn: rn rm: rm extend: ext amount: n
!
cmp: rn with: rm extend: ext amount: n
	self addSub: 16r60000000 rd: (self zr: rn) rn: rn rm: rm extend: ext amount: n
!
cmn: rn with: rm extend: ext amount: n
	self addSub: 16r20000000 rd: (self zr: rn) rn: rn rm: rm extend: ext amount: n
! !

!Arm64Assembler methodsFor: 'logical'!
logical: opc rd: rd rn: rn imm: imm
	"opc: 0 and, 16r20000000 orr, 16r40000000 eor, 16r60000000 ands."
	| enc |
	enc := self logicalImmediate: imm asUInt64 width: (self bits: rd).
	enc < 0 ifTrue: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: (((16r12000000 bitOr: (self sf: rd)) bitOr: opc) bitOr: ((enc asUInt64 << 10) bitOr: (self rd: rd rn: rn)))
!
logical: opc rd: rd rn: rn rm: rm shift: type amount: n
	"opc as above, plus 16r200000 to invert rm (bic, orn, eon, bics)."
	n >= (self bits: rd) ifTrue: [^self fail: ASM_ERR_OPERAND].
	self emit: (((16r0A000000 bitOr: (self sf: rd)) bitOr: opc) bitOr: ((((type bitAnd: 3) asUInt64 << 22) bitOr: (n asUInt64 << 10)) bitOr: (self rd: rd rn: rn rm: rm)))
!
and: rd with: rn imm: imm
	self logical: 0 rd: rd rn: rn imm: imm
!
orr: rd with: rn imm: imm
	self logical: 16r20000000 rd: rd rn: rn imm: imm
!
eor: rd with: rn imm: imm
	self logical: 16r40000000 rd: rd rn: rn imm: imm
!
ands: rd with: rn imm: imm
	self logical: 16r60000000 rd: rd rn: rn imm: imm
!
bic: rd with: rn imm: imm
	self logical: 0 rd: rd rn: rn imm: imm asUInt64 bitInvert64
!
tst: rn imm: imm
	self logical: 16r60000000 rd: (self zr: rn) rn: rn imm: imm
!
and: rd with: rn with: rm
	self logical: 0 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
orr: rd with: rn with: rm
	self logical: 16r20000000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
eor: rd with: rn with: rm
	self logical: 16r40000000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
ands: rd with: rn with: rm
	self logical: 16r60000000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
bic: rd with: rn with: rm
	self logical: 16r200000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
orn: rd with: rn with: rm
	self logical: 16r20200000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
eon: rd with: rn with: rm
	self logical: 16r40200000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
bics: rd with: rn with: rm
	self logical: 16r60200000 rd: rd rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
tst: rn with: rm
	self logical: 16r60000000 rd: (self zr: rn) rn: rn rm: rm shift: SHIFT_LSL amount: 0
!
mvn: rd with: rm
	self logical: 16r20200000 rd: rd rn: (self zr: rd) rm: rm shift: SHIFT_LSL amount: 0
!
and: rd with: rn with: rm shift: type amount: n
	self logical: 0 rd: rd rn: rn rm: rm shift: type amount: n
!
orr: rd with: rn with: rm shift: type amount: n
	self logical: 16r20000000 rd: rd rn: rn rm: rm shift: type amount: n
!
eor: rd with: rn with: rm shift: type amount: n
	self logical: 16r40000000 rd: rd rn: rn rm: rm shift: type amount: n
!
ands: rd with: rn with: rm shift: type amount: n
	self logical: 16r60000000 rd: rd rn: rn rm: rm shift: type amount: n
!
bic: rd with: rn with: rm shift: type amount: n
	self logical: 16r200000 rd: rd rn: rn rm: rm shift: type amount: n
!
orn: rd with: rn with: rm shift: type amount: n
	self logical: 16r20200000 rd: rd rn: rn rm: rm shift: type amount: n
!
eon: rd with: rn with: rm shift: type amount: n
	self logical: 16r40200000 rd: rd rn: rn rm: rm shift: type amount: n
!
bics: rd with: rn with: rm shift: type amount: n
	self logical: 16r60200000 rd: rd rn: rn rm: rm shift: type amount: n
!
tst: rn with: rm shift: type amount: n
	self logical: 16r60000000 rd: (self zr: rn) rn: rn rm: rm shift: type amount: n
! !

!Arm64Assembler methodsFor: 'moves'!
moveWide: opc rd: rd imm: imm shift: s
	"opc: 0 movn, 16r40000000 movz, 16r60000000 movk; s: 0, 16, 32 or 48."
	((imm between: 0 and: 16rFFFF) and: [(s bitAnd: 15) = 0 and: [s between: 0 and: (self bits: rd) - 16]]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: (((16r12800000 bitOr: (self sf: rd)) bitOr: opc) bitOr: ((((s >> 4) asUInt64 << 21) bitOr: (imm asUInt64 << 5)) bitOr: (rd bitAnd: 31)))
!
movz: rd imm: imm shift: s
	self moveWide: 16r40000000 rd: rd imm: imm shift: s
!
movk: rd imm: imm shift: s
	self moveWide: 16r60000000 rd: rd imm: imm shift: s
!
movn: rd imm: imm shift: s
	self moveWide: 0 rd: rd imm: imm shift: s
!
mov: rd with: rm
	"A register move; to or from SP it is add #0."
	((self isSP: rd) or: [self isSP: rm])
		ifTrue: [self addSub: 0 rd: rd rn: rm imm: 0]
		ifFalse: [self logical: 16r20000000 rd: rd rn: (self zr: rd) rm: rm shift: SHIFT_LSL amount: 0]
!
mov: rd imm: value
	"The shortest sequence: movz or movn and movks, or orr with a logical immediate. A W register takes the low 32 bits."
	(value between: 0 and: 16rFFFF)
		ifTrue: [self moveWide: 16r40000000 rd: rd imm: value shift: 0]
		ifFalse: [self movImm: rd value: value asUInt64]
!
movImm: rd value: value
	<c: 'void asm_mov_imm(int64_t rd, uint64_t value)'>
	<export>
	| v halves zeros ones enc inverted first |
	v := (rd bitAnd: REG_W) = 0 ifTrue: [value] ifFalse: [value bitAnd: 16rFFFFFFFF].
	halves := (self bits: rd) >> 4.
	zeros := 0.
	ones := 0.
	0 to: halves - 1 do: [:i |
		| h |
		h := (v >> (16 * i)) bitAnd: 16rFFFF.
		h = 0 ifTrue: [zeros := zeros + 1].
		h = 16rFFFF ifTrue: [ones := ones + 1]].
	halves - (zeros max: ones) > 1 ifTrue: [
		enc := self logicalImmediate: v width: (self bits: rd).
		enc >= 0 ifTrue: [^self emit: ((16r32000000 bitOr: (self sf: rd)) bitOr: ((enc asUInt64 << 10) bitOr: (self rd: rd rn: 31)))]].
	"movn when more halfwords are all ones than all zeros"
	inverted := ones > zeros.
	first := true.
	0 to: halves - 1 do: [:i |
		| h |
		h := (v >> (16 * i)) bitAnd: 16rFFFF.
		(inverted ifTrue: [h ~= 16rFFFF] ifFalse: [h ~= 0]) ifTrue: [
			first
				ifTrue: [
					inverted
						ifTrue: [self movn: rd imm: (h bitXor: 16rFFFF) shift: 16 * i]
						ifFalse: [self movz: rd imm: h shift: 16 * i].
					first := false]
				ifFalse: [self movk: rd imm: h shift: 16 * i]]].
	first ifTrue: [
		inverted
			ifTrue: [self movn: rd imm: 0 shift: 0]
			ifFalse: [self movz: rd imm: 0 shift: 0]]
!
mov: rd imm64: value
	"Always movz and three movks, so that patchMov64At:value: can rewrite it."
	| v |
	v := value asUInt64.
	self movz: rd imm: (v bitAnd: 16rFFFF) shift: 0.
	self movk: rd imm: ((v >> 16) bitAnd: 16rFFFF) shift: 16.
	self movk: rd imm: ((v >> 32) bitAnd: 16rFFFF) shift: 32.
	self movk: rd imm: v >> 48 shift: 48
! !

!Arm64Assembler methodsFor: 'shifts and bitfields'!
bitfield: opc rd: rd rn: rn immr: r imms: s
	"opc: 0 sbfm, 16r20000000 bfm, 16r40000000 ubfm."
	| sf |
	sf := self sf: rd.
	((r between: 0 and: (self bits: rd) - 1) and: [s between: 0 and: (self bits: rd) - 1]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: (((16r13000000 bitOr: sf) bitOr: ((sf >> 9) bitOr: opc)) bitOr: (((r asUInt64 << 16) bitOr: (s asUInt64 << 10)) bitOr: (self rd: rd rn: rn)))
!
sbfm: rd with: rn immr: r imms: s
	self bitfield: 0 rd: rd rn: rn immr: r imms: s
!
bfm: rd with: rn immr: r imms: s
	self bitfield: 16r20000000 rd: rd rn: rn immr: r imms: s
!
ubfm: rd with: rn immr: r imms: s
	self bitfield: 16r40000000 rd: rd rn: rn immr: r imms: s
!
extract: opc rd: rd rn: rn lsb: lsb width: w
	"ubfx, sbfx, bfxil: w bits of rn from bit lsb."
	((lsb >= 0 and: [w >= 1]) and: [lsb + w <= (self bits: rd)]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self bitfield: opc rd: rd rn: rn immr: lsb imms: lsb + w - 1
!
insert: opc rd: rd rn: rn lsb: lsb width: w
	"ubfiz, sbfiz, bfi: the low w bits of rn to bit lsb."
	((lsb >= 0 and: [w >= 1]) and: [lsb + w <= (self bits: rd)]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self bitfield: opc rd: rd rn: rn immr: ((self bits: rd) - lsb bitAnd: (self bits: rd) - 1) imms: w - 1
!
ubfx: rd with: rn lsb: lsb width: w
	self extract: 16r40000000 rd: rd rn: rn lsb: lsb width: w
!
sbfx: rd with: rn lsb: lsb width: w
	self extract: 0 rd: rd rn: rn lsb: lsb width: w
!
bfxil: rd with: rn lsb: lsb width: w
	self extract: 16r20000000 rd: rd rn: rn lsb: lsb width: w
!
ubfiz: rd with: rn lsb: lsb width: w
	self insert: 16r40000000 rd: rd rn: rn lsb: lsb width: w
!
sbfiz: rd with: rn lsb: lsb width: w
	self insert: 0 rd: rd rn: rn lsb: lsb width: w
!
bfi: rd with: rn lsb: lsb width: w
	self insert: 16r20000000 rd: rd rn: rn lsb: lsb width: w
!
lsl: rd with: rn imm: s
	(s between: 0 and: (self bits: rd) - 1) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self bitfield: 16r40000000 rd: rd rn: rn immr: ((self bits: rd) - s bitAnd: (self bits: rd) - 1) imms: (self bits: rd) - 1 - s
!
lsr: rd with: rn imm: s
	self bitfield: 16r40000000 rd: rd rn: rn immr: s imms: (self bits: rd) - 1
!
asr: rd with: rn imm: s
	self bitfield: 0 rd: rd rn: rn immr: s imms: (self bits: rd) - 1
!
ror: rd with: rn imm: s
	"extr rd, rn, rn, #s"
	| sf |
	sf := self sf: rd.
	(s between: 0 and: (self bits: rd) - 1) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: (((16r13800000 bitOr: sf) bitOr: (sf >> 9)) bitOr: ((s asUInt64 << 10) bitOr: (self rd: rd rn: rn rm: rn)))
!
sxtb: rd with: rn
	self bitfield: 0 rd: rd rn: rn immr: 0 imms: 7
!
sxth: rd with: rn
	self bitfield: 0 rd: rd rn: rn immr: 0 imms: 15
!
sxtw: rd with: rn
	self bitfield: 0 rd: rd rn: rn immr: 0 imms: 31
!
uxtb: rd with: rn
	"A W register zero-extends into its X register."
	self bitfield: 16r40000000 rd: (rd bitOr: REG_W) rn: rn immr: 0 imms: 7
!
uxth: rd with: rn
	self bitfield: 16r40000000 rd: (rd bitOr: REG_W) rn: rn immr: 0 imms: 15
!
dataProcessing2: opcode rd: rd rn: rn rm: rm
	self emit: ((16r1AC00000 bitOr: (self sf: rd)) bitOr: ((opcode asUInt64 << 10) bitOr: (self rd: rd rn: rn rm: rm)))
!
lsl: rd with: rn with: rm
	self dataProcessing2: 8 rd: rd rn: rn rm: rm
!
lsr: rd with: rn with: rm
	self dataProcessing2: 9 rd: rd rn: rn rm: rm
!
asr: rd with: rn with: rm
	self dataProcessing2: 10 rd: rd rn: rn rm: rm
!
ror: rd with: rn with: rm
	self dataProcessing2: 11 rd: rd rn: rn rm: rm
!
clz: rd with: rn
	self emit: ((16r5AC01000 bitOr: (self sf: rd)) bitOr: (self rd: rd rn: rn))
! !

!Arm64Assembler methodsFor: 'multiply and divide'!
madd: rd with: rn with: rm add: ra
	"rd := ra + (rn * rm)"
	self emit: ((16r1B000000 bitOr: (self sf: rd)) bitOr: (((ra bitAnd: 31) asUInt64 << 10) bitOr: (self rd: rd rn: rn rm: rm)))
!
msub: rd with: rn with: rm sub: ra
	"rd := ra - (rn * rm)"
	self emit: ((16r1B008000 bitOr: (self sf: rd)) bitOr: (((ra bitAnd: 31) asUInt64 << 10) bitOr: (self rd: rd rn: rn rm: rm)))
!
mul: rd with: rn with: rm
	self madd: rd with: rn with: rm add: 31
!
smulh: rd with: rn with: rm
	"The high 64 bits of the signed 128-bit product."
	self emit: (16r9B407C00 bitOr: (self rd: rd rn: rn rm: rm))
!
umulh: rd with: rn with: rm
	self emit: (16r9BC07C00 bitOr: (self rd: rd rn: rn rm: rm))
!
sdiv: rd with: rn with: rm
	self dataProcessing2: 3 rd: rd rn: rn rm: rm
!
udiv: rd with: rn with: rm
	self dataProcessing2: 2 rd: rd rn: rn rm: rm
! !

!Arm64Assembler methodsFor: 'conditional select'!
select: op rd: rd rn: rn rm: rm cond: c
	"op: 0 csel, 16r400 csinc, 16r40000000 csinv, 16r40000400 csneg."
	self emit: (((16r1A800000 bitOr: (self sf: rd)) bitOr: op) bitOr: (((c bitAnd: 15) asUInt64 << 12) bitOr: (self rd: rd rn: rn rm: rm)))
!
csel: rd with: rn with: rm cond: c
	self select: 0 rd: rd rn: rn rm: rm cond: c
!
csinc: rd with: rn with: rm cond: c
	self select: 16r400 rd: rd rn: rn rm: rm cond: c
!
csinv: rd with: rn with: rm cond: c
	self select: 16r40000000 rd: rd rn: rn rm: rm cond: c
!
csneg: rd with: rn with: rm cond: c
	self select: 16r40000400 rd: rd rn: rn rm: rm cond: c
!
cset: rd cond: c
	"rd := c ? 1 : 0"
	self select: 16r400 rd: rd rn: 31 rm: 31 cond: (c bitXor: 1)
!
csetm: rd cond: c
	"rd := c ? -1 : 0"
	self select: 16r40000000 rd: rd rn: 31 rm: 31 cond: (c bitXor: 1)
!
cinc: rd with: rn cond: c
	self select: 16r400 rd: rd rn: rn rm: rn cond: (c bitXor: 1)
!
cinv: rd with: rn cond: c
	self select: 16r40000000 rd: rd rn: rn rm: rn cond: (c bitXor: 1)
!
cneg: rd with: rn cond: c
	self select: 16r40000400 rd: rd rn: rn rm: rn cond: (c bitXor: 1)
! !

!Arm64Assembler methodsFor: 'loads and stores'!
loadStore: bits rt: rt base: rn offset: off scale: s
	"The unsigned scaled offset form if off fits it, else the unscaled one (ldur, stur). bits: size, V and opc."
	((off >= 0 and: [(off bitAnd: (1 << s) - 1) = 0]) and: [off >> s <= 4095])
		ifTrue: [self emit: ((16r39000000 bitOr: bits) bitOr: (((off >> s) asUInt64 << 10) bitOr: (self rd: rt rn: rn)))]
		ifFalse: [self loadStore: (16r38000000 bitOr: bits) rt: rt base: rn imm9: off]
!
loadStore: bits rt: rt base: rn imm9: off
	"Unscaled (bits 16r38000000), post-index (16r38000400), pre-index (16r38000C00)."
	(off between: -256 and: 255) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: ((bits bitOr: ((off bitAnd: 511) asUInt64 << 12)) bitOr: (self rd: rt rn: rn))
!
loadStore: bits rt: rt base: rn index: rm extend: ext shift: n scale: s
	"Register offset: ext EXT_LSL (uxtx), EXT_UXTW, EXT_SXTW or EXT_SXTX; n 0 or the access size's log2."
	((n = 0 or: [n = s]) and: [(ext bitAnd: 2) ~= 0]) ifFalse: [^self fail: ASM_ERR_OPERAND].
	self emit: (((16r38200800 bitOr: bits) bitOr: (ext asUInt64 << 13)) bitOr: (((n = 0 ifTrue: [0] ifFalse: [16r1000]) bitOr: (self rd: rt rn: rn rm: rm))))
!
loadBits: rt
	"size, V and opc of ldr into rt."
	^(self isD: rt) ifTrue: [16rC4400000] ifFalse: [(rt bitAnd: REG_W) = 0 ifTrue: [16rC0400000] ifFalse: [16r80400000]]
!
storeBits: rt
	^(self isD: rt) ifTrue: [16rC4000000] ifFalse: [(rt bitAnd: REG_W) = 0 ifTrue: [16rC0000000] ifFalse: [16r80000000]]
!
scaleOf: rt
	^(rt bitAnd: REG_W) = 0 ifTrue: [3] ifFalse: [2]
!
signedBits: x w: w rt: rt
	"opc of a sign-extending load: to X or to W."
	^(rt bitAnd: REG_W) = 0 ifTrue: [x] ifFalse: [w]
!
ldr: rt base: rn offset: off
	self loadStore: (self loadBits: rt) rt: rt base: rn offset: off scale: (self scaleOf: rt)
!
ldr: rt base: rn preIndex: off
	self loadStore: (16r38000C00 bitOr: (self loadBits: rt)) rt: rt base: rn imm9: off
!
ldr: rt base: rn postIndex: off
	self loadStore: (16r38000400 bitOr: (self loadBits: rt)) rt: rt base: rn imm9: off
!
ldr: rt base: rn index: rm
	self loadStore: (self loadBits: rt) rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: (self scaleOf: rt)
!
ldr: rt base: rn index: rm extend: ext shift: n
	self loadStore: (self loadBits: rt) rt: rt base: rn index: rm extend: ext shift: n scale: (self scaleOf: rt)
!
ldur: rt base: rn offset: off
	self loadStore: (16r38000000 bitOr: (self loadBits: rt)) rt: rt base: rn imm9: off
!
str: rt base: rn offset: off
	self loadStore: (self storeBits: rt) rt: rt base: rn offset: off scale: (self scaleOf: rt)
!
str: rt base: rn preIndex: off
	self loadStore: (16r38000C00 bitOr: (self storeBits: rt)) rt: rt base: rn imm9: off
!
str: rt base: rn postIndex: off
	self loadStore: (16r38000400 bitOr: (self storeBits: rt)) rt: rt base: rn imm9: off
!
str: rt base: rn index: rm
	self loadStore: (self storeBits: rt) rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: (self scaleOf: rt)
!
str: rt base: rn index: rm extend: ext shift: n
	self loadStore: (self storeBits: rt) rt: rt base: rn index: rm extend: ext shift: n scale: (self scaleOf: rt)
!
stur: rt base: rn offset: off
	self loadStore: (16r38000000 bitOr: (self storeBits: rt)) rt: rt base: rn imm9: off
!
ldrb: rt base: rn offset: off
	self loadStore: 16r400000 rt: rt base: rn offset: off scale: 0
!
ldrb: rt base: rn preIndex: off
	self loadStore: 16r38400C00 rt: rt base: rn imm9: off
!
ldrb: rt base: rn postIndex: off
	self loadStore: 16r38400400 rt: rt base: rn imm9: off
!
ldrb: rt base: rn index: rm
	self loadStore: 16r400000 rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 0
!
ldrb: rt base: rn index: rm extend: ext shift: n
	self loadStore: 16r400000 rt: rt base: rn index: rm extend: ext shift: n scale: 0
!
ldurb: rt base: rn offset: off
	self loadStore: 16r38400000 rt: rt base: rn imm9: off
!
strb: rt base: rn offset: off
	self loadStore: 0 rt: rt base: rn offset: off scale: 0
!
strb: rt base: rn preIndex: off
	self loadStore: 16r38000C00 rt: rt base: rn imm9: off
!
strb: rt base: rn postIndex: off
	self loadStore: 16r38000400 rt: rt base: rn imm9: off
!
strb: rt base: rn index: rm
	self loadStore: 0 rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 0
!
strb: rt base: rn index: rm extend: ext shift: n
	self loadStore: 0 rt: rt base: rn index: rm extend: ext shift: n scale: 0
!
sturb: rt base: rn offset: off
	self loadStore: 16r38000000 rt: rt base: rn imm9: off
!
ldrh: rt base: rn offset: off
	self loadStore: 16r40400000 rt: rt base: rn offset: off scale: 1
!
ldrh: rt base: rn preIndex: off
	self loadStore: 16r78400C00 rt: rt base: rn imm9: off
!
ldrh: rt base: rn postIndex: off
	self loadStore: 16r78400400 rt: rt base: rn imm9: off
!
ldrh: rt base: rn index: rm
	self loadStore: 16r40400000 rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 1
!
ldrh: rt base: rn index: rm extend: ext shift: n
	self loadStore: 16r40400000 rt: rt base: rn index: rm extend: ext shift: n scale: 1
!
ldurh: rt base: rn offset: off
	self loadStore: 16r78400000 rt: rt base: rn imm9: off
!
strh: rt base: rn offset: off
	self loadStore: 16r40000000 rt: rt base: rn offset: off scale: 1
!
strh: rt base: rn preIndex: off
	self loadStore: 16r78000C00 rt: rt base: rn imm9: off
!
strh: rt base: rn postIndex: off
	self loadStore: 16r78000400 rt: rt base: rn imm9: off
!
strh: rt base: rn index: rm
	self loadStore: 16r40000000 rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 1
!
strh: rt base: rn index: rm extend: ext shift: n
	self loadStore: 16r40000000 rt: rt base: rn index: rm extend: ext shift: n scale: 1
!
sturh: rt base: rn offset: off
	self loadStore: 16r78000000 rt: rt base: rn imm9: off
!
ldrsb: rt base: rn offset: off
	self loadStore: (self signedBits: 16r800000 w: 16rC00000 rt: rt) rt: rt base: rn offset: off scale: 0
!
ldrsb: rt base: rn preIndex: off
	self loadStore: (16r38000C00 bitOr: (self signedBits: 16r800000 w: 16rC00000 rt: rt)) rt: rt base: rn imm9: off
!
ldrsb: rt base: rn postIndex: off
	self loadStore: (16r38000400 bitOr: (self signedBits: 16r800000 w: 16rC00000 rt: rt)) rt: rt base: rn imm9: off
!
ldrsb: rt base: rn index: rm
	self loadStore: (self signedBits: 16r800000 w: 16rC00000 rt: rt) rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 0
!
ldrsb: rt base: rn index: rm extend: ext shift: n
	self loadStore: (self signedBits: 16r800000 w: 16rC00000 rt: rt) rt: rt base: rn index: rm extend: ext shift: n scale: 0
!
ldursb: rt base: rn offset: off
	self loadStore: (16r38000000 bitOr: (self signedBits: 16r800000 w: 16rC00000 rt: rt)) rt: rt base: rn imm9: off
!
ldrsh: rt base: rn offset: off
	self loadStore: (self signedBits: 16r40800000 w: 16r40C00000 rt: rt) rt: rt base: rn offset: off scale: 1
!
ldrsh: rt base: rn preIndex: off
	self loadStore: (16r38000C00 bitOr: (self signedBits: 16r40800000 w: 16r40C00000 rt: rt)) rt: rt base: rn imm9: off
!
ldrsh: rt base: rn postIndex: off
	self loadStore: (16r38000400 bitOr: (self signedBits: 16r40800000 w: 16r40C00000 rt: rt)) rt: rt base: rn imm9: off
!
ldrsh: rt base: rn index: rm
	self loadStore: (self signedBits: 16r40800000 w: 16r40C00000 rt: rt) rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 1
!
ldrsh: rt base: rn index: rm extend: ext shift: n
	self loadStore: (self signedBits: 16r40800000 w: 16r40C00000 rt: rt) rt: rt base: rn index: rm extend: ext shift: n scale: 1
!
ldursh: rt base: rn offset: off
	self loadStore: (16r38000000 bitOr: (self signedBits: 16r40800000 w: 16r40C00000 rt: rt)) rt: rt base: rn imm9: off
!
ldrsw: rt base: rn offset: off
	self loadStore: 16r80800000 rt: rt base: rn offset: off scale: 2
!
ldrsw: rt base: rn preIndex: off
	self loadStore: 16rB8800C00 rt: rt base: rn imm9: off
!
ldrsw: rt base: rn postIndex: off
	self loadStore: 16rB8800400 rt: rt base: rn imm9: off
!
ldrsw: rt base: rn index: rm
	self loadStore: 16r80800000 rt: rt base: rn index: rm extend: EXT_LSL shift: 0 scale: 2
!
ldrsw: rt base: rn index: rm extend: ext shift: n
	self loadStore: 16r80800000 rt: rt base: rn index: rm extend: ext shift: n scale: 2
!
ldursw: rt base: rn offset: off
	self loadStore: 16rB8800000 rt: rt base: rn imm9: off
!
pair: bits rt: rt rt2: rt2 base: rn offset: off
	"ldp and stp; bits: addressing mode (16r00800000 post, 16r01000000 offset, 16r01800000 pre) and 16r400000 for a load."
	| s |
	s := self scaleOf: rt.
	((off bitAnd: (1 << s) - 1) = 0 and: [(off >> s) between: -64 and: 63]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: ((((16r28000000 bitOr: bits) bitOr: ((self isD: rt) ifTrue: [16r44000000] ifFalse: [(self sf: rt)]))
		bitOr: (((off >> s) bitAnd: 127) asUInt64 << 15)) bitOr: (((rt2 bitAnd: 31) asUInt64 << 10) bitOr: (self rd: rt rn: rn)))
!
ldp: rt with: rt2 base: rn offset: off
	self pair: 16r01400000 rt: rt rt2: rt2 base: rn offset: off
!
ldp: rt with: rt2 base: rn preIndex: off
	self pair: 16r01C00000 rt: rt rt2: rt2 base: rn offset: off
!
ldp: rt with: rt2 base: rn postIndex: off
	self pair: 16r00C00000 rt: rt rt2: rt2 base: rn offset: off
!
stp: rt with: rt2 base: rn offset: off
	self pair: 16r01000000 rt: rt rt2: rt2 base: rn offset: off
!
stp: rt with: rt2 base: rn preIndex: off
	self pair: 16r01800000 rt: rt rt2: rt2 base: rn offset: off
!
stp: rt with: rt2 base: rn postIndex: off
	self pair: 16r00800000 rt: rt rt2: rt2 base: rn offset: off
!
ldr: rt label: aLabel
	"Load from a pc-relative literal."
	self emit: (((self isD: rt) ifTrue: [16r5C000000] ifFalse: [(rt bitAnd: REG_W) = 0 ifTrue: [16r58000000] ifFalse: [16r18000000]])
		bitOr: (((self offsetTo: (self targetOf: aLabel) bits: 19) asUInt64 << 5) bitOr: (rt bitAnd: 31)))
! !

!Arm64Assembler methodsFor: 'pc-relative'!
adr: rd label: aLabel
	| off |
	off := ((self targetOf: aLabel) - asmPc) asInt64.
	(off between: -16r100000 and: 16rFFFFF) ifFalse: [^self fail: ASM_ERR_RANGE].
	self emit: ((16r10000000 bitOr: ((off bitAnd: 3) asUInt64 << 29)) bitOr: ((((off >> 2) bitAnd: 16r7FFFF) asUInt64 << 5) bitOr: (rd bitAnd: 31)))
!
adrp: rd label: aLabel
	"rd := the 4 KB page of aLabel"
	| off |
	off := (((self targetOf: aLabel) bitClear: 16rFFF) - (asmPc bitClear: 16rFFF)) asInt64 >> 12.
	(off between: -16r100000 and: 16rFFFFF) ifFalse: [^self fail: ASM_ERR_RANGE].
	self emit: ((16r90000000 bitOr: ((off bitAnd: 3) asUInt64 << 29)) bitOr: ((((off >> 2) bitAnd: 16r7FFFF) asUInt64 << 5) bitOr: (rd bitAnd: 31)))
! !

!Arm64Assembler methodsFor: 'branches'!
b: aLabel
	self emit: (16r14000000 bitOr: (self offsetTo: (self targetOf: aLabel) bits: 26))
!
bl: aLabel
	self emit: (16r94000000 bitOr: (self offsetTo: (self targetOf: aLabel) bits: 26))
!
b: aLabel if: c
	self emit: (16r54000000 bitOr: (((self offsetTo: (self targetOf: aLabel) bits: 19) asUInt64 << 5) bitOr: (c bitAnd: 15)))
!
cbz: rt to: aLabel
	self emit: ((16r34000000 bitOr: (self sf: rt)) bitOr: (((self offsetTo: (self targetOf: aLabel) bits: 19) asUInt64 << 5) bitOr: (rt bitAnd: 31)))
!
cbnz: rt to: aLabel
	self emit: ((16r35000000 bitOr: (self sf: rt)) bitOr: (((self offsetTo: (self targetOf: aLabel) bits: 19) asUInt64 << 5) bitOr: (rt bitAnd: 31)))
!
testBranch: op rt: rt bit: n to: aLabel
	(n between: 0 and: 63) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: (((op bitOr: ((n >> 5) asUInt64 << 31)) bitOr: ((n bitAnd: 31) asUInt64 << 19))
		bitOr: (((self offsetTo: (self targetOf: aLabel) bits: 14) asUInt64 << 5) bitOr: (rt bitAnd: 31)))
!
tbz: rt bit: n to: aLabel
	self testBranch: 16r36000000 rt: rt bit: n to: aLabel
!
tbnz: rt bit: n to: aLabel
	self testBranch: 16r37000000 rt: rt bit: n to: aLabel
!
br: rn
	self emit: (16rD61F0000 bitOr: ((rn bitAnd: 31) asUInt64 << 5))
!
blr: rn
	self emit: (16rD63F0000 bitOr: ((rn bitAnd: 31) asUInt64 << 5))
!
ret
	self emit: 16rD65F03C0
!
ret: rn
	self emit: (16rD65F0000 bitOr: ((rn bitAnd: 31) asUInt64 << 5))
! !

!Arm64Assembler methodsFor: 'system'!
nop
	self emit: 16rD503201F
!
brk: imm
	self emit: (16rD4200000 bitOr: ((imm bitAnd: 16rFFFF) asUInt64 << 5))
!
dmb: option
	self emit: (16rD50330BF bitOr: ((option bitAnd: 15) asUInt64 << 8))
!
dsb: option
	self emit: (16rD503309F bitOr: ((option bitAnd: 15) asUInt64 << 8))
!
isb
	self emit: 16rD5033FDF
! !

!Arm64Assembler methodsFor: 'floating point'!
fmov: rd with: rn
	"Between D registers, or between a D and an X register."
	(self isD: rd)
		ifTrue: [self emit: (((self isD: rn) ifTrue: [16r1E604000] ifFalse: [16r9E670000]) bitOr: (self rd: rd rn: rn))]
		ifFalse: [self emit: (16r9E660000 bitOr: (self rd: rd rn: rn))]
!
fmov: rd imm: aDouble
	| enc |
	enc := self fmovImmediate: aDouble.
	enc < 0 ifTrue: [^self fail: ASM_ERR_IMMEDIATE].
	self emit: ((16r1E601000 bitOr: (enc asUInt64 << 13)) bitOr: (rd bitAnd: 31))
!
fadd: rd with: rn with: rm
	self emit: (16r1E602800 bitOr: (self rd: rd rn: rn rm: rm))
!
fsub: rd with: rn with: rm
	self emit: (16r1E603800 bitOr: (self rd: rd rn: rn rm: rm))
!
fmul: rd with: rn with: rm
	self emit: (16r1E600800 bitOr: (self rd: rd rn: rn rm: rm))
!
fdiv: rd with: rn with: rm
	self emit: (16r1E601800 bitOr: (self rd: rd rn: rn rm: rm))
!
fsqrt: rd with: rn
	self emit: (16r1E61C000 bitOr: (self rd: rd rn: rn))
!
fneg: rd with: rn
	self emit: (16r1E614000 bitOr: (self rd: rd rn: rn))
!
fabs: rd with: rn
	self emit: (16r1E60C000 bitOr: (self rd: rd rn: rn))
!
frintn: rd with: rn
	"Round to nearest, ties to even."
	self emit: (16r1E644000 bitOr: (self rd: rd rn: rn))
!
frintp: rd with: rn
	"Round toward +infinity."
	self emit: (16r1E64C000 bitOr: (self rd: rd rn: rn))
!
frintm: rd with: rn
	"Round toward -infinity."
	self emit: (16r1E654000 bitOr: (self rd: rd rn: rn))
!
frintz: rd with: rn
	"Round toward zero."
	self emit: (16r1E65C000 bitOr: (self rd: rd rn: rn))
!
fcmp: rn with: rm
	self emit: (16r1E602000 bitOr: (self rd: 0 rn: rn rm: rm))
!
fcmpZero: rn
	self emit: (16r1E602008 bitOr: ((rn bitAnd: 31) asUInt64 << 5))
!
fcsel: rd with: rn with: rm cond: c
	self emit: ((16r1E600C00 bitOr: ((c bitAnd: 15) asUInt64 << 12)) bitOr: (self rd: rd rn: rn rm: rm))
!
scvtf: rd with: rn
	"The signed integer in rn (W or X) as a double."
	self emit: ((16r1E620000 bitOr: (self sf: rn)) bitOr: (self rd: rd rn: rn))
!
ucvtf: rd with: rn
	self emit: ((16r1E630000 bitOr: (self sf: rn)) bitOr: (self rd: rd rn: rn))
!
fcvtzs: rd with: rn
	"The double in rn rounded toward zero to a signed integer in rd (W or X), saturated."
	self emit: ((16r1E780000 bitOr: (self sf: rd)) bitOr: (self rd: rd rn: rn))
! !

!Arm64Assembler methodsFor: 'encoders'!
logicalImmediate: value width: width
	"N:immr:imms of value as a logical immediate of width (32 or 64) bits, or -1 if it does not encode."
	<c: 'int32_t asm_logical_immediate(uint64_t value, int32_t width)'>
	<export>
	| v size half mask elem ones pattern rot r |
	v := value.
	width = 32 ifTrue: [
		v := value bitAnd: 16rFFFFFFFF.
		v := v bitOr: v << 32].
	(v = 0 or: [v = 16rFFFFFFFFFFFFFFFF]) ifTrue: [^-1].
	"the smallest element that repeats"
	size := 64.
	half := 32.
	[size > 2 and: [(v bitAnd: 16rFFFFFFFFFFFFFFFF >> (64 - half)) = ((v >> half) bitAnd: 16rFFFFFFFFFFFFFFFF >> (64 - half))]] whileTrue: [
		size := half.
		half := half >> 1].
	mask := 16rFFFFFFFFFFFFFFFF >> (64 - size).
	elem := v bitAnd: mask.
	ones := 0.
	0 to: size - 1 do: [:i | ((elem >> i) bitAnd: 1) = 1 ifTrue: [ones := ones + 1]].
	"elem must be a run of ones rotated right"
	pattern := 16rFFFFFFFFFFFFFFFF >> (64 - ones).
	rot := elem.
	r := 0.
	[r < size and: [rot ~= pattern]] whileTrue: [
		rot := ((rot >> 1) bitOr: ((rot bitAnd: 1) << (size - 1))) bitAnd: mask.
		r := r + 1].
	r = size ifTrue: [^-1].
	^((((size = 64 ifTrue: [4096] ifFalse: [0])) bitOr: ((size - r bitAnd: size - 1) << 6)) bitOr: ((128 - (2 * size) bitOr: ones - 1) bitAnd: 63)) asInt32
!
fmovImmediate: aDouble
	"The 8-bit immediate of fmov for aDouble, or -1: ±(16..31)/16 * 2^(-3..4)."
	<c: 'int32_t asm_fmov_immediate(double d)'>
	<export>
	| b exp |
	b := self bitsOfDouble: aDouble.
	(b bitAnd: 16rFFFFFFFFFFFF) = 0 ifFalse: [^-1].
	exp := (b >> 54) bitAnd: 16rFF.
	((((b >> 62) bitAnd: 1) = 1 and: [exp = 0]) or: [((b >> 62) bitAnd: 1) = 0 and: [exp = 16rFF]]) ifFalse: [^-1].
	^(((b >> 63) << 7) bitOr: (((exp bitAnd: 1) << 6) bitOr: ((b >> 48) bitAnd: 16r3F))) asInt32
! !

!Arm64Assembler methodsFor: 'patching'!
patchBranchAt: site to: target
	"Point the pc-relative instruction at site (b, bl, b.cond, cbz, cbnz, tbz, tbnz, ldr literal, adr, adrp) to target; answer whether it reaches."
	<c: 'bool asm_patch_branch(uint64_t site, uint64_t target)'>
	<export>
	| w off |
	w := self uint32At: site.
	off := (target - site) asInt64.
	(w bitAnd: 16r9F000000) = 16r90000000 ifTrue: [
		off := ((target bitClear: 16rFFF) - (site bitClear: 16rFFF)) asInt64 >> 12.
		^self patch: site word: (w bitAnd: 16r9F00001F) offset: off].
	(w bitAnd: 16r9F000000) = 16r10000000 ifTrue: [^self patch: site word: (w bitAnd: 16r9F00001F) offset: off].
	(off bitAnd: 3) = 0 ifFalse: [^self patchFailed].
	off := off >> 2.
	(w bitAnd: 16r7C000000) = 16r14000000 ifTrue: [
		(off between: -16r2000000 and: 16r1FFFFFF) ifFalse: [^self patchFailed].
		self uint32At: site put: ((w bitAnd: 16rFC000000) bitOr: (off bitAnd: 16r3FFFFFF)).
		^true].
	(w bitAnd: 16r7E000000) = 16r36000000 ifTrue: [
		(off between: -16r2000 and: 16r1FFF) ifFalse: [^self patchFailed].
		self uint32At: site put: ((w bitAnd: 16rFFF8001F) bitOr: ((off bitAnd: 16r3FFF) asUInt64 << 5)).
		^true].
	((w bitAnd: 16rFF000010) = 16r54000000 or: [(w bitAnd: 16r7E000000) = 16r34000000 or: [(w bitAnd: 16r3B000000) = 16r18000000]]) ifTrue: [
		(off between: -16r40000 and: 16r3FFFF) ifFalse: [^self patchFailed].
		self uint32At: site put: ((w bitAnd: 16rFF00001F) bitOr: ((off bitAnd: 16r7FFFF) asUInt64 << 5)).
		^true].
	^self patchFailed
!
patch: site word: w offset: off
	"adr and adrp: off (bytes or pages) into immlo and immhi."
	(off between: -16r100000 and: 16rFFFFF) ifFalse: [^self patchFailed].
	self uint32At: site put: ((w bitOr: ((off bitAnd: 3) asUInt64 << 29)) bitOr: (((off >> 2) bitAnd: 16r7FFFF) asUInt64 << 5)).
	^true
!
patchFailed
	self fail: ASM_ERR_RANGE.
	^false
!
branchTargetAt: site
	"The target of the pc-relative instruction at site, 0 if it is none."
	<c: 'uint64_t asm_branch_target(uint64_t site)'>
	<export>
	| w |
	w := self uint32At: site.
	((w bitAnd: 16r1F000000) = 16r10000000) ifTrue: [
		| imm |
		imm := ((((w >> 5) bitAnd: 16r7FFFF) asUInt64 << 2) bitOr: ((w >> 29) bitAnd: 3)) asInt64.
		imm := (imm bitXor: 16r100000) - 16r100000.
		(w bitAnd: 16r80000000) = 0 ifTrue: [^site + imm].
		^(site bitClear: 16rFFF) + (imm * 4096)].
	(w bitAnd: 16r7C000000) = 16r14000000 ifTrue: [^site + ((((w bitAnd: 16r3FFFFFF) asInt64 bitXor: 16r2000000) - 16r2000000) * 4)].
	(w bitAnd: 16r7E000000) = 16r36000000 ifTrue: [^site + (((((w >> 5) bitAnd: 16r3FFF) asInt64 bitXor: 16r2000) - 16r2000) * 4)].
	((w bitAnd: 16rFF000010) = 16r54000000 or: [(w bitAnd: 16r7E000000) = 16r34000000 or: [(w bitAnd: 16r3B000000) = 16r18000000]]) ifTrue: [
		^site + (((((w >> 5) bitAnd: 16r7FFFF) asInt64 bitXor: 16r40000) - 16r40000) * 4)].
	^0
!
patchMov64At: site value: value
	"Rewrite the constant of the mov:imm64: sequence at site."
	<c: 'void asm_patch_mov64(uint64_t site, uint64_t value)'>
	<export>
	0 to: 3 do: [:i |
		self uint32At: site + (4 * i) put: (((self uint32At: site + (4 * i)) bitAnd: 16rFFE0001F) bitOr: (((value >> (16 * i)) bitAnd: 16rFFFF) << 5))]
!
mov64At: site
	"The constant of the mov:imm64: sequence at site."
	<c: 'uint64_t asm_mov64(uint64_t site)'>
	<export>
	| v |
	v := 0 asUInt64.
	0 to: 3 do: [:i | v := v bitOr: (((self uint32At: site + (4 * i)) >> 5) bitAnd: 16rFFFF) asUInt64 << (16 * i)].
	^v
! !
