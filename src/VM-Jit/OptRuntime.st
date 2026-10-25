OptModule subclass: #OptRuntime
	instanceVariableNames: 'ir builder passes regalloc codegen rtDeoptVals rtDeoptCount rtActMethod rtActClosure rtActRcv rtActPc rtActDepth rtActVals rtActCount rtOptYoung rtOptYoungCount rtOptYoungOverflow rtStatOptCompiled rtStatOptFailed rtStatOptBytecodes rtStatOptUs rtStatOptBytes rtStatDeopts rtStatOptOsr rtStatInvalidations rtAll rtAllCount'
	classVariableNames: 'OPT_MAX_DEOPTS OPT_MAX_DEOPT_ACTS OPT_MAX_DEOPT_VALS OPT_MAX_HEADERS OPT_MAX_YOUNG'
	package: 'VM-Jit'!

OptRuntime comment: 'The optimizing tier''s side of the runtime (docs/jit.md, Optimizing tier): when to optimize (tierUp:), compiling (OptBuilder, OptPasses, OptRegalloc, OptCodegen), sends from optimized code, deoptimization (a guard failed: the registers are in the JitState; after a send: everything is in slots), rebuilding an optimized frame''s activations as frames (deoptimization) or Contexts (materializeAll), resuming an optimized frame the interpreter returns into, the GC roots of optimized code (its method and oop pool).

An optimized method''s header (JitMethod, mode opt) is linked from its method''s lower-tier header (opt; lower back); frames of the method run the optimized code, frames of its blocks the lower tier''s. The header carries the safepoint table (spTable: offset of each safepoint''s record in meta) and the records (OptCodegen>>recordState:kind:node:inSlots:).'!

!OptRuntime class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (builder OptBuilder) (passes OptPasses) (regalloc OptRegalloc) (codegen OptCodegen)
		(rtDeoptVals 'oop[OPT_MAX_DEOPT_VALS]') (rtDeoptCount int32_t)
		(rtActMethod 'oop[OPT_MAX_DEOPT_ACTS]') (rtActClosure 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActRcv 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActPc 'int32_t[OPT_MAX_DEOPT_ACTS]')
		(rtActDepth 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActVals 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActCount int32_t)
		(rtOptYoung 'JitMethod *[OPT_MAX_YOUNG]') (rtOptYoungCount int32_t) (rtOptYoungOverflow bool)
		(rtStatOptCompiled uint64_t) (rtStatOptFailed uint64_t) (rtStatOptBytecodes uint64_t) (rtStatOptUs uint64_t) (rtStatOptBytes uint64_t)
		(rtStatDeopts uint64_t) (rtStatOptOsr uint64_t) (rtStatInvalidations uint64_t)
		(rtAll 'JitMethod *[OPT_MAX_HEADERS]') (rtAllCount int32_t))
!
initialize
	OPT_MAX_DEOPT_VALS := 8192.
	OPT_MAX_DEOPT_ACTS := 256.
	OPT_MAX_YOUNG := 1024.
	OPT_MAX_HEADERS := 16384.
	OPT_MAX_DEOPTS := 8
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
tierUp: f
	"f's method ran out of its count at f's pc (synced): answer 0 to go on in the lower tier, 1 to leave, or where f continues in optimized code."
	<c: 'uint64_t opt_tier_up(Frame *f)'>
	<var: #o type: 'JitMethod *'>
	| m h o |
	m := f method.
	runtime counterFor: m put: 16r3FFFFFFF.
	h := runtime lookup: m.
	(runtime hasCode: h) ifFalse: [^0].
	o := self optOf: h.
	(o isNull and: [h opt = 0]) ifTrue: [o := self optimize: m lower: h].
	o isNull ifTrue: [^0].
	(f pc = 0 and: [f closure = memory nilOop and: [f code = (self cCoerce: h to: 'uint64_t')]]) ifTrue: [
		f code: (self cCoerce: o to: 'uint64_t').
		^o start].
	^0
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
	cache endWriting.
	self noteYoung: o.
	(runtime hasCode: o) ifFalse: [^self null].
	interpreter setCacheCode: (self cCoerce: o to: 'uint64_t') forMethod: m.
	^o
