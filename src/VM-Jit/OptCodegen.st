OptModule subclass: #OptCodegen
	instanceVariableNames: 'ir passes regalloc cgCodeStart cgBcSize cgValidSlots cgEntryPc cgSlotTop cgMaxOut cgExitPlainLabel cgExitSyncLabel cgDeoptLabel cgReturnLabel cgHeaderLabel cgSendLabel cgInterruptLabel cgBarrierLabel cgDeoptReturnLabel cgStackFullLabel cgOuts cgOutCount cgPoolOops cgPoolLabels cgPoolCount cgMetaWords cgMetaCount cgSpOffsets cgSpCount cgMoveSrc cgMoveDst cgMoveLoc cgMoveCount cgRootAct cgLastPc cgLastAct builder cgDeps cgDepCount cgSunk cgSunkCount cgChainActs cgChainCount cgDoubles'
	classVariableNames: 'CG_MAX_META CG_MAX_MOVES CG_MAX_OUT CG_MAX_POOL CG_MAX_SP OUT_BARRIER OUT_BOTTOM OUT_DEOPT OUT_INTERRUPT OUT_LAZY OUT_SEND OUT_STACK OUT_WIDOW'
	package: 'VM-Jit'!

OptCodegen comment: 'Emits arm64 code for the allocated IR (OptRegalloc) in block order, then the out-of-line paths (guard failures, interrupt checks, store barriers, deoptimization after a call, the stack check), then the oop pool the code loads constants from (pc-relative; GC roots). Records for every safepoint and guard the deoptimization metadata (OptRuntime decodes it): kind, continuation, the send, and for each activation its method, closure, receiver, pc and where each slot''s value is (LOC_*).

Frame layout: slots 0..numArgs-1 the arguments, then home slots (OptRegalloc), slotTop of them; a send''s receiver and arguments go at slotTop..., the callee''s frame starts after them; the result comes back in slot slotTop. At a safepoint the frame''s pc is bcSize + the safepoint''s index and its sp counts the slots in use, so GCs see every value saved there; the bytecode map has the continuation of each send under that pc.'!

!OptCodegen class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (passes OptPasses) (regalloc OptRegalloc)
		(cgCodeStart uint64_t) (cgBcSize int32_t) (cgValidSlots int32_t) (cgEntryPc int32_t) (cgSlotTop int32_t) (cgMaxOut int32_t)
		(cgExitPlainLabel int32_t) (cgExitSyncLabel int32_t) (cgDeoptLabel int32_t) (cgReturnLabel int32_t) (cgHeaderLabel int32_t) (cgSendLabel int32_t) (cgInterruptLabel int32_t)
		(cgBarrierLabel int32_t) (cgDeoptReturnLabel int32_t) (cgStackFullLabel int32_t)
		(cgOuts 'OptOut[CG_MAX_OUT]') (cgOutCount int32_t)
		(cgPoolOops 'oop[CG_MAX_POOL]') (cgPoolLabels 'int32_t[CG_MAX_POOL]') (cgPoolCount int32_t)
		(cgMetaWords 'int32_t[CG_MAX_META]') (cgMetaCount int32_t) (cgSpOffsets 'int32_t[CG_MAX_SP]') (cgSpCount int32_t)
		(cgMoveSrc 'int32_t[CG_MAX_MOVES]') (cgMoveDst 'int32_t[CG_MAX_MOVES]') (cgMoveLoc 'int32_t[CG_MAX_MOVES]') (cgMoveCount int32_t) (cgRootAct int32_t) (cgLastPc int32_t) (cgLastAct int32_t)
		(builder OptBuilder) (cgDeps 'int32_t[256]') (cgDepCount int32_t)
		(cgSunk 'int32_t[64]') (cgSunkCount int32_t) (cgDoubles bool) (cgChainActs 'int32_t[512]') (cgChainCount int32_t))
!
initialize
	CG_MAX_OUT := 4096.
	CG_MAX_POOL := 1024.
	CG_MAX_META := 262144.
	CG_MAX_SP := 4096.
	CG_MAX_MOVES := 256.
	OUT_DEOPT := 1.
	OUT_INTERRUPT := 2.
	OUT_BARRIER := 3.
	OUT_LAZY := 4.
	OUT_STACK := 5.
	OUT_BOTTOM := 6.
	OUT_SEND := 7.
	OUT_WIDOW := 8
! !

!OptCodegen methodsFor: 'accessing'!
slotTop
	^cgSlotTop
!
maxOut
	^cgMaxOut
!
poolCount
	^cgPoolCount
!
poolOffset
	"Code offset of the pool (8-byte entries)."
	cgPoolCount = 0 ifTrue: [^0 asInt64].
	^((asm addressOf: (cgPoolLabels at: 0)) - cgCodeStart) asInt64
!
spCount
	^cgSpCount
!
spOffsetAt: i
	^cgSpOffsets at: i
!
metaCount
	^cgMetaCount
!
metaAt: i
	^cgMetaWords at: i
! !

!OptCodegen methodsFor: 'generating'!
generate: m act: a
	"Emit the code at the assembler's pc; answer whether it could."
	<c: 'bool opt_generate(oop m, int32_t a)'>
	| b bl |
	cgCodeStart := asm pc.
	cgRootAct := a.
	cgLastPc := -1.
	cgLastAct := -1.
	cgBcSize := self methodSize: m.
	cgValidSlots := builder validSlots.
	cgEntryPc := builder entryPc.
	cgSlotTop := regalloc slotCount.
	cgSlotTop < cgValidSlots ifTrue: [cgSlotTop := cgValidSlots].
	cgMaxOut := self maxOutgoing asInt32.
	cgDoubles := false.
	0 to: ir nodeCount - 1 do: [:i | ((ir node: i) block >= 0 and: [(ir node: i) rep asInt32 = R_DBL]) ifTrue: [cgDoubles := true]].
	cgOutCount := 0.
	cgPoolCount := 0.
	cgMetaCount := 0.
	cgSpCount := 0.
	cgExitPlainLabel := asm newLabel.
	cgExitSyncLabel := asm newLabel.
	cgDeoptLabel := asm labelAt: stubs optDeoptStub.
	cgReturnLabel := asm labelAt: stubs optReturnStub.
	cgSendLabel := asm labelAt: stubs optSendStub.
	cgInterruptLabel := asm labelAt: stubs interruptStub.
	cgBarrierLabel := asm labelAt: stubs barrierStub.
	cgDeoptReturnLabel := asm labelAt: stubs optDeoptReturnStub.
	cgStackFullLabel := asm labelAt: stubs optStackFullStub.
	cgHeaderLabel := asm newLabel.
	0 to: passes orderCount - 1 do: [:i | (ir block: (passes orderAt: i)) label: asm newLabel].
	self emitEntry.
	0 to: passes orderCount - 1 do: [:i |
		b := passes orderAt: i.
		bl := ir block: b.
		asm bind: bl label.
		self emitBlock: b next: (i + 1 < passes orderCount ifTrue: [passes orderAt: i + 1] ifFalse: [-1])].
	(self emitOuts) ifFalse: [^false].
	cgDepCount := (builder depCount min: 256) asInt32.
	0 to: cgDepCount - 1 do: [:i | cgDeps at: i put: (self poolIndexOf: (builder depAt: i))].
	asm bind: cgExitPlainLabel.
	asm comment: 'leave to the interpreter (the runtime made the frames canonical)'.
	asm b: (asm labelAt: stubs exitPlainAddress).
	asm bind: cgExitSyncLabel.
	asm comment: 'leave to the interpreter at the stored pc'.
	asm b: (asm labelAt: stubs exitSyncAddress).
	self emitPool.
	"the header follows, 8-byte aligned (JitRuntime>>finish:code:mode:)"
	[(asm pc bitAnd: 7) ~= 0] whileTrue: [asm emit: 16rD503201F].
	asm bind: cgHeaderLabel.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'codegen: asm error %d, %d safepoints, %d metadata words
' with: asm errorCode with: cgSpCount with: cgMetaCount].
	^asm failed not and: [cgSpCount < CG_MAX_SP and: [cgMetaCount < (CG_MAX_META - 1024)]]
!
maxOutgoing
	| n |
	n := 0.
	0 to: ir nodeCount - 1 do: [:i |
		((ir node: i) block >= 0 and: [((ir node: i) op asInt32 = O_SEND or: [(ir node: i) op asInt32 = O_CALL])]) ifTrue: [
			n := n max: (ir node: i) nargs asInt32]].
	^n
!
emitEntry
	"The prologue from compiled callers, then start: room for the frame, home slots nil, the arguments."
	| s |
	self emitPrologue.
	runtime noteResume: cgEntryPc at: asm pc - cgCodeStart.
	asm comment: 'room for the frame''s slots (else the interpreter runs it)'.
	s := self out: OUT_STACK node: -1 index: 0.
	asm mov: X16 imm: 8 * (cgSlotTop + cgMaxOut + 1).
	asm add: X16 with: X20 with: X16.
	asm ldr: X17 base: X22 offset: self cstackLimitOffset.
	asm cmp: X16 with: X17.
	asm b: s if: COND_HI.
	asm comment: 'invalidated (a direct call from older code): the interpreter runs it'.
	asm adr: X16 label: cgHeaderLabel.
	asm ldr: W16 base: X16 offset: self headerFlagsOffset.
	asm tst: W16 imm: 2.
	asm b: s if: COND_NE.
	cgSlotTop > cgValidSlots ifTrue: [
		asm comment: 'home slots nil'.
		asm ldr: X16 base: X22 offset: self nilOffset.
		cgValidSlots to: cgSlotTop - 1 do: [:i | asm str: X16 base: X20 offset: 8 * i]]
