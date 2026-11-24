VMModule subclass: #FFIStubCompiler
	instanceVariableNames: 'asm memory wrapperHelpers publishedCount wrappedCount stubTargets stubKeys stubKeysHigh stubEntries'
	classVariableNames: 'FFI_STUB_BYTES FFI_STUB_LIMIT FFI_WRAPPED_BYTES FFI_WRAPPED_LIMIT FFI_WRAPPED_LANES FFI_STUB_TABLE_SIZE'
	package: 'VM-Jit'!

FFIStubCompiler comment: 'Hosted launchers for fixed C signatures, excluding variadics. A wrapper validates and unboxes oops, calls the resolved target, and boxes its result. Legacy word stubs accept already marshalled arguments. Published entries are immutable and stay live until exit, independent of CodeCache. Publish only on the VM thread. The cache contains code, not authorization; callers must resolve and authorize before obtaining an entry.'!

!FFIStubCompiler class methodsFor: 'declaring'!
declarations
	^#((asm JitAssembler) (memory FFIStubMemory) (wrapperHelpers FFIWrapperHelpers)
		(publishedCount uint32_t) (wrappedCount uint32_t)
		(stubTargets 'uint64_t[FFI_STUB_TABLE_SIZE]') (stubKeys 'uint64_t[FFI_STUB_TABLE_SIZE]')
		(stubKeysHigh 'uint64_t[FFI_STUB_TABLE_SIZE]')
		(stubEntries 'uint64_t[FFI_STUB_TABLE_SIZE]'))
!
initialize
	FFI_STUB_BYTES := 256.
	FFI_STUB_LIMIT := 1024.
	FFI_WRAPPED_BYTES := 4096.
	FFI_WRAPPED_LIMIT := 1024.
	"Native argument lanes of a wrapper: a slice or magnitude takes two."
	FFI_WRAPPED_LANES := 16.
	FFI_STUB_TABLE_SIZE := 2 * (FFI_STUB_LIMIT + FFI_WRAPPED_LIMIT)
! !

!FFIStubCompiler methodsFor: 'public'!
canPublishCode
	<export>
	<returns: 'bool'>
	^memory canMapFFIStubs
!
staticCoreEntry: name signature: signature
	<function>
	<var: #name type: 'const char *'>
	<var: #signature type: 'uint32_t'>
	<returns: 'uint64_t'>
	^memory staticCoreEntry: name signature: signature
!
publishCode: bytes size: size
	"Copy a complete packet, return its entry (at least 16-byte aligned), or 0. PC-relative references must stay within the packet."
	<export>
	<var: #bytes type: 'const uint8_t *'>
	<var: #size type: 'uint32_t'>
	<returns: 'uint64_t'>
	| entry |
	(bytes isNull or: [size = 0 or: [size > FFI_STUB_BYTES or: [publishedCount = FFI_STUB_LIMIT]]]) ifTrue: [^0].
	entry := memory publishFFIStub: bytes size: size.
	entry ~= 0 ifTrue: [publishedCount := publishedCount + 1].
	^entry
!
downcall: target types: types count: n result: result
	"Answer uint64_t (*)(uint64_t *words), or 0. Tags: 1 i32, 2 u32, 3 i64, 4 u64, 5 ptr, 6 f64, 7 void."
	<export>
	<var: #target type: 'uint64_t'>
	<var: #types type: 'uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<returns: 'uint64_t'>
	| key slot tag buf p size entry |
	(target = 0 or: [n < 0 or: [n > 6 or: [result < 1 or: [result > 7]]]]) ifTrue: [^0].
	(n > 0 and: [types isNull]) ifTrue: [^0].
	self canPublishCode ifFalse: [^0].
	key := result asUInt32.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		(tag = 0 or: [tag > 6]) ifTrue: [^0].
		key := ((key asUInt64 << 3) bitOr: tag) asUInt32].
	slot := self stubSlotFor: target key: key asUInt64 high: 0.
	(stubEntries at: slot) ~= 0 ifTrue: [^stubEntries at: slot].
	publishedCount = FFI_STUB_LIMIT ifTrue: [^0].
	"Aligned scratch space for either encoder."
	buf := self local: 'uint32_t[64]'.
	p := self cCoerce: buf to: 'uint8_t *'.
	size := asm isX64
		ifTrue: [self encodeX64: p target: target types: types count: n result: result]
		ifFalse: [self encodeArm64: buf target: target types: types count: n result: result].
	entry := self publishCode: p size: size.
	entry ~= 0 ifTrue: [self rememberStub: entry target: target key: key asUInt64 high: 0 at: slot].
	^entry
