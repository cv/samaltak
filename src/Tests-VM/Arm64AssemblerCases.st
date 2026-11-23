Arm64Module subclass: #Arm64AssemblerCases
	instanceVariableNames: 'asm libc posix buffer'
	classVariableNames: ''
	package: 'Tests-VM'!

Arm64AssemblerCases comment: 'The instruction forms Arm64AssemblerTest checks, each with the source the system assembler gets (instructions separated by |; tools/arm64-reference.py assembles them into Arm64Reference). A Lowtalk program: it prints each case''s source and the words the assembler emits for it, simulated and as C.'!

!Arm64AssemblerCases class methodsFor: 'declaring'!
declarations
	^#((asm Arm64Assembler) (libc LibC) (posix Posix) (buffer uint64_t))
! !

!Arm64AssemblerCases methodsFor: 'running'!
main: argc argv: argv
	<function>
	<var: #argc type: 'int'>
	<var: #argv type: 'char **'>
	"a page-aligned buffer, for adrp"
	buffer := self cCoerce: (posix mmap: self null length: 65536 protection: (posix PROT_READ bitOr: posix PROT_WRITE) flags: (posix MAP_PRIVATE bitOr: posix MAP_ANON) file: -1 offset: 0) to: 'uint64_t'.
	self addSub; logical; moves; shifts; multiply; conditional; bitfield; loadStore; pairs; pcRelative; branches; system; floatingPoint.
	^0
!
case: aString emit: aBlock
	asm beginAt: buffer limit: buffer + 65536.
	aBlock value.
	self print: aString error: asm finish
!
print: source error: error
	"source: the words emitted, or source: error n"
	<function>
	libc printf: '%s:' with: source.
	error = ASM_OK
		ifTrue: [0 to: (asm codeSize asInt64 quo: 4) - 1 do: [:i | libc printf: ' %08x' with: (self uint32At: buffer + (4 * i))]]
		ifFalse: [libc printf: ' error %d' with: error].
	libc printf: '
'
! !

!Arm64AssemblerCases methodsFor: 'cases'!
addSub
	<function>
	self case: 'add x0, x1, #12' emit: [asm add: X0 with: X1 imm: 12].
	self case: 'add w3, w4, #4095' emit: [asm add: W3 with: W4 imm: 4095].
	self case: 'add x0, x1, #1, lsl #12' emit: [asm add: X0 with: X1 imm: 4096].
	self case: 'add x5, x6, #0xfff, lsl #12' emit: [asm add: X5 with: X6 imm: 16rFFF000].
	self case: 'sub x0, x1, #5' emit: [asm add: X0 with: X1 imm: -5].
	self case: 'add sp, sp, #32' emit: [asm add: SP with: SP imm: 32].
	self case: 'sub sp, sp, #0x10' emit: [asm sub: SP with: SP imm: 16].
	self case: 'add x29, sp, #0' emit: [asm add: X29 with: SP imm: 0].
	self case: 'add wsp, w1, #3' emit: [asm add: WSP with: W1 imm: 3].
	self case: 'sub w0, w1, #1, lsl #12' emit: [asm sub: W0 with: W1 imm: 4096].
	self case: 'sub x2, x3, #7' emit: [asm sub: X2 with: X3 imm: 7].
	self case: 'adds x0, x1, #1' emit: [asm adds: X0 with: X1 imm: 1].
	self case: 'adds w0, w1, #2' emit: [asm adds: W0 with: W1 imm: 2].
	self case: 'subs x0, x1, #1' emit: [asm subs: X0 with: X1 imm: 1].
	self case: 'subs w9, w10, #0xfff' emit: [asm subs: W9 with: W10 imm: 4095].
	self case: 'adds x0, sp, #8' emit: [asm adds: X0 with: SP imm: 8].
	self case: 'cmp x0, #0' emit: [asm cmp: X0 imm: 0].
	self case: 'cmp w1, #42' emit: [asm cmp: W1 imm: 42].
	self case: 'cmp sp, #16' emit: [asm cmp: SP imm: 16].
	self case: 'cmn x3, #5' emit: [asm cmp: X3 imm: -5].
	self case: 'cmn w3, #1, lsl #12' emit: [asm cmn: W3 imm: 4096].
	self case: 'add x0, x1, x2' emit: [asm add: X0 with: X1 with: X2].
	self case: 'add w0, w1, w2' emit: [asm add: W0 with: W1 with: W2].
	self case: 'add x0, x1, x2, lsl #3' emit: [asm add: X0 with: X1 with: X2 shift: SHIFT_LSL amount: 3].
	self case: 'add x0, x1, x2, lsr #63' emit: [asm add: X0 with: X1 with: X2 shift: SHIFT_LSR amount: 63].
	self case: 'add w0, w1, w2, asr #31' emit: [asm add: W0 with: W1 with: W2 shift: SHIFT_ASR amount: 31].
	self case: 'sub x0, x1, x2' emit: [asm sub: X0 with: X1 with: X2].
	self case: 'sub w7, w8, w9, lsl #2' emit: [asm sub: W7 with: W8 with: W9 shift: SHIFT_LSL amount: 2].
	self case: 'adds x0, x1, x2' emit: [asm adds: X0 with: X1 with: X2].
	self case: 'adds w0, w1, w2, lsr #1' emit: [asm adds: W0 with: W1 with: W2 shift: SHIFT_LSR amount: 1].
	self case: 'subs x0, x1, x2' emit: [asm subs: X0 with: X1 with: X2].
	self case: 'subs x0, x1, x2, asr #4' emit: [asm subs: X0 with: X1 with: X2 shift: SHIFT_ASR amount: 4].
	self case: 'cmp x0, x1' emit: [asm cmp: X0 with: X1].
	self case: 'cmp w0, w1, lsl #3' emit: [asm cmp: W0 with: W1 shift: SHIFT_LSL amount: 3].
	self case: 'cmn x0, x1' emit: [asm cmn: X0 with: X1].
	self case: 'cmn w4, w5, asr #2' emit: [asm cmn: W4 with: W5 shift: SHIFT_ASR amount: 2].
	self case: 'neg x0, x1' emit: [asm neg: X0 with: X1].
	self case: 'neg w0, w1, lsl #2' emit: [asm sub: W0 with: WZR with: W1 shift: SHIFT_LSL amount: 2].
	self case: 'negs x3, x4' emit: [asm negs: X3 with: X4].
	self case: 'add x0, sp, x1' emit: [asm add: X0 with: SP with: X1].
	self case: 'add sp, sp, x1' emit: [asm add: SP with: SP with: X1].
	self case: 'add w0, wsp, w1' emit: [asm add: W0 with: WSP with: W1].
	self case: 'sub sp, sp, x2' emit: [asm sub: SP with: SP with: X2].
	self case: 'add x0, x1, w2, sxtw' emit: [asm add: X0 with: X1 with: W2 extend: EXT_SXTW amount: 0].
	self case: 'add x0, x1, w2, uxtw #2' emit: [asm add: X0 with: X1 with: W2 extend: EXT_UXTW amount: 2].
	self case: 'add x0, x1, w2, uxtb' emit: [asm add: X0 with: X1 with: W2 extend: EXT_UXTB amount: 0].
	self case: 'add x0, x1, w2, sxth #1' emit: [asm add: X0 with: X1 with: W2 extend: EXT_SXTH amount: 1].
	self case: 'add x0, x1, x2, sxtx #4' emit: [asm add: X0 with: X1 with: X2 extend: EXT_SXTX amount: 4].
	self case: 'add x0, x1, x2, uxtx #3' emit: [asm add: X0 with: X1 with: X2 extend: EXT_UXTX amount: 3].
	self case: 'add sp, x1, x2, lsl #3' emit: [asm add: SP with: X1 with: X2 extend: EXT_UXTX amount: 3].
	self case: 'add w0, w1, w2, uxtb' emit: [asm add: W0 with: W1 with: W2 extend: EXT_UXTB amount: 0].
	self case: 'add w0, w1, w2, sxth #2' emit: [asm add: W0 with: W1 with: W2 extend: EXT_SXTH amount: 2].
	self case: 'sub x0, x1, w2, sxtw #3' emit: [asm sub: X0 with: X1 with: W2 extend: EXT_SXTW amount: 3].
	self case: 'adds x0, x1, w2, uxtw' emit: [asm adds: X0 with: X1 with: W2 extend: EXT_UXTW amount: 0].
	self case: 'subs x0, sp, x2, uxtx #1' emit: [asm subs: X0 with: SP with: X2 extend: EXT_UXTX amount: 1].
	self case: 'cmp x0, w1, sxtw' emit: [asm cmp: X0 with: W1 extend: EXT_SXTW amount: 0].
	self case: 'cmp sp, x1' emit: [asm cmp: SP with: X1].
	self case: 'cmn x0, w1, uxtb #1' emit: [asm cmn: X0 with: W1 extend: EXT_UXTB amount: 1]
