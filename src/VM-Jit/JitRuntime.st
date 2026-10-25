VMCoreModule subclass: #JitRuntime
	instanceVariableNames: 'stubs template stencil baseline brt cache asm analysis jitMode jitFlags jitThreshold jitOsrThreshold jitCacheMB cacheOpened flushPending invalidations stateBlock methodTable tableCount methodCounts youngMethods youngCount youngOverflow mapPcs mapOffsets mapCount refSites refCount sendPushed performFn performArgsFn statCompiled statFailed statBytecodes statCompileUs statCodeBytes statCacheFlushes statEntries statExits statResumes statOsr feedback optimizer jitOptThreshold optCounts entryCells'
	classVariableNames: 'JIT_BASELINE JIT_FLAG_ACCESS JIT_FLAG_ALLOC JIT_FLAG_ARITH JIT_FLAG_BARRIER JIT_FLAG_BLOCKS JIT_FLAG_CALLS JIT_FLAG_DEOPT JIT_FLAG_EAGER JIT_FLAG_EMBED JIT_FLAG_FLOAT JIT_FLAG_FUSE JIT_FLAG_GVN JIT_FLAG_IC JIT_FLAG_INLINE JIT_FLAG_LAST JIT_FLAG_MEGA JIT_FLAG_NLR JIT_FLAG_NOTES JIT_FLAG_PIC JIT_FLAG_PRIMS JIT_FLAG_QUICK JIT_FLAG_REGS JIT_FLAG_TEMPS JIT_FLAG_UNBOX JIT_MAX_COUNT JIT_MAX_MAP JIT_MAX_REFS JIT_MAX_YOUNG JIT_NONE JIT_OPT JIT_PROLOGUE_BYTES JIT_STENCIL JIT_TABLE_SIZE JIT_TEMPLATE JIT_THREADED JM_DEAD JM_FAILED JM_NOTES JM_OSR'
	package: 'VM-Jit'!

JitRuntime comment: 'The runtime every compiler''s machine code runs on (docs/jit.md, Shared runtime): configuration (--jit, --jit-threshold, --jit-osr, --jit-flags, --jit-cache), the compiled methods (JitMethod headers in the code cache, found by the method''s identity hash; their methods are GC roots, young ones listed for scavenges; embedded object references patched by full GCs and become), the interpreter''s hooks (activated:, resume:, backJump:), the functions machine code calls (send:info:site:, special:info:site:, interrupt:, closure:, makeArray:, outerTemp:, widow:, writeBarrier:value:), code cache flushes, statistics.

Machine code runs the interpreter''s frames: x19 the Frame, x20 its slots, x21 the receiver, x22 the JitState. Before calling a function here that may allocate, collect, flush frames, switch processes or run Smalltalk, it stores the frame''s pc and sp (the bytecode it is at and the slots in use); the function makes the interpreter''s view canonical (sync:) and answers 0 to continue, 1 to leave to the interpreter (the native stack is dropped; the interpreter reloads the top frame or Context), or for a send the entry of the callee''s code (frame pushed, the caller calls it with blr). The compilers are Arm64Modules (they name registers); they ask me what they need through inline accessors.'!

!JitRuntime class methodsFor: 'declaring'!
declarations
	^#((stubs JitStubs) (template JitTemplateCompiler) (stencil JitStencilCompiler) (baseline JitBaselineCompiler) (brt JitBaselineRuntime) (cache CodeCache) (asm Arm64Assembler) (analysis BytecodeAnalysis)
		(feedback JitFeedback) (optimizer OptRuntime)
		(jitMode int32_t) (jitFlags uint32_t) (jitThreshold int64_t 2) (jitOsrThreshold int64_t 50) (jitOptThreshold int64_t 1000) (jitCacheMB int64_t 64)
		(cacheOpened bool) (flushPending bool) (invalidations uint64_t)
		(stateBlock 'JitState[1]')
		(methodTable 'JitMethod *[JIT_TABLE_SIZE]') (tableCount int64_t) (methodCounts 'uint16_t[JIT_TABLE_SIZE]')
		(youngMethods 'JitMethod *[JIT_MAX_YOUNG]') (youngCount int32_t) (youngOverflow bool) (optCounts 'int32_t[JIT_TABLE_SIZE]') (entryCells 'uint64_t[131072]')
		(mapPcs 'uint32_t[JIT_MAX_MAP]') (mapOffsets 'uint32_t[JIT_MAX_MAP]') (mapCount int32_t)
		(refSites 'uint32_t[JIT_MAX_REFS]') (refCount int32_t) (sendPushed int32_t)
		(performFn prim_fn) (performArgsFn prim_fn)
		(statCompiled uint64_t) (statFailed uint64_t) (statBytecodes uint64_t) (statCompileUs uint64_t) (statCodeBytes uint64_t) (statCacheFlushes uint64_t)
		(statEntries uint64_t) (statExits uint64_t) (statResumes uint64_t) (statOsr uint64_t))
!
initialize
	JIT_NONE := 0.
	JIT_TEMPLATE := 1.
	JIT_THREADED := 2.
	JIT_STENCIL := 3.
	JIT_BASELINE := 4.
	JIT_OPT := 5.
	JIT_FLAG_ARITH := 1.
	JIT_FLAG_FUSE := 2.
	JIT_FLAG_BARRIER := 4.
	JIT_FLAG_NOTES := 8.
	JIT_FLAG_EMBED := 16.
	JIT_FLAG_IC := 32.
	JIT_FLAG_PIC := 64.
	JIT_FLAG_MEGA := 128.
	JIT_FLAG_REGS := 256.
	JIT_FLAG_PRIMS := 512.
	JIT_FLAG_ACCESS := 1024.
	JIT_FLAG_ALLOC := 2048.
	JIT_FLAG_FLOAT := 4096.
	JIT_FLAG_BLOCKS := 8192.
	JIT_FLAG_NLR := 16384.
	JIT_FLAG_QUICK := 32768.
	JIT_FLAG_TEMPS := 65536.
	"the optimizing tier's (also blocks, prims, alloc; then its stress flags)"
	JIT_FLAG_INLINE := 131072.
	JIT_FLAG_UNBOX := 262144.
	JIT_FLAG_CALLS := 524288.
	JIT_FLAG_GVN := 1048576.
	JIT_FLAG_EAGER := 2097152.
	JIT_FLAG_DEOPT := 4194304.
	JIT_FLAG_LAST := JIT_FLAG_DEOPT.
	JIT_TABLE_SIZE := 65536.
	JIT_MAX_YOUNG := 4096.
	JIT_MAX_MAP := 32768.
	JIT_MAX_REFS := 4096.
	JIT_PROLOGUE_BYTES := 20.
	JIT_MAX_COUNT := 16rFFFF.
	JM_FAILED := 1.
	JM_DEAD := 2.
	JM_NOTES := 4.
	JM_OSR := 8
! !

!JitRuntime methodsFor: 'configuration'!
enabled
	^jitMode ~= JIT_NONE
!
mode
	^jitMode
!
flags
	^jitFlags
!
threshold
	^jitThreshold
!
osrThreshold
	^jitOsrThreshold
!
cacheMB
	^jitCacheMB
!
mode: m
	jitMode := m
!
threshold: n
	jitThreshold := n
!
osrThreshold: n
	jitOsrThreshold := n
!
cacheMB: n
	jitCacheMB := n
!
arith
	"Inline SmallInteger arithmetic and comparisons."
	^(jitFlags bitAnd: JIT_FLAG_ARITH) ~= 0
!
fuse
	"A comparison followed by a conditional jump branches directly."
	^(jitFlags bitAnd: JIT_FLAG_FUSE) ~= 0
!
barrier
	"The store barrier's fast path inline."
	^(jitFlags bitAnd: JIT_FLAG_BARRIER) ~= 0
!
notes
	"Record annotations for all code, not only for code compiled for disassembly."
	^(jitFlags bitAnd: JIT_FLAG_NOTES) ~= 0
!
embed
	"Embed old literal constants in the code instead of loading them through the frame's lits."
	^(jitFlags bitAnd: JIT_FLAG_EMBED) ~= 0
!
flag: bit
	^(jitFlags bitAnd: bit) ~= 0
!
inlineFlag
	^JIT_FLAG_INLINE
!
blocksFlag
	^JIT_FLAG_BLOCKS
!
primsFlag
	^JIT_FLAG_PRIMS
!
gvnFlag
	^JIT_FLAG_GVN
!
unboxFlag
	^JIT_FLAG_UNBOX
!
callsFlag
	^JIT_FLAG_CALLS
!
allocFlag
	^JIT_FLAG_ALLOC
!
eagerFlag
	^JIT_FLAG_EAGER
!
deoptFlag
	^JIT_FLAG_DEOPT
!
optThreshold
	^jitOptThreshold
!
optThreshold: n
	jitOptThreshold := n
!
tiering
	"--jit opt: the lower tier counts entries and backward jumps toward optimization."
	^jitMode = JIT_OPT
!
optMode
	^JIT_OPT
!
lowerMode
	"The compiler of a method's first machine code."
	^jitMode = JIT_OPT ifTrue: [JIT_TEMPLATE] ifFalse: [jitMode]
!
ic
	"Baseline: machine-code inline caches (else every send looks up in the runtime)."
	^(jitFlags bitAnd: JIT_FLAG_IC) ~= 0
!
pic
	"Baseline: polymorphic inline caches (else a monomorphic miss goes megamorphic)."
	^(jitFlags bitAnd: JIT_FLAG_PIC) ~= 0
!
mega
	"Baseline: megamorphic sends probe a cache in machine code (else they call the runtime)."
	^(jitFlags bitAnd: JIT_FLAG_MEGA) ~= 0
!
regs
	"Baseline: operands stay in registers between bytecodes (else every push goes to its slot)."
	^(jitFlags bitAnd: JIT_FLAG_REGS) ~= 0