!
emitBlock: b next: nextBlock
	| n nd |
	n := (ir block: b) first.
	[n >= 0] whileTrue: [
		nd := ir node: n.
		((nd bcact ~= cgLastAct or: [nd bcpc ~= cgLastPc]) and: [nd op asInt32 ~= O_PHI and: [nd op asInt32 ~= O_CONST]]) ifTrue: [
			nd bcact = cgRootAct
				ifTrue: [asm bytecode: nd bcpc]
				ifFalse: [
					nd bcact ~= cgLastAct ifTrue: [asm comment: 'inlined activation %d' with: nd bcact].
					asm comment: 'its pc %d' with: nd bcpc].
			cgLastAct := nd bcact.
			cgLastPc := nd bcpc].
		self emitNode: n block: b next: nextBlock.
		n := nd next]
! !

!OptCodegen methodsFor: 'operands'!
src: v into: scratch
	"A register holding v: its own, or scratch loaded from its slot or with the constant."
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [
		self loadConstant: nd aux asUInt64 into: scratch.
		^scratch].
	nd reg >= 0 ifTrue: [^nd reg asInt32].
	nd slot >= 0 ifTrue: [
		asm ldr: scratch base: X20 offset: 8 * nd slot asInt32.
		^scratch].
	asm fail: ASM_ERR_OPERAND.
	^scratch
!
dst: n
	"Where n's result is computed: its register, or X14 if it lives in its slot."
	| nd |
	nd := ir node: n.
	nd reg >= 0 ifTrue: [^nd reg asInt32].
	^X14
!
def: n from: r
	"n's result is in r: into its register, and into its home slot if it has one (a value lives in its slot across safepoints: stored once, where it is defined)."
	| nd |
	nd := ir node: n.
	(nd reg >= 0 and: [nd reg asInt32 ~= r]) ifTrue: [asm mov: nd reg asInt32 with: r].
	nd slot >= 0 ifTrue: [asm str: r base: X20 offset: 8 * nd slot asInt32]
!
loadConstant: v into: r
	(self isInt: v) ifTrue: [
		(v asInt64 between: -16r80000000 and: 16r7FFFFFFF) ifTrue: [^asm mov: r imm: v asInt64].
		^asm mov: r imm: v].
	v = memory nilOop ifTrue: [^asm ldr: r base: X22 offset: self nilOffset].
	v = memory trueOop ifTrue: [^asm ldr: r base: X22 offset: self trueOffset].
	v = memory falseOop ifTrue: [^asm ldr: r base: X22 offset: self falseOffset].
	(v bitAnd: 7) ~= 0 ifTrue: [^asm mov: r imm: v].
	asm ldr: r label: (cgPoolLabels at: (self poolIndexOf: v))
!
poolIndexOf: v
	"v's entry in the pool (made if needed)."
	<c: 'int32_t opt_pool_index(uint64_t v)'>
	0 to: cgPoolCount - 1 do: [:i | (cgPoolOops at: i) = v ifTrue: [^i]].
	cgPoolCount >= CG_MAX_POOL ifTrue: [
		asm fail: ASM_ERR_FULL.
		^0].
	cgPoolOops at: cgPoolCount put: v.
	cgPoolLabels at: cgPoolCount put: asm newLabel.
	cgPoolCount := cgPoolCount + 1.
	^cgPoolCount - 1
!
emitPool
	[(asm pc bitAnd: 7) ~= 0] whileTrue: [asm emit: 16rD503201F].
	0 to: cgPoolCount - 1 do: [:i |
		asm bind: (cgPoolLabels at: i).
		asm emit64: (cgPoolOops at: i)]
!
cstackLimitOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #cstackLimit) to: 'int64_t'
!
dumpOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #dump) to: 'int64_t'
!
hashBoxOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #hashBox) to: 'int64_t'
!
stressOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #stress) to: 'int64_t'
!
codeOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #code) to: 'int64_t'
!
ipOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #ip) to: 'int64_t'
!
headerFlagsOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitMethod *') fieldAddress: #flags) to: 'int64_t'
! !

!OptCodegen methodsFor: 'nodes'!
emitNode: n block: b next: nextBlock
	<c: 'void opt_emit_node(int32_t n, int32_t b, int32_t nextBlock)'>
	| nd op x y r s |
	nd := ir node: n.
	op := nd op asInt32.
	op = O_PHI ifTrue: [^self].
	op = O_CONST ifTrue: [^self].
	op = O_CLOSURE ifTrue: [^self].
	op = O_HOMESLOT ifTrue: [^self].
	op = O_LOADSLOT ifTrue: [
		r := self dst: n.
		asm ldr: r base: X20 offset: 8 * nd aux.
		^self def: n from: r].
	op = O_STORESLOT ifTrue: [
		asm str: (self src: nd a into: X14) base: X20 offset: 8 * nd aux.
		^self].
	op = O_PARAM ifTrue: [
		(nd reg < 0 and: [nd slot < 0]) ifTrue: [^self].
		r := self dst: n.
		nd aux = -2
			ifTrue: [asm ldr: r base: X19 offset: self closureOffset]
			ifFalse: [asm ldr: r base: X20 offset: 8 * nd aux].
		^self def: n from: r].
	op = O_LOADFIELD ifTrue: [
		x := self src: nd a into: X15.
		r := self dst: n.
		asm ldr: r base: x offset: (self fieldOffset: nd aux).
		^self def: n from: r].
	op = O_STOREFIELD ifTrue: [^self emitStore: n].
	(op = O_OUTERLOAD or: [op = O_OUTERSTORE]) ifTrue: [^self emitOuterTemp: n].
	op = O_INDEXLOAD ifTrue: [^self emitIndexLoad: n].
	op = O_INDEXSTORE ifTrue: [^self emitIndexStore: n].
	op = O_SIZE ifTrue: [
		x := self src: nd a into: X15.
		self emitSizeOf: x kind: nd aux asInt32 fixed: nd aux2 asInt32.
		asm add: X16 with: X16 with: X16.
		r := self dst: n.
		asm orr: r with: X16 imm: 1.
		^self def: n from: r].
	op = O_CLASSOF ifTrue: [^self emitClassOf: n].
	(op = O_UNBOXF or: [op = O_BOXF or: [op = O_FARITH or: [op = O_FSQRT]]]) ifTrue: [^self emitFloat: n].
	(op = O_EQ or: [op = O_NE or: [op = O_ICMP or: [op = O_CLASSIS or: [op = O_FCMP or: [op = O_BOTHINT]]]]]) ifTrue: [
		(self isFused: n) ifTrue: [^self].
		self emitCompare: n.
		r := self dst: n.
		asm ldr: X16 base: X22 offset: self trueOffset.
		asm ldr: X17 base: X22 offset: self falseOffset.
		asm csel: r with: X16 with: X17 cond: (self conditionOf: n).
		^self def: n from: r].
	op = O_GUARDCLASS ifTrue: [
		s := self deoptLabelFor: n.
		x := self src: nd a into: X15.
		asm comment: 'guard: its class'.
		self emitClassTest: x class: nd aux asUInt64.
		asm b: s if: COND_NE.
		^self def: n from: x].
	op = O_CAST ifTrue: [^self def: n from: (self src: nd a into: X15)].
	op = O_GUARDINT ifTrue: [
		s := self deoptLabelFor: n.
		x := self src: nd a into: X15.
		asm comment: 'guard: a SmallInteger'.
		asm tst: x imm: 1.
		asm b: s if: COND_EQ.
		^self def: n from: x].
	(op = O_IADD or: [op = O_ISUB]) ifTrue: [^self emitAddSub: n].
	op = O_IMUL ifTrue: [^self emitMul: n].
	(op = O_IMOD or: [op = O_IDIV or: [op = O_ISHIFT]]) ifTrue: [^self emitDivShift: n].
	op = O_NOTINTS ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: 'guard: not two SmallIntegers'.
		x := self src: nd a into: X14.
		y := self src: nd b into: X15.
		asm and: X16 with: x with: y.
		asm tst: X16 imm: 1.
		asm b: s if: COND_NE.
		^self].
	(op = O_IAND or: [op = O_IOR or: [op = O_IXOR]]) ifTrue: [
		x := self src: nd a into: X14.
		y := self src: nd b into: X15.
		r := self dst: n.
		op = O_IAND ifTrue: [asm and: r with: x with: y].
		op = O_IOR ifTrue: [asm orr: r with: x with: y].
		op = O_IXOR ifTrue: [
			asm eor: r with: x with: y.
			asm orr: r with: r imm: 1].
		^self def: n from: r].
	op = O_CHECKINT ifTrue: [^self emitCheckInterrupt: n].
	(op = O_SEND or: [op = O_CALL]) ifTrue: [^self emitSend: n].
	op = O_GOTO ifTrue: [
		self emitMovesFrom: b to: (ir block: b) succ0.
		(ir block: b) succ0 ~= nextBlock ifTrue: [asm b: (ir block: (ir block: b) succ0) label].
		^self].
	op = O_BRANCH ifTrue: [^self emitBranch: n block: b next: nextBlock].
	op = O_RETURN ifTrue: [^self emitReturn: n].
	op = O_DEOPT ifTrue: [
		asm b: (self deoptLabelFor: n).
		^self].
	asm fail: ASM_ERR_OPERAND
