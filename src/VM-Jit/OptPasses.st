OptModule subclass: #OptPasses
	instanceVariableNames: 'ir psOrder psOrderCount psVisitMark psWorkList psIdom psPre psPost psChild psSibling psHeads psChain psUnboxOff psUnboxed psTwin psLoopOuter psMemEnd psMemMark psMemKill psCounted psAffine psTPhi psTLo psTHi psTCount psRLo psRHi psILo psIHi psCHi psCStep psCHead psCLimit psCCond psLoopK psLoopConst psLoopCap'
	classVariableNames: ''
	package: 'VM-Jit'!

OptPasses comment: 'Passes over the IR (OptIR) after it is built: operands resolved through replaced nodes, trivial phis removed, unreachable blocks and unused pure nodes dropped, critical edges split, the blocks ordered (reverse postorder, the order code is emitted in).

They may run on the helper thread (OptRuntime>>backEnd:, docs/jit.md Background compilation) while the VM runs Smalltalk: read nothing of the heap, the type feedback or the runtime but through the IR (its snapshot: OptIR>>flagsAtAct:pc:, constClassOf:, smallFloatClass; flags are fine).'!

!OptPasses class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (psOrder 'int32_t[OPT_MAX_BLOCKS]') (psOrderCount int32_t) (psVisitMark 'uint8_t[OPT_MAX_BLOCKS]') (psWorkList 'int32_t[OPT_MAX_NODES]')
		(psIdom 'int32_t[OPT_MAX_BLOCKS]') (psPre 'int32_t[OPT_MAX_BLOCKS]') (psPost 'int32_t[OPT_MAX_BLOCKS]') (psChild 'int32_t[OPT_MAX_BLOCKS]') (psSibling 'int32_t[OPT_MAX_BLOCKS]')
		(psHeads 'int32_t[4096]') (psChain 'int32_t[OPT_MAX_NODES]') (psUnboxOff bool) (psUnboxed bool)
		(psTwin 'int32_t[OPT_MAX_NODES]') (psLoopOuter 'int32_t[OPT_MAX_BLOCKS]') (psMemEnd 'int32_t[OPT_MAX_BLOCKS]') (psMemMark 'int32_t[OPT_MAX_BLOCKS]') (psMemKill 'uint8_t[OPT_MAX_BLOCKS]') (psCounted 'int64_t[4]') (psAffine 'int64_t[8]')
		(psTPhi 'int32_t[16]') (psTLo 'int64_t[16]') (psTHi 'int64_t[16]') (psTCount int32_t) (psRLo int64_t) (psRHi int64_t) (psILo int64_t) (psIHi int64_t)
		(psCHi int64_t) (psCStep int64_t) (psCHead bool) (psCLimit int32_t) (psCCond int32_t) (psLoopK 'int64_t[OPT_MAX_BLOCKS]') (psLoopConst 'int32_t[OPT_MAX_BLOCKS]') (psLoopCap 'uint8_t[OPT_MAX_BLOCKS]'))
! !

!OptPasses methodsFor: 'accessing'!
orderCount
	^psOrderCount
!
unboxOff: aBoolean
	"Compile without unboxPhis (a compilation it made fail is tried again so)."
	psUnboxOff := aBoolean
!
unboxed
	"unboxPhis made a twin in this compilation."
	^psUnboxed
!
orderAt: i
	^psOrder at: i
! !

!OptPasses methodsFor: 'cleanup'!
cleanup: entry
	"After building: resolve, simplify phis, split critical edges, number values, hoist guards out of loops, drop what is unreachable or unused, order the blocks, mark the compares only equality uses."
	<function>
	self computeOrder: entry.
	self removeUnreachable.
	self simplifyPhis.
	self resolveOperands.
	self typePhis.
	self foldIntTests ifTrue: [
		self computeOrder: entry.
		self removeUnreachable.
		self simplifyPhis].
	self dropIntChecks.
	self resolveOperands.
	self typeBooleanPhis.
	self typeFloatPhis.
	self forwardUnboxes.
	self resolveOperands.
	psUnboxed := false.
	(psUnboxOff not and: [runtime flag: runtime unboxFlag]) ifTrue: [
		self unboxPhis.
		self dropBoxes.
		self resolveOperands].
	ir full ifTrue: [^self].
	self splitCriticalEdges.
	ir full ifTrue: [^self].
	self computeOrder: entry.
	((runtime flag: runtime gvnFlag) or: [runtime flag: runtime hoistFlag]) ifTrue: [self dominators: entry].
	(runtime flag: runtime hoistFlag) ifTrue: [self hoistReceiverGuards: entry].
	(runtime flag: runtime gvnFlag) ifTrue: [
		self valueNumbers.
		"a load forwarded to the SmallInteger stored: its guard goes"
		self dropIntChecks.
		self resolveOperands].
	self ranges.
	(runtime flag: runtime hoistFlag) ifTrue: [
		self hoistGuards.
		"what loops' phis replaced, and the guards of SmallIntegers that leaves"
		self dropIntChecks.
		self resolveOperands.
		"what moved before a loop may be what was there (an invariant load and its guard)"
		(runtime flag: runtime gvnFlag) ifTrue: [
			self valueNumbers.
			"a load forwarded to the SmallInteger stored: its guard goes"
			self dropIntChecks.
			self resolveOperands]].
	ir full ifTrue: [^self].
	(runtime flag: runtime hoistFlag) ifTrue: [self pollsAtHeads].
	self unboxStates.
	self countUses.
	self removeDead.
	self countUses.
	self equalityCompares
!
equalityCompares
	"A compareWith: of bytes (O_STRCMP) that only = 0 or ~= 0 uses (String>>=): whether the bytes are equal is all it answers (NF_EQONLY)."
	<function>
	| nd x y |
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd block >= 0 and: [nd op asInt32 = O_ICMP and: [nd aux = 6 or: [nd aux = 7]]]) ifTrue: [
			x := ir node: (ir resolve: nd a).
			y := ir node: (ir resolve: nd b).
			x op asInt32 = O_STRCMP ifFalse: [
				y := x.
				x := ir node: (ir resolve: nd b)].
			(x op asInt32 = O_STRCMP and: [x uses = 1 and: [y op asInt32 = O_CONST and: [y aux = (self intOop: 0) asInt64]]]) ifTrue: [
				x flags: (x flags bitOr: NF_EQONLY)]]]
!
simplifyPhis
	"A phi whose operands are all one value (or itself) is that value; repeat until none is left."
	<function>
	| changed nd same v ok |
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: ir nodeCount - 1 do: [:n |
			nd := ir node: n.
			(nd op asInt32 = O_PHI and: [nd fwd < 0 and: [nd block >= 0]]) ifTrue: [
				same := -1.
				ok := true.
				0 to: nd nargs asInt32 - 1 do: [:i |
					v := ir resolve: (ir operand: nd args + i).
					(v ~= n and: [v ~= same]) ifTrue: [
						same < 0 ifTrue: [same := v] ifFalse: [ok := false]]].
				(ok and: [same >= 0]) ifTrue: [
					nd fwd: same.
					ir unlink: n.
					changed := true]]]]
!
typePhis
	"A phi of SmallIntegers (every operand one, or such a phi: a loop's counter, a running sum) is a SmallInteger, to a fixed point from all of them. An operand counts only from where control can come (neverRuns:); one that a guard took for a SmallInteger on every way to its edge is that guard (n to: 1 by: -1 counts down from an argument that its first test guarded); a frame slot a loop's unit takes for a SmallInteger is one, guarded where a phi rests on it."
	<function>
	| changed nd v count e g |
	count := 0.
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_PHI and: [nd fwd < 0 and: [nd block >= 0 and: [nd tkind asInt32 = T_ANY]]]) ifTrue: [
			nd tkind: T_SMI.
			psWorkList at: count put: n.
			count := count + 1]].
	0 to: count - 1 do: [:k |
		nd := ir node: (psWorkList at: k).
		e := (ir block: nd block) preds.
		0 to: nd nargs asInt32 - 1 do: [:i |
			v := ir resolve: (ir operand: nd args + i).
			(e >= 0 and: [(self isSmallInt: v) not]) ifTrue: [
				g := self intGuardOf: v before: (ir edge: e) from.
				g >= 0 ifTrue: [ir operand: nd args + i put: g]].
			e >= 0 ifTrue: [e := (ir edge: e) next]]].
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: count - 1 do: [:k |
			nd := ir node: (psWorkList at: k).
			nd tkind asInt32 = T_SMI ifTrue: [
				e := (ir block: nd block) preds.
				0 to: nd nargs asInt32 - 1 do: [:i |
					v := ir resolve: (ir operand: nd args + i).
					((self isSmallInt: v) or: [nd tkind asInt32 ~= T_SMI or: [e >= 0 and: [self neverRuns: (ir edge: e) from]]]) ifFalse: [
						nd tkind: T_ANY.
						changed := true].
					e >= 0 ifTrue: [e := (ir edge: e) next]]]]].
	0 to: count - 1 do: [:k |
		nd := ir node: (psWorkList at: k).
		nd tkind asInt32 = T_SMI ifTrue: [
			0 to: nd nargs asInt32 - 1 do: [:i | self guardFrameInt: (ir resolve: (ir operand: nd args + i))]]]
!
intGuardOf: v before: p
	"A guard that v is a SmallInteger in block p or in a block every way to p passes (a chain of single predecessors up from p), else -1."
	<function>
	| chain k b nd |
	chain := self local: 'int32_t[8]'.
	k := 0.
	b := p.
	[b >= 0 and: [k < 8]] whileTrue: [
		chain at: k put: b.
		k := k + 1.
		b := (ir block: b) npreds = 1 ifTrue: [(ir edge: (ir block: b) preds) from] ifFalse: [-1]].
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_GUARDINT and: [nd block >= 0 and: [nd fwd < 0 and: [(ir resolve: nd a) = v]]]) ifTrue: [
			0 to: k - 1 do: [:j | (chain at: j) = nd block ifTrue: [^n]]]].
	^-1
!
dropIntChecks
	"A guard that a SmallInteger is one goes, and its cast to one (a type switch's: arithmetic then sees a constant behind it); not the guard at a loop unit's entry that makes a frame's slot one (guardFrameInt:)."
	<function>
	| nd |
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(((nd op asInt32 = O_GUARDINT and: [(nd flags bitAnd: NF_HOISTED) = 0]) or: [nd op asInt32 = O_CAST and: [nd tkind asInt32 = T_SMI]]) and: [nd fwd < 0 and: [nd block >= 0 and: [(ir node: (ir resolve: nd a)) tkind asInt32 = T_SMI]]]) ifTrue: [
			nd fwd: (ir resolve: nd a).
			ir unlink: n]]
!
foldIntTests
	"Arithmetic on two SmallIntegers has no Float case (neverRuns:): its test goes, the SmallInteger case follows it, the frame's slots among the two are guarded. Answer whether any did (its Float case is unreachable now)."
	<function>
	| bl t folded |
	folded := false.
	0 to: ir blockCount - 1 do: [:b |
		bl := ir block: b.
		(bl rpo >= 0 and: [bl succ1 >= 0 and: [self neverRuns: bl succ1]]) ifTrue: [
			t := ir node: (ir resolve: (ir node: bl last) a).
			self guardFrameInt: (ir resolve: t a).
			self guardFrameInt: (ir resolve: t b).
			(ir node: bl last) op: O_GOTO asUInt16.
			(ir node: bl last) a: -1.
			bl succ1: -1.
			folded := true]].
	^folded
!
neverRuns: b
	"Block b is the Float case of arithmetic on two values (OptBuilder>>floatArith:x:y:pc:act:rcvSlot:), both SmallIntegers: the test before it takes the other."
	| bl p t |
	bl := ir block: b.
	bl npreds = 1 ifFalse: [^false].
	p := ir block: (ir edge: bl preds) from.
	(p succ1 = b and: [p last >= 0 and: [(ir node: p last) op asInt32 = O_BRANCH]]) ifFalse: [^false].
	t := ir node: (ir resolve: (ir node: p last) a).
	^t op asInt32 = O_BOTHINT and: [(self isSmallInt: (ir resolve: t a)) and: [self isSmallInt: (ir resolve: t b)]]
!
isSmallInt: v
	"v is a SmallInteger, or a loop unit's parameter it takes for one."
	^(ir node: v) tkind asInt32 = T_SMI or: [self isFrameInt: v]
!
isFrameInt: v
	"v is a loop unit's parameter, a frame slot that held a SmallInteger when the unit was compiled (and no guard of such a slot failed at the loop's entry before: OptBuilder>>frameInts)."
	| nd |
	nd := ir node: v.
	^ir osrState >= 0 and: [nd op asInt32 = O_PARAM and: [nd aux >= 0 and: [nd aux < 64 and: [(ir osrInts bitAnd: 1 asUInt64 << nd aux) ~= 0]]]]
!
guardFrameInt: v
	"If v is a loop unit's parameter taken for a SmallInteger and not guarded yet: it is one from here on, guarded at the end of the entry block (failing, the loop's head continues in the interpreter, and the loop's units take no slot for a SmallInteger again)."
	| g |
	((ir node: v) tkind asInt32 ~= T_SMI and: [self isFrameInt: v]) ifFalse: [^self].
	g := ir newNode: O_GUARDINT rep: R_OOP.
	ir full ifTrue: [^self].
	(ir node: v) tkind: T_SMI.
	(ir node: g) a: v.
	(ir node: g) state: ir osrState.
	(ir node: g) flags: (NF_GUARD bitOr: NF_HOISTED).
	(ir node: g) tkind: T_SMI.
	(ir node: g) bcact: (ir state: ir osrState) act.
	(ir node: g) bcpc: (ir state: ir osrState) pc.
	ir insert: g before: (ir block: ir osrEntry) last
!
typeBooleanPhis
	"A phi of Booleans (true, false, comparisons, such phis: and:, or:) is a Boolean, to a fixed point from all of them: a branch on a Boolean needs no mustBeBoolean check, so no frame state (it would name the Boolean: a comparison only its branch reads makes none)."
	<function>
	| changed nd v count |
	count := 0.
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_PHI and: [nd fwd < 0 and: [nd block >= 0 and: [nd tkind asInt32 = T_ANY]]]) ifTrue: [
			nd tkind: T_BOOL.
			psWorkList at: count put: n.
			count := count + 1]].
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: count - 1 do: [:k |
			nd := ir node: (psWorkList at: k).
			0 to: nd nargs asInt32 - 1 do: [:i |
				v := ir resolve: (ir operand: nd args + i).
				(nd tkind asInt32 = T_BOOL and: [(ir node: v) tkind asInt32 ~= T_BOOL]) ifTrue: [
					nd tkind: T_ANY.
					changed := true]]]].
	0 to: ir blockCount - 1 do: [:b |
		count := (ir block: b) last.
		(count >= 0 and: [(ir node: count) op asInt32 = O_BRANCH and: [(ir node: (ir resolve: (ir node: count) a)) tkind asInt32 = T_BOOL]]) ifTrue: [(ir node: count) state: -1]]
