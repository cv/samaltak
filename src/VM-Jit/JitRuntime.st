VMCoreModule subclass: #JitRuntime
	instanceVariableNames: 'stubs template stencil cache asm analysis jitMode jitFlags jitThreshold jitOsrThreshold jitCacheMB cacheOpened flushPending invalidations stateBlock methodTable tableCount methodCounts youngMethods youngCount youngOverflow mapPcs mapOffsets mapCount refSites refCount sendPushed performFn performArgsFn statCompiled statFailed statBytecodes statCompileUs statCodeBytes statCacheFlushes statEntries statExits statResumes statOsr'
	classVariableNames: 'JIT_FLAG_ARITH JIT_FLAG_BARRIER JIT_FLAG_EMBED JIT_FLAG_FUSE JIT_FLAG_NOTES JIT_MAX_COUNT JIT_MAX_MAP JIT_MAX_REFS JIT_MAX_YOUNG JIT_NONE JIT_PROLOGUE_BYTES JIT_STENCIL JIT_TABLE_SIZE JIT_TEMPLATE JIT_THREADED JM_DEAD JM_FAILED JM_NOTES'
	package: 'VM-Jit'!

JitRuntime comment: 'The runtime every compiler''s machine code runs on (docs/jit.md, Shared runtime): configuration (--jit, --jit-threshold, --jit-osr, --jit-flags, --jit-cache), the compiled methods (JitMethod headers in the code cache, found by the method''s identity hash; their methods are GC roots, young ones listed for scavenges; embedded object references patched by full GCs and become), the interpreter''s hooks (activated:, resume:, backJump:), the functions machine code calls (send:info:site:, special:info:site:, interrupt:, closure:, makeArray:, outerTemp:, widow:, writeBarrier:value:), code cache flushes, statistics.

Machine code runs the interpreter''s frames: x19 the Frame, x20 its slots, x21 the receiver, x22 the JitState. Before calling a function here that may allocate, collect, flush frames, switch processes or run Smalltalk, it stores the frame''s pc and sp (the bytecode it is at and the slots in use); the function makes the interpreter''s view canonical (sync:) and answers 0 to continue, 1 to leave to the interpreter (the native stack is dropped; the interpreter reloads the top frame or Context), or for a send the entry of the callee''s code (frame pushed, the caller calls it with blr). The compilers are Arm64Modules (they name registers); they ask me what they need through inline accessors.'!

!JitRuntime class methodsFor: 'declaring'!
declarations
	^#((stubs JitStubs) (template JitTemplateCompiler) (stencil JitStencilCompiler) (cache CodeCache) (asm Arm64Assembler) (analysis BytecodeAnalysis)
		(jitMode int32_t) (jitFlags uint32_t) (jitThreshold int64_t 2) (jitOsrThreshold int64_t 50) (jitCacheMB int64_t 64)
		(cacheOpened bool) (flushPending bool) (invalidations uint64_t)
		(stateBlock 'JitState[1]')
		(methodTable 'JitMethod *[JIT_TABLE_SIZE]') (tableCount int64_t) (methodCounts 'uint16_t[JIT_TABLE_SIZE]')
		(youngMethods 'JitMethod *[JIT_MAX_YOUNG]') (youngCount int32_t) (youngOverflow bool)
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
	JIT_FLAG_ARITH := 1.
	JIT_FLAG_FUSE := 2.
	JIT_FLAG_BARRIER := 4.
	JIT_FLAG_NOTES := 8.
	JIT_FLAG_EMBED := 16.
	JIT_TABLE_SIZE := 65536.
	JIT_MAX_YOUNG := 4096.
	JIT_MAX_MAP := 32768.
	JIT_MAX_REFS := 4096.
	JIT_PROLOGUE_BYTES := 20.
	JIT_MAX_COUNT := 16rFFFF.
	JM_FAILED := 1.
	JM_DEAD := 2.
	JM_NOTES := 4
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
	^-1