!
isFused: n
	"A comparison whose only use is the branch right after it: the branch compares."
	| nd nx |
	nd := ir node: n.
	nd uses = 1 ifFalse: [^false].
	nd next < 0 ifTrue: [^false].
	nx := ir node: nd next.
	^nx op asInt32 = O_BRANCH and: [nx a = n]
!
conditionOf: n
	| nd k |
	nd := ir node: n.
	nd op asInt32 = O_EQ ifTrue: [^COND_EQ].
	nd op asInt32 = O_CLASSIS ifTrue: [^COND_EQ].
	nd op asInt32 = O_NE ifTrue: [^COND_NE].
	nd op asInt32 = O_BOTHINT ifTrue: [^COND_EQ].
	k := nd aux asInt32.
	"floats: unordered (NaN) compares false, except ~="
	nd op asInt32 = O_FCMP ifTrue: [^k caseOf: {[2] -> [COND_MI]. [3] -> [COND_GT]. [4] -> [COND_LS]. [5] -> [COND_GE]. [6] -> [COND_EQ]} otherwise: [COND_NE]].
	^k caseOf: {[2] -> [COND_LT]. [3] -> [COND_GT]. [4] -> [COND_LE]. [5] -> [COND_GE]. [6] -> [COND_EQ]} otherwise: [COND_NE]
!
emitCompare: n
	| nd x y |
	nd := ir node: n.
	nd op asInt32 = O_FCMP ifTrue: [^asm fcmp: (self dsrc: nd a) with: (self dsrc: nd b)].
	x := self src: nd a into: X14.
	nd op asInt32 = O_CLASSIS ifTrue: [^self emitClassTest: x class: nd aux asUInt64].
	nd op asInt32 = O_BOTHINT ifTrue: [
		y := self src: nd b into: X15.
		asm and: X16 with: x with: y.
		asm and: X16 with: X16 imm: 1.
		^asm cmp: X16 imm: 1].
	((ir node: nd b) op asInt32 = O_CONST and: [(self isInt: (ir node: nd b) aux asUInt64) and: [(ir node: nd b) aux between: -4095 and: 4095]])
		ifTrue: [
			(ir node: nd b) aux >= 0
				ifTrue: [asm cmp: x imm: (ir node: nd b) aux]
				ifFalse: [asm cmn: x imm: (ir node: nd b) aux negated]]
		ifFalse: [
			y := self src: nd b into: X15.
			asm cmp: x with: y]
!
emitBranch: n block: b next: nextBlock
	| nd v vd t f tl fl s rv |
	nd := ir node: n.
	v := nd a.
	vd := ir node: v.
	(vd tkind asInt32 ~= T_BOOL and: [(self isFused: v) not]) ifTrue: [s := self deoptLabelFor: n].
	t := (ir block: b) succ0.
	f := (ir block: b) succ1.
	tl := (ir block: t) label.
	fl := (ir block: f) label.
	(self isFused: v) ifTrue: [
		self emitCompare: v.
		t = nextBlock
			ifTrue: [asm b: fl if: ((self conditionOf: v) bitXor: 1)]
			ifFalse: [
				asm b: tl if: (self conditionOf: v).
				f ~= nextBlock ifTrue: [asm b: fl]].
		^self].
	rv := self src: v into: X14.
	asm ldr: X16 base: X22 offset: self trueOffset.
	asm cmp: rv with: X16.
	asm b: tl if: COND_EQ.
	vd tkind asInt32 ~= T_BOOL ifTrue: [
		asm comment: 'neither true nor false: the interpreter sends mustBeBoolean'.
		asm ldr: X16 base: X22 offset: self falseOffset.
		asm cmp: rv with: X16.
		asm b: s if: COND_NE].
	f ~= nextBlock ifTrue: [asm b: fl]
!
dsrc: v
	"v's D register (doubles always have one)."
	(ir node: v) reg >= D0 ifTrue: [^(ir node: v) reg asInt32].
	asm fail: ASM_ERR_OPERAND.
	^D0
!
emitFloat: n
	"Unboxing (a SmallFloat64 decoded, a SmallInteger converted), boxing (as a SmallFloat64), arithmetic and sqrt on doubles; what does not fit deoptimizes."
	| nd op s x r int done zero store k |
	nd := ir node: n.
	op := nd op asInt32.
	op = O_UNBOXF ifTrue: [
		x := self src: nd a into: X15.
		r := self dsrc: n.
		(ir node: nd a) tkind asInt32 ~= T_FLOAT ifTrue: [
			s := self deoptLabelFor: n.
			int := asm newLabel.
			done := asm newLabel.
			asm tbnz: x bit: 0 to: int.
			asm and: X16 with: x imm: 7.
			asm cmp: X16 imm: 4.
			asm b: s if: COND_NE].
		asm comment: 'a SmallFloat64''s double'.
		asm lsr: X16 with: x imm: 3.
		asm mov: X17 imm: 16r7000000000000000.
		asm add: X17 with: X16 with: X17.
		asm cmp: X16 imm: 1.
		asm csel: X16 with: X16 with: X17 cond: COND_LS.
		asm ror: X16 with: X16 imm: 1.
		asm fmov: r with: X16.
		(ir node: nd a) tkind asInt32 ~= T_FLOAT ifTrue: [
			asm b: done.
			asm bind: int.
			asm asr: X16 with: x imm: 1.
			asm scvtf: r with: X16.
			asm bind: done].
		^self].
	op = O_BOXF ifTrue: [
		s := self deoptLabelFor: n.
		zero := asm newLabel.
		store := asm newLabel.
		asm comment: 'as a SmallFloat64 (out of its exponent range: deoptimize)'.
		asm fmov: X16 with: (self dsrc: nd a).
		asm lsl: X17 with: X16 imm: 1.
		asm cbz: X17 to: zero.
		asm ubfx: X15 with: X16 lsb: 52 width: 11.
		asm sub: X15 with: X15 imm: 897.
		asm cmp: X15 imm: 253.
		asm b: s if: COND_HI.
		asm ror: X17 with: X16 imm: 63.
		asm mov: X15 imm: 16r7000000000000000.
		asm sub: X17 with: X17 with: X15.
		asm b: store.
		asm bind: zero.
		asm lsr: X17 with: X16 imm: 63.
		asm bind: store.
		r := self dst: n.
		asm lsl: r with: X17 imm: 3.
		asm orr: r with: r imm: 4.
		^self def: n from: r].
	op = O_FSQRT ifTrue: [^asm fsqrt: (self dsrc: n) with: (self dsrc: nd a)].
	k := nd aux asInt32.
	k = 9 ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: 'division by zero: deoptimize'.
		asm fcmpZero: (self dsrc: nd b).
		asm b: s if: COND_EQ].
	k = 0 ifTrue: [^asm fadd: (self dsrc: n) with: (self dsrc: nd a) with: (self dsrc: nd b)].
	k = 1 ifTrue: [^asm fsub: (self dsrc: n) with: (self dsrc: nd a) with: (self dsrc: nd b)].
	k = 8 ifTrue: [^asm fmul: (self dsrc: n) with: (self dsrc: nd a) with: (self dsrc: nd b)].
	asm fdiv: (self dsrc: n) with: (self dsrc: nd a) with: (self dsrc: nd b)
!
emitSizeOf: x kind: ek fixed: fixed
	"X16 := the number of indexable elements of x (pointer slots after fixed fields, or bytes); uses X17."
	ek = E_PTR ifTrue: [
		asm ldr: W16 base: x offset: 0.
		fixed > 0 ifTrue: [asm sub: X16 with: X16 imm: fixed].
		^self].
	asm comment: 'bytes: 8 per slot less the unused ones (the format''s low bits)'.
	asm ldr: X17 base: x offset: 0.
	asm ubfx: X16 with: X17 lsb: 0 width: 32.
	asm ubfx: X17 with: X17 lsb: 32 width: 5.
	asm sub: X17 with: X17 imm: F_BYTES.
	asm lsl: X16 with: X16 imm: 3.
	asm sub: X16 with: X16 with: X17
