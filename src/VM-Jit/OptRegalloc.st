OptModule subclass: #OptRegalloc
	instanceVariableNames: 'ir passes builtins raLiveWords raLiveIn raLiveOut raLiveArena raSorted raSortCount raBucket raBucketNext raActive raActiveCount raFreeRegs raSafePos raSafeCall raSafeCount raSlotTop raSlotFree raSlotFreeCount raSlotBase raRawTop raRawFree raRawFreeCount raRawBase raValidSlots raMaxPos raSafeList raSafeListCount raCost'
	classVariableNames: 'RA_ARENA RA_MAX_ACTIVE RA_MAX_SAFE RA_MAX_SAFELIST RA_MAX_SLOTS RA_NREGS'
	package: 'VM-Jit'!

OptRegalloc comment: 'Register allocation for the optimizing tier (Poletto and Sarkar''s linear scan over one live interval per value). Blocks in OptPasses'' order get positions (two per node; a block''s phis at its start); block-level liveness (iterative, bit sets) gives each value the interval from its first to its last live position (a phi''s covers the ends of its predecessors, where the moves into it are; a frame state''s values at a safepoint stay live after it). Values get one of the 18 allocatable registers (x0-x13, x18, x26-x28; x18 only where code may use it, Linux and UEFI: Arm64Assembler>>hasX18; x14-x17 are the code generator''s scratch, x23-x25 hold nil, true and false for baseline code) for their whole interval, or a frame slot if none is free (the interval ending last is spilled). Values live across a safepoint (a send, an interrupt check: everything there may run Smalltalk and move objects) also get a home slot: their registers are stored there before it and reloaded after. Doubles get d16-d31 and raw slots of their own (IEEE bits, which the collector does not read), after the others and the frame''s valid slots. Constants get neither: the code generator materializes them where they are used.'!

!OptRegalloc class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (passes OptPasses) (builtins Builtins) (raLiveWords int32_t) (raLiveIn int32_t) (raLiveOut int32_t) (raLiveArena 'uint64_t[RA_ARENA]')
		(raSorted 'int32_t[OPT_MAX_NODES]') (raSortCount int32_t) (raBucket 'int32_t[OPT_MAX_NODES]') (raBucketNext 'int32_t[OPT_MAX_NODES]')
		(raActive 'int32_t[RA_MAX_ACTIVE]') (raActiveCount int32_t) (raFreeRegs 'int32_t[RA_NREGS]')
		(raSafePos 'int32_t[RA_MAX_SAFE]') (raSafeCall 'uint8_t[RA_MAX_SAFE]') (raSafeCount int32_t)
		(raSlotTop int32_t) (raSlotFree 'int32_t[RA_MAX_SLOTS]') (raSlotFreeCount int32_t) (raSlotBase int32_t) (raRawTop int32_t) (raRawFree 'int32_t[RA_MAX_SLOTS]') (raRawFreeCount int32_t) (raRawBase int32_t) (raCost 'int32_t[OPT_MAX_NODES]') (raValidSlots int32_t) (raMaxPos int32_t) (raSafeList 'int32_t[RA_MAX_SAFELIST]') (raSafeListCount int32_t))
!
initialize
	RA_ARENA := 1048576.
	RA_MAX_ACTIVE := 1024.
	RA_MAX_SAFE := 4096.
	RA_MAX_SAFELIST := 262144.
	RA_MAX_SLOTS := 1024.
	RA_NREGS := 36
! !

!OptRegalloc methodsFor: 'accessing'!
slotCount
	"Frame slots used: the outermost method's arguments, then home slots, then raw slots (rawCount of them)."
	raRawTop = 0 ifTrue: [^raSlotTop].
	^raRawBase + raRawTop
!
rawCount
	"Raw slots: the last ones of the frame."
	^raRawTop