!
entryFor: target argumentTags: types count: n returnTag: result operation: operation
	"Answer oop (*)(const oop *args), or 0 if no launcher can be published. The launcher returns 0 only before entering target. Consume logical tags at compilation, never at invocation."
	<export>
	<var: #target type: 'uint64_t'>
	<var: #types type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<var: #operation type: 'int32_t'>
	<returns: 'uint64_t'>
	| key keyHigh slot tag lanes buf p size entry text prepare finish |
	(target = 0 or: [n < 0 or: [n > FFI_WRAPPED_LANES]]) ifTrue: [^0].
	((result >= 1 and: [result <= 7 and: [result ~= 5]]) or: [result = 11 or: [result = 12 or: [result = 15]]]) ifFalse: [^0].
	(n > 0 and: [types isNull]) ifTrue: [^0].
	self canPublishCode ifFalse: [^0].
	text := n = 1 and: [operation = 0 and: [
		((types at: 0) = 13 and: [result = 7]) or: [(types at: 0) = 14 and: [result = 15]]]].
	(result = 15 and: [text not]) ifTrue: [^0].
	result = 11 ifTrue: [
		(n = 2 and: [operation = 0 and: [(types at: 0) = 10 and: [(types at: 1) = 10]]]) ifFalse: [^0]].
	operation = 1 ifTrue: [
		(n = 3 and: [result = 1 and: [(types at: 0) = 5 and: [(types at: 1) = 5 and: [(types at: 2) = 4]]]]) ifFalse: [^0]
	] ifFalse: [operation = 0 ifFalse: [^0]].
	"Nonzero 5-bit tags, the result's and then up to sixteen arguments', encode arity
	 in two words. Bit 62 is the operation; bit 63 separates the word-stub namespace."
	key := result asUInt64.
	keyHigh := 0 asUInt64.
	lanes := n.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		(tag = 0 or: [tag = 7 or: [(tag > 10 and: [text not]) or: [tag = 5 and: [operation = 0]]]]) ifTrue: [^0].
		(text or: [self wrappedTwoLanes: tag]) ifTrue: [lanes := lanes + 1].
		i < 11
			ifTrue: [key := key bitOr: tag asUInt64 << (5 * (i + 1))]
			ifFalse: [keyHigh := keyHigh bitOr: tag asUInt64 << (5 * (i - 11))]].
	lanes > FFI_WRAPPED_LANES ifTrue: [^0].
	key := (key bitOr: operation asUInt64 << 62) bitOr: 16r8000000000000000 asUInt64.
	slot := self stubSlotFor: target key: key high: keyHigh.
	(stubEntries at: slot) ~= 0 ifTrue: [^stubEntries at: slot].
	wrappedCount = FFI_WRAPPED_LIMIT ifTrue: [^0].
	buf := self local: 'uint32_t[1024]'.
	p := self cCoerce: buf to: 'uint8_t *'.
	text
		ifTrue: [
			prepare := wrapperHelpers textArgumentHelper: (types at: 0).
			finish := wrapperHelpers textResultHelper: result.
			size := asm isX64
				ifTrue: [self encodeTextX64: p target: target prepare: prepare finish: finish owned: result = 15]
				ifFalse: [self encodeTextArm64: buf target: target prepare: prepare finish: finish owned: result = 15]]
		ifFalse: [
			size := asm isX64
				ifTrue: [self encodeWrappedX64: p target: target types: types count: n result: result operation: operation]
				ifFalse: [self encodeWrappedArm64: buf target: target types: types count: n result: result operation: operation]].
	(size = 0 or: [size > FFI_WRAPPED_BYTES]) ifTrue: [^0].
	entry := memory publishFFIStub: p size: size.
	entry ~= 0 ifTrue: [
		wrappedCount := wrappedCount + 1.
		self rememberStub: entry target: target key: key high: keyHigh at: slot].
	^entry
! !

!FFIStubCompiler methodsFor: 'cache'!
stubSlotFor: target key: key high: keyHigh
	<function>
	<var: #target type: 'uint64_t'>
	<var: #key type: 'uint64_t'>
	<var: #keyHigh type: 'uint64_t'>
	<returns: 'uint32_t'>
	| hash slot |
	hash := (target >> 4) bitXor: ((target >> 17) bitXor: (target >> 32)).
	hash := hash bitXor: (key bitXor: ((key >> 12) bitXor: ((key >> 37) bitXor: (keyHigh bitXor: keyHigh >> 19)))).
	slot := (hash bitAnd: FFI_STUB_TABLE_SIZE - 1) asUInt32.
	[(stubEntries at: slot) ~= 0] whileTrue: [
		((stubTargets at: slot) = target and: [(stubKeys at: slot) = key and: [(stubKeysHigh at: slot) = keyHigh]]) ifTrue: [^slot].
		slot := (slot + 1) bitAnd: FFI_STUB_TABLE_SIZE - 1].
	^slot
!
rememberStub: entry target: target key: key high: keyHigh at: slot
	<var: #key type: 'uint64_t'>
	<var: #keyHigh type: 'uint64_t'>
	stubTargets at: slot put: target.
	stubKeys at: slot put: key.
	stubKeysHigh at: slot put: keyHigh.
	stubEntries at: slot put: entry
! !

!FFIStubCompiler methodsFor: 'wrapper helper addresses'!
wrappedTwoLanes: tag
	^tag >= 8 and: [tag <= 10]