!
prims
	"Baseline: primitives of compiled methods in machine code (else they call the primitive's C function)."
	^(jitFlags bitAnd: JIT_FLAG_PRIMS) ~= 0
!
access
	"Baseline: at: at:put: size class x y inline at send sites."
	^(jitFlags bitAnd: JIT_FLAG_ACCESS) ~= 0
!
alloc
	"Baseline: allocation in machine code (eden bump pointer): basicNew, closures, Contexts, Arrays, Floats."
	^(jitFlags bitAnd: JIT_FLAG_ALLOC) ~= 0
!
float
	"Baseline: Float arithmetic and comparisons inline."
	^(jitFlags bitAnd: JIT_FLAG_FLOAT) ~= 0
!
blocks
	"Baseline: value sends enter the block's code directly (a cache in machine code)."
	^(jitFlags bitAnd: JIT_FLAG_BLOCKS) ~= 0
!
nlr
	"Baseline: non-local returns to a home frame in machine code return there directly."
	^(jitFlags bitAnd: JIT_FLAG_NLR) ~= 0
!
quick
	"Baseline: methods that only answer an instance variable, a constant or self, or set instance variables, run without a frame."
	^(jitFlags bitAnd: JIT_FLAG_QUICK) ~= 0
!
temps
	"Baseline: temporaries cached in registers within a basic block."
	^(jitFlags bitAnd: JIT_FLAG_TEMPS) ~= 0
!
baselineMode
	^JIT_BASELINE
!
isBaseline
	^jitMode = JIT_BASELINE
!
templateMode
	^JIT_TEMPLATE
!
prologueBytes
	^JIT_PROLOGUE_BYTES
!
modeNamed: name
	"The mode called name, -1 if there is none."
	<c: 'int32_t jit_mode_named(const char *name)'>
	(libc strcmp: name with: 'none') = 0 ifTrue: [^JIT_NONE].
	(libc strcmp: name with: 'template') = 0 ifTrue: [^JIT_TEMPLATE].
	(libc strcmp: name with: 'threaded') = 0 ifTrue: [^JIT_THREADED].
	(libc strcmp: name with: 'stencil') = 0 ifTrue: [^JIT_STENCIL].
	(libc strcmp: name with: 'opt') = 0 ifTrue: [^JIT_OPT].
	(libc strcmp: name with: 'baseline') = 0 ifTrue: [^JIT_BASELINE].
	^-1
!
modeName: m
	<c: 'const char *jit_mode_name(int32_t m)'>
	m = JIT_TEMPLATE ifTrue: [^'template'].
	m = JIT_THREADED ifTrue: [^'threaded'].
	m = JIT_STENCIL ifTrue: [^'stencil'].
	m = JIT_OPT ifTrue: [^'opt'].
	m = JIT_BASELINE ifTrue: [^'baseline'].
	^'none'
!
flagNamed: name length: n
	"The bit of the ablation flag called name (n bytes), 0 if there is none."
	(self is: name length: n named: 'arith') ifTrue: [^JIT_FLAG_ARITH].
	(self is: name length: n named: 'fuse') ifTrue: [^JIT_FLAG_FUSE].
	(self is: name length: n named: 'barrier') ifTrue: [^JIT_FLAG_BARRIER].
	(self is: name length: n named: 'notes') ifTrue: [^JIT_FLAG_NOTES].
	(self is: name length: n named: 'embed') ifTrue: [^JIT_FLAG_EMBED].
	(self is: name length: n named: 'ic') ifTrue: [^JIT_FLAG_IC].
	(self is: name length: n named: 'pic') ifTrue: [^JIT_FLAG_PIC].
	(self is: name length: n named: 'mega') ifTrue: [^JIT_FLAG_MEGA].
	(self is: name length: n named: 'regs') ifTrue: [^JIT_FLAG_REGS].
	(self is: name length: n named: 'prims') ifTrue: [^JIT_FLAG_PRIMS].
	(self is: name length: n named: 'access') ifTrue: [^JIT_FLAG_ACCESS].
	(self is: name length: n named: 'alloc') ifTrue: [^JIT_FLAG_ALLOC].
	(self is: name length: n named: 'float') ifTrue: [^JIT_FLAG_FLOAT].
	(self is: name length: n named: 'blocks') ifTrue: [^JIT_FLAG_BLOCKS].
	(self is: name length: n named: 'nlr') ifTrue: [^JIT_FLAG_NLR].
	(self is: name length: n named: 'quick') ifTrue: [^JIT_FLAG_QUICK].
	(self is: name length: n named: 'temps') ifTrue: [^JIT_FLAG_TEMPS].
	(self is: name length: n named: 'inline') ifTrue: [^JIT_FLAG_INLINE].
	(self is: name length: n named: 'gvn') ifTrue: [^JIT_FLAG_GVN].
	(self is: name length: n named: 'unbox') ifTrue: [^JIT_FLAG_UNBOX].
	(self is: name length: n named: 'calls') ifTrue: [^JIT_FLAG_CALLS].
	(self is: name length: n named: 'eager') ifTrue: [^JIT_FLAG_EAGER].
	(self is: name length: n named: 'deopt') ifTrue: [^JIT_FLAG_DEOPT].
	^0
!
is: s length: n named: name
	^(libc strlen: name) = n asUInt64 and: [(libc memcmp: s with: name size: n asUInt64) = 0]
!
flagName: bit
	<c: 'const char *jit_flag_name(uint32_t bit)'>
	bit = JIT_FLAG_ARITH ifTrue: [^'arith'].
	bit = JIT_FLAG_FUSE ifTrue: [^'fuse'].
	bit = JIT_FLAG_BARRIER ifTrue: [^'barrier'].
	bit = JIT_FLAG_NOTES ifTrue: [^'notes'].
	bit = JIT_FLAG_EMBED ifTrue: [^'embed'].
	bit = JIT_FLAG_IC ifTrue: [^'ic'].
	bit = JIT_FLAG_PIC ifTrue: [^'pic'].
	bit = JIT_FLAG_MEGA ifTrue: [^'mega'].
	bit = JIT_FLAG_REGS ifTrue: [^'regs'].
	bit = JIT_FLAG_PRIMS ifTrue: [^'prims'].
	bit = JIT_FLAG_ACCESS ifTrue: [^'access'].
	bit = JIT_FLAG_ALLOC ifTrue: [^'alloc'].
	bit = JIT_FLAG_FLOAT ifTrue: [^'float'].
	bit = JIT_FLAG_BLOCKS ifTrue: [^'blocks'].
	bit = JIT_FLAG_NLR ifTrue: [^'nlr'].
	bit = JIT_FLAG_QUICK ifTrue: [^'quick'].
	bit = JIT_FLAG_TEMPS ifTrue: [^'temps'].
	bit = JIT_FLAG_INLINE ifTrue: [^'inline'].
	bit = JIT_FLAG_GVN ifTrue: [^'gvn'].
	bit = JIT_FLAG_UNBOX ifTrue: [^'unbox'].
	bit = JIT_FLAG_CALLS ifTrue: [^'calls'].
	bit = JIT_FLAG_EAGER ifTrue: [^'eager'].
	^'deopt'
!
lastFlag
	^JIT_FLAG_LAST
!
parseFlags: s
	"a,b,-c: set a and b, clear c. Answer whether every name is a flag."
	<c: 'bool jit_parse_flags(const char *s)'>
	| i start bit off |
	i := 0.
	[(s at: i) ~= 0] whileTrue: [
		off := (s at: i) = $- value.
		off ifTrue: [i := i + 1].
		start := i.
		[(s at: i) ~= 0 and: [(s at: i) ~= $, value]] whileTrue: [i := i + 1].
		bit := self flagNamed: s + start length: i - start.
		bit = 0 ifTrue: [^false].
		jitFlags := (off ifTrue: [jitFlags bitClear: bit] ifFalse: [jitFlags bitOr: bit]) asUInt32.
		(s at: i) = $, value ifTrue: [i := i + 1]].
	^true
!
setMode: m
	"Switch compilers: all code is dropped at the next point without machine code on the native stack."
	<c: 'bool jit_set_mode(int32_t m)'>
	(m ~= JIT_NONE and: [self ensureOpen not]) ifTrue: [^false].
	jitMode := m.
	flushPending := true.
	invalidations := invalidations + 1.
	interpreter flushMethodCache.
	^true
!
setFlags: f
	<c: 'void jit_set_flags(uint32_t f)'>
	jitFlags := f.
	flushPending := true.
	invalidations := invalidations + 1
!
defaults
	"Before the command line: --jit none, threshold 2, OSR after 50 backward jumps, optimization after 1000 entries and backward jumps, 64 MB, every flag but notes, embed and the stress flags eager and deopt."
	<c: 'void jit_defaults(void)'>
	jitMode := JIT_NONE.
	jitFlags := ((JIT_FLAG_LAST << 1) - 1 bitClear: (((JIT_FLAG_NOTES bitOr: JIT_FLAG_EMBED) bitOr: JIT_FLAG_EAGER) bitOr: JIT_FLAG_DEOPT)) asUInt32
!
start
	"After the image is loaded."
	<c: 'void jit_start(void)'>
	| t |
	t := self primitiveTable.
	0 to: self primitiveCount - 1 do: [:i |
		(libc strcmp: (t + i) name with: 'perform') = 0 ifTrue: [performFn := (t + i) function].
		(libc strcmp: (t + i) name with: 'performWithArguments') = 0 ifTrue: [performArgsFn := (t + i) function]].
	self refreshState.
	(jitMode ~= JIT_NONE and: [self ensureOpen not]) ifTrue: [self fatal: 'cannot open a %lld MB code cache' with: jitCacheMB]
!
ensureOpen
	"Map the code cache and generate the stubs, once."
	<c: 'bool jit_ensure_open(void)'>
	cacheOpened ifTrue: [^true].
	(jitCacheMB < 1 or: [jitCacheMB > 128]) ifTrue: [^false].
	(cache openWithSize: (jitCacheMB << 20) asUInt64) ifFalse: [^false].
	self refreshState.
	stubs generate ifFalse: [^false].
	stencil open ifFalse: [^false].
	cache keep.
	cacheOpened := true.
	^true