!
logical
	<function>
	self case: 'and x0, x1, #0xff' emit: [asm and: X0 with: X1 imm: 255].
	self case: 'and w0, w1, #0xff' emit: [asm and: W0 with: W1 imm: 255].
	self case: 'and x0, x1, #0xfffffffffffffff0' emit: [asm and: X0 with: X1 imm: -16].
	self case: 'and w2, w3, #0x80000001' emit: [asm and: W2 with: W3 imm: 16r80000001].
	self case: 'and x0, x1, #0x5555555555555555' emit: [asm and: X0 with: X1 imm: 16r5555555555555555].
	self case: 'and sp, x1, #0xfffffffffffffff0' emit: [asm and: SP with: X1 imm: -16].
	self case: 'orr x0, x1, #0x1' emit: [asm orr: X0 with: X1 imm: 1].
	self case: 'orr w0, w1, #0xf0f0f0f0' emit: [asm orr: W0 with: W1 imm: 16rF0F0F0F0].
	self case: 'eor x0, x1, #0x7' emit: [asm eor: X0 with: X1 imm: 7].
	self case: 'eor w5, w6, #0x3fffffff' emit: [asm eor: W5 with: W6 imm: 16r3FFFFFFF].
	self case: 'ands x0, x1, #0x8000000000000000' emit: [asm ands: X0 with: X1 imm: 16r8000000000000000].
	self case: 'ands w0, w1, #0x1' emit: [asm ands: W0 with: W1 imm: 1].
	self case: 'and x0, x1, #0xfffffffffffffffe' emit: [asm bic: X0 with: X1 imm: 1].
	self case: 'tst x0, #0x7' emit: [asm tst: X0 imm: 7].
	self case: 'tst w1, #0x1' emit: [asm tst: W1 imm: 1].
	self case: 'and x0, x1, x2' emit: [asm and: X0 with: X1 with: X2].
	self case: 'and w0, w1, w2, lsl #3' emit: [asm and: W0 with: W1 with: W2 shift: SHIFT_LSL amount: 3].
	self case: 'and x0, x1, x2, ror #7' emit: [asm and: X0 with: X1 with: X2 shift: SHIFT_ROR amount: 7].
	self case: 'orr x0, x1, x2' emit: [asm orr: X0 with: X1 with: X2].
	self case: 'orr x0, x1, x2, lsr #12' emit: [asm orr: X0 with: X1 with: X2 shift: SHIFT_LSR amount: 12].
	self case: 'orr w9, w10, w11, asr #1' emit: [asm orr: W9 with: W10 with: W11 shift: SHIFT_ASR amount: 1].
	self case: 'eor x0, x1, x2' emit: [asm eor: X0 with: X1 with: X2].
	self case: 'eor w0, w1, w2, ror #31' emit: [asm eor: W0 with: W1 with: W2 shift: SHIFT_ROR amount: 31].
	self case: 'ands x0, x1, x2' emit: [asm ands: X0 with: X1 with: X2].
	self case: 'ands x0, x1, x2, lsl #63' emit: [asm ands: X0 with: X1 with: X2 shift: SHIFT_LSL amount: 63].
	self case: 'bic x0, x1, x2' emit: [asm bic: X0 with: X1 with: X2].
	self case: 'bic w0, w1, w2, lsr #4' emit: [asm bic: W0 with: W1 with: W2 shift: SHIFT_LSR amount: 4].
	self case: 'bics x0, x1, x2' emit: [asm bics: X0 with: X1 with: X2].
	self case: 'orn x0, x1, x2' emit: [asm orn: X0 with: X1 with: X2].
	self case: 'eon w0, w1, w2, lsl #1' emit: [asm eon: W0 with: W1 with: W2 shift: SHIFT_LSL amount: 1].
	self case: 'mvn x0, x1' emit: [asm mvn: X0 with: X1].
	self case: 'mvn w0, w1' emit: [asm mvn: W0 with: W1].
	self case: 'tst x0, x1' emit: [asm tst: X0 with: X1].
	self case: 'tst w0, w1, lsr #2' emit: [asm tst: W0 with: W1 shift: SHIFT_LSR amount: 2]
