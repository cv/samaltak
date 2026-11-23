VMModule subclass: #FFIStubCompiler
	instanceVariableNames: 'asm memory wrapperHelpers publishedCount wrappedCount stubTargets stubKeys stubEntries'
	classVariableNames: 'FFI_STUB_BYTES FFI_STUB_LIMIT FFI_WRAPPED_BYTES FFI_WRAPPED_LIMIT FFI_STUB_TABLE_SIZE'
	package: 'VM-Jit'!

FFIStubCompiler comment: 'Hosted launchers for fixed C signatures, excluding variadics. A wrapper validates and unboxes oops, calls the resolved target, and boxes its result. Legacy word stubs accept already marshalled arguments. Published entries are immutable and stay live until exit, independent of CodeCache. Publish only on the VM thread. The cache contains code, not authorization; callers must resolve and authorize before obtaining an entry.'!

!FFIStubCompiler class methodsFor: 'declaring'!
declarations
	^#((asm JitAssembler) (memory FFIStubMemory) (wrapperHelpers FFIWrapperHelpers)
		(publishedCount uint32_t) (wrappedCount uint32_t)
		(stubTargets 'uint64_t[FFI_STUB_TABLE_SIZE]') (stubKeys 'uint32_t[FFI_STUB_TABLE_SIZE]')
		(stubEntries 'uint64_t[FFI_STUB_TABLE_SIZE]'))
!
initialize
	FFI_STUB_BYTES := 256.
	FFI_STUB_LIMIT := 1024.
	FFI_WRAPPED_BYTES := 2048.
	FFI_WRAPPED_LIMIT := 1024.
	FFI_STUB_TABLE_SIZE := 2 * (FFI_STUB_LIMIT + FFI_WRAPPED_LIMIT)
! !

!FFIStubCompiler methodsFor: 'public'!
canPublishCode
	<export>
	<returns: 'bool'>
	^memory canMapFFIStubs
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
	slot := self stubSlotFor: target key: key.
	(stubEntries at: slot) ~= 0 ifTrue: [^stubEntries at: slot].
	publishedCount = FFI_STUB_LIMIT ifTrue: [^0].
	"Aligned scratch space for either encoder."
	buf := self local: 'uint32_t[64]'.
	p := self cCoerce: buf to: 'uint8_t *'.
	size := asm isX64
		ifTrue: [self encodeX64: p target: target types: types count: n result: result]
		ifFalse: [self encodeArm64: buf target: target types: types count: n result: result].
	entry := self publishCode: p size: size.
	entry ~= 0 ifTrue: [self rememberStub: entry target: target key: key at: slot].
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
	| key slot tag lanes buf p size entry |
	(target = 0 or: [n < 0 or: [n > 6 or: [result < 1 or: [(result > 7 and: [result ~= 11]) or: [result = 5]]]]]) ifTrue: [^0].
	(n > 0 and: [types isNull]) ifTrue: [^0].
	self canPublishCode ifFalse: [^0].
	result = 11 ifTrue: [
		(n = 2 and: [operation = 0 and: [(types at: 0) = 10 and: [(types at: 1) = 10]]]) ifFalse: [^0]].
	operation = 1 ifTrue: [
		(n = 3 and: [result = 1 and: [(types at: 0) = 5 and: [(types at: 1) = 5 and: [(types at: 2) = 4]]]]) ifFalse: [^0]
	] ifFalse: [operation = 0 ifFalse: [^0]].
	"Nonzero prefix encodes arity, result and operation; the high bit separates the word-stub namespace."
	key := (16 + (operation * 8) + result) asUInt32.
	lanes := n.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		(tag = 0 or: [tag = 7 or: [tag > 10 or: [tag = 5 and: [operation = 0]]]]) ifTrue: [^0].
		(self wrappedTwoLanes: tag) ifTrue: [lanes := lanes + 1].
		key := ((key asUInt64 << 4) bitOr: tag) asUInt32].
	lanes > 6 ifTrue: [^0].
	key := (key bitOr: 16r80000000) asUInt32.
	slot := self stubSlotFor: target key: key.
	(stubEntries at: slot) ~= 0 ifTrue: [^stubEntries at: slot].
	wrappedCount = FFI_WRAPPED_LIMIT ifTrue: [^0].
	buf := self local: 'uint32_t[512]'.
	p := self cCoerce: buf to: 'uint8_t *'.
	size := asm isX64
		ifTrue: [self encodeWrappedX64: p target: target types: types count: n result: result operation: operation]
		ifFalse: [self encodeWrappedArm64: buf target: target types: types count: n result: result operation: operation].
	(size = 0 or: [size > FFI_WRAPPED_BYTES]) ifTrue: [^0].
	entry := memory publishFFIStub: p size: size.
	entry ~= 0 ifTrue: [
		wrappedCount := wrappedCount + 1.
		self rememberStub: entry target: target key: key at: slot].
	^entry