!
typeFloatPhis
	"A phi of SmallFloat64s (every operand one: a box, a Float constant, a value of that class, such a phi; or, from a loop unit's entry, a frame slot that held one when the unit was compiled, guarded there) is a SmallFloat64, to a fixed point from all of them."
	<function>
	| changed nd v count e k |
	count := 0.
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_PHI and: [nd fwd < 0 and: [nd block >= 0 and: [nd rep asInt32 = R_OOP and: [nd tkind asInt32 = T_ANY and: [nd nargs asInt32 > 0]]]]]) ifTrue: [
			nd tkind: T_FLOAT.
			psWorkList at: count put: n.
			count := count + 1]].
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: count - 1 do: [:i |
			nd := ir node: (psWorkList at: i).
			e := (ir block: nd block) preds.
			k := 0.
			[nd tkind asInt32 = T_FLOAT and: [e >= 0]] whileTrue: [
				v := ir resolve: (ir operand: nd args + k).
				(((ir node: v) tkind asInt32 = T_FLOAT and: [(ir node: v) rep asInt32 = R_OOP]) or: [(ir edge: e) from = ir osrEntry and: [self isFrameFloat: v]]) ifFalse: [
					nd tkind: T_ANY.
					changed := true].
				k := k + 1.
				e := (ir edge: e) next]]].
	"the frame's slots: guarded once, at the end of the entry block (failing, the loop's head continues in the interpreter)"
	0 to: count - 1 do: [:i |
		nd := ir node: (psWorkList at: i).
		nd tkind asInt32 = T_FLOAT ifTrue: [
			e := (ir block: nd block) preds.
			k := 0.
			[e >= 0] whileTrue: [
				v := ir resolve: (ir operand: nd args + k).
				((ir edge: e) from = ir osrEntry and: [self isFrameFloat: v]) ifTrue: [
					v := self floatGuardOf: v.
					ir full ifTrue: [^self].
					ir operand: nd args + k put: v].
				k := k + 1.
				e := (ir edge: e) next]]]
!
isFrameFloat: v
	"v is a loop unit's parameter, a frame slot that held a SmallFloat64 when the unit was compiled."
	| nd |
	nd := ir node: v.
	^ir osrState >= 0 and: [nd op asInt32 = O_PARAM and: [nd aux >= 0 and: [nd aux < 64 and: [(ir osrFloats bitAnd: 1 asUInt64 << nd aux) ~= 0]]]]
!
floatGuardOf: v
	"Loop unit parameter v, guarded to be a SmallFloat64 (once) at the end of the entry block: failing, it deoptimizes to the loop's head."
	| n g |
	n := (ir block: ir osrEntry) first.
	[n >= 0] whileTrue: [
		((ir node: n) op asInt32 = O_GUARDCLASS and: [(ir node: n) a = v and: [(ir node: n) aux = ir smallFloatClass asInt64]]) ifTrue: [^n].
		n := (ir node: n) next].
	g := ir newNode: O_GUARDCLASS rep: R_OOP.
	ir full ifTrue: [^-1].
	(ir node: g) a: v.
	(ir node: g) aux: ir smallFloatClass asInt64.
	(ir node: g) state: ir osrState.
	(ir node: g) flags: NF_GUARD.
	(ir node: g) tkind: T_FLOAT.
	(ir node: g) bcact: (ir state: ir osrState) act.
	(ir node: g) bcpc: (ir state: ir osrState) pc.
	ir insert: g before: (ir block: ir osrEntry) last.
	^g
!
unboxPhis
	"A loop's Float phi gets a twin on doubles that the loop's arithmetic reads instead of unboxing the phi every time around, so the chain stays on doubles (the boxed phi stays for all else: frame states, sends, the exit): into it flow Float constants, the doubles of boxes, the twin itself, and from a loop unit's entry the frame's value, unboxed there once (a guard). Across the loop's sends and interrupt checks the twin is in its raw home slot."
	<function>
	| hb lo hi e n nd k o u ok uses |
	0 to: ir nodeCount - 1 do: [:i | psTwin at: i put: -1].
	"a SmallFloat64 phi's unboxings, anywhere: its twin"
	0 to: ir nodeCount - 1 do: [:i |
		nd := ir node: i.
		(nd op asInt32 = O_UNBOXF and: [nd fwd < 0 and: [nd block >= 0 and: [self isFloatPhi: (ir resolve: nd a)]]]) ifTrue: [
			u := self twinOf: (ir resolve: nd a).
			ir full ifTrue: [^self].
			nd fwd: u.
			ir unlink: i]].
	0 to: ir blockCount - 1 do: [:h |
		hb := ir block: h.
		(hb rpo >= 0 and: [(hb flags bitAnd: BF_LOOP) ~= 0]) ifTrue: [
			"the loop's code: from the header to its last latch, in order"
			lo := hb rpo.
			hi := -1.
			e := hb preds.
			[e >= 0] whileTrue: [
				(ir block: (ir edge: e) from) rpo >= lo ifTrue: [hi := hi max: (ir block: (ir edge: e) from) rpo].
				e := (ir edge: e) next].
			hi >= 0 ifTrue: [
				n := hb first.
				[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
					nd := ir node: n.
					ok := nd fwd < 0 and: [nd rep asInt32 = R_OOP and: [nd tkind asInt32 ~= T_SMI]].
					e := hb preds.
					k := 0.
					[ok and: [e >= 0]] whileTrue: [
						o := ir resolve: (ir operand: nd args + k).
						ok := o = n or: [(ir node: o) op asInt32 = O_BOXF or: [(self isFloatConstant: o) or: [(ir edge: e) from = ir osrEntry and: [self isFrameNumber: o]]]].
						k := k + 1.
						e := (ir edge: e) next].
					uses := 0.
					ok ifTrue: [
						lo to: hi do: [:i |
							u := (ir block: (psOrder at: i)) first.
							[u >= 0] whileTrue: [
								((ir node: u) op asInt32 = O_UNBOXF and: [(ir resolve: (ir node: u) a) = n]) ifTrue: [uses := uses + 1].
								u := (ir node: u) next]]].
					uses > 0 ifTrue: [self twin: n block: h from: lo to: hi].
					n := nd next]]]]
!
isFloatConstant: v
	^(ir node: v) op asInt32 = O_CONST and: [((ir node: v) aux bitAnd: 7) = 4]
!
forwardUnboxes
	"A box's double unboxed again (in another block, after a safepoint) is that double; a guard that two values are not both SmallIntegers, one of them a SmallFloat64, goes (it would keep a box only frame states need otherwise)."
	<function>
	| nd v |
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_UNBOXF and: [nd fwd < 0 and: [nd block >= 0]]) ifTrue: [
			v := ir resolve: nd a.
			(ir node: v) op asInt32 = O_BOXF ifTrue: [
				nd fwd: (ir resolve: (ir node: v) a).
				ir unlink: n]].
		(nd op asInt32 = O_NOTINTS and: [nd block >= 0 and: [(ir node: (ir resolve: nd a)) tkind asInt32 = T_FLOAT or: [(ir node: (ir resolve: nd b)) tkind asInt32 = T_FLOAT]]]) ifTrue: [ir unlink: n]]
!
unboxStates
	"A box only frame states name: they name its double instead (deoptimization boxes it), and the box goes (removeDead). Operands (a phi's too) and activations' receivers are real uses: their boxes stay."
	<function>
	| nd st v |
	0 to: ir nodeCount - 1 do: [:n | psWorkList at: n put: 0].
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		nd block >= 0 ifTrue: [
			nd a >= 0 ifTrue: [psWorkList at: nd a put: 1].
			nd b >= 0 ifTrue: [psWorkList at: nd b put: 1].
			(nd c >= 0 and: [nd op asInt32 ~= O_SEND]) ifTrue: [psWorkList at: nd c put: 1].
			0 to: nd nargs asInt32 - 1 do: [:i | (ir operand: nd args + i) >= 0 ifTrue: [psWorkList at: (ir operand: nd args + i) put: 1]]]].
	0 to: ir actCount - 1 do: [:a | (ir act: a) receiver >= 0 ifTrue: [psWorkList at: (ir act: a) receiver put: 1]].
	0 to: ir stateCount - 1 do: [:s |
		st := ir state: s.
		0 to: st depth do: [:i |
			v := ir operand: st vals + i.
			(v >= 0 and: [(ir node: v) op asInt32 = O_BOXF and: [(ir node: v) block >= 0 and: [(psWorkList at: v) = 0]]]) ifTrue: [
				ir operand: st vals + i put: (ir resolve: (ir node: v) a)]]]
!
isFrameNumber: v
	"v is a loop unit's parameter, a frame slot that held a number when the unit was compiled."
	| nd |
	nd := ir node: v.
	^ir osrState >= 0 and: [nd op asInt32 = O_PARAM and: [nd aux >= 0 and: [nd aux < 64 and: [(ir osrNumbers bitAnd: 1 asUInt64 << nd aux) ~= 0]]]]
!
twin: n block: h from: lo to: hi
	"Phi n's twin on doubles in h: operands the doubles of n's (an unboxing guard at the loop unit's entry); n's unboxings in the loop read it."
	| nd p2 e k o x g u nu |
	nd := ir node: n.
	p2 := ir newNode: O_PHI rep: R_DBL.
	(ir node: p2) bcact: nd bcact.
	(ir node: p2) bcpc: nd bcpc.
	(ir node: p2) tkind: T_FLOAT.
	(ir node: p2) nargs: nd nargs.
	(ir node: p2) args: (ir allocOperands: nd nargs asInt32).
	ir insert: p2 before: n.
	e := (ir block: h) preds.
	k := 0.
	[e >= 0] whileTrue: [
		o := ir resolve: (ir operand: nd args + k).
		x := o = n
			ifTrue: [p2]
			ifFalse: [
				(ir node: o) op asInt32 = O_BOXF
					ifTrue: [ir resolve: (ir node: o) a]
					ifFalse: [
						(self isFloatConstant: o)
							ifTrue: [o]
							ifFalse: [
								g := ir newNode: O_UNBOXF rep: R_DBL.
								(ir node: g) a: o.
								(ir node: g) state: ir osrState.
								(ir node: g) flags: NF_GUARD.
								(ir node: g) bcact: nd bcact.
								(ir node: g) bcpc: nd bcpc.
								ir insert: g before: (ir block: (ir edge: e) from) last.
								g]]].
		ir operand: (ir node: p2) args + k put: x.
		k := k + 1.
		e := (ir edge: e) next].
	lo to: hi do: [:i |
		u := (ir block: (psOrder at: i)) first.
		[u >= 0] whileTrue: [
			nu := (ir node: u) next.
			((ir node: u) op asInt32 = O_UNBOXF and: [(ir resolve: (ir node: u) a) = n]) ifTrue: [
				(ir node: u) fwd: p2.
				ir unlink: u].
			u := nu]].
	psUnboxed := true
!
isFloatPhi: n
	"n is a live phi of SmallFloat64s (typeFloatPhis), its values boxed."
	| nd |
	nd := ir node: n.
	^nd op asInt32 = O_PHI and: [nd fwd < 0 and: [nd block >= 0 and: [nd rep asInt32 = R_OOP and: [nd tkind asInt32 = T_FLOAT]]]]
!
twinOf: n
	"SmallFloat64 phi n's twin on doubles, made once, before it: its operands the doubles of n's (a box's double, a Float constant, such a phi's twin, else the value decoded at the end of the predecessor); -1 if the IR is full."
	<function>
	| nd p2 e k o x |
	(psTwin at: n) >= 0 ifTrue: [^psTwin at: n].
	nd := ir node: n.
	psUnboxed := true.
	p2 := ir newNode: O_PHI rep: R_DBL.
	ir full ifTrue: [^-1].
	(ir node: p2) bcact: nd bcact.
	(ir node: p2) bcpc: nd bcpc.
	(ir node: p2) tkind: T_FLOAT.
	(ir node: p2) nargs: nd nargs.
	(ir node: p2) args: (ir allocOperands: nd nargs asInt32).
	ir full ifTrue: [^-1].
	ir insert: p2 before: n.
	"before the operands: a cycle of phis meets it"
	psTwin at: n put: p2.
	e := (ir block: nd block) preds.
	k := 0.
	[e >= 0] whileTrue: [
		o := ir resolve: (ir operand: nd args + k).
		x := (ir node: o) op asInt32 = O_BOXF
			ifTrue: [ir resolve: (ir node: o) a]
			ifFalse: [
				(self isFloatConstant: o)
					ifTrue: [o]
					ifFalse: [
						(ir node: o) op asInt32 = O_PHI
							ifTrue: [self twinOf: o]
							ifFalse: [self unboxed: o at: (ir edge: e) from]]].
		ir full ifTrue: [^-1].
		ir operand: (ir node: p2) args + k put: x.
		k := k + 1.
		e := (ir edge: e) next].
	^p2
!
unboxed: o at: b
	"SmallFloat64 o's double, decoded at the end of block b: no check, it cannot fail (no state)."
	| g |
	g := ir newNode: O_UNBOXF rep: R_DBL.
	ir full ifTrue: [^-1].
	(ir node: g) a: o.
	(ir node: g) flags: NF_PURE.
	(ir node: g) bcact: (ir node: o) bcact.
	(ir node: g) bcpc: (ir node: o) bcpc.
	ir insert: g before: (ir block: b) last.
	^g
!
dropBoxes
	"A SmallFloat64 phi whose box nothing needs goes: what read it reads its twin (frame states too: deoptimization boxes it); a store or return after its loop boxes the twin itself, right before, with its own state (out of SmallFloat64's range it deoptimizes, the interpreter does it). So does one after the loop of a box only such uses need (the box is then left to frame states: unboxStates). Any other use needs the box (a send, a guard, an activation's receiver, a phi but such a one), as does every such phi or box that one flows into. workList: 1 such a phi or box, 2 one that needs its box."
	<function>
	| count nd changed v t |
	ir full ifTrue: [^self].
	count := ir nodeCount.
	0 to: count - 1 do: [:n | psWorkList at: n put: (((self isFloatPhi: n) or: [(ir node: n) op asInt32 = O_BOXF and: [(ir node: n) block >= 0]]) ifTrue: [1] ifFalse: [0])].
	self findLoops.
	0 to: count - 1 do: [:n |
		nd := ir node: n.
		nd block >= 0 ifTrue: [
			nd a >= 0 ifTrue: [self box: nd a usedBy: n operand: 0].
			nd b >= 0 ifTrue: [self box: nd b usedBy: n operand: 1].
			(nd c >= 0 and: [nd op asInt32 ~= O_SEND]) ifTrue: [self box: nd c usedBy: n operand: 2].
			0 to: nd nargs asInt32 - 1 do: [:i | (ir operand: nd args + i) >= 0 ifTrue: [self box: (ir operand: nd args + i) usedBy: n operand: 3]]]].
	0 to: ir actCount - 1 do: [:a |
		self needBox: (ir act: a) receiver.
		self needBox: (ir act: a) closure].
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: count - 1 do: [:n |
			nd := ir node: n.
			(psWorkList at: n) = 2 ifTrue: [
				0 to: nd nargs asInt32 - 1 do: [:i |
					v := ir resolve: (ir operand: nd args + i).
					(psWorkList at: v) = 1 ifTrue: [
						psWorkList at: v put: 2.
						changed := true]]]]].
	"the twins, while the stores and returns still name the phis; then their boxes; then the phis go"
	0 to: count - 1 do: [:n |
		((psWorkList at: n) = 1 and: [self isFloatPhi: n]) ifTrue: [
			self twinOf: n.
			ir full ifTrue: [^self]]].
	0 to: count - 1 do: [:n |
		nd := ir node: n.
		nd block >= 0 ifTrue: [
			(nd op asInt32 = O_INDEXSTORE and: [(psWorkList at: (ir resolve: nd c)) = 1]) ifTrue: [nd c: (self box: (ir resolve: nd c) for: n)].
			(nd op asInt32 = O_STOREFIELD and: [(psWorkList at: (ir resolve: nd b)) = 1]) ifTrue: [nd b: (self box: (ir resolve: nd b) for: n)].
			(nd op asInt32 = O_RETURN and: [(psWorkList at: (ir resolve: nd a)) = 1]) ifTrue: [nd a: (self box: (ir resolve: nd a) for: n)].
			ir full ifTrue: [^self]]].
	0 to: count - 1 do: [:n |
		((psWorkList at: n) = 1 and: [self isFloatPhi: n]) ifTrue: [
			t := psTwin at: n.
			(ir node: n) fwd: t.
			ir unlink: n]]