!
moves
	<function>
	self case: 'mov x0, x1' emit: [asm mov: X0 with: X1].
	self case: 'mov w0, w1' emit: [asm mov: W0 with: W1].
	self case: 'mov x0, sp' emit: [asm mov: X0 with: SP].
	self case: 'mov sp, x29' emit: [asm mov: SP with: X29].
	self case: 'mov wsp, w3' emit: [asm mov: WSP with: W3].
	self case: 'mov x0, xzr' emit: [asm mov: X0 with: XZR].
	self case: 'movz x0, #0' emit: [asm mov: X0 imm: 0].
	self case: 'movz w0, #0' emit: [asm mov: W0 imm: 0].
	self case: 'movz x0, #42' emit: [asm mov: X0 imm: 42].
	self case: 'movz x0, #0xffff' emit: [asm mov: X0 imm: 16rFFFF].
	self case: 'movz x0, #1, lsl #16' emit: [asm mov: X0 imm: 16r10000].
	self case: 'movz x0, #0x1234, lsl #48' emit: [asm mov: X0 imm: 16r1234000000000000].
	self case: 'movz w0, #0xffff, lsl #16' emit: [asm mov: W0 imm: 16rFFFF0000].
	self case: 'movn x0, #0' emit: [asm mov: X0 imm: -1].
	self case: 'movn w0, #0' emit: [asm mov: W0 imm: 16rFFFFFFFF].
	self case: 'movn w0, #0' emit: [asm mov: W0 imm: -1].
	self case: 'movn x0, #41' emit: [asm mov: X0 imm: -42].
	self case: 'movn x0, #0xffff, lsl #16' emit: [asm mov: X0 imm: 16rFFFFFFFF0000FFFF].
	self case: 'movn w1, #0x1233' emit: [asm mov: W1 imm: 16rFFFFEDCC].
	self case: 'movz x0, #0x5678|movk x0, #0x1234, lsl #16' emit: [asm mov: X0 imm: 16r12345678].
	self case: 'movz x0, #0xdef0|movk x0, #0x9abc, lsl #16|movk x0, #0x5678, lsl #32|movk x0, #0x1234, lsl #48' emit: [asm mov: X0 imm: 16r123456789ABCDEF0].
	self case: 'movz x3, #0x2, lsl #16|movk x3, #0x1, lsl #48' emit: [asm mov: X3 imm: 16r0001000000020000].
	self case: 'orr x3, xzr, #0x1000000010000' emit: [asm mov: X3 imm: 16r0001000000010000].
	self case: 'movn x0, #0x1234|movk x0, #0x5678, lsl #32' emit: [asm mov: X0 imm: 16rFFFF5678FFFFEDCB].
	self case: 'movz w2, #0x5678|movk w2, #0x1234, lsl #16' emit: [asm mov: W2 imm: 16r12345678].
	self case: 'orr x0, xzr, #0x5555555555555555' emit: [asm mov: X0 imm: 16r5555555555555555].
	self case: 'orr w0, wzr, #0xff00ff' emit: [asm mov: W0 imm: 16rFF00FF].
	self case: 'orr x0, xzr, #0xffff00000000ffff' emit: [asm mov: X0 imm: 16rFFFF00000000FFFF].
	self case: 'movz x0, #0x1234, lsl #16' emit: [asm movz: X0 imm: 16r1234 shift: 16].
	self case: 'movz w0, #0' emit: [asm movz: W0 imm: 0 shift: 0].
	self case: 'movz x0, #0, lsl #32' emit: [asm movz: X0 imm: 0 shift: 32].
	self case: 'movk x0, #0xbeef, lsl #32' emit: [asm movk: X0 imm: 16rBEEF shift: 32].
	self case: 'movk w0, #0xbeef' emit: [asm movk: W0 imm: 16rBEEF shift: 0].
	self case: 'movn x0, #0x7, lsl #48' emit: [asm movn: X0 imm: 7 shift: 48].
	self case: 'movn w0, #0xffff' emit: [asm movn: W0 imm: 16rFFFF shift: 0].
	self case: 'movz x9, #0x7788|movk x9, #0x5566, lsl #16|movk x9, #0x3344, lsl #32|movk x9, #0x1122, lsl #48' emit: [asm mov: X9 imm64: 16r1122334455667788].
	self case: 'movz x16, #0x0|movk x16, #0x0, lsl #16|movk x16, #0x0, lsl #32|movk x16, #0x0, lsl #48' emit: [asm mov: X16 imm64: 0]
!
shifts
	<function>
	self case: 'lsl x0, x1, #3' emit: [asm lsl: X0 with: X1 imm: 3].
	self case: 'lsl x0, x1, #63' emit: [asm lsl: X0 with: X1 imm: 63].
	self case: 'lsl w0, w1, #1' emit: [asm lsl: W0 with: W1 imm: 1].
	self case: 'lsr x0, x1, #3' emit: [asm lsr: X0 with: X1 imm: 3].
	self case: 'lsr w0, w1, #31' emit: [asm lsr: W0 with: W1 imm: 31].
	self case: 'asr x0, x1, #1' emit: [asm asr: X0 with: X1 imm: 1].
	self case: 'asr w0, w1, #7' emit: [asm asr: W0 with: W1 imm: 7].
	self case: 'ror x0, x1, #13' emit: [asm ror: X0 with: X1 imm: 13].
	self case: 'ror w0, w1, #31' emit: [asm ror: W0 with: W1 imm: 31].
	self case: 'lsl x0, x1, x2' emit: [asm lsl: X0 with: X1 with: X2].
	self case: 'lsl w0, w1, w2' emit: [asm lsl: W0 with: W1 with: W2].
	self case: 'lsr x0, x1, x2' emit: [asm lsr: X0 with: X1 with: X2].
	self case: 'asr x0, x1, x2' emit: [asm asr: X0 with: X1 with: X2].
	self case: 'asr w3, w4, w5' emit: [asm asr: W3 with: W4 with: W5].
	self case: 'ror x0, x1, x2' emit: [asm ror: X0 with: X1 with: X2]