!
regAt: i
	"Allocatable register i: x0-x13, x18, x24-x28 (x24 and x25 never free), then d16-d31 for doubles (on x86 x0-x5, x9, x21, then d2-d15: regAtX64:)."
	asm isX64 ifTrue: [^self regAtX64: i].
	i >= 20 ifTrue: [^D16 + (i - 20)].
	i = 14 ifTrue: [^X18].
	^i < 14 ifTrue: [i] ifFalse: [i + 9]
!
isValue: n
	"n has a result that lives in a register or slot (constants are rematerialized)."
	| nd |
	n < 0 ifTrue: [^false].
	nd := ir node: n.
	^nd block >= 0 and: [nd rep asInt32 ~= R_NONE and: [nd op asInt32 ~= O_CONST and: [nd op asInt32 ~= O_CLOSURE and: [nd op asInt32 ~= O_HOMESLOT and: [(nd flags bitAnd: NF_DEAD) = 0]]]]]
!
isSafepoint: n
	| op |
	op := (ir node: n) op asInt32.
	^op = O_SEND or: [op = O_CALL or: [op = O_CHECKINT or: [op = O_MKARRAY]]]
! !

!OptRegalloc methodsFor: 'allocation'!
allocate: numArgs valid: n
	"Allocate registers and slots for the ordered IR (the frame's first n slots hold values at its entry); answer whether it fit."
	<function>
	self numberPositions.
	(self liveness) ifFalse: [^false].
	(self recordSafepointLiveness) ifFalse: [^false].
	self buildIntervals.
	(self linearScan) ifFalse: [^false].
	raSlotBase := numArgs.
	raValidSlots := n.
	^self assignSlots
!
numberPositions
	"Two positions per node, a block's phis at its first position."
	<function>
	| pos b bl n nd |
	pos := 2.
	raSafeCount := 0.
	0 to: passes orderCount - 1 do: [:i |
		b := passes orderAt: i.
		bl := ir block: b.
		bl from: pos.
		n := bl first.
		[n >= 0] whileTrue: [
			nd := ir node: n.
			nd op asInt32 = O_PHI
				ifTrue: [nd pos: bl from]
				ifFalse: [
					pos := pos + 2.
					nd pos: pos.
					((self isSafepoint: n) and: [raSafeCount < RA_MAX_SAFE]) ifTrue: [
						raSafePos at: raSafeCount put: pos.
						raSafeCall at: raSafeCount put: ((nd op asInt32 = O_CHECKINT or: [nd op asInt32 = O_MKARRAY]) ifTrue: [0] ifFalse: [1]).
						raSafeCount := raSafeCount + 1]].
			nd lstart: 16r7FFFFFFF.
			nd lend: -1.
			nd reg: -1.
			nd slot: -1.
			n := nd next].
		pos := pos + 2.
		bl to: pos].
	raMaxPos := pos asInt32
!
liveness
	"liveIn/liveOut bit sets per block until nothing changes (blocks in postorder)."
	<function>
	| words changed b bl in out tmp |
	words := (ir nodeCount + 63) >> 6.
	raLiveWords := words.
	2 * ir blockCount * words + words > RA_ARENA ifTrue: [^false].
	raLiveIn := 0.
	raLiveOut := ir blockCount * words.
	libc memset: raLiveArena value: 0 size: 8 * (2 * ir blockCount * words + words) asUInt64.
	changed := true.
	[changed] whileTrue: [
		changed := false.
		passes orderCount - 1 to: 0 by: -1 do: [:i |
			b := passes orderAt: i.
			bl := ir block: b.
			out := raLiveOut + (b * words).
			tmp := 2 * ir blockCount * words.
			"out := the successors' live-in plus their phis' operands from b"
			0 to: words - 1 do: [:w | raLiveArena at: tmp + w put: 0].
			bl succ0 >= 0 ifTrue: [self addLiveInOf: bl succ0 from: b to: tmp].
			bl succ1 >= 0 ifTrue: [self addLiveInOf: bl succ1 from: b to: tmp].
			0 to: words - 1 do: [:w |
				(raLiveArena at: tmp + w) ~= (raLiveArena at: out + w) ifTrue: [
					raLiveArena at: out + w put: (raLiveArena at: tmp + w).
					changed := true]].
			"in := uses before definitions, walking back from out"
			in := raLiveIn + (b * words).
			self transfer: b out: out into: in]].
	^true