!
box: v usedBy: n operand: i
	"v is n's operand i (0 a, 1 b, 2 c, 3 another): a SmallFloat64 phi's or a box's box is needed unless n is such a phi or boxes it itself."
	| p |
	p := ir resolve: v.
	((psWorkList at: p) = 1 and: [(self isFloatPhi: n) not and: [(self sinks: p into: n operand: i) not]]) ifTrue: [psWorkList at: p put: 2]
!
needBox: v
	(v >= 0 and: [(psWorkList at: (ir resolve: v)) = 1]) ifTrue: [psWorkList at: (ir resolve: v) put: 2]
!
sinks: p into: n operand: i
	"n stores (b of a field store, c of an indexed one) or returns SmallFloat64 phi or box p, its operand i: a phi no more often than its block runs, not in its loop if it heads one; a box outside its innermost loop (n in no loop, or in one around those); with a state that does it again (where no box failed before)."
	<function>
	| nd op st h l b |
	nd := ir node: n.
	op := nd op asInt32.
	((op = O_INDEXSTORE and: [i = 2]) or: [(op = O_STOREFIELD and: [i = 1]) or: [op = O_RETURN and: [i = 0]]]) ifFalse: [^false].
	nd state < 0 ifTrue: [^false].
	st := ir state: nd state.
	"a block's ^ (inlined in its home method): deoptimized there, the unit would not be optimized again"
	(op = O_RETURN and: [st parent >= 0]) ifTrue: [^false].
	((ir flagsAtAct: st act pc: st pc) bitAnd: feedback deoptOther) = 0 ifFalse: [^false].
	b := (ir node: p) block.
	h := (ir block: b) loop.
	(ir node: p) op asInt32 = O_PHI
		ifTrue: [h = b ifTrue: [h := psLoopOuter at: h]]
		ifFalse: [
			h < 0 ifTrue: [^false].
			h := psLoopOuter at: h].
	l := (ir block: nd block) loop.
	l < 0 ifTrue: [^true].
	[h >= 0] whileTrue: [
		h = l ifTrue: [^true].
		h := psLoopOuter at: h].
	^false
!
box: p for: n
	"A box of SmallFloat64 phi p's twin (box p's double) for n's use, right before n, with n's state."
	| nd b |
	nd := ir node: n.
	b := ir newNode: O_BOXF rep: R_OOP.
	ir full ifTrue: [^-1].
	(ir node: b) a: ((ir node: p) op asInt32 = O_PHI ifTrue: [psTwin at: p] ifFalse: [ir resolve: (ir node: p) a]).
	(ir node: b) state: nd state.
	(ir node: b) tkind: T_FLOAT.
	(ir node: b) flags: NF_GUARD.
	(ir node: b) aux2: -1.
	(ir node: b) bcact: nd bcact.
	(ir node: b) bcpc: nd bcpc.
	ir insert: b before: n.
	^b
!
findLoops
	"Natural loops, inner ones first (the blocks from the last in order): block loop: the innermost loop's head (a head its own, -1 in none), psLoopOuter: a head's next loop out (-1). A loop is its head and what reaches a latch (a predecessor not before it in order) without passing it."
	<function>
	| h e sp b |
	0 to: ir blockCount - 1 do: [:i |
		(ir block: i) loop: -1.
		psLoopOuter at: i put: -1].
	psOrderCount - 1 to: 0 by: -1 do: [:i |
		h := psOrder at: i.
		((ir block: h) flags bitAnd: BF_LOOP) ~= 0 ifTrue: [
			sp := 0.
			e := (ir block: h) preds.
			[e >= 0] whileTrue: [
				b := (ir edge: e) from.
				(ir block: b) rpo >= (ir block: h) rpo ifTrue: [
					(ir block: h) loop: h.
					sp := self loop: h reaches: b sp: sp].
				e := (ir edge: e) next].
			[sp > 0] whileTrue: [
				sp := sp - 1.
				e := (ir block: (psHeads at: sp)) preds.
				[e >= 0] whileTrue: [
					sp := self loop: h reaches: (ir edge: e) from sp: sp.
					e := (ir edge: e) next]]]]
!
loop: h reaches: b sp: sp
	"Block b is in h's loop: so is the outermost loop found so far that b is in (or b): it is pushed (psHeads) if it is new to h's."
	<function>
	| x |
	b = h ifTrue: [^sp].
	(ir block: b) loop < 0 ifTrue: [
		(ir block: b) loop: h.
		psHeads at: sp put: b.
		^sp + 1].
	x := (ir block: b) loop.
	[(psLoopOuter at: x) >= 0] whileTrue: [x := psLoopOuter at: x].
	x = h ifTrue: [^sp].
	psLoopOuter at: x put: h.
	psHeads at: sp put: x.
	^sp + 1
!
resolveOperands
	"Every operand (fixed, variadic, of frame states) to what replaced it."
	<function>
	| nd st |
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		nd a >= 0 ifTrue: [nd a: (ir resolve: nd a)].
		nd b >= 0 ifTrue: [nd b: (ir resolve: nd b)].
		nd c >= 0 ifTrue: [(nd op asInt32 = O_SEND) ifFalse: [nd c: (ir resolve: nd c)]].
		0 to: nd nargs asInt32 - 1 do: [:i | ir operand: nd args + i put: (ir resolve: (ir operand: nd args + i))]].
	0 to: ir stateCount - 1 do: [:s |
		st := ir state: s.
		0 to: st depth do: [:i | ir operand: st vals + i put: (ir resolve: (ir operand: st vals + i))]].
	0 to: ir actCount - 1 do: [:a |
		(ir act: a) receiver: (ir resolve: (ir act: a) receiver).
		(ir act: a) closure: (ir resolve: (ir act: a) closure)]
!
dominators: entry
	"Immediate dominators (Cooper, Harvey and Kennedy, A Simple, Fast Dominance Algorithm), then the dominator tree's preorder and postorder numbers."
	<function>
	| changed b new e p n sp k |
	0 to: ir blockCount - 1 do: [:i |
		psIdom at: i put: -1.
		psChild at: i put: -1.
		psSibling at: i put: -1].
	psIdom at: entry put: entry.
	changed := true.
	[changed] whileTrue: [
		changed := false.
		1 to: psOrderCount - 1 do: [:i |
			b := psOrder at: i.
			new := -1.
			e := (ir block: b) preds.
			[e >= 0] whileTrue: [
				p := (ir edge: e) from.
				((ir block: p) rpo >= 0 and: [(psIdom at: p) >= 0]) ifTrue: [
					new := new < 0 ifTrue: [p] ifFalse: [self intersect: p with: new]].
				e := (ir edge: e) next].
			(new >= 0 and: [(psIdom at: b) ~= new]) ifTrue: [
				psIdom at: b put: new.
				changed := true]]].
	1 to: psOrderCount - 1 do: [:i |
		b := psOrder at: i.
		(psIdom at: b) >= 0 ifTrue: [
			psSibling at: b put: (psChild at: (psIdom at: b)).
			psChild at: (psIdom at: b) put: b]].
	"preorder and postorder of the tree (iterative: workList holds (block, child to visit next))"
	n := 0.
	sp := 2.
	psWorkList at: 0 put: entry.
	psWorkList at: 1 put: (psChild at: entry).
	psPre at: entry put: n.
	n := n + 1.
	[sp > 0] whileTrue: [
		k := psWorkList at: sp - 1.
		k >= 0
			ifTrue: [
				psWorkList at: sp - 1 put: (psSibling at: k).
				psPre at: k put: n.
				n := n + 1.
				psWorkList at: sp put: k.
				psWorkList at: sp + 1 put: (psChild at: k).
				sp := sp + 2]
			ifFalse: [
				psPost at: (psWorkList at: sp - 2) put: n.
				n := n + 1.
				sp := sp - 2]]
!
intersect: b1 with: b2
	| x y |
	x := b1.
	y := b2.
	[x ~= y] whileTrue: [
		[(ir block: x) rpo > (ir block: y) rpo] whileTrue: [x := psIdom at: x].
		[(ir block: y) rpo > (ir block: x) rpo] whileTrue: [y := psIdom at: y]].
	^x
!
dominates: x block: y
	^(psPre at: x) <= (psPre at: y) and: [(psPost at: y) <= (psPost at: x)]
!
valueNumbers
	"Global value numbering over the dominator tree: a deterministic node (arithmetic, comparisons, guards, conversions, constants) with the same operation and operands as one in a dominating position is that one; a field load as one in a dominating position with no safepoint on any path between, nor a store but into another field (the first 64; stores into indexed slots never write a named field)."
	<function>
	| b n nd h m md mem found stamp fields stores st d |
	0 to: 4095 do: [:i | psHeads at: i put: -1].
	fields := self local: 'int32_t[64]'.
	stores := self local: 'int32_t[64]'.
	0 to: 63 do: [:i |
		fields at: i put: 0.
		stores at: i put: -1].
	0 to: ir blockCount - 1 do: [:i |
		psMemMark at: i put: -1.
		psMemKill at: i put: 0.
		n := (ir block: i) first.
		[n >= 0] whileTrue: [
			((self changesMemory: (ir node: n)) and: [(ir node: n) op asInt32 ~= O_INDEXSTORE]) ifTrue: [psMemKill at: i put: 1].
			n := (ir node: n) next]].
	stamp := 0.
	0 to: psOrderCount - 1 do: [:i |
		b := psOrder at: i.
		"what the block before left holds on if only it leads here (an inlined method's blocks)"
		((ir block: b) npreds = 1 and: [i > 0 and: [(ir edge: (ir block: b) preds) from = (psOrder at: i - 1)]]) ifFalse: [
			d := psIdom at: b.
			(d >= 0 and: [d ~= b and: [self memoryKeptFrom: d to: b mark: i]])
				ifTrue: [
					"nothing on the way from the dominator writes memory: its loads hold, but fields a store wrote since (in it, or in blocks not on the way) are loaded again"
					mem := (psMemEnd at: d) asInt64.
					0 to: 63 do: [:f |
						(fields at: f) > mem ifTrue: [
							stamp := stamp + 1.
							fields at: f put: stamp.
							stores at: f put: -1]]]
				ifFalse: [
					stamp := stamp + 1.
					mem := stamp]].
		n := (ir block: b) first.
		[n >= 0] whileTrue: [
			nd := ir node: n.
			nd a >= 0 ifTrue: [nd a: (ir resolve: nd a)].
			nd b >= 0 ifTrue: [nd b: (ir resolve: nd b)].
			((self changesMemory: nd) and: [nd op asInt32 ~= O_INDEXSTORE]) ifTrue: [
				stamp := stamp + 1.
				"a store into a field leaves the other fields (of any object) as they are"
				(nd op asInt32 = O_STOREFIELD and: [nd aux >= 0 and: [nd aux < 64]])
					ifTrue: [
						fields at: nd aux put: stamp.
						stores at: nd aux put: n]
					ifFalse: [mem := stamp]].
			(self isNumbered: nd) ifTrue: [
				"loads: only since the last safepoint or store that may have written the field"
				nd op asInt32 = O_LOADFIELD ifTrue: [
					nd aux2: ((nd aux >= 0 and: [nd aux < 64 and: [(fields at: nd aux) > mem]]) ifTrue: [fields at: nd aux] ifFalse: [mem])].
				h := self hashOf: nd.
				found := -1.
				"a load of the field the last store wrote, into the same object, nothing that may write it between: the value stored"
				(nd op asInt32 = O_LOADFIELD and: [nd aux >= 0 and: [nd aux < 64 and: [(fields at: nd aux) > mem and: [(stores at: nd aux) >= 0]]]]) ifTrue: [
					st := ir node: (stores at: nd aux).
					(ir resolve: st a) = (ir resolve: nd a) ifTrue: [found := ir resolve: st b]].
				m := psHeads at: h.
				[m >= 0 and: [found < 0]] whileTrue: [
					md := ir node: m.
					((self same: nd as: md) and: [md block >= 0 and: [self dominates: md block block: b]]) ifTrue: [found := m].
					m := psChain at: m].
				found >= 0
					ifTrue: [
						m := nd next.
						nd fwd: found.
						ir unlink: n.
						n := m]
					ifFalse: [
						psChain at: n put: (psHeads at: h).
						psHeads at: h put: n.
						n := nd next]]
				ifFalse: [n := nd next]].
		psMemEnd at: b put: mem asInt32]
!
memoryKeptFrom: d to: b mark: k
	"No block on a path from d to b (d dominates b; b too if a path comes back to it) writes memory or may run anything (psMemKill): walked backward from b, marked k."
	<function>
	| sp x e |
	sp := 0.
	e := (ir block: b) preds.
	[e >= 0] whileTrue: [
		x := (ir edge: e) from.
		(x ~= d and: [(psMemMark at: x) ~= k]) ifTrue: [
			psMemMark at: x put: k.
			psWorkList at: sp put: x.
			sp := sp + 1].
		e := (ir edge: e) next].
	[sp > 0] whileTrue: [
		sp := sp - 1.
		x := psWorkList at: sp.
		(psMemKill at: x) ~= 0 ifTrue: [^false].
		e := (ir block: x) preds.
		[e >= 0] whileTrue: [
			(ir edge: e) from ~= d ifTrue: [
				((psMemMark at: (ir edge: e) from) ~= k and: [sp < OPT_MAX_NODES]) ifTrue: [
					psMemMark at: (ir edge: e) from put: k.
					psWorkList at: sp put: (ir edge: e) from.
					sp := sp + 1]].
			e := (ir edge: e) next]].
	^true
!
hoistReceiverGuards: entry
	"A method's or a block's unit: the guards of the class of its receiver (which no activation changes), wherever they are, run once, at the entry (after its interrupt check, deoptimizing to the unit's start), where value numbering makes them one: the receiver is checked once per activation, not again in every branch and loop that sends to it. Not if they guard different classes; a site whose hoisted guard failed (deoptHoisted) keeps its guard where it is."
	<function>
	| rcv st cls n nd |
	rcv := (ir act: (ir block: entry) act) receiver.
	rcv < 0 ifTrue: [^self].
	rcv := ir resolve: rcv.
	(ir node: rcv) op asInt32 = O_PARAM ifFalse: [^self].
	st := -1.
	n := (ir block: entry) first.
	[n >= 0] whileTrue: [
		((ir node: n) op asInt32 = O_CHECKINT and: [st < 0]) ifTrue: [st := (ir node: n) state].
		n := (ir node: n) next].
	(st < 0 or: [(ir block: entry) last < 0]) ifTrue: [^self].
	cls := 0.
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		(nd op asInt32 = O_GUARDCLASS and: [nd block >= 0 and: [nd block ~= entry and: [(ir resolve: nd a) = rcv]]]) ifTrue: [
			((ir flagsAtAct: nd bcact pc: nd bcpc) bitAnd: feedback deoptHoisted) ~= 0 ifTrue: [^self].
			(cls ~= 0 and: [cls ~= nd aux]) ifTrue: [^self].
			cls := nd aux]].
	cls = 0 ifTrue: [^self].
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		(nd op asInt32 = O_GUARDCLASS and: [nd block >= 0 and: [nd block ~= entry and: [(ir resolve: nd a) = rcv]]]) ifTrue: [
			ir unlink: m.
			ir insert: m before: (ir block: entry) last.
			nd := ir node: m.
			nd a: rcv.
			nd state: st.
			nd flags: (nd flags bitOr: NF_HOISTED)]]