!
multiply
	<function>
	self case: 'mul x0, x1, x2' emit: [asm mul: X0 with: X1 with: X2].
	self case: 'mul w0, w1, w2' emit: [asm mul: W0 with: W1 with: W2].
	self case: 'madd x0, x1, x2, x3' emit: [asm madd: X0 with: X1 with: X2 add: X3].
	self case: 'madd w0, w1, w2, w3' emit: [asm madd: W0 with: W1 with: W2 add: W3].
	self case: 'msub x0, x1, x2, x3' emit: [asm msub: X0 with: X1 with: X2 sub: X3].
	self case: 'mneg x0, x1, x2' emit: [asm msub: X0 with: X1 with: X2 sub: XZR].
	self case: 'smulh x0, x1, x2' emit: [asm smulh: X0 with: X1 with: X2].
	self case: 'umulh x5, x6, x7' emit: [asm umulh: X5 with: X6 with: X7].
	self case: 'sdiv x0, x1, x2' emit: [asm sdiv: X0 with: X1 with: X2].
	self case: 'sdiv w0, w1, w2' emit: [asm sdiv: W0 with: W1 with: W2].
	self case: 'udiv x0, x1, x2' emit: [asm udiv: X0 with: X1 with: X2].
	self case: 'udiv w0, w1, w2' emit: [asm udiv: W0 with: W1 with: W2].
	self case: 'clz x0, x1' emit: [asm clz: X0 with: X1].
	self case: 'clz w0, w1' emit: [asm clz: W0 with: W1]
!
conditional
	<function>
	self case: 'csel x0, x1, x2, eq' emit: [asm csel: X0 with: X1 with: X2 cond: COND_EQ].
	self case: 'csel w0, w1, w2, lt' emit: [asm csel: W0 with: W1 with: W2 cond: COND_LT].
	self case: 'csinc x0, x1, x2, ne' emit: [asm csinc: X0 with: X1 with: X2 cond: COND_NE].
	self case: 'csinc x0, x1, x1, hs' emit: [asm csinc: X0 with: X1 with: X1 cond: COND_HS].
	self case: 'csinv w0, w1, w2, gt' emit: [asm csinv: W0 with: W1 with: W2 cond: COND_GT].
	self case: 'csinv x0, x1, x1, vs' emit: [asm csinv: X0 with: X1 with: X1 cond: COND_VS].
	self case: 'csneg x0, x1, x2, le' emit: [asm csneg: X0 with: X1 with: X2 cond: COND_LE].
	self case: 'csel x0, x1, x2, al' emit: [asm csel: X0 with: X1 with: X2 cond: COND_AL].
	self case: 'cset x0, eq' emit: [asm cset: X0 cond: COND_EQ].
	self case: 'cset w0, lo' emit: [asm cset: W0 cond: COND_LO].
	self case: 'cset x3, mi' emit: [asm cset: X3 cond: COND_MI].
	self case: 'csetm x0, ne' emit: [asm csetm: X0 cond: COND_NE].
	self case: 'csetm w0, ge' emit: [asm csetm: W0 cond: COND_GE].
	self case: 'ccmp x0, x1, #0, eq' emit: [asm ccmp: X0 with: X1 nzcv: 0 cond: COND_EQ].
	self case: 'ccmp w3, w30, #15, ne' emit: [asm ccmp: W3 with: W30 nzcv: 15 cond: COND_NE].
	self case: 'ccmp x30, xzr, #6, hs' emit: [asm ccmp: X30 with: XZR nzcv: 6 cond: COND_HS].
	self case: 'ccmn x2, x3, #4, lt' emit: [asm ccmn: X2 with: X3 nzcv: 4 cond: COND_LT].
	self case: 'ccmp x4, #31, #2, gt' emit: [asm ccmp: X4 imm: 31 nzcv: 2 cond: COND_GT].
	self case: 'ccmp w5, #0, #8, al' emit: [asm ccmp: W5 imm: 0 nzcv: 8 cond: COND_AL].
	self case: 'ccmn x6, #7, #0, ls' emit: [asm ccmp: X6 imm: -7 nzcv: 0 cond: COND_LS].
	self case: 'ccmn w7, #1, #10, mi' emit: [asm ccmn: W7 imm: 1 nzcv: 10 cond: COND_MI].
	self case: 'ccmp x8, #3, #9, vs' emit: [asm ccmn: X8 imm: -3 nzcv: 9 cond: COND_VS].
	self case: 'cneg x0, x1, mi' emit: [asm cneg: X0 with: X1 cond: COND_MI].
	self case: 'cneg w0, w1, ls' emit: [asm cneg: W0 with: W1 cond: COND_LS].
	self case: 'cinc x0, x1, pl' emit: [asm cinc: X0 with: X1 cond: COND_PL].
	self case: 'cinv x0, x1, hi' emit: [asm cinv: X0 with: X1 cond: COND_HI]