!
emitIndexCheck: n
	"X17 := the 0-based element index of n's index operand (a SmallInteger) in its object, deoptimizing if it is out of bounds; answer the object's register."
	| nd x i s |
	nd := ir node: n.
	s := self deoptLabelFor: n.
	x := self src: nd a into: X14.
	asm comment: 'bounds check'.
	self emitSizeOf: x kind: nd aux asInt32 fixed: nd aux2 asInt32.
	i := self src: nd b into: X15.
	asm asr: X17 with: i imm: 1.
	asm sub: X17 with: X17 imm: 1.
	asm cmp: X17 with: X16.
	asm b: s if: COND_HS.
	^x
!
emitIndexLoad: n
	| nd x r ek |
	nd := ir node: n.
	ek := nd aux asInt32.
	x := self emitIndexCheck: n.
	asm add: X16 with: x imm: 16 + (8 * nd aux2).
	r := self dst: n.
	ek = E_PTR ifTrue: [
		asm ldr: r base: X16 index: X17 extend: EXT_LSL shift: 3.
		^self def: n from: r].
	asm ldrb: W16 base: X16 index: X17.
	ek = E_BYTE
		ifTrue: [
			asm lsl: X16 with: X16 imm: 1.
			asm orr: r with: X16 imm: 1]
		ifFalse: [
			asm lsl: X16 with: X16 imm: 3.
			asm orr: r with: X16 imm: 2].
	self def: n from: r
!
emitIndexStore: n
	"The value: a SmallInteger 0-255 into bytes, a Character below 256 into a string, any oop into pointers (with the store barrier); an immutable object deoptimizes."
	| nd x v ek s done check slow |
	nd := ir node: n.
	ek := nd aux asInt32.
	s := self deoptLabelFor: n.
	x := self emitIndexCheck: n.
	asm ldr: X16 base: x offset: 0.
	asm tst: X16 imm: H_IMMUTABLE.
	asm b: s if: COND_NE.
	asm add: X16 with: x imm: 16 + (8 * nd aux2).
	asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: (ek = E_PTR ifTrue: [3] ifFalse: [0]).
	v := self src: nd c into: X15.
	ek ~= E_PTR ifTrue: [
		ek = E_BYTE
			ifTrue: [
				asm tst: v imm: 1.
				asm b: s if: COND_EQ.
				asm lsr: X17 with: v imm: 1]
			ifFalse: [
				asm and: X17 with: v imm: 7.
				asm cmp: X17 imm: 2.
				asm b: s if: COND_NE.
				asm lsr: X17 with: v imm: 3].
		asm cmp: X17 imm: 255.
		asm b: s if: COND_HI.
		asm strb: W17 base: X16 offset: 0.
		^self].
	asm str: v base: X16 offset: 0.
	(ir node: nd c) op asInt32 = O_CONST ifTrue: [
		(((ir node: nd c) aux bitAnd: 7) ~= 0 or: [(self isYoung: (ir node: nd c) aux asUInt64) not]) ifTrue: [^self]].
	done := asm newLabel.
	check := asm newLabel.
	slow := self out: OUT_BARRIER node: n index: (x bitOr: v << 8).
	(cgOuts + (cgOutCount - 1)) resume: done.
	asm comment: 'store barrier'.
	asm tst: v imm: 7.
	asm b: done if: COND_NE.
	asm ldr: X16 base: X22 offset: self youngLoOffset.
	asm cmp: v with: X16.
	asm b: done if: COND_LO.
	asm ldr: X17 base: X22 offset: self youngHiOffset.
	asm cmp: v with: X17.
	asm b: done if: COND_HS.
	asm cmp: x with: X16.
	asm b: check if: COND_LO.
	asm cmp: x with: X17.
	asm b: done if: COND_LO.
	asm bind: check.
	asm ldr: X16 base: x offset: 0.
	asm tst: X16 imm: H_REMEMBERED.
	asm b: slow if: COND_EQ.
	asm bind: done
!
emitClassTest: x class: cls
	"Flags EQ if x's class is cls (no branch: a tagged x reads a word of the JitState instead of a class)."
	cls = memory clsSmallint ifTrue: [
		asm and: X16 with: x imm: 1.
		^asm cmp: X16 imm: 1].
	cls = memory clsSmallfloat ifTrue: [
		asm and: X16 with: x imm: 7.
		^asm cmp: X16 imm: 4].
	cls = memory clsChar ifTrue: [
		asm and: X16 with: x imm: 7.
		^asm cmp: X16 imm: 2].
	asm tst: x imm: 7.
	asm csel: X16 with: x with: X22 cond: COND_EQ.
	asm ldr: X16 base: X16 offset: 8.
	self loadConstant: cls into: X17.
	asm cmp: X16 with: X17
!
emitAddSub: n
	| nd x y c isAdd s |
	nd := ir node: n.
	s := self deoptLabelFor: n.
	isAdd := nd op asInt32 = O_IADD.
	x := self src: nd a into: X14.
	((ir node: nd b) op asInt32 = O_CONST and: [((ir node: nd b) aux asUInt64 - 1) asInt64 between: -4095 and: 4095])
		ifTrue: [
			c := ((ir node: nd b) aux asUInt64 - 1) asInt64.
			(isAdd = (c >= 0))
				ifTrue: [asm adds: X16 with: x imm: (c < 0 ifTrue: [c negated] ifFalse: [c])]
				ifFalse: [asm subs: X16 with: x imm: (c < 0 ifTrue: [c negated] ifFalse: [c])]]
		ifFalse: [
			y := self src: nd b into: X15.
			asm sub: X17 with: y imm: 1.
			isAdd
				ifTrue: [asm adds: X16 with: x with: X17]
				ifFalse: [asm subs: X16 with: x with: X17]].
	asm b: s if: COND_VS.
	self def: n from: X16
!
emitDivShift: n
	"SmallInteger modulo and division (floored; a zero divisor deoptimizes) and bitShift: (a result that does not fit deoptimizes)."
	| nd s op neg done |
	nd := ir node: n.
	op := nd op asInt32.
	s := self deoptLabelFor: n.
	asm asr: X16 with: (self src: nd a into: X14) imm: 1.
	asm asr: X17 with: (self src: nd b into: X15) imm: 1.
	done := asm newLabel.
	op = O_ISHIFT ifTrue: [
		neg := asm newLabel.
		asm tbnz: X17 bit: 63 to: neg.
		asm comment: 'left: back again or deoptimize'.
		asm cmp: X17 imm: 62.
		asm b: s if: COND_HI.
		asm lsl: X15 with: X16 with: X17.
		asm asr: X14 with: X15 with: X17.
		asm cmp: X14 with: X16.
		asm b: s if: COND_NE.
		asm b: done.
		asm bind: neg.
		asm neg: X17 with: X17.
		asm mov: X14 imm: 63.
		asm cmp: X17 with: X14.
		asm csel: X17 with: X17 with: X14 cond: COND_LS.
		asm asr: X15 with: X16 with: X17.
		asm bind: done.
		asm adds: X15 with: X15 with: X15.
		asm b: s if: COND_VS.
		asm orr: X15 with: X15 imm: 1.
		^self def: n from: X15].
	asm cbz: X17 to: s.
	asm sdiv: X15 with: X16 with: X17.
	asm msub: X14 with: X15 with: X17 sub: X16.
	asm comment: 'floored: a remainder of the divisor''s other sign moves'.
	asm cbz: X14 to: done.
	asm eor: X16 with: X14 with: X17.
	asm tbz: X16 bit: 63 to: done.
	op = O_IMOD
		ifTrue: [asm add: X14 with: X14 with: X17]
		ifFalse: [asm sub: X15 with: X15 imm: 1].
	asm bind: done.
	op = O_IMOD
		ifTrue: [
			asm add: X14 with: X14 with: X14.
			asm orr: X15 with: X14 imm: 1]
		ifFalse: [
			asm adds: X15 with: X15 with: X15.
			asm b: s if: COND_VS.
			asm orr: X15 with: X15 imm: 1].
	self def: n from: X15
!
emitMul: n
	| nd x y s |
	nd := ir node: n.
	s := self deoptLabelFor: n.
	x := self src: nd a into: X14.
	y := self src: nd b into: X15.
	asm asr: X16 with: x imm: 1.
	asm sub: X17 with: y imm: 1.
	asm mul: X15 with: X16 with: X17.
	asm smulh: X16 with: X16 with: X17.
	asm cmp: X16 with: X15 shift: SHIFT_ASR amount: 63.
	asm b: s if: COND_NE.
	asm orr: X16 with: X15 imm: 1.
	self def: n from: X16
!
emitClassOf: n
	| nd x r imm done ch |
	nd := ir node: n.
	x := self src: nd a into: X15.
	r := self dst: n.
	imm := asm newLabel.
	done := asm newLabel.
	ch := asm newLabel.
	asm ands: X16 with: x imm: 7.
	asm b: imm if: COND_NE.
	asm ldr: r base: x offset: 8.
	asm b: done.
	asm bind: imm.
	asm tst: x imm: 1.
	asm b: ch if: COND_EQ.
	self loadConstant: memory clsSmallint into: r.
	asm b: done.
	asm bind: ch.
	asm cmp: X16 imm: 2.
	self loadConstant: memory clsChar into: X17.
	self loadConstant: memory clsSmallfloat into: r.
	asm csel: r with: X17 with: r cond: COND_EQ.
	asm bind: done.
	self def: n from: r