!
addLiveInOf: s from: b to: set
	"The live-in of successor s (without its phis) and the operands its phis take from b."
	| in k n nd |
	in := raLiveIn + (s * raLiveWords).
	0 to: raLiveWords - 1 do: [:w | raLiveArena at: set + w put: ((raLiveArena at: set + w) bitOr: (raLiveArena at: in + w))].
	k := self predIndexOf: b in: s.
	n := (ir block: s) first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		k >= 0 ifTrue: [self set: (ir operand: nd args + k) in: set].
		n := nd next]
!
predIndexOf: b in: s
	| e i |
	e := (ir block: s) preds.
	i := 0.
	[e >= 0] whileTrue: [
		(ir edge: e) from = b ifTrue: [^i].
		i := i + 1.
		e := (ir edge: e) next].
	^-1
!
set: v in: set
	(self isValue: v) ifTrue: [raLiveArena at: set + (v >> 6) put: ((raLiveArena at: set + (v >> 6)) bitOr: (1 asUInt64 << (v bitAnd: 63)))]
!
clear: v in: set
	raLiveArena at: set + (v >> 6) put: ((raLiveArena at: set + (v >> 6)) bitClear: (1 asUInt64 << (v bitAnd: 63)))
!
isSet: v in: set
	^((raLiveArena at: set + (v >> 6)) bitAnd: (1 asUInt64 << (v bitAnd: 63))) ~= 0
!
transfer: b out: out into: in
	"in := (out minus b's definitions) plus its uses, walking b backward; b's phis are not live-in."
	<function>
	| n nd |
	0 to: raLiveWords - 1 do: [:w | raLiveArena at: in + w put: (raLiveArena at: out + w)].
	n := (ir block: b) last.
	[n >= 0] whileTrue: [
		nd := ir node: n.
		self clear: n in: in.
		nd op asInt32 ~= O_PHI ifTrue: [self usesOf: n into: in].
		n := nd prev]
!
recordSafepointLiveness
	"For each safepoint, the values live after it (its frame state's among them): saved before it, reloaded after it."
	<function>
	| b n nd st s set sv bits v |
	raSafeListCount := 0.
	set := 2 * ir blockCount * raLiveWords.
	0 to: passes orderCount - 1 do: [:i |
		b := passes orderAt: i.
		0 to: raLiveWords - 1 do: [:w | raLiveArena at: set + w put: (raLiveArena at: raLiveOut + (b * raLiveWords) + w)].
		n := (ir block: b) last.
		[n >= 0] whileTrue: [
			nd := ir node: n.
			(self isSafepoint: n) ifTrue: [
				nd live: raSafeListCount.
				0 to: raLiveWords - 1 do: [:w |
					bits := raLiveArena at: set + w.
					[bits ~= 0] whileTrue: [
						v := w * 64 + (builtins ctz64: bits).
						(v ~= n and: [raSafeListCount < RA_MAX_SAFELIST]) ifTrue: [
							raSafeList at: raSafeListCount put: v.
							raSafeListCount := raSafeListCount + 1].
						bits := bits bitAnd: bits - 1]].
				s := nd state.
				[s >= 0] whileTrue: [
					st := ir state: s.
					0 to: st depth + 1 do: [:j |
						sv := j <= st depth ifTrue: [ir operand: st vals + j] ifFalse: [self closureOfState: st].
						((self isValue: sv) and: [(self isSet: sv in: set) not and: [raSafeListCount < RA_MAX_SAFELIST]]) ifTrue: [
							self set: sv in: set.
							raSafeList at: raSafeListCount put: sv.
							raSafeListCount := raSafeListCount + 1]].
					s := st parent].
				nd nlive: raSafeListCount - nd live].
			self clear: n in: set.
			nd op asInt32 ~= O_PHI ifTrue: [self usesOf: n into: set].
			n := nd prev]].
	^raSafeListCount < RA_MAX_SAFELIST