! !

!FFIStubCompiler methodsFor: 'cache'!
stubSlotFor: target key: key
	<function>
	<var: #target type: 'uint64_t'>
	<var: #key type: 'uint32_t'>
	<returns: 'uint32_t'>
	| hash slot |
	hash := (target >> 4) bitXor: ((target >> 17) bitXor: (target >> 32)).
	hash := hash bitXor: (key bitXor: (key >> 12)).
	slot := (hash bitAnd: FFI_STUB_TABLE_SIZE - 1) asUInt32.
	[(stubEntries at: slot) ~= 0] whileTrue: [
		((stubTargets at: slot) = target and: [(stubKeys at: slot) = key]) ifTrue: [^slot].
		slot := (slot + 1) bitAnd: FFI_STUB_TABLE_SIZE - 1].
	^slot
!
rememberStub: entry target: target key: key at: slot
	stubTargets at: slot put: target.
	stubKeys at: slot put: key.
	stubEntries at: slot put: entry
! !

!FFIStubCompiler methodsFor: 'wrapper helper addresses'!
wrappedTwoLanes: tag
	^tag >= 8 and: [tag <= 10]
!
wrappedArgumentHelper: tag
	^wrapperHelpers wrappedArgumentHelper: tag
!
wrappedResultHelper: tag
	^wrapperHelpers wrappedResultHelper: tag
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
	 puts values in their final registers and spills live lanes only around
	 argument helpers. Scratch and memcmp lengths never escape the frame."
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
	<returns: 'uint32_t'>
	| p failSites failed gp fp tag helper slow done reg rex jump rejected epilogue stackBytes |
	"At most two failure sites per argument plus the two memcmp bounds."
	failSites := self local: 'uint32_t[14]'.
	failed := 0.
	gp := 0.
	fp := 0.
	"endbr64; push r12; sub rsp,80; mov r12,rdi (oop args).
	 Stack remains aligned; [rsp+0..47] are spill homes, +48 and +56
	 are helper outputs, +64 and +72 are memcmp slice lengths."
	p := self emitX64: 16r5441FA1E0FF3 asUInt64 count: 6 at: start.
	stackBytes := 80 + (((self sizeof: 'BigIntegerNativeResult') + 15) bitClear: 15) asUInt64.
	result = 11
		ifTrue: [
			p := self emitX64: ((stackBytes << 24) bitOr: 16rEC8148) count: 7 at: p. "sub rsp,imm32"
			p := self emitX64: 16rFC8949 asUInt64 count: 3 at: p]
		ifFalse: [p := self emitX64: 16rFC894950EC8348 asUInt64 count: 7 at: p].
	0 to: n - 1 do: [:i |
		tag := types at: i.
		helper := self wrappedArgumentHelper: tag.
		helper = 0 ifTrue: [^0].
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
		p := self x64WrappedSpillGP: gp fp: fp restore: false at: p.
		"mov rdi,rax; lea rsi,[rsp+48]"
		p := self emitX64: 16r3024748D48C78948 asUInt64 count: 8 at: p.
		(tag = 5 or: [self wrappedTwoLanes: tag]) ifTrue: [
			p := self emitX64: 16r3824548D48 asUInt64 count: 5 at: p]. "lea rdx,[rsp+56]"
		p := self x64WrappedCall: helper at: p.
		p := self emitX64: 16rC084 asUInt64 count: 2 at: p. "test al,al"
		p := self x64WrappedJcc: 4 at: p.
		failSites at: failed put: (p - start) asUInt32.
		failed := failed + 1.
		p := self x64WrappedSpillGP: gp fp: fp restore: true at: p.
		tag = 6 ifTrue: [
			p := self x64WrappedXMM: fp offset: 48 restore: true at: p.
			fp := fp + 1
		] ifFalse: [
			tag <= 2
				ifTrue: [p := self emitX64: 16r3024448B asUInt64 count: 4 at: p] "mov eax,[rsp+48]"
				ifFalse: [p := self emitX64: 16r3024448B48 asUInt64 count: 5 at: p]. "mov rax,[rsp+48]"
			tag <= 4 ifTrue: [self x64WrappedPatch: done to: p].
			reg := self x64WrappedGP: gp.
			rex := (tag <= 2 ifTrue: [16r40] ifFalse: [16r48]) + (reg >> 3).
			"mov final GP lane, eax/rax"
			p := self emitX64: (16rC08900 asUInt64 + rex asUInt64 + ((reg bitAnd: 7) asUInt64 << 16)) count: 3 at: p.
			gp := gp + 1.
			(self wrappedTwoLanes: tag) ifTrue: [
				p := self x64WrappedGP: (self x64WrappedGP: gp) offset: 56 restore: true at: p.
				gp := gp + 1].
			tag = 5 ifTrue: [
				"Save the validated slice length (not an argument)."
				p := self x64WrappedGP: 10 offset: 56 restore: true at: p.
				p := self x64WrappedGP: 10 offset: 64 + (i * 8) restore: false at: p]]].
	operation = 1 ifTrue: [
		"cmp rdx,[rsp+64/72]; ja reject"
		0 to: 1 do: [:i |
			p := self emitX64: (16r4024543B48 asUInt64 + (i asUInt64 << 35)) count: 5 at: p.
			p := self x64WrappedJcc: 7 at: p.
			failSites at: failed put: (p - start) asUInt32.
			failed := failed + 1]].
	result = 11 ifTrue: [
		"Exact two-magnitude signature: the hidden fifth GP argument is r8."
		p := self emitX64: 16r5024448D4C asUInt64 count: 5 at: p].
	p := self x64WrappedCall: target at: p.
	result = 11
		ifTrue: [
			p := self emitX64: 16r50247C8D48 asUInt64 count: 5 at: p. "lea rdi,[rsp+80]"
			p := self x64WrappedCall: (self wrappedResultHelper: result) at: p]
		ifFalse: [p := self x64WrappedResult: result at: p].
	failed > 0 ifTrue: [
		jump := self emitX64: 16rEB asUInt64 count: 2 at: p. "jmp epilogue"
		rejected := jump.
		p := self emitX64: 16rC031 asUInt64 count: 2 at: rejected. "xor eax,eax"
		epilogue := p.
		jump at: -1 put: (epilogue - jump) asUInt8.
		0 to: failed - 1 do: [:i |
			self x64WrappedPatch: start + (failSites at: i) to: rejected]].
	"add rsp,80; pop r12; ret"
	result = 11
		ifTrue: [
			p := self emitX64: ((stackBytes << 24) bitOr: 16rC48148) count: 7 at: p.
			p := self emitX64: 16rC35C41 asUInt64 count: 3 at: p]
		ifFalse: [p := self emitX64: 16rC35C4150C48348 asUInt64 count: 7 at: p].
	^(p - start) asUInt32