!
emitStore: n
	"Store b into a's field; the generational barrier's tests inline, the remembering out of line. A frame state: deoptimize if a is immutable."
	| nd o v s |
	nd := ir node: n.
	nd state >= 0 ifTrue: [s := self deoptLabelFor: n].
	o := self src: nd a into: X14.
	v := self src: nd b into: X15.
	nd state >= 0 ifTrue: [
		asm comment: 'immutable: the interpreter sends attemptToAssign:withIndex:'.
		asm ldr: X16 base: o offset: 0.
		asm tst: X16 imm: H_IMMUTABLE.
		asm b: s if: COND_NE].
	asm str: v base: o offset: (self fieldOffset: nd aux).
	self emitBarrier: n object: o value: v
!
emitBarrier: n object: o value: v
	"After storing n's value v into object o: the generational barrier (o and v not in X16, X17)."
	| done slow check nd |
	nd := ir node: n.
	(ir node: nd b) op asInt32 = O_CONST ifTrue: [
		(((ir node: nd b) aux bitAnd: 7) ~= 0 or: [(self isYoung: (ir node: nd b) aux asUInt64) not]) ifTrue: [^self]].
	"immediates, Booleans, nil: never young"
	((ir node: nd b) tkind asInt32 between: T_SMI and: T_NIL) ifTrue: [^self].
	(ir node: nd b) tkind asInt32 = T_CHAR ifTrue: [^self].
	done := asm newLabel.
	check := asm newLabel.
	slow := self out: OUT_BARRIER node: n index: (o bitOr: v << 8).
	(cgOuts + (cgOutCount - 1)) resume: done.
	asm comment: 'store barrier: an immediate, an old value, a young object or a remembered one need nothing'.
	asm tst: v imm: 7.
	asm b: done if: COND_NE.
	asm ldr: X16 base: X22 offset: self youngLoOffset.
	asm cmp: v with: X16.
	asm b: done if: COND_LO.
	asm ldr: X17 base: X22 offset: self youngHiOffset.
	asm cmp: v with: X17.
	asm b: done if: COND_HS.
	asm cmp: o with: X16.
	asm b: check if: COND_LO.
	asm cmp: o with: X17.
	asm b: done if: COND_LO.
	asm bind: check.
	asm ldr: X16 base: o offset: 0.
	asm tst: X16 imm: H_REMEMBERED.
	asm b: slow if: COND_EQ.
	asm bind: done
!
emitOuterTemp: n
	"A temp of the Context lv levels out of the unit's closure (the template's outerTemp:): in the frame it is married to (sender: the frame's index), else in it."
	| nd v x married done r |
	nd := ir node: n.
	nd op asInt32 = O_OUTERSTORE ifTrue: [v := self src: nd b into: X14].
	x := self src: nd a into: X15.
	asm comment: 'outer temp %d' with: nd aux2.
	asm ldr: X15 base: x offset: (self fieldOffset: BC_OUTER).
	2 to: nd aux asInt32 do: [:k |
		asm ldr: X17 base: X15 offset: (self fieldOffset: CTX_CLOSURE).
		asm ldr: X15 base: X17 offset: (self fieldOffset: BC_OUTER)].
	asm ldr: X17 base: X15 offset: (self fieldOffset: CTX_SENDER).
	married := asm newLabel.
	done := asm newLabel.
	asm tbnz: X17 bit: 0 to: married.
	nd op asInt32 = O_OUTERLOAD
		ifTrue: [
			r := self dst: n.
			asm ldr: r base: X15 offset: (self fieldOffset: CTX_FIXED + nd aux2).
			asm b: done.
			asm bind: married.
			asm ldr: X16 base: X22 offset: self framesOffset.
			asm asr: X17 with: X17 imm: 1.
			asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: 6.
			asm ldr: X16 base: X16 offset: self fpOffset.
			asm ldr: r base: X16 offset: 8 * nd aux2.
			asm bind: done.
			^self def: n from: r].
	asm str: v base: X15 offset: (self fieldOffset: CTX_FIXED + nd aux2).
	self emitBarrier: n object: X15 value: v.
	asm b: done.
	asm bind: married.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm asr: X17 with: X17 imm: 1.
	asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: 6.
	asm ldr: X16 base: X16 offset: self fpOffset.
	asm str: v base: X16 offset: 8 * nd aux2.
	asm bind: done
!
emitReturn: n
	| nd x s back w |
	nd := ir node: n.
	x := self src: nd a into: X14.
	asm comment: 'the bottom frame returns into a Context: the interpreter does it'.
	s := self out: OUT_BOTTOM node: n index: 0.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm cmp: X19 with: X16.
	asm b: s if: COND_EQ.
	asm comment: 'result into the receiver''s slot, pop the frame, return'.
	asm stur: x base: X20 offset: -8.
	builder entryPc > (ir act: cgRootAct) startpc ifTrue: [
		"a loop's unit: the frame may be married (no block refers to its Context)"
		back := asm newLabel.
		w := self out: OUT_WIDOW node: n index: 0.
		(cgOuts + (cgOutCount - 1)) resume: back.
		asm ldr: X16 base: X19 offset: self ctxOffset.
		asm ldr: X17 base: X22 offset: self nilOffset.
		asm cmp: X16 with: X17.
		asm b: w if: COND_NE.
		asm bind: back].
	asm sub: X19 with: X19 imm: self frameBytes.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret
!
emitCheckInterrupt: n
	| s back |
	back := asm newLabel.
	s := self out: OUT_INTERRUPT node: n index: 0.
	(cgOuts + (cgOutCount - 1)) resume: back.
	asm comment: 'interrupt check'.
	asm ldr: W16 base: X22 offset: self interruptOffset.
	asm cbnz: W16 to: s.
	self emitStressAt: n label: s.
	asm bind: back
!
emitStressAt: n label: l
	"--jit-flags deopt: every so often take the slow path anyway."
	(runtime flag: runtime deoptFlag) ifFalse: [^self].
	asm comment: 'deoptimization stress'.
	asm ldr: X16 base: X22 offset: self stressOffset.
	asm subs: X16 with: X16 imm: 1.
	asm str: X16 base: X22 offset: self stressOffset.
	asm b: l if: COND_EQ
!
emitSend: n
	"Through the runtime (OptRuntime>>send:index:site:): receiver and arguments at slotTop, the result comes back there."
	| nd argc k here cont r lazy slow done |
	nd := ir node: n.
	argc := nd nargs asInt32 - 1.
	k := self recordCall: n.
	done := asm newLabel.
	(nd flags bitAnd: NF_ALLOC) ~= 0 ifTrue: [
		slow := asm newLabel.
		self emitAllocate: n slow: slow done: done.
		asm bind: slow].
	self saveAcross: n.
	asm comment: 'receiver and arguments'.
	0 to: argc do: [:i |
		r := self src: (ir operand: nd args + i) into: X14.
		asm str: r base: X20 offset: 8 * (cgSlotTop + i)].
	cont := asm newLabel.
	here := asm newLabel.
	nd op asInt32 = O_CALL
		ifTrue: [
			self emitFramePc: cgBcSize + k sp: cgSlotTop.
			slow := self out: OUT_SEND node: n index: k.
			(cgOuts + (cgOutCount - 1)) resume: cont.
			self emitPushFrameFor: nd tcls argc: argc slow: slow]
		ifFalse: [
			(nd flags bitAnd: NF_BLOCKCALL) ~= 0 ifTrue: [
				slow := asm newLabel.
				self emitFramePc: cgBcSize + k sp: cgSlotTop.
				self emitBlockCall: argc index: k slow: slow.
				asm b: cont.
				asm bind: slow].
			self emitFramePc: cgBcSize + k sp: cgSlotTop + argc + 1.
			asm bind: here.
			self emitRuntimeSend: k site: here exit: cont].
	asm bind: cont.
	runtime noteResume: cgBcSize + k at: asm pc - cgCodeStart.
	cgSpOffsets at: k put: asm pc - cgCodeStart.
	asm ldr: X20 base: X19 offset: self fpOffset.
	lazy := self out: OUT_LAZY node: n index: k.
	asm comment: 'invalidated meanwhile: deoptimize'.
	asm adr: X16 label: cgHeaderLabel.
	asm ldr: W16 base: X16 offset: self headerFlagsOffset.
	asm tst: W16 imm: 2.
	asm b: lazy if: COND_NE.
	self emitStressAt: n label: lazy.
	asm comment: 'the result'.
	r := self dst: n.
	asm ldr: r base: X20 offset: 8 * cgSlotTop.
	self def: n from: r.
	self reloadAcross: n.
	asm bind: done