!
wrappedFloatLane: tag
	^tag = 6
!
wrappedNarrowLane: tag
	"A 4-byte argument: Apple's arm64 ABI gives it a 4-byte stack slot."
	^tag <= 2
!
layoutLanes: types count: n gp: gpMax fp: fpMax packed: packed into: laneStack totals: totals
	"Give each native lane (in argument order; a two-lane tag's pointer, then its length)
	 a register (-1) or an offset in the outgoing stack area. AAPCS64 and SysV: integer
	 and floating-point lanes take their own registers in order, and once a class runs
	 out, its later lanes go to the stack in argument order. Each takes an 8-byte slot,
	 or with packed (Apple arm64) its natural size and alignment. totals gets the
	 integer and floating-point lane counts. Answer the area's size, a multiple of 16."
	<function>
	<var: #types type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #gpMax type: 'int32_t'>
	<var: #fpMax type: 'int32_t'>
	<var: #packed type: 'bool'>
	<var: #laneStack type: 'int32_t *'>
	<var: #totals type: 'int32_t *'>
	<var: #size type: 'int32_t'>
	<var: #stack type: 'int32_t'>
	<returns: 'int32_t'>
	| gp fp lane stack tag size float width |
	gp := 0.
	fp := 0.
	lane := 0.
	stack := 0.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		float := self wrappedFloatLane: tag.
		width := (self wrappedTwoLanes: tag) ifTrue: [2] ifFalse: [1].
		1 to: width do: [:k |
			(float ifTrue: [fp < fpMax] ifFalse: [gp < gpMax])
				ifTrue: [laneStack at: lane put: -1]
				ifFalse: [
					size := (packed and: [self wrappedNarrowLane: tag]) ifTrue: [4] ifFalse: [8].
					stack := (stack + size - 1) bitClear: size - 1.
					laneStack at: lane put: stack.
					stack := stack + size].
			float ifTrue: [fp := fp + 1] ifFalse: [gp := gp + 1].
			lane := lane + 1]].
	totals at: 0 put: gp.
	totals at: 1 put: fp.
	^(stack + 15) bitClear: 15
!
wrappedArgumentHelper: tag
	^wrapperHelpers wrappedArgumentHelper: tag
!
wrappedResultHelper: tag
	^wrapperHelpers wrappedResultHelper: tag
!
wrappedInlineWideResult: tag
	^tag = 3 or: [tag = 4 or: [tag = 12]]
!
wrappedTailResult: tag
	"The result already occupies the boxer's ABI lane (f64) or needs no lane (void).
	 Restoring the wrapper frame cannot clobber a live lane; the boxer can return directly."
	^tag = 6 or: [tag = 7]
! !

!FFIStubCompiler methodsFor: 'x64 SysV'!
emitX64: bits count: count at: p
	"Write unaligned little-endian instruction fragments without unaligned C stores."
	<function>
	<arch: #x86_64>
	<var: #bits type: 'uint64_t'>
	<var: #count type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	0 to: count - 1 do: [:i | p at: i put: (bits >> (i * 8)) asUInt8].
	^p + count
!
encodeX64: start target: target types: types count: n result: result
	<function>
	<arch: #x86_64>
	<var: #start type: 'uint8_t *'>
	<var: #target type: 'uint64_t'>
	<var: #types type: 'uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<returns: 'uint32_t'>
	| p gp fp tag reg rex operand |
	"endbr64; push rbp (align to 16 bytes before call); mov rbp,rsp; mov r10,rdi (words)"
	p := self emitX64: 16rFA1E0FF3 asUInt64 count: 4 at: start.
	p := self emitX64: 16r00FA8949E5894855 asUInt64 count: 7 at: p.
	gp := 0.
	fp := 0.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		tag = 6 ifTrue: [
			"movsd xmmN,[r10+disp8]"
			p := self emitX64: 16r100F41F2 asUInt64 count: 4 at: p.
			operand := 16r42 + (fp * 8).
			fp := fp + 1
		] ifFalse: [
			"Register encodings, in order: rdi,rsi,rdx,rcx,r8,r9."
			reg := ((16r981267 asUInt64 >> (gp * 4)) bitAnd: 15) asInt32.
			gp := gp + 1.
			rex := 16r41 + ((reg bitAnd: 8) quo: 2).
			operand := 16r42 + ((reg bitAnd: 7) * 8).
			"mov r32/r64,[r10+disp8]: i32/u32 use a 32-bit load."
			tag >= 3 ifTrue: [rex := rex + 8].
			p := self emitX64: (16r8B00 asUInt64 bitOr: rex asUInt64) count: 2 at: p].
		p := self emitX64: (operand + (i * 2048)) asUInt64 count: 2 at: p].
	"movabs r11,target; call r11"
	p := self emitX64: 16rBB49 asUInt64 count: 2 at: p.
	p := self emitX64: target count: 8 at: p.
	p := self emitX64: 16rD3FF41 asUInt64 count: 3 at: p.
	result = 1 ifTrue: [p := self emitX64: 16rC06348 asUInt64 count: 3 at: p]. "movsxd rax,eax"
	result = 2 ifTrue: [p := self emitX64: 16rC089 asUInt64 count: 2 at: p]. "mov eax,eax"
	result = 6 ifTrue: [p := self emitX64: 16rC07E0F4866 asUInt64 count: 5 at: p]. "movq rax,xmm0"
	result = 7 ifTrue: [p := self emitX64: 16rC031 asUInt64 count: 2 at: p]. "xor eax,eax"
	p := self emitX64: 16rC35D asUInt64 count: 2 at: p. "pop rbp; ret"
	^(p - start) asUInt32