!
safeLiveAt: i
	^raSafeList at: i
!
closureOfState: st
	"The closure value of st's activation that deoptimization reads (not one never made, nor a block unit's: its frame's), -1 if none."
	| c |
	c := (ir act: st act) closure.
	c < 0 ifTrue: [^-1].
	(ir node: c) op asInt32 = O_PARAM ifTrue: [^-1].
	^c
!
usesOf: n into: set
	| nd s st |
	nd := ir node: n.
	nd a >= 0 ifTrue: [self set: nd a in: set].
	nd b >= 0 ifTrue: [self set: nd b in: set].
	(nd c >= 0 and: [nd op asInt32 ~= O_SEND]) ifTrue: [self set: nd c in: set].
	nd op asInt32 ~= O_PHI ifTrue: [0 to: nd nargs asInt32 - 1 do: [:i | self set: (ir operand: nd args + i) in: set]].
	s := nd state.
	[s >= 0] whileTrue: [
		st := ir state: s.
		0 to: st depth do: [:i | self set: (ir operand: st vals + i) in: set].
		self set: (self closureOfState: st) in: set.
		s := st parent]
!
is: x cheaperThan: y
	"x86: interval x costs less per position than y kept in its slot (cost:plus:), or as much and ends later."
	<arch: #x86_64>
	| cx cy lx ly |
	cx := (raCost at: x) asInt64.
	cy := (raCost at: y) asInt64.
	lx := ((ir node: x) lend - (ir node: x) lstart + 1) asInt64.
	ly := ((ir node: y) lend - (ir node: y) lstart + 1) asInt64.
	cx * ly < (cy * lx) ifTrue: [^true].
	^cx * ly = (cy * lx) and: [(ir node: x) lend > (ir node: y) lend]
!
cost: v plus: w
	"x86: v costs w more kept in its slot."
	<arch: #x86_64>
	(self isValue: v) ifTrue: [raCost at: v put: (raCost at: v) + w]
!
extend: v to: pos
	| nd |
	(self isValue: v) ifFalse: [^self].
	nd := ir node: v.
	pos < nd lstart ifTrue: [nd lstart: pos].
	pos > nd lend ifTrue: [nd lend: pos]