!
hoistGuards
	"Innermost loops first: a guard that leaves a loop may leave the one around it too."
	<function>
	self findLoops.
	psOrderCount - 1 to: 0 by: -1 do: [:i |
		((ir block: (psOrder at: i)) flags bitAnd: BF_LOOP) ~= 0 ifTrue: [self hoistOutOf: (psOrder at: i)]]
!
hoistOutOf: h
	"A guard that every turn of loop h passes, of a value from before the loop, runs once instead, where the loop is entered, and deoptimizes to the loop's head. The loop must have one edge in (critical edges are split: its source only jumps here)."
	<function>
	| e k p entry index latch count b n next s |
	entry := -1.
	latch := -1.
	e := (ir block: h) preds.
	k := 0.
	[e >= 0] whileTrue: [
		p := (ir edge: e) from.
		(self dominates: h block: p)
			ifTrue: [latch := latch < 0 ifTrue: [p] ifFalse: [self intersect: p with: latch]]
			ifFalse: [
				entry >= 0 ifTrue: [^self].
				entry := p.
				index := k].
		k := k + 1.
		e := (ir edge: e) next].
	(entry < 0 or: [latch < 0 or: [(ir block: entry) succ1 >= 0 or: [(ir block: h) entryState < 0]]]) ifTrue: [^self].
	"the blocks on every turn, from the head down"
	count := 0.
	b := latch.
	[psWorkList at: count put: b.
	 count := count + 1.
	 b = h] whileFalse: [b := psIdom at: b].
	s := -1.
	count - 1 to: 0 by: -1 do: [:i |
		n := (ir block: (psWorkList at: i)) first.
		[n >= 0] whileTrue: [
			next := (ir node: n) next.
			(self isHoistable: n outOf: h) ifTrue: [
				s < 0 ifTrue: [
					s := self state: (ir block: h) entryState enteredFrom: index of: h.
					ir full ifTrue: [^self]].
				ir unlink: n.
				ir insert: n before: (ir block: entry) last.
				(ir node: n) state >= 0 ifTrue: [(ir node: n) state: s].
				(ir node: n) flags: ((ir node: n) flags bitOr: NF_HOISTED)].
			((self isInvariantOuterLoad: n of: h) or: [(self isClosureLoad: n of: h) or: [self isInvariantFieldLoad: n of: h]]) ifTrue: [
				ir unlink: n.
				ir insert: n before: (ir block: entry) last].
			n := next]].
	self outerSlotsOutOf: h entry: entry.
	self promoteOuterTempsOf: h entry: entry index: index latch: latch.
	self boundsOutOf: h entry: entry index: index.
	self headBoundsOutOf: h entry: entry index: index.
	self rangeBoundsOutOf: h entry: entry index: index.
	self mutabilityOutOf: h entry: entry index: index
!
mutabilityOutOf: h entry: entry index: index
	"Loop h, entered from block entry alone (h's predecessor index), sends nothing: its stores into an object from before the loop (its class known) check once, in entry, that it is not immutable (only a primitive changes that; what else may run, at an interrupt check, runs when the code has left the unit). Failing, the interpreter goes on from the loop's head and the store's send is marked: it checks every time from then on."
	<function>
	| s nd op x g k objs guards |
	(self loop: h changesOuterTemp: -1) ifTrue: [^self].
	objs := self local: 'int32_t[8]'.
	guards := self local: 'int32_t[8]'.
	k := 0.
	s := -1.
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		op := nd op asInt32.
		(((op = O_INDEXSTORE and: [(nd flags bitAnd: NF_MUTABLE) = 0]) or: [op = O_STOREFIELD and: [nd state >= 0]]) and: [nd block >= 0 and: [(self block: nd block isIn: h) and: [((ir flagsAtAct: nd bcact pc: nd bcpc) bitAnd: feedback deoptHoisted) = 0]]]) ifTrue: [
			x := ir resolve: nd a.
			((self isBefore: x loop: h) and: [(ir node: x) tkind asInt32 = T_OBJ]) ifTrue: [
				g := -1.
				0 to: k - 1 do: [:j | (objs at: j) = x ifTrue: [g := guards at: j]].
				(g < 0 and: [k < 8]) ifTrue: [
					s < 0 ifTrue: [
						s := self state: (ir block: h) entryState enteredFrom: index of: h.
						ir full ifTrue: [^self]].
					g := ir newNode: O_GUARDMUTABLE rep: R_NONE.
					ir full ifTrue: [^self].
					nd := ir node: m.
					(ir node: g) a: x.
					(ir node: g) state: s.
					(ir node: g) flags: (NF_GUARD bitOr: NF_HOISTED).
					(ir node: g) bcact: nd bcact.
					(ir node: g) bcpc: nd bcpc.
					ir insert: g before: (ir block: entry) last.
					objs at: k put: x.
					guards at: k put: g.
					k := k + 1].
				g >= 0 ifTrue: [
					nd := ir node: m.
					op = O_INDEXSTORE
						ifTrue: [nd flags: (nd flags bitOr: NF_MUTABLE)]
						ifFalse: [nd state: -1]]]]]
!
headBoundsOutOf: h entry: entry index: index
	"Loop h, entered from block entry alone (h's predecessor index), tests at its head that a SmallInteger phi is below a limit from before the loop, going on into the loop when it is, and counts the phi up by a constant: past the test the phi is between its start and the limit less one. An indexed load or store there at the phi plus 1, of an object from before the loop (its class known), checks no bounds if, once in entry, the start is at least 0 and the limit at most the object's size (boundsOutOf:entry:index: for a loop tested at its bottom)."
	<function>
	| hb br cond phi limit i0 back k s n nd x size body |
	hb := ir block: h.
	(hb npreds = 2 and: [hb last >= 0 and: [hb succ1 >= 0]]) ifFalse: [^self].
	br := ir node: hb last.
	br op asInt32 = O_BRANCH ifFalse: [^self].
	cond := ir node: (ir resolve: br a).
	(cond op asInt32 = O_ICMP and: [cond aux = 2]) ifFalse: [^self].
	body := hb succ0.
	(self block: body isIn: h) ifFalse: [^self].
	phi := self intValueOf: cond a.
	limit := ir resolve: cond b.
	((ir node: phi) op asInt32 = O_PHI and: [(ir node: phi) block = h and: [(ir node: phi) nargs asInt32 = 2 and: [(ir node: phi) tkind asInt32 = T_SMI]]]) ifFalse: [^self].
	((ir node: limit) tkind asInt32 = T_SMI and: [self isBefore: limit loop: h]) ifFalse: [^self].
	i0 := ir resolve: (ir operand: (ir node: phi) args + index).
	back := ir node: (ir resolve: (ir operand: (ir node: phi) args + (1 - index))).
	nd := ir node: (ir resolve: back b).
	(back op asInt32 = O_IADD and: [(self intValueOf: back a) = phi and: [nd op asInt32 = O_CONST and: [(nd aux bitAnd: 1) = 1 and: [nd aux >= 3]]]]) ifFalse: [^self].
	(ir node: i0) tkind asInt32 = T_SMI ifFalse: [^self].
	s := -1.
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		((nd op asInt32 = O_INDEXLOAD or: [nd op asInt32 = O_INDEXSTORE]) and: [nd block >= 0 and: [(nd flags bitAnd: NF_NOBOUNDS) = 0 and: [(self dominates: body block: nd block) and: [self isPhi: phi plusOne: (ir resolve: nd b)]]]]) ifTrue: [
			x := ir resolve: nd a.
			((self isBefore: x loop: h) and: [(ir node: x) tkind asInt32 = T_OBJ and: [((ir flagsAtAct: nd bcact pc: nd bcpc) bitAnd: feedback deoptHoisted) = 0]]) ifTrue: [
				s < 0 ifTrue: [
					s := self state: hb entryState enteredFrom: index of: h.
					ir full ifTrue: [^self].
					self guard: -1 or: 0 atMost: i0 for: m in: entry state: s].
				size := ir newNode: O_SIZE rep: R_OOP.
				ir full ifTrue: [^self].
				nd := ir node: m.
				(ir node: size) a: x.
				(ir node: size) aux: nd aux.
				(ir node: size) aux2: nd aux2.
				(ir node: size) tkind: T_SMI.
				(ir node: size) bcact: nd bcact.
				(ir node: size) bcpc: nd bcpc.
				ir insert: size before: (ir block: entry) last.
				self guard: limit atMost: size for: m in: entry state: s.
				ir full ifTrue: [^self].
				(ir node: m) flags: ((ir node: m) flags bitOr: NF_NOBOUNDS)]]]
!
isPhi: phi plusOne: v
	"v is phi + 1."
	| nd c |
	nd := ir node: v.
	(nd op asInt32 = O_IADD and: [(self intValueOf: nd a) = phi]) ifFalse: [^false].
	c := ir node: (ir resolve: nd b).
	^c op asInt32 = O_CONST and: [c aux = 3]
!
intValueOf: v
	"v, or what a guard that it is a SmallInteger guards when that is one (a phi that replaced a load: dropIntChecks drops the guard later)."
	| n |
	n := ir resolve: v.
	[(ir node: n) op asInt32 = O_GUARDINT and: [(ir node: (ir resolve: (ir node: n) a)) tkind asInt32 = T_SMI]] whileTrue: [n := ir resolve: (ir node: n) a].
	^n
!
rangeBoundsOutOf: h entry: entry index: index
	"Loop h, entered from block entry alone (h's predecessor index): an indexed load or store in it, of an object from before the loop (its class known there), at an index whose range is known and starts at 1 or above (ranges), checks no bounds if, once in entry, the range's top is at most the object's size. A check that fails there leaves at the loop's head and marks the access's send: it checks every time from then on."
	<function>
	| s nd i x size |
	s := -1.
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		((nd op asInt32 = O_INDEXLOAD or: [nd op asInt32 = O_INDEXSTORE]) and: [nd block >= 0 and: [(nd flags bitAnd: NF_NOBOUNDS) = 0 and: [self block: nd block isIn: h]]]) ifTrue: [
			i := ir node: (ir resolve: nd b).
			x := ir resolve: nd a.
			(i lo >= 1 and: [i hi < 16r40000000 and: [(self isBefore: x loop: h) and: [(ir node: x) tkind asInt32 = T_OBJ and: [((ir flagsAtAct: nd bcact pc: nd bcpc) bitAnd: feedback deoptHoisted) = 0]]]]) ifTrue: [
				s < 0 ifTrue: [
					s := self state: (ir block: h) entryState enteredFrom: index of: h.
					ir full ifTrue: [^self]].
				size := ir newNode: O_SIZE rep: R_OOP.
				ir full ifTrue: [^self].
				nd := ir node: m.
				(ir node: size) a: x.
				(ir node: size) aux: nd aux.
				(ir node: size) aux2: nd aux2.
				(ir node: size) tkind: T_SMI.
				(ir node: size) bcact: nd bcact.
				(ir node: size) bcpc: nd bcpc.
				ir insert: size before: (ir block: entry) last.
				self guard: -1 or: (ir node: (ir resolve: nd b)) hi atMost: size for: m in: entry state: s.
				ir full ifTrue: [^self].
				(ir node: m) flags: ((ir node: m) flags bitOr: NF_NOBOUNDS)]]]
!
promoteOuterTempsOf: h entry: entry index: index latch: latch
	"Loop h, entered from block entry alone (h's predecessor index), latch its block back, sends nothing: an outer temp, or a field of an object from before the loop, that one store on every turn writes (and no other store of an outer temp or field of that index, nor a read of the outer temp through another closure; for a field no store of an outer temp) is a phi of h, what it holds where the loop is entered and what the store wrote; the store stays. Loads of it before the store read the phi, loads after it the value stored. A SmallInteger stored makes the phi one, the value at the entry guarded there (failing, the interpreter goes on from the loop's head, and the load's send is marked: no phi for it again)."
	<function>
	| nd st s e g p u nu ok ld |
	((ir block: h) npreds = 2 and: [(self loop: h changesOuterTemp: -1) not]) ifFalse: [^self].
	s := -1.
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		(nd block >= 0 and: [(ir block: nd block) loop = h and: [(self dominates: nd block block: latch) and: [(nd op asInt32 = O_OUTERSTORE and: [nd c >= 0]) or: [nd op asInt32 = O_STOREFIELD and: [self isBefore: (ir resolve: nd a) loop: h]]]]]) ifTrue: [
			"the store, alone among the loop's of that index; loads of it all in h's own blocks, before or after it"
			st := m.
			ok := true.
			ld := -1.
			0 to: ir nodeCount - 1 do: [:j |
				u := ir node: j.
				(u block >= 0 and: [j ~= st and: [(self is: u sameIndexAs: nd) and: [self block: u block isIn: h]]]) ifTrue: [
					(u op asInt32 = O_OUTERSTORE or: [u op asInt32 = O_STOREFIELD]) ifTrue: [ok := false].
					((self is: u loadOf: nd) and: [(ir block: u block) loop = h])
						ifTrue: [
							((self dominates: u block block: nd block) or: [self dominates: nd block block: u block]) ifFalse: [ok := false].
							(u block = nd block and: [(self isBefore: j node: st) not and: [(self isBefore: st node: j) not]]) ifTrue: [ok := false].
							ld < 0 ifTrue: [ld := j]]
						ifFalse: [u op asInt32 = O_OUTERLOAD ifTrue: [ok := false]]]].
			"a field: no store of an outer temp in the loop (a Context's slots are fields)"
			nd op asInt32 = O_STOREFIELD ifTrue: [
				0 to: ir nodeCount - 1 do: [:j | ((ir node: j) block >= 0 and: [(ir node: j) op asInt32 = O_OUTERSTORE and: [self block: (ir node: j) block isIn: h]]) ifTrue: [ok := false]]].
			(ok and: [ld >= 0 and: [((ir flagsAtAct: (ir node: ld) bcact pc: (ir node: ld) bcpc) bitAnd: feedback deoptHoisted) = 0]]) ifTrue: [
				s < 0 ifTrue: [
					s := self state: (ir block: h) entryState enteredFrom: index of: h.
					ir full ifTrue: [^self]].
				"what it holds where the loop is entered"
				nd := ir node: st.
				e := ir newNode: (nd op asInt32 = O_OUTERSTORE ifTrue: [O_OUTERLOAD] ifFalse: [O_LOADFIELD]) rep: R_OOP.
				ir full ifTrue: [^self].
				nd := ir node: st.
				(ir node: e) a: (ir resolve: nd a).
				nd op asInt32 = O_OUTERSTORE ifTrue: [
					(ir node: e) c: (ir resolve: nd c).
					(ir node: e) aux2: nd aux2].
				(ir node: e) aux: nd aux.
				(ir node: e) bcact: (ir node: ld) bcact.
				(ir node: e) bcpc: (ir node: ld) bcpc.
				ir insert: e before: (ir block: entry) last.
				(ir node: (ir resolve: nd b)) tkind asInt32 = T_SMI ifTrue: [
					g := ir newNode: O_GUARDINT rep: R_OOP.
					ir full ifTrue: [^self].
					(ir node: g) a: e.
					(ir node: g) state: s.
					(ir node: g) flags: (NF_GUARD bitOr: NF_HOISTED).
					(ir node: g) tkind: T_SMI.
					(ir node: g) bcact: (ir node: ld) bcact.
					(ir node: g) bcpc: (ir node: ld) bcpc.
					ir insert: g before: (ir block: entry) last.
					e := g].
				p := ir newNode: O_PHI rep: R_OOP.
				ir full ifTrue: [^self].
				(ir node: p) nargs: 2.
				(ir node: p) args: (ir allocOperands: 2).
				ir full ifTrue: [^self].
				(ir node: p) tkind: (ir node: e) tkind.
				(ir node: p) bcact: (ir node: ld) bcact.
				(ir node: p) bcpc: (ir node: ld) bcpc.
				ir operand: (ir node: p) args + index put: e.
				ir operand: (ir node: p) args + (1 - index) put: (ir resolve: (ir node: st) b).
				ir insert: p before: (ir block: h) first.
				"the loads: the phi before the store, the value stored after it"
				0 to: ir nodeCount - 1 do: [:j |
					u := ir node: j.
					(u block >= 0 and: [j ~= e and: [(self is: u loadOf: (ir node: st)) and: [(ir block: u block) loop = h]]]) ifTrue: [
						nu := ((self dominates: (ir node: st) block block: u block) and: [u block ~= (ir node: st) block or: [self isBefore: st node: j]])
							ifTrue: [ir resolve: (ir node: st) b]
							ifFalse: [p].
						u fwd: nu.
						ir unlink: j]]]]]