! !

!FFIStubCompiler methodsFor: 'arm64'!
encodeArm64: buf target: target types: types count: n result: result
	<function>
	<arch: #arm64>
	<var: #buf type: 'uint32_t *'>
	<var: #target type: 'uint64_t'>
	<var: #types type: 'uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<returns: 'uint32_t'>
	| j gp fp tag insn |
	buf at: 0 put: 16rD503245F. "bti c"
	buf at: 1 put: 16rA9BF7BFD. "stp x29,x30,[sp,#-16]!!"
	buf at: 2 put: 16r910003FD. "mov x29,sp"
	buf at: 3 put: 16rAA0003E9. "mov x9,x0 (words)"
	j := 4.
	gp := 0.
	fp := 0.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		tag = 6 ifTrue: [
			insn := 16rFD400120 + (i * 1024) + fp. "ldr dN,[x9,#i*8]"
			fp := fp + 1
		] ifFalse: [
			tag <= 2
				ifTrue: [insn := 16rB9400120 + (i * 2048) + gp] "ldr wN"
				ifFalse: [insn := 16rF9400120 + (i * 1024) + gp]. "ldr xN"
			gp := gp + 1].
		buf at: j put: insn.
		j := j + 1].
	"movz x16,#lo16; movk x16,#next16,lsl #16/#32/#48; blr x16"
	buf at: j put: 16rD2800010 + ((target bitAnd: 16rFFFF) * 32).
	1 to: 3 do: [:i |
		buf at: j + i put: (16rF2800010 + (i * 2097152)) asUInt64 + (((target >> (i * 16)) bitAnd: 16rFFFF) * 32)].
	buf at: j + 4 put: 16rD63F0200.
	j := j + 5.
	insn := 0.
	result = 1 ifTrue: [insn := 16r93407C00]. "sxtw x0,w0"
	result = 2 ifTrue: [insn := 16r2A0003E0]. "mov w0,w0"
	result = 6 ifTrue: [insn := 16r9E660000]. "fmov x0,d0"
	result = 7 ifTrue: [insn := 16rAA1F03E0]. "mov x0,xzr"
	insn ~= 0 ifTrue: [
		buf at: j put: insn.
		j := j + 1].
	buf at: j put: 16rA8C17BFD. "ldp x29,x30,[sp],#16"
	buf at: j + 1 put: 16rD65F03C0. "ret"
	^(j + 2) asUInt32 * 4
! !

VMModule subclass: #FFIStubMemory
	instanceVariableNames: 'posix libc jit'
	classVariableNames: ''
	package: 'VM-Jit'!

!FFIStubMemory class methodsFor: 'declaring'!
declarations
	^#((posix Posix) (libc LibC) (jit JitPlatform))
!
isAbstractModule
	^self == FFIStubMemory
!
isInterface
	^self == FFIStubMemory
! !

!FFIStubMemory methodsFor: 'publication'!
canMapFFIStubs
	<returns: 'bool'>
	self subclassResponsibility
!
publishFFIStub: bytes size: size
	<var: #bytes type: 'const uint8_t *'>
	<var: #size type: 'uint32_t'>
	<returns: 'uint64_t'>
	self subclassResponsibility
!
packsStackArguments
	"Whether stack arguments take their natural size and alignment rather than 8-byte slots (Apple's arm64 ABI)."
	<returns: 'bool'>
	self subclassResponsibility
!
staticCoreEntry: name signature: signature
	"An exact, precompiled vm:core launcher or 0; never resolves a grant."
	<var: #name type: 'const char *'>
	<var: #signature type: 'uint32_t'>
	<returns: 'uint64_t'>
	self subclassResponsibility
! !

FFIStubMemory subclass: #DarwinFFIStubMemory
	instanceVariableNames: 'darwinPlatform cache ffiStubNext ffiStubRemaining'
	classVariableNames: ''
	package: 'VM-Jit'!

!DarwinFFIStubMemory class methodsFor: 'declaring'!
declarations
	^#((darwinPlatform DarwinJitPlatform) (cache CodeCache) (ffiStubNext 'uint8_t *') (ffiStubRemaining uint32_t))
!
targetOS
	^#darwin
! !