!
modeName: m
	<c: 'const char *jit_mode_name(int32_t m)'>
	m = JIT_TEMPLATE ifTrue: [^'template'].
	m = JIT_THREADED ifTrue: [^'threaded'].
	m = JIT_STENCIL ifTrue: [^'stencil'].
	^'none'
!
flagNamed: name length: n
	"The bit of the ablation flag called name (n bytes), 0 if there is none."
	(self is: name length: n named: 'arith') ifTrue: [^JIT_FLAG_ARITH].
	(self is: name length: n named: 'fuse') ifTrue: [^JIT_FLAG_FUSE].
	(self is: name length: n named: 'barrier') ifTrue: [^JIT_FLAG_BARRIER].
	(self is: name length: n named: 'notes') ifTrue: [^JIT_FLAG_NOTES].
	(self is: name length: n named: 'embed') ifTrue: [^JIT_FLAG_EMBED].
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
	^'embed'
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
	"Before the command line: --jit none, threshold 2, OSR after 50 backward jumps, 64 MB, flags arith fuse barrier."
	<c: 'void jit_defaults(void)'>
	jitMode := JIT_NONE.
	jitFlags := (JIT_FLAG_ARITH bitOr: JIT_FLAG_FUSE) bitOr: JIT_FLAG_BARRIER
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
	stateBlock pointClass: memory clsPoint
!
requestInterrupt
	"Any thread: machine code checks state interrupt at method entries and backward jumps."
	stateBlock interrupt: 1
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
! !

!JitRuntime methodsFor: 'compiled methods'!
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
codeResetTo: address
	"Drop code compiled from address on (for a disassembly only)."
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
	h notNull ifTrue: [^(self hasCode: h) ifTrue: [h] ifFalse: [self null]].
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
	^(self hasCode: h) ifTrue: [self cCoerce: h to: 'uint64_t'] ifFalse: [0]
!
frameCodeFor: m
	"Frame code of a new activation of m (a block's frame: its home method)."
	jitMode = JIT_NONE ifTrue: [^0 asUInt64].
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
	h := self compile: m mode: jitMode notes: self notes.
	h isNull ifTrue: [^self null].
	(self insert: h) ifFalse: [^self null].
	(self hasCode: h) ifFalse: [^self null].
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
			[JIT_STENCIL] -> [stencil compile: m threaded: false]}
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
	self sortMap: h.
	h start: start + (self mapOffsetOf: h pc: 0).
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
	off := self mapOffsetOf: h pc: f ip - (interpreter methodBcs: f method).
	off < 0 ifTrue: [^0].
	^h codeStart + off asUInt64
!
kill: h
	"h's code must not run again: frames using it go back to the interpreter for good."
	| f |
	cache beginWriting.
	h method: memory nilOop.
	h flags: (h flags bitOr: JM_DEAD).
	cache endWriting.
	0 to: interpreter nframes - 1 do: [:i |
		f := interpreter frames + i.
		f code = (self cCoerce: h to: 'uint64_t') ifTrue: [f code: 0]].
	invalidations := invalidations + 1.
	interpreter flushMethodCache
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
	interpreter flushMethodCache.
	flushPending := false.
	statCacheFlushes := statCacheFlushes + 1
!
prepare
	"Interpreter side, no machine code on the native stack: apply a pending flush."
	flushPending ifTrue: [self flushCode]
! !