!
bitfield
	<function>
	self case: 'ubfx x0, x1, #3, #5' emit: [asm ubfx: X0 with: X1 lsb: 3 width: 5].
	self case: 'ubfx w0, w1, #1, #30' emit: [asm ubfx: W0 with: W1 lsb: 1 width: 30].
	self case: 'ubfx x0, x1, #0, #32' emit: [asm ubfx: X0 with: X1 lsb: 0 width: 32].
	self case: 'sbfx x0, x1, #4, #8' emit: [asm sbfx: X0 with: X1 lsb: 4 width: 8].
	self case: 'sbfx w0, w1, #0, #3' emit: [asm sbfx: W0 with: W1 lsb: 0 width: 3].
	self case: 'ubfiz x0, x1, #3, #61' emit: [asm ubfiz: X0 with: X1 lsb: 3 width: 61].
	self case: 'ubfiz x0, x1, #2, #32' emit: [asm ubfiz: X0 with: X1 lsb: 2 width: 32].
	self case: 'ubfiz w0, w1, #8, #4' emit: [asm ubfiz: W0 with: W1 lsb: 8 width: 4].
	self case: 'sbfiz x0, x1, #1, #32' emit: [asm sbfiz: X0 with: X1 lsb: 1 width: 32].
	self case: 'bfi x0, x1, #8, #16' emit: [asm bfi: X0 with: X1 lsb: 8 width: 16].
	self case: 'bfi w0, w1, #1, #3' emit: [asm bfi: W0 with: W1 lsb: 1 width: 3].
	self case: 'bfxil x0, x1, #4, #4' emit: [asm bfxil: X0 with: X1 lsb: 4 width: 4].
	self case: 'ubfm x0, x1, #5, #10' emit: [asm ubfm: X0 with: X1 immr: 5 imms: 10].
	self case: 'sbfm w0, w1, #31, #30' emit: [asm sbfm: W0 with: W1 immr: 31 imms: 30].
	self case: 'bfm x0, x1, #60, #2' emit: [asm bfm: X0 with: X1 immr: 60 imms: 2].
	self case: 'sxtb x0, w1' emit: [asm sxtb: X0 with: W1].
	self case: 'sxtb w0, w1' emit: [asm sxtb: W0 with: W1].
	self case: 'sxth x0, w1' emit: [asm sxth: X0 with: W1].
	self case: 'sxtw x0, w1' emit: [asm sxtw: X0 with: W1].
	self case: 'uxtb w0, w1' emit: [asm uxtb: W0 with: W1].
	self case: 'uxth w0, w1' emit: [asm uxth: W0 with: W1]
