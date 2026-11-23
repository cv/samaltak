Arm64Module subclass: #AsmLoweringFuzz
	instanceVariableNames: 'asm cache libc state memory seed skipped regs dregs dump kind failedKind'
	classVariableNames: 'FZ_NREGS'
	package: 'Tests-VM'!

AsmLoweringFuzz comment: 'A Lowtalk program for AsmLoweringTest: random programs of the instructions the code generators use (arm64''s, written through JitAssembler), run on random registers and memory. Built for arm64 they run as arm64 code; built for x86-64 Amd64Assembler emits them as x86 code. Each program prints its registers, D registers and memory afterwards: the two CPUs must print the same (tools/lowering-check.sh runs the arm64 build under qemu-aarch64). A program one assembler rejects prints skip (Amd64Assembler: flags its code destroyed before an instruction read them).

	program seed count [length [dump]]: with dump, program number dump''s code goes to the file code.bin.'!

!AsmLoweringFuzz class methodsFor: 'declaring'!
declarations
	^#((asm JitAssembler) (cache CodeCache) (libc LibC) (state 'uint64_t[32]') (memory 'uint64_t[64]') (seed uint64_t) (skipped int32_t) (regs 'int32_t[16]') (dregs 'int32_t[4]') (dump int32_t) (kind int32_t) (failedKind int32_t))
!
initialize
	FZ_NREGS := 14
! !

!AsmLoweringFuzz methodsFor: 'running'!
main: argc argv: argv
	<function>
	<var: #argc type: 'int'>
	<var: #argv type: 'char **'>
	| n len |
	argc < 3 ifTrue: [
		libc printf: 'usage: program seed count [length]
'.
		^2].
	(cache openWithSize: 4194304) ifFalse: [
		libc printf: 'no code cache
'.
		^1].
	seed := (libc atol: (argv at: 1)) asUInt64 bitOr: 1.
	n := libc atoi: (argv at: 2).
	len := argc > 3 ifTrue: [libc atoi: (argv at: 3)] ifFalse: [12].
	dump := argc > 4 ifTrue: [libc atoi: (argv at: 4)] ifFalse: [-1].
	regs at: 0 put: X0. regs at: 1 put: X1. regs at: 2 put: X2. regs at: 3 put: X3. regs at: 4 put: X4. regs at: 5 put: X5.
	regs at: 6 put: X9. regs at: 7 put: X10. regs at: 8 put: X11. regs at: 9 put: X16. regs at: 10 put: X17.
	regs at: 11 put: X12. regs at: 12 put: X13. regs at: 13 put: X14.
	dregs at: 0 put: D0. dregs at: 1 put: D1. dregs at: 2 put: D2. dregs at: 3 put: D3.
	skipped := 0.
	0 to: n - 1 do: [:i | self run: i length: len].
	libc printf: 'skipped=%d
' with: skipped.
	^0
!
nextRandom
	"xorshift64*"
	<function>
	<returns: 'uint64_t'>
	seed := seed bitXor: seed >> 12.
	seed := seed bitXor: seed << 25.
	seed := seed bitXor: seed >> 27.
	^seed * 2685821657736338717
!
below: n
	<function>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	^(self nextRandom >> 33) asInt64 rem: n
!
reg
	"A register under test."
	<function>
	<returns: 'int32_t'>
	^regs at: (self below: FZ_NREGS)
!
wreg
	"A register under test, sometimes as a W register."
	<function>
	<returns: 'int32_t'>
	| r |
	r := self reg.
	(self below: 4) = 0 ifTrue: [^r + REG_W].
	^r
!
value
	"A random register value: small, negative, 32-bit, boundary or any 64 bits."
	<function>
	<returns: 'uint64_t'>
	| k |
	k := self below: 8.
	k = 0 ifTrue: [^(self below: 16) asUInt64].
	k = 1 ifTrue: [^(self below: 16) negated asUInt64].
	k = 2 ifTrue: [^self nextRandom bitAnd: 16rFFFFFFFF].
	k = 3 ifTrue: [^16r8000000000000000 asUInt64 + (self below: 3) asUInt64 - 1].
	k = 4 ifTrue: [^16r7FFFFFFF asUInt64 + (self below: 3) asUInt64].
	k = 5 ifTrue: [^((self below: 64) asUInt64 << 3) bitOr: 1].
	^self nextRandom