!
x64WrappedCall: target at: p
	<function>
	<arch: #x86_64>
	<var: #target type: 'uint64_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| q |
	"movabs r11,target; call r11"
	q := self emitX64: 16rBB49 asUInt64 count: 2 at: p.
	q := self emitX64: target count: 8 at: q.
	^self emitX64: 16rD3FF41 asUInt64 count: 3 at: q
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
	| rex opcode modrm |
	"mov r64,[rsp+disp8] or mov [rsp+disp8],r64"
	rex := 16r48 + ((reg bitAnd: 8) >> 1).
	opcode := restore ifTrue: [16r8B] ifFalse: [16r89].
	modrm := 16r44 + ((reg bitAnd: 7) * 8).
	^self emitX64: (16r24000000 asUInt64 + rex asUInt64 + (opcode asUInt64 << 8) + (modrm asUInt64 << 16) + (offset asUInt64 << 32)) count: 5 at: p
!
x64WrappedXMM: lane offset: offset restore: restore at: p
	<function>
	<arch: #x86_64>
	<var: #lane type: 'int32_t'>
	<var: #offset type: 'int32_t'>
	<var: #restore type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| opcode modrm |
	"movsd xmmN,[rsp+disp8] or movsd [rsp+disp8],xmmN"
	opcode := restore ifTrue: [16r10] ifFalse: [16r11].
	modrm := 16r44 + (lane * 8).
	^self emitX64: (16r2400000FF2 asUInt64 + (opcode asUInt64 << 16) + (modrm asUInt64 << 24) + (offset asUInt64 << 40)) count: 6 at: p