!
loadStore
	<function>
	self case: 'ldr x0, [x1]' emit: [asm ldr: X0 base: X1 offset: 0].
	self case: 'ldr x0, [x1, #8]' emit: [asm ldr: X0 base: X1 offset: 8].
	self case: 'ldr x0, [sp, #32760]' emit: [asm ldr: X0 base: SP offset: 32760].
	self case: 'ldur x0, [x1, #-8]' emit: [asm ldr: X0 base: X1 offset: -8].
	self case: 'ldur x0, [x1, #3]' emit: [asm ldr: X0 base: X1 offset: 3].
	self case: 'ldur x0, [x1, #255]' emit: [asm ldur: X0 base: X1 offset: 255].
	self case: 'ldur x0, [x1, #-256]' emit: [asm ldur: X0 base: X1 offset: -256].
	self case: 'ldur x0, [x1, #16]' emit: [asm ldur: X0 base: X1 offset: 16].
	self case: 'ldr w0, [x1, #4]' emit: [asm ldr: W0 base: X1 offset: 4].
	self case: 'ldr w0, [x1, #16380]' emit: [asm ldr: W0 base: X1 offset: 16380].
	self case: 'ldur w0, [x1, #-4]' emit: [asm ldr: W0 base: X1 offset: -4].
	self case: 'ldr x0, [x1, #16]!!' emit: [asm ldr: X0 base: X1 preIndex: 16].
	self case: 'ldr x0, [x1], #-16' emit: [asm ldr: X0 base: X1 postIndex: -16].
	self case: 'ldr w0, [sp, #-4]!!' emit: [asm ldr: W0 base: SP preIndex: -4].
	self case: 'ldr w0, [x1], #255' emit: [asm ldr: W0 base: X1 postIndex: 255].
	self case: 'ldr x0, [x1, x2]' emit: [asm ldr: X0 base: X1 index: X2].
	self case: 'ldr x0, [x1, x2, lsl #3]' emit: [asm ldr: X0 base: X1 index: X2 extend: EXT_LSL shift: 3].
	self case: 'ldr x0, [x1, w2, sxtw]' emit: [asm ldr: X0 base: X1 index: W2 extend: EXT_SXTW shift: 0].
	self case: 'ldr x0, [x1, w2, uxtw #3]' emit: [asm ldr: X0 base: X1 index: W2 extend: EXT_UXTW shift: 3].
	self case: 'ldr x0, [x1, x2, sxtx]' emit: [asm ldr: X0 base: X1 index: X2 extend: EXT_SXTX shift: 0].
	self case: 'ldr w0, [x1, x2, lsl #2]' emit: [asm ldr: W0 base: X1 index: X2 extend: EXT_LSL shift: 2].
	self case: 'ldr w0, [sp, w2, sxtw #2]' emit: [asm ldr: W0 base: SP index: W2 extend: EXT_SXTW shift: 2].
	self case: 'str x0, [x1]' emit: [asm str: X0 base: X1 offset: 0].
	self case: 'str x0, [x1, #24]' emit: [asm str: X0 base: X1 offset: 24].
	self case: 'stur x0, [x1, #-24]' emit: [asm str: X0 base: X1 offset: -24].
	self case: 'stur w5, [x6, #1]' emit: [asm stur: W5 base: X6 offset: 1].
	self case: 'str w0, [x1, #8]' emit: [asm str: W0 base: X1 offset: 8].
	self case: 'str x30, [sp, #-16]!!' emit: [asm str: X30 base: SP preIndex: -16].
	self case: 'str x0, [x1], #8' emit: [asm str: X0 base: X1 postIndex: 8].
	self case: 'str xzr, [x1, x2, lsl #3]' emit: [asm str: XZR base: X1 index: X2 extend: EXT_LSL shift: 3].
	self case: 'str wzr, [x1, w2, uxtw]' emit: [asm str: WZR base: X1 index: W2 extend: EXT_UXTW shift: 0].
	self case: 'ldrb w0, [x1]' emit: [asm ldrb: W0 base: X1 offset: 0].
	self case: 'ldrb w0, [x1, #4095]' emit: [asm ldrb: W0 base: X1 offset: 4095].
	self case: 'ldurb w0, [x1, #-1]' emit: [asm ldrb: W0 base: X1 offset: -1].
	self case: 'ldrb w0, [x1, #1]!!' emit: [asm ldrb: W0 base: X1 preIndex: 1].
	self case: 'ldrb w0, [x1], #1' emit: [asm ldrb: W0 base: X1 postIndex: 1].
	self case: 'ldrb w0, [x1, x2]' emit: [asm ldrb: W0 base: X1 index: X2].
	self case: 'ldrb w0, [x1, w2, sxtw]' emit: [asm ldrb: W0 base: X1 index: W2 extend: EXT_SXTW shift: 0].
	self case: 'strb w0, [x1, #7]' emit: [asm strb: W0 base: X1 offset: 7].
	self case: 'sturb w0, [x1, #-7]' emit: [asm strb: W0 base: X1 offset: -7].
	self case: 'strb w0, [x1], #-1' emit: [asm strb: W0 base: X1 postIndex: -1].
	self case: 'strb w0, [x1, x2]' emit: [asm strb: W0 base: X1 index: X2].
	self case: 'ldrh w0, [x1, #2]' emit: [asm ldrh: W0 base: X1 offset: 2].
	self case: 'ldrh w0, [x1, #8190]' emit: [asm ldrh: W0 base: X1 offset: 8190].
	self case: 'ldurh w0, [x1, #1]' emit: [asm ldrh: W0 base: X1 offset: 1].
	self case: 'ldrh w0, [x1, #-2]!!' emit: [asm ldrh: W0 base: X1 preIndex: -2].
	self case: 'ldrh w0, [x1, x2, lsl #1]' emit: [asm ldrh: W0 base: X1 index: X2 extend: EXT_LSL shift: 1].
	self case: 'strh w0, [x1, #6]' emit: [asm strh: W0 base: X1 offset: 6].
	self case: 'sturh w0, [x1, #-6]' emit: [asm strh: W0 base: X1 offset: -6].
	self case: 'strh w0, [x1], #2' emit: [asm strh: W0 base: X1 postIndex: 2].
	self case: 'strh w0, [x1, w2, uxtw #1]' emit: [asm strh: W0 base: X1 index: W2 extend: EXT_UXTW shift: 1].
	self case: 'ldrsb x0, [x1]' emit: [asm ldrsb: X0 base: X1 offset: 0].
	self case: 'ldrsb w0, [x1, #3]' emit: [asm ldrsb: W0 base: X1 offset: 3].
	self case: 'ldursb x0, [x1, #-3]' emit: [asm ldrsb: X0 base: X1 offset: -3].
	self case: 'ldrsb x0, [x1, #1]!!' emit: [asm ldrsb: X0 base: X1 preIndex: 1].
	self case: 'ldrsb w0, [x1, x2]' emit: [asm ldrsb: W0 base: X1 index: X2].
	self case: 'ldrsh x0, [x1, #2]' emit: [asm ldrsh: X0 base: X1 offset: 2].
	self case: 'ldrsh w0, [x1, #4]' emit: [asm ldrsh: W0 base: X1 offset: 4].
	self case: 'ldursh w0, [x1, #-1]' emit: [asm ldrsh: W0 base: X1 offset: -1].
	self case: 'ldrsh x0, [x1], #2' emit: [asm ldrsh: X0 base: X1 postIndex: 2].
	self case: 'ldrsh x0, [x1, x2, lsl #1]' emit: [asm ldrsh: X0 base: X1 index: X2 extend: EXT_LSL shift: 1].
	self case: 'ldrsw x0, [x1, #4]' emit: [asm ldrsw: X0 base: X1 offset: 4].
	self case: 'ldrsw x0, [x1, #16380]' emit: [asm ldrsw: X0 base: X1 offset: 16380].
	self case: 'ldursw x0, [x1, #-4]' emit: [asm ldrsw: X0 base: X1 offset: -4].
	self case: 'ldrsw x0, [x1, #-4]!!' emit: [asm ldrsw: X0 base: X1 preIndex: -4].
	self case: 'ldrsw x0, [x1, w2, sxtw #2]' emit: [asm ldrsw: X0 base: X1 index: W2 extend: EXT_SXTW shift: 2].
	self case: 'ldursb w0, [x1, #5]' emit: [asm ldursb: W0 base: X1 offset: 5].
	self case: 'ldursh x0, [x1, #6]' emit: [asm ldursh: X0 base: X1 offset: 6].
	self case: 'ldursw x0, [x1, #8]' emit: [asm ldursw: X0 base: X1 offset: 8].
	self case: 'ldurb w0, [x1, #9]' emit: [asm ldurb: W0 base: X1 offset: 9].
	self case: 'ldurh w0, [x1, #10]' emit: [asm ldurh: W0 base: X1 offset: 10].
	self case: 'sturb w0, [x1, #11]' emit: [asm sturb: W0 base: X1 offset: 11].
	self case: 'sturh w0, [x1, #12]' emit: [asm sturh: W0 base: X1 offset: 12].
	self case: 'ldr d0, [x1]' emit: [asm ldr: D0 base: X1 offset: 0].
	self case: 'ldr d1, [x2, #8]' emit: [asm ldr: D1 base: X2 offset: 8].
	self case: 'ldr d31, [sp, #32760]' emit: [asm ldr: D31 base: SP offset: 32760].
	self case: 'ldur d1, [x2, #-8]' emit: [asm ldr: D1 base: X2 offset: -8].
	self case: 'ldr d1, [x2, #16]!!' emit: [asm ldr: D1 base: X2 preIndex: 16].
	self case: 'ldr d1, [x2], #-8' emit: [asm ldr: D1 base: X2 postIndex: -8].
	self case: 'ldr d1, [x2, x3, lsl #3]' emit: [asm ldr: D1 base: X2 index: X3 extend: EXT_LSL shift: 3].
	self case: 'ldr d1, [x2, w3, sxtw]' emit: [asm ldr: D1 base: X2 index: W3 extend: EXT_SXTW shift: 0].
	self case: 'str d0, [x1]' emit: [asm str: D0 base: X1 offset: 0].
	self case: 'str d7, [x1, #64]' emit: [asm str: D7 base: X1 offset: 64].
	self case: 'stur d7, [x1, #-64]' emit: [asm str: D7 base: X1 offset: -64].
	self case: 'str d8, [sp, #-16]!!' emit: [asm str: D8 base: SP preIndex: -16].
	self case: 'str d8, [sp], #16' emit: [asm str: D8 base: SP postIndex: 16].
	self case: 'str d8, [x0, x1]' emit: [asm str: D8 base: X0 index: X1].
	self case: 'stur d8, [x0, #3]' emit: [asm stur: D8 base: X0 offset: 3].
	self case: 'ldur d8, [x0, #4]' emit: [asm ldur: D8 base: X0 offset: 4]