!
logicalImmediate: isW
	"A random arm64 bitmask immediate."
	<function>
	<var: #isW type: 'bool'>
	<returns: 'uint64_t'>
	| k |
	isW ifTrue: [
		k := self below: 8.
		k = 0 ifTrue: [^1].
		k = 1 ifTrue: [^16rFF].
		k = 2 ifTrue: [^16rFFFF].
		k = 3 ifTrue: [^16r7FFFFFFF].
		k = 4 ifTrue: [^16rFFFFFFF0].
		k = 5 ifTrue: [^16r80000000].
		k = 6 ifTrue: [^16r0F0F0F0F].
		^16r55555555].
	k := self below: 16.
	k = 0 ifTrue: [^1].
	k = 1 ifTrue: [^7].
	k = 2 ifTrue: [^16rFF].
	k = 3 ifTrue: [^16rFFFFFFFF].
	k = 4 ifTrue: [^16r7FFFFFFF].
	k = 5 ifTrue: [^16rFFFFFFFF00000000].
	k = 6 ifTrue: [^16rFFFFFFFFFFFFFFFE].
	k = 7 ifTrue: [^16r8000000000000000].
	k = 8 ifTrue: [^16r7FFFFFFFFFFFFFFF].
	k = 9 ifTrue: [^16rF0F0F0F0F0F0F0F0].
	k = 10 ifTrue: [^16r5555555555555555].
	k = 11 ifTrue: [^16rFFFF0000FFFF0000].
	k = 12 ifTrue: [^16rFFF000].
	k = 13 ifTrue: [^16rFFFFFFFFFFFF0000].
	k = 14 ifTrue: [^16r1F8].
	^16rC000000000000001
!
cond
	"A condition (not al or nv)."
	<function>
	<returns: 'int32_t'>
	^(self below: 14) asInt32
!
run: i length: len
	"Generate program i, run it, print what it left."
	<function>
	<var: #i type: 'int32_t'>
	<var: #len type: 'int32_t'>
	| start err fn |
	cache flush.
	start := cache top.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	self emitEntry.
	failedKind := -1.
	0 to: len - 1 do: [:k |
		self emitInstruction.
		(asm failed and: [failedKind < 0]) ifTrue: [failedKind := kind]].
	self emitExit.
	"the code's start as a label: to a stub it would branch to"
	asm labelAt: start.
	err := asm finish.
	cache endWritingFrom: start size: asm codeSize.
	0 to: FZ_NREGS - 1 do: [:k | state at: k put: self value].
	0 to: 3 do: [:k | state at: 16 + k put: (self bitsOfDouble: (self below: 2000) asFloat / 16.0 - 60.0)].
	0 to: 63 do: [:k | memory at: k put: self value].
	err ~= ASM_OK ifTrue: [
		skipped := skipped + 1.
		libc printf: 'p%d skip %d k%d
' with: i with: err with: failedKind.
		^self].
	cache allocate: asm codeSize.
	i = dump ifTrue: [
		| f |
		f := libc fopen: 'code.bin' mode: 'wb'.
		libc fwrite: (self cCoerce: start to: 'void *') size: 1 count: asm codeSize file: f.
		libc fclose: f].
	fn := self cCoerce: start to: 'void (*)(uint64_t *, uint64_t *)'.
	fn call: state with: memory.
	self print: i
!
print: i
	<function>
	<var: #i type: 'int32_t'>
	| sum |
	libc printf: 'p%d' with: i.
	0 to: FZ_NREGS - 1 do: [:k | libc printf: ' %llx' with: (state at: k)].
	0 to: 3 do: [:k |
		| b |
		b := state at: 16 + k.
		(((b >> 52) bitAnd: 16r7FF) = 16r7FF and: [(b bitAnd: 16rFFFFFFFFFFFFF) ~= 0])
			ifTrue: [libc printf: ' nan']
			ifFalse: [libc printf: ' %llx' with: b]].
	sum := 0 asUInt64.
	0 to: 63 do: [:k | sum := (sum * 31) + (memory at: k)].
	libc printf: ' m%llx
' with: sum
! !

!AsmLoweringFuzz methodsFor: 'emitting'!
emitEntry
	"x0: the state (registers, then d registers at 16), x1: memory (x20). Saves what either CPU's C calling convention wants saved."
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm stp: X19 with: X20 base: SP preIndex: -16.
	asm stp: X10 with: X11 base: SP preIndex: -16.
	asm stp: X17 with: X21 base: SP preIndex: -16.
	asm mov: X19 with: X0.
	asm mov: X20 with: X1.
	0 to: FZ_NREGS - 1 do: [:k | asm ldr: (regs at: k) base: X19 offset: 8 * k].
	0 to: 3 do: [:k | asm ldr: (dregs at: k) base: X19 offset: 8 * (16 + k)]