!
emitAllocate: n slow: slow done: done
	"basicNew(:) in eden: header (slots, format, a hash from the JitState's seed), class, nil fields; no room, the sample's limit or an odd size: the send (slow)."
	| nd fmt isize k sz r loop fill |
	nd := ir node: n.
	fmt := (nd c bitAnd: 255) asInt32.
	isize := (nd c >> 8) asInt32.
	k := -1.
	asm comment: 'allocate in eden'.
	nd nargs asInt32 = 1
		ifTrue: [k := isize]
		ifFalse: [
			sz := ir node: (ir operand: nd args + 1).
			(sz op asInt32 = O_CONST and: [(self isInt: sz aux asUInt64) and: [(self intVal: sz aux asUInt64) between: 0 and: 4096]])
				ifTrue: [k := isize + (self intVal: sz aux asUInt64) asInt32]
				ifFalse: [
					r := self src: (ir operand: nd args + 1) into: X15.
					asm tbz: r bit: 0 to: slow.
					asm asr: X15 with: r imm: 1.
					asm cmp: X15 imm: 4096.
					asm b: slow if: COND_HI.
					isize > 0 ifTrue: [asm add: X15 with: X15 imm: isize]]].
	k >= 0 ifTrue: [asm mov: X15 imm: k].
	asm comment: 'header: slots, format, a hash (the VM''s generator)'.
	fmt ~= 0 ifTrue: [asm orr: X15 with: X15 imm: fmt asUInt64 << H_FMT_SHIFT].
	asm ldr: X16 base: X22 offset: self hashBoxOffset.
	asm ldr: X17 base: X16 offset: 0.
	asm mov: X14 imm: 6364136223846793005.
	asm mul: X17 with: X17 with: X14.
	asm mov: X14 imm: 1442695040888963407.
	asm add: X17 with: X17 with: X14.
	asm str: X17 base: X16 offset: 0.
	asm lsr: X17 with: X17 imm: 40.
	asm and: X17 with: X17 imm: H_HASH_MASK.
	asm cmp: X17 imm: 0.
	asm csinc: X17 with: X17 with: XZR cond: COND_NE.
	asm orr: X15 with: X15 with: X17 shift: SHIFT_LSL amount: H_HASH_SHIFT.
	asm comment: 'room in eden'.
	asm ubfx: X14 with: X15 lsb: 0 width: 32.
	asm lsl: X14 with: X14 imm: 3.
	asm add: X14 with: X14 imm: 16.
	asm adrp: X17 label: (asm labelAt: gc edenBoxAddress).
	asm add: X17 with: X17 imm: (gc edenBoxAddress bitAnd: 16rFFF) asInt64.
	asm ldr: X16 base: X17 offset: 0.
	asm add: X14 with: X16 with: X14.
	asm ldr: X17 base: X17 offset: 8.
	asm cmp: X14 with: X17.
	asm b: slow if: COND_HI.
	asm adrp: X17 label: (asm labelAt: gc edenBoxAddress).
	asm add: X17 with: X17 imm: (gc edenBoxAddress bitAnd: 16rFFF) asInt64.
	asm str: X14 base: X17 offset: 0.
	self loadConstant: nd tcls into: X17.
	asm stp: X15 with: X17 base: X16 offset: 0.
	asm comment: 'fields nil'.
	asm ldr: X17 base: X22 offset: self nilOffset.
	(k >= 0 and: [k <= 16])
		ifTrue: [0 to: k - 1 do: [:i | asm str: X17 base: X16 offset: 16 + (8 * i)]]
		ifFalse: [
			loop := asm newLabel.
			fill := asm newLabel.
			asm ldr: W15 base: X16 offset: 0.
			asm add: X14 with: X16 imm: 16.
			asm b: fill.
			asm bind: loop.
			asm str: X17 base: X14 postIndex: 8.
			asm sub: W15 with: W15 imm: 1.
			asm bind: fill.
			asm cbnz: W15 to: loop].
	r := self dst: n.
	asm mov: r with: X16.
	self def: n from: r.
	asm b: done
!
emitRuntimeSend: k site: here exit: cont
	"Call the runtime's send (the site's key: here, bound at the adr); it answers 0 (done), 1 (leave) or the callee's entry."
	asm comment: 'send: call the runtime'.
	asm mov: X0 with: X19.
	asm mov: X1 imm: k.
	asm adr: X2 label: here.
	asm bl: cgSendLabel.
	asm comment: '0: done, 1: leave, else the callee''s entry'.
	asm cbz: X0 to: cont.
	asm cmp: X0 imm: 1.
	asm b: cgExitPlainLabel if: COND_EQ.
	asm blr: X0
!
emitPushFrameFor: m argc: n slow: slow
	"A direct call of m (it has machine code): its frame pushed here as the interpreter would (pushFrame:argc:code:ecode:), then a call of its entry; no room on the stack: the runtime's send."
	| ntemps fs fb cell |
	ntemps := (self intVal: (self loadRef: m at: CM_NUMTEMPS)) asInt32.
	fs := (self intVal: (self loadRef: m at: CM_FRAMESIZE)) asInt32.
	fs < (n + ntemps) ifTrue: [fs := n + ntemps].
	fb := self frameBytes asInt64.
	asm comment: 'direct call: push the callee''s frame'.
	asm mov: X16 imm: 8 * (cgSlotTop + 1).
	asm add: X16 with: X20 with: X16.
	asm mov: X17 imm: 8 * (fs + CTX_SLACK).
	asm add: X17 with: X16 with: X17.
	asm ldr: X15 base: X22 offset: self cstackLimitOffset.
	asm cmp: X17 with: X15.
	asm b: slow if: COND_HI.
	asm str: X16 base: X19 offset: fb + self fpOffset.
	self loadConstant: m into: X17.
	asm str: X17 base: X19 offset: fb.
	asm ldr: X15 base: X22 offset: self nilOffset.
	asm str: X15 base: X19 offset: fb + self closureOffset.
	asm str: X15 base: X19 offset: fb + self ctxOffset.
	0 to: ntemps - 1 do: [:i | asm str: X15 base: X16 offset: 8 * (n + i)].
	asm ldr: X14 base: X17 offset: (self fieldOffset: CM_BYTECODES).
	asm add: X14 with: X14 imm: 16.
	asm str: X14 base: X19 offset: fb + self ipOffset.
	asm ldr: X14 base: X17 offset: (self fieldOffset: CM_LITERALS).
	asm add: X14 with: X14 imm: 16.
	asm str: X14 base: X19 offset: fb + self litsOffset.
	asm mov: X14 imm: (n + ntemps) asInt64 << 32.
	asm str: X14 base: X19 offset: fb + self pcOffset.
	asm comment: 'its code and entry: the method''s cell (it follows the method''s tier)'.
	cell := runtime cellAddressOf: m.
	asm adrp: X15 label: (asm labelAt: cell).
	asm add: X15 with: X15 imm: (cell bitAnd: 16rFFF) asInt64.
	asm ldr: X14 base: X15 offset: 8.
	asm str: X14 base: X19 offset: fb + self codeOffset.
	asm ldr: X16 base: X15 offset: 0.
	asm blr: X16
!
emitBlockCall: n index: k slow: slow
	"The closure at slotTop (its argument count n) runs the code this site called last: its frame pushed as the interpreter's blockActivate:fromArray: does, then a call of the entry; else, or no room on the stack: slow. Live values are in their home slots: x0-x13 are free."
	| e fb loop fill |
	e := runtime blockCallEntryFor: cgCodeStart index: k.
	fb := self frameBytes asInt64.
	asm comment: 'block call: the closure this site called last?'.
	asm ldr: X14 base: X20 offset: 8 * cgSlotTop.
	asm tst: X14 imm: 7.
	asm b: slow if: COND_NE.
	asm ldr: X15 base: X14 offset: (self fieldOffset: BC_NUMARGS).
	asm cmp: X15 imm: 2 * n + 1.
	asm b: slow if: COND_NE.
	asm ldr: X15 base: X14 offset: 8.
	self loadConstant: memory clsBlock into: X16.
	asm cmp: X15 with: X16.
	asm b: slow if: COND_NE.
	asm adrp: X16 label: (asm labelAt: e).
	asm add: X16 with: X16 imm: (e bitAnd: 16rFFF) asInt64.
	asm ldr: X15 base: X14 offset: (self fieldOffset: BC_OUTER).
	asm ldr: X17 base: X15 offset: (self fieldOffset: CTX_METHOD).
	asm ldp: X0 with: X1 base: X16 offset: 0.
	asm cmp: X17 with: X0.
	asm b: slow if: COND_NE.
	asm ldr: X2 base: X14 offset: (self fieldOffset: BC_STARTPC).
	asm cmp: X2 with: X1.
	asm b: slow if: COND_NE.
	asm ldp: X0 with: X1 base: X16 offset: 16.
	asm comment: 'its frame: temps, frame size, room on the stack'.
	asm ldr: X2 base: X14 offset: (self fieldOffset: BC_NUMTEMPS).
	asm asr: X2 with: X2 imm: 1.
	asm ldr: X3 base: X14 offset: (self fieldOffset: BC_FRAMESIZE).
	asm asr: X3 with: X3 imm: 1.
	asm add: X4 with: X2 imm: n.
	asm cmp: X3 with: X4.
	asm csel: X3 with: X3 with: X4 cond: COND_GT.
	asm add: X16 with: X20 imm: 8 * (cgSlotTop + 1).
	asm add: X4 with: X16 with: X3 shift: SHIFT_LSL amount: 3.
	asm add: X4 with: X4 imm: 8 * CTX_SLACK.
	asm ldr: X5 base: X22 offset: self cstackLimitOffset.
	asm cmp: X4 with: X5.
	asm b: slow if: COND_HI.
	asm comment: 'the receiver: the outer context''s'.
	asm ldr: X5 base: X15 offset: (self fieldOffset: CTX_RECEIVER).
	asm str: X5 base: X20 offset: 8 * cgSlotTop.
	asm str: X17 base: X19 offset: fb.
	asm str: X14 base: X19 offset: fb + self closureOffset.
	asm ldr: X5 base: X22 offset: self nilOffset.
	asm str: X5 base: X19 offset: fb + self ctxOffset.
	asm str: X0 base: X19 offset: fb + self codeOffset.
	asm str: X16 base: X19 offset: fb + self fpOffset.
	asm ldr: X6 base: X14 offset: (self fieldOffset: BC_STARTPC).
	asm asr: X6 with: X6 imm: 1.
	asm ldr: X7 base: X17 offset: (self fieldOffset: CM_BYTECODES).
	asm add: X7 with: X7 imm: 16.
	asm add: X7 with: X7 with: X6.
	asm str: X7 base: X19 offset: fb + self ipOffset.
	asm ldr: X7 base: X17 offset: (self fieldOffset: CM_LITERALS).
	asm add: X7 with: X7 imm: 16.
	asm str: X7 base: X19 offset: fb + self litsOffset.
	asm add: X8 with: X2 imm: n.
	asm orr: X6 with: X6 with: X8 shift: SHIFT_LSL amount: 32.
	asm str: X6 base: X19 offset: fb + self pcOffset.
	asm comment: 'temps nil'.
	loop := asm newLabel.
	fill := asm newLabel.
	asm add: X9 with: X16 imm: 8 * n.
	asm b: fill.
	asm bind: loop.
	asm str: X5 base: X9 postIndex: 8.
	asm sub: X2 with: X2 imm: 1.
	asm bind: fill.
	asm cbnz: X2 to: loop.
	asm blr: X1