!JitRuntime methodsFor: 'garbage collection'!
youngRoots: fn
	"Scavenges: the methods of headers compiled while their method was young."
	<c: 'void jit_young_roots(void (*fn)(oop *))'>
	youngOverflow ifTrue: [
		cache beginWriting.
		self methodRoots: fn.
		^cache endWriting].
	youngCount = 0 ifTrue: [^self].
	cache beginWriting.
	0 to: youngCount - 1 do: [:i | fn call: ((youngMethods at: i) fieldAddress: #method)].
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
	tableCount = 0 ifTrue: [^self].
	cache beginWriting.
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
	n := 0.
	youngOverflow ifFalse: [
		0 to: youngCount - 1 do: [:i |
			(self isYoung: (youngMethods at: i) method) ifTrue: [
				youngMethods at: n put: (youngMethods at: i).
				n := n + 1]].
		youngCount := n asInt32]
!
becomeMethod: from
	"from is about to be replaced: if it is a compiled method, its code must not run for its successor."
	<c: 'void jit_become(oop from)'>
	| h |
	jitMode = JIT_NONE ifTrue: [^self].
	h := self lookup: from.
	h notNull ifTrue: [self kill: h]
!
headersValid: valid
	<c: 'bool jit_headers_valid(bool (*valid)(oop))'>
	| h |
	0 to: JIT_TABLE_SIZE - 1 do: [:i |
		h := methodTable at: i.
		(h notNull and: [(valid call: h method) not]) ifTrue: [^false]].
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
	 r := (self cCoerce: stubs enterAddress to: 'int64_t (*)(Frame *, uint64_t)') call: f with: a.
	 r = 0 ifTrue: [
		statExits := statExits + 1.
		^self].
	 g := self cCoerce: (r bitClear: 7) to: 'Frame *'.
	 (r bitAnd: 7) = 0 ifTrue: [
		statExits := statExits + 1.
		^interpreter syncFrame: g].
	 g sp: g sp + 1.
	 g pc: (g ip - (interpreter methodBcs: g method)) asInt32.
	 interpreter syncFrame: g.
	 a := self addressFor: g.
	 a = 0 ifTrue: [^self].
	 statResumes := statResumes + 1.
	 f := g] repeat
! !

!JitRuntime methodsFor: 'called by machine code'!
sync: f
	"Machine code stored f's pc and sp: f is the top frame."
	interpreter syncFrame: f
!
leave: f pc: pc sp: n
	"Leave to the interpreter, which continues f at pc with n slots."
	<c: 'uint64_t jit_leave(Frame *f, int64_t pc, int64_t n)'>
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
		inv ~= invalidations ifTrue: [^self leave: f pc: (f ip - (interpreter methodBcs: f method)) sp: f sp - n].
		^0].
	status = PS_SWITCHED ifTrue: [
		interpreter statFlushes ~= flushes ifTrue: [^1].
		interpreter nframes > ((f - interpreter frames) + 1) ifTrue: [^self entryOfTop].
		inv ~= invalidations ifTrue: [^self leave: f pc: (f ip - (interpreter methodBcs: f method)) sp: f sp].
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
	stateBlock interrupt: 0.
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
! !

VMStruct subclass: #JitState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitState comment: 'What machine code reads through x22: nil, true and false and the classes inline paths check (refreshed after every GC), the interrupt flag (set with the scheduler''s, cleared by the runtime''s interrupt check), the frames array, the native stack pointer jit_enter left (exits reset it), the young space''s bounds (the store barrier).'!

!JitState class methodsFor: 'declaring'!
fields
	^#((nilOop oop) (trueOop oop) (falseOop oop) (interrupt int32_t) (pad int32_t) (frames uint64_t) (exitSp uint64_t) (youngLo uint64_t) (youngHi uint64_t)
		(arrayClass oop) (pointClass oop))
! !

VMStruct subclass: #JitMethod
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitMethod comment: 'The header of a compiled method, in the code cache after its code: the method (a GC root), the compiler (mode), where the code starts and how long it is, start (the method''s first bytecode, after the prologue; its entry from a compiled caller is JIT_PROLOGUE_BYTES before), the bytecode map (pc, offset pairs of the resumption points, in pc order), the offsets of embedded object references (mov:imm64:), and, if recorded, the notes for disassembly. flags: JM_FAILED (no code: the method is not compiled again), JM_DEAD (its code must not run), JM_NOTES.'!

!JitMethod class methodsFor: 'declaring'!
fields
	^#((method oop) (start uint64_t) (codeStart uint64_t) (codeSize uint32_t) (bytecodes uint32_t) (mode int32_t) (flags uint32_t)
		(mapCount uint32_t) (refCount uint32_t) (map 'uint32_t *') (refs 'uint32_t *')
		(noteCount uint32_t) (pad uint32_t) (noteOffsets 'uint32_t *') (noteTexts 'uint64_t *') (noteValues 'int64_t *'))
! !