!
x64WrappedSpillGP: gp fp: fp restore: restore at: p
	<function>
	<arch: #x86_64>
	<var: #gp type: 'int32_t'>
	<var: #fp type: 'int32_t'>
	<var: #restore type: 'bool'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| q |
	q := p.
	0 to: gp - 1 do: [:i |
		q := self x64WrappedGP: (self x64WrappedGP: i) offset: i * 8 restore: restore at: q].
	0 to: fp - 1 do: [:i |
		q := self x64WrappedXMM: i offset: (gp + i) * 8 restore: restore at: q].
	^q
!
x64WrappedResult: result at: p
	<function>
	<arch: #x86_64>
	<var: #result type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'uint8_t *'>
	| q slow done helper |
	q := p.
	result = 1 ifTrue: [q := self emitX64: 16rC06348 asUInt64 count: 3 at: q]. "movsxd rax,eax"
	result = 2 ifTrue: [q := self emitX64: 16rC089 asUInt64 count: 2 at: q]. "mov eax,eax"
	result <= 2 ifTrue: [
		^self emitX64: 16r0100448D48 asUInt64 count: 5 at: q]. "lea rax,[rax+rax+1]"
	helper := self wrappedResultHelper: result.
	result >= 6 ifTrue: [^self x64WrappedCall: helper at: q]. "f64 is already in xmm0; void needs no input"
	"Preserve rax in rdi for the cold boxing helper."
	q := self emitX64: 16rC78948 asUInt64 count: 3 at: q. "mov rdi,rax"
	result = 3 ifTrue: [
		q := self emitX64: 16rC00148 asUInt64 count: 3 at: q. "add rax,rax"
		slow := self x64WrappedJcc: 0 at: q. "jo helper"
		q := self emitX64: 16r01C88348 asUInt64 count: 4 at: slow "or rax,1"
	] ifFalse: [
		q := self emitX64: 16r3EEFC148 asUInt64 count: 4 at: q. "shr rdi,62"
		slow := self x64WrappedJcc: 5 at: q. "jnz helper"
		q := self emitX64: 16r0100448D48 asUInt64 count: 5 at: slow]. "lea rax,[rax+rax+1]"
	done := self emitX64: 16rE9 asUInt64 count: 5 at: q. "jmp boxed"
	self x64WrappedPatch: slow to: done.
	q := done.
	result = 4 ifTrue: [q := self emitX64: 16rC78948 asUInt64 count: 3 at: q]. "mov rdi,rax"
	q := self x64WrappedCall: helper at: q.
	self x64WrappedPatch: done to: q.
	^q
! !