!
pairs
	<function>
	self case: 'ldp x0, x1, [x2]' emit: [asm ldp: X0 with: X1 base: X2 offset: 0].
	self case: 'ldp x0, x1, [x2, #16]' emit: [asm ldp: X0 with: X1 base: X2 offset: 16].
	self case: 'ldp x0, x1, [x2, #504]' emit: [asm ldp: X0 with: X1 base: X2 offset: 504].
	self case: 'ldp x0, x1, [x2, #-512]' emit: [asm ldp: X0 with: X1 base: X2 offset: -512].
	self case: 'ldp x29, x30, [sp], #16' emit: [asm ldp: X29 with: X30 base: SP postIndex: 16].
	self case: 'ldp x29, x30, [sp, #-16]!!' emit: [asm ldp: X29 with: X30 base: SP preIndex: -16].
	self case: 'ldp w0, w1, [x2, #8]' emit: [asm ldp: W0 with: W1 base: X2 offset: 8].
	self case: 'ldp w0, w1, [x2, #-256]' emit: [asm ldp: W0 with: W1 base: X2 offset: -256].
	self case: 'ldp w0, w1, [x2], #4' emit: [asm ldp: W0 with: W1 base: X2 postIndex: 4].
	self case: 'ldp w0, w1, [x2, #252]!!' emit: [asm ldp: W0 with: W1 base: X2 preIndex: 252].
	self case: 'stp x29, x30, [sp, #-16]!!' emit: [asm stp: X29 with: X30 base: SP preIndex: -16].
	self case: 'stp x19, x20, [sp, #16]' emit: [asm stp: X19 with: X20 base: SP offset: 16].
	self case: 'stp x0, x1, [x2], #-32' emit: [asm stp: X0 with: X1 base: X2 postIndex: -32].
	self case: 'stp w0, w1, [x2]' emit: [asm stp: W0 with: W1 base: X2 offset: 0].
	self case: 'stp w0, wzr, [x2, #-4]!!' emit: [asm stp: W0 with: WZR base: X2 preIndex: -4].
	self case: 'stp xzr, xzr, [x2, #8]' emit: [asm stp: XZR with: XZR base: X2 offset: 8].
	self case: 'ldp d0, d1, [x2]' emit: [asm ldp: D0 with: D1 base: X2 offset: 0].
	self case: 'ldp d8, d9, [sp, #-512]' emit: [asm ldp: D8 with: D9 base: SP offset: -512].
	self case: 'ldp d8, d9, [sp], #16' emit: [asm ldp: D8 with: D9 base: SP postIndex: 16].
	self case: 'ldp d8, d9, [sp, #32]!!' emit: [asm ldp: D8 with: D9 base: SP preIndex: 32].
	self case: 'stp d8, d9, [sp, #-16]!!' emit: [asm stp: D8 with: D9 base: SP preIndex: -16].
	self case: 'stp d14, d15, [sp, #504]' emit: [asm stp: D14 with: D15 base: SP offset: 504].
	self case: 'stp d0, d1, [x3], #-16' emit: [asm stp: D0 with: D1 base: X3 postIndex: -16]
!
pcRelative
	<function>
	self case: 'ldr x0, .+8' emit: [asm ldr: X0 label: (asm labelAt: asm pc + 8)].
	self case: 'ldr x1, .-4' emit: [asm ldr: X1 label: (asm labelAt: asm pc - 4)].
	self case: 'ldr w1, .+1048572' emit: [asm ldr: W1 label: (asm labelAt: asm pc + 1048572)].
	self case: 'ldr d2, .-1048576' emit: [asm ldr: D2 label: (asm labelAt: asm pc - 1048576)].
	self case: 'adr x0, .+0' emit: [asm adr: X0 label: (asm labelAt: asm pc)].
	self case: 'adr x0, .+5' emit: [asm adr: X0 label: (asm labelAt: asm pc + 5)].
	self case: 'adr x3, .-3' emit: [asm adr: X3 label: (asm labelAt: asm pc - 3)].
	self case: 'adr x0, .+1048575' emit: [asm adr: X0 label: (asm labelAt: asm pc + 1048575)].
	self case: 'adr x0, .-1048576' emit: [asm adr: X0 label: (asm labelAt: asm pc - 1048576)].
	self case: 'adrp x0, #0x3000' emit: [asm adrp: X0 label: (asm labelAt: asm pc + 16r3000)].
	self case: 'adrp x1, #-0x1000' emit: [asm adrp: X1 label: (asm labelAt: asm pc - 16r1000)].
	self case: 'adrp x2, #0' emit: [asm adrp: X2 label: (asm labelAt: asm pc + 16rFFF)].
	self case: 'adrp x0, #0xfffff000' emit: [asm adrp: X0 label: (asm labelAt: asm pc + 16rFFFFF000)].
	self case: 'adrp x0, #-0x100000000' emit: [asm adrp: X0 label: (asm labelAt: (asm pc - 16r100000000) asUInt64)]