!DarwinFFIStubMemory methodsFor: 'publication'!
canMapFFIStubs
	<export>
	^jit canRunCode
!
packsStackArguments
	<export>
	^true
!
publishFFIStub: bytes size: size
	<export>
	| mapping entry reserved |
	self canMapFFIStubs ifFalse: [^0].
	ffiStubNext isNull ifTrue: [
		mapping := darwinPlatform ffiArenaBase.
		mapping = posix MAP_FAILED ifTrue: [^0].
		ffiStubNext := self cCoerce: mapping to: 'uint8_t *'.
		ffiStubRemaining := cache ffiArenaBytes].
	reserved := (size + 15) bitClear: 15.
	reserved > ffiStubRemaining ifTrue: [^0].
	entry := ffiStubNext.
	jit beginWriting.
	libc memcpy: entry from: bytes size: size.
	jit endWriting.
	jit invalidate: entry size: size.
	ffiStubNext := ffiStubNext + reserved.
	ffiStubRemaining := ffiStubRemaining - reserved.
	^self cCoerce: entry to: 'uint64_t'
!
staticCoreEntry: name signature: signature
	<export>
	^0
! !

FFIStubMemory subclass: #LinuxFFIStubMemory
	instanceVariableNames: 'protection'
	classVariableNames: ''
	package: 'VM-Jit'!

!LinuxFFIStubMemory class methodsFor: 'declaring'!
declarations
	^#((protection FFIStubPosix))
!
targetOS
	^#linux
!
isSimulated
	^false
! !

!LinuxFFIStubMemory methodsFor: 'publication'!
canMapFFIStubs
	<export>
	^true
!
packsStackArguments
	<export>
	^false
!
publishFFIStub: bytes size: size
	"One OS page per packet, bounded by the compiler's publication count. Never reopen a page that other threads may be executing."
	<export>
	| entry |
	entry := posix mmap: self null length: size protection: (posix PROT_READ bitOr: posix PROT_WRITE)
		flags: (posix MAP_PRIVATE bitOr: posix MAP_ANON) file: -1 offset: 0.
	entry = posix MAP_FAILED ifTrue: [^0].
	libc memcpy: entry from: bytes size: size.
	(protection protect: entry size: size flags: (posix PROT_READ bitOr: posix PROT_EXEC)) ~= 0 ifTrue: [
		posix munmap: entry length: size.
		^0].
	jit invalidate: entry size: size.
	^self cCoerce: entry to: 'uint64_t'
!
staticCoreEntry: name signature: signature
	<export>
	^0
! !

CLibrary subclass: #FFIStubPosix
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

!FFIStubPosix class methodsFor: 'declaring'!
headers
	^#('<sys/mman.h>')
!
targetOS
	^#linux
! !

!FFIStubPosix methodsFor: 'memory protection'!
protect: address size: size flags: flags
	<c: 'int mprotect(void *address, size_t size, int flags)'>
	^self error: 'not simulated'
! !

