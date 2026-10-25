OptModule subclass: #OptBuilder
	instanceVariableNames: 'ir obCurBlock obBailed obVarTop obDefKeys obDefVals obDefCount obIncPhis obIncVars obIncCount obAnaMethods obAnaBases obAnaCount obAnaTop obAnaDepth obAnaFlag obAnaBack obPcBlocks obPcbTop obEntryBlock obRootMethod obInlined obDeps obDepCount obPrimKinds obPrimsKnown obNoInline obNoInlineCount obArgVals obArgFlags obUnitStart obOsrPc obParamSlots obValidSlots obSafeEpoch obAnaFloat'
	classVariableNames: 'OA_BLOCK OA_LOOP OA_START OA_TARGET OPT_MAX_VARS OPT_MAX_NOINLINE OPT_MAX_PRIM PK_AT PK_FLOAT PK_FSQRT PK_NEW PK_NEWSIZE PK_ATPUT PK_CLASS PK_IDENTICAL PK_INT PK_SIZE PK_STRINGAT PK_STRINGATPUT OPT_INLINE_BUDGET OPT_INLINE_DEPTH OPT_INLINE_SIZE OPT_MAX_ANA OPT_MAX_DEPS OPT_MAX_INC'
	package: 'VM-Jit'!

OptBuilder comment: 'Builds the IR (OptIR) of a method from its bytecodes: an abstract interpretation of each activation''s bytecodes in pc order, its slots (arguments, temps, operand stack: the depths BytecodeAnalysis computed) SSA variables, phis made on demand (Braun et al., Simple and Efficient Construction of Static Single Assignment Form, CC 2013: a block is sealed once all its predecessors are known; jump targets when the scan reaches them, loop heads after their last backward jump). Sends, guards and interrupt checks get frame states (OptState) for deoptimization. bail abandons the method (a bytecode the tier does not compile).'!

!OptBuilder class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (obCurBlock int32_t) (obBailed bool) (obVarTop int32_t)
		(obDefKeys 'int32_t[OPT_DEF_SIZE]') (obDefVals 'int32_t[OPT_DEF_SIZE]') (obDefCount int32_t)
		(obIncPhis 'int32_t[OPT_MAX_INC]') (obIncVars 'int32_t[OPT_MAX_INC]') (obIncCount int32_t)
		(obAnaMethods 'oop[OPT_MAX_ANA]') (obAnaBases 'int32_t[OPT_MAX_ANA]') (obAnaCount int32_t) (obAnaTop int32_t)
		(obAnaDepth 'int16_t[OPT_ANA_MAX]') (obAnaFlag 'uint8_t[OPT_ANA_MAX]') (obAnaBack 'int32_t[OPT_ANA_MAX]')
		(obPcBlocks 'int32_t[OPT_PCB_MAX]') (obPcbTop int32_t) (obEntryBlock int32_t) (obRootMethod oop)
		(obInlined int32_t) (obDeps 'oop[OPT_MAX_DEPS]') (obDepCount int32_t) (obPrimKinds 'uint8_t[OPT_MAX_PRIM]') (obPrimsKnown bool)
		(obNoInline 'oop[OPT_MAX_NOINLINE]') (obNoInlineCount int32_t) (obArgVals 'int32_t[OPT_MAX_VARS]') (obArgFlags 'uint8_t[OPT_MAX_VARS]') (obUnitStart int32_t) (obOsrPc int32_t) (obParamSlots int32_t) (obValidSlots int32_t) (obSafeEpoch int32_t) (obAnaFloat 'bool[OPT_MAX_ANA]'))
!
initialize
	OPT_MAX_INC := 16384.
	OPT_MAX_ANA := 256.
	OPT_MAX_DEPS := 256.
	OPT_MAX_PRIM := 1024.
	OPT_MAX_NOINLINE := 8.
	OPT_MAX_VARS := 65536.
	PK_AT := 1.
	PK_ATPUT := 2.
	PK_SIZE := 3.
	PK_STRINGAT := 4.
	PK_STRINGATPUT := 5.
	PK_CLASS := 6.
	PK_IDENTICAL := 7.
	PK_INT := 32.
	PK_FLOAT := 64.
	PK_FSQRT := 8.
	PK_NEW := 9.
	PK_NEWSIZE := 10.
	OPT_INLINE_SIZE := 80.
	OPT_INLINE_BUDGET := 1500.
	OPT_INLINE_DEPTH := 8.
	OA_START := 1.
	OA_TARGET := 2.
	OA_LOOP := 4.
	OA_BLOCK := 8
! !

!OptBuilder methodsFor: 'accessing'!
entryBlock
	^obEntryBlock
!
bailed
	^obBailed or: [ir full]
