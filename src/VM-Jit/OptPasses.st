OptModule subclass: #OptPasses
	instanceVariableNames: 'ir psOrder psOrderCount psVisitMark psWorkList psIdom psPre psPost psChild psSibling psHeads psChain psUnboxOff psUnboxed'
	classVariableNames: ''
	package: 'VM-Jit'!

OptPasses comment: 'Passes over the IR (OptIR) after it is built: operands resolved through replaced nodes, trivial phis removed, unreachable blocks and unused pure nodes dropped, critical edges split, the blocks ordered (reverse postorder, the order code is emitted in).'!

!OptPasses class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (psOrder 'int32_t[OPT_MAX_BLOCKS]') (psOrderCount int32_t) (psVisitMark 'uint8_t[OPT_MAX_BLOCKS]') (psWorkList 'int32_t[OPT_MAX_NODES]')
		(psIdom 'int32_t[OPT_MAX_BLOCKS]') (psPre 'int32_t[OPT_MAX_BLOCKS]') (psPost 'int32_t[OPT_MAX_BLOCKS]') (psChild 'int32_t[OPT_MAX_BLOCKS]') (psSibling 'int32_t[OPT_MAX_BLOCKS]')
		(psHeads 'int32_t[4096]') (psChain 'int32_t[OPT_MAX_NODES]') (psUnboxOff bool) (psUnboxed bool))
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
	"After building: resolve, simplify phis, split critical edges, number values, hoist guards out of loops, drop what is unreachable or unused, order the blocks."
	<function>
	self computeOrder: entry.
	self removeUnreachable.
	self simplifyPhis.
	self resolveOperands.
	self typePhis.
	self resolveOperands.
	self forwardUnboxes.
	self resolveOperands.
	psUnboxed := false.
	(psUnboxOff not and: [runtime flag: runtime unboxFlag]) ifTrue: [
		self unboxPhis.
		self resolveOperands].
	self splitCriticalEdges.
	self computeOrder: entry.
	((runtime flag: runtime gvnFlag) or: [runtime flag: runtime hoistFlag]) ifTrue: [self dominators: entry].
	(runtime flag: runtime gvnFlag) ifTrue: [
		self valueNumbers.
		self resolveOperands].
	(runtime flag: runtime hoistFlag) ifTrue: [self hoistGuards].
	self unboxStates.
	self countUses.
	self removeDead.
	self countUses
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
	"A phi of SmallIntegers (every operand one, or such a phi: a loop's counter, a running sum) is a SmallInteger, to a fixed point from all of them; guards of SmallIntegers go."
	<function>
	| changed nd v count |
	count := 0.
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_PHI and: [nd fwd < 0 and: [nd block >= 0 and: [nd tkind asInt32 = T_ANY]]]) ifTrue: [
			nd tkind: T_SMI.
			psWorkList at: count put: n.
			count := count + 1]].
	changed := true.
	[changed] whileTrue: [
		changed := false.
		0 to: count - 1 do: [:k |
			nd := ir node: (psWorkList at: k).
			nd tkind asInt32 = T_SMI ifTrue: [
				0 to: nd nargs asInt32 - 1 do: [:i |
					v := ir resolve: (ir operand: nd args + i).
					((ir node: v) tkind asInt32 = T_SMI or: [nd tkind asInt32 ~= T_SMI]) ifFalse: [
						nd tkind: T_ANY.
						changed := true]]]]].
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd op asInt32 = O_GUARDINT and: [nd fwd < 0 and: [nd block >= 0 and: [(ir node: (ir resolve: nd a)) tkind asInt32 = T_SMI]]]) ifTrue: [
			nd fwd: (ir resolve: nd a).
			ir unlink: n]]
!
unboxPhis
	"A loop's Float phi gets a twin on doubles that the loop's arithmetic reads instead of unboxing the phi every time around, so the chain stays on doubles (the boxed phi stays for all else: frame states, sends, the exit): into it flow Float constants, the doubles of boxes, the twin itself, and from a loop unit's entry the frame's value, unboxed there once (a guard). Across the loop's sends and interrupt checks the twin is in its raw home slot."
	<function>
	| hb lo hi e n nd k o u ok uses |
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
	"Global value numbering over the dominator tree: a deterministic node (arithmetic, comparisons, guards, conversions, constants) with the same operation and operands as one in a dominating position is that one; a field load only within its block with no store or safepoint between."
	<function>
	| b n nd h m md mem found |
	0 to: 4095 do: [:i | psHeads at: i put: -1].
	mem := 0.
	0 to: psOrderCount - 1 do: [:i |
		b := psOrder at: i.
		mem := mem + 1.
		n := (ir block: b) first.
		[n >= 0] whileTrue: [
			nd := ir node: n.
			nd a >= 0 ifTrue: [nd a: (ir resolve: nd a)].
			nd b >= 0 ifTrue: [nd b: (ir resolve: nd b)].
			(self changesMemory: nd) ifTrue: [mem := mem + 1].
			(self isNumbered: nd) ifTrue: [
				"loads: only since the last store or safepoint"
				nd op asInt32 = O_LOADFIELD ifTrue: [nd aux2: mem].
				h := self hashOf: nd.
				found := -1.
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
				ifFalse: [n := nd next]]]
!
hoistGuards
	"Innermost loops first: a guard that leaves a loop may leave the one around it too."
	<function>
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
				(ir node: n) state: s.
				(ir node: n) flags: ((ir node: n) flags bitOr: NF_HOISTED)].
			n := next]]
!
isHoistable: n outOf: h
	"n is a guard of a value from before loop h, and no guard moved out of a loop has failed at its site."
	| nd op b |
	nd := ir node: n.
	op := nd op asInt32.
	(op = O_GUARDCLASS or: [op = O_GUARDINT]) ifFalse: [^false].
	b := (ir node: nd a) block.
	b < 0 ifTrue: [^false].
	(self dominates: h block: b) ifTrue: [^false].
	^((feedback flagsAt: (ir act: nd bcact) method pc: nd bcpc) bitAnd: feedback deoptHoisted) = 0
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
		or: [op = O_GUARDINT or: [op = O_GUARDCLASS or: [op = O_CAST or: [op = O_SIZE or: [op = O_LOADFIELD
		or: [op = O_IMOD or: [op = O_IDIV or: [op = O_ISHIFT or: [op = O_IXOR or: [op = O_NOTINTS or: [op = O_CHARCONV]]]]]]]]]]]]]]]]]]]]]]]]]]]
!
changesMemory: nd
	"A store, or a safepoint (anything may run there)."
	| op |
	op := nd op asInt32.
	^op = O_STOREFIELD or: [op = O_INDEXSTORE or: [op = O_OUTERSTORE or: [op = O_SEND or: [op = O_CALL or: [op = O_CHECKINT]]]]]
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