!
buildIntervals
	<function>
	| b bl in out n nd k e p s st after bits weight depth |
	"x86: what keeping a value in its slot costs, for linearScan: its definition and uses, 8 times for each loop around them (a frame state's uses cost nothing)"
	asm isX64 ifTrue: [0 to: ir nodeCount - 1 do: [:i | raCost at: i put: 0]].
	0 to: passes orderCount - 1 do: [:i |
		b := passes orderAt: i.
		bl := ir block: b.
		in := raLiveIn + (b * raLiveWords).
		out := raLiveOut + (b * raLiveWords).
		0 to: raLiveWords - 1 do: [:w |
			bits := raLiveArena at: in + w.
			[bits ~= 0] whileTrue: [
				self extend: w * 64 + (builtins ctz64: bits) to: bl from.
				bits := bits bitAnd: bits - 1].
			bits := raLiveArena at: out + w.
			[bits ~= 0] whileTrue: [
				self extend: w * 64 + (builtins ctz64: bits) to: bl to.
				bits := bits bitAnd: bits - 1]].
		asm isX64 ifTrue: [
			depth := passes loopDepthOf: b.
			weight := 1 << (3 * (depth min: 3))].
		n := bl first.
		[n >= 0] whileTrue: [
			nd := ir node: n.
			self extend: n to: nd pos.
			asm isX64 ifTrue: [self cost: n plus: weight].
			nd op asInt32 = O_PHI
				ifTrue: [
					"the moves into a phi are at the ends of its predecessors"
					e := bl preds.
					k := 0.
					[e >= 0] whileTrue: [
						p := ir block: (ir edge: e) from.
						self extend: n to: p to - 1.
						self extend: (ir operand: nd args + k) to: p to - 1.
						asm isX64 ifTrue: [
							depth := passes loopDepthOf: (ir edge: e) from.
							self cost: (ir operand: nd args + k) plus: 1 << (3 * (depth min: 3))].
						k := k + 1.
						e := (ir edge: e) next]]
				ifFalse: [
					nd a >= 0 ifTrue: [self extend: nd a to: nd pos].
					nd b >= 0 ifTrue: [self extend: nd b to: nd pos].
					(nd c >= 0 and: [nd op asInt32 ~= O_SEND]) ifTrue: [self extend: nd c to: nd pos].
					0 to: nd nargs asInt32 - 1 do: [:j | self extend: (ir operand: nd args + j) to: nd pos].
					asm isX64 ifTrue: [
						nd a >= 0 ifTrue: [self cost: nd a plus: weight].
						nd b >= 0 ifTrue: [self cost: nd b plus: weight].
						(nd c >= 0 and: [nd op asInt32 ~= O_SEND]) ifTrue: [self cost: nd c plus: weight].
						0 to: nd nargs asInt32 - 1 do: [:j | self cost: (ir operand: nd args + j) plus: weight]].
					"a safepoint's state is read while it runs: its values outlive it"
					after := (self isSafepoint: n) ifTrue: [nd pos + 1] ifFalse: [nd pos].
					s := nd state.
					[s >= 0] whileTrue: [
						st := ir state: s.
						0 to: st depth do: [:j | self extend: (ir operand: st vals + j) to: after].
						self extend: (self closureOfState: st) to: after.
						s := st parent]].
			n := nd next]]
!
linearScan
	"Registers in order of interval start; spill the interval that ends last when none is free."
	<function>
	| v nd j r victim far lo hi dbl best |
	self sortIntervals.
	raActiveCount := 0.
	0 to: RA_NREGS - 1 do: [:i | raFreeRegs at: i put: 1].
	"x24-x25: true and false, for the baseline code it calls and returns to (x23, nil, has no index); x18 where code may not use it (macOS)"
	15 to: 16 do: [:i | raFreeRegs at: i put: 0].
	asm hasX18 ifFalse: [raFreeRegs at: 14 put: 0].
	"x86: 8 general registers, 14 d registers (regAtX64:)"
	asm isX64 ifTrue: [
		8 to: 19 do: [:i | raFreeRegs at: i put: 0].
		34 to: RA_NREGS - 1 do: [:i | raFreeRegs at: i put: 0]].
	0 to: raSortCount - 1 do: [:i |
		v := raSorted at: i.
		nd := ir node: v.
		"expire"
		j := 0.
		[j < raActiveCount] whileTrue: [
			(ir node: (raActive at: j)) lend < nd lstart
				ifTrue: [
					raFreeRegs at: (self regIndexOf: (ir node: (raActive at: j)) reg asInt32) put: 1.
					raActiveCount := raActiveCount - 1.
					raActive at: j put: (raActive at: raActiveCount)]
				ifFalse: [j := j + 1]].
		"doubles: d16-d31, spilled as the others are (to raw slots)"
		dbl := nd rep asInt32 = R_DBL.
		lo := dbl ifTrue: [20] ifFalse: [0].
		hi := dbl ifTrue: [RA_NREGS - 1] ifFalse: [19].
		r := -1.
		lo to: hi do: [:k | (r < 0 and: [(raFreeRegs at: k) = 1]) ifTrue: [r := k]].
		r >= 0
			ifTrue: [
				raFreeRegs at: r put: 0.
				nd reg: (self regAt: r) asInt16.
				raActiveCount >= RA_MAX_ACTIVE ifTrue: [^false].
				raActive at: raActiveCount put: v.
				raActiveCount := raActiveCount + 1]
			ifFalse: [
				victim := -1.
				far := nd lend.
				asm isX64
					ifTrue: [
						"x86, few registers: the one that costs least per position it is live kept in its slot (cost:plus:), at a tie the one ending last; maybe this one"
						best := v.
						0 to: raActiveCount - 1 do: [:k |
							((ir node: (raActive at: k)) rep = nd rep and: [self is: (raActive at: k) cheaperThan: best]) ifTrue: [
								best := raActive at: k.
								victim := k]]]
					ifFalse: [
						0 to: raActiveCount - 1 do: [:k |
							((ir node: (raActive at: k)) lend > far and: [(ir node: (raActive at: k)) rep = nd rep]) ifTrue: [
								far := (ir node: (raActive at: k)) lend.
								victim := k]]].
				victim >= 0
					ifTrue: [
						nd reg: (ir node: (raActive at: victim)) reg.
						(ir node: (raActive at: victim)) reg: -1.
						raActive at: victim put: v]
					ifFalse: [nd reg: -1]]].
	^true
