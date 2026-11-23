VMModule subclass: #FFIStubCompiler
	instanceVariableNames: 'asm memory publishedCount stubTargets stubKeys stubEntries'
	classVariableNames: 'FFI_STUB_BYTES FFI_STUB_LIMIT FFI_STUB_TABLE_SIZE'
	package: 'VM-Jit'!

FFIStubCompiler comment: 'Hosted adapters for fixed C signatures, excluding variadics. The caller supplies a validated target and one native word per argument; f64 words hold IEEE bits. The returned entry is process-local. Publish only on the VM thread; entries are immutable and stay live until exit, independent of CodeCache. Target and signature are cached, not authority: the caller must resolve and validate on each use.'!

!FFIStubCompiler class methodsFor: 'declaring'!
declarations
	^#((asm JitAssembler) (memory FFIStubMemory) (publishedCount uint32_t)
		(stubTargets 'uint64_t[FFI_STUB_TABLE_SIZE]') (stubKeys 'uint32_t[FFI_STUB_TABLE_SIZE]')
		(stubEntries 'uint64_t[FFI_STUB_TABLE_SIZE]'))
!
initialize
	FFI_STUB_BYTES := 256.
	FFI_STUB_LIMIT := 1024.
	FFI_STUB_TABLE_SIZE := 2 * FFI_STUB_LIMIT
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
	slot := (((target >> 4) bitXor: ((target >> 17) bitXor: ((target >> 32) bitXor: key)))
		bitAnd: FFI_STUB_TABLE_SIZE - 1) asUInt32.
	[(stubEntries at: slot) ~= 0] whileTrue: [
		((stubTargets at: slot) = target and: [(stubKeys at: slot) = key]) ifTrue: [^stubEntries at: slot].
		slot := (slot + 1) bitAnd: FFI_STUB_TABLE_SIZE - 1].
	publishedCount = FFI_STUB_LIMIT ifTrue: [^0].
	"Aligned scratch space for either encoder."
	buf := self local: 'uint32_t[64]'.
	p := self cCoerce: buf to: 'uint8_t *'.
	size := asm isX64
		ifTrue: [self encodeX64: p target: target types: types count: n result: result]
		ifFalse: [self encodeArm64: buf target: target types: types count: n result: result].
	entry := self publishCode: p size: size.
	entry ~= 0 ifTrue: [
		stubTargets at: slot put: target.
		stubKeys at: slot put: key.
		stubEntries at: slot put: entry].
	^entry
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