! !

!JitRuntime methodsFor: 'state'!
state
	^stateBlock
!
refreshState
	"The JitState machine code reads through x22."
	<c: 'void jit_refresh_state(void)'>
	stateBlock nilOop: memory nilOop.
	stateBlock trueOop: memory trueOop.
	stateBlock falseOop: memory falseOop.
	stateBlock frames: (self cCoerce: interpreter frames to: 'uint64_t').
	stateBlock youngLo: gc youngLo.
	stateBlock youngHi: gc youngHi.
	stateBlock arrayClass: memory clsArray.
	stateBlock pointClass: memory clsPoint.
	stateBlock stackLimitNormal: interpreter cstackEnd - (8 * (analysis maxDepthLimit + CTX_SLACK + 1)) asUInt64.
	stateBlock interrupt = 0 ifTrue: [stateBlock stackLimit: stateBlock stackLimitNormal].
	stateBlock edenBox: gc edenBoxAddress.
	stateBlock hashBox: memory hashBoxAddress.
	stateBlock lcgMul: 6364136223846793005.
	stateBlock lcgAdd: 1442695040888963407.
	0 to: 7 do: [:t | stateBlock tagClasses at: t put: ((t bitAnd: 1) ~= 0
		ifTrue: [memory clsSmallint]
		ifFalse: [t = 2 ifTrue: [memory clsChar] ifFalse: [t = 4 ifTrue: [memory clsSmallfloat] ifFalse: [memory nilOop]]])].
	stateBlock blockClass: memory clsBlock.
	stateBlock byteStringClass: memory clsBytestring.
	stateBlock byteArrayClass: memory clsBytearray.
	stateBlock contextClass: memory clsContext.
	stateBlock boxedFloatClass: memory clsBoxedfloat.
	stateBlock wordArrayClass: (memory special: SO_BITMAP).
	stateBlock byteSymbolClass: (memory special: SO_BYTESYMBOL).
	brt refresh.
	stateBlock cstackLimit: interpreter cstackLimit.
	self resetStress
!
resetStress
	"--jit-flags deopt: optimized code takes its slow paths every 37th time it passes one of them."
	stateBlock stress <= 0 ifTrue: [stateBlock stress: 37]
!
requestInterrupt
	"Any thread: machine code checks state interrupt at backward jumps and, through stackLimit, at method entries."
	stateBlock interrupt: 1.
	stateBlock stackLimit: 0
!
clearInterrupt
	"The runtime handles the interrupt: entries stop taking the slow path (unless another is requested meanwhile)."
	stateBlock interrupt: 0.
	stateBlock stackLimit: stateBlock stackLimitNormal.
	stateBlock interrupt ~= 0 ifTrue: [stateBlock stackLimit: 0]
!
stateAddress
	^self cCoerce: stateBlock to: 'uint64_t'
!
isOldObject: v
	"Machine code may embed v (full GCs and become patch it)."
	^(self isPtr: v) and: [(self isYoung: v) not]
! !

