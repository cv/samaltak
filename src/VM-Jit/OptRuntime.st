OptModule subclass: #OptRuntime
	instanceVariableNames: 'ir builder passes regalloc codegen rtDeoptVals rtDeoptCount rtActMethod rtActClosure rtActRcv rtActPc rtActDepth rtActVals rtActCount rtOptYoung rtOptYoungCount rtOptYoungOverflow rtStatOptCompiled rtStatOptFailed rtStatOptBytecodes rtStatOptUs rtStatOptBytes rtStatDeopts rtStatOptOsr rtStatInvalidations rtAll rtAllCount rtSunkAct rtSunkStart rtSunkInfo rtSunkOrder rtSunkCount rtSunkUseVal rtSunkUseId rtSunkUseCount rtWritten rtUnitStart rtUnitOsr rtUnitDepth rtUnits rtUnitCount rtFailed rtBlockCalls rtTraceSends rtStamp'
	classVariableNames: 'OPT_BLOCK_CALLS OPT_MAX_UNITS OPT_MAX_GENERATIONS OPT_MAX_DEOPTS OPT_MAX_DEOPT_ACTS OPT_MAX_DEOPT_VALS OPT_MAX_HEADERS OPT_MAX_YOUNG'
	package: 'VM-Jit'!

OptRuntime comment: 'The optimizing tier''s side of the runtime (docs/jit.md, Optimizing tier): when to optimize (tierUp:), compiling (OptBuilder, OptPasses, OptRegalloc, OptCodegen), sends from optimized code, deoptimization (a guard failed: the registers are in the JitState; after a send: everything is in slots), rebuilding an optimized frame''s activations as frames (deoptimization) or Contexts (materializeAll), resuming an optimized frame the interpreter returns into, the GC roots of optimized code (its method and oop pool).

An optimized method''s header (JitMethod, mode opt) is linked from its method''s lower-tier (baseline) header (opt; lower back); new frames of the method run the optimized code: the interpreter''s and optimized callers through the method''s cell, baseline callers through its unchecked entry (JitBaselineRuntime>>redirect:to:). Blocks and loops have units of their own (unitOf:start:osr:). The header carries the safepoint table (spTable: offset of each safepoint''s record in meta) and the records (OptCodegen>>recordState:kind:node:inSlots:).'!

!OptRuntime class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (builder OptBuilder) (passes OptPasses) (regalloc OptRegalloc) (codegen OptCodegen)
		(rtDeoptVals 'oop[OPT_MAX_DEOPT_VALS]') (rtDeoptCount int32_t)
		(rtActMethod 'oop[OPT_MAX_DEOPT_ACTS]') (rtActClosure 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActRcv 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActPc 'int32_t[OPT_MAX_DEOPT_ACTS]')
		(rtActDepth 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActVals 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActCount int32_t)
		(rtOptYoung 'JitMethod *[OPT_MAX_YOUNG]') (rtOptYoungCount int32_t) (rtOptYoungOverflow bool)
		(rtStatOptCompiled uint64_t) (rtStatOptFailed uint64_t) (rtStatOptBytecodes uint64_t) (rtStatOptUs uint64_t) (rtStatOptBytes uint64_t)
		(rtStatDeopts uint64_t) (rtStatOptOsr uint64_t) (rtStatInvalidations uint64_t)
		(rtAll 'JitMethod *[OPT_MAX_HEADERS]') (rtAllCount int32_t)
		(rtSunkAct 'int32_t[64]') (rtSunkStart 'int32_t[64]') (rtSunkInfo 'int32_t[64]') (rtSunkOrder 'int32_t[64]') (rtSunkCount int32_t)
		(rtSunkUseVal 'int32_t[OPT_MAX_DEOPT_VALS]') (rtSunkUseId 'int32_t[OPT_MAX_DEOPT_VALS]') (rtSunkUseCount int32_t) (rtWritten int32_t)
		(rtUnitStart int32_t) (rtUnitOsr int32_t) (rtUnitDepth int32_t) (rtUnits 'JitMethod *[OPT_MAX_UNITS]') (rtUnitCount int32_t) (rtFailed 'uint64_t[OPT_MAX_UNITS]') (rtBlockCalls 'uint64_t[OPT_BLOCK_CALLS]') (rtTraceSends bool) (rtStamp uint32_t))
!
initialize
	OPT_MAX_DEOPT_VALS := 8192.
	OPT_MAX_DEOPT_ACTS := 256.
	OPT_MAX_YOUNG := 1024.
	OPT_MAX_HEADERS := 16384.
	OPT_MAX_DEOPTS := 8.
	OPT_MAX_GENERATIONS := 32.
	OPT_BLOCK_CALLS := 16384.
	OPT_MAX_UNITS := 4096
! !

!OptRuntime methodsFor: 'statistics'!
statOptCompiled
	^rtStatOptCompiled
!
statOptFailed
	^rtStatOptFailed
!
statOptBytecodes
	^rtStatOptBytecodes
!
statOptUs
	^rtStatOptUs
!
statOptBytes
	^rtStatOptBytes
!
statDeopts
	^rtStatDeopts
!
statOptOsr
	^rtStatOptOsr
!
statInvalidations
	^rtStatInvalidations
!
stat: i
	"vmStats' order: optimized, bytecodes, µs, code bytes, deoptimizations, OSR entries, invalidations, failures."
	i = 0 ifTrue: [^rtStatOptCompiled asInt64].
	i = 1 ifTrue: [^rtStatOptBytecodes asInt64].
	i = 2 ifTrue: [^rtStatOptUs asInt64].
	i = 3 ifTrue: [^rtStatOptBytes asInt64].
	i = 4 ifTrue: [^rtStatDeopts asInt64].
	i = 5 ifTrue: [^rtStatOptOsr asInt64].
	i = 6 ifTrue: [^rtStatInvalidations asInt64].
	^rtStatOptFailed asInt64
! !