!
emitFramePc: pc sp: sp
	asm comment: 'frame pc and sp'.
	asm mov: X16 imm: ((sp asInt64 << 32) bitOr: pc).
	asm str: X16 base: X19 offset: self pcOffset
!
saveAcross: n
	"Values live after safepoint n are in their home slots already (def:from:)."
!
reloadAcross: n
	| v nd |
	(ir node: n) live to: (ir node: n) live + (ir node: n) nlive - 1 do: [:i |
		v := regalloc safeLiveAt: i.
		nd := ir node: v.
		(nd reg >= 0 and: [nd slot >= 0]) ifTrue: [asm ldr: nd reg asInt32 base: X20 offset: 8 * nd slot asInt32]]
! !

!OptCodegen methodsFor: 'phi moves'!
emitMovesFrom: b to: s
	"Parallel moves into s's phis of their operands from b."
	| k n nd |
	k := regalloc predIndexOf: b in: s.
	k < 0 ifTrue: [^self].
	cgMoveCount := 0.
	n := (ir block: s) first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		(regalloc isValue: n) ifTrue: [
			cgMoveCount >= CG_MAX_MOVES ifTrue: [^asm fail: ASM_ERR_FULL].
			cgMoveDst at: cgMoveCount put: n.
			cgMoveSrc at: cgMoveCount put: (ir operand: nd args + k).
			cgMoveCount := cgMoveCount + 1].
		n := nd next].
	self sequentializeMoves
!
locOf: v
	"A location for the move resolver: register r, 1000 + slot, -1 for a constant."
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [^-1].
	nd reg >= 0 ifTrue: [^nd reg asInt32].
	^1000 + nd slot asInt32
!
sequentializeMoves
	"Emit the parallel moves: one whose destination no pending move reads; in a cycle, the destination's value is kept in X16 and its readers read X16. Constants last (they read nothing)."
	| progress d blocked k |
	0 to: cgMoveCount - 1 do: [:i | cgMoveLoc at: i put: (self locOf: (cgMoveSrc at: i))].
	[(k := self firstRegisterMove) >= 0] whileTrue: [
		progress := false.
		k := 0.
		[k < cgMoveCount] whileTrue: [
			d := self locOf: (cgMoveDst at: k).
			blocked := false.
			(cgMoveLoc at: k) >= 0 ifTrue: [
				0 to: cgMoveCount - 1 do: [:j | (j ~= k and: [(cgMoveLoc at: j) = d]) ifTrue: [blocked := true]]].
			((cgMoveLoc at: k) < 0 or: [blocked]) ifTrue: [k := k + 1] ifFalse: [
				(cgMoveLoc at: k) ~= d ifTrue: [
					self moveLoc: (cgMoveLoc at: k) toReg: X17 unless: d.
					self moveRegTo: (cgMoveDst at: k) from: ((cgMoveLoc at: k) < 1000 ifTrue: [cgMoveLoc at: k] ifFalse: [X17])].
				self removeMove: k.
				progress := true]].
		progress ifFalse: [
			"a cycle: keep the first register move's destination in X16"
			k := self firstRegisterMove.
			d := self locOf: (cgMoveDst at: k).
			self moveLoc: d toReg: X16 unless: -1.
			0 to: cgMoveCount - 1 do: [:j | (cgMoveLoc at: j) = d ifTrue: [cgMoveLoc at: j put: X16]]]].
	0 to: cgMoveCount - 1 do: [:i | self moveRegTo: (cgMoveDst at: i) from: (self src: (cgMoveSrc at: i) into: X17)].
	cgMoveCount := 0
!
firstRegisterMove
	0 to: cgMoveCount - 1 do: [:i | (cgMoveLoc at: i) >= 0 ifTrue: [^i]].
	^-1
!
removeMove: k
	cgMoveCount := cgMoveCount - 1.
	cgMoveSrc at: k put: (cgMoveSrc at: cgMoveCount).
	cgMoveDst at: k put: (cgMoveDst at: cgMoveCount).
	cgMoveLoc at: k put: (cgMoveLoc at: cgMoveCount)
!
moveLoc: l toReg: r unless: d
	"r := the value at location l (a register below 1000, else a slot); nothing if l is a register (moveRegTo:from: reads it)."
	l < 1000 ifTrue: [
		d = -1 ifTrue: [asm mov: r with: l].
		^self].
	asm ldr: r base: X20 offset: 8 * (l - 1000)
!
moveValue: v to: phi
	| r |
	(self locOf: v) = (self locOf: phi) ifTrue: [^self].
	r := self src: v into: X17.
	self moveRegTo: phi from: r
!
moveLoc: l toReg: r
	l < 1000
		ifTrue: [asm mov: r with: l]
		ifFalse: [asm ldr: r base: X20 offset: 8 * (l - 1000)]
!
moveRegTo: phi from: r
	| nd |
	nd := ir node: phi.
	(nd reg >= 0 and: [nd reg asInt32 ~= r]) ifTrue: [asm mov: nd reg asInt32 with: r].
	nd slot >= 0 ifTrue: [asm str: r base: X20 offset: 8 * nd slot asInt32]
! !

!OptCodegen methodsFor: 'out of line'!
out: kind node: n index: i
	"An out-of-line path emitted after the code; answer its label."
	| o |
	cgOutCount >= CG_MAX_OUT ifTrue: [
		asm fail: ASM_ERR_FULL.
		^asm newLabel].
	o := cgOuts + cgOutCount.
	o kind: kind.
	o node: n.
	o index: i.
	o label: asm newLabel.
	o resume: -1.
	o pos: (n >= 0 ifTrue: [(ir node: n) pos] ifFalse: [0]).
	cgOutCount := cgOutCount + 1.
	^o label
!
deoptLabelFor: n
	"The label of a guard's failure: its metadata recorded with the registers as they are here."
	| k l |
	k := self recordGuard: n.
	l := self out: OUT_DEOPT node: n index: k.
	self emitStressAt: n label: l.
	^l
