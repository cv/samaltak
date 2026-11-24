!FFIStubCompiler methodsFor: 'wrapped text'!
encodeTextX64: start target: target prepare: prepare finish: finish owned: owned
	<function>
	<arch: #x86_64>
	<var: #start type: 'uint8_t *'>
	<var: #target type: 'uint64_t'>
	<var: #prepare type: 'uint64_t'>
	<var: #finish type: 'uint64_t'>
	<var: #owned type: 'bool'>
	<returns: 'uint32_t'>
	| p stackBytes rejected done |
	"endbr64; stack record with call alignment; prepare(args[0], &record).
	 The record's first two fields are the final pointer and count lanes."
	stackBytes := (((self sizeof: 'FFITextBuffer') + 15) bitClear: 15) asUInt64 + 8.
	p := self emitX64: 16rFA1E0FF3 asUInt64 count: 4 at: start.
	p := self emitX64: ((stackBytes << 24) bitOr: 16rEC8148) count: 7 at: p.
	p := self emitX64: 16rE689483F8B48 asUInt64 count: 6 at: p. "mov rdi,[rdi]; mov rsi,rsp"
	p := self x64WrappedCall: prepare at: p.
	p := self emitX64: 16rC084 asUInt64 count: 2 at: p. "test al,al"
	rejected := self x64WrappedJcc: 4 at: p.
	p := self emitX64: 16r243C8B48 asUInt64 count: 4 at: rejected. "mov rdi,[rsp]"
	p := self emitX64: 16r0824748B48 asUInt64 count: 5 at: p. "mov rsi,[rsp+8]"
	owned ifTrue: [p := self emitX64: 16rE28948 asUInt64 count: 3 at: p]. "mov rdx,rsp"
	p := self x64WrappedCall: target at: p.
	p := self emitX64: 16rE78948 asUInt64 count: 3 at: p. "mov rdi,rsp"
	p := self x64WrappedCall: finish at: p.
	done := self emitX64: 16r02EB asUInt64 count: 2 at: p. "jmp over xor eax,eax"
	self x64WrappedPatch: rejected to: done.
	p := self emitX64: 16rC031 asUInt64 count: 2 at: done.
	p := self emitX64: ((stackBytes << 24) bitOr: 16rC48148) count: 7 at: p.
	p := self emitX64: 16rC3 asUInt64 count: 1 at: p.
	^(p - start) asUInt32
!
encodeTextArm64: buf target: target prepare: prepare finish: finish owned: owned
	<function>
	<arch: #arm64>
	<var: #buf type: 'uint32_t *'>
	<var: #target type: 'uint64_t'>
	<var: #prepare type: 'uint64_t'>
	<var: #finish type: 'uint64_t'>
	<var: #owned type: 'bool'>
	<returns: 'uint32_t'>
	| j stackBytes rejected |
	stackBytes := (((self sizeof: 'FFITextBuffer') + 15) bitClear: 15) asUInt32.
	buf at: 0 put: 16rD503245F. "bti c"
	buf at: 1 put: 16rA9BF7BFD. "stp x29,x30,[sp,#-16]!!"
	buf at: 2 put: 16r910003FD. "mov x29,sp"
	buf at: 3 put: 16rD10003FF + (stackBytes * 1024). "sub sp,sp,#stackBytes"
	buf at: 4 put: 16rF9400000. "ldr x0,[x0]"
	buf at: 5 put: 16r910003E1. "mov x1,sp"
	rejected := self arm64WrappedCall: prepare at: 6 into: buf.
	j := rejected + 1.
	buf at: j put: 16rA94007E0. "ldp x0,x1,[sp]"
	j := j + 1.
	owned ifTrue: [
		buf at: j put: 16r910003E2. "mov x2,sp"
		j := j + 1].
	j := self arm64WrappedCall: target at: j into: buf.
	buf at: j put: 16r910003E0. "mov x0,sp"
	j := self arm64WrappedCall: finish at: j + 1 into: buf.
	buf at: j put: 16r14000002. "b epilogue"
	self arm64WrappedBranch: 16r36000000 from: rejected to: j + 1 mask: 16r3FFF into: buf. "tbz w0,#0,rejected"
	buf at: j + 1 put: 16rAA1F03E0. "mov x0,xzr"
	buf at: j + 2 put: 16r910003FF + (stackBytes * 1024). "add sp,sp,#stackBytes"
	buf at: j + 3 put: 16rA8C17BFD. "ldp x29,x30,[sp],#16"
	buf at: j + 4 put: 16rD65F03C0. "ret"
	^(j + 5) asUInt32 * 4
! !