!FFIStubCompiler methodsFor: 'wrapped x64 SysV'!
encodeWrappedX64: start target: target types: types count: n result: result operation: operation
	"Called with a validated signature. Only the encoder sees tags. The launcher
	 puts register arguments in their final registers and spills live lanes only
	 around argument helpers; stack arguments go straight to their outgoing slots.
	 Scratch and memcmp lengths never escape the frame."
	<function>
	<arch: #x86_64>
	<var: #start type: 'uint8_t *'>
	<var: #target type: 'uint64_t'>
	<var: #types type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<var: #operation type: 'int32_t'>
	<var: #gp type: 'int32_t'>
	<var: #fp type: 'int32_t'>
	<var: #gpLive type: 'int32_t'>
	<var: #fpLive type: 'int32_t'>
	<var: #off type: 'int32_t'>
	<var: #homes type: 'int32_t'>
	<var: #outs type: 'int32_t'>
	<var: #integerOut type: 'int32_t'>
	<var: #frame type: 'int32_t'>
	<returns: 'uint32_t'>
	| p failSites failed gp fp gpLive fpLive tag helper slow done reg rex wideResultSlow rejected epilogue tail
		laneStack totals homes outs integerOut frame off lane |
	"At most two failure sites per argument plus the two memcmp bounds."
	failSites := self local: 'uint32_t[40]'.
	laneStack := self local: 'int32_t[FFI_WRAPPED_LANES]'.
	totals := self local: 'int32_t[2]'.
	"[rsp+0..homes) holds the outgoing stack arguments; then the register lanes'
	 spill homes (at least 48 bytes), two helper outputs and two memcmp slice
	 lengths. Entry, push r12 and a frame of 16-byte multiples keep calls aligned."
	homes := self layoutLanes: types count: n gp: 6 fp: 8 packed: false into: laneStack totals: totals.
	gpLive := (totals at: 0) < 6 ifTrue: [totals at: 0] ifFalse: [6].
	fpLive := (totals at: 1) < 8 ifTrue: [totals at: 1] ifFalse: [8].
	outs := homes + ((gpLive + fpLive) * 8 < 48 ifTrue: [48] ifFalse: [((gpLive + fpLive) * 8 + 15) bitClear: 15]).
	integerOut := outs + 32.
	frame := integerOut.
	result = 11 ifTrue: [frame := frame + (((self sizeof: 'BigIntegerNativeResult') + 15) bitClear: 15) asInt32].
	failed := 0.
	gp := 0.
	fp := 0.
	lane := 0.
	p := self emitX64: 16r5441FA1E0FF3 asUInt64 count: 6 at: start. "endbr64; push r12"
	p := self x64AdjustStack: frame add: false at: p.
	p := self emitX64: 16rFC8949 asUInt64 count: 3 at: p. "mov r12,rdi (oop args)"
	0 to: n - 1 do: [:i |
		tag := types at: i.
		helper := self wrappedArgumentHelper: tag.
		helper = 0 ifTrue: [^0].
		off := laneStack at: lane.
		"mov rax,[r12+i*8]"
		p := self emitX64: (16r24448B49 asUInt64 + (i asUInt64 << 35)) count: 5 at: p.
		done := p.
		tag <= 4 ifTrue: [
			"test al,1; jz slow; sar rax,1"
			p := self emitX64: 16r01A8 asUInt64 count: 2 at: p.
			slow := self x64WrappedJcc: 4 at: p.
			p := self emitX64: 16rF8D148 asUInt64 count: 3 at: slow.
			tag <= 2 ifTrue: [
				tag = 1
					ifTrue: [p := self emitX64: 16rD0634C asUInt64 count: 3 at: p] "movsxd r10,eax"
					ifFalse: [p := self emitX64: 16rC28941 asUInt64 count: 3 at: p]. "mov r10d,eax"
				p := self emitX64: 16rD0394C asUInt64 count: 3 at: p. "cmp rax,r10"
				p := self x64WrappedJcc: 5 at: p. "jne reject"
				failSites at: failed put: (p - start) asUInt32.
				failed := failed + 1].
			tag = 4 ifTrue: [
				p := self x64WrappedJcc: 8 at: p. "js reject; SAR set SF"
				failSites at: failed put: (p - start) asUInt32.
				failed := failed + 1].
			done := self emitX64: 16rE9 asUInt64 count: 5 at: p. "jmp merge"
			self x64WrappedPatch: slow to: done.
			p := done].
		p := self x64WrappedSpillGP: (gp < 6 ifTrue: [gp] ifFalse: [6]) fp: (fp < 8 ifTrue: [fp] ifFalse: [8]) base: homes restore: false at: p.
		p := self emitX64: 16rC78948 asUInt64 count: 3 at: p. "mov rdi,rax"
		"lea rsi,[rsp+out]: a stack double goes straight to its slot"
		p := self x64Lea: 6 offset: ((tag = 6 and: [off >= 0]) ifTrue: [off] ifFalse: [outs]) at: p.
		(tag = 5 or: [self wrappedTwoLanes: tag]) ifTrue: [
			p := self x64Lea: 2 offset: outs + 8 at: p]. "lea rdx,[rsp+out+8]"
		p := self x64WrappedCall: helper at: p.
		p := self emitX64: 16rC084 asUInt64 count: 2 at: p. "test al,al"
		p := self x64WrappedJcc: 4 at: p.
		failSites at: failed put: (p - start) asUInt32.
		failed := failed + 1.
		p := self x64WrappedSpillGP: (gp < 6 ifTrue: [gp] ifFalse: [6]) fp: (fp < 8 ifTrue: [fp] ifFalse: [8]) base: homes restore: true at: p.
		tag = 6 ifTrue: [
			off < 0 ifTrue: [p := self x64WrappedXMM: fp offset: outs restore: true at: p].
			fp := fp + 1.
			lane := lane + 1
		] ifFalse: [
			tag <= 2
				ifTrue: [p := self x64Rsp: 16r8B asUInt64 count: 1 reg: 0 offset: outs at: p] "mov eax,[rsp+out]"
				ifFalse: [p := self x64WrappedGP: 0 offset: outs restore: true at: p]. "mov rax,[rsp+out]"
			tag <= 4 ifTrue: [self x64WrappedPatch: done to: p].
			off < 0
				ifTrue: [
					reg := self x64WrappedGP: gp.
					rex := (tag <= 2 ifTrue: [16r40] ifFalse: [16r48]) + (reg >> 3).
					"mov final GP lane, eax/rax"
					p := self emitX64: (16rC08900 asUInt64 + rex asUInt64 + ((reg bitAnd: 7) asUInt64 << 16)) count: 3 at: p]
				ifFalse: [p := self x64WrappedGP: 0 offset: off restore: false at: p]. "mov [rsp+slot],rax"
			gp := gp + 1.
			lane := lane + 1.
			(self wrappedTwoLanes: tag) ifTrue: [
				off := laneStack at: lane.
				off < 0
					ifTrue: [p := self x64WrappedGP: (self x64WrappedGP: gp) offset: outs + 8 restore: true at: p]
					ifFalse: [
						p := self x64WrappedGP: 0 offset: outs + 8 restore: true at: p.
						p := self x64WrappedGP: 0 offset: off restore: false at: p].
				gp := gp + 1.
				lane := lane + 1].
			tag = 5 ifTrue: [
				"Save the validated slice length (not an argument)."
				p := self x64WrappedGP: 10 offset: outs + 8 restore: true at: p.
				p := self x64WrappedGP: 10 offset: outs + 16 + (i * 8) restore: false at: p]]].
	operation = 1 ifTrue: [
		"cmp rdx,[rsp+out+16/24]; ja reject"
		0 to: 1 do: [:i |
			p := self x64Rsp: 16r3B48 asUInt64 count: 2 reg: 2 offset: outs + 16 + (i * 8) at: p.
			p := self x64WrappedJcc: 7 at: p.
			failSites at: failed put: (p - start) asUInt32.
			failed := failed + 1]].
	result = 11 ifTrue: [
		"Exact two-magnitude signature: the hidden fifth GP argument is r8."
		p := self x64Lea: 8 offset: integerOut at: p].
	p := self x64WrappedCall: target at: p.
	wideResultSlow := self local: 'uint8_t *'.
	wideResultSlow value: self null.
	tail := self wrappedTailResult: result.
	result = 11
		ifTrue: [
			p := self x64Lea: 7 offset: integerOut at: p. "lea rdi,[rsp+integerOut]"
			p := self x64WrappedCall: (self wrappedResultHelper: result) at: p]
		ifFalse: [
			tail ifFalse: [p := self x64WrappedInlineResult: result at: p slow: wideResultSlow]].
	epilogue := p.
	p := self x64RestoreWrappedStack: frame at: p.
	p := tail
		ifTrue: [self x64WrappedTransfer: (self wrappedResultHelper: result) tail: true at: p]
		ifFalse: [self emitX64: 16rC3 asUInt64 count: 1 at: p].
	wideResultSlow value notNull ifTrue: [
		self x64WrappedPatch: wideResultSlow value to: p.
		p := self x64RestoreWrappedStack: frame at: p.
		p := self x64WrappedTransfer: (self wrappedResultHelper: result) tail: true at: p].
	failed > 0 ifTrue: [
		rejected := p.
		p := self emitX64: 16rC031 asUInt64 count: 2 at: p. "xor eax,eax"
		tail
			ifTrue: [
				p := self x64RestoreWrappedStack: frame at: p.
				p := self emitX64: 16rC3 asUInt64 count: 1 at: p]
			ifFalse: [
				p := self emitX64: 16rE9 asUInt64 count: 5 at: p. "jmp epilogue"
				self x64WrappedPatch: p to: epilogue].
		0 to: failed - 1 do: [:i |
			self x64WrappedPatch: start + (failSites at: i) to: rejected]].
	^(p - start) asUInt32