!
emitExit
	0 to: FZ_NREGS - 1 do: [:k | asm str: (regs at: k) base: X19 offset: 8 * k].
	0 to: 3 do: [:k | asm str: (dregs at: k) base: X19 offset: 8 * (16 + k)].
	asm ldp: X17 with: X21 base: SP postIndex: 16.
	asm ldp: X10 with: X11 base: SP postIndex: 16.
	asm ldp: X19 with: X20 base: SP postIndex: 16.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret
!
nzcv: n
	"One of the flags a subtraction gives (0 2 3 6 8 9 10), by n."
	| j |
	j := n rem: 7.
	j = 0 ifTrue: [^0].
	j < 3 ifTrue: [^j + 1].
	j = 3 ifTrue: [^6].
	^j + 4
!
emitFlagSetter
	"An instruction that sets the flags (random values drawn first: C does not order a call's arguments)."
	<function>
	| k a b i m s |
	k := self below: 9.
	a := self reg.
	b := self reg.
	i := self below: 4096.
	m := self logicalImmediate: false.
	s := self below: 64.
	asm failed ifFalse: [kind := (200 + k) asInt32].
	k = 0 ifTrue: [^asm cmp: a with: b].
	k = 1 ifTrue: [^asm cmp: a imm: i].
	k = 2 ifTrue: [^asm cmn: a imm: i].
	k = 3 ifTrue: [^asm adds: a with: b with: a].
	k = 4 ifTrue: [^asm subs: a with: b with: a].
	k = 5 ifTrue: [^asm subs: a with: b imm: i].
	k = 6 ifTrue: [^asm tst: a imm: m].
	k = 7 ifTrue: [^asm tst: a with: b].
	asm cmp: a with: b shift: SHIFT_ASR amount: s