!OptRuntime methodsFor: 'functions for the stubs'!
sendFunction
	^self cCoerce: (self functionPointer: #send:index:site:) to: 'uint64_t'
!
deoptFunction
	^self cCoerce: (self functionPointer: #deoptGuard:index:) to: 'uint64_t'
!
deoptReturnFunction
	^self cCoerce: (self functionPointer: #deoptReturn:index:) to: 'uint64_t'
!
stackFullFunction
	^self cCoerce: (self functionPointer: #stackFull:) to: 'uint64_t'
!
returnFunction
	^self cCoerce: (self functionPointer: #returnBottom:index:) to: 'uint64_t'
! !

!OptRuntime methodsFor: 'headers'!
isOpt: h
	^h notNull and: [h mode = runtime optMode]
!
isAlive: h
	"An optimized header whose code may run."
	^(runtime hasCode: h) and: [(h flags bitAnd: 2) = 0]
!
optOf: h
	"The live optimized header of lower-tier header h, null if none."
	| o |
	h isNull ifTrue: [^self null].
	h opt = 0 ifTrue: [^self null].
	o := self cCoerce: h opt to: 'JitMethod *'.
	(self isAlive: o) ifFalse: [^self null].
	^o
!
recordOf: h index: k
	^h meta + (h spTable at: k)
!
poolAt: i of: h
	^(self cCoerce: h codeStart + h poolOffset to: 'oop *') at: i
! !

!OptRuntime methodsFor: 'tiering'!
initialCount: m
	"The lower tier's count for m when its code is installed: entries and backward jumps before m is optimized."
	<c: 'int32_t opt_initial_count(oop m)'>
	(runtime flag: runtime eagerFlag) ifTrue: [^1].
	^(runtime optThreshold max: 1) asInt32
!
tierUp: f loop: loop
	"f's method ran out of its count at f's pc (synced), its entry or (loop ~= 0) a loop head: answer 0 to go on in the lower tier, 1 to leave, or where f continues in optimized code (at a loop head: on-stack replacement)."
	<c: 'uint64_t opt_tier_up(Frame *f, int64_t loop)'>
	<var: #o type: 'JitMethod *'>
	| m h o s k |
	m := f method.
	"the count's slot is shared by methods whose hashes meet there, and more units of m may follow (its blocks, its loops, frames resumed in the lower tier): it starts over whatever happens; failures are remembered per unit"
	runtime counterFor: m put: (self initialCount: m).
	h := runtime lookup: m.
	(runtime hasCode: h) ifFalse: [^0].
	f code = (self cCoerce: h to: 'uint64_t') ifFalse: [^0].
	s := f closure = memory nilOop ifTrue: [0] ifFalse: [(self intVal: (self loadRef: f closure at: BC_STARTPC)) asInt32].
	(s = 0 and: [h opt = 0 and: [(self failed: m start: 0 osr: 0) not]]) ifTrue: [
		(self optimize: m lower: h) isNull ifTrue: [self noteFailed: m start: 0 osr: 0]].
	k := loop = 0 ifTrue: [0] ifFalse: [f pc + 1].
	"a married frame's temps may change through its Context (blocks it made): a unit of its own keeps those in the frame"
	(k ~= 0 and: [f ctx ~= memory nilOop and: [self makesClosures: m start: s]]) ifTrue: [k := k + 16r10000].
	(s = 0 and: [k = 0])
		ifTrue: [o := self optOf: h]
		ifFalse: [
			o := self unitOf: m start: s osr: k.
			"a failed compilation leaves a header without code: not compiled again (an invalidated one is)"
			((o isNull or: [(runtime hasCode: o) and: [(self isAlive: o) not and: [o generation < OPT_MAX_GENERATIONS]]]) and: [(self failed: m start: s osr: k) not]) ifTrue: [
				o := self optimizeUnit: m start: s osr: k depth: f sp lower: h previous: o.
				o isNull ifTrue: [self noteFailed: m start: s osr: k]]].
	(o isNull or: [(self isAlive: o) not]) ifTrue: [^0].
	k ~= 0 ifTrue: [rtStatOptOsr := rtStatOptOsr + 1].
	f code: (self cCoerce: o to: 'uint64_t').
	^o start
!
makesClosures: m start: s
	"The code of m (s 0) or of its block at startpc s makes BlockClosures that may reach its frame (through outer temps, ^, thisContext)."
	| bcs pc end op closures reach |
	bcs := self methodBytecodes: m.
	end := s = 0 ifTrue: [self methodSize: m] ifFalse: [s + (((bcs at: s - 2) asInt64 << 8) bitOr: (bcs at: s - 1)) asInt32].
	pc := s.
	closures := false.
	reach := false.
	[pc < end] whileTrue: [
		op := bcs at: pc.
		op = 16r8F ifTrue: [closures := true].
		((op >= 16r8A and: [op <= 16r8C]) or: [op = 16r7C or: [op = 16r76]]) ifTrue: [reach := true].
		pc := (pc + (analysis lengthOf: op)) asInt32].
	^closures and: [reach]
!
blockCallsAddress
	"Where block call sites of optimized code (OptCodegen>>emitBlockCall:index:slow:) find the code of the closures they call: 4 words per entry (home method, startpc, frame code, entry) by home method and startpc, cleared at every GC."
	^self cCoerce: rtBlockCalls to: 'uint64_t'
!
blockCallsMask
	^(OPT_BLOCK_CALLS quo: 4) - 1
!
blockCallSlotOf: m start: s
	"The cache entry of home method m's block at startpc s (a SmallInteger)."
	^((m >> 3) bitXor: (s >> 1)) asInt64 bitAnd: (OPT_BLOCK_CALLS quo: 4) - 1
!
noteBlockCall: h index: k closure: c entry: e
	"A block call site sent value to c: its frame code and entry e, for the next time."
	| p g |
	e <= 1 ifTrue: [^self].
	g := interpreter frames + (interpreter nframes - 1).
	p := rtBlockCalls + (4 * (self blockCallSlotOf: g method start: (self loadRef: c at: BC_STARTPC))).
	p at: 0 put: g method.
	p at: 1 put: (self loadRef: c at: BC_STARTPC).
	p at: 2 put: g code.
	p at: 3 put: e
!
clearBlockCalls
	<c: 'void opt_clear_block_calls(void)'>
	libc memset: rtBlockCalls value: 0 size: 8 * OPT_BLOCK_CALLS
!
unitOf: m start: s osr: t
	"The optimized code of m's block at startpc s (0: m) entered at its start (t 0) or at loop head t - 1, alive or not; null if there is none."
	<c: 'JitMethod *opt_unit_of(oop m, int32_t s, int32_t t)'>
	| i h |
	i := self unitHash: m start: s osr: t.
	[(h := rtUnits at: i) notNull] whileTrue: [
		(h methodHash = (self hashOf: m) asUInt32 and: [h blockStart = s asUInt32 and: [h osrPc = t asUInt32 and: [h method = m or: [(self isAlive: h) not]]]]) ifTrue: [^h].
		i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	^self null
!
failedKey: m start: s osr: t
	^(((self hashOf: m) asUInt64 << 32) bitOr: ((s asUInt64 bitAnd: 16rFFFF) << 16)) bitOr: (t asUInt64 bitAnd: 16rFFFF)
!
failed: m start: s osr: t
	"Compiling this unit failed before (a hash table of keys; a collision only means it is not tried; noteFailed: probes as far)."
	| key i n |
	key := (self failedKey: m start: s osr: t) bitOr: 1 << 63.
	i := ((key bitXor: key >> 29) bitAnd: OPT_MAX_UNITS - 1) asInt32.
	n := 0.
	[(rtFailed at: i) ~= 0 and: [n < (OPT_MAX_UNITS quo: 2)]] whileTrue: [
		(rtFailed at: i) = key ifTrue: [^true].
		n := n + 1.
		i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	^false
!
noteFailed: m start: s osr: t
	| key i n |
	key := (self failedKey: m start: s osr: t) bitOr: 1 << 63.
	i := ((key bitXor: key >> 29) bitAnd: OPT_MAX_UNITS - 1) asInt32.
	n := 0.
	[(rtFailed at: i) ~= 0] whileTrue: [
		n := n + 1.
		n >= (OPT_MAX_UNITS quo: 2) ifTrue: [^self].
		i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	rtFailed at: i put: key
!
unitHash: m start: s osr: t
	^(((self hashOf: m) asUInt64 * 31 + s asUInt64) * 31 + t asUInt64) bitAnd: OPT_MAX_UNITS - 1
!
blockCodeFor: m start: s
	"Frame code of a new activation of m's block at s: its optimized code if it may run, else m's (lower tier, or counting)."
	<c: 'uint64_t opt_block_code(oop m, int32_t s)'>
	| o |
	o := self unitOf: m start: s osr: 0.
	(o notNull and: [self isAlive: o]) ifTrue: [^self cCoerce: o to: 'uint64_t'].
	^runtime blockCodeFor: m
!
optimizeUnit: m start: s osr: t depth: d lower: h previous: p
	"Compile m's block at startpc s (0: m) entered at its start (t 0) or at loop head t - 1 with d slots as a unit of its own, in place of p (invalidated) if not null; null if it could not."
	<c: 'JitMethod *opt_optimize_unit(oop m, int32_t s, int32_t t, int32_t d, JitMethod *h, JitMethod *p)'>
	| o t0 i |
	rtUnitCount >= ((OPT_MAX_UNITS quo: 4) * 3) ifTrue: [^self null].
	rtUnitStart := s.
	rtUnitOsr := t.
	rtUnitDepth := d.
	t0 := runtime nowUs.
	o := runtime compile: m mode: runtime optMode notes: runtime notes.
	rtStatOptUs := rtStatOptUs + (runtime nowUs - t0) asUInt64.
	rtUnitStart := 0.
	rtUnitOsr := 0.
	o isNull ifTrue: [^self null].
	rtAllCount < OPT_MAX_HEADERS
		ifTrue: [
			rtAll at: rtAllCount put: o.
			rtAllCount := rtAllCount + 1]
		ifFalse: [runtime requestFlush].
	cache beginWriting.
	o lower: (self cCoerce: h to: 'uint64_t').
	o blockStart: s asUInt32.
	o osrPc: t asUInt32.
	o stamp: rtStamp.
	p notNull ifTrue: [o generation: p generation + 1].
	o methodHash: (self hashOf: m) asUInt32.
	cache endWriting.
	self noteYoung: o.
	i := self unitHash: m start: s osr: t.
	[(rtUnits at: i) notNull and: [(rtUnits at: i) ~= p]] whileTrue: [i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	(rtUnits at: i) isNull ifTrue: [rtUnitCount := rtUnitCount + 1].
	rtUnits at: i put: o.
	^o
!
unitEntry
	"The pc the unit being compiled is entered at: 0 for a method, a block's startpc, a loop head."
	rtUnitOsr > 0 ifTrue: [^(rtUnitOsr bitAnd: 16rFFFF) - 1].
	^rtUnitStart
!
optimize: m lower: h
	"Compile m with the optimizer, link it to its lower-tier header h and install it; null if it could not."
	<c: 'JitMethod *opt_optimize(oop m, JitMethod *h)'>
	| o t0 |
	t0 := runtime nowUs.
	o := runtime compile: m mode: runtime optMode notes: runtime notes.
	rtStatOptUs := rtStatOptUs + (runtime nowUs - t0) asUInt64.
	o isNull ifTrue: [^self null].
	rtAllCount < OPT_MAX_HEADERS
		ifTrue: [
			rtAll at: rtAllCount put: o.
			rtAllCount := rtAllCount + 1]
		ifFalse: [runtime requestFlush].
	cache beginWriting.
	h opt: (self cCoerce: o to: 'uint64_t').
	o lower: (self cCoerce: h to: 'uint64_t').
	o stamp: rtStamp.
	cache endWriting.
	self noteYoung: o.
	(runtime hasCode: o) ifFalse: [^self null].
	interpreter setCacheCode: (self cCoerce: o to: 'uint64_t') forMethod: m.
	runtime codeChanged: m.
	^o
!
compile: m
	"Emit optimized code for m at the assembler's pc (JitRuntime>>compile:mode:notes:); answer whether it could."
	<c: 'bool opt_compile(oop m)'>
	| ok trace limit |
	trace := (libc getenv: 'SAMALTAK_OPT_TRACE') notNull.
	rtTraceSends := (libc getenv: 'SAMALTAK_OPT_SENDS') notNull.
	limit := libc getenv: 'SAMALTAK_OPT_LIMIT'.
	(limit notNull and: [rtStatOptCompiled >= (libc atol: limit) asUInt64]) ifTrue: [^false].
	trace ifTrue: [
		libc fprintf: libc stderr format: 'opt: (block %d, loop %d) ' with: rtUnitStart with: rtUnitOsr.
		interpreter printActivation: m receiver: memory nilOop closure: memory nilOop on: libc stderr].
	ok := (builder build: m start: rtUnitStart osr: (rtUnitOsr bitAnd: 16rFFFF) - 1 depth: rtUnitDepth resident: rtUnitOsr >= 16r10000) and: [
		passes cleanup: builder entryBlock.
		trace ifTrue: [ir print].
		(regalloc allocate: builder paramSlots) and: [
			trace ifTrue: [
				libc fputs: 'allocated:
' to: libc stderr.
				ir print].
			codegen generate: m act: 0]].
	"the analysis the runtime reads afterwards is m's"
	analysis analyze: m.
	ok ifFalse: [rtStatOptFailed := rtStatOptFailed + 1].
	trace ifTrue: [libc fprintf: libc stderr format: 'opt: %s
' with: (ok ifTrue: ['ok'] ifFalse: ['failed'])].
	^ok
!
extraBytes
	"What the optimized code's header needs after its notes: the safepoint table and the records."
	^4 * (codegen spCount + codegen metaCount + codegen depCount) + 8
!
writeExtra: h at: p
	"Fill the optimized header h's own fields and write its tables at p; answer the address after them."
	| q |
	h slots: codegen slotTop asUInt32.
	h bcSize: (self methodSize: h method) asUInt32.
	h poolOffset: codegen poolOffset asUInt32.
	h poolCount: codegen poolCount asUInt32.
	h spCount: codegen spCount asUInt32.
	h spTable: (self cCoerce: p to: 'int32_t *').
	0 to: codegen spCount - 1 do: [:i | h spTable at: i put: (codegen spTableAt: i)].
	q := p + (4 * codegen spCount).
	h meta: (self cCoerce: q to: 'int32_t *').
	0 to: codegen metaCount - 1 do: [:i | h meta at: i put: (codegen metaAt: i)].
	q := q + (4 * codegen metaCount).
	h depCount: codegen depCount asUInt32.
	h deps: (self cCoerce: q to: 'int32_t *').
	0 to: codegen depCount - 1 do: [:i | h deps at: i put: (codegen depAt: i)].
	rtStatOptCompiled := rtStatOptCompiled + 1.
	rtStatOptBytecodes := rtStatOptBytecodes + h bcSize asUInt64.
	rtStatOptBytes := rtStatOptBytes + h codeSize asUInt64.
	^q + (4 * codegen depCount)
!
noteYoung: o
	"o's method or a pool entry is young: scavenges visit it."
	| young |
	young := self isYoung: o method.
	0 to: o poolCount asInt64 - 1 do: [:i | ((self isPtr: (self poolAt: i of: o)) and: [self isYoung: (self poolAt: i of: o)]) ifTrue: [young := true]].
	young ifFalse: [^self].
	rtOptYoungCount < OPT_MAX_YOUNG
		ifTrue: [
			rtOptYoung at: rtOptYoungCount put: o.
			rtOptYoungCount := rtOptYoungCount + 1]
		ifFalse: [rtOptYoungOverflow := true]
! !

!OptRuntime methodsFor: 'sends'!
send: f index: k site: key
	"Optimized code sends at safepoint k of f (its pc and sp stored, receiver and arguments at slot slots): answer 0 (the result is in that slot), 1 (leave) or the callee's entry (frame pushed)."
	<c: 'uint64_t opt_send(Frame *f, int64_t k, uint64_t key)'>
	| h rec info n kind sp sel base r cls e ns ok v flushes |
	h := self cCoerce: f code to: 'JitMethod *'.
	rec := self recordOf: h index: k.
	info := rec at: 2.
	n := (info bitAnd: 255) asInt32.
	kind := (info >> 8) bitAnd: 255.
	sp := (info >> 16) bitAnd: 255.
	sel := self poolAt: (rec at: 3) of: h.
	rtTraceSends ifTrue: [
		interpreter printSymbol: sel on: libc stderr.
		libc fputs: ' in ' to: libc stderr.
		interpreter printActivation: h method receiver: memory nilOop closure: memory nilOop on: libc stderr].
	base := f fp + h slots asInt64.
	r := base at: 0.
	kind = 2 ifTrue: [
		r := runtime specialFast: sp base: base.
		r ~= 0 ifTrue: [
			base at: 0 put: r.
			^0].
		r := base at: 0.
		((sp = 21 or: [sp = 22 or: [sp = 30]]) and: [(self isPtr: r) and: [(self rawClass: r) = memory clsBlock and: [(self loadRef: r at: BC_NUMARGS) = (self intOop: n)]]]) ifTrue: [
			runtime sync: f.
			flushes := interpreter statFlushes.
			interpreter activateBlock: n.
			"no room for its frame: the frames became Contexts, the interpreter goes on"
			interpreter statFlushes ~= flushes ifTrue: [^1].
			v := runtime entryOfTop.
			self noteBlockCall: h index: k closure: r entry: v.
			^v]].
	cls := kind = 1
		ifTrue: [self loadRef: (self loadRef: (self innermostMethodOf: rec h: h) at: CM_CLASS) at: BEH_SUPERCLASS]
		ifFalse: [interpreter receiverClass: r].
	e := interpreter icacheAt: (self cCoerce: key to: 'uint8_t *').
	(e cls = cls and: [e sel = key]) ifFalse: [
		e := interpreter siteEntry: (self cCoerce: key to: 'uint8_t *') class: cls selector: sel.
		e isNull ifTrue: [^self doesNotUnderstand: sel class: cls frame: f index: k argc: n]].
	(e kind bitAnd: (runtime kConst bitOr: runtime kCtx)) = runtime kConst ifTrue: [
		e qconst ~= 0 ifTrue: [base at: 0 put: e qconst].
		^self sent: f].
	((e kind bitAnd: (runtime kQuick bitOr: runtime kCtx)) = runtime kQuick and: [n = 0 and: [(self isPtr: r) and: [r ~= interpreter activeCtx and: [(self formatOf: r) <= F_FIXVAR and: [(self numSlots: r) > e quick asUInt32]]]]]) ifTrue: [
		base at: 0 put: (self loadRef: r at: e quick).
		^self sent: f].
	((e kind bitAnd: (runtime kSetter bitOr: runtime kCtx)) = runtime kSetter and: [e nset = n and: [(self isPtr: r) and: [r ~= interpreter activeCtx and: [((self header: r) bitAnd: H_IMMUTABLE) = 0 and: [(self formatOf: r) <= F_FIXVAR]]]]]) ifTrue: [
		ns := self numSlots: r.
		ok := true.
		0 to: n - 1 do: [:j | ok := ok and: [(e setIvar at: j) < ns]].
		ok ifTrue: [
			0 to: n - 1 do: [:j | self storeRef: r at: (e setIvar at: j) put: (base at: 1 + j)].
			^self sent: f]].
	"a leaf primitive neither collects nor leaves: the frames below need not be canonical"
	((e kind bitAnd: (runtime kLeaf bitOr: runtime kCtx)) = runtime kLeaf and: [runtime callLeaf: e base: base argc: n]) ifTrue: [^self sent: f].
	runtime sync: f.
	((e kind bitAnd: runtime kCtx) ~= 0 and: [self isInt: (self loadRef: r at: CTX_SENDER)]) ifTrue: [^self leaveBefore: f index: k].
	(runtime isPerform: e) ifTrue: [^self perform: e frame: f index: k argc: n].
	runtime sendPushed: 0.
	r := runtime dispatch: e frame: f argc: n.
	"a primitive answered: a safepoint (the profiler samples an allocation there)"
	r = 0 ifTrue: [^self sent: f].
	^r
!
perform: e frame: f index: k argc: n
	"Safepoint k of f sends a perform: (entry e, n arguments): send its selector as the primitive does (Interpreter>>primResend:argc:), the arguments moved down over the selector. A send that would not complete here (the primitive fails, cannotSend:base:) leaves before the perform:, which the interpreter executes again."
	| base sel arr m g |
	base := f fp + (f sp - n - 1).
	sel := base at: 1.
	arr := n = 2 ifTrue: [base at: 2] ifFalse: [memory nilOop].
	m := (runtime isPerformWithArguments: e)
		ifTrue: [((self isPtr: arr) and: [(self rawClass: arr) = memory clsArray]) ifTrue: [(self numSlots: arr) asInt32] ifFalse: [-1]]
		ifFalse: [n - 1].
	g := (m >= 0 and: [(interpreter selectorArgc: sel) = m]) ifTrue: [interpreter entryFor: (interpreter receiverClass: (base at: 0)) selector: sel] ifFalse: [self null].
	(self cannotSend: g base: base) ifTrue: [^self leaveBefore: f index: k].
	(runtime isPerformWithArguments: e)
		ifTrue: [0 to: m - 1 do: [:i | base at: 1 + i put: (self loadRef: arr at: i)]]
		ifFalse: [libc memmove: base + 1 from: base + 2 size: m asUInt64 * 8].
	interpreter activeSetStackp: f sp - n + m.
	^self resend: g frame: f argc: m
!
doesNotUnderstand: sel class: cls frame: f index: k argc: n
	"Safepoint k of f sends sel, which cls does not understand: send doesNotUnderstand: with a Message of sel and the arguments, over them, as the interpreter does (Interpreter>>sendDoesNotUnderstand). If that would not complete here (cannotSend:base:) leave before the send."
	| base roots msg isize |
	base := f fp + (f sp - n - 1).
	(self cannotSend: (interpreter entryFor: cls selector: (memory special: SO_SEL_DNU)) base: base) ifTrue: [^self leaveBefore: f index: k].
	runtime sync: f.
	"allocating may collect: sel, cls and the Array are roots, the arguments are in slots"
	roots := self local: 'oop[3]'.
	roots at: 0 put: sel.
	roots at: 1 put: cls.
	memory pushRoot: roots.
	memory pushRoot: roots + 1.
	roots at: 2 put: (memory allocObj: memory clsArray format: F_VAR slots: n asUInt32).
	libc memcpy: (self slotsOf: (roots at: 2)) from: base + 1 size: n asUInt64 * 8.
	gc rememberIfOld: (roots at: 2).
	memory pushRoot: roots + 2.
	isize := (self intVal: (self loadRef: memory clsMessage at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	msg := memory allocObj: memory clsMessage format: F_FIXED slots: (isize < 2 ifTrue: [2] ifFalse: [isize]) asUInt32.
	memory popRoot.
	memory popRoot.
	memory popRoot.
	self storeRef: msg at: MSG_SELECTOR put: (roots at: 0).
	self storeRef: msg at: MSG_ARGS put: (roots at: 2).
	base at: 1 put: msg.
	interpreter activeSetStackp: f sp - n + 1.
	^self resend: (interpreter entryFor: (roots at: 1) selector: (memory special: SO_SEL_DNU)) frame: f argc: 1
!
cannotSend: g base: base
	"The send of g's method to the receiver at base cannot complete here: not understood (g null), perform: again, a married Context, no room for its frame."
	^g isNull or: [(runtime isPerform: g) or: [(self cCoerce: base + (1 + g fsize) to: 'uint64_t') > interpreter cstackLimit or: [
		(g kind bitAnd: runtime kCtx) ~= 0 and: [self isInt: (self loadRef: (base at: 0) at: CTX_SENDER)]]]]
!
resend: g frame: f argc: n
	"Send g's method to the receiver and n arguments on top of f (they replaced a perform:'s or a send's): answer as send:index:site:."
	| r |
	runtime sendPushed: 0.
	r := runtime dispatch: g frame: f argc: n.
	r = 0 ifTrue: [^self sent: f].
	^r
!
sent: f
	"A send completed without a frame: a safepoint, as in the interpreter."
	runtime state interrupt = 0 ifTrue: [^0 asUInt64].
	f sp: ((self cCoerce: f code to: 'JitMethod *') slots + 1) asInt32.
	^runtime interrupt: f
!
innermostMethodOf: rec h: h
	| p nacts m |
	nacts := rec at: 4.
	p := 5.
	m := memory nilOop.
	0 to: nacts - 1 do: [:j |
		m := self poolAt: (rec at: p) of: h.
		p := p + 5 + (rec at: p + 4)].
	^m
!
leave: f after: after
	"The runtime leaves to the interpreter while optimized frame f (on top) sends: before the send (it is executed again) or after it (its result pushed)."
	<c: 'uint64_t opt_leave(Frame *f, bool after)'>
	| h |
	h := self cCoerce: f code to: 'JitMethod *'.
	^self deoptFrame: f index: f pc - h bcSize asInt32 regs: self null mode: (after ifTrue: [2] ifFalse: [1])
!
leaveBefore: f index: k
	runtime sync: f.
	^self deoptFrame: f index: k regs: self null mode: 1
!
stackFull: f
	"No room for f's optimized frame at its entry: the interpreter runs it from pc 0 (f's pc and sp stored)."
	<c: 'uint64_t opt_stack_full(Frame *f)'>
	| h |
	h := self cCoerce: f code to: 'JitMethod *'.
	f code: h lower.
	^0
! !

!OptRuntime methodsFor: 'deoptimization'!
deoptGuard: f index: k
	"A guard of f's code failed at safepoint k; the registers are in the JitState's dump. Rebuild f's activations as frames; the interpreter continues the top one."
	<c: 'uint64_t opt_deopt_guard(Frame *f, int64_t k)'>
	| h why r m pc fresh stressed sig |
	runtime canonicalizeBelow: f.
	h := self cCoerce: f code to: 'JitMethod *'.
	why := ((self recordOf: h index: k) at: 0) >> 8.
	"--jit-flags deopt: no feedback from the stress"
	stressed := (runtime flag: runtime deoptFlag) and: [runtime state stress <= 0].
	stressed ifTrue: [why := 0].
	r := self deoptFrame: f index: k regs: runtime state dump mode: 0.
	"a block unit's ^ (the interpreter does it every time): the unit is not optimized again"
	((self methodBytecodes: (rtActMethod at: rtActCount - 1)) at: (rtActPc at: rtActCount - 1)) = 16r7C ifTrue: [
		(self isAlive: h) ifTrue: [
			self noteFailed: h method start: h blockStart asInt32 osr: h osrPc asInt32.
			self invalidate: h].
		^r].
	"the innermost activation's method and pc: where the guard's bytecode is; feedback it had not given: compile again now"
	(why = feedback deoptArith or: [why = feedback deoptOther]) ifTrue: [why := why bitOr: (self operandFlagsAt: (rtActMethod at: rtActCount - 1) pc: (rtActPc at: rtActCount - 1)) asInt32].
	fresh := false.
	why ~= 0 ifTrue: [
		m := rtActMethod at: rtActCount - 1.
		pc := rtActPc at: rtActCount - 1.
		sig := self signatureAt: m pc: pc.
		feedback noteFlags: m pc: pc flags: why asUInt32.
		(why bitAnd: feedback deoptClass) ~= 0 ifTrue: [self noteReceiverAt: m pc: pc].
		fresh := (self signatureAt: m pc: pc) ~= sig.
		fresh ifTrue: [
			rtStamp := rtStamp + 1.
			(feedback siteAt: m pc: pc) stamp: rtStamp].
		"in code compiled before the feedback said it: compile again now; again in code compiled with it: speculate no more here"
		(fresh not and: [self isAlive: h]) ifTrue: [
			(feedback siteAt: m pc: pc) stamp > h stamp
				ifTrue: [fresh := true]
				ifFalse: [
					why := why bitOr: feedback deoptOther asInt32.
					fresh := ((feedback flagsAt: m pc: pc) bitAnd: feedback deoptOther) = 0.
					feedback noteFlags: m pc: pc flags: why asUInt32]].
		(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
			libc fprintf: libc stderr format: 'deopt why %d fresh %d flags now %d at pc %d of ' with: why with: (fresh ifTrue: [1] ifFalse: [0]) with: (feedback flagsAt: m pc: pc) with: pc.
			interpreter printActivation: m receiver: memory nilOop closure: memory nilOop on: libc stderr]].
	stressed ifTrue: [^r].
	cache beginWriting.
	h deopts: h deopts + 1.
	cache endWriting.
	(fresh or: [h deopts > OPT_MAX_DEOPTS]) ifTrue: [self invalidate: h].
	^r
!
signatureAt: m pc: pc
	"What the site at m's pc reports: its flags and how many classes."
	| s n |
	s := feedback siteAt: m pc: pc.
	s isNull ifTrue: [^-1].
	n := 0.
	0 to: feedback classSlots - 1 do: [:i | (s classes at: i) ~= 0 ifTrue: [n := n + 1]].
	^s flags asInt64 + (n << 32)
!
noteReceiverAt: m pc: pc
	"A class guard of the send at m's pc failed: its receiver (on the rebuilt top frame) is feedback, the next type switch takes its class too."
	| p g i |
	p := (self methodBytecodes: m) + pc.
	(analysis pushesOf: p) > 0 ifTrue: [^self].
	g := interpreter frames + (interpreter nframes - 1).
	i := g sp - (analysis sendArgcOf: p) - 1.
	i >= 0 ifTrue: [
		feedback noteSend: m pc: pc class: (interpreter receiverClass: (g fp at: i)).
		(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
			libc fprintf: libc stderr format: 'deopt receiver %lld (Array %lld): ' with: (interpreter receiverClass: (g fp at: i)) with: memory clsArray.
			interpreter printClassName: (interpreter receiverClass: (g fp at: i)) on: libc stderr.
			libc fputc: 10 to: libc stderr]].
	"at: at:put: size: the lower tier takes Arrays inline, without feedback"
	((p at: 0) >= 16rB0 and: [(p at: 0) <= 16rB2]) ifTrue: [feedback noteSend: m pc: pc class: memory clsArray]
!
operandFlagsAt: m pc: pc
	"An arithmetic guard of the instruction at m's pc failed: its operands (on top of the rebuilt top frame, or the temps a superinstruction pushes) were Floats, or something neither a Float nor a SmallInteger (feedback)."
	| g p op fl |
	g := interpreter frames + (interpreter nframes - 1).
	p := (self methodBytecodes: m) + pc.
	op := p at: 0.
	(analysis pushesOf: p) > 0 ifTrue: [
		fl := self flagsOf: (g fp at: (p at: 1)).
		(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]]) ifTrue: [fl := fl bitOr: (self flagsOf: (g fp at: (p at: 2)))].
		^fl].
	fl := 0.
	g sp - 2 to: g sp - 1 do: [:i | i >= 0 ifTrue: [fl := fl bitOr: (self flagsOf: (g fp at: i))]].
	^fl
!
flagsOf: v
	((v bitAnd: 7) = 4 or: [(self isPtr: v) and: [(self rawClass: v) = memory clsBoxedfloat]]) ifTrue: [^feedback sawFloat].
	(self isInt: v) ifFalse: [^feedback sawNonInt].
	^0
!
returnBottom: f index: k
	"Frame f (the bottom frame) returns into activeCtx at safepoint k (its state: the return bytecode, the result on top; the registers in the JitState's dump), as the interpreter's returnTop does; if activeCtx is dead the interpreter does it (deoptimize)."
	<c: 'uint64_t opt_return_bottom(Frame *f, int64_t k)'>
	| h ctx sp v |
	h := self cCoerce: f code to: 'JitMethod *'.
	ctx := interpreter activeCtx.
	(self isInt: (self loadRef: ctx at: CTX_PC)) ifFalse: [^self deoptFrame: f index: k regs: runtime state dump mode: 0].
	self decode: h index: k frame: f regs: runtime state dump mode: 0.
	"return top: the stack's top; return self: the receiver"
	v := ((self methodBytecodes: (rtActMethod at: 0)) at: (rtActPc at: 0)) = 16r7A
		ifTrue: [rtDeoptVals at: (rtActRcv at: 0)]
		ifFalse: [rtDeoptVals at: rtDeoptCount - 1].
	rtDeoptCount := 0.
	f ctx ~= memory nilOop ifTrue: [
		f sp: 0.
		interpreter widow: f].
	interpreter nframes: 0.
	interpreter cstackUsed: 0.
	sp := self intVal: (self loadRef: ctx at: CTX_STACKP).
	self storeRef: ctx at: CTX_FIXED + sp put: v.
	(self slotsOf: ctx) at: CTX_STACKP put: (self intOop: sp + 1).
	gc rememberIfOld: ctx.
	^1
!
deoptReturn: f index: k
	"After the send of safepoint k (the result in slot slots): f's code was invalidated (or stress): rebuild its activations."
	<c: 'uint64_t opt_deopt_return(Frame *f, int64_t k)'>
	runtime canonicalizeBelow: f.
	^self deoptFrame: f index: k regs: self null mode: 2
!
deoptFrame: f index: k regs: regs mode: mode
	"Rebuild optimized frame f (the top frame) as the frames of its activations at safepoint k. mode 0: as recorded (a guard, an interrupt check), 1: before the send (it is executed again), 2: after it (its result pushed). Closures the code never made are made now, their outer activations' frames married. Answer 1 (leave: the interpreter continues the top frame)."
	<c: 'uint64_t opt_deopt_frame(Frame *f, int64_t k, uint64_t *regs, int32_t mode)'>
	| h fi g sunk |
	h := self cCoerce: f code to: 'JitMethod *'.
	rtStatDeopts := rtStatDeopts + 1.
	runtime resetStress.
	self decode: h index: k frame: f regs: regs mode: mode.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [self traceDeopt: h index: k mode: mode].
	fi := (f - interpreter frames) asInt32.
	self writeFrames: fi from: f fp.
	0 to: rtSunkCount - 1 do: [:j |
		sunk := rtSunkOrder at: j.
		g := interpreter frames + fi + (rtSunkAct at: sunk).
		interpreter marry: g.
		self makeSunk: sunk outer: g ctx.
		self writeFrames: fi from: (interpreter frames + fi) fp].
	rtDeoptCount := 0.
	^1
!
writeFrames: fi from: fp0
	"The activations' frames from frame fi on, the first one's slots at fp0, their values from deoptVals (married frames stay married)."
	| fp g m d cl |
	fp := fp0.
	0 to: rtActCount - 1 do: [:i |
		g := interpreter frames + (fi + i).
		m := rtActMethod at: i.
		d := rtActDepth at: i.
		i > 0 ifTrue: [fp := fp + (rtActDepth at: i - 1) + 1].
		fp at: -1 put: (rtDeoptVals at: (rtActRcv at: i)).
		0 to: d - 1 do: [:s | fp at: s put: (rtDeoptVals at: (rtActVals at: i) + s)].
		cl := (rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop].
		(i >= rtWritten and: [i > 0]) ifTrue: [g ctx: memory nilOop].
		g method: m.
		g closure: cl.
		g code: (runtime blockCodeFor: m).
		g fp: fp.
		g ip: (self methodBytecodes: m) + (rtActPc at: i).
		g pc: (rtActPc at: i).
		g lits: (self slotsOf: (self loadRef: m at: CM_LITERALS)).
		g sp: d].
	rtWritten := rtActCount.
	interpreter nframes: fi + rtActCount.
	interpreter cstackUsed: (fp + (rtActDepth at: rtActCount - 1) - interpreter cstackBase) asUInt64
!
makeSunk: s outer: ctx
	"Make the closure of sunk entry s, its outerContext ctx; every value that was it becomes it."
	<c: 'void opt_make_sunk(int32_t s, oop ctx)'>
	| r b bc isize info o |
	r := self local: 'oop'.
	r value: ctx.
	memory pushRoot: r.
	bc := memory clsBlock.
	isize := (self intVal: (self loadRef: bc at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	b := memory allocObj: bc format: F_FIXED slots: (isize < 5 ifTrue: [5] ifFalse: [isize]) asUInt32.
	memory popRoot.
	info := rtSunkInfo at: s.
	o := self slotsOf: b.
	o at: BC_OUTER put: r value.
	o at: BC_STARTPC put: (self intOop: (rtSunkStart at: s)).
	o at: BC_NUMARGS put: (self intOop: (info bitAnd: 255)).
	o at: BC_NUMTEMPS put: (self intOop: ((info >> 8) bitAnd: 255)).
	o at: BC_FRAMESIZE put: (self intOop: ((info >> 16) bitAnd: 255)).
	gc rememberIfOld: b.
	0 to: rtSunkUseCount - 1 do: [:i | (rtSunkUseId at: i) = s ifTrue: [rtDeoptVals at: (rtSunkUseVal at: i) put: b]]
!
decode: h index: k frame: f regs: regs mode: mode
	"Read safepoint k's record into the activation arrays, the values into deoptVals (GC roots), the closures never made into the sunk arrays (in the order of the activations that make them). mode 1 pushes the send's receiver and arguments (and goes back to the send), 2 its result."
	<c: 'void opt_decode(JitMethod *h, int64_t k, Frame *f, uint64_t *regs, int32_t mode)'>
	| rec p nacts d base sendPc argc op bcs ns t |
	rec := self recordOf: h index: k.
	sendPc := rec at: 1.
	argc := ((rec at: 2) bitAnd: 255) asInt32.
	nacts := rec at: 4.
	p := 5.
	rtDeoptCount := 0.
	rtSunkUseCount := 0.
	rtWritten := 0.
	rtActCount := nacts.
	0 to: nacts - 1 do: [:j |
		rtActMethod at: j put: (self poolAt: (rec at: p) of: h).
		rtActClosure at: j put: ((rec at: p + 1) < 0 ifTrue: [-1] ifFalse: [self value: (rec at: p + 1) h: h frame: f regs: regs]).
		(rec at: p + 1) = -2 ifTrue: [
			"a block unit's closure: its frame's"
			self push: f closure.
			rtActClosure at: j put: rtDeoptCount - 1].
		rtActRcv at: j put: (self value: (rec at: p + 2) h: h frame: f regs: regs).
		rtActPc at: j put: (rec at: p + 3).
		d := rec at: p + 4.
		rtActDepth at: j put: d.
		rtActVals at: j put: rtDeoptCount.
		0 to: d - 1 do: [:i | self value: (rec at: p + 5 + i) h: h frame: f regs: regs].
		p := p + 5 + d].
	ns := rec at: p.
	p := p + 1.
	rtSunkCount := ns.
	0 to: ns - 1 do: [:j |
		rtSunkAct at: j put: (rec at: p).
		rtSunkStart at: j put: (rec at: p + 1).
		rtSunkInfo at: j put: (rec at: p + 2).
		rtSunkOrder at: j put: j.
		p := p + 3].
	"outer activations' closures first"
	1 to: ns - 1 do: [:j |
		t := rtSunkOrder at: j.
		d := j - 1.
		[d >= 0 and: [(rtSunkAct at: (rtSunkOrder at: d)) > (rtSunkAct at: t)]] whileTrue: [
			rtSunkOrder at: d + 1 put: (rtSunkOrder at: d).
			d := d - 1].
		rtSunkOrder at: d + 1 put: t].
	base := f fp + h slots asInt64.
	mode = 2 ifTrue: [
		self push: (base at: 0).
		rtActDepth at: nacts - 1 put: (rtActDepth at: nacts - 1) + 1].
	mode = 1 ifTrue: [
		bcs := self methodBytecodes: (rtActMethod at: nacts - 1).
		op := bcs at: sendPc.
		((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifFalse: [
			0 to: argc do: [:i | self push: (base at: i)].
			rtActDepth at: nacts - 1 put: (rtActDepth at: nacts - 1) + argc + 1].
		rtActPc at: nacts - 1 put: sendPc]
!
traceDeopt: h index: k mode: mode
	<c: 'void opt_trace_deopt(JitMethod *h, int64_t k, int32_t mode)'>
	libc fprintf: libc stderr format: 'deopt mode %d at %lld (unit loop %d), %d activations, ' with: mode with: k with: h osrPc with: rtActCount.
	libc fprintf: libc stderr format: 'innermost pc %d depth %d: ' with: (rtActPc at: rtActCount - 1) with: (rtActDepth at: rtActCount - 1).
	interpreter printActivation: h method receiver: memory nilOop closure: memory nilOop on: libc stderr
!
push: v
	"v at the end of deoptVals (it extends the innermost activation)."
	rtDeoptCount < OPT_MAX_DEOPT_VALS ifTrue: [
		rtDeoptVals at: rtDeoptCount put: v.
		rtDeoptCount := rtDeoptCount + 1]
!
value: loc h: h frame: f regs: regs
	"Append the value at location loc to deoptVals; answer its index."
	| kind payload v |
	kind := loc bitAnd: 7.
	payload := loc asInt64 >> 3.
	v := memory nilOop.
	kind = LOC_SLOT ifTrue: [v := f fp at: payload].
	kind = LOC_REG ifTrue: [v := regs at: payload].
	kind = LOC_CONST ifTrue: [v := self poolAt: payload of: h].
	kind = LOC_SMI ifTrue: [v := self intOop: payload].
	(kind = LOC_SUNK and: [rtSunkUseCount < OPT_MAX_DEOPT_VALS]) ifTrue: [
		rtSunkUseVal at: rtSunkUseCount put: rtDeoptCount.
		rtSunkUseId at: rtSunkUseCount put: payload asInt32.
		rtSunkUseCount := rtSunkUseCount + 1].
	self push: v.
	^rtDeoptCount - 1
!
materialize: f
	"materializeAll meets optimized frame f: a Context for each of its activations (their senders chained from activeCtx), the last one activeCtx; and the closures never made."
	<c: 'void opt_materialize(Frame *f)'>
	<var: #mode type: 'int32_t'>
	| h k mode top ctx n s first sunk c |
	h := self cCoerce: f code to: 'JitMethod *'.
	k := f pc - h bcSize asInt32.
	top := f = (interpreter frames + (interpreter nframes - 1)).
	mode := 0.
	(top and: [f sp = (h slots + 1) asInt32 and: [((self recordOf: h index: k) at: 0) = SP_CALL]]) ifTrue: [mode := 2].
	self decode: h index: k frame: f regs: self null mode: mode.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'materialize top %d sp %d: ' with: (top ifTrue: [1] ifFalse: [0]) with: f sp.
		self traceDeopt: h index: k mode: mode].
	(top and: [mode = 0 and: [((self recordOf: h index: k) at: 0) = SP_CALL]]) ifTrue: [
		"a primitive is running: its receiver and arguments (up to sp: a perform: sends fewer) are on the stack, as the interpreter's"
		interpreter primBaseIndex: (rtActDepth at: rtActCount - 1).
		0 to: f sp - h slots asInt32 - 1 do: [:i | self push: ((f fp + h slots asInt64) at: i)].
		rtActDepth at: rtActCount - 1 put: rtDeoptCount - (rtActVals at: rtActCount - 1)].
	"the Contexts (kept in deoptVals), then the closures, then the Contexts' contents"
	first := rtDeoptCount.
	0 to: rtActCount - 1 do: [:i |
		n := (self frameSizeOfAct: i) + CTX_SLACK.
		n < (rtActDepth at: i) ifTrue: [n := rtActDepth at: i].
		"a married frame (a loop's unit) keeps its Context"
		(i = 0 and: [f ctx ~= memory nilOop and: [(self numSlots: f ctx) >= (CTX_FIXED + n) asUInt32]])
			ifTrue: [ctx := f ctx]
			ifFalse: [ctx := memory allocContext: n asUInt32].
		self push: ctx].
	0 to: rtSunkCount - 1 do: [:j |
		sunk := rtSunkOrder at: j.
		self makeSunk: sunk outer: (rtDeoptVals at: first + (rtSunkAct at: sunk))].
	0 to: rtActCount - 1 do: [:i |
		c := rtDeoptVals at: first + i.
		s := self slotsOf: c.
		s at: CTX_SENDER put: interpreter activeCtx.
		s at: CTX_PC put: (self intOop: (rtActPc at: i)).
		s at: CTX_STACKP put: (self intOop: (rtActDepth at: i)).
		s at: CTX_METHOD put: (rtActMethod at: i).
		s at: CTX_CLOSURE put: ((rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop]).
		s at: CTX_RECEIVER put: (rtDeoptVals at: (rtActRcv at: i)).
		0 to: (rtActDepth at: i) - 1 do: [:j | s at: CTX_FIXED + j put: (rtDeoptVals at: (rtActVals at: i) + j)].
		gc rememberIfOld: c.
		interpreter activeCtx: c].
	rtDeoptCount := 0
!
frameSizeOfAct: i
	"The frame size of decoded activation i: its closure's (made or not), else its method's."
	| c info |
	(rtActClosure at: i) < 0 ifTrue: [^self frameSizeOf: (rtActMethod at: i) closure: memory nilOop].
	0 to: rtSunkUseCount - 1 do: [:u |
		(rtSunkUseVal at: u) = (rtActClosure at: i) ifTrue: [
			info := rtSunkInfo at: (rtSunkUseId at: u).
			^((info >> 16) bitAnd: 255) max: (info bitAnd: 255) + ((info >> 8) bitAnd: 255)]].
	c := rtDeoptVals at: (rtActClosure at: i).
	^self frameSizeOf: (rtActMethod at: i) closure: c
!
frameSizeOf: m closure: c
	"frameSize of an activation of m or of block c (at least its arguments and temps), as Interpreter>>frameSize:."
	<c: 'int64_t opt_frame_size_of(oop m, oop c)'>
	| src fs min blk |
	blk := c ~= memory nilOop.
	src := blk ifTrue: [c] ifFalse: [m].
	fs := self intVal: (self loadRef: src at: (blk ifTrue: [BC_FRAMESIZE] ifFalse: [CM_FRAMESIZE])).
	min := blk
		ifTrue: [(self intVal: (self loadRef: src at: BC_NUMARGS)) + (self intVal: (self loadRef: src at: BC_NUMTEMPS))]
		ifFalse: [(self intVal: (self loadRef: src at: CM_NUMARGS)) + (self intVal: (self loadRef: src at: CM_NUMTEMPS))].
	^fs > min ifTrue: [fs] ifFalse: [min]
!
resume: f
	"The interpreter returns into optimized frame f (on top; the result is in slot slots): answer where its code continues, 0 if it was deoptimized (the interpreter continues the top frame)."
	<c: 'uint64_t opt_resume(Frame *f)'>
	| h k off |
	h := self cCoerce: f code to: 'JitMethod *'.
	k := f pc - h bcSize asInt32.
	off := (self isAlive: h) ifTrue: [runtime mapOffsetOf: h pc: f pc] ifFalse: [-1].
	(off < 0 and: [k < 0]) ifTrue: [
		"not entered yet: the lower tier runs it"
		f code: h lower.
		^runtime addressFor: f].
	off < 0 ifTrue: [
		self deoptFrame: f index: k regs: self null mode: 2.
		^0].
	^h codeStart + off asUInt64
! !

!OptRuntime methodsFor: 'garbage collection'!
youngRoots: fn
	<c: 'void opt_young_roots(void (*fn)(oop *))'>
	| n o |
	self clearBlockCalls.
	self decodedRoots: fn.
	rtOptYoungOverflow ifTrue: [^self allPools: fn].
	rtOptYoungCount = 0 ifTrue: [^self].
	cache beginWriting.
	0 to: rtOptYoungCount - 1 do: [:i | self roots: (rtOptYoung at: i) fn: fn].
	cache endWriting.
	n := 0.
	0 to: rtOptYoungCount - 1 do: [:i |
		o := rtOptYoung at: i.
		(self stillYoung: o) ifTrue: [
			rtOptYoung at: n put: o.
			n := n + 1]].
	rtOptYoungCount := n asInt32
!
decodedRoots: fn
	"While activations are rebuilt (materialize: allocates): their methods and values."
	rtDeoptCount = 0 ifTrue: [^self].
	0 to: rtDeoptCount - 1 do: [:i | fn call: rtDeoptVals + i].
	0 to: rtActCount - 1 do: [:i | fn call: rtActMethod + i]
!
stillYoung: o
	(self isYoung: o method) ifTrue: [^true].
	0 to: o poolCount asInt64 - 1 do: [:i | ((self isPtr: (self poolAt: i of: o)) and: [self isYoung: (self poolAt: i of: o)]) ifTrue: [^true]].
	^false
!
allRoots: fn
	<c: 'void opt_all_roots(void (*fn)(oop *))'>
	self clearBlockCalls.
	self decodedRoots: fn.
	self allPools: fn
!
allPools: fn
	"Every optimized header's method and pool (in the code cache)."
	cache beginWriting.
	0 to: rtAllCount - 1 do: [:i | self roots: (rtAll at: i) fn: fn].
	cache endWriting
!
headerValid: o with: valid
	"The GC verifier: o's method and pool."
	<c: 'bool opt_header_valid(JitMethod *o, bool (*valid)(oop))'>
	| pool |
	(valid call: o method) ifFalse: [
		libc fputs: 'optimized code: bad method
' to: libc stderr.
		^false].
	pool := self cCoerce: o codeStart + o poolOffset to: 'oop *'.
	0 to: o poolCount asInt64 - 1 do: [:i |
		((self isPtr: (pool at: i)) and: [(valid call: (pool at: i)) not]) ifTrue: [
			libc fprintf: libc stderr format: 'optimized code: bad pool entry %lld: %llx
' with: i with: (pool at: i).
			^false]].
	^true
!
roots: o fn: fn
	| pool |
	fn call: (o fieldAddress: #method).
	pool := self cCoerce: o codeStart + o poolOffset to: 'oop *'.
	0 to: o poolCount asInt64 - 1 do: [:i | (self isPtr: (pool at: i)) ifTrue: [fn call: pool + i]]
!
flushed
	"The code cache was flushed."
	<c: 'void opt_flushed(void)'>
	self clearBlockCalls.
	rtOptYoungCount := 0.
	rtOptYoungOverflow := false.
	rtAllCount := 0.
	libc memset: rtUnits value: 0 size: 8 * OPT_MAX_UNITS.
	libc memset: rtFailed value: 0 size: 8 * OPT_MAX_UNITS.
	rtUnitCount := 0
! !

!OptRuntime methodsFor: 'invalidation'!
invalidate: o
	"o's assumptions no longer hold: its code must not run again (frames running it deoptimize when they continue); its method or unit is optimized again later."
	| h |
	(self isAlive: o) ifFalse: [^self].
	rtStatInvalidations := rtStatInvalidations + 1.
	(o blockStart = 0 and: [o osrPc = 0]) ifTrue: [
		runtime counterFor: o method put: (self initialCount: o method).
		h := self cCoerce: o lower to: 'JitMethod *'.
		cache beginWriting.
		h opt: 0.
		cache endWriting.
		runtime codeChanged: o method].
	runtime kill: o
!
invalidateSelector: sel
	"A method for sel was added or removed: optimized code that inlined or speculated on a send of sel."
	<c: 'void opt_invalidate_selector(oop sel)'>
	| o |
	0 to: rtAllCount - 1 do: [:i |
		o := rtAll at: i.
		0 to: o depCount asInt64 - 1 do: [:k | (self poolAt: (o deps at: k) of: o) = sel ifTrue: [self invalidate: o]]]
!
invalidateAll
	<c: 'void opt_invalidate_all(void)'>
	0 to: rtAllCount - 1 do: [:i | self invalidate: (rtAll at: i)]
!