!
x64AdjustStack: bytes add: add at: p
	"sub/add rsp,imm8 or imm32"
	<function>
	<arch: #x86_64>
	<var: #bytes type: 'int32_t'>
	<var: #add type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	bytes < 128 ifTrue: [
		^self emitX64: (add ifTrue: [16rC48348] ifFalse: [16rEC8348]) asUInt64 + (bytes asUInt64 << 24) count: 4 at: p].
	^self emitX64: (add ifTrue: [16rC48148] ifFalse: [16rEC8148]) asUInt64 + (bytes asUInt64 << 24) count: 7 at: p
!
x64RestoreWrappedStack: bytes at: p
	<function>
	<arch: #x86_64>
	<var: #bytes type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	^self emitX64: 16r5C41 asUInt64 count: 2 at: (self x64AdjustStack: bytes add: true at: p) "add rsp,bytes; pop r12"
!
x64Rsp: opcode count: count reg: reg offset: offset at: p
	"opcode (count bytes, with any prefix and REX), then ModRM for reg and [rsp+offset], with an 8- or 32-bit displacement."
	<function>
	<arch: #x86_64>
	<var: #opcode type: 'uint64_t'>
	<var: #count type: 'int32_t'>
	<var: #reg type: 'int32_t'>
	<var: #offset type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| q |
	q := self emitX64: opcode count: count at: p.
	offset < 128 ifTrue: [
		^self emitX64: 16r2444 asUInt64 + ((reg bitAnd: 7) asUInt64 << 3) + (offset asUInt64 << 16) count: 3 at: q].
	^self emitX64: 16r2484 asUInt64 + ((reg bitAnd: 7) asUInt64 << 3) + (offset asUInt64 << 16) count: 6 at: q
!
x64Lea: reg offset: offset at: p
	"lea r64,[rsp+offset]"
	<function>
	<arch: #x86_64>
	<var: #reg type: 'int32_t'>
	<var: #offset type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	^self x64Rsp: 16r8D48 asUInt64 + ((reg bitAnd: 8) >> 1) asUInt64 count: 2 reg: reg offset: offset at: p