!
is: u sameIndexAs: st
	"u stores or loads what store st writes, or an outer temp or field of the same index (of another closure, level or object)."
	st op asInt32 = O_OUTERSTORE ifTrue: [^(u op asInt32 = O_OUTERSTORE or: [u op asInt32 = O_OUTERLOAD]) and: [u aux2 = st aux2]].
	^(u op asInt32 = O_STOREFIELD or: [u op asInt32 = O_LOADFIELD]) and: [u aux = st aux]
!
is: u loadOf: st
	"u loads exactly what store st writes: the outer temp of the same closure, level and index (through the frame found before the loop), or the same field of the same object."
	st op asInt32 = O_OUTERSTORE ifTrue: [^u op asInt32 = O_OUTERLOAD and: [u aux2 = st aux2 and: [u aux = st aux and: [u c >= 0 and: [(ir resolve: u a) = (ir resolve: st a)]]]]].
	^u op asInt32 = O_LOADFIELD and: [u aux = st aux and: [(ir resolve: u a) = (ir resolve: st a)]]
!
isBefore: m node: n
	"Node m comes before node n in their block."
	| k |
	k := (ir node: m) next.
	[k >= 0] whileTrue: [
		k = n ifTrue: [^true].
		k := (ir node: k) next].
	^false
!
outerSlotsOutOf: h entry: entry
	"Loop h, entered from block entry alone, sends nothing: whether the home Context of a closure from before the loop is married to a frame, and where that frame is, stays as it is while the loop runs (what else may run, at an interrupt check, runs when the code has left the unit). The loop's loads and stores of that closure's outer temps take it from a node where the loop is entered (O_OUTERSLOT, one for each closure and level)."
	<function>
	| b n nd op slot k slots |
	(self loop: h changesOuterTemp: -1) ifTrue: [^self].
	slots := self local: 'int32_t[8]'.
	k := 0.
	0 to: psOrderCount - 1 do: [:i |
		b := psOrder at: i.
		(self block: b isIn: h) ifTrue: [
			n := (ir block: b) first.
			[n >= 0] whileTrue: [
				nd := ir node: n.
				op := nd op asInt32.
				((op = O_OUTERLOAD or: [op = O_OUTERSTORE]) and: [nd c < 0 and: [self isBefore: nd a loop: h]]) ifTrue: [
					slot := -1.
					0 to: k - 1 do: [:j |
						((ir node: (slots at: j)) a = nd a and: [(ir node: (slots at: j)) aux = nd aux]) ifTrue: [slot := slots at: j]].
					(slot < 0 and: [k < 8]) ifTrue: [
						slot := ir newNode: O_OUTERSLOT rep: R_OOP.
						ir full ifTrue: [^self].
						nd := ir node: n.
						(ir node: slot) a: nd a.
						(ir node: slot) aux: nd aux.
						ir insert: slot before: (ir block: entry) last.
						slots at: k put: slot.
						k := k + 1].
					slot >= 0 ifTrue: [(ir node: n) c: slot]].
				n := (ir node: n) next]]]
!
boundsOutOf: h entry: entry index: index
	"Loop h, entered from block entry alone (h's predecessor index), is counted (countedLoop:index:): on its turn t, 0 to T = (limit - start) // step, its counter is start + step * t, and so is every induction variable of it (a phi of h that a constant is added to on every way around, inductionStep:of:index:: PixelPack's s := s + 4) its start plus its step times t. An indexed load or store in the loop, of an object from before the loop (its class known there), at an index affine in one of them (b + c * v + k: affine:of:) has its least and its greatest index on the first and the last turn: it checks no bounds if, once in entry, the loop is entered with the counter within its limit, the least index is at least 1 and the greatest at most the object's size (as reversed's n + 1 - i, the mismatch loop's start + i - 1 of two objects, a loop by 4's i + 3). A check that fails there, or arithmetic of it that overflows, leaves at the loop's head and marks the access's send: it checks every time from then on."
	<function>
	| phi i0 step limit s t nd x q e q0 qT v0 vT lo hi size c |
	phi := self countedLoop: h index: index.
	phi < 0 ifTrue: [^self].
	i0 := psCounted at: 1.
	step := psCounted at: 2.
	limit := psCounted at: 3.
	s := -1.
	t := -1.
	0 to: ir nodeCount - 1 do: [:m |
		nd := ir node: m.
		((nd op asInt32 = O_INDEXLOAD or: [nd op asInt32 = O_INDEXSTORE]) and: [nd block >= 0 and: [(nd flags bitAnd: NF_NOBOUNDS) = 0 and: [self block: nd block isIn: h]]]) ifTrue: [
			x := ir resolve: nd a.
			((self isBefore: x loop: h) and: [(ir node: x) tkind asInt32 = T_OBJ and: [((ir flagsAtAct: nd bcact pc: nd bcpc) bitAnd: feedback deoptHoisted) = 0 and: [self affine: (ir resolve: nd b) of: h]]]) ifTrue: [
				q := psAffine at: 0.
				c := psAffine at: 1.
				e := q = phi ifTrue: [step] ifFalse: [self inductionStep: q of: h index: index].
				e ~= 0 ifTrue: [
					s < 0 ifTrue: [
						s := self state: (ir block: h) entryState enteredFrom: index of: h.
						ir full ifTrue: [^self].
						step > 0
							ifTrue: [self guard: i0 atMost: limit for: m in: entry state: s]
							ifFalse: [self guard: limit atMost: i0 for: m in: entry state: s].
						ir full ifTrue: [^self]].
					q0 := ir resolve: (ir operand: (ir node: q) args + index).
					"its value on the last turn"
					(q = phi and: [step = 1 or: [step = -1]])
						ifTrue: [qT := limit]
						ifFalse: [
							t < 0 ifTrue: [
								t := step > 0
									ifTrue: [self hoisted: O_ISUB a: limit b: i0 for: m in: entry state: s]
									ifFalse: [self hoisted: O_ISUB a: i0 b: limit for: m in: entry state: s].
								(step = 1 or: [step = -1]) ifFalse: [t := self hoisted: O_IDIV a: t b: (self smallInteger: (step > 0 ifTrue: [step] ifFalse: [step negated]) in: entry) for: m in: entry state: s].
								ir full ifTrue: [^self]].
							qT := e = 1
								ifTrue: [self hoisted: O_IADD a: q0 b: t for: m in: entry state: s]
								ifFalse: [
									e = -1
										ifTrue: [self hoisted: O_ISUB a: q0 b: t for: m in: entry state: s]
										ifFalse: [self hoisted: O_IADD a: q0 b: (self hoisted: O_IMUL a: t b: (self smallInteger: e in: entry) for: m in: entry state: s) for: m in: entry state: s]]].
					v0 := self affineAt: q0 for: m in: entry state: s.
					vT := self affineAt: qT for: m in: entry state: s.
					ir full ifTrue: [^self].
					c * e > 0
						ifTrue: [
							lo := v0.
							hi := vT]
						ifFalse: [
							lo := vT.
							hi := v0].
					"a least index that is a constant below 1 would fail every time"
					((self isIntConst: lo) and: [(self intVal: (ir node: lo) aux asUInt64) < 1]) ifFalse: [
						(self isIntConst: lo) ifFalse: [self guard: -1 atMost: lo for: m in: entry state: s].
						size := ir newNode: O_SIZE rep: R_OOP.
						ir full ifTrue: [^self].
						nd := ir node: m.
						(ir node: size) a: x.
						(ir node: size) aux: nd aux.
						(ir node: size) aux2: nd aux2.
						(ir node: size) tkind: T_SMI.
						(ir node: size) bcact: nd bcact.
						(ir node: size) bcpc: nd bcpc.
						ir insert: size before: (ir block: entry) last.
						self guard: hi atMost: size for: m in: entry state: s.
						ir full ifTrue: [^self].
						(ir node: m) flags: ((ir node: m) flags bitOr: NF_NOBOUNDS).
						self inBounds: (ir resolve: (ir node: m) b)]]]]]
!
inBounds: v
	"Index v of an access its loop checked once (boundsOutOf:entry:index:) is within the object's bounds on every turn, and so is, give or take a constant, the sum or difference it adds a constant to, and so on down (start + i - 1: start + i): these check no overflow."
	| n nd k |
	n := v.
	k := 0.
	[k < 6] whileTrue: [
		nd := ir node: n.
		((nd op asInt32 = O_IADD or: [nd op asInt32 = O_ISUB]) and: [nd block >= 0]) ifFalse: [^self].
		self inRange: nd.
		n := (self isIntConst: (ir resolve: nd b))
			ifTrue: [self intValueOf: nd a]
			ifFalse: [(self isIntConst: (ir resolve: nd a)) ifTrue: [self intValueOf: nd b] ifFalse: [-1]].
		n < 0 ifTrue: [^self].
		k := k + 1]
!
countedLoop: h index: index
	"Loop h, entered from its predecessor index alone, counts a SmallInteger phi by a constant step and goes around again while the phi's next value is at most (counting down: at least) a SmallInteger limit from before the loop, the branch on every way back (to:do:, to:by:do:): answer the phi, its start, step and limit in psCounted; else -1. Wherever the loop reads the phi, it is between its start and the limit if the loop was entered so."
	<function>
	| hb e c prev steps cond limit phi n nd i0 i1 step |
	hb := ir block: h.
	hb npreds = 2 ifFalse: [^-1].
	"the branch every way back passes: on the phi's next value <= limit (>=), true to go around"
	e := hb preds.
	index = 0 ifTrue: [e := (ir edge: e) next].
	c := (ir edge: e) from.
	prev := h.
	steps := 0.
	[(ir block: c) succ1 < 0 and: [(ir block: c) npreds = 1 and: [steps < 4]]] whileTrue: [
		prev := c.
		c := (ir edge: (ir block: c) preds) from.
		steps := steps + 1].
	((ir block: c) succ1 >= 0 and: [(ir block: c) succ0 = prev and: [(ir block: c) last >= 0]]) ifFalse: [^-1].
	cond := ir node: (ir resolve: (ir node: (ir block: c) last) a).
	(cond op asInt32 = O_ICMP and: [cond aux = 4 or: [cond aux = 5]]) ifFalse: [^-1].
	limit := ir resolve: cond b.
	((ir node: limit) tkind asInt32 = T_SMI and: [self isBefore: limit loop: h]) ifFalse: [^-1].
	phi := -1.
	n := hb first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		(nd fwd < 0 and: [nd tkind asInt32 = T_SMI and: [nd nargs asInt32 = 2 and: [(ir resolve: (ir operand: nd args + (1 - index))) = (ir resolve: cond a)]]]) ifTrue: [phi := n].
		n := nd next].
	phi < 0 ifTrue: [^-1].
	i0 := ir resolve: (ir operand: (ir node: phi) args + index).
	(ir node: i0) tkind asInt32 = T_SMI ifFalse: [^-1].
	i1 := ir node: (ir resolve: cond a).
	(i1 op asInt32 = O_IADD and: [(ir resolve: i1 a) = phi and: [self isIntConst: (ir resolve: i1 b)]]) ifFalse: [^-1].
	step := self intVal: (ir node: (ir resolve: i1 b)) aux asUInt64.
	((cond aux = 4 and: [step between: 1 and: 16r10000]) or: [cond aux = 5 and: [step between: -16r10000 and: -1]]) ifFalse: [^-1].
	psCounted at: 0 put: phi.
	psCounted at: 1 put: i0.
	psCounted at: 2 put: step.
	psCounted at: 3 put: limit.
	^phi
!
inductionStep: q of: h index: index
	"If q is a SmallInteger phi of loop h (entered from its predecessor index) that a constant is added to on every way around (the value it takes back is q plus or minus the constant): that constant, else 0."
	| nd back y k |
	nd := ir node: q.
	(nd op asInt32 = O_PHI and: [nd block = h and: [nd nargs asInt32 = 2 and: [nd tkind asInt32 = T_SMI and: [nd fwd < 0]]]]) ifFalse: [^0].
	(ir node: (ir resolve: (ir operand: nd args + index))) tkind asInt32 = T_SMI ifFalse: [^0].
	back := ir node: (ir resolve: (ir operand: nd args + (1 - index))).
	(back op asInt32 = O_IADD or: [back op asInt32 = O_ISUB]) ifFalse: [^0].
	y := -1.
	(self intValueOf: back a) = q ifTrue: [y := ir resolve: back b].
	(y < 0 and: [back op asInt32 = O_IADD and: [(self intValueOf: back b) = q]]) ifTrue: [y := ir resolve: back a].
	(y >= 0 and: [self isIntConst: y]) ifFalse: [^0].
	k := self intVal: (ir node: y) aux asUInt64.
	(k between: -16r10000 and: 16r10000) ifFalse: [^0].
	^back op asInt32 = O_IADD ifTrue: [k] ifFalse: [k negated]
!
affine: v of: h
	"Index v is affine in a phi of loop h: b + c * phi + k, b a sum or difference of at most two SmallIntegers from before the loop, c (not 0) and k constants; into psAffine: the phi, c, k, the number of b's terms, then each term and its sign."
	psAffine at: 0 put: -1.
	psAffine at: 1 put: 0.
	psAffine at: 2 put: 0.
	psAffine at: 3 put: 0.
	(self affine: v of: h times: 1 depth: 0) ifFalse: [^false].
	^(psAffine at: 0) >= 0 and: [(psAffine at: 1) ~= 0 and: [((psAffine at: 1) between: -16r100000 and: 16r100000) and: [(psAffine at: 2) between: -16r10000000000 and: 16r10000000000]]]
!
affine: v of: h times: f depth: d
	"affine:of:, v counted f times."
	<function>
	| n nd op y k |
	n := self intValueOf: v.
	nd := ir node: n.
	op := nd op asInt32.
	(self isIntConst: n) ifTrue: [
		k := self intVal: nd aux asUInt64.
		(k between: -16r40000000 and: 16r40000000) ifFalse: [^false].
		psAffine at: 2 put: (psAffine at: 2) + (f * k).
		^true].
	nd tkind asInt32 = T_SMI ifFalse: [^false].
	(self isBefore: n loop: h) ifTrue: [
		((f = 1 or: [f = -1]) and: [(psAffine at: 3) < 2]) ifFalse: [^false].
		psAffine at: 4 + (2 * (psAffine at: 3)) put: n.
		psAffine at: 5 + (2 * (psAffine at: 3)) put: f.
		psAffine at: 3 put: (psAffine at: 3) + 1.
		^true].
	(op = O_PHI and: [nd block = h]) ifTrue: [
		((psAffine at: 0) >= 0 and: [(psAffine at: 0) ~= n]) ifTrue: [^false].
		psAffine at: 0 put: n.
		psAffine at: 1 put: (psAffine at: 1) + f.
		^true].
	d >= 6 ifTrue: [^false].
	(op = O_IADD or: [op = O_ISUB]) ifTrue: [
		^(self affine: nd a of: h times: f depth: d + 1) and: [self affine: nd b of: h times: (op = O_IADD ifTrue: [f] ifFalse: [f negated]) depth: d + 1]].
	op = O_IMUL ifFalse: [^false].
	(self isIntConst: (ir resolve: nd b))
		ifTrue: [
			y := nd a.
			k := self intVal: (ir node: (ir resolve: nd b)) aux asUInt64]
		ifFalse: [
			(self isIntConst: (ir resolve: nd a)) ifFalse: [^false].
			y := nd b.
			k := self intVal: (ir node: (ir resolve: nd a)) aux asUInt64].
	((k between: -16r10000 and: 16r10000) and: [(f * k) between: -16r100000 and: 16r100000]) ifFalse: [^false].
	^self affine: y of: h times: f * k depth: d + 1