!
emitOuts
	| o l |
	0 to: cgOutCount - 1 do: [:i |
		o := cgOuts + i.
		asm bind: o label.
		o kind = OUT_DEOPT ifTrue: [
			asm comment: 'guard failed: deoptimize'.
			asm mov: W17 imm: o index.
			asm b: cgDeoptLabel].
		o kind = OUT_INTERRUPT ifTrue: [
			asm comment: 'interrupt: call the runtime'.
			self saveAcross: o node.
			self emitFramePc: cgBcSize + (self recordSafepoint: o node kind: (ir node: o node) aux asInt32) sp: cgSlotTop.
			asm mov: X0 with: X19.
			asm bl: cgInterruptLabel.
			asm cbnz: X0 to: cgExitPlainLabel.
			self reloadAcross: o node.
			asm b: o resume].
		o kind = OUT_BARRIER ifTrue: [
			asm comment: 'remember the old object: call the runtime'.
			self emitBarrierCall: o].
		o kind = OUT_LAZY ifTrue: [
			asm comment: 'deoptimize after the send: the runtime rebuilds the frames'.
			self emitFramePc: cgBcSize + o index sp: cgSlotTop + 1.
			asm mov: X0 with: X19.
			asm mov: X1 imm: o index.
			asm bl: cgDeoptReturnLabel.
			asm b: cgExitPlainLabel].
		o kind = OUT_SEND ifTrue: [
			asm comment: 'no room for the callee''s frame: the runtime sends'.
			self emitFramePc: cgBcSize + o index sp: cgSlotTop + (ir node: o node) nargs asInt32.
			l := asm newLabel.
			asm bind: l.
			self emitRuntimeSend: o index site: l exit: o resume.
			asm b: o resume].
		o kind = OUT_STACK ifTrue: [
			asm comment: 'no room for the frame: the interpreter runs it'.
			self emitFramePc: cgEntryPc sp: cgValidSlots.
			asm mov: X0 with: X19.
			asm bl: cgStackFullLabel.
			asm b: cgExitSyncLabel].
		o kind = OUT_WIDOW ifTrue: [
			asm comment: 'married: its Context becomes a dead one'.
			self emitFramePc: 0 sp: 0.
			asm mov: X0 with: X19.
			asm bl: (asm labelAt: stubs widowStub).
			asm b: o resume].
		o kind = OUT_BOTTOM ifTrue: [
			asm comment: 'the bottom frame returns into a Context: the runtime does it'.
			asm mov: W17 imm: (self recordGuard: o node).
			asm b: cgReturnLabel]].
	^true
!
emitBarrierCall: o
	"Save the scratch registers the C function may change, call the barrier, restore."
	| obj v |
	obj := o index bitAnd: 255.
	v := o index >> 8.
	0 to: 7 do: [:i | asm stp: 2 * i with: 2 * i + 1 base: SP preIndex: -16].
	cgDoubles ifTrue: [0 to: 7 do: [:i | asm stp: D16 + (2 * i) with: D16 + (2 * i) + 1 base: SP preIndex: -16]].
	asm mov: X16 with: obj.
	asm mov: X17 with: v.
	asm mov: X0 with: X16.
	asm mov: X1 with: X17.
	asm bl: cgBarrierLabel.
	cgDoubles ifTrue: [7 to: 0 by: -1 do: [:i | asm ldp: D16 + (2 * i) with: D16 + (2 * i) + 1 base: SP postIndex: 16]].
	7 to: 0 by: -1 do: [:i | asm ldp: 2 * i with: 2 * i + 1 base: SP postIndex: 16].
	asm b: o resume
! !

!OptCodegen methodsFor: 'metadata'!
meta: w
	cgMetaCount < CG_MAX_META ifTrue: [cgMetaWords at: cgMetaCount put: w asInt32].
	cgMetaCount := cgMetaCount + 1
!
newSafepoint
	| k |
	k := cgSpCount.
	cgSpCount < CG_MAX_SP ifTrue: [cgSpOffsets at: k put: 0].
	cgSpCount := cgSpCount + 1.
	^k
!
recordGuard: n
	"Metadata for deoptimizing at guard n: its state with every value where it is now, and why (feedback for the next compilation)."
	| op why |
	op := (ir node: n) op asInt32.
	why := (op = O_GUARDCLASS or: [op = O_DEOPT])
		ifTrue: [feedback deoptClass]
		ifFalse: [op = O_NOTINTS ifTrue: [feedback sawInts] ifFalse: [
			(op = O_GUARDINT or: [op = O_IADD or: [op = O_ISUB or: [op = O_IMUL or: [op = O_IMOD or: [op = O_IDIV or: [op = O_ISHIFT]]]]]]) ifTrue: [feedback deoptArith] ifFalse: [feedback deoptOther]]].
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [libc fprintf: libc stderr format: 'guard safepoint %d: v%d
' with: cgSpCount with: n].
	^self recordState: (ir node: n) state kind: (SP_GUARD bitOr: why asInt64 << 8) asInt32 node: n inSlots: false
!
recordSafepoint: n kind: k
	^self recordState: (ir node: n) state kind: k node: n inSlots: true
!
recordCall: n
	^self recordState: (ir node: n) state kind: SP_CALL node: n inSlots: true
!
recordState: s kind: kind node: n inSlots: inSlots
	"Safepoint record: kind, metadata offset in the table; [kind, send pc, send info, selector, nacts, then per activation from the outermost: method, closure, receiver, pc, depth, locations]."
	<c: 'int32_t opt_record_state(int32_t s, int32_t kind, int32_t n, bool inSlots)'>
	| k chain nchain t st nd |
	k := self newSafepoint.
	k < CG_MAX_SP ifTrue: [cgMetaWords at: CG_MAX_META - 1 - k put: cgMetaCount].
	nd := ir node: n.
	self meta: kind.
	kind = SP_CALL
		ifTrue: [
			self meta: (nd aux2 >> 32) asInt32.
			self meta: (nd aux2 bitAnd: 16rFFFFFFFF) asInt32.
			self meta: (self poolIndexOf: nd aux asUInt64)]
		ifFalse: [
			self meta: -1.
			self meta: 0.
			self meta: 0].
	"the chain of states, outermost first"
	nchain := 0.
	t := s.
	[t >= 0] whileTrue: [
		nchain := nchain + 1.
		t := (ir state: t) parent].
	self meta: nchain.
	cgSunkCount := 0.
	cgChainCount := nchain asInt32.
	nchain - 1 to: 0 by: -1 do: [:i |
		t := s.
		i timesRepeat: [t := (ir state: t) parent].
		st := ir state: t.
		cgChainActs at: nchain - 1 - i put: st act.
		self meta: (self poolIndexOf: (ir act: st act) method).
		self meta: ((ir act: st act) closure >= 0 ifTrue: [self closureLocOf: (ir act: st act) closure inSlots: inSlots] ifFalse: [-1]).
		self meta: (self locOf: (ir operand: st vals) inSlots: inSlots).
		self meta: st pc.
		self meta: st depth.
		0 to: st depth - 1 do: [:j | self meta: (self locOf: (ir operand: st vals + 1 + j) inSlots: inSlots)]].
	"closures that were never made: the activation that makes them (its index above), startpc, arguments, temps, frame size"
	self meta: cgSunkCount.
	0 to: cgSunkCount - 1 do: [:j |
		nd := ir node: (cgSunk at: j).
		t := -1.
		0 to: nchain - 1 do: [:i | (cgChainActs at: i) = (nd aux2 >> 32) asInt32 ifTrue: [t := i asInt32]].
		t < 0 ifTrue: [asm fail: ASM_ERR_OPERAND].
		self meta: t.
		self meta: nd aux asInt32.
		self meta: (nd aux2 bitAnd: 16rFFFFFF) asInt32].
	^k
!
closureLocOf: v inSlots: inSlots
	"A block unit's closure is its frame's (-2)."
	(ir node: v) op asInt32 = O_PARAM ifTrue: [^-2].
	^self locOf: v inSlots: inSlots
!
sunkIndexOf: v
	"v's entry in this record's closures that were never made."
	0 to: cgSunkCount - 1 do: [:j | (cgSunk at: j) = v ifTrue: [^j]].
	cgSunkCount >= 64 ifTrue: [
		asm fail: ASM_ERR_FULL.
		^0].
	cgSunk at: cgSunkCount put: v.
	cgSunkCount := cgSunkCount + 1.
	^cgSunkCount - 1
!
locOf: v inSlots: inSlots
	"Where deoptimization finds v: a constant, its register (not at a safepoint), its slot."
	| nd c |
	nd := ir node: v.
	nd op asInt32 = O_CLOSURE ifTrue: [^((self sunkIndexOf: v) asInt64 << 3) bitOr: LOC_SUNK].
	nd op asInt32 = O_HOMESLOT ifTrue: [^(nd aux << 3) bitOr: LOC_SLOT].
	nd op asInt32 = O_CONST ifTrue: [
		c := nd aux asUInt64.
		((self isInt: c) and: [(self intVal: c) between: -16r8000000 and: 16r7FFFFFF]) ifTrue: [^((self intVal: c) << 3) bitOr: LOC_SMI].
		^((self poolIndexOf: c) asInt64 << 3) bitOr: LOC_CONST].
	(inSlots not and: [nd reg >= 0]) ifTrue: [^(nd reg asInt64 << 3) bitOr: LOC_REG].
	nd slot >= 0 ifTrue: [^(nd slot asInt64 << 3) bitOr: LOC_SLOT].
	asm fail: ASM_ERR_OPERAND.
	^0
!
depCount
	^cgDepCount
!
depAt: i
	^cgDeps at: i
!
spTableAt: k
	"The metadata offset of safepoint k."
	^cgMetaWords at: CG_MAX_META - 1 - k
! !

VMStruct subclass: #OptOut
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptOut comment: 'An out-of-line path of optimized code (OptCodegen): its kind, the node it belongs to, an index (a safepoint, registers), its label and where it goes back to.'!

!OptOut class methodsFor: 'declaring'!
fields
	^#((kind int32_t) (node int32_t) (index int32_t) (label int32_t) (resume int32_t) (pos int32_t))
! !