!
x64WrappedCall: target at: p
	<function>
	<arch: #x86_64>
	<var: #target type: 'uint64_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	^self x64WrappedTransfer: target tail: false at: p
!
x64WrappedTransfer: target tail: tail at: p
	<function>
	<arch: #x86_64>
	<var: #target type: 'uint64_t'>
	<var: #tail type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| q |
	"movabs r11,target; jmp/call r11"
	q := self emitX64: 16rBB49 asUInt64 count: 2 at: p.
	q := self emitX64: target count: 8 at: q.
	^self emitX64: (tail ifTrue: [16rE3FF41] ifFalse: [16rD3FF41]) asUInt64 count: 3 at: q
!
x64WrappedJcc: condition at: p
	<function>
	<arch: #x86_64>
	<var: #condition type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	^self emitX64: (16r800F asUInt64 + (condition asUInt64 << 8)) count: 6 at: p
!
x64WrappedPatch: next to: target
	<function>
	<arch: #x86_64>
	<var: #next type: 'uint8_t *'>
	<var: #target type: 'uint8_t *'>
	<returns: 'void'>
	self emitX64: (target - next) asUInt32 asUInt64 count: 4 at: next - 4
!
x64WrappedGP: lane
	<function>
	<arch: #x86_64>
	<var: #lane type: 'int32_t'>
	<returns: 'int32_t'>
	"rdi,rsi,rdx,rcx,r8,r9"
	^((16r981267 asUInt64 >> (lane * 4)) bitAnd: 15) asInt32
!
x64WrappedGP: reg offset: offset restore: restore at: p
	<function>
	<arch: #x86_64>
	<var: #reg type: 'int32_t'>
	<var: #offset type: 'int32_t'>
	<var: #restore type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| rex opcode |
	"mov r64,[rsp+offset] or mov [rsp+offset],r64"
	rex := 16r48 + ((reg bitAnd: 8) >> 1).
	opcode := restore ifTrue: [16r8B] ifFalse: [16r89].
	^self x64Rsp: rex asUInt64 + (opcode asUInt64 << 8) count: 2 reg: reg offset: offset at: p
!
x64WrappedXMM: lane offset: offset restore: restore at: p
	<function>
	<arch: #x86_64>
	<var: #lane type: 'int32_t'>
	<var: #offset type: 'int32_t'>
	<var: #restore type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| opcode |
	"movsd xmmN,[rsp+offset] or movsd [rsp+offset],xmmN"
	opcode := restore ifTrue: [16r10] ifFalse: [16r11].
	^self x64Rsp: 16r0FF2 asUInt64 + (opcode asUInt64 << 16) count: 3 reg: lane offset: offset at: p
!
x64WrappedSpillGP: gp fp: fp base: base restore: restore at: p
	"Spill or restore the first gp integer and fp floating-point register lanes at [rsp+base]."
	<function>
	<arch: #x86_64>
	<var: #gp type: 'int32_t'>
	<var: #fp type: 'int32_t'>
	<var: #base type: 'int32_t'>
	<var: #restore type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| q |
	q := p.
	0 to: gp - 1 do: [:i |
		q := self x64WrappedGP: (self x64WrappedGP: i) offset: base + (i * 8) restore: restore at: q].
	0 to: fp - 1 do: [:i |
		q := self x64WrappedXMM: i offset: base + ((gp + i) * 8) restore: restore at: q].
	^q
!
x64WrappedInlineResult: result at: p slow: slow
	<function>
	<arch: #x86_64>
	<var: #result type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<var: #slow type: 'uint8_t **'>
	<returns: 'uint8_t *'>
	| q |
	q := p.
	result = 1 ifTrue: [q := self emitX64: 16rC06348 asUInt64 count: 3 at: q]. "movsxd rax,eax"
	result = 2 ifTrue: [q := self emitX64: 16rC089 asUInt64 count: 2 at: q]. "mov eax,eax"
	result <= 2 ifTrue: [
		^self emitX64: 16r0100448D48 asUInt64 count: 5 at: q]. "lea rax,[rax+rax+1]"
	"Keep the C return in the boxer's argument lane on overflow/error."
	q := self emitX64: 16rC78948 asUInt64 count: 3 at: q. "mov rdi,rax"
	result = 3 ifTrue: [
		q := self emitX64: 16rC00148 asUInt64 count: 3 at: q. "add rax,rax"
		slow value: (self x64WrappedJcc: 0 at: q). "jo helper"
		^self emitX64: 16r01C88348 asUInt64 count: 4 at: slow value]. "or rax,1"
	q := self emitX64: 16r3EE8C148 asUInt64 count: 4 at: q. "shr rax,62 (unsigned or nonnegative)"
	slow value: (self x64WrappedJcc: 5 at: q). "jnz helper"
	^self emitX64: 16r013F448D48 asUInt64 count: 5 at: slow value "lea rax,[rdi+rdi+1]"
! !