!
affineAt: q0 for: m in: entry state: s
	"At the end of block entry: the index psAffine describes (affine:of:) with its phi's value q0; for the bounds of indexed access m (hoisted:a:b:for:in:state:)."
	<function>
	| c acc b sg k |
	c := psAffine at: 1.
	acc := -1.
	c = 1 ifTrue: [acc := q0].
	(c = 1 or: [c = -1]) ifFalse: [acc := self hoisted: O_IMUL a: q0 b: (self smallInteger: c in: entry) for: m in: entry state: s].
	0 to: (psAffine at: 3) - 1 do: [:j |
		b := psAffine at: 4 + (2 * j).
		sg := psAffine at: 5 + (2 * j).
		acc := acc < 0
			ifTrue: [sg > 0 ifTrue: [b] ifFalse: [self hoisted: O_ISUB a: (self smallInteger: 0 in: entry) b: b for: m in: entry state: s]]
			ifFalse: [self hoisted: (sg > 0 ifTrue: [O_IADD] ifFalse: [O_ISUB]) a: acc b: b for: m in: entry state: s]].
	c = -1 ifTrue: [acc := self hoisted: O_ISUB a: (acc < 0 ifTrue: [self smallInteger: 0 in: entry] ifFalse: [acc]) b: q0 for: m in: entry state: s].
	k := psAffine at: 2.
	k ~= 0 ifTrue: [acc := self hoisted: O_IADD a: acc b: (self smallInteger: k in: entry) for: m in: entry state: s].
	^acc
!
hoisted: op a: a b: b for: m in: entry state: s
	"At the end of block entry: SmallIntegers a op b (O_IADD, O_ISUB, O_IMUL, O_IDIV floored), of constants a constant; one that overflows leaves at state s, for the bounds of indexed access m, whose send a failure marks."
	<function>
	| n nd x y v |
	(a < 0 or: [b < 0 or: [ir full]]) ifTrue: [^-1].
	((self isIntConst: a) and: [self isIntConst: b]) ifTrue: [
		x := self intVal: (ir node: a) aux asUInt64.
		y := self intVal: (ir node: b) aux asUInt64.
		((x between: -16r40000000 and: 16r40000000) and: [(y between: -16r40000000 and: 16r40000000) and: [op ~= O_IDIV or: [x >= 0 and: [y > 0]]]]) ifTrue: [
			v := op = O_IADD
				ifTrue: [x + y]
				ifFalse: [
					op = O_ISUB
						ifTrue: [x - y]
						ifFalse: [op = O_IMUL ifTrue: [x * y] ifFalse: [x quo: y]]].
			^self smallInteger: v in: entry]].
	n := ir newNode: op rep: R_OOP.
	ir full ifTrue: [^-1].
	nd := ir node: n.
	nd a: a.
	nd b: b.
	nd tkind: T_SMI.
	nd state: s.
	nd flags: (NF_GUARD bitOr: NF_HOISTED).
	nd bcact: (ir node: m) bcact.
	nd bcpc: (ir node: m) bcpc.
	ir insert: n before: (ir block: entry) last.
	^n
!
smallInteger: v in: entry
	"A SmallInteger constant v at the end of block entry."
	<function>
	| n nd |
	n := ir newNode: O_CONST rep: R_OOP.
	ir full ifTrue: [^-1].
	nd := ir node: n.
	nd aux: (self intOop: v) asInt64.
	nd flags: NF_PURE.
	nd tkind: T_SMI.
	nd lo: v.
	nd hi: v.
	ir insert: n before: (ir block: entry) last.
	^n
!
isIntConst: v
	"v is a SmallInteger constant."
	| nd |
	nd := ir node: v.
	^nd op asInt32 = O_CONST and: [nd rep asInt32 = R_OOP and: [self isInt: nd aux asUInt64]]
!
isBefore: v loop: h
	"Value v is from before loop h: a constant, or defined in a block h does not dominate."
	| b |
	(ir node: v) op asInt32 = O_CONST ifTrue: [^true].
	b := (ir node: v) block.
	^b >= 0 and: [(self dominates: h block: b) not]
!
guard: a atMost: b for: m in: entry state: s
	"At the end of block entry: SmallInteger a (-1: the constant 1) is at most SmallInteger b, else leave at state s; for the bounds of indexed access m, whose send a failure marks."
	self guard: a or: 1 atMost: b for: m in: entry state: s
!
guard: a below: b for: m in: entry state: s
	"guard:atMost:for:in:state:, strictly below."
	self guard: a atMost: b for: m in: entry state: s.
	ir full ifFalse: [(ir node: (ir node: (ir block: entry) last) prev) aux2: 1]
!
guard: a or: k atMost: b for: m in: entry state: s
	"guard:atMost:for:in:state:, a -1 for the constant SmallInteger k."
	| g |
	g := ir newNode: O_GUARDLE rep: R_NONE.
	ir full ifTrue: [^self].
	(ir node: g) a: a.
	a < 0 ifTrue: [(ir node: g) aux: (self intOop: k) asInt64].
	(ir node: g) b: b.
	(ir node: g) state: s.
	(ir node: g) flags: (NF_GUARD bitOr: NF_HOISTED).
	(ir node: g) bcact: (ir node: m) bcact.
	(ir node: g) bcpc: (ir node: m) bcpc.
	ir insert: g before: (ir block: entry) last
!
isHoistable: n outOf: h
	"n is a guard of a value from before loop h (or its decoding as a double), or a sum or difference of SmallIntegers from before it (its overflow check a guard), and no guard moved out of a loop has failed at its site."
	| nd op b |
	nd := ir node: n.
	op := nd op asInt32.
	(op = O_IADD or: [op = O_ISUB])
		ifTrue: [((self isBefore: (ir resolve: nd a) loop: h) and: [self isBefore: (ir resolve: nd b) loop: h]) ifFalse: [^false]]
		ifFalse: [
			(op = O_GUARDCLASS or: [op = O_GUARDINT or: [op = O_GUARDCLOSURE or: [op = O_GUARDEQ or: [op = O_UNBOXF]]]]) ifFalse: [^false].
			b := (ir node: nd a) block.
			b < 0 ifTrue: [^false].
			(self dominates: h block: b) ifTrue: [^false]].
	^((ir flagsAtAct: nd bcact pc: nd bcpc) bitAnd: feedback deoptHoisted) = 0
!
isInvariantFieldLoad: n of: h
	"n loads a field of an object from before loop h, and no turn of the loop writes that field of an object that may be it (a store into it, unless both classes are known and differ; a send, or a store into an outer temp, may write anything)."
	<function>
	| nd b m md op |
	nd := ir node: n.
	(nd op asInt32 = O_LOADFIELD and: [self isBefore: (ir resolve: nd a) loop: h]) ifFalse: [^false].
	0 to: psOrderCount - 1 do: [:k |
		b := psOrder at: k.
		(self block: b isIn: h) ifTrue: [
			m := (ir block: b) first.
			[m >= 0] whileTrue: [
				md := ir node: m.
				op := md op asInt32.
				(op = O_SEND or: [op = O_CALL or: [op = O_OUTERSTORE or: [op = O_STOREFIELD and: [md aux = nd aux and: [self mayBeSame: (ir resolve: md a) as: (ir resolve: nd a)]]]]]) ifTrue: [^false].
				m := md next]]].
	^true
!
mayBeSame: x as: y
	"Values x and y may be one object: unless the classes of both are known and differ."
	| cx cy |
	cx := self knownClassOf: x.
	cy := self knownClassOf: y.
	^cx = 0 or: [cy = 0 or: [cx = cy]]
!
knownClassOf: v
	"v's class if the IR knows it (a constant's, a guard's or cast's), else 0."
	<returns: 'oop'>
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [^ir constClassOf: v].
	(nd tkind asInt32 = T_OBJ and: [nd tcls ~= 0]) ifTrue: [^nd tcls].
	^0
!
isClosureLoad: n of: h
	"n loads, from before loop h, what never changes of a closure whose body is inline (O_GUARDCLOSURE): its outerContext, or that Context's receiver."
	| nd x |
	nd := ir node: n.
	nd op asInt32 = O_LOADFIELD ifFalse: [^false].
	x := ir node: nd a.
	(x block < 0 or: [self dominates: h block: x block]) ifTrue: [^false].
	x op asInt32 = O_GUARDCLOSURE ifTrue: [^nd aux = BC_OUTER].
	^x op asInt32 = O_LOADFIELD and: [x aux = BC_OUTER and: [(ir node: x a) op asInt32 = O_GUARDCLOSURE and: [nd aux = CTX_RECEIVER]]]
!
ranges
	"Integer ranges (lo..hi): forward through the blocks (forwardRanges), then each loop's phis of SmallIntegers narrowed by what flows into them (rangesOfLoop:) and forward again, twice: an outer loop's phi may rest on an inner loop's, a loop's sum on its counter."
	<function>
	self forwardRanges.
	self findLoops.
	0 to: ir blockCount - 1 do: [:b |
		psLoopK at: b put: 0.
		psLoopConst at: b put: -1.
		psLoopCap at: b put: 0].
	1 to: 2 do: [:r |
		self loopRanges ifTrue: [self forwardRanges]]
!
loopRanges
	"rangesOfLoop: of each loop, outer ones first; whether a phi narrowed."
	<function>
	| h changed |
	changed := false.
	0 to: psOrderCount - 1 do: [:i |
		h := psOrder at: i.
		(((ir block: h) flags bitAnd: BF_LOOP) ~= 0 and: [(ir block: h) loop = h]) ifTrue: [
			(self rangesOfLoop: h) ifTrue: [changed := true]]].
	^changed
!
rangesOfLoop: h
	"Loop h's phis of SmallIntegers (up to 16) narrowed to what flows into them; and with one edge in and one around, a phi that every turn adds a range to (incrementOf:phi:loop:depth:) to where it starts plus that range times the most turns the loop may take, its counter's (counterOf:index:): from the counter's start to its limit, over its step. Where it helps, guards where the loop is entered (failing, the interpreter goes on from the loop's head and the guard's send is marked: not again) bound the counter's start and limit to the largest SmallInteger less twice the step (its sum then checks no overflow) and the limit less the start to 2^32, 2^28 or 2^24 turns (the largest that bounds as many phis as any: sums of bytes, a sum of such sums). Answer whether a phi narrowed."
	<function>
	| hb e p k entry index entries n nd cnt counter back limit c t0 tk best bestK kk got changed s cap e0 ehi elo lhi canGuard g d |
	hb := ir block: h.
	cnt := 0.
	n := hb first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		(nd fwd < 0 and: [nd tkind asInt32 = T_SMI and: [cnt < 16]]) ifTrue: [
			psTPhi at: cnt put: n.
			cnt := cnt + 1].
		n := nd next].
	psTCount := cnt asInt32.
	cnt = 0 ifTrue: [^false].
	entry := -1.
	index := -1.
	entries := 0.
	k := 0.
	e := hb preds.
	[e >= 0] whileTrue: [
		p := (ir edge: e) from.
		(ir block: p) rpo < hb rpo ifTrue: [
			entries := entries + 1.
			entry := p.
			index := k].
		k := k + 1.
		e := (ir edge: e) next].
	(entries = 1 and: [hb npreds = 2]) ifFalse: [index := -1].
	counter := -1.
	index >= 0 ifTrue: [counter := self counterOf: h index: index].
	canGuard := index >= 0 and: [(runtime flag: runtime hoistFlag) and: [(ir block: entry) succ1 < 0 and: [hb entryState >= 0]]].
	psCHi := VM_INT_MAX.
	t0 := -1.
	c := 1.
	s := -1.
	counter >= 0 ifTrue: [
		c := psCStep.
		limit := psCLimit.
		back := ir resolve: (ir operand: (ir node: counter) args + (1 - index)).
		e0 := ir resolve: (ir operand: (ir node: counter) args + index).
		cap := VM_INT_MAX - (2 * c).
		ehi := (ir node: e0) hi.
		elo := (ir node: e0) lo.
		lhi := (ir node: limit) hi.
		((ehi > cap or: [lhi > cap]) and: [canGuard and: [(psLoopCap at: h) = 0 and: [(self isMarked: back) not]]]) ifTrue: [
			s := self state: hb entryState enteredFrom: index of: h.
			ir full ifTrue: [^false].
			ehi > cap ifTrue: [self rangeGuard: e0 atMost: (self constantInt: cap in: entry) for: back in: entry state: s].
			lhi > cap ifTrue: [self rangeGuard: limit atMost: (self constantInt: cap in: entry) for: back in: entry state: s].
			ir full ifTrue: [^false].
			psLoopCap at: h put: 1].
		(psLoopCap at: h) = 1 ifTrue: [
			ehi := ehi min: cap.
			lhi := lhi min: cap].
		psCHead ifTrue: [psCHi := ehi max: lhi + c] ifFalse: [psCHi := ehi max: lhi].
		(elo > VM_INT_MIN and: [lhi < VM_INT_MAX]) ifTrue: [
			lhi < elo
				ifTrue: [t0 := 1]
				ifFalse: [t0 := ((lhi - elo) quo: c) + 1].
			t0 > 16r10000000000 ifTrue: [t0 := -1]]].
	tk := t0.
	(psLoopK at: h) > 0 ifTrue: [tk := self trips: t0 within: (psLoopK at: h) step: c].
	best := self evaluateLoop: h index: index trips: tk counter: counter.
	bestK := 0.
	(counter >= 0 and: [canGuard and: [(self isMarked: psCCond) not]]) ifTrue: [
		kk := 16r100000000.
		[kk >= 16r1000000] whileTrue: [
			((psLoopK at: h) = 0 or: [kk < (psLoopK at: h)]) ifTrue: [
				got := self evaluateLoop: h index: index trips: (self trips: t0 within: kk step: c) counter: counter.
				got > best ifTrue: [
					best := got.
					bestK := kk]].
			kk := kk quo: 16].
		bestK > 0 ifTrue: [
			(psLoopK at: h) = 0
				ifTrue: [
					s < 0 ifTrue: [
						s := self state: hb entryState enteredFrom: index of: h.
						ir full ifTrue: [^false]].
					d := ir newNode: O_ISUB rep: R_OOP.
					ir full ifTrue: [^false].
					(ir node: d) a: limit.
					(ir node: d) b: e0.
					(ir node: d) tkind: T_SMI.
					(ir node: d) state: s.
					(ir node: d) flags: (NF_GUARD bitOr: NF_HOISTED).
					(ir node: d) bcact: (ir node: psCCond) bcact.
					(ir node: d) bcpc: (ir node: psCCond) bcpc.
					ir insert: d before: (ir block: entry) last.
					g := self constantInt: bestK in: entry.
					self rangeGuard: d atMost: g for: psCCond in: entry state: s.
					ir full ifTrue: [^false].
					psLoopConst at: h put: g]
				ifFalse: [
					g := psLoopConst at: h.
					(ir node: g) aux: (self intOop: bestK) asInt64.
					(ir node: g) lo: bestK.
					(ir node: g) hi: bestK].
			psLoopK at: h put: bestK.
			tk := self trips: t0 within: bestK step: c]].
	self evaluateLoop: h index: index trips: tk counter: counter.
	changed := false.
	0 to: psTCount - 1 do: [:j |
		nd := ir node: (psTPhi at: j).
		(psTLo at: j) > nd lo ifTrue: [
			nd lo: (psTLo at: j).
			changed := true].
		(psTHi at: j) < nd hi ifTrue: [
			nd hi: (psTHi at: j).
			changed := true]].
	^changed