!
regAtX64: i
	"x86: x0-x5 (rdi rsi rdx rcx r8 r9), x9 (rax), x21 (r13: optimized code does not keep the receiver there), then d2-d15; the others have no x86 register or are the code generator's (x10, x11, x16, x17)."
	<arch: #x86_64>
	i >= 20 ifTrue: [^D2 + (i - 20)].
	i < 6 ifTrue: [^i].
	^i = 6 ifTrue: [X9] ifFalse: [X21]
!
regIndexOf: reg
	asm isX64 ifTrue: [
		reg >= D0 ifTrue: [^reg - D2 + 20].
		reg < 6 ifTrue: [^reg].
		^reg = X9 ifTrue: [6] ifFalse: [7]].
	reg >= D0 ifTrue: [^reg - D16 + 20].
	reg = X18 ifTrue: [^14].
	^reg < 14 ifTrue: [reg] ifFalse: [reg - 9]
!
sortIntervals
	"sorted: the values by interval start (bucketed by position)."
	| v p nd |
	0 to: raMaxPos do: [:i | raBucket at: i put: -1].
	ir nodeCount - 1 to: 0 by: -1 do: [:n |
		((self isValue: n) and: [(ir node: n) lend >= 0]) ifTrue: [
			p := (ir node: n) lstart.
			raBucketNext at: n put: (raBucket at: p).
			raBucket at: p put: n]].
	raSortCount := 0.
	0 to: raMaxPos do: [:i |
		v := raBucket at: i.
		[v >= 0] whileTrue: [
			raSorted at: raSortCount put: v.
			raSortCount := raSortCount + 1.
			v := raBucketNext at: v]]
!
isGuard: nd
	"Its result is its operand."
	| op |
	op := nd op asInt32.
	^op = O_GUARDCLASS or: [op = O_GUARDINT or: [op = O_GUARDCLOSURE or: [op = O_CAST]]]
!
shareSlotOf: v
	"v's input already holds v in its home slot (unless it is a phi's, written on every edge, or lazy, written only on slow paths): v's too, kept until the later of their ends."
	| nd input owner |
	nd := ir node: v.
	input := ir node: nd a.
	(input slot >= 0 and: [input op asInt32 ~= O_PHI and: [(input flags bitAnd: NF_LAZY) = 0]]) ifFalse: [^self].
	nd slot: input slot.
	nd flags: (nd flags bitOr: NF_LAZY).
	0 to: raActiveCount - 1 do: [:j |
		owner := ir node: (raActive at: j).
		(owner slot = nd slot and: [owner lend < nd lend and: [owner rep = nd rep]]) ifTrue: [raActive at: j put: v]]
!
crossesSafepoint: v
	"v is live after a safepoint inside its interval."
	| nd |
	nd := ir node: v.
	0 to: raSafeCount - 1 do: [:i | ((raSafePos at: i) >= nd lstart and: [(raSafePos at: i) < nd lend]) ifTrue: [^true]].
	^false