!
branches
	<function>
	self case: 'b .+8' emit: [asm b: (asm labelAt: asm pc + 8)].
	self case: 'b .-4' emit: [asm b: (asm labelAt: asm pc - 4)].
	self case: 'b .+0' emit: [asm b: (asm labelAt: asm pc)].
	self case: 'b .+134217724' emit: [asm b: (asm labelAt: asm pc + 134217724)].
	self case: 'b .-134217728' emit: [asm b: (asm labelAt: asm pc - 134217728)].
	self case: 'bl .+64' emit: [asm bl: (asm labelAt: asm pc + 64)].
	self case: 'bl .-64' emit: [asm bl: (asm labelAt: asm pc - 64)].
	self case: 'b.eq .+8' emit: [asm b: (asm labelAt: asm pc + 8) if: COND_EQ].
	self case: 'b.ne .-8' emit: [asm b: (asm labelAt: asm pc - 8) if: COND_NE].
	self case: 'b.hs .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_HS].
	self case: 'b.lo .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_LO].
	self case: 'b.mi .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_MI].
	self case: 'b.pl .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_PL].
	self case: 'b.vs .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_VS].
	self case: 'b.vc .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_VC].
	self case: 'b.hi .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_HI].
	self case: 'b.ls .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_LS].
	self case: 'b.ge .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_GE].
	self case: 'b.lt .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_LT].
	self case: 'b.gt .+1048572' emit: [asm b: (asm labelAt: asm pc + 1048572) if: COND_GT].
	self case: 'b.le .-1048576' emit: [asm b: (asm labelAt: asm pc - 1048576) if: COND_LE].
	self case: 'b.al .+4' emit: [asm b: (asm labelAt: asm pc + 4) if: COND_AL].
	self case: 'cbz x0, .+12' emit: [asm cbz: X0 to: (asm labelAt: asm pc + 12)].
	self case: 'cbz w3, .-12' emit: [asm cbz: W3 to: (asm labelAt: asm pc - 12)].
	self case: 'cbnz x0, .+1048572' emit: [asm cbnz: X0 to: (asm labelAt: asm pc + 1048572)].
	self case: 'cbnz w30, .-1048576' emit: [asm cbnz: W30 to: (asm labelAt: asm pc - 1048576)].
	self case: 'tbz w0, #0, .+8' emit: [asm tbz: W0 bit: 0 to: (asm labelAt: asm pc + 8)].
	self case: 'tbz x1, #63, .-8' emit: [asm tbz: X1 bit: 63 to: (asm labelAt: asm pc - 8)].
	self case: 'tbz x1, #32, .+32764' emit: [asm tbz: X1 bit: 32 to: (asm labelAt: asm pc + 32764)].
	self case: 'tbnz w2, #31, .-32768' emit: [asm tbnz: W2 bit: 31 to: (asm labelAt: asm pc - 32768)].
	self case: 'tbnz x3, #40, .+4' emit: [asm tbnz: X3 bit: 40 to: (asm labelAt: asm pc + 4)].
	self case: 'tbnz w3, #5, .+4' emit: [asm tbnz: X3 bit: 5 to: (asm labelAt: asm pc + 4)].
	self case: 'br x16' emit: [asm br: X16].
	self case: 'blr x9' emit: [asm blr: X9].
	self case: 'ret' emit: [asm ret].
	self case: 'ret x1' emit: [asm ret: X1]
!
system
	<function>
	self case: 'nop' emit: [asm nop].
	self case: 'brk #0' emit: [asm brk: 0].
	self case: 'brk #0xffff' emit: [asm brk: 16rFFFF].
	self case: 'dmb ish' emit: [asm dmb: BARRIER_ISH].
	self case: 'dmb ishld' emit: [asm dmb: BARRIER_ISHLD].
	self case: 'dmb ishst' emit: [asm dmb: BARRIER_ISHST].
	self case: 'dmb sy' emit: [asm dmb: BARRIER_SY].
	self case: 'dmb ld' emit: [asm dmb: BARRIER_LD].
	self case: 'dsb sy' emit: [asm dsb: BARRIER_SY].
	self case: 'dsb ish' emit: [asm dsb: BARRIER_ISH].
	self case: 'isb' emit: [asm isb]
!
floatingPoint
	<function>
	self case: 'fmov d0, d1' emit: [asm fmov: D0 with: D1].
	self case: 'fmov d31, d30' emit: [asm fmov: D31 with: D30].
	self case: 'fmov d0, x1' emit: [asm fmov: D0 with: X1].
	self case: 'fmov x0, d1' emit: [asm fmov: X0 with: D1].
	self case: 'fmov d2, xzr' emit: [asm fmov: D2 with: XZR].
	self case: 'fmov d0, #1.0' emit: [asm fmov: D0 imm: 1.0].
	self case: 'fmov d0, #-2.0' emit: [asm fmov: D0 imm: -2.0].
	self case: 'fmov d0, #0.5' emit: [asm fmov: D0 imm: 0.5].
	self case: 'fmov d0, #0.125' emit: [asm fmov: D0 imm: 0.125].
	self case: 'fmov d0, #31.0' emit: [asm fmov: D0 imm: 31.0].
	self case: 'fmov d0, #1.9375' emit: [asm fmov: D0 imm: 1.9375].
	self case: 'fmov d7, #-0.1875' emit: [asm fmov: D7 imm: -0.1875].
	self case: 'fmov d0, #10.0' emit: [asm fmov: D0 imm: 10.0].
	self case: 'fadd d0, d1, d2' emit: [asm fadd: D0 with: D1 with: D2].
	self case: 'fsub d0, d1, d2' emit: [asm fsub: D0 with: D1 with: D2].
	self case: 'fmul d3, d4, d5' emit: [asm fmul: D3 with: D4 with: D5].
	self case: 'fdiv d29, d30, d31' emit: [asm fdiv: D29 with: D30 with: D31].
	self case: 'fsqrt d0, d1' emit: [asm fsqrt: D0 with: D1].
	self case: 'fneg d0, d1' emit: [asm fneg: D0 with: D1].
	self case: 'fabs d0, d1' emit: [asm fabs: D0 with: D1].
	self case: 'fcmp d0, d1' emit: [asm fcmp: D0 with: D1].
	self case: 'fcmp d8, #0.0' emit: [asm fcmpZero: D8].
	self case: 'fcsel d0, d1, d2, gt' emit: [asm fcsel: D0 with: D1 with: D2 cond: COND_GT].
	self case: 'fcsel d0, d1, d2, vs' emit: [asm fcsel: D0 with: D1 with: D2 cond: COND_VS].
	self case: 'scvtf d0, x1' emit: [asm scvtf: D0 with: X1].
	self case: 'scvtf d0, w1' emit: [asm scvtf: D0 with: W1].
	self case: 'ucvtf d0, x1' emit: [asm ucvtf: D0 with: X1].
	self case: 'ucvtf d0, w1' emit: [asm ucvtf: D0 with: W1].
	self case: 'fcvtzs x0, d1' emit: [asm fcvtzs: X0 with: D1].
	self case: 'fcvtzs w0, d1' emit: [asm fcvtzs: W0 with: D1].
	self case: 'frintm d0, d1' emit: [asm frintm: D0 with: D1].
	self case: 'frintp d0, d1' emit: [asm frintp: D0 with: D1].
	self case: 'frintz d0, d1' emit: [asm frintz: D0 with: D1].
	self case: 'frintn d0, d1' emit: [asm frintn: D0 with: D1].
	"ccmn #0: an addition's flags (C clear), not ccmp #0's"
	self case: 'ccmn x6, #0, #2, hs' emit: [asm ccmn: X6 imm: 0 nzcv: 2 cond: COND_HS].
	self case: 'rev w0, w1' emit: [asm rev: W0 with: W1].
	self case: 'rev x16, x17' emit: [asm rev: X16 with: X17]
! !