!
evaluateLoop: h index: index trips: t counter: counter
	"psTLo, psTHi := the ranges of loop h's phis (psTPhi; rangesOfLoop:) if the loop goes around at most t times from where it is entered (-1: not known), over two sweeps (a phi may rest on one after it); answer how many are within half the SmallIntegers' range."
	<function>
	| n nd lo hi elo ehi l2 h2 good |
	0 to: psTCount - 1 do: [:j |
		psTLo at: j put: (ir node: (psTPhi at: j)) lo.
		psTHi at: j put: (ir node: (psTPhi at: j)) hi].
	1 to: 2 do: [:sweep |
		0 to: psTCount - 1 do: [:j |
			n := psTPhi at: j.
			nd := ir node: n.
			lo := VM_INT_MAX.
			hi := VM_INT_MIN.
			0 to: nd nargs asInt32 - 1 do: [:k |
				self rangeOf: (ir operand: nd args + k) loop: h depth: 0.
				lo := lo min: psRLo.
				hi := hi max: psRHi].
			(index >= 0 and: [nd nargs asInt32 = 2]) ifTrue: [
				self rangeOf: (ir operand: nd args + index) loop: h depth: 0.
				elo := psRLo.
				ehi := psRHi.
				(self incrementOf: (ir operand: nd args + (1 - index)) phi: n loop: h depth: 0) ifTrue: [
					psILo >= 0
						ifTrue: [l2 := elo]
						ifFalse: [l2 := self add: elo times: t of: psILo].
					psIHi <= 0
						ifTrue: [h2 := ehi]
						ifFalse: [h2 := self add: ehi times: t of: psIHi].
					lo := lo max: l2.
					hi := hi min: h2].
				n = counter ifTrue: [hi := hi min: psCHi]].
			psTLo at: j put: (lo max: (psTLo at: j)).
			psTHi at: j put: (hi min: (psTHi at: j))]].
	good := 0.
	0 to: psTCount - 1 do: [:j |
		((psTLo at: j) >= -16r2000000000000000 and: [(psTHi at: j) <= 16r2000000000000000]) ifTrue: [good := good + 1]].
	^good
!
rangeOf: v loop: h depth: d
	"psRLo..psRHi := the range of value v: loop h's phis at their ranges in psTLo and psTHi (evaluateLoop:trips:counter:), and sums, differences, guards and joins in the loop worked out again from theirs (to depth 8); otherwise what forwardRanges found."
	<function>
	| n nd op lo hi alo ahi |
	n := ir resolve: v.
	nd := ir node: n.
	op := nd op asInt32.
	psRLo := nd lo.
	psRHi := nd hi.
	(nd block < 0 or: [(self block: nd block isIn: h) not]) ifTrue: [^self].
	(op = O_PHI and: [nd block = h]) ifTrue: [
		0 to: psTCount - 1 do: [:j |
			(psTPhi at: j) = n ifTrue: [
				psRLo := psTLo at: j.
				psRHi := psTHi at: j]].
		^self].
	d >= 8 ifTrue: [^self].
	(op = O_IADD or: [op = O_ISUB]) ifTrue: [
		self rangeOf: nd a loop: h depth: d + 1.
		alo := psRLo.
		ahi := psRHi.
		self rangeOf: (ir node: n) b loop: h depth: d + 1.
		op = O_IADD
			ifTrue: [
				lo := alo + psRLo.
				hi := ahi + psRHi]
			ifFalse: [
				lo := alo - psRHi.
				hi := ahi - psRLo].
		nd := ir node: n.
		(lo >= VM_INT_MIN and: [hi <= VM_INT_MAX])
			ifTrue: [
				psRLo := lo max: nd lo.
				psRHi := hi min: nd hi]
			ifFalse: [
				psRLo := nd lo.
				psRHi := nd hi].
		^self].
	(op = O_GUARDINT or: [op = O_CAST]) ifTrue: [
		self rangeOf: nd a loop: h depth: d + 1.
		nd := ir node: n.
		psRLo := psRLo max: nd lo.
		psRHi := psRHi min: nd hi.
		^self].
	op = O_PHI ifTrue: [
		lo := VM_INT_MAX.
		hi := VM_INT_MIN.
		0 to: nd nargs asInt32 - 1 do: [:k |
			self rangeOf: (ir operand: (ir node: n) args + k) loop: h depth: d + 1.
			lo := lo min: psRLo.
			hi := hi max: psRHi].
		nd := ir node: n.
		psRLo := lo max: nd lo.
		psRHi := hi min: nd hi]
!
incrementOf: v phi: p loop: h depth: d
	"Whether value v is phi p of loop h's head plus a range (psILo..psIHi) in the same turn: p itself, a sum with p plus something or a difference of that and something (rangeOf:loop:depth:), what guards it, a join in the loop of such values."
	<function>
	| n nd op lo hi |
	n := ir resolve: v.
	n = p ifTrue: [
		psILo := 0.
		psIHi := 0.
		^true].
	d >= 8 ifTrue: [^false].
	nd := ir node: n.
	op := nd op asInt32.
	(nd block < 0 or: [(self block: nd block isIn: h) not]) ifTrue: [^false].
	(op = O_GUARDINT or: [op = O_CAST]) ifTrue: [^self incrementOf: nd a phi: p loop: h depth: d + 1].
	(op = O_IADD or: [op = O_ISUB]) ifTrue: [
		(self incrementOf: nd a phi: p loop: h depth: d + 1) ifTrue: [
			lo := psILo.
			hi := psIHi.
			self rangeOf: (ir node: n) b loop: h depth: 0.
			op = O_IADD ifTrue: [^self increment: lo + psRLo to: hi + psRHi].
			^self increment: lo - psRHi to: hi - psRLo].
		(op = O_IADD and: [self incrementOf: (ir node: n) b phi: p loop: h depth: d + 1]) ifTrue: [
			lo := psILo.
			hi := psIHi.
			self rangeOf: (ir node: n) a loop: h depth: 0.
			^self increment: lo + psRLo to: hi + psRHi].
		^false].
	(op = O_PHI and: [nd block ~= h]) ifTrue: [
		lo := VM_INT_MAX.
		hi := VM_INT_MIN.
		0 to: nd nargs asInt32 - 1 do: [:k |
			(self incrementOf: (ir operand: (ir node: n) args + k) phi: p loop: h depth: d + 1) ifFalse: [^false].
			lo := lo min: psILo.
			hi := hi max: psIHi].
		^self increment: lo to: hi].
	^false
!
increment: lo to: hi
	"psILo..psIHi := lo..hi if that is within the SmallIntegers' range."
	(lo >= VM_INT_MIN and: [hi <= VM_INT_MAX]) ifFalse: [^false].
	psILo := lo.
	psIHi := hi.
	^true
!
add: a times: t of: c
	"a + t * c, or the end of the SmallIntegers' range it would pass (t < 0: not known)."
	<function>
	<returns: 'int64_t'>
	<var: #a type: 'int64_t'>
	<var: #t type: 'int64_t'>
	<var: #c type: 'int64_t'>
	(t = 0 or: [c = 0]) ifTrue: [^a].
	c > 0
		ifTrue: [(t < 0 or: [c > ((VM_INT_MAX - a) quo: t)]) ifTrue: [^VM_INT_MAX]]
		ifFalse: [(t < 0 or: [c negated > ((a - VM_INT_MIN) quo: t)]) ifTrue: [^VM_INT_MIN]].
	^a + (t * c)
!
trips: t within: k step: c
	"The most turns of a loop that turns at most t times (-1: not known) whose counter's limit less its start is at most k, counting by c."
	| x |
	x := (k quo: c) + 1.
	(t >= 0 and: [t < x]) ifTrue: [^t].
	^x
!
counterOf: h index: index
	"Loop h's counter, entered from predecessor index: a phi of SmallIntegers that each turn adds a constant c > 0 to (psCStep), tested at the head, below or at most a limit from before the loop (psCLimit; psCHead true), going on into the loop when it is, or on the way back, its next value below or at most the limit, going around when it is (boundsOutOf:entry:index:); psCCond the comparison. -1 if there is none."
	<function>
	| hb br cond phi e c prev steps n nd |
	hb := ir block: h.
	(hb last >= 0 and: [hb succ1 >= 0 and: [(self block: hb succ0 isIn: h) and: [(self block: hb succ1 isIn: h) not]]]) ifTrue: [
		br := ir node: hb last.
		br op asInt32 = O_BRANCH ifTrue: [
			cond := ir node: (ir resolve: br a).
			(cond op asInt32 = O_ICMP and: [cond aux = 2 or: [cond aux = 4]]) ifTrue: [
				phi := self intValueOf: cond a.
				((ir node: phi) block = h and: [(self isCounter: phi index: index) and: [self isLimit: (ir resolve: cond b) of: h]]) ifTrue: [
					psCHead := true.
					psCLimit := ir resolve: cond b.
					psCCond := ir resolve: br a.
					^phi]]]].
	e := hb preds.
	index = 0 ifTrue: [e := (ir edge: e) next].
	c := (ir edge: e) from.
	prev := h.
	steps := 0.
	[(ir block: c) succ1 < 0 and: [(ir block: c) npreds = 1 and: [steps < 4]]] whileTrue: [
		prev := c.
		c := (ir edge: (ir block: c) preds) from.
		steps := steps + 1].
	((ir block: c) succ1 >= 0 and: [(ir block: c) succ0 = prev and: [(ir block: c) last >= 0]]) ifFalse: [^-1].
	br := ir node: (ir block: c) last.
	br op asInt32 = O_BRANCH ifFalse: [^-1].
	cond := ir node: (ir resolve: br a).
	(cond op asInt32 = O_ICMP and: [cond aux = 2 or: [cond aux = 4]]) ifFalse: [^-1].
	(self isLimit: (ir resolve: cond b) of: h) ifFalse: [^-1].
	n := hb first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		(nd fwd < 0 and: [nd nargs asInt32 = 2 and: [(ir resolve: (ir operand: nd args + (1 - index))) = (ir resolve: (ir node: (ir resolve: br a)) a) and: [self isCounter: n index: index]]]) ifTrue: [
			psCHead := false.
			psCLimit := ir resolve: (ir node: (ir resolve: br a)) b.
			psCCond := ir resolve: br a.
			^n].
		n := (ir node: n) next].
	^-1
!
isCounter: phi index: index
	"phi is a phi of SmallIntegers whose value around the loop (not from predecessor index) is itself plus a constant from 1 to 2^20 (psCStep)."
	| nd back c |
	nd := ir node: phi.
	(nd op asInt32 = O_PHI and: [nd nargs asInt32 = 2 and: [nd tkind asInt32 = T_SMI]]) ifFalse: [^false].
	back := ir node: (ir resolve: (ir operand: nd args + (1 - index))).
	(back op asInt32 = O_IADD and: [(self intValueOf: back a) = phi]) ifFalse: [^false].
	c := ir node: (ir resolve: back b).
	(c op asInt32 = O_CONST and: [(c aux bitAnd: 1) = 1 and: [c aux >= 3 and: [c aux < 16r200000]]]) ifFalse: [^false].
	psCStep := self intVal: c aux.
	^true
!
isLimit: v of: h
	"v is a SmallInteger from before loop h."
	| nd |
	nd := ir node: v.
	nd tkind asInt32 = T_SMI ifFalse: [^false].
	nd op asInt32 = O_CONST ifTrue: [^true].
	^nd block >= 0 and: [(self block: nd block isIn: h) not]
!
rangeGuard: a atMost: b for: m in: entry state: s
	"guard:atMost:for:in:state:, for ranges of a loop's sums (rangesOfLoop:): its listing says so."
	self guard: a atMost: b for: m in: entry state: s.
	ir full ifFalse: [(ir node: (ir node: (ir block: entry) last) prev) aux2: 2]
!
isMarked: m
	"A guard moved out of a loop has failed at node m's send."
	^((ir flagsAtAct: (ir node: m) bcact pc: (ir node: m) bcpc) bitAnd: feedback deoptHoisted) ~= 0
!
constantInt: k in: entry
	"A constant SmallInteger k, at the end of block entry."
	<function>
	| n nd |
	n := ir newNode: O_CONST rep: R_OOP.
	ir full ifTrue: [^n].
	nd := ir node: n.
	nd aux: (self intOop: k) asInt64.
	nd flags: NF_PURE.
	nd tkind: T_SMI.
	nd lo: k.
	nd hi: k.
	ir insert: n before: (ir block: entry) last.
	^n
!
pollsAtHeads
	"A loop with one edge in and one around, whose way around holds its interrupt check and nothing else, checks at its head instead (after its phis, at the head's frame state: the frame as a turn starts), so that the way around is only a jump, which the branch before it takes past it to the head when it moves nothing (OptCodegen>>jumpTargetOf:): a bottom-tested loop ends in one compare and branch."
	<function>
	| h hb e p latch lb m f |
	0 to: psOrderCount - 1 do: [:i |
		h := psOrder at: i.
		hb := ir block: h.
		((hb flags bitAnd: BF_LOOP) ~= 0 and: [hb npreds = 2 and: [hb entryState >= 0]]) ifTrue: [
			latch := -1.
			e := hb preds.
			[e >= 0] whileTrue: [
				p := (ir edge: e) from.
				(ir block: p) rpo >= hb rpo ifTrue: [latch := p].
				e := (ir edge: e) next].
			"a loop of one block checks where it is already"
			(latch >= 0 and: [latch ~= h]) ifTrue: [
				lb := ir block: latch.
				m := lb first.
				(m >= 0 and: [(ir node: m) op asInt32 = O_CHECKINT and: [(ir node: m) next = lb last and: [(ir node: lb last) op asInt32 = O_GOTO]]]) ifTrue: [
					f := hb first.
					[f >= 0 and: [(ir node: f) op asInt32 = O_PHI]] whileTrue: [f := (ir node: f) next].
					f >= 0 ifTrue: [
						ir unlink: m.
						ir insert: m before: f.
						(ir node: m) state: hb entryState]]]]]
!
allBefore: n
	"Every operand of phi n comes from a block before its own in order (none from a loop's back edge)."
	| b e |
	b := (ir node: n) block.
	e := (ir block: b) preds.
	[e >= 0] whileTrue: [
		(ir block: (ir edge: e) from) rpo >= (ir block: b) rpo ifTrue: [^false].
		e := (ir edge: e) next].
	^true