!
crossesCall: v
	"v is live after a send or call inside its interval (a safepoint that is not an interrupt check)."
	| nd |
	nd := ir node: v.
	0 to: raSafeCount - 1 do: [:i | ((raSafeCall at: i) ~= 0 and: [(raSafePos at: i) >= nd lstart and: [(raSafePos at: i) < nd lend]]) ifTrue: [^true]].
	^false
!
assignSlots
	"Home slots for spilled values and values live across safepoints, reused when intervals no longer overlap; doubles' are raw slots, numbered apart, after the others and the frame's valid slots."
	<function>
	| v nd j |
	raSlotTop := raSlotBase.
	raSlotFreeCount := 0.
	raRawTop := 0.
	raRawFreeCount := 0.
	raActiveCount := 0.
	0 to: raSortCount - 1 do: [:i |
		v := raSorted at: i.
		nd := ir node: v.
		"an argument (a unit's parameter) lives in its own slot, which the code never writes"
		((nd reg < 0 or: [self crossesSafepoint: v]) and: [nd op asInt32 = O_PARAM and: [nd aux >= 0]]) ifTrue: [nd slot: nd aux asInt16].
		"a guard's result is its input: in the same slot, if the input is in one"
		((nd reg < 0 or: [self crossesSafepoint: v]) and: [nd slot < 0 and: [self isGuard: nd]]) ifTrue: [self shareSlotOf: v].
		((nd reg < 0 or: [self crossesSafepoint: v]) and: [nd slot < 0]) ifTrue: [
			j := 0.
			[j < raActiveCount] whileTrue: [
				(ir node: (raActive at: j)) lend < nd lstart
					ifTrue: [
						(ir node: (raActive at: j)) rep asInt32 = R_DBL
							ifTrue: [
								raRawFree at: raRawFreeCount put: (ir node: (raActive at: j)) slot asInt32.
								raRawFreeCount := raRawFreeCount + 1]
							ifFalse: [
								raSlotFree at: raSlotFreeCount put: (ir node: (raActive at: j)) slot asInt32.
								raSlotFreeCount := raSlotFreeCount + 1].
						raActiveCount := raActiveCount - 1.
						raActive at: j put: (raActive at: raActiveCount)]
					ifFalse: [j := j + 1]].
			nd rep asInt32 = R_DBL
				ifTrue: [
					raRawFreeCount > 0
						ifTrue: [
							raRawFreeCount := raRawFreeCount - 1.
							nd slot: (raRawFree at: raRawFreeCount) asInt16]
						ifFalse: [
							raRawTop >= RA_MAX_SLOTS ifTrue: [^false].
							nd slot: raRawTop asInt16.
							raRawTop := raRawTop + 1]]
				ifFalse: [
					raSlotFreeCount > 0
						ifTrue: [
							raSlotFreeCount := raSlotFreeCount - 1.
							nd slot: (raSlotFree at: raSlotFreeCount) asInt16]
						ifFalse: [
							raSlotTop >= RA_MAX_SLOTS ifTrue: [^false].
							nd slot: raSlotTop asInt16.
							raSlotTop := raSlotTop + 1]].
			raActiveCount >= RA_MAX_ACTIVE ifTrue: [^false].
			raActive at: raActiveCount put: v.
			raActiveCount := raActiveCount + 1.
			"only interrupt checks need it in its slot: their slow path stores it"
			(nd reg >= 0 and: [(self crossesCall: v) not]) ifTrue: [nd flags: (nd flags bitOr: NF_LAZY)]]].
	"the raw slots: after the others"
	raRawBase := raSlotTop max: raValidSlots.
	raRawBase + raRawTop > RA_MAX_SLOTS ifTrue: [^false].
	0 to: raSortCount - 1 do: [:i |
		nd := ir node: (raSorted at: i).
		(nd rep asInt32 = R_DBL and: [nd slot >= 0]) ifTrue: [nd slot: (nd slot + raRawBase) asInt16]].
	^true
! !