!JitRuntime methodsFor: 'functions for the stubs'!
sendFunction
	^self cCoerce: (self functionPointer: #send:info:site:) to: 'uint64_t'
!
primitiveNumberNamed: name
	"The number of the primitive called name, -1 if there is none."
	<c: 'int64_t jit_primitive_number(const char *name)'>
	| t |
	t := self primitiveTable.
	0 to: self primitiveCount - 1 do: [:i | (libc strcmp: (t + i) name with: name) = 0 ifTrue: [^(t + i) number asInt64]].
	^-1
!
nowUs
	^scheduler nowUs
!
optSendFunction
	^optimizer sendFunction
!
optDeoptFunction
	^optimizer deoptFunction
!
optDeoptReturnFunction
	^optimizer deoptReturnFunction
!
optStackFullFunction
	^optimizer stackFullFunction
!
optReturnFunction
	^optimizer returnFunction
!
specialFunction
	^self cCoerce: (self functionPointer: #special:info:site:) to: 'uint64_t'
!
interruptFunction
	^self cCoerce: (self functionPointer: #interrupt:) to: 'uint64_t'
!
closureFunction
	^self cCoerce: (self functionPointer: #closure:) to: 'uint64_t'
!
makeArrayFunction
	^self cCoerce: (self functionPointer: #makeArray:) to: 'uint64_t'
!
outerTempFunction
	^self cCoerce: (self functionPointer: #outerTemp:) to: 'uint64_t'
!
widowFunction
	^self cCoerce: (self functionPointer: #widow:) to: 'uint64_t'
!
writeBarrierFunction
	^self cCoerce: (self functionPointer: #writeBarrier:value:) to: 'uint64_t'
!
tierUpFunction
	^self cCoerce: (self functionPointer: #tierUp:loop:) to: 'uint64_t'
!
exitSyncFunction
	^self cCoerce: (self functionPointer: #exitSync:) to: 'uint64_t'
! !

!JitRuntime methodsFor: 'compiled methods'!
codeAddressOf: m
	"m has machine code compiled code may call directly (pushing its frame itself)."
	<c: 'bool jit_has_code(oop m)'>
	jitMode = JIT_NONE ifTrue: [^false].
	^self hasCode: (self lookup: m)
!
slotOf: m
	"The index of m's header in the method table, -1 if it has none."
	<c: 'int64_t jit_slot_of(oop m)'>
	| i h |
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	[(h := methodTable at: i) notNull] whileTrue: [
		h method = m ifTrue: [^i].
		i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1].
	^-1
!
cellAddressOf: m
	"Where direct calls of m (codeAddressOf: m) find the entry and the header of its best code: a call follows m's tier."
	^self cCoerce: entryCells + (2 * (self slotOf: m)) to: 'uint64_t'
!
setCell: i code: h
	"Direct calls of the method at table index i enter h."
	entryCells at: 2 * i put: h start - JIT_PROLOGUE_BYTES.
	entryCells at: 2 * i + 1 put: (self cCoerce: h to: 'uint64_t')
!
codeChanged: m
	"m's best code changed (optimized, invalidated): its direct callers follow."
	<c: 'void jit_code_changed(oop m)'>
	| i |
	i := self slotOf: m.
	i >= 0 ifTrue: [self setCell: i code: (self best: (methodTable at: i))]
!
lookup: m
	"m's header, null if m has none."
	<c: 'JitMethod *jit_lookup(oop m)'>
	| i h |
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	[(h := methodTable at: i) notNull] whileTrue: [
		h method = m ifTrue: [^h].
		i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1].
	^self null
!
insert: h
	| i |
	tableCount >= ((JIT_TABLE_SIZE quo: 4) * 3) ifTrue: [
		flushPending := true.
		^false].
	i := (self hashOf: h method) bitAnd: JIT_TABLE_SIZE - 1.
	[(methodTable at: i) notNull] whileTrue: [i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1].
	methodTable at: i put: h.
	tableCount := tableCount + 1.
	(self hasCode: h) ifTrue: [self setCell: i code: h].
	(self isYoung: h method) ifTrue: [
		youngCount < JIT_MAX_YOUNG
			ifTrue: [
				youngMethods at: youngCount put: h.
				youngCount := youngCount + 1]
			ifFalse: [youngOverflow := true]].
	^true
!
hasCode: h
	^h notNull and: [(h flags bitAnd: JM_FAILED) = 0]
!
isCode: c
	"A frame's or cache entry's code: a JitMethod (not 0, nor a count up to JIT_MAX_COUNT)."
	^c > JIT_MAX_COUNT
!
hasNotes: h
	^(h flags bitAnd: JM_NOTES) ~= 0
!
codeTop
	^cache top
!
invalidations
	^invalidations
!
tableCount
	^tableCount
!
tableSize
	^JIT_TABLE_SIZE
!
headerAt: i
	^methodTable at: i
!
requestFlush
	"The code cache is full: flush it at the next interpreter hook."
	flushPending := true
!
codeResetTo: address
	"Drop code compiled from address on (for a disassembly only)."
	brt forgetSlotsFrom: address.
	cache resetTo: address
!
symbolCount
	^stubs symbolCount
!
symbolAddressAt: i
	^stubs symbolAddressAt: i
!
symbolNameAt: i
	^stubs symbolNameAt: i
!
codeOf: m counting: counting
	"m's header if it has code; else, counting an activation, compile it when its count reaches the threshold."
	<c: 'JitMethod *jit_code_of(oop m, bool counting)'>
	| h i c |
	jitMode = JIT_NONE ifTrue: [^self null].
	h := self lookup: m.
	h notNull ifTrue: [^(self hasCode: h) ifTrue: [self best: h] ifFalse: [self null]].
	counting ifFalse: [^self null].
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	c := (methodCounts at: i) asInt64.
	c >= jitThreshold ifTrue: [^self compileAndInstall: m].
	c < 65535 ifTrue: [methodCounts at: i put: (c + 1) asUInt16].
	^self null
!
cacheCodeFor: m
	"What a method cache entry for m remembers (CacheEntry code): its header, 1 to count its activations, 0 if it is never compiled."
	<c: 'uint64_t jit_cache_code(oop m)'>
	| h |
	jitMode = JIT_NONE ifTrue: [^0].
	h := self lookup: m.
	h isNull ifTrue: [^1].
	^(self hasCode: h) ifTrue: [self cCoerce: (self best: h) to: 'uint64_t'] ifFalse: [0]
!
best: h
	"h's method's optimized code if it has some that may run, else h."
	| o |
	h opt = 0 ifTrue: [^h].
	o := self cCoerce: h opt to: 'JitMethod *'.
	((self hasCode: o) and: [(o flags bitAnd: JM_DEAD) = 0]) ifTrue: [^o].
	^h
!
isOptFrame: f
	"f runs optimized code (its pc is a safepoint, its slots are the optimizer's)."
	^(self isCode: f code) and: [(self cCoerce: f code to: 'JitMethod *') mode = JIT_OPT]
!
tableAt: i
	^methodTable at: i
!
isPerform: e
	^(e kind bitAnd: K_PRIM) ~= 0 and: [e prim = performFn or: [e prim = performArgsFn]]
!
sendPushed: n
	sendPushed := n
!
kConst
	^K_CONST
!
kQuick
	^K_QUICK
!
kSetter
	^K_SETTER
!
kCtx
	^K_CTX
!
frameCodeFor: m
	"Frame code of a new activation of m (a block's frame: its home method)."
	jitMode = JIT_NONE ifTrue: [^0 asUInt64].
	^self blockCodeFor: m
!
frameCodeFor: m block: startpc
	"Frame code of a new activation of m's block at startpc: its optimized code if it has some, else its home method's."
	jitMode = JIT_NONE ifTrue: [^0 asUInt64].
	jitMode = JIT_OPT ifTrue: [^optimizer blockCodeFor: m start: startpc].
	^self blockCodeFor: m
!
blockCodeFor: m
	<c: 'uint64_t jit_block_code(oop m)'>
	| h |
	h := self lookup: m.
	(self hasCode: h) ifTrue: [^self cCoerce: h to: 'uint64_t'].
	^1
!
compileAndInstall: m
	<c: 'JitMethod *jit_compile_install(oop m)'>
	| h |
	h := self compile: m mode: self lowerMode notes: self notes.
	h isNull ifTrue: [^self null].
	(self insert: h) ifFalse: [^self null].
	(self hasCode: h) ifFalse: [^self null].
	self tiering ifTrue: [optCounts at: ((self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1) put: (optimizer initialCount: m)].
	interpreter setCacheCode: (self cCoerce: h to: 'uint64_t') forMethod: m.
	^h
!
compile: m mode: md notes: wantNotes
	"Compile m with compiler md into the code cache; answer its header (flagged JM_FAILED if md cannot compile it), null if the cache is full."
	<c: 'JitMethod *jit_compile(oop m, int32_t md, bool notes)'>
	<var: #h type: 'JitMethod *'>
	| t0 start ok h err |
	self ensureOpen ifFalse: [^self null].
	t0 := scheduler nowUs.
	start := cache top.
	mapCount := 0.
	refCount := 0.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: wantNotes.
	ok := (analysis analyze: m) and: [
		md caseOf: {
			[JIT_TEMPLATE] -> [template compile: m].
			[JIT_THREADED] -> [stencil compile: m threaded: true].
			[JIT_STENCIL] -> [stencil compile: m threaded: false].
			[JIT_BASELINE] -> [baseline compile: m].
			[JIT_OPT] -> [optimizer compile: m]}
			otherwise: [false]].
	err := asm finish.
	(asm isFull: err) ifTrue: [
		asm recordNotes: false.
		cache endWritingFrom: start size: 0.
		flushPending := true.
		^self null].
	(ok and: [asm isOK: err])
		ifTrue: [h := self finish: m code: start mode: md]
		ifFalse: [
			statFailed := statFailed + 1.
			h := self failedHeaderFor: m].
	asm recordNotes: false.
	cache endWritingFrom: start size: cache top - start.
	h isNull ifTrue: [
		flushPending := true.
		^self null].
	(self hasCode: h) ifTrue: [
		statCompiled := statCompiled + 1.
		statBytecodes := statBytecodes + analysis size asUInt64.
		statCodeBytes := statCodeBytes + h codeSize].
	statCompileUs := statCompileUs + (scheduler nowUs - t0) asUInt64.
	^h
!
finish: m code: start mode: md
	"The code is at start up to asm pc: append the header, the bytecode map, the embedded references and the notes."
	<c: 'JitMethod *jit_finish(oop m, uint64_t start, int32_t md)'>
	| hdr p size n h |
	hdr := (asm pc + 7) bitClear: 7.
	n := asm noteCount.
	size := (hdr - start) + (self sizeof: 'JitMethod') + (8 * mapCount) + (4 * refCount) + (20 * n) + 8.
	md = JIT_OPT ifTrue: [size := size + optimizer extraBytes].
	md = JIT_BASELINE ifTrue: [
		size := size + baseline tablesBytes asUInt64.
		(brt canRegister: baseline oopSlotCount) ifFalse: [^self null]].
	cache limit - start < size ifTrue: [^self null].
	h := self cCoerce: hdr to: 'JitMethod *'.
	libc memset: h value: 0 size: (self sizeof: 'JitMethod').
	h method: m.
	h mode: md.
	h codeStart: start.
	h codeSize: (asm pc - start) asUInt32.
	h bytecodes: analysis size asUInt32.
	p := hdr + (self sizeof: 'JitMethod').
	h map: (self cCoerce: p to: 'uint32_t *').
	h mapCount: mapCount asUInt32.
	0 to: mapCount - 1 do: [:i |
		h map at: 2 * i put: (mapPcs at: i).
		h map at: 2 * i + 1 put: (mapOffsets at: i)].
	p := p + (8 * mapCount).
	h refs: (self cCoerce: p to: 'uint32_t *').
	h refCount: refCount asUInt32.
	0 to: refCount - 1 do: [:i | h refs at: i put: (refSites at: i)].
	p := (p + (4 * refCount) + 7) bitClear: 7.
	n > 0 ifTrue: [
		h flags: JM_NOTES.
		h noteCount: n asUInt32.
		h noteValues: (self cCoerce: p to: 'int64_t *').
		h noteTexts: (self cCoerce: p + (8 * n) to: 'uint64_t *').
		h noteOffsets: (self cCoerce: p + (16 * n) to: 'uint32_t *').
		0 to: n - 1 do: [:i |
			h noteValues at: i put: (asm noteValueAt: i).
			h noteTexts at: i put: (self cCoerce: (asm noteTextAt: i) to: 'uint64_t').
			h noteOffsets at: i put: (asm noteOffsetAt: i)].
		p := p + (20 * n)].
	md = JIT_OPT ifTrue: [p := optimizer writeExtra: h at: p].
	md = JIT_BASELINE ifTrue: [p := baseline writeTables: h at: p].
	self sortMap: h.
	h start: start + (self mapOffsetOf: h pc: (md = JIT_OPT ifTrue: [optimizer unitEntry] ifFalse: [0])).
	cache allocate: p - start.
	^h
!
sortMap: h
	"Resumption points emitted out of line come late: put the map in pc order."
	| i pc off |
	1 to: h mapCount asInt64 - 1 do: [:k |
		pc := h map at: 2 * k.
		off := h map at: 2 * k + 1.
		i := k - 1.
		[i >= 0 and: [(h map at: 2 * i) > pc]] whileTrue: [
			h map at: 2 * i + 2 put: (h map at: 2 * i).
			h map at: 2 * i + 3 put: (h map at: 2 * i + 1).
			i := i - 1].
		h map at: 2 * i + 2 put: pc.
		h map at: 2 * i + 3 put: off]
!
failedHeaderFor: m
	"A header without code: m is not compiled again until the next flush."
	<c: 'JitMethod *jit_failed_header(oop m)'>
	| hdr h |
	hdr := (cache top + 7) bitClear: 7.
	cache limit - cache top < ((self sizeof: 'JitMethod') + 8) ifTrue: [^self null].
	h := self cCoerce: hdr to: 'JitMethod *'.
	libc memset: h value: 0 size: (self sizeof: 'JitMethod').
	h method: m.
	h flags: JM_FAILED.
	cache allocate: hdr + (self sizeof: 'JitMethod') - cache top.
	^h
!
counterAddressFor: m
	"Where the lower tier counts m's entries and backward jumps toward optimization (--jit opt)."
	^self cCoerce: optCounts + ((self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1) to: 'uint64_t'
!
counterFor: m put: n
	optCounts at: ((self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1) put: n asInt32
!
noteResume: pc at: offset
	"The compiler: the interpreter may continue the frame at pc in the code at offset."
	mapCount < JIT_MAX_MAP ifTrue: [
		mapPcs at: mapCount put: pc asUInt32.
		mapOffsets at: mapCount put: offset asUInt32.
		mapCount := mapCount + 1]
!
noteReference: offset
	"The compiler: a mov:imm64: of an old object at offset (patched by full GCs and become). Answer whether there was room."
	refCount >= JIT_MAX_REFS ifTrue: [^false].
	refSites at: refCount put: offset asUInt32.
	refCount := refCount + 1.
	^true
!
mapOffsetOf: h pc: pc
	"The code offset of resumption point pc, -1 if pc is none (binary search: the map is in pc order)."
	<c: 'int64_t jit_map_offset(JitMethod *h, int64_t pc)'>
	| lo hi mid v |
	lo := 0.
	hi := h mapCount asInt64 - 1.
	[lo <= hi] whileTrue: [
		mid := (lo + hi) quo: 2.
		v := (h map at: 2 * mid) asInt64.
		v = pc ifTrue: [^(h map at: 2 * mid + 1) asInt64].
		v < pc ifTrue: [lo := mid + 1] ifFalse: [hi := mid - 1]].
	^-1
!
addressFor: f
	"Where f's machine code continues at f's ip, 0 if nowhere."
	<c: 'uint64_t jit_address_for(Frame *f)'>
	| h off |
	(self isCode: f code) ifFalse: [^0].
	h := self cCoerce: f code to: 'JitMethod *'.
	h mode = JIT_OPT ifTrue: [^optimizer resume: f].
	off := self mapOffsetOf: h pc: f ip - (interpreter methodBcs: f method).
	off < 0 ifTrue: [^0].
	^h codeStart + off asUInt64
!
kill: h
	"h's code must not run again: frames using it go back to the interpreter for good."
	<c: 'void jit_kill(JitMethod *h)'>
	| f |
	optimizer clearBlockCalls.
	cache beginWriting.
	h method: memory nilOop.
	h flags: (h flags bitOr: JM_DEAD).
	cache endWriting.
	h mode ~= JIT_OPT ifTrue: [
		0 to: interpreter nframes - 1 do: [:i |
			f := interpreter frames + i.
			f code = (self cCoerce: h to: 'uint64_t') ifTrue: [f code: 0]]].
	(h opt ~= 0 and: [h mode ~= JIT_OPT]) ifTrue: [self kill: (self cCoerce: h opt to: 'JitMethod *')].
	invalidations := invalidations + 1.
	interpreter flushMethodCache.
	jitMode = JIT_BASELINE ifTrue: [brt unlinkAll]
!
methodsChanged
	"Smalltalk changed method dictionaries (flushMethodCache): inline caches relink."
	<c: 'void jit_methods_changed(void)'>
	(jitMode = JIT_BASELINE and: [cacheOpened]) ifTrue: [
		brt unlinkAll.
		brt nilTestsChanged: 0]
!
methodsChangedFor: sel
	<c: 'void jit_methods_changed_for(oop sel)'>
	(jitMode = JIT_BASELINE and: [cacheOpened]) ifTrue: [
		brt unlinkSelector: sel.
		brt nilTestsChanged: sel]
!
dropAllCode
	"Code that may be wrong now: running code leaves at its next runtime call, all code is dropped before Smalltalk goes on."
	flushPending := true.
	invalidations := invalidations + 1
!
flushCode
	"Drop all machine code (none is on the native stack): frames continue in the interpreter."
	<c: 'void jit_flush(void)'>
	0 to: interpreter nframes - 1 do: [:i | (interpreter frames + i) code: (jitMode = JIT_NONE ifTrue: [0] ifFalse: [1])].
	libc memset: methodTable value: 0 size: 8 * JIT_TABLE_SIZE.
	libc memset: methodCounts value: 0 size: 2 * JIT_TABLE_SIZE.
	tableCount := 0.
	youngCount := 0.
	youngOverflow := false.
	cacheOpened ifTrue: [cache flush].
	optimizer flushed.
	brt flushed.
	interpreter flushMethodCache.
	flushPending := false.
	statCacheFlushes := statCacheFlushes + 1
!
prepare
	"Interpreter side, no machine code on the native stack: apply a pending flush (not while optimized frames wait for callees: their metadata is in the cache)."
	(flushPending and: [self noOptFrames]) ifTrue: [self flushCode]
!
noOptFrames
	<c: 'bool jit_no_opt_frames(void)'>
	0 to: interpreter nframes - 1 do: [:i | (self isOptFrame: interpreter frames + i) ifTrue: [^false]].
	^true
! !

!JitRuntime methodsFor: 'garbage collection'!
youngRoots: fn
	"Scavenges: the methods of headers compiled while their method was young, the young objects baseline code refers to."
	<c: 'void jit_young_roots(void (*fn)(oop *))'>
	feedback youngRoots: fn.
	optimizer youngRoots: fn.
	cacheOpened ifFalse: [^self].
	cache beginWriting.
	youngOverflow
		ifTrue: [self methodRoots: fn]
		ifFalse: [0 to: youngCount - 1 do: [:i | fn call: ((youngMethods at: i) fieldAddress: #method)]].
	brt youngRoots: fn.
	cache endWriting
!
methodRoots: fn
	| h |
	0 to: JIT_TABLE_SIZE - 1 do: [:i |
		h := methodTable at: i.
		h notNull ifTrue: [fn call: (h fieldAddress: #method)]]
!
allRoots: fn
	"Full GCs and become: every header's method and every embedded reference."
	<c: 'void jit_all_roots(void (*fn)(oop *))'>
	| h r v site |
	feedback allRoots: fn.
	optimizer allRoots: fn.
	cacheOpened ifFalse: [^self].
	cache beginWriting.
	brt allRoots: fn.
	tableCount = 0 ifTrue: [^cache endWriting].
	self methodRoots: fn.
	r := self local: 'oop'.
	0 to: JIT_TABLE_SIZE - 1 do: [:i |
		h := methodTable at: i.
		(h notNull and: [h refCount > 0 and: [(h flags bitAnd: JM_DEAD) = 0]]) ifTrue: [
			0 to: h refCount asInt64 - 1 do: [:k |
				site := h codeStart + (h refs at: k).
				v := asm mov64At: site.
				r value: v.
				fn call: r.
				r value ~= v ifTrue: [
					asm patchMov64At: site value: r value.
					cache invalidate: site size: 16]]]].
	cache endWriting
!
afterGC
	"Objects moved: refresh the JitState, forget young headers whose methods are old now."
	<c: 'void jit_after_gc(void)'>
	| n |
	self refreshState.
	brt afterGC.
	n := 0.
	youngOverflow ifFalse: [
		0 to: youngCount - 1 do: [:i |
			(self isYoung: (youngMethods at: i) method) ifTrue: [
				youngMethods at: n put: (youngMethods at: i).
				n := n + 1]].
		youngCount := n asInt32]
!
optMethodsChanged: sel
	"Smalltalk changed a method dictionary (for selector sel; nil: any): optimized code relying on it is invalidated."
	<c: 'void jit_opt_methods_changed(oop sel)'>
	jitMode = JIT_OPT ifFalse: [^self].
	sel = memory nilOop
		ifTrue: [optimizer invalidateAll]
		ifFalse: [optimizer invalidateSelector: sel]
!
materializeOpt: f
	"materializeAll meets optimized frame f."
	<c: 'void jit_materialize_opt(Frame *f)'>
	optimizer materialize: f
!
becomeMethod: from
	"from is about to be replaced: if it is a compiled method, its code must not run for its successor."
	<c: 'void jit_become(oop from)'>
	| h |
	jitMode = JIT_NONE ifTrue: [^self].
	"optimized code embeds classes and methods it speculated on"
	jitMode = JIT_OPT ifTrue: [optimizer invalidateAll].
	h := self lookup: from.
	h notNull ifTrue: [self kill: h].
	(jitMode = JIT_BASELINE and: [cacheOpened]) ifTrue: [brt unlinkAll]
!
headersValid: valid
	<c: 'bool jit_headers_valid(bool (*valid)(oop))'>
	| h |
	0 to: JIT_TABLE_SIZE - 1 do: [:i |
		h := methodTable at: i.
		(h notNull and: [(valid call: h method) not]) ifTrue: [^false].
		(h notNull and: [h opt ~= 0 and: [(optimizer headerValid: (self cCoerce: h opt to: 'JitMethod *') with: valid) not]]) ifTrue: [^false]].
	^true
! !

!JitRuntime methodsFor: 'interpreter hooks'!
activated: f
	"The interpreter pushed f (top frame) for a method whose cache entry has code or counts activations."
	<c: 'void jit_activated(Frame *f)'>
	| h |
	self prepare.
	h := (self isCode: f code)
		ifTrue: [self cCoerce: f code to: 'JitMethod *']
		ifFalse: [self codeOf: f method counting: true].
	h isNull ifTrue: [
		f code: (jitMode = JIT_NONE ifTrue: [0] ifFalse: [1]).
		^self].
	f code: (self cCoerce: h to: 'uint64_t').
	self run: f at: h start
!
resume: f
	"The interpreter is about to continue f (top frame, f code a header) at f's ip."
	<c: 'void jit_resume(Frame *f)'>
	| a |
	self prepare.
	a := self addressFor: f.
	a = 0 ifTrue: [^self].
	statResumes := statResumes + 1.
	self run: f at: a
!
backJump: f
	"The interpreter jumped back in f (top frame, f code not 0): on-stack replacement."
	<c: 'void jit_back_jump(Frame *f)'>
	| n h a |
	self prepare.
	f code = 0 ifTrue: [^self].
	(self isCode: f code) ifFalse: [
		n := f code.
		n < jitOsrThreshold asUInt64 ifTrue: [
			n < JIT_MAX_COUNT ifTrue: [f code: n + 1].
			^self].
		h := self lookup: f method.
		h isNull ifTrue: [h := self compileAndInstall: f method].
		(self hasCode: h) ifFalse: [
			f code: 0.
			^self].
		f code: (self cCoerce: h to: 'uint64_t')].
	a := self addressFor: f.
	a = 0 ifTrue: [^self].
	statOsr := statOsr + 1.
	self run: f at: a
!
resumeContext: looping
	"The interpreter runs activeCtx without frames, returned into it or (looping) jumping back in it: if its method has machine code for its pc, it continues there, married to frame 0 (Interpreter>>thawFor:). A looping Context's method is compiled after --jit-osr backward jumps."
	<c: 'void jit_resume_context(bool looping)'>
	| c m h pc off f i n |
	self prepare.
	c := interpreter activeCtx.
	m := self loadRef: c at: CTX_METHOD.
	pc := self loadRef: c at: CTX_PC.
	(self isInt: pc) ifFalse: [^self].
	h := self lookup: m.
	(h isNull and: [looping]) ifTrue: [
		i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
		n := (methodCounts at: i) asInt64.
		n >= jitOsrThreshold
			ifTrue: [h := self compileAndInstall: m]
			ifFalse: [methodCounts at: i put: (n + 1) asUInt16]].
	(self hasCode: h) ifFalse: [^self].
	off := self mapOffsetOf: h pc: (self intVal: pc).
	off < 0 ifTrue: [^self].
	f := interpreter thawFor: (self cCoerce: h to: 'uint64_t').
	f isNull ifTrue: [^self].
	looping ifTrue: [statOsr := statOsr + 1] ifFalse: [statResumes := statResumes + 1].
	self run: f at: h codeStart + off asUInt64
!
run: frame at: address
	"Run machine code from address in frame (top frame, state externalized) until it leaves; on return into a frame with code continue there."
	| r f a g |
	f := frame.
	a := address.
	[statEntries := statEntries + 1.
	 jitMode = JIT_BASELINE ifTrue: [
		"baseline returns from frame 0 (into a Context) take the married frame's slow path; machine code keeps pc and sp"
		(f = interpreter frames and: [f ctx = memory nilOop]) ifTrue: [interpreter marry: f].
		f pc: 0.
		f sp: 0].
	 r := (self cCoerce: (jitMode = JIT_BASELINE ifTrue: [stubs blEnterAddress] ifFalse: [stubs enterAddress]) to: 'int64_t (*)(Frame *, uint64_t)') call: f with: a.
	 r = 0 ifTrue: [
		statExits := statExits + 1.
		^self].
	 g := self cCoerce: (r bitClear: 7) to: 'Frame *'.
	 (r bitAnd: 7) = 0 ifTrue: [
		statExits := statExits + 1.
		^interpreter syncFrame: g].
	 g sp: g sp + 1.
	 (self isOptFrame: g) ifFalse: [g pc: (g ip - (interpreter methodBcs: g method)) asInt32].
	 interpreter syncFrame: g.
	 a := self addressFor: g.
	 a = 0 ifTrue: [^self].
	 statResumes := statResumes + 1.
	 f := g] repeat
! !

!JitRuntime methodsFor: 'called by machine code'!
sync: f
	"Machine code stored f's pc and sp: f is the top frame (baseline frames suspended below it become canonical too)."
	jitMode = JIT_BASELINE ifTrue: [
		f method: (self cCoerce: f code to: 'JitMethod *') method.
		brt canonicalizeBelow: f].
	interpreter syncFrame: f.
	f lits: (self slotsOf: (self loadRef: f method at: CM_LITERALS))
!
exitSync: f
	"The exit stub: f stored its pc and sp and leaves to the interpreter."
	<c: 'uint64_t jit_exit_sync(Frame *f)'>
	self sync: f.
	^0
!
leave: f pc: pc sp: n
	"Leave to the interpreter, which continues f at pc with n slots."
	<c: 'uint64_t jit_leave(Frame *f, int64_t pc, int64_t n)'>
	(self isOptFrame: f) ifTrue: [^optimizer leave: f after: false].
	f pc: pc asInt32.
	f sp: n asInt32.
	interpreter syncFrame: f.
	^1
!
send: f info: info site: key
	"A send at f's pc, f's sp counting receiver and arguments. info: argc | instruction length << 8 | selector << 16 (literal index, or special selector) | kind << 24 (0 a literal selector, 1 super, 2 special) | 1 << 26 if a superinstruction pushed the operands; key: the site's code address, its key in the interpreter's inline caches. Answer 0 (the result is in the receiver's slot), 1 (leave), or the callee's entry. Sends that need no frame touch the frame only if an interrupt is pending."
	<c: 'uint64_t jit_send(Frame *f, uint64_t info, uint64_t key)'>
	| n len kind base r cls e sel ns ok |
	n := (info bitAnd: 255) asInt32.
	len := ((info >> 8) bitAnd: 255) asInt32.
	kind := (info >> 24) bitAnd: 3.
	base := f fp + (f sp - n - 1).
	r := base at: 0.
	cls := kind = 1
		ifTrue: [self loadRef: (self loadRef: f method at: CM_CLASS) at: BEH_SUPERCLASS]
		ifFalse: [interpreter receiverClass: r].
	e := interpreter icacheAt: (self cCoerce: key to: 'uint8_t *').
	(e cls = cls and: [e sel = key]) ifFalse: [
		sel := kind = 2
			ifTrue: [self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: ((info >> 16) bitAnd: 255)]
			ifFalse: [f lits at: ((info >> 16) bitAnd: 255)].
		jitMode = JIT_OPT ifTrue: [feedback noteSend: f method pc: f pc class: cls].
		e := interpreter siteEntry: (self cCoerce: key to: 'uint8_t *') class: cls selector: sel.
		e isNull ifTrue: [^self leave: f pc: f pc sp: f sp - (((info >> 26) bitAnd: 1) * 2) asInt32]].
	(e kind bitAnd: (K_CONST bitOr: K_CTX)) = K_CONST ifTrue: [
		e qconst ~= 0 ifTrue: [base at: 0 put: e qconst].
		^self sent: f argc: n length: len].
	((e kind bitAnd: (K_QUICK bitOr: K_CTX)) = K_QUICK and: [n = 0 and: [(self isPtr: r) and: [r ~= interpreter activeCtx and: [(memory formatOf: r) <= F_FIXVAR and: [(self numSlots: r) > e quick asUInt32]]]]]) ifTrue: [
		base at: 0 put: (self loadRef: r at: e quick).
		^self sent: f argc: n length: len].
	((e kind bitAnd: (K_SETTER bitOr: K_CTX)) = K_SETTER and: [e nset = n and: [(self isPtr: r) and: [r ~= interpreter activeCtx and: [(self isImmutable: r) not and: [(memory formatOf: r) <= F_FIXVAR]]]]]) ifTrue: [
		ns := self numSlots: r.
		ok := true.
		0 to: n - 1 do: [:k | ok := ok and: [(e setIvar at: k) < ns]].
		ok ifTrue: [
			0 to: n - 1 do: [:k | self storeRef: r at: (e setIvar at: k) put: (base at: 1 + k)].
			^self sent: f argc: n length: len]].
	self sync: f.
	((e kind bitAnd: K_CTX) ~= 0 and: [self isInt: (self loadRef: r at: CTX_SENDER)]) ifTrue: [
		^self leave: f pc: f pc sp: f sp - (((info >> 26) bitAnd: 1) * 2) asInt32].
	((e kind bitAnd: K_PRIM) ~= 0 and: [e prim = performFn or: [e prim = performArgsFn]]) ifTrue: [
		^self leave: f pc: f pc sp: f sp - (((info >> 26) bitAnd: 1) * 2) asInt32].
	sendPushed := (((info >> 26) bitAnd: 1) * 2) asInt32.
	f ip: f ip + len.
	^self dispatch: e frame: f argc: n
!
leaveAfter: f pc: pc sp: n
	"Leave to the interpreter after a send completed (its result pushed)."
	(self isOptFrame: f) ifTrue: [^optimizer leave: f after: true].
	^self leave: f pc: pc sp: n
!
sent: f argc: n length: len
	"A send completed without a frame: a safepoint, as in the interpreter."
	<c: 'uint64_t jit_sent(Frame *f, int32_t n, int32_t len)'>
	stateBlock interrupt = 0 ifTrue: [^0].
	f pc: f pc + len.
	f sp: f sp - n.
	^self interrupt: f
!
special: f info: info site: key
	"A special selector (A0-BF, or the operation of a superinstruction; info and key as for send:info:site:) whose inline path did not apply; its operands are in their slots."
	<c: 'uint64_t jit_special(Frame *f, uint64_t info, uint64_t key)'>
	| k n len base r flushes |
	n := (info bitAnd: 255) asInt32.
	len := ((info >> 8) bitAnd: 255) asInt32.
	k := ((info >> 16) bitAnd: 255) asInt32.
	base := f fp + (f sp - n - 1).
	jitMode = JIT_OPT ifTrue: [feedback noteSend: f method pc: f pc class: (interpreter receiverClass: (base at: 0))].
	r := self specialFast: k base: base.
	r ~= 0 ifTrue: [
		base at: 0 put: r.
		^0].
	((k = 21 or: [k = 22 or: [k = 30]]) and: [(self isPtr: (base at: 0)) and: [(self rawClass: (base at: 0)) = memory clsBlock and: [(self loadRef: (base at: 0) at: BC_NUMARGS) = (self intOop: n)]]]) ifTrue: [
		self sync: f.
		f ip: f ip + len.
		flushes := interpreter statFlushes.
		interpreter activateBlock: n.
		interpreter statFlushes ~= flushes ifTrue: [^1].
		^self entryOfTop].
	^self send: f info: info site: key
!
specialFast: k base: base
	"The interpreter's fast paths of special selector k with receiver and arguments at base: the result, or 0."
	<c: 'oop jit_special_fast(int32_t k, oop *base)'>
	| a b x y c i v fx fy |
	a := base at: 0.
	b := base at: 1.
	k = 19 ifTrue: [^self bool: a = b].
	k = 20 ifTrue: [^self bool: a ~= b].
	k = 29 ifTrue: [^memory classOf: a].
	(k = 27 or: [k = 28]) ifTrue: [
		((self isPtr: a) and: [(self rawClass: a) = memory clsPoint]) ifTrue: [^self loadRef: a at: k - 27].
		^0].
	k = 18 ifTrue: [
		(self isPtr: a) ifTrue: [
			(self rawClass: a) = memory clsArray ifTrue: [^self intOop: (self numSlots: a)].
			((self rawClass: a) = memory clsBytestring or: [(self rawClass: a) = memory clsBytearray]) ifTrue: [^self intOop: (memory byteSize: a) asInt64]].
		^0].
	k = 16 ifTrue: [
		((self isInt: b) and: [self isPtr: a]) ifTrue: [
			i := ((self intVal: b) - 1) asUInt64.
			((self rawClass: a) = memory clsArray and: [i < (self numSlots: a)]) ifTrue: [^self loadRef: a at: i].
			((self rawClass: a) = memory clsBytestring and: [i < (memory byteSize: a)]) ifTrue: [^self charOop: ((self bytesOf: a) at: i)].
			((self rawClass: a) = memory clsBytearray and: [i < (memory byteSize: a)]) ifTrue: [^self intOop: ((self bytesOf: a) at: i)]].
		^0].
	k = 17 ifTrue: [
		v := base at: 2.
		((self isInt: b) and: [(self isPtr: a) and: [(self isImmutable: a) not]]) ifTrue: [
			i := ((self intVal: b) - 1) asUInt64.
			((self rawClass: a) = memory clsArray and: [i < (self numSlots: a)]) ifTrue: [
				self storeRef: a at: i put: v.
				^v].
			((self rawClass: a) = memory clsBytestring and: [(self isChar: v) and: [(self charVal: v) < 256 and: [i < (memory byteSize: a)]]]) ifTrue: [
				(self bytesOf: a) at: i put: (self charVal: v) asUInt8.
				^v].
			((self rawClass: a) = memory clsBytearray and: [(self isInt: v) and: [(self intVal: v) asUInt64 < 256 and: [i < (memory byteSize: a)]]]) ifTrue: [
				(self bytesOf: a) at: i put: (self intVal: v) asUInt8.
				^v]].
		^0].
	(k > 15 or: [k = 11]) ifTrue: [^0].
	(self isInt: (a bitAnd: b)) ifTrue: [
		x := self intVal: a.
		y := self intVal: b.
		k = 0 ifTrue: [x ifNoOverflowAdd: y do: [:r | (self intFits: r) ifTrue: [^self intOop: r]]. ^0].
		k = 1 ifTrue: [x ifNoOverflowSub: y do: [:r | (self intFits: r) ifTrue: [^self intOop: r]]. ^0].
		(k >= 2 and: [k <= 7]) ifTrue: [
			c := k = 2 ifTrue: [x < y] ifFalse: [
				k = 3 ifTrue: [x > y] ifFalse: [
					k = 4 ifTrue: [x <= y] ifFalse: [
						k = 5 ifTrue: [x >= y] ifFalse: [
							k = 6 ifTrue: [x = y] ifFalse: [x ~= y]]]]].
			^self bool: c].
		k = 8 ifTrue: [x ifNoOverflowMul: y do: [:r | (self intFits: r) ifTrue: [^self intOop: r]]. ^0].
		k = 9 ifTrue: [
			(y ~= 0 and: [(x rem: y) = 0 and: [self intFits: (x quo: y)]]) ifTrue: [^self intOop: (x quo: y)].
			^0].
		k = 10 ifTrue: [
			y ~= 0 ifTrue: [^self intOop: (interpreter floorMod: x by: y)].
			^0].
		k = 13 ifTrue: [
			(y ~= 0 and: [self intFits: (interpreter floorDiv: x by: y)]) ifTrue: [^self intOop: (interpreter floorDiv: x by: y)].
			^0].
		k = 12 ifTrue: [
			y >= 0 ifTrue: [
				(y < 62 and: [(self intFits: (x asUInt64 << y) asInt64) and: [((x asUInt64 << y) asInt64 >> y) = x]]) ifTrue: [^self intOop: (x asUInt64 << y) asInt64].
				x = 0 ifTrue: [^a].
				^0].
			^self intOop: (y <= -63 ifTrue: [x < 0 ifTrue: [-1] ifFalse: [0]] ifFalse: [x >> y negated])].
		k = 14 ifTrue: [^a bitAnd: b].
		k = 15 ifTrue: [^a bitOr: b].
		^0].
	k > 9 ifTrue: [^0].
	(interpreter isFloatPair: a and: b) ifFalse: [^0].
	fx := interpreter numVal: a.
	fy := interpreter numVal: b.
	(k >= 2 and: [k <= 7]) ifTrue: [
		c := k = 2 ifTrue: [fx < fy] ifFalse: [
			k = 3 ifTrue: [fx > fy] ifFalse: [
				k = 4 ifTrue: [fx <= fy] ifFalse: [
					k = 5 ifTrue: [fx >= fy] ifFalse: [
						k = 6 ifTrue: [fx = fy] ifFalse: [fx ~= fy]]]]].
		^self bool: c].
	k = 0 ifTrue: [^interpreter floatImm: fx + fy].
	k = 1 ifTrue: [^interpreter floatImm: fx - fy].
	k = 8 ifTrue: [^interpreter floatImm: fx * fy].
	(k = 9 and: [fy ~= 0.0]) ifTrue: [^interpreter floatImm: fx / fy].
	^0
!
dispatch: e frame: f argc: n
	"f's ip is past the send, f's sp counts receiver and arguments."
	<c: 'uint64_t jit_dispatch(CacheEntry *e, Frame *f, int32_t n)'>
	| kind base m status ecode flushes inv r v ns ok g |
	kind := e kind.
	base := f fp + (f sp - n - 1).
	m := e method.
	kind = K_JIT ifTrue: [
		(self isCode: e code) ifFalse: [^self activate: m frame: f argc: n ecode: -1 code: 0].
		g := interpreter pushFrameEntry: e argc: n.
		g isNull ifTrue: [^self leave: f pc: f pc sp: f sp - sendPushed].
		^(self cCoerce: e code to: 'JitMethod *') start - JIT_PROLOGUE_BYTES].
	kind = 0 ifTrue: [^self activate: m frame: f argc: n ecode: -1 code: 0].
	(kind bitAnd: K_LEAF) ~= 0 ifTrue: [
		status := interpreter callPrimitive: e prim base: base argc: n.
		status = PS_OK ifTrue: [
			base at: 0 put: interpreter primResult.
			interpreter primResult: memory nilOop.
			^0].
		^self activate: m frame: f argc: n ecode: (self errorCodeFor: m) code: 0].
	(kind bitAnd: K_CONST) ~= 0 ifTrue: [
		e qconst ~= 0 ifTrue: [base at: 0 put: e qconst].
		^0].
	(e nset = n and: [n ~= 0]) ifTrue: [
		r := base at: 0.
		((self isPtr: r) and: [r ~= interpreter activeCtx and: [(self isImmutable: r) not and: [(memory formatOf: r) <= F_FIXVAR]]]) ifTrue: [
			ns := self numSlots: r.
			ok := true.
			0 to: n - 1 do: [:k | ok := ok and: [(e setIvar at: k) < ns]].
			ok ifTrue: [
				0 to: n - 1 do: [:k | self storeRef: r at: (e setIvar at: k) put: (base at: 1 + k)].
				^0]]].
	(e quick >= 0 and: [n = 0]) ifTrue: [
		r := base at: 0.
		((self isPtr: r) and: [r ~= interpreter activeCtx and: [(memory formatOf: r) <= F_FIXVAR and: [(self numSlots: r) > e quick asUInt32]]]) ifTrue: [
			base at: 0 put: (self loadRef: r at: e quick).
			^0]].
	(kind bitAnd: K_PRIM) = 0 ifTrue: [^self activate: m frame: f argc: n ecode: -1 code: 0].
	flushes := interpreter statFlushes.
	inv := invalidations.
	interpreter tmpRoots at: 0 put: m.
	status := interpreter callPrimitive: e prim base: base argc: n.
	m := interpreter tmpRoots at: 0.
	interpreter tmpRoots at: 0 put: memory nilOop.
	status = PS_OK ifTrue: [
		v := interpreter primResult.
		interpreter primResult: memory nilOop.
		interpreter statFlushes ~= flushes ifTrue: [
			interpreter primCommit: v.
			^1].
		base at: 0 put: v.
		inv ~= invalidations ifTrue: [^self leaveAfter: f pc: (f ip - (interpreter methodBcs: f method)) sp: f sp - n].
		^0].
	status = PS_SWITCHED ifTrue: [
		interpreter statFlushes ~= flushes ifTrue: [^1].
		interpreter nframes > ((f - interpreter frames) + 1) ifTrue: [^self entryOfTop].
		inv ~= invalidations ifTrue: [^self leaveAfter: f pc: (f ip - (interpreter methodBcs: f method)) sp: f sp].
		^0].
	status = PS_RESEND ifTrue: [self fatal: 'a resending primitive called from machine code'].
	interpreter statFlushes ~= flushes ifTrue: [self fatal: 'a failing primitive flushed the frames'].
	^self activate: m frame: f argc: n ecode: (self errorCodeFor: m) code: 0
!
errorCodeFor: m
	"The error code a failed primitive leaves in m's first temp, -1 if none."
	(interpreter primErrorCode >= 0 and: [(self intVal: (self loadRef: m at: CM_NUMTEMPS)) > 0 and: [((interpreter methodPrim: m) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0]]) ifTrue: [^interpreter primErrorCode].
	^-1
!
activate: m frame: f argc: n ecode: ecode code: hint
	"Push a frame for m (receiver and arguments at the top of f, f's ip at the continuation, its pc still at the send): answer its entry, or 1 to leave for the interpreter to run it. If the stack is full the interpreter executes the send again."
	<c: 'uint64_t jit_activate(oop m, Frame *f, int32_t n, int32_t ecode, uint64_t hint)'>
	| h g |
	h := (self isCode: hint) ifTrue: [self cCoerce: hint to: 'JitMethod *'] ifFalse: [self codeOf: m counting: true].
	g := interpreter pushFrame: m argc: n code: ((self hasCode: h) ifTrue: [self cCoerce: h to: 'uint64_t'] ifFalse: [self frameCodeFor: m]) ecode: ecode.
	g isNull ifTrue: [^self leave: f pc: f pc sp: f sp - sendPushed].
	(self hasCode: h) ifFalse: [^1].
	^h start - JIT_PROLOGUE_BYTES
!
entryOfTop
	"A frame was pushed above the caller: its entry if it has code, else 1."
	<c: 'uint64_t jit_entry_of_top(void)'>
	| top a |
	top := interpreter frames + (interpreter nframes - 1).
	a := self addressFor: top.
	a = 0 ifTrue: [^1].
	^a - JIT_PROLOGUE_BYTES
!
interrupt: f
	"An interrupt check at a method or block entry or a backward jump; f's pc and sp are where the interpreter would continue."
	<c: 'uint64_t jit_interrupt(Frame *f)'>
	| flushes inv |
	self sync: f.
	self resetStress.
	self clearInterrupt.
	flushes := interpreter statFlushes.
	inv := invalidations.
	interpreter interruptSafepoint.
	(interpreter statFlushes ~= flushes or: [inv ~= invalidations]) ifTrue: [^1].
	^0
!
closure: f
	"0x8F at f's pc: push a BlockClosure whose outerContext is f's (married) Context."
	<c: 'uint64_t jit_closure(Frame *f)'>
	| p na nt fs b bc isize s startpc |
	self sync: f.
	p := f ip.
	na := p at: 1.
	nt := p at: 2.
	fs := p at: 3.
	startpc := f pc + 6.
	interpreter marry: f.
	bc := memory clsBlock.
	isize := (self intVal: (self loadRef: bc at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	b := memory allocObj: bc format: F_FIXED slots: (isize < 5 ifTrue: [5] ifFalse: [isize]) asUInt32.
	s := self slotsOf: b.
	s at: BC_OUTER put: f ctx.
	s at: BC_STARTPC put: (self intOop: startpc).
	s at: BC_NUMARGS put: (self intOop: na).
	s at: BC_NUMTEMPS put: (self intOop: nt).
	s at: BC_FRAMESIZE put: (self intOop: fs).
	gc rememberIfOld: b.
	f fp at: f sp put: b.
	^0
!
makeArray: f
	"0x94 n at f's pc: the top n slots into a new Array."
	<c: 'uint64_t jit_make_array(Frame *f)'>
	| n a |
	self sync: f.
	n := f ip at: 1.
	a := memory allocObj: memory clsArray format: F_VAR slots: n.
	libc memcpy: (self slotsOf: a) from: f fp + f sp - n size: n asUInt64 * 8.
	gc rememberIfOld: a.
	f fp at: f sp - n put: a.
	^0
!
outerTemp: f
	"0x8A-0x8C at f's pc (does not allocate). A married Context's temps are in its frame."
	<c: 'uint64_t jit_outer_temp(Frame *f)'>
	| p op d i c k slot |
	p := (interpreter methodBcs: f method) + f pc.
	op := p at: 0.
	d := (p at: 1) asInt32.
	i := p at: 2.
	c := self loadRef: f closure at: BC_OUTER.
	[d := d - 1. d > 0] whileTrue: [c := self loadRef: (self loadRef: c at: CTX_CLOSURE) at: BC_OUTER].
	k := self loadRef: c at: CTX_SENDER.
	slot := f fp + f sp.
	(self isInt: k) ifTrue: [
		op = 16r8A
			ifTrue: [slot at: 0 put: ((interpreter frames + (self intVal: k)) fp at: i)]
			ifFalse: [(interpreter frames + (self intVal: k)) fp at: i put: (slot at: -1)].
		^0].
	op = 16r8A
		ifTrue: [slot at: 0 put: (self loadRef: c at: CTX_FIXED + i)]
		ifFalse: [self storeRef: c at: CTX_FIXED + i put: (slot at: -1)].
	^0
!
blockCallEntryFor: start index: k
	"The address of the optimizer's block call cache entry of safepoint k of the code at start."
	^optimizer blockCallsAddress + (32 * (optimizer blockCallSlot: start index: k))
!
tierUp: f loop: loop
	"The lower tier's counter for f's method ran out at f's pc (a method entry, or a backward jump if loop ~= 0; f's pc and sp stored): answer 0 to go on, 1 to leave, or where f continues in optimized code."
	<c: 'uint64_t jit_tier_up(Frame *f, int64_t loop)'>
	self sync: f.
	^optimizer tierUp: f loop: loop
!
widow: f
	"f returns and is married: its Context keeps its slots."
	<c: 'uint64_t jit_widow(Frame *f)'>
	interpreter widow: f.
	^0
!
writeBarrier: o value: v
	"v was stored into o."
	<c: 'uint64_t jit_write_barrier(oop o, oop v)'>
	((self isPtr: v) and: [(self isYoung: v) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]])
		ifTrue: [gc remember: o].
	^0
! !

!JitRuntime methodsFor: 'statistics'!
statCompiled
	^statCompiled
!
statFailed
	^statFailed
!
statBytecodes
	^statBytecodes
!
statCompileUs
	^statCompileUs
!
statCodeBytes
	^statCodeBytes
!
statCacheFlushes
	^statCacheFlushes
!
statEntries
	^statEntries
!
statExits
	^statExits
!
statResumes
	^statResumes
!
statOsr
	^statOsr
!
optStat: i
	"The optimizing tier's counters (OptRuntime>>stat:)."
	<c: 'int64_t jit_opt_stat(int32_t i)'>
	^optimizer stat: i
!
brtFeedbackSitesOf: m
	"Baseline type feedback (JitBaselineRuntime>>feedbackSitesOf: and friends) for other modules."
	^brt feedbackSitesOf: m
!
brtFeedbackPcOf: m site: i
	^brt feedbackPcOf: m site: i
!
brtFeedbackSelectorOf: m site: i
	^brt feedbackSelectorOf: m site: i
!
brtFeedbackStateOf: m site: i
	^brt feedbackStateOf: m site: i
!
brtFeedbackCasesOf: m site: i
	^brt feedbackCasesOf: m site: i
!
brtFeedbackClassOf: m site: i case: j
	^brt feedbackClassOf: m site: i case: j
!
brtFeedbackTargetOf: m site: i case: j
	^brt feedbackTargetOf: m site: i case: j
!
baselineStat: i
	"Counters of baseline code (JitBaselineRuntime): misses, links, polymorphic caches, megamorphic sites, block cache misses, C primitive calls, non-local returns, frame walks."
	<c: 'uint64_t jit_baseline_stat(int32_t i)'>
	^i caseOf: {
		[0] -> [brt statMisses]. [1] -> [brt statLinks]. [2] -> [brt statPics]. [3] -> [brt statMegas].
		[4] -> [brt statBlockMisses]. [5] -> [brt statPrimCalls]. [6] -> [brt statNlrs]}
		otherwise: [brt statWalks]
! !

VMStruct subclass: #JitState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitState comment: 'What machine code reads through x22: nil, true and false and the classes inline paths check (refreshed after every GC; tagClasses by the low 3 bits of an immediate), the interrupt flag (set with the scheduler''s, cleared by the runtime''s interrupt check), the frames array, the native stack pointer jit_enter left (exits reset it), the young space''s bounds (the store barrier). Baseline code also uses: stackLimit (a callee''s fp at or above it takes the entry''s slow path: the C stack is nearly full, or an interrupt is pending, which sets it to 0; stackLimitNormal is its value otherwise), baseFrame and baseRecord (the first Frame and native frame record of the activations since jit_enter: frame f''s record is baseRecord - (f - baseFrame) / 4), the addresses of eden''s top and limit (edenBox) and of the identity hash generator (hashBox, with its multiplier and increment), the megamorphic and block caches (JitBaselineRuntime), and words the runtime answers through (nlrFrame, nlrFp, result, ecode) or reads (primRet: where a C primitive returns to). Optimized code also uses: cstackLimit (the highest slot address a frame may use), the deoptimization stress counter, where a guard that fails saves the registers (dump: x0-x31, then d0-d31).'!

!JitState class methodsFor: 'declaring'!
fields
	^#((nilOop oop) (trueOop oop) (falseOop oop) (interrupt int32_t) (pad int32_t) (frames uint64_t) (exitSp uint64_t) (youngLo uint64_t) (youngHi uint64_t)
		(arrayClass oop) (pointClass oop)
		(stackLimit uint64_t) (stackLimitNormal uint64_t) (baseFrame uint64_t) (baseRecord uint64_t)
		(edenBox uint64_t) (hashBox uint64_t) (lcgMul uint64_t) (lcgAdd uint64_t)
		(tagClasses 'oop[8]') (blockClass oop) (byteStringClass oop) (byteArrayClass oop) (contextClass oop) (boxedFloatClass oop) (wordArrayClass oop) (byteSymbolClass oop)
		(megaCache uint64_t) (blockCache uint64_t) (nlrFrame uint64_t) (nlrFp uint64_t) (result oop) (ecode int64_t) (primRet uint64_t)
		(cstackLimit uint64_t) (stress int64_t) (dump 'uint64_t[64]'))
! !

VMStruct subclass: #JitMethod
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitMethod comment: 'The header of a compiled method, in the code cache after its code: the method (a GC root), the compiler (mode), where the code starts and how long it is, start (the method''s first bytecode, after the prologue; its entry from a compiled caller is JIT_PROLOGUE_BYTES before), the bytecode map (pc, offset pairs of the resumption points, in pc order), the offsets of embedded object references (mov:imm64:), and, if recorded, the notes for disassembly. Baseline code also has its checked and unchecked entries, its send sites (BaselineSite), its return map (return offset, pc | depth << 16, argc | length << 8 | pushes << 26) and its blocks (startpc, entry offset). flags: JM_FAILED (no code: the method is not compiled again), JM_DEAD (its code must not run), JM_NOTES A lower tier''s header links its method''s optimized code (opt); optimized code (mode opt, OptRuntime) has: lower, its frame''s slots, the method''s bytecode size, its oop pool (in the code, GC roots), the safepoint table and records, its dependencies, deoptimizations, the unit (blockStart, osrPc) and when it was compiled (generation, stamp).'!

!JitMethod class methodsFor: 'declaring'!
fields
	^#((method oop) (start uint64_t) (codeStart uint64_t) (codeSize uint32_t) (bytecodes uint32_t) (mode int32_t) (flags uint32_t)
		(mapCount uint32_t) (refCount uint32_t) (map 'uint32_t *') (refs 'uint32_t *')
		(noteCount uint32_t) (methodHash uint32_t) (noteOffsets 'uint32_t *') (noteTexts 'uint64_t *') (noteValues 'int64_t *')
		(entry uint64_t) (uentry uint64_t) (sites 'BaselineSite *') (rets 'uint32_t *') (blocks 'uint32_t *') (siteCount uint32_t) (retCount uint32_t) (blockCount uint32_t) (pad2 uint32_t)
		(opt uint64_t) (lower uint64_t) (slots uint32_t) (bcSize uint32_t) (poolOffset uint32_t) (poolCount uint32_t)
		(spCount uint32_t) (depCount uint32_t) (spTable 'int32_t *') (meta 'int32_t *') (deps 'int32_t *') (deopts uint32_t) (blockStart uint32_t) (osrPc uint32_t) (generation uint32_t) (stamp uint32_t) (pad3 uint32_t))
! !