!
forwardRanges
	"Integer ranges (lo..hi; a Character's are its code point's), forward in order: a byte or a Character loaded from bytes or a string is 0 to 255, a Character's code point 0 to 16r10FFFF, a size 0 to 2^35 (2^32 slots); sums and differences of ranges, bitAnd: with a non-negative value, \\ by a positive constant, the joins of ranges where branches meet (a loop's head's phis: rangesOfLoop:), and what guards and casts pass on. What is known in range checks nothing (NF_INRANGE; its frame state dropped): a sum or difference that stays a SmallInteger, the Character of a code point, a store of a byte or of a Character below 256 into bytes or a string."
	<function>
	| n nd op x y lo hi |
	0 to: psOrderCount - 1 do: [:i |
		n := (ir block: (psOrder at: i)) first.
		[n >= 0] whileTrue: [
			nd := ir node: n.
			op := nd op asInt32.
			op = O_SIZE ifTrue: [
				nd lo: -8.
				nd aux = E_PTR ifTrue: [nd hi: 16rFFFFFFFF] ifFalse: [nd hi: 16r800000000]].
			(op = O_PHI and: [((ir block: nd block) flags bitAnd: BF_LOOP) = 0 and: [self allBefore: n]]) ifTrue: [
				lo := VM_INT_MAX.
				hi := VM_INT_MIN.
				0 to: nd nargs asInt32 - 1 do: [:k |
					x := ir node: (ir resolve: (ir operand: nd args + k)).
					lo := lo min: x lo.
					hi := hi max: x hi].
				nd lo: (nd lo max: lo).
				nd hi: (nd hi min: hi)].
			(op = O_INDEXLOAD and: [nd aux ~= E_PTR]) ifTrue: [
				nd lo: (self lowestOf: nd aux asInt32).
				nd hi: (self highestOf: nd aux asInt32)].
			(op = O_CAST or: [op = O_GUARDINT or: [op = O_GUARDCLASS]]) ifTrue: [
				x := ir node: (ir resolve: nd a).
				nd lo: (nd lo max: x lo).
				nd hi: (nd hi min: x hi)].
			op = O_CHARCONV ifTrue: [
				x := ir node: (ir resolve: nd a).
				(nd aux ~= 0 and: [x lo >= 0 and: [x hi <= CHAR_VALUE_MAX]]) ifTrue: [self inRange: nd].
				nd lo: (x lo max: 0).
				nd hi: (x hi min: CHAR_VALUE_MAX)].
			(op = O_IADD or: [op = O_ISUB]) ifTrue: [
				x := ir node: (ir resolve: nd a).
				y := ir node: (ir resolve: nd b).
				op = O_IADD
					ifTrue: [
						lo := x lo + y lo.
						hi := x hi + y hi]
					ifFalse: [
						lo := x lo - y hi.
						hi := x hi - y lo].
				(lo >= VM_INT_MIN and: [hi <= VM_INT_MAX]) ifTrue: [
					self inRange: nd.
					nd lo: lo.
					nd hi: hi]].
			op = O_IAND ifTrue: [
				x := ir node: (ir resolve: nd a).
				y := ir node: (ir resolve: nd b).
				(x lo >= 0 or: [y lo >= 0]) ifTrue: [
					nd lo: 0.
					nd hi: ((x lo >= 0 ifTrue: [x hi] ifFalse: [VM_INT_MAX]) min: (y lo >= 0 ifTrue: [y hi] ifFalse: [VM_INT_MAX]))]].
			(op = O_IMOD and: [nd aux = 0]) ifTrue: [
				y := ir node: (ir resolve: nd b).
				(y lo = y hi and: [y lo > 0]) ifTrue: [
					nd lo: 0.
					nd hi: y lo - 1]].
			(op = O_INDEXSTORE and: [nd aux ~= E_PTR]) ifTrue: [
				x := ir node: (ir resolve: nd c).
				(x tkind asInt32 = (nd aux = E_CHAR ifTrue: [T_CHAR] ifFalse: [T_SMI]) and: [x lo >= (self lowestOf: nd aux asInt32) and: [x hi <= (self highestOf: nd aux asInt32)]]) ifTrue: [
					nd flags: (nd flags bitOr: NF_INRANGE)]].
			n := nd next]]
!
lowestOf: ek
	"The least value an indexed load of element kind ek (not E_PTR) answers, a Character's code point for E_CHAR."
	<returns: 'int64_t'>
	(ek = E_I16 or: [ek = E_I16BE]) ifTrue: [^-32768].
	^0
!
highestOf: ek
	"The greatest value an indexed load of element kind ek (not E_PTR) answers, a Character's code point for E_CHAR (below 256: bytes)."
	<returns: 'int64_t'>
	(ek = E_U16 or: [ek = E_U16BE]) ifTrue: [^65535].
	(ek = E_I16 or: [ek = E_I16BE]) ifTrue: [^32767].
	(ek = E_W32 or: [ek = E_U32 or: [ek = E_U32BE]]) ifTrue: [^16rFFFFFFFF].
	^255
!
inRange: nd
	"nd (an add or subtract, the Character of a code point) cannot fail: it checks nothing."
	nd flags: (nd flags bitOr: NF_INRANGE).
	nd state: -1
!
isInvariantOuterLoad: n of: h
	"n loads an outer temp of a closure from before loop h, and no turn of the loop changes that temp: the load may run once, where the loop is entered."
	| nd b |
	nd := ir node: n.
	nd op asInt32 = O_OUTERLOAD ifFalse: [^false].
	b := (ir node: nd a) block.
	(b < 0 or: [self dominates: h block: b]) ifTrue: [^false].
	^(self loop: h changesOuterTemp: nd aux2) not
!
loop: h changesOuterTemp: i
	"A turn of loop h may store into an outer temp of index i: it has such a store, or a send (anything may run there; what else may run, at an interrupt check, runs when the code has left the unit)."
	<function>
	| b n nd op |
	0 to: psOrderCount - 1 do: [:k |
		b := psOrder at: k.
		(self block: b isIn: h) ifTrue: [
			n := (ir block: b) first.
			[n >= 0] whileTrue: [
				nd := ir node: n.
				op := nd op asInt32.
				(op = O_SEND or: [op = O_CALL or: [op = O_OUTERSTORE and: [nd aux2 = i]]]) ifTrue: [^true].
				n := nd next]]].
	^false
!
loopDepthOf: b
	"How many loops (findLoops) hold block b."
	<arch: #x86_64>
	| l d |
	d := 0.
	l := (ir block: b) loop.
	[l >= 0 and: [d < 16]] whileTrue: [
		d := d + 1.
		l := psLoopOuter at: l].
	^d
!
block: b isIn: h
	"Block b is in loop h (findLoops)."
	| l |
	l := (ir block: b) loop.
	[l >= 0] whileTrue: [
		l = h ifTrue: [^true].
		l := psLoopOuter at: l].
	^false
!
state: s enteredFrom: k of: h
	"State s at the head of loop h, and its parents, as they are where the loop is entered: h's phis are what they take from predecessor k."
	<function>
	| st n ns vals v |
	s < 0 ifTrue: [^-1].
	st := ir state: s.
	n := ir newState.
	ir full ifTrue: [^-1].
	vals := ir allocOperands: st depth + 1.
	ir full ifTrue: [^-1].
	ns := ir state: n.
	ns act: st act.
	ns pc: st pc.
	ns depth: st depth.
	ns flags: st flags.
	ns vals: vals.
	0 to: st depth do: [:i |
		v := ir operand: st vals + i.
		(v >= 0 and: [(ir node: v) op asInt32 = O_PHI and: [(ir node: v) block = h]]) ifTrue: [v := ir operand: (ir node: v) args + k].
		ir operand: vals + i put: v].
	ns parent: (self state: st parent enteredFrom: k of: h).
	^n
!
isNumbered: nd
	| op |
	op := nd op asInt32.
	nd nargs asInt32 = 0 ifFalse: [^false].
	^op = O_CONST or: [op = O_IADD or: [op = O_ISUB or: [op = O_IMUL or: [op = O_ICMP or: [op = O_IAND or: [op = O_IOR or: [op = O_EQ or: [op = O_NE
		or: [op = O_CLASSOF or: [op = O_CLASSIS or: [op = O_BOTHINT or: [op = O_FARITH or: [op = O_FCMP or: [op = O_FSQRT or: [op = O_BOXF or: [op = O_UNBOXF
		or: [op = O_GUARDINT or: [op = O_GUARDCLASS or: [op = O_GUARDCLOSURE or: [op = O_GUARDEQ or: [op = O_CAST or: [op = O_SIZE or: [op = O_LOADFIELD
		or: [op = O_IMOD or: [op = O_IDIV or: [op = O_ISHIFT or: [op = O_IXOR or: [op = O_NOTINTS or: [op = O_CHARCONV]]]]]]]]]]]]]]]]]]]]]]]]]]]]]
!
changesMemory: nd
	"A store, or a safepoint (anything may run there)."
	| op |
	op := nd op asInt32.
	^op = O_STOREFIELD or: [op = O_INDEXSTORE or: [op = O_OUTERSTORE or: [op = O_SEND or: [op = O_CALL or: [op = O_CHECKINT or: [op = O_MKARRAY]]]]]]
!
hashOf: nd
	^(((((nd op asInt64 * 31 + nd a) * 31 + nd b) * 31 + nd aux) * 31 + nd aux2) * 31 + nd tcls asInt64) asUInt64 >> 3 bitAnd: 4095
!
same: x as: y
	^x op = y op and: [x a = y a and: [x b = y b and: [x aux = y aux and: [x aux2 = y aux2 and: [x tcls = y tcls and: [x tkind = y tkind]]]]]]
!
computeOrder: entry
	"Reverse postorder from entry (iterative depth-first search); block rpo numbers, -1 if unreachable."
	<function>
	| sp b bl n post stack state |
	0 to: ir blockCount - 1 do: [:i |
		psVisitMark at: i put: 0.
		(ir block: i) rpo: -1].
	"workList holds (block, next successor to visit) pairs"
	post := 0.
	sp := 0.
	psWorkList at: 0 put: entry.
	psWorkList at: 1 put: 0.
	sp := 2.
	psVisitMark at: entry put: 1.
	[sp > 0] whileTrue: [
		b := psWorkList at: sp - 2.
		state := psWorkList at: sp - 1.
		bl := ir block: b.
		n := state = 0 ifTrue: [bl succ0] ifFalse: [state = 1 ifTrue: [bl succ1] ifFalse: [-1]].
		state < 2
			ifTrue: [
				psWorkList at: sp - 1 put: state + 1.
				(n >= 0 and: [(psVisitMark at: n) = 0]) ifTrue: [
					psVisitMark at: n put: 1.
					psWorkList at: sp put: n.
					psWorkList at: sp + 1 put: 0.
					sp := sp + 2]]
			ifFalse: [
				psOrder at: post put: b.
				post := post + 1.
				sp := sp - 2]].
	"reverse"
	0 to: (post quo: 2) - 1 do: [:i |
		b := psOrder at: i.
		psOrder at: i put: (psOrder at: post - 1 - i).
		psOrder at: post - 1 - i put: b].
	psOrderCount := post asInt32.
	0 to: post - 1 do: [:i | (ir block: (psOrder at: i)) rpo: i]
!
removeUnreachable
	"Edges from unreachable blocks go; their nodes are unlinked (phis lose the matching operands)."
	<function>
	| bl e prev k nd n idx w |
	0 to: ir blockCount - 1 do: [:b |
		bl := ir block: b.
		bl rpo >= 0 ifTrue: [
			"drop predecessor edges from unreachable blocks, and the phi operands for them"
			e := bl preds.
			prev := -1.
			idx := 0.
			w := 0.
			[e >= 0] whileTrue: [
				(ir block: (ir edge: e) from) rpo < 0
					ifTrue: [
						prev >= 0 ifTrue: [(ir edge: prev) next: (ir edge: e) next] ifFalse: [bl preds: (ir edge: e) next].
						bl npreds: bl npreds - 1]
					ifFalse: [
						n := bl first.
						[n >= 0] whileTrue: [
							nd := ir node: n.
							nd op asInt32 = O_PHI ifTrue: [ir operand: nd args + w put: (ir operand: nd args + idx)].
							n := nd next].
						w := w + 1.
						prev := e].
				idx := idx + 1.
				e := (ir edge: e) next].
			n := bl first.
			[n >= 0] whileTrue: [
				nd := ir node: n.
				nd op asInt32 = O_PHI ifTrue: [nd nargs: w asUInt16].
				n := nd next]]].
	0 to: ir blockCount - 1 do: [:b |
		bl := ir block: b.
		bl rpo < 0 ifTrue: [
			[(k := bl first) >= 0] whileTrue: [
				(ir node: k) flags: ((ir node: k) flags bitOr: NF_DEAD).
				ir unlink: k]]]
!
splitCriticalEdges
	"An edge from a block with two successors into one with several predecessors gets a block of its own (phi moves go there)."
	<function>
	| bl n s g nb |
	nb := ir blockCount.
	0 to: nb - 1 do: [:b |
		bl := ir block: b.
		(bl rpo >= 0 and: [bl succ1 >= 0]) ifTrue: [
			0 to: 1 do: [:k |
				s := k = 0 ifTrue: [(ir block: b) succ0] ifFalse: [(ir block: b) succ1].
				(ir block: s) npreds > 1 ifTrue: [
					n := ir newBlock.
					(ir block: n) act: (ir block: b) act.
					(ir block: n) flags: BF_SEALED.
					g := ir newNode: O_GOTO rep: R_NONE.
					ir append: g to: n.
					(ir block: n) succ0: s.
					ir addPred: b to: n.
					ir replacePred: b with: n in: s.
					k = 0 ifTrue: [(ir block: b) succ0: n] ifFalse: [(ir block: b) succ1: n]]]]]
!
countUses
	"uses: how many operands (and frame state values) name each node."
	<function>
	| nd st |
	0 to: ir nodeCount - 1 do: [:n | (ir node: n) uses: 0].
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		nd block >= 0 ifTrue: [
			nd a >= 0 ifTrue: [self use: nd a].
			nd b >= 0 ifTrue: [self use: nd b].
			(nd c >= 0 and: [nd op asInt32 ~= O_SEND]) ifTrue: [self use: nd c].
			0 to: nd nargs asInt32 - 1 do: [:i | self use: (ir operand: nd args + i)].
			nd state >= 0 ifTrue: [self useState: nd state]]].
	0 to: ir actCount - 1 do: [:a | (ir act: a) receiver >= 0 ifTrue: [self use: (ir act: a) receiver]]
!
use: v
	v >= 0 ifTrue: [(ir node: v) uses: (ir node: v) uses + 1]
!
useState: s
	"The values of state s and its parents."
	| st t |
	t := s.
	[t >= 0] whileTrue: [
		st := ir state: t.
		0 to: st depth do: [:i | self use: (ir operand: st vals + i)].
		t := st parent]
!
removeDead
	"Pure nodes nothing uses go (repeatedly)."
	<function>
	| changed nd |
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: ir nodeCount - 1 do: [:n |
			nd := ir node: n.
			(nd block >= 0 and: [nd uses = 0 and: [(nd flags bitAnd: NF_PURE) ~= 0 or: [nd op asInt32 = O_PHI or: [nd op asInt32 = O_LOADFIELD or: [nd op asInt32 = O_CLASSOF or: [nd op asInt32 = O_EQ or: [nd op asInt32 = O_NE or: [nd op asInt32 = O_CAST or: [nd op asInt32 = O_CLASSIS or: [nd op asInt32 = O_SIZE or: [(nd op asInt32 = O_PARAM and: [nd aux >= 0]) or: [self isFloatPure: nd]]]]]]]]]]]]) ifTrue: [
				nd a >= 0 ifTrue: [(ir node: nd a) uses: (ir node: nd a) uses - 1].
				nd b >= 0 ifTrue: [(ir node: nd b) uses: (ir node: nd b) uses - 1].
				0 to: nd nargs asInt32 - 1 do: [:i | (ir node: (ir operand: nd args + i)) uses: (ir node: (ir operand: nd args + i)) uses - 1].
				nd flags: (nd flags bitOr: NF_DEAD).
				ir unlink: n.
				changed := true]]]
!
isFloatPure: nd
	"A float operation whose result alone it is for (an unused box deoptimizes only where the interpreter would box)."
	| op |
	op := nd op asInt32.
	^op = O_BOXF or: [op = O_FCMP or: [op = O_BOTHINT or: [op = O_FSQRT or: [op = O_LOADSLOT or: [op = O_FARITH and: [nd aux ~= 9]]]]]]
! !