!
compile: m
	"Emit optimized code for m at the assembler's pc (JitRuntime>>compile:mode:notes:); answer whether it could."
	<c: 'bool opt_compile(oop m)'>
	| ok trace limit |
	trace := (libc getenv: 'SAMALTAK_OPT_TRACE') notNull.
	limit := libc getenv: 'SAMALTAK_OPT_LIMIT'.
	(limit notNull and: [rtStatOptCompiled >= (libc atol: limit) asUInt64]) ifTrue: [^false].
	trace ifTrue: [
		libc fputs: 'opt: ' to: libc stderr.
		interpreter printActivation: m receiver: memory nilOop closure: memory nilOop on: libc stderr].
	ok := (builder build: m) and: [
		passes cleanup: builder entryBlock.
		trace ifTrue: [ir print].
		(regalloc allocate: (ir act: 0) numArgs) and: [
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
	| h rec info n kind sp sel base r cls e ns ok |
	h := self cCoerce: f code to: 'JitMethod *'.
	rec := self recordOf: h index: k.
	info := rec at: 2.
	n := (info bitAnd: 255) asInt32.
	kind := (info >> 8) bitAnd: 255.
	sp := (info >> 16) bitAnd: 255.
	sel := self poolAt: (rec at: 3) of: h.
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
			interpreter activateBlock: n.
			^runtime entryOfTop]].
	cls := kind = 1
		ifTrue: [self loadRef: (self loadRef: (self innermostMethodOf: rec h: h) at: CM_CLASS) at: BEH_SUPERCLASS]
		ifFalse: [interpreter receiverClass: r].
	e := interpreter icacheAt: (self cCoerce: key to: 'uint8_t *').
	(e cls = cls and: [e sel = key]) ifFalse: [
		e := interpreter siteEntry: (self cCoerce: key to: 'uint8_t *') class: cls selector: sel.
		e isNull ifTrue: [^self leaveBefore: f index: k]].
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
	runtime sync: f.
	((e kind bitAnd: runtime kCtx) ~= 0 and: [self isInt: (self loadRef: r at: CTX_SENDER)]) ifTrue: [^self leaveBefore: f index: k].
	(runtime isPerform: e) ifTrue: [^self leaveBefore: f index: k].
	runtime sendPushed: 0.
	^runtime dispatch: e frame: f argc: n
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
	| h why r |
	h := self cCoerce: f code to: 'JitMethod *'.
	why := ((self recordOf: h index: k) at: 0) >> 8.
	r := self deoptFrame: f index: k regs: runtime state dump mode: 0.
	"the innermost activation's method and pc: where the guard's bytecode is"
	why ~= 0 ifTrue: [feedback noteFlags: (rtActMethod at: rtActCount - 1) pc: (rtActPc at: rtActCount - 1) flags: why asUInt32].
	cache beginWriting.
	h deopts: h deopts + 1.
	cache endWriting.
	h deopts > OPT_MAX_DEOPTS ifTrue: [self invalidate: h].
	^r
!
deoptReturn: f index: k
	"After the send of safepoint k (the result in slot slots): f's code was invalidated (or stress): rebuild its activations."
	<c: 'uint64_t opt_deopt_return(Frame *f, int64_t k)'>
	^self deoptFrame: f index: k regs: self null mode: 2
!
deoptFrame: f index: k regs: regs mode: mode
	"Rebuild optimized frame f (the top frame) as the frames of its activations at safepoint k. mode 0: as recorded (a guard, an interrupt check), 1: before the send (it is executed again), 2: after it (its result pushed). Answer 1 (leave: the interpreter continues the top frame)."
	<c: 'uint64_t opt_deopt_frame(Frame *f, int64_t k, uint64_t *regs, int32_t mode)'>
	| h fi fp g j m d cl |
	h := self cCoerce: f code to: 'JitMethod *'.
	rtStatDeopts := rtStatDeopts + 1.
	runtime resetStress.
	self decode: h index: k frame: f regs: regs mode: mode.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [self traceDeopt: h index: k mode: mode].
	fi := (f - interpreter frames) asInt32.
	fp := f fp.
	0 to: rtActCount - 1 do: [:i |
		j := fi + i.
		g := interpreter frames + j.
		m := rtActMethod at: i.
		d := rtActDepth at: i.
		i > 0 ifTrue: [fp := fp + (rtActDepth at: i - 1) + 1].
		fp at: -1 put: (rtDeoptVals at: (rtActRcv at: i)).
		0 to: d - 1 do: [:s | fp at: s put: (rtDeoptVals at: (rtActVals at: i) + s)].
		cl := (rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop].
		g method: m.
		g closure: cl.
		g ctx: memory nilOop.
		g code: (runtime blockCodeFor: m).
		g fp: fp.
		g ip: (self methodBytecodes: m) + (rtActPc at: i).
		g pc: (rtActPc at: i).
		g lits: (self slotsOf: (self loadRef: m at: CM_LITERALS)).
		g sp: d].
	interpreter nframes: fi + rtActCount.
	interpreter cstackUsed: (fp + (rtActDepth at: rtActCount - 1) - interpreter cstackBase) asUInt64.
	rtDeoptCount := 0.
	^1
