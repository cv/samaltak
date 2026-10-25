OptModule subclass: #OptPasses
	instanceVariableNames: 'ir psOrder psOrderCount psVisitMark psWorkList psIdom psPre psPost psChild psSibling psHeads psChain'
	classVariableNames: ''
	package: 'VM-Jit'!

OptPasses comment: 'Passes over the IR (OptIR) after it is built: operands resolved through replaced nodes, trivial phis removed, unreachable blocks and unused pure nodes dropped, critical edges split, the blocks ordered (reverse postorder, the order code is emitted in).'!

!OptPasses class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (psOrder 'int32_t[OPT_MAX_BLOCKS]') (psOrderCount int32_t) (psVisitMark 'uint8_t[OPT_MAX_BLOCKS]') (psWorkList 'int32_t[OPT_MAX_NODES]')
		(psIdom 'int32_t[OPT_MAX_BLOCKS]') (psPre 'int32_t[OPT_MAX_BLOCKS]') (psPost 'int32_t[OPT_MAX_BLOCKS]') (psChild 'int32_t[OPT_MAX_BLOCKS]') (psSibling 'int32_t[OPT_MAX_BLOCKS]')
		(psHeads 'int32_t[4096]') (psChain 'int32_t[OPT_MAX_NODES]'))
! !

!OptPasses methodsFor: 'accessing'!
orderCount
	^psOrderCount
!
orderAt: i
	^psOrder at: i
! !

!OptPasses methodsFor: 'cleanup'!
cleanup: entry
	"After building: resolve, simplify phis, drop what is unreachable or unused, split critical edges, order the blocks."
	<c: 'void opt_cleanup(int32_t entry)'>
	self computeOrder: entry.
	self removeUnreachable.
	self simplifyPhis.
	self resolveOperands.
	(runtime flag: runtime gvnFlag) ifTrue: [
		self dominators: entry.
		self valueNumbers.
		self resolveOperands].
	self splitCriticalEdges.
	self computeOrder: entry.
	self countUses.
	self removeDead.
	self countUses
!
simplifyPhis
	"A phi whose operands are all one value (or itself) is that value; repeat until none is left."
	<c: 'void opt_simplify_phis(void)'>
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
resolveOperands
	"Every operand (fixed, variadic, of frame states) to what replaced it."
	<c: 'void opt_resolve_operands(void)'>
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
	<c: 'void opt_dominators(int32_t entry)'>
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
	<c: 'void opt_value_numbers(void)'>
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
				"loads, and doubles (they cannot live across a safepoint): only since the last store or safepoint"
				(nd op asInt32 = O_LOADFIELD or: [nd rep asInt32 = R_DBL]) ifTrue: [nd aux2: mem].
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
	<c: 'void opt_compute_order(int32_t entry)'>
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
	<c: 'void opt_remove_unreachable(void)'>
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
	<c: 'void opt_split_critical_edges(void)'>
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
	<c: 'void opt_count_uses(void)'>
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
	<c: 'void opt_remove_dead(void)'>
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