!
emitInstruction
	"One instruction (or a short pattern) from the code generators' repertoire; every random value is drawn first, in order."
	<function>
	| k a b c e wa w v i i12 m mw s s32 lsb width cond d d1 d2 off boff two lbl |
	k := self below: 48.
	kind := k asInt32.
	a := self reg.
	b := self reg.
	c := self reg.
	e := self reg.
	wa := self wreg.
	w := (self below: 4) = 0 ifTrue: [REG_W] ifFalse: [0].
	v := self value.
	i := self below: 4096.
	i12 := (self below: 4096) * 4096.
	m := self logicalImmediate: false.
	mw := self logicalImmediate: true.
	s := self below: 64.
	s32 := self below: 32.
	lsb := self below: 63.
	width := 1 + (self below: 64 - lsb).
	cond := self cond.
	d := dregs at: (self below: 4).
	d1 := dregs at: (self below: 4).
	d2 := dregs at: (self below: 4).
	off := 8 * (self below: 63).
	boff := self below: 512.
	two := self below: 2.
	k = 0 ifTrue: [^asm mov: a with: b].
	k = 1 ifTrue: [^asm mov: wa imm: v].
	k = 2 ifTrue: [^asm add: a with: b imm: i].
	k = 3 ifTrue: [^asm sub: a with: b imm: i].
	k = 4 ifTrue: [^asm add: a with: b imm: i12].
	k = 5 ifTrue: [^asm adds: a with: b imm: i].
	k = 6 ifTrue: [^asm add: a + w with: b + w with: c + w].
	k = 7 ifTrue: [^asm sub: a + w with: b + w with: c + w].
	k = 8 ifTrue: [^asm add: a with: b with: c shift: SHIFT_LSL amount: (s bitAnd: 7)].
	k = 9 ifTrue: [^asm and: a with: b with: c].
	k = 10 ifTrue: [^asm orr: a with: b with: c].
	k = 11 ifTrue: [^asm eor: a with: b with: c].
	k = 12 ifTrue: [^asm and: a with: b imm: m].
	k = 13 ifTrue: [^asm orr: a with: b imm: m].
	k = 14 ifTrue: [^asm eor: a with: b imm: m].
	k = 15 ifTrue: [^asm and: a + REG_W with: b + REG_W imm: mw].
	k = 16 ifTrue: [^asm lsl: a with: b imm: s].
	k = 17 ifTrue: [^asm lsr: a with: b imm: s].
	k = 18 ifTrue: [^asm asr: a with: b imm: s].
	k = 19 ifTrue: [^asm lsl: a + REG_W with: b + REG_W imm: s32].
	k = 20 ifTrue: [^asm lsl: a with: b with: c].
	k = 21 ifTrue: [^asm asr: a with: b with: c].
	k = 22 ifTrue: [^asm lsr: a with: b with: c].
	k = 23 ifTrue: [^asm ubfx: a with: b lsb: lsb width: width].
	k = 24 ifTrue: [^asm mul: a with: b with: c].
	k = 25 ifTrue: [^asm smulh: a with: b with: c].
	k = 26 ifTrue: [^asm sdiv: a with: b with: c].
	k = 27 ifTrue: [^asm msub: a with: b with: c sub: e].
	k = 28 ifTrue: [^asm neg: a with: b].
	k = 29 ifTrue: [
		self emitFlagSetter.
		asm failed ifFalse: [kind := k asInt32].
		^asm csel: a with: b with: c cond: cond].
	k = 30 ifTrue: [
		self emitFlagSetter.
		asm failed ifFalse: [kind := k asInt32].
		^asm cset: a cond: cond].
	k = 31 ifTrue: [
		self emitFlagSetter.
		asm failed ifFalse: [kind := k asInt32].
		^asm csinc: a with: b with: c cond: cond].
	k = 32 ifTrue: [
		"a branch over an instruction"
		self emitFlagSetter.
		asm failed ifFalse: [kind := k asInt32].
		lbl := asm newLabel.
		asm b: lbl if: cond.
		asm add: a with: b imm: 1 + (i bitAnd: 63).
		^asm bind: lbl].
	k = 33 ifTrue: [
		lbl := asm newLabel.
		two = 0 ifTrue: [asm cbz: wa to: lbl] ifFalse: [asm cbnz: wa to: lbl].
		asm eor: a with: b imm: 16rFF.
		^asm bind: lbl].
	k = 34 ifTrue: [
		lbl := asm newLabel.
		two = 0 ifTrue: [asm tbz: a bit: s to: lbl] ifFalse: [asm tbnz: a bit: s to: lbl].
		asm sub: b with: c imm: 1 + (i bitAnd: 63).
		^asm bind: lbl].
	k = 35 ifTrue: [^asm ldr: wa base: X20 offset: off].
	k = 36 ifTrue: [^asm str: wa base: X20 offset: off].
	k = 37 ifTrue: [^asm ldrb: a base: X20 offset: boff].
	k = 38 ifTrue: [^asm strb: a base: X20 offset: boff].
	k = 39 ifTrue: [
		"a load pair into one register is unpredictable on arm64"
		a = b ifTrue: [b := a = X0 ifTrue: [X1] ifFalse: [X0]].
		^asm ldp: a with: b base: X20 offset: off].
	k = 40 ifTrue: [^asm stp: a with: b base: X20 offset: off].
	k = 41 ifTrue: [
		"an indexed load: the index masked into range first"
		asm and: c with: c imm: 63.
		^asm ldr: a base: X20 index: c extend: EXT_LSL shift: 3].
	k = 42 ifTrue: [
		asm and: c with: c imm: 63.
		^asm str: a base: X20 index: c extend: EXT_LSL shift: 3].
	k = 43 ifTrue: [
		two = 0 ifTrue: [^asm fadd: d with: d1 with: d2].
		^asm fsub: d with: d1 with: d2].
	k = 44 ifTrue: [
		two = 0 ifTrue: [^asm fmul: d with: d1 with: d2].
		^asm fdiv: d with: d1 with: d2].
	k = 45 ifTrue: [
		"a conditional compare (ccmp, ccmn; a register or an immediate) on another's flags, nzcv one a subtraction gives, then a select on its flags"
		self emitFlagSetter.
		asm failed ifFalse: [kind := k asInt32].
		(s bitAnd: 3) = 0 ifTrue: [asm ccmp: b with: c nzcv: (self nzcv: i) cond: cond].
		(s bitAnd: 3) = 1 ifTrue: [asm ccmn: b with: c nzcv: (self nzcv: i) cond: cond].
		(s bitAnd: 3) = 2 ifTrue: [asm ccmp: b imm: ((i >> 3) rem: 63) asInt64 - 31 nzcv: (self nzcv: i) cond: cond].
		(s bitAnd: 3) = 3 ifTrue: [asm ccmn: b imm: ((i >> 3) rem: 63) asInt64 - 31 nzcv: (self nzcv: i) cond: cond].
		^asm cset: a cond: (lsb rem: 14) asInt32].
	k = 46 ifTrue: [
		"rev (W or X) between another's flags and a select on them: it leaves the flags"
		self emitFlagSetter.
		asm failed ifFalse: [kind := k asInt32].
		asm rev: a + w with: b + w.
		^asm csel: c with: c with: e cond: cond].
	"a floating point compare and a select or branch on it"
	two = 0
		ifTrue: [asm fcmp: d with: d1]
		ifFalse: [asm fcmpZero: d].
	(s bitAnd: 1) = 0 ifTrue: [^asm cset: a cond: cond].
	lbl := asm newLabel.
	asm b: lbl if: cond.
	asm add: a with: a imm: 1000.
	asm bind: lbl
! !