!
bail
	(obBailed not and: [(libc getenv: 'SAMALTAK_OPT_TRACE') notNull]) ifTrue: [
		libc fprintf: libc stderr format: 'opt: bail at pc %d of act %d
' with: ir originPc with: ir originAct].
	obBailed := true
! !

!OptBuilder methodsFor: 'building'!
build: m start: s osr: t depth: d
	"The IR of m (s 0), or of its block at startpc s, entered at its start (t -1) or at loop head t with d slots; answer whether it could be built. A closure an inlined method makes that escapes would have to be made: build again without inlining that method."
	<c: 'bool opt_build(oop m, int32_t s, int32_t t, int32_t d)'>
	| e |
	obNoInlineCount := 0.
	obUnitStart := s.
	obOsrPc := t.
	obValidSlots := d.
	[(self buildOnce: m) ifFalse: [^false].
	 e := self escapingClosure.
	 e < 0 ifTrue: [^true].
	 (libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [libc fprintf: libc stderr format: 'opt: a closure of act %d escapes
' with: e].
	 (e = 0 or: [obNoInlineCount >= OPT_MAX_NOINLINE]) ifTrue: [^false].
	 obNoInline at: obNoInlineCount put: (ir act: e) method.
	 obNoInlineCount := obNoInlineCount + 1] repeat
!
buildOnce: m
	<c: 'bool opt_build_once(oop m)'>
	| a b |
	ir reset.
	obBailed := false.
	obVarTop := 0.
	libc memset: obArgFlags value: 0 size: OPT_MAX_VARS.
	obDefCount := 0.
	libc memset: obDefKeys value: 0 size: 4 * OPT_DEF_SIZE.
	obIncCount := 0.
	obAnaCount := 0.
	obAnaTop := 0.
	obPcbTop := 0.
	obRootMethod := m.
	obInlined := 0.
	obDepCount := 0.
	obSafeEpoch := 0.
	a := obUnitStart > 0 ifTrue: [self newBlockActFor: m start: obUnitStart] ifFalse: [self newActFor: m].
	a < 0 ifTrue: [^false].
	obEntryBlock := ir newBlock.
	(ir block: obEntryBlock) flags: BF_SEALED.
	(ir block: obEntryBlock) act: a.
	obCurBlock := obEntryBlock.
	(ir act: a) receiver: (self param: -1).
	obUnitStart > 0 ifTrue: [(ir act: a) closure: (self param: -2)].
	obParamSlots := (ir act: a) numArgs.
	obOsrPc >= 0 ifTrue: [^self buildOsr: a].
	obValidSlots := (ir act: a) numArgs + (ir act: a) numTemps.
	0 to: (ir act: a) numArgs - 1 do: [:i | self writeArg: (self var: a slot: i) value: (self param: i)].
	(ir act: a) numArgs to: (ir act: a) numArgs + (ir act: a) numTemps - 1 do: [:i | self write: (self var: a slot: i) value: (self constant: memory nilOop)].
	"a failed primitive's error code is in the first temp"
	((ir act: a) numTemps > 0 and: [obUnitStart = 0 and: [(self isInt: (self loadRef: m at: CM_PRIMITIVE)) and: [((self intVal: (self loadRef: m at: CM_PRIMITIVE)) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0]]]) ifTrue: [
		self write: (self var: a slot: (ir act: a) numArgs) value: (self param: (ir act: a) numArgs)].
	self checkInterruptAct: a pc: obUnitStart depth: (ir act: a) numArgs + (ir act: a) numTemps kind: SP_ENTRY.
	b := ir newBlock.
	self goto: b.
	obCurBlock := b.
	self seal: b.
	self buildAct: a.
	self bailed ifTrue: [^false].
	0 to: ir blockCount - 1 do: [:k | ((ir block: k) flags bitAnd: BF_SEALED) = 0 ifTrue: [self seal: k]].
	^self bailed not
!
buildOsr: a
	"Enter at loop head obOsrPc: the frame's slots there are the parameters."
	| b |
	obValidSlots = (self depthAt: obOsrPc act: a) ifFalse: [^false].
	obParamSlots := obValidSlots.
	0 to: obValidSlots - 1 do: [:i |
		i < (ir act: a) numArgs
			ifTrue: [self writeArg: (self var: a slot: i) value: (self param: i)]
			ifFalse: [self write: (self var: a slot: i) value: (self param: i)]].
	b := self blockAt: obOsrPc act: a.
	self goto: b.
	self buildAct: a.
	self bailed ifTrue: [^false].
	0 to: ir blockCount - 1 do: [:k | ((ir block: k) flags bitAnd: BF_SEALED) = 0 ifTrue: [self seal: k]].
	^self bailed not
!
entryPc
	"Where the unit is entered: its start, or the loop head."
	obOsrPc >= 0 ifTrue: [^obOsrPc].
	^obUnitStart
!
paramSlots
	"The frame's slots the code reads at its entry and keeps (home slots follow)."
	^obParamSlots
!
validSlots
	"The frame's slots that hold values at its entry (the others are made nil)."
	^obValidSlots
!
newActFor: m
	"An activation of method m (not yet linked to a caller), its analysis and pc map; -1 if m cannot be compiled."
	<c: 'int32_t opt_new_act_for(oop m)'>
	| a ac ana fs |
	ana := self analysisOf: m.
	ana < 0 ifTrue: [^-1].
	a := ir newAct.
	ac := ir act: a.
	ac method: m.
	ac numArgs: (self intVal: (self loadRef: m at: CM_NUMARGS)) asInt32.
	ac numTemps: (self intVal: (self loadRef: m at: CM_NUMTEMPS)) asInt32.
	fs := (self intVal: (self loadRef: m at: CM_FRAMESIZE)) asInt32.
	fs < (ac numArgs + ac numTemps) ifTrue: [fs := ac numArgs + ac numTemps].
	ac nslots: fs + 4.
	ac startpc: 0.
	ac endpc: (self methodSize: m).
	ac ana: ana.
	ac home: a.
	(self allocPcBlocks: a) ifFalse: [^-1].
	ac varBase: obVarTop.
	ac retVar: obVarTop + ac nslots.
	obVarTop := obVarTop + ac nslots + 1.
	^a
!
newBlockActFor: m start: s
	"The activation of m's block at startpc s, compiled as a unit: its closure the frame's, its outer temps through it (no outer activation), ^ deoptimizes; -1 if m cannot be compiled."
	<c: 'int32_t opt_new_block_act_for(oop m, int32_t s)'>
	| a ac fs |
	a := self newActFor: m.
	a < 0 ifTrue: [^-1].
	ac := ir act: a.
	ac numArgs: (self byteAt: s - 5 act: a) asInt32.
	ac numTemps: (self byteAt: s - 4 act: a) asInt32.
	fs := (self byteAt: s - 3 act: a) asInt32.
	fs < (ac numArgs + ac numTemps) ifTrue: [fs := ac numArgs + ac numTemps].
	ac startpc: s.
	ac endpc: s + (((self byteAt: s - 2 act: a) asInt64 << 8 bitOr: (self byteAt: s - 1 act: a)) asInt32).
	ac home: -1.
	fs + 4 > ac nslots ifTrue: [
		ac nslots: fs + 4.
		ac retVar: ac varBase + ac nslots.
		obVarTop := ac varBase + ac nslots + 1].
	^a
!
allocPcBlocks: a
	| ac n |
	ac := ir act: a.
	n := self methodSize: ac method.
	obPcbTop + n > OPT_PCB_MAX ifTrue: [
		self bail.
		^false].
	ac pcb: obPcbTop.
	0 to: n - 1 do: [:i | obPcBlocks at: obPcbTop + i put: -1].
	obPcbTop := obPcbTop + n.
	^true
!
analysisOf: m
	"The base of m's analysis in the arena (depth and flags per pc, the last backward jump to each loop head); -1 if m cannot be analyzed."
	<c: 'int32_t opt_analysis_of(oop m)'>
	| n base f t |
	0 to: obAnaCount - 1 do: [:i | (obAnaMethods at: i) = m ifTrue: [^obAnaBases at: i]].
	obAnaCount >= OPT_MAX_ANA ifTrue: [^-1].
	(analysis analyze: m) ifFalse: [^-1].
	n := analysis size.
	obAnaTop + n > OPT_ANA_MAX ifTrue: [^-1].
	base := obAnaTop.
	0 to: n - 1 do: [:pc |
		f := 0.
		(analysis isStart: pc) ifTrue: [f := f bitOr: OA_START].
		(analysis isTarget: pc) ifTrue: [f := f bitOr: OA_TARGET].
		(analysis isLoopHead: pc) ifTrue: [f := f bitOr: OA_LOOP].
		(analysis isBlockStart: pc) ifTrue: [f := f bitOr: OA_BLOCK].
		obAnaFlag at: base + pc put: f asUInt8.
		obAnaDepth at: base + pc put: (analysis depthAt: pc) asInt16.
		obAnaBack at: base + pc put: -1].
	0 to: n - 1 do: [:pc |
		((f := obAnaFlag at: base + pc) bitAnd: OA_START) ~= 0 ifTrue: [
			((analysis byteAt: pc) >= 16r90 and: [(analysis byteAt: pc) <= 16r92]) ifTrue: [
				t := analysis jumpTargetAt: pc.
				(t <= pc and: [(obAnaBack at: base + t) < pc]) ifTrue: [obAnaBack at: base + t put: pc]]]].
	obAnaMethods at: obAnaCount put: m.
	obAnaBases at: obAnaCount put: base.
	obAnaFloat at: obAnaCount put: false.
	0 to: n - 1 do: [:pc | ((feedback flagsAt: m pc: pc) bitAnd: feedback sawFloat) ~= 0 ifTrue: [obAnaFloat at: obAnaCount put: true]].
	obAnaCount := obAnaCount + 1.
	obAnaTop := obAnaTop + n.
	^base
!
isStart: pc act: a
	^((obAnaFlag at: (ir act: a) ana + pc) bitAnd: OA_START) ~= 0
!
isTarget: pc act: a
	^((obAnaFlag at: (ir act: a) ana + pc) bitAnd: OA_TARGET) ~= 0
!
isLoopHead: pc act: a
	^((obAnaFlag at: (ir act: a) ana + pc) bitAnd: OA_LOOP) ~= 0
!
depthAt: pc act: a
	^(obAnaDepth at: (ir act: a) ana + pc) asInt32
!
lastBackJumpTo: pc act: a
	^obAnaBack at: (ir act: a) ana + pc
!
byteAt: pc act: a
	^(self methodBytecodes: (ir act: a) method) at: pc
!
int16At: pc act: a
	| p |
	p := self methodBytecodes: (ir act: a) method.
	^((p at: pc) bitOr: (p at: pc + 1) asInt64 << 8) asInt16 asInt32
!
literal: i act: a
	^self methodLiteral: (ir act: a) method at: i
!
buildAct: a
	"Scan a's bytecodes from startpc to endpc."
	<c: 'void opt_build_act(int32_t a)'>
	| pc b ac |
	ac := ir act: a.
	pc := ac startpc.
	[pc < ac endpc and: [self bailed not]] whileTrue: [
		(self isStart: pc act: a)
			ifFalse: [pc := pc + 1]
			ifTrue: [
				b := obPcBlocks at: ac pcb + pc.
				(b < 0 and: [self isTarget: pc act: a]) ifTrue: [b := self blockAt: pc act: a].
				b >= 0 ifTrue: [
					(obCurBlock >= 0 and: [obCurBlock ~= b]) ifTrue: [self goto: b].
					obCurBlock := b.
					(self isLoopHead: pc act: a) ifFalse: [self seal: b]].
				obCurBlock < 0
					ifTrue: [pc := self skip: pc act: a]
					ifFalse: [pc := self emit: pc act: a]]]
!
skip: pc act: a
	"The instruction after the one at pc in dead code (a closure's body is skipped with it)."
	| op |
	op := self byteAt: pc act: a.
	op = 16r8F ifTrue: [^pc + 6 + (((self byteAt: pc + 4 act: a) asInt64 << 8) bitOr: (self byteAt: pc + 5 act: a)) asInt32].
	^(pc + (analysis lengthOf: op)) asInt32
! !

!OptBuilder methodsFor: 'variables'!
var: a slot: i
	^(ir act: a) varBase + i
!
defIndex: var block: b
	| key i |
	key := var * OPT_MAX_BLOCKS + b + 1.
	i := (key asUInt32 * 2654435761) asUInt32 >> 15 bitAnd: OPT_DEF_SIZE - 1.
	[(obDefKeys at: i) ~= 0 and: [(obDefKeys at: i) ~= key]] whileTrue: [i := (i + 1) bitAnd: OPT_DEF_SIZE - 1].
	^i
!
write: var value: v
	self write: var value: v in: obCurBlock
!
write: var value: v in: b
	<c: 'void opt_write(int32_t var, int32_t v, int32_t b)'>
	| i |
	i := self defIndex: var block: b.
	(obDefKeys at: i) = 0 ifTrue: [
		obDefCount >= ((OPT_DEF_SIZE quo: 4) * 3) ifTrue: [^self bail].
		obDefCount := obDefCount + 1.
		obDefKeys at: i put: var * OPT_MAX_BLOCKS + b + 1].
	obDefVals at: i put: v
!
read: var
	^self read: var in: obCurBlock
!
writeArg: var value: v
	"An argument: Smalltalk never assigns it, so every read is v (no phis, even in loops not yet closed)."
	var < OPT_MAX_VARS ifTrue: [
		obArgVals at: var put: v.
		obArgFlags at: var put: 1].
	self write: var value: v
!
read: var in: b
	<c: 'int32_t opt_read(int32_t var, int32_t b)'>
	| i v bl phi |
	(var < OPT_MAX_VARS and: [(obArgFlags at: var) ~= 0]) ifTrue: [^ir resolve: (obArgVals at: var)].
	i := self defIndex: var block: b.
	(obDefKeys at: i) ~= 0 ifTrue: [^ir resolve: (obDefVals at: i)].
	bl := ir block: b.
	(bl flags bitAnd: BF_SEALED) = 0
		ifTrue: [
			phi := self newPhi: b var: var.
			obIncCount >= OPT_MAX_INC ifTrue: [
				self bail.
				^phi].
			obIncPhis at: obIncCount put: phi.
			obIncVars at: obIncCount put: var.
			obIncCount := obIncCount + 1.
			v := phi]
		ifFalse: [
			bl npreds = 1
				ifTrue: [v := self read: var in: (ir pred: 0 of: b)]
				ifFalse: [
					bl npreds = 0
						ifTrue: [v := self constant: memory nilOop]
						ifFalse: [
							phi := self newPhi: b var: var.
							self write: var value: phi in: b.
							self addPhiOperands: phi var: var.
							v := phi]]].
	self write: var value: v in: b.
	^v
!
newPhi: b var: var
	| n |
	n := ir newNode: O_PHI rep: R_OOP.
	(ir node: n) aux2: var.
	ir prepend: n to: b.
	^n
!
addPhiOperands: phi var: var
	<c: 'void opt_add_phi_operands(int32_t phi, int32_t var)'>
	| b n args |
	b := (ir node: phi) block.
	n := (ir block: b) npreds.
	args := ir allocOperands: n.
	(ir node: phi) args: args.
	(ir node: phi) nargs: n asUInt16.
	0 to: n - 1 do: [:i | ir operand: args + i put: (self read: var in: (ir pred: i of: b))]
!
seal: b
	"All of b's predecessors are known: complete its phis."
	<c: 'void opt_seal(int32_t b)'>
	| bl k |
	bl := ir block: b.
	(bl flags bitAnd: BF_SEALED) ~= 0 ifTrue: [^self].
	bl flags: (bl flags bitOr: BF_SEALED).
	k := 0.
	[k < obIncCount] whileTrue: [
		(ir node: (obIncPhis at: k)) block = b ifTrue: [
			self addPhiOperands: (obIncPhis at: k) var: (obIncVars at: k).
			obIncCount := obIncCount - 1.
			obIncPhis at: k put: (obIncPhis at: obIncCount).
			obIncVars at: k put: (obIncVars at: obIncCount)]
		ifFalse: [k := k + 1]]
! !

!OptBuilder methodsFor: 'nodes'!
add: op rep: rep
	"A new node at the end of the current block."
	| n |
	n := ir newNode: op rep: rep.
	ir append: n to: obCurBlock.
	^n
!
param: i
	| n |
	n := self add: O_PARAM rep: R_OOP.
	(ir node: n) aux: i.
	^n
!
constant: v
	"A constant oop (in the entry block, so that it dominates every use)."
	<c: 'int32_t opt_constant(uint64_t v)'>
	| n nd |
	n := ir newNode: O_CONST rep: R_OOP.
	nd := ir node: n.
	nd aux: v asInt64.
	nd flags: NF_PURE.
	(self isInt: v) ifTrue: [
		nd tkind: T_SMI.
		nd lo: (self intVal: v).
		nd hi: (self intVal: v)].
	v = memory nilOop ifTrue: [nd tkind: T_NIL].
	(v = memory trueOop or: [v = memory falseOop]) ifTrue: [nd tkind: T_BOOL].
	(v bitAnd: 7) = 4 ifTrue: [nd tkind: T_FLOAT].
	(ir block: obEntryBlock) last >= 0
		ifTrue: [
			((ir node: (ir block: obEntryBlock) last) op asInt32 >= O_GOTO)
				ifTrue: [ir insert: n before: (ir block: obEntryBlock) last]
				ifFalse: [ir append: n to: obEntryBlock]]
		ifFalse: [ir append: n to: obEntryBlock].
	^n
!
binary: op a: x b: y
	| n |
	n := self add: op rep: R_OOP.
	(ir node: n) a: x.
	(ir node: n) b: y.
	^n
!
goto: b
	"End the current block with a jump to b."
	<c: 'void opt_goto(int32_t b)'>
	self add: O_GOTO rep: R_NONE.
	(ir block: obCurBlock) succ0: b.
	ir addPred: obCurBlock to: b.
	obCurBlock := -1
!
blockAt: pc act: a
	"The block that starts at a's pc."
	<c: 'int32_t opt_block_at(int32_t pc, int32_t a)'>
	| b |
	b := obPcBlocks at: (ir act: a) pcb + pc.
	b >= 0 ifTrue: [^b].
	b := ir newBlock.
	(ir block: b) act: a.
	(ir block: b) pc: pc.
	(self isLoopHead: pc act: a) ifTrue: [(ir block: b) flags: BF_LOOP].
	obPcBlocks at: (ir act: a) pcb + pc put: b.
	^b
! !

!OptBuilder methodsFor: 'frame states'!
stateAct: a pc: pc depth: d
	"The frame state of a continuing at pc with d slots, and its callers'."
	<c: 'int32_t opt_make_state(int32_t a, int32_t pc, int32_t d)'>
	| s st ac vals p |
	ac := ir act: a.
	s := ir newState.
	st := ir state: s.
	st act: a.
	st pc: pc.
	st depth: d.
	vals := ir allocOperands: d + 1.
	st vals: vals.
	ir operand: vals put: ac receiver.
	0 to: d - 1 do: [:i | ir operand: vals + 1 + i put: (self read: (self var: a slot: i))].
	p := ac parent.
	p >= 0 ifTrue: [(ir state: s) parent: (self stateAct: p pc: (ac sendPc + (analysis lengthOf: (self byteAt: ac sendPc act: p))) asInt32 depth: (self receiverSlotAt: ac sendPc act: p))].
	^s
!
receiverSlotAt: pc act: a
	"The slot of the receiver of the send the instruction at pc makes."
	| p |
	p := (self methodBytecodes: (ir act: a) method) + pc.
	(analysis pushesOf: p) > 0 ifTrue: [^self depthAt: pc act: a].
	^(self depthAt: pc act: a) - (analysis sendArgcOf: p) - 1
!
checkInterruptAct: a pc: pc depth: d kind: k
	| n |
	n := self add: O_CHECKINT rep: R_NONE.
	obSafeEpoch := obSafeEpoch + 1.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	(ir node: n) aux: k.
	^n
! !

!OptBuilder methodsFor: 'bytecodes'!
emit: pc act: a
	"Build the instruction at a's pc; answer the next pc."
	<c: 'int32_t opt_emit(int32_t pc, int32_t a)'>
	| op d next v |
	ir origin: a pc: pc.
	op := self byteAt: pc act: a.
	d := self depthAt: pc act: a.
	next := (pc + (analysis lengthOf: op)) asInt32.
	op < 16r10 ifTrue: [
		self push: (self read: (self var: a slot: op)) act: a depth: d.
		^next].
	op < 16r20 ifTrue: [
		self push: (self loadField: op - 16r10 of: (ir act: a) receiver) act: a depth: d.
		^next].
	op < 16r40 ifTrue: [
		self push: (self constant: (self literal: op - 16r20 act: a)) act: a depth: d.
		^next].
	op < 16r60 ifTrue: [
		self push: (self loadField: ASSOC_VALUE of: (self constant: (self literal: op - 16r40 act: a))) act: a depth: d.
		^next].
	op < 16r68 ifTrue: [
		self write: (self var: a slot: op - 16r60) value: (self read: (self var: a slot: d - 1)).
		^next].
	op = 16r70 ifTrue: [
		self push: (ir act: a) receiver act: a depth: d.
		^next].
	op = 16r71 ifTrue: [
		self push: (self constant: memory trueOop) act: a depth: d.
		^next].
	op = 16r72 ifTrue: [
		self push: (self constant: memory falseOop) act: a depth: d.
		^next].
	op = 16r73 ifTrue: [
		self push: (self constant: memory nilOop) act: a depth: d.
		^next].
	op = 16r74 ifTrue: [
		self push: (self constant: (self intOop: 0)) act: a depth: d.
		^next].
	op = 16r75 ifTrue: [
		self push: (self constant: (self intOop: 1)) act: a depth: d.
		^next].
	op = 16r77 ifTrue: [
		self push: (self read: (self var: a slot: d - 1)) act: a depth: d.
		^next].
	op = 16r78 ifTrue: [^next].
	(op = 16r79 or: [op = 16r7B]) ifTrue: [
		self localReturn: (self read: (self var: a slot: d - 1)) act: a pc: pc depth: d.
		^next].
	op = 16r7A ifTrue: [
		self localReturn: (ir act: a) receiver act: a pc: pc depth: d.
		^next].
	op = 16r80 ifTrue: [
		self push: (self read: (self var: a slot: (self byteAt: pc + 1 act: a))) act: a depth: d.
		^next].
	op = 16r81 ifTrue: [
		self push: (self loadField: (self byteAt: pc + 1 act: a) of: (ir act: a) receiver) act: a depth: d.
		^next].
	op = 16r82 ifTrue: [
		self push: (self constant: (self literal: (self byteAt: pc + 1 act: a) act: a)) act: a depth: d.
		^next].
	op = 16r83 ifTrue: [
		self push: (self loadField: ASSOC_VALUE of: (self constant: (self literal: (self byteAt: pc + 1 act: a) act: a))) act: a depth: d.
		^next].
	op = 16r84 ifTrue: [
		self write: (self var: a slot: (self byteAt: pc + 1 act: a)) value: (self read: (self var: a slot: d - 1)).
		^next].
	op = 16r85 ifTrue: [
		self storeField: (self byteAt: pc + 1 act: a) of: (ir act: a) receiver value: (self read: (self var: a slot: d - 1))
			checked: (self stateAct: a pc: pc depth: d).
		^next].
	(op = 16r86 or: [op = 16r89]) ifTrue: [
		self storeField: ASSOC_VALUE of: (self constant: (self literal: (self byteAt: pc + 1 act: a) act: a)) value: (self read: (self var: a slot: d - 1)) checked: -1.
		^next].
	op = 16r87 ifTrue: [
		self write: (self var: a slot: (self byteAt: pc + 1 act: a)) value: (self read: (self var: a slot: d - 1)).
		^next].
	op = 16r90 ifTrue: [
		self jumpTo: (pc + 3 + (self int16At: pc + 1 act: a)) from: pc act: a.
		^next].
	(op = 16r91 or: [op = 16r92]) ifTrue: [
		self conditionalJump: pc act: a.
		^next].
	op = 16r93 ifTrue: [
		self push: (self constant: (self intOop: (self int16At: pc + 1 act: a))) act: a depth: d.
		^next].
	(op = 16r8D or: [op = 16r8E or: [op >= 16rC0 and: [op < 16rF0]]]) ifTrue: [
		self send: pc act: a.
		^next].
	((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [
		self superinstruction: pc act: a.
		^next].
	(op >= 16rA0 and: [op < 16rC0]) ifTrue: [
		self special: op - 16rA0 pc: pc act: a rcvSlot: d - (analysis specialArgc: op - 16rA0) - 1.
		^next].
	op = 16r8F ifTrue: [
		v := self closureAt: pc act: a.
		self push: v act: a depth: d.
		^(pc + 6 + (((self byteAt: pc + 4 act: a) asInt64 << 8) bitOr: (self byteAt: pc + 5 act: a))) asInt32].
	(op >= 16r8A and: [op <= 16r8C]) ifTrue: [
		self outerTemp: pc act: a depth: d.
		^next].
	op = 16r7C ifTrue: [
		self nonLocalReturn: (self read: (self var: a slot: d - 1)) act: a pc: pc depth: d.
		^next].
	"thisContext, Arrays: not yet"
	self bail.
	^next
!
closureAt: pc act: a
	"0x8F: a BlockClosure for the body after pc; as long as it is only evaluated by inlined value sends it is never made (its frame states describe it)."
	| n na nt fs |
	na := self byteAt: pc + 1 act: a.
	nt := self byteAt: pc + 2 act: a.
	fs := self byteAt: pc + 3 act: a.
	n := self add: O_CLOSURE rep: R_OOP.
	(ir node: n) aux: pc + 6.
	(ir node: n) aux2: (((na asInt64 bitOr: nt asInt64 << 8) bitOr: fs asInt64 << 16) bitOr: a asInt64 << 32).
	(ir node: n) tkind: T_OBJ.
	(ir node: n) tcls: memory clsBlock.
	(ir node: n) flags: NF_PURE.
	^n
!
outerTemp: pc act: a depth: d
	"push (8A), store (8B), pop and store (8C) a temp of an enclosing block or method: inlined, it is that activation's variable."
	| op t v lv |
	op := self byteAt: pc act: a.
	t := a.
	lv := (self byteAt: pc + 1 act: a) asInt32.
	[lv > 0 and: [(ir act: t) outer >= 0]] whileTrue: [
		t := (ir act: t) outer.
		lv := lv - 1].
	lv > 0 ifTrue: [
		(t = 0 and: [obUnitStart > 0]) ifFalse: [^self bail].
		^self outerTemp: op levels: lv index: (self byteAt: pc + 2 act: a) act: a depth: d].
	op = 16r8A ifTrue: [^self push: (self read: (self var: t slot: (self byteAt: pc + 2 act: a))) act: a depth: d].
	v := self read: (self var: a slot: d - 1).
	self write: (self var: t slot: (self byteAt: pc + 2 act: a)) value: v
!
outerTemp: op levels: lv index: i act: a depth: d
	"An outer temp of the block unit's closure, lv levels out: in its outerContext chain (or the frame it is married to)."
	| n |
	n := self add: (op = 16r8A ifTrue: [O_OUTERLOAD] ifFalse: [O_OUTERSTORE]) rep: (op = 16r8A ifTrue: [R_OOP] ifFalse: [R_NONE]).
	(ir node: n) a: (ir act: 0) closure.
	(ir node: n) aux: lv.
	(ir node: n) aux2: i.
	op = 16r8A ifTrue: [^self push: n act: a depth: d].
	(ir node: n) b: (self read: (self var: a slot: d - 1))
!
nonLocalReturn: v act: a pc: pc depth: d
	"^ in a block: return from its home method, inlined here (or the method compiled); in a block unit the interpreter does it."
	| h n |
	h := (ir act: a) home.
	(h < 0 and: [obUnitStart > 0]) ifTrue: [^self deoptAct: a state: (self stateAct: a pc: pc depth: d)].
	(h < 0 or: [(ir act: h) closure >= 0]) ifTrue: [^self bail].
	(ir act: h) parent >= 0 ifTrue: [
		self write: (ir act: h) retVar value: v.
		^self goto: (ir act: h) retBlock].
	n := self add: O_RETURN rep: R_NONE.
	(ir node: n) a: v.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	obCurBlock := -1
!
isValueSelector: sel
	"sel is value or value: repeated."
	| b n |
	((self isPtr: sel) and: [(self formatOf: sel) >= F_BYTES]) ifFalse: [^false].
	n := (memory byteSize: sel) asInt64.
	b := self bytesOf: sel.
	(n >= 5 and: [(b at: 0) = $v value and: [(b at: 1) = $a value and: [(b at: 2) = $l value and: [(b at: 3) = $u value and: [(b at: 4) = $e value]]]]]) ifFalse: [^false].
	n = 5 ifTrue: [^true].
	(n rem: 6) = 0 ifFalse: [^false].
	0 to: (n quo: 6) - 1 do: [:i |
		((b at: 6 * i) = $v value and: [(b at: 6 * i + 5) = $: value]) ifFalse: [^false]].
	^true
!
isClosure: v numArgs: n
	"v is a closure this compilation made, taking n arguments."
	| nd |
	nd := ir node: (ir resolve: v).
	^nd op asInt32 = O_CLOSURE and: [(nd aux2 bitAnd: 255) = n]
!
inlineBlock: c pc: pc act: a rcvSlot: r argc: argc
	"Evaluate closure c (made in this compilation) here: its body as an activation whose outer activation is the one that made it."
	<c: 'void opt_inline_block(int32_t c, int32_t pc, int32_t a, int32_t r, int32_t argc)'>
	| b ac def nd entry ret na nt fs size |
	nd := ir node: c.
	def := (nd aux2 >> 32) asInt32.
	na := (nd aux2 bitAnd: 255) asInt32.
	nt := ((nd aux2 >> 8) bitAnd: 255) asInt32.
	fs := ((nd aux2 >> 16) bitAnd: 255) asInt32.
	b := ir newAct.
	ac := ir act: b.
	ac method: (ir act: def) method.
	ac ana: (ir act: def) ana.
	ac numArgs: na.
	ac numTemps: nt.
	fs < (na + nt) ifTrue: [fs := na + nt].
	ac nslots: fs + 4.
	ac startpc: nd aux asInt32.
	size := ((self byteAt: nd aux asInt32 - 2 act: def) asInt64 << 8 bitOr: (self byteAt: nd aux asInt32 - 1 act: def)) asInt32.
	ac endpc: nd aux asInt32 + size.
	ac closure: c.
	ac outer: def.
	ac home: (ir act: def) home.
	ac receiver: (ir act: def) receiver.
	ac parent: a.
	ac sendPc: pc.
	ac sendArgc: argc.
	(self allocPcBlocks: b) ifFalse: [^self].
	ac varBase: obVarTop.
	ac retVar: obVarTop + ac nslots.
	obVarTop := obVarTop + ac nslots + 1.
	obInlined := obInlined + size.
	0 to: argc - 1 do: [:i | self writeArg: (self var: b slot: i) value: (self read: (self var: a slot: r + 1 + i))].
	argc to: argc + nt - 1 do: [:i | self write: (self var: b slot: i) value: (self constant: memory nilOop)].
	entry := ir newBlock.
	(ir block: entry) act: b.
	ret := ir newBlock.
	(ir block: ret) act: a.
	ac retBlock: ret.
	self goto: entry.
	obCurBlock := entry.
	self seal: entry.
	self buildAct: b.
	ir origin: a pc: pc.
	self seal: ret.
	(ir block: ret) npreds = 0 ifTrue: [
		obCurBlock := -1.
		^self].
	obCurBlock := ret.
	self write: (self var: a slot: r) value: (self read: (ir act: b) retVar)
!
escapingClosure
	"A closure that something other than a frame state uses (it would have to be made): the activation that made it, -1 if there is none."
	<c: 'int32_t opt_escaping_closure(void)'>
	| nd |
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd block >= 0 and: [(nd flags bitAnd: NF_DEAD) = 0]) ifTrue: [
			(self usesClosure: nd a) ifTrue: [^self definingActOf: nd a].
			(self usesClosure: nd b) ifTrue: [^self definingActOf: nd b].
			(self usesClosure: nd c) ifTrue: [^self definingActOf: nd c].
			nd op asInt32 ~= O_PHI ifTrue: [
				0 to: nd nargs asInt32 - 1 do: [:i | (self usesClosure: (ir operand: nd args + i)) ifTrue: [^self definingActOf: (ir operand: nd args + i)]]].
			nd op asInt32 = O_PHI ifTrue: [
				0 to: nd nargs asInt32 - 1 do: [:i | (self usesClosure: (ir operand: nd args + i)) ifTrue: [^self definingActOf: (ir operand: nd args + i)]]]]].
	^-1
!
usesClosure: v
	v < 0 ifTrue: [^false].
	^(ir node: (ir resolve: v)) op asInt32 = O_CLOSURE
!
definingActOf: v
	^((ir node: (ir resolve: v)) aux2 >> 32) asInt32
!
push: v act: a depth: d
	self write: (self var: a slot: d) value: v
!
loadField: i of: o
	| n |
	n := self add: O_LOADFIELD rep: R_OOP.
	(ir node: n) a: o.
	(ir node: n) aux: i.
	^n
!
storeField: i of: o value: v checked: s
	"Store v into o's field i; s >= 0: the state if o is immutable (the interpreter sends attemptToAssign:withIndex:)."
	| n |
	n := self add: O_STOREFIELD rep: R_NONE.
	(ir node: n) a: o.
	(ir node: n) b: v.
	(ir node: n) aux: i.
	(ir node: n) state: s.
	^n
!
localReturn: v act: a pc: pc depth: d
	"Return v: from the method (the state is for the interpreter to return from the bottom frame), or from an inlined activation to its caller."
	| n |
	(ir act: a) parent >= 0 ifTrue: [
		self write: (ir act: a) retVar value: v.
		^self goto: (ir act: a) retBlock].
	n := self add: O_RETURN rep: R_NONE.
	(ir node: n) a: v.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	obCurBlock := -1
!
jumpTo: t from: pc act: a
	| b |
	b := self blockAt: t act: a.
	"a backward jump checks for interrupts before it is taken (at its pc, its condition still on the stack)"
	t <= pc ifTrue: [self checkInterruptAct: a pc: pc depth: (self depthAt: pc act: a) kind: SP_LOOP].
	self goto: b.
	(t <= pc and: [(self lastBackJumpTo: t act: a) = pc]) ifTrue: [self seal: b]
!
conditionalJump: pc act: a
	"Pop, jump to t if true (0x91) or false (0x92); neither: deoptimize (the interpreter sends mustBeBoolean)."
	| op t d v taken fall n onTrue onFalse k back c |
	op := self byteAt: pc act: a.
	t := pc + 3 + (self int16At: pc + 1 act: a).
	d := self depthAt: pc act: a.
	v := self read: (self var: a slot: d - 1).
	back := t <= pc.
	fall := self blockAt: pc + 3 act: a.
	taken := self blockAt: t act: a.
	k := (ir node: v) op asInt32.
	k = O_CONST ifTrue: [
		c := (ir node: v) aux asUInt64.
		(c = memory trueOop or: [c = memory falseOop]) ifTrue: [
			(c = memory trueOop) = (op = 16r91)
				ifTrue: [self jumpTo: t from: pc act: a]
				ifFalse: [self goto: fall].
			^self]].
	back ifTrue: [
		"the backward edge goes through an interrupt check"
		n := ir newBlock.
		(ir block: n) act: a.
		(ir block: n) flags: BF_SEALED.
		taken := n].
	onTrue := op = 16r91 ifTrue: [taken] ifFalse: [fall].
	onFalse := op = 16r91 ifTrue: [fall] ifFalse: [taken].
	n := self add: O_BRANCH rep: R_NONE.
	(ir node: n) a: v.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	(ir block: obCurBlock) succ0: onTrue.
	(ir block: obCurBlock) succ1: onFalse.
	ir addPred: obCurBlock to: onTrue.
	ir addPred: obCurBlock to: onFalse.
	obCurBlock := -1.
	back ifTrue: [
		obCurBlock := taken.
		self jumpTo: t from: pc act: a]
! !

!OptBuilder methodsFor: 'sends'!
send: pc act: a
	<var: #kind type: 'int32_t'>
	| op argc sel kind |
	op := self byteAt: pc act: a.
	op >= 16rC0
		ifTrue: [
			argc := ((op - 16rC0) >> 4) asInt32.
			sel := self literal: (op bitAnd: 15) act: a.
			kind := 0]
		ifFalse: [
			argc := (self byteAt: pc + 2 act: a) asInt32.
			sel := self literal: (self byteAt: pc + 1 act: a) act: a.
			kind := op = 16r8E ifTrue: [1] ifFalse: [0]].
	self sendSelector: sel argc: argc kind: kind special: 0 pc: pc act: a rcvSlot: (self depthAt: pc act: a) - argc - 1
!
superinstruction: pc act: a
	"push temp a, push temp / literal / int8 b, then a special selector: the operands are pushed as the interpreter would."
	| op x y k d |
	op := self byteAt: pc act: a.
	d := self depthAt: pc act: a.
	x := self read: (self var: a slot: (self byteAt: pc + 1 act: a)).
	(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]])
		ifTrue: [y := self read: (self var: a slot: (self byteAt: pc + 2 act: a))]
		ifFalse: [
			(op = 16r98 or: [op >= 16rF0 and: [op < 16rF6]])
				ifTrue: [y := self constant: (self literal: (self byteAt: pc + 2 act: a) act: a)]
				ifFalse: [y := self constant: (self intOop: (self byteAt: pc + 2 act: a) asInt8)]].
	self push: x act: a depth: d.
	self push: y act: a depth: d + 1.
	k := analysis specialIndexOf: (self methodBytecodes: (ir act: a) method) + pc.
	self special: k pc: pc act: a rcvSlot: d
!
special: k pc: pc act: a rcvSlot: r
	"Special selector k at pc, receiver in slot r: inline what needs no send, else send it."
	| x y n argc fl |
	argc := analysis specialArgc: k.
	x := self read: (self var: a slot: r).
	argc > 0 ifTrue: [y := self read: (self var: a slot: r + 1)].
	(k = 19 or: [k = 20]) ifTrue: [
		self push: (self binary: (k = 19 ifTrue: [O_EQ] ifFalse: [O_NE]) a: x b: y) act: a depth: r.
		^self].
	((k = 21 or: [k = 22 or: [k = 30]]) and: [(runtime flag: runtime blocksFlag) and: [self isClosure: x numArgs: argc]]) ifTrue: [
		^self inlineBlock: (ir resolve: x) pc: pc act: a rcvSlot: r argc: argc].
	k = 29 ifTrue: [
		n := self add: O_CLASSOF rep: R_OOP.
		(ir node: n) a: x.
		self push: n act: a depth: r.
		^self].
	(k >= 16 and: [k <= 18 and: [(self knownClassOf: x) = 0 and: [(runtime flag: runtime primsFlag) and: [(feedback siteAt: (ir act: a) method pc: pc) isNull]]]]) ifTrue: [
		"no feedback: the lower tier's Array fast path took them all"
		self write: (self var: a slot: r) value: (self guard: x class: memory clsArray state: (self stateAct: a pc: pc depth: (self depthAt: pc act: a)))].
	(k <= 9 or: [k = 14 or: [k = 15]]) ifTrue: [
		fl := feedback flagsAt: (ir act: a) method pc: pc.
		(k <= 9 and: [(fl bitAnd: (feedback sawNonInt bitOr: feedback deoptOther)) = 0 and: [
			(fl bitAnd: feedback sawFloat) ~= 0 or: [(self isFloat: x) or: [(self isFloat: y) or: [self sawFloatIn: (ir act: a) method]]]]]) ifTrue: [
				^self floatArith: k x: x y: y pc: pc act: a rcvSlot: r].
		(k ~= 9 and: [(fl bitAnd: ((feedback sawFloat bitOr: feedback sawNonInt) bitOr: (feedback deoptArith bitOr: feedback overflowed))) = 0 and: [
			(self sawOnlyIntsAt: pc act: a)]]) ifTrue: [
				^self intArith: k x: x y: y pc: pc act: a rcvSlot: r]].
	self sendSelector: (self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: k) argc: argc kind: 2 special: k pc: pc act: a rcvSlot: r
!
sawOnlyIntsAt: pc act: a
	"The send at a's pc reported no receiver class but SmallInteger (the lower tier's inline paths report none)."
	| site |
	site := feedback siteAt: (ir act: a) method pc: pc.
	site isNull ifTrue: [^true].
	0 to: feedback classSlots - 1 do: [:i |
		((site classes at: i) ~= 0 and: [(site classes at: i) ~= memory clsSmallint]) ifTrue: [^false]].
	^true
!
intArith: k x: x y: y pc: pc act: a rcvSlot: r
	"SmallInteger arithmetic or comparison, speculated: guards deoptimize to the send."
	| s gx gy n |
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	gx := self guardInt: x state: s.
	gy := self guardInt: y state: s.
	(k >= 2 and: [k <= 7]) ifTrue: [
		n := self binary: O_ICMP a: gx b: gy.
		(ir node: n) aux: k.
		(ir node: n) tkind: T_BOOL.
		self push: n act: a depth: r.
		^self].
	n := self binary: (k caseOf: {[0] -> [O_IADD]. [1] -> [O_ISUB]. [8] -> [O_IMUL]. [14] -> [O_IAND]} otherwise: [O_IOR]) a: gx b: gy.
	(ir node: n) tkind: T_SMI.
	(k <= 1 or: [k = 8]) ifTrue: [(ir node: n) state: s].
	self push: n act: a depth: r
!
floatArith: k x: x y: y pc: pc act: a rcvSlot: r
	"Float arithmetic or comparison k, speculated: SmallFloat64 or SmallInteger operands as doubles (two SmallIntegers: the SmallInteger operation), the result a SmallFloat64; anything else deoptimizes to the send."
	<c: 'void opt_float_arith(int32_t k, int32_t x, int32_t y, int32_t pc, int32_t a, int32_t r)'>
	<var: #merge type: 'int32_t'>
	| s fx fy n merge t f test fl |
	fl := feedback flagsAt: (ir act: a) method pc: pc.
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	merge := -1.
	((self isFloat: x) or: [self isFloat: y]) ifFalse: [
		test := self binary: O_BOTHINT a: x b: y.
		(ir node: test) tkind: T_BOOL.
		t := ir newBlock.
		(ir block: t) act: a.
		f := ir newBlock.
		(ir block: f) act: a.
		merge := ir newBlock.
		(ir block: merge) act: a.
		self branch: test true: t false: f.
		self seal: t.
		self seal: f.
		obCurBlock := t.
		(k = 9 or: [(fl bitAnd: (feedback deoptArith bitOr: feedback overflowed)) ~= 0])
			ifTrue: [self callSelector: (self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: k) argc: 1 kind: 2 special: k pc: pc act: a rcvSlot: r]
			ifFalse: [self intArith: k x: (self cast: x class: memory clsSmallint) y: (self cast: y class: memory clsSmallint) pc: pc act: a rcvSlot: r].
		self goto: merge.
		obCurBlock := f].
	fx := self unboxFloat: x state: s.
	fy := self unboxFloat: y state: s.
	(k >= 2 and: [k <= 7])
		ifTrue: [
			n := self binary: O_FCMP a: fx b: fy.
			(ir node: n) aux: k.
			(ir node: n) tkind: T_BOOL.
			self push: n act: a depth: r]
		ifFalse: [
			n := self add: O_FARITH rep: R_DBL.
			(ir node: n) a: fx.
			(ir node: n) b: fy.
			(ir node: n) aux: k.
			k = 9 ifTrue: [(ir node: n) state: s].
			self push: (self boxFloat: n state: s) act: a depth: r].
	merge >= 0 ifTrue: [
		self goto: merge.
		self seal: merge.
		obCurBlock := merge]
!
sawFloatIn: m
	"Some arithmetic of m saw a Float (its other arithmetic may well too)."
	0 to: obAnaCount - 1 do: [:i | (obAnaMethods at: i) = m ifTrue: [^obAnaFloat at: i]].
	^false
!
isFloat: v
	^(ir node: (ir resolve: v)) tkind asInt32 = T_FLOAT
!
unboxFloat: v state: s
	"v as a double: a SmallFloat64 decoded, a SmallInteger converted, else deoptimize; a value this block boxed since the last safepoint is used directly."
	| nd n |
	nd := ir node: v.
	(nd op asInt32 = O_BOXF and: [nd block = obCurBlock and: [nd aux2 = obSafeEpoch]]) ifTrue: [^nd a].
	n := self add: O_UNBOXF rep: R_DBL.
	(ir node: n) a: v.
	(ir node: n) state: s.
	(ir node: n) flags: NF_GUARD.
	^n
!
boxFloat: d state: s
	"Double d as a SmallFloat64; out of its range: deoptimize (the interpreter makes a boxed Float)."
	| n |
	n := self add: O_BOXF rep: R_OOP.
	(ir node: n) a: d.
	(ir node: n) state: s.
	(ir node: n) tkind: T_FLOAT.
	(ir node: n) aux2: obSafeEpoch.
	^n
!
guardInt: v state: s
	| n |
	(ir node: v) tkind asInt32 = T_SMI ifTrue: [^v].
	n := self add: O_GUARDINT rep: R_OOP.
	(ir node: n) a: v.
	(ir node: n) state: s.
	(ir node: n) tkind: T_SMI.
	(ir node: n) flags: NF_GUARD.
	^n
!
sendSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
	"A send: inlined (or called) for the receiver's class if it is known, for each class feedback saw (guarded), else through the runtime."
	((runtime flag: runtime blocksFlag) and: [(self isValueSelector: sel) and: [self isClosure: (self read: (self var: a slot: r)) numArgs: argc]]) ifTrue: [
		self inlineBlock: (ir resolve: (self read: (self var: a slot: r))) pc: pc act: a rcvSlot: r argc: argc.
		^-1].
	((runtime flag: runtime inlineFlag) and: [self inlineSend: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r]) ifTrue: [^-1].
	^self callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
!
inlineSend: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
	"Inline the send for the receiver classes it is known or speculated to have; answer whether it did."
	<c: 'bool opt_inline_send(uint64_t sel, int32_t argc, int32_t kind, int32_t k, int32_t pc, int32_t a, int32_t r)'>
	| rcv cls site n merge s test next t g fl |
	rcv := self read: (self var: a slot: r).
	kind = 1 ifTrue: [
		cls := self loadRef: (self loadRef: (ir act: a) method at: CM_CLASS) at: BEH_SUPERCLASS.
		^self send: sel to: rcv class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r].
	cls := self knownClassOf: rcv.
	cls ~= 0 ifTrue: [^self send: sel to: rcv class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r].
	site := feedback siteAt: (ir act: a) method pc: pc.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'opt: send at pc %d of act %d: feedback %s ' with: pc with: a with: (site isNull ifTrue: ['none'] ifFalse: ['some']).
		interpreter printSymbol: sel on: libc stderr.
		libc fputc: 10 to: libc stderr].
	site isNull ifTrue: [^false].
	fl := site flags.
	(fl bitAnd: ((feedback mega bitOr: feedback deoptClass) bitOr: feedback deoptOther)) ~= 0 ifTrue: [^false].
	n := 0.
	0 to: feedback classSlots - 1 do: [:i | (site classes at: i) ~= 0 ifTrue: [n := n + 1]].
	n = 0 ifTrue: [^false].
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	n = 1 ifTrue: [
		g := self guard: rcv class: (site classes at: 0) state: s.
		^self send: sel to: g class: (site classes at: 0) argc: argc kind: kind pc: pc act: a rcvSlot: r].
	"a type switch; any other class deoptimizes"
	merge := ir newBlock.
	(ir block: merge) act: a.
	0 to: n - 1 do: [:i |
		cls := site classes at: i.
		test := self add: O_CLASSIS rep: R_OOP.
		(ir node: test) a: rcv.
		(ir node: test) aux: cls asInt64.
		(ir node: test) tkind: T_BOOL.
		t := ir newBlock.
		(ir block: t) act: a.
		next := ir newBlock.
		(ir block: next) act: a.
		self branch: test true: t false: next.
		self seal: t.
		self seal: next.
		obCurBlock := t.
		g := self cast: rcv class: cls.
		self write: (self var: a slot: r) value: g.
		(self send: sel to: g class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r) ifFalse: [
			self callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r].
		obCurBlock >= 0 ifTrue: [self goto: merge].
		obCurBlock := next].
	self deoptAct: a state: s.
	self seal: merge.
	obCurBlock := (ir block: merge) npreds > 0 ifTrue: [merge] ifFalse: [-1].
	^true
!
send: sel to: rcv class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r
	"The receiver's class is cls: inline the method it finds, else send. Answer false only if nothing was emitted."
	| m n |
	m := interpreter lookupMethod: cls selector: sel.
	m = 0 ifTrue: [^false].
	self noteDependency: sel.
	self write: (self var: a slot: r) value: rcv.
	((runtime flag: runtime allocFlag) and: [self allocate: m selector: sel class: cls argc: argc pc: pc act: a rcvSlot: r]) ifTrue: [^true].
	((self methodPrimitive: m) ~= 0 and: [(runtime flag: runtime primsFlag) and: [
		self inlinePrimitive: (self methodPrimitive: m) class: cls argc: argc pc: pc act: a rcvSlot: r]]) ifTrue: [^true].
	(self canInline: m act: a) ifTrue: [
		self inlineMethod: m receiverClass: cls pc: pc act: a rcvSlot: r argc: argc.
		^true].
	(self loadRef: m at: CM_PRIMITIVE) = (self intOop: 0) ifTrue: [
		((runtime flag: runtime callsFlag) and: [runtime codeAddressOf: m]) ifTrue: [
			"a direct call: the frame pushed inline, no lookup"
			n := self callSelector: sel argc: argc kind: 0 special: 0 pc: pc act: a rcvSlot: r.
			(ir node: n) op: O_CALL.
			(ir node: n) tcls: m.
			^true]].
	self callSelector: sel argc: argc kind: (kind = 1 ifTrue: [1] ifFalse: [0]) special: 0 pc: pc act: a rcvSlot: r.
	^true
!
allocate: m selector: sel class: cls argc: argc pc: pc act: a rcvSlot: r
	"m is basicNew or basicNew: and the receiver (of metaclass cls) a class whose instances have pointer slots: the send with a fast path that allocates in eden (NF_ALLOC; c: format and fixed fields); answer whether it is one."
	| kind inst fo spec isize fmt n |
	kind := self primKindOf: (self methodPrimitive: m).
	((kind = PK_NEW and: [argc = 0]) or: [kind = PK_NEWSIZE and: [argc = 1]]) ifFalse: [^false].
	inst := self loadRef: cls at: META_THISCLASS.
	((self isPtr: inst) and: [(self classOf: inst) = cls]) ifFalse: [^false].
	fo := self loadRef: inst at: BEH_FORMAT.
	(self isInt: fo) ifFalse: [^false].
	spec := (self intVal: fo) >> CLS_SPEC_SHIFT.
	isize := (self intVal: fo) bitAnd: CLS_INSTSIZE_MASK.
	kind = PK_NEW
		ifTrue: [
			spec <= 1 ifFalse: [^false].
			fmt := isize ~= 0 ifTrue: [F_FIXED] ifFalse: [F_EMPTY]]
		ifFalse: [
			(spec = 2 or: [spec = 3]) ifFalse: [^false].
			fmt := (isize ~= 0 or: [spec = 3]) ifTrue: [F_FIXVAR] ifFalse: [F_VAR]].
	n := self callSelector: sel argc: argc kind: 0 special: 0 pc: pc act: a rcvSlot: r.
	(ir node: n) flags: ((ir node: n) flags bitOr: NF_ALLOC).
	(ir node: n) c: (fmt bitOr: isize << 8) asInt32.
	(ir node: n) tkind: T_OBJ.
	(ir node: n) tcls: inst.
	^true
!
primKindOf: p
	"What the optimizer knows primitive p to be (PK_*), 0 if nothing."
	obPrimsKnown ifFalse: [
		obPrimsKnown := true.
		libc memset: obPrimKinds value: 0 size: OPT_MAX_PRIM.
		self primNamed: 'at' kind: PK_AT.
		self primNamed: 'atPut' kind: PK_ATPUT.
		self primNamed: 'basicSize' kind: PK_SIZE.
		self primNamed: 'stringAt' kind: PK_STRINGAT.
		self primNamed: 'stringAtPut' kind: PK_STRINGATPUT.
		self primNamed: 'class' kind: PK_CLASS.
		self primNamed: 'identical' kind: PK_IDENTICAL.
		self primNamed: 'intAdd' kind: PK_INT + 0.
		self primNamed: 'intSub' kind: PK_INT + 1.
		self primNamed: 'intLess' kind: PK_INT + 2.
		self primNamed: 'intGreater' kind: PK_INT + 3.
		self primNamed: 'intLessEq' kind: PK_INT + 4.
		self primNamed: 'intGreaterEq' kind: PK_INT + 5.
		self primNamed: 'intEq' kind: PK_INT + 6.
		self primNamed: 'intNotEq' kind: PK_INT + 7.
		self primNamed: 'intMul' kind: PK_INT + 8.
		self primNamed: 'intBitAnd' kind: PK_INT + 14.
		self primNamed: 'intBitOr' kind: PK_INT + 15.
		self primNamed: 'floatAdd' kind: PK_FLOAT + 0.
		self primNamed: 'floatSub' kind: PK_FLOAT + 1.
		self primNamed: 'floatLess' kind: PK_FLOAT + 2.
		self primNamed: 'floatGreater' kind: PK_FLOAT + 3.
		self primNamed: 'floatLessEq' kind: PK_FLOAT + 4.
		self primNamed: 'floatGreaterEq' kind: PK_FLOAT + 5.
		self primNamed: 'floatEq' kind: PK_FLOAT + 6.
		self primNamed: 'floatNotEq' kind: PK_FLOAT + 7.
		self primNamed: 'floatMul' kind: PK_FLOAT + 8.
		self primNamed: 'floatDiv' kind: PK_FLOAT + 9.
		self primNamed: 'floatSqrt' kind: PK_FSQRT.
		self primNamed: 'basicNew' kind: PK_NEW.
		self primNamed: 'basicNew:' kind: PK_NEWSIZE].
	(p <= 0 or: [p >= OPT_MAX_PRIM]) ifTrue: [^0].
	^(obPrimKinds at: p) asInt32
!
primNamed: name kind: k
	| p |
	p := runtime primitiveNumberNamed: name.
	(p > 0 and: [p < OPT_MAX_PRIM]) ifTrue: [obPrimKinds at: p put: k asUInt8]
!
inlinePrimitive: p class: cls argc: argc pc: pc act: a rcvSlot: r
	"The receiver (of class cls) is in a's slot r: inline primitive p if the optimizer knows it for cls (a failure deoptimizes to the send); answer whether it did."
	<c: 'bool opt_inline_primitive(int64_t p, uint64_t cls, int32_t argc, int32_t pc, int32_t a, int32_t r)'>
	| kind fmt spec fixed ek rcv s n idx val fl |
	kind := self primKindOf: p.
	kind = 0 ifTrue: [^false].
	rcv := self read: (self var: a slot: r).
	(kind = PK_CLASS and: [argc = 0]) ifTrue: [
		n := self add: O_CLASSOF rep: R_OOP.
		(ir node: n) a: rcv.
		self push: n act: a depth: r.
		^true].
	(kind = PK_IDENTICAL and: [argc = 1]) ifTrue: [
		self push: (self binary: O_EQ a: rcv b: (self read: (self var: a slot: r + 1))) act: a depth: r.
		^true].
	(kind >= PK_FLOAT or: [kind = PK_FSQRT]) ifTrue: [
		(cls = memory clsSmallfloat and: [((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: (feedback sawNonInt bitOr: feedback deoptOther)) = 0]) ifFalse: [^false].
		(kind = PK_FSQRT and: [argc = 0]) ifTrue: [
			s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
			idx := self unboxFloat: rcv state: s.
			n := self add: O_FSQRT rep: R_DBL.
			(ir node: n) a: idx.
			self push: (self boxFloat: n state: s) act: a depth: r.
			^true].
		argc = 1 ifFalse: [^false].
		self floatArith: (kind - PK_FLOAT) asInt32 x: rcv y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r.
		^true].
	(kind >= PK_INT and: [argc = 1]) ifTrue: [
		cls = memory clsSmallint ifFalse: [^false].
		fl := feedback flagsAt: (ir act: a) method pc: pc.
		"the argument was not always a SmallInteger: Floats as doubles, else the send"
		(fl bitAnd: ((feedback sawFloat bitOr: feedback sawNonInt) bitOr: (feedback deoptArith bitOr: feedback overflowed))) ~= 0 ifTrue: [
			(kind - PK_INT <= 9 and: [(fl bitAnd: feedback sawFloat) ~= 0 and: [(fl bitAnd: (feedback sawNonInt bitOr: feedback deoptOther)) = 0]]) ifFalse: [^false].
			self floatArith: (kind - PK_INT) asInt32 x: rcv y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r.
			^true].
		self intArith: kind - PK_INT x: rcv y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r.
		^true].
	fmt := self intVal: (self loadRef: cls at: BEH_FORMAT).
	spec := fmt >> 16.
	fixed := fmt bitAnd: CLS_INSTSIZE_MASK.
	ek := -1.
	(spec = F_VAR or: [spec = F_FIXVAR]) ifTrue: [ek := E_PTR].
	spec >= F_BYTES ifTrue: [
		ek := E_BYTE.
		fixed := 0].
	(kind = PK_STRINGAT or: [kind = PK_STRINGATPUT]) ifTrue: [
		spec >= F_BYTES ifFalse: [^false].
		ek := E_CHAR].
	ek < 0 ifTrue: [^false].
	((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback deoptOther) ~= 0 ifTrue: [^false].
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	(kind = PK_SIZE and: [argc = 0]) ifTrue: [
		n := self add: O_SIZE rep: R_OOP.
		(ir node: n) a: rcv.
		(ir node: n) aux: ek.
		(ir node: n) aux2: fixed.
		(ir node: n) tkind: T_SMI.
		self push: n act: a depth: r.
		^true].
	((kind = PK_AT or: [kind = PK_STRINGAT]) and: [argc = 1]) ifTrue: [
		idx := self guardInt: (self read: (self var: a slot: r + 1)) state: s.
		n := self add: O_INDEXLOAD rep: R_OOP.
		(ir node: n) a: rcv.
		(ir node: n) b: idx.
		(ir node: n) aux: ek.
		(ir node: n) aux2: fixed.
		(ir node: n) state: s.
		ek = E_BYTE ifTrue: [(ir node: n) tkind: T_SMI].
		ek = E_CHAR ifTrue: [(ir node: n) tkind: T_CHAR].
		self push: n act: a depth: r.
		^true].
	((kind = PK_ATPUT or: [kind = PK_STRINGATPUT]) and: [argc = 2]) ifTrue: [
		idx := self guardInt: (self read: (self var: a slot: r + 1)) state: s.
		val := self read: (self var: a slot: r + 2).
		n := self add: O_INDEXSTORE rep: R_NONE.
		(ir node: n) a: rcv.
		(ir node: n) b: idx.
		(ir node: n) c: val.
		(ir node: n) aux: ek.
		(ir node: n) aux2: fixed.
		(ir node: n) state: s.
		self push: val act: a depth: r.
		^true].
	^false
!
knownClassOf: v
	"v's class if the IR knows it, else 0."
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [^self classOf: nd aux asUInt64].
	nd tkind asInt32 = T_SMI ifTrue: [^memory clsSmallint].
	nd tkind asInt32 = T_FLOAT ifTrue: [^memory clsSmallfloat].
	nd tkind asInt32 = T_NIL ifTrue: [^self classOf: memory nilOop].
	(nd tkind asInt32 = T_OBJ and: [nd tcls ~= 0]) ifTrue: [^nd tcls].
	^0
!
canInline: m act: a
	"m may be inlined into a: small, no primitive, only bytecodes the tier inlines, not too deep or recursive, within the budget."
	<c: 'bool opt_can_inline(oop m, int32_t a)'>
	| size bcs pc op depth p same |
	(self loadRef: m at: CM_PRIMITIVE) ~= (self intOop: 0) ifTrue: [^false].
	0 to: obNoInlineCount - 1 do: [:i | (obNoInline at: i) = m ifTrue: [^false]].
	size := self methodSize: m.
	size > OPT_INLINE_SIZE ifTrue: [^false].
	obInlined + size > OPT_INLINE_BUDGET ifTrue: [^false].
	depth := 0.
	same := 0.
	p := a.
	[p >= 0] whileTrue: [
		depth := depth + 1.
		(ir act: p) method = m ifTrue: [same := same + 1].
		p := (ir act: p) parent].
	(depth >= OPT_INLINE_DEPTH or: [same > 1]) ifTrue: [^false].
	(self analysisOf: m) < 0 ifTrue: [^false].
	bcs := self methodBytecodes: m.
	pc := 0.
	[pc < size] whileTrue: [
		op := bcs at: pc.
		(op = 16r76 or: [op = 16r94 or: [((runtime flag: runtime blocksFlag) not and: [op = 16r7C or: [op = 16r8F or: [op >= 16r8A and: [op <= 16r8C]]]])]]) ifTrue: [^false].
		pc := pc + (analysis lengthOf: op)].
	^true
!
inlineMethod: m receiverClass: cls pc: pc act: a rcvSlot: r argc: argc
	"Build m's activation in place of the send at a's pc: its arguments are a's slots after the receiver; its returns go to a block where a continues with the result."
	<c: 'void opt_inline_method(oop m, uint64_t cls, int32_t pc, int32_t a, int32_t r, int32_t argc)'>
	| b ac entry ret |
	b := self newActFor: m.
	b < 0 ifTrue: [^self bail].
	obInlined := obInlined + (self methodSize: m).
	ac := ir act: b.
	ac parent: a.
	ac sendPc: pc.
	ac sendArgc: argc.
	ac receiver: (self read: (self var: a slot: r)).
	ac rcvClass: cls.
	0 to: argc - 1 do: [:i | self writeArg: (self var: b slot: i) value: (self read: (self var: a slot: r + 1 + i))].
	argc to: argc + ac numTemps - 1 do: [:i | self write: (self var: b slot: i) value: (self constant: memory nilOop)].
	entry := ir newBlock.
	(ir block: entry) act: b.
	ret := ir newBlock.
	(ir block: ret) act: a.
	(ir act: b) retBlock: ret.
	self goto: entry.
	obCurBlock := entry.
	self seal: entry.
	self buildAct: b.
	ir origin: a pc: pc.
	self seal: ret.
	(ir block: ret) npreds = 0 ifTrue: [
		obCurBlock := -1.
		^self].
	obCurBlock := ret.
	self write: (self var: a slot: r) value: (self read: (ir act: b) retVar)
!
guard: v class: cls state: s
	"v, deoptimizing unless its class is cls."
	| n |
	cls = memory clsSmallint ifTrue: [^self guardInt: v state: s].
	n := self add: O_GUARDCLASS rep: R_OOP.
	(ir node: n) a: v.
	(ir node: n) aux: cls asInt64.
	(ir node: n) state: s.
	(ir node: n) flags: NF_GUARD.
	self type: n class: cls.
	^n
!
cast: v class: cls
	"v, known to be of class cls (a type switch tested it)."
	| n |
	n := self add: O_CAST rep: R_OOP.
	(ir node: n) a: v.
	self type: n class: cls.
	^n
!
type: n class: cls
	cls = memory clsSmallfloat ifTrue: [^(ir node: n) tkind: T_FLOAT].
	cls = memory clsSmallint
		ifTrue: [(ir node: n) tkind: T_SMI]
		ifFalse: [
			(ir node: n) tkind: T_OBJ.
			(ir node: n) tcls: cls]
!
branch: v true: t false: f
	"End the current block with a branch on Boolean v (known to be one)."
	| n |
	n := self add: O_BRANCH rep: R_NONE.
	(ir node: n) a: v.
	(ir block: obCurBlock) succ0: t.
	(ir block: obCurBlock) succ1: f.
	ir addPred: obCurBlock to: t.
	ir addPred: obCurBlock to: f.
	obCurBlock := -1
!
deoptAct: a state: s
	"End the current block: deoptimize."
	| n |
	n := self add: O_DEOPT rep: R_NONE.
	(ir node: n) state: s.
	obCurBlock := -1
!
noteDependency: sel
	"The code depends on what sel finds (inlined or speculated): a method change for sel invalidates it."
	0 to: obDepCount - 1 do: [:i | (obDeps at: i) = sel ifTrue: [^self]].
	obDepCount < OPT_MAX_DEPS ifTrue: [
		obDeps at: obDepCount put: sel.
		obDepCount := obDepCount + 1]
!
depCount
	^obDepCount
!
depAt: i
	^obDeps at: i
!
callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
	"A send through the runtime: the result replaces the receiver."
	| n args |
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'opt: runtime send at pc %d of act %d: ' with: pc with: a.
		interpreter printSymbol: sel on: libc stderr.
		libc fputc: 10 to: libc stderr].
	n := self add: O_SEND rep: R_OOP.
	obSafeEpoch := obSafeEpoch + 1.
	args := ir allocOperands: argc + 1.
	0 to: argc do: [:i | ir operand: args + i put: (self read: (self var: a slot: r + i))].
	(ir node: n) args: args.
	(ir node: n) nargs: (argc + 1) asUInt16.
	(ir node: n) aux: sel asInt64.
	(ir node: n) aux2: (((argc asInt64 bitOr: kind asInt64 << 8) bitOr: k asInt64 << 16) bitOr: pc asInt64 << 32).
	(ir node: n) state: (self stateAct: a pc: (pc + (analysis lengthOf: (self byteAt: pc act: a))) asInt32 depth: r).
	self push: n act: a depth: r.
	^n
! !