!
decode: h index: k frame: f regs: regs mode: mode
	"Read safepoint k's record into the activation arrays, the values into deoptVals (GC roots). mode 1 pushes the send's receiver and arguments (and goes back to the send), 2 its result."
	<c: 'void opt_decode(JitMethod *h, int64_t k, Frame *f, uint64_t *regs, int32_t mode)'>
	| rec p nacts d base sendPc argc op bcs |
	rec := self recordOf: h index: k.
	sendPc := rec at: 1.
	argc := ((rec at: 2) bitAnd: 255) asInt32.
	nacts := rec at: 4.
	p := 5.
	rtDeoptCount := 0.
	rtActCount := nacts.
	0 to: nacts - 1 do: [:j |
		rtActMethod at: j put: (self poolAt: (rec at: p) of: h).
		rtActClosure at: j put: ((rec at: p + 1) < 0 ifTrue: [-1] ifFalse: [self value: (rec at: p + 1) h: h frame: f regs: regs]).
		rtActRcv at: j put: (self value: (rec at: p + 2) h: h frame: f regs: regs).
		rtActPc at: j put: (rec at: p + 3).
		d := rec at: p + 4.
		rtActDepth at: j put: d.
		rtActVals at: j put: rtDeoptCount.
		0 to: d - 1 do: [:i | self value: (rec at: p + 5 + i) h: h frame: f regs: regs].
		p := p + 5 + d].
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
	libc fprintf: libc stderr format: 'deopt mode %d at %lld, %d activations, ' with: mode with: k with: rtActCount.
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
	self push: v.
	^rtDeoptCount - 1
!
materialize: f
	"materializeAll meets optimized frame f: a Context for each of its activations (their senders chained from activeCtx), the last one activeCtx."
	<c: 'void opt_materialize(Frame *f)'>
	<var: #mode type: 'int32_t'>
	| h k mode top ctx n s |
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
		"a primitive is running: its receiver and arguments are on the stack, as the interpreter's"
		interpreter primBaseIndex: (rtActDepth at: rtActCount - 1).
		0 to: (((self recordOf: h index: k) at: 2) bitAnd: 255) do: [:i | self push: ((f fp + h slots asInt64) at: i)].
		rtActDepth at: rtActCount - 1 put: rtDeoptCount - (rtActVals at: rtActCount - 1)].
	0 to: rtActCount - 1 do: [:i |
		n := (self frameSizeOf: (rtActMethod at: i) closure: ((rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop])) + CTX_SLACK.
		n < (rtActDepth at: i) ifTrue: [n := rtActDepth at: i].
		ctx := memory allocContext: n asUInt32.
		s := self slotsOf: ctx.
		s at: CTX_SENDER put: interpreter activeCtx.
		s at: CTX_PC put: (self intOop: (rtActPc at: i)).
		s at: CTX_STACKP put: (self intOop: (rtActDepth at: i)).
		s at: CTX_METHOD put: (rtActMethod at: i).
		s at: CTX_CLOSURE put: ((rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop]).
		s at: CTX_RECEIVER put: (rtDeoptVals at: (rtActRcv at: i)).
		0 to: (rtActDepth at: i) - 1 do: [:j | s at: CTX_FIXED + j put: (rtDeoptVals at: (rtActVals at: i) + j)].
		gc rememberIfOld: ctx.
		interpreter activeCtx: ctx].
	rtDeoptCount := 0
!
frameSizeOf: m closure: c
	"frameSize of an activation of m or of block c (at least its arguments and temps), as Interpreter>>frameSize:."
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
	off < 0 ifTrue: [
		self deoptFrame: f index: k regs: self null mode: 2.
		^0].
	^h codeStart + off asUInt64
! !

!OptRuntime methodsFor: 'garbage collection'!
youngRoots: fn
	<c: 'void opt_young_roots(void (*fn)(oop *))'>
	| n o |
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
	rtOptYoungCount := 0.
	rtOptYoungOverflow := false.
	rtAllCount := 0
! !

!OptRuntime methodsFor: 'invalidation'!
invalidate: o
	"o's assumptions no longer hold: its code must not run again (frames running it deoptimize when they continue); its method is optimized again later."
	| h |
	(self isAlive: o) ifFalse: [^self].
	rtStatInvalidations := rtStatInvalidations + 1.
	runtime counterFor: o method put: (self initialCount: o method).
	h := self cCoerce: o lower to: 'JitMethod *'.
	cache beginWriting.
	h opt: 0.
	cache endWriting.
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
