!FFIStubCompiler methodsFor: '*VM-Jit'!
arm64WrappedBranch: opcode from: site to: dest mask: mask into: buf
	<function>
	<arch: #arm64>
	<var: #opcode type: 'uint32_t'>
	<var: #site type: 'int32_t'>
	<var: #dest type: 'int32_t'>
	<var: #mask type: 'uint32_t'>
	<var: #buf type: 'uint32_t *'>
	"All branches stay in the packet, with displacement relative to the instruction."
	| disp |
	disp := (dest - site) asUInt32 bitAnd: mask.
	mask = 16r3FFFFFF ifFalse: [disp := (disp asUInt64 << 5) asUInt32].
	buf at: site put: (opcode bitOr: disp)
!
arm64WrappedCall: address at: j into: buf
	<function>
	<arch: #arm64>
	<var: #address type: 'uint64_t'>
	<var: #j type: 'int32_t'>
	<var: #buf type: 'uint32_t *'>
	<returns: 'int32_t'>
	"movz/movk x16,imm16; blr x16. Neither the target nor helpers need a literal pool."
	buf at: j put: 16rD2800010 + ((address bitAnd: 16rFFFF) * 32).
	1 to: 3 do: [:i |
		buf at: j + i put: (16rF2800010 + (i * 2097152)) asUInt64 + (((address >> (i * 16)) bitAnd: 16rFFFF) * 32)].
	buf at: j + 4 put: 16rD63F0200.
	^j + 5
!
encodeWrappedArm64: buf target: target types: types count: n result: result operation: operation
	<function>
	<arch: #arm64>
	<var: #buf type: 'uint32_t *'>
	<var: #target type: 'uint64_t'>
	<var: #types type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<var: #operation type: 'int32_t'>
	<var: #j type: 'int32_t'>
	<var: #helper type: 'uint64_t'>
	<var: #rejection type: 'uint32_t'>
	<var: #resultDone type: 'int32_t'>
	<returns: 'uint32_t'>
	"oop (*)(const oop *args). Counts/tags are checked by the shared compiler.
	x19 holds args; converted args live in preserved x20..x25 and d8..d13 across
	helper calls, not a word vector. Only a helper's typed out slot (and a slice
	length) use scratch on the stack; helpers must not allocate before entry."
	| j gp fp tag gpSave fpSave fpBase localBytes gp32 reg helper slow ok rejection
		rejectSites failCount resultDone epilogue reject |
	gp := 0.
	fp := 0.
	gp32 := 0 asUInt32.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		tag = 6
			ifTrue: [fp := fp + 1]
			ifFalse: [
				tag <= 2 ifTrue: [gp32 := gp32 bitOr: (1 asUInt32 << gp)].
				gp := gp + ((self wrappedTwoLanes: tag) ifTrue: [2] ifFalse: [1])]].
	gpSave := gp + 1. "Include x19."
	operation = 1 ifTrue: [gpSave := gpSave + 2]. "x23/x24 hold memcmp bounds."
	fpBase := 16 + (gpSave * 8).
	fpSave := fp.
	localBytes := (fpBase + (fpSave * 8) + 15) bitClear: 15.
	buf at: 0 put: 16rD503245F. "bti c"
	buf at: 1 put: 16rA9BF7BFD. "stp x29,x30,[sp,#-16]!!"
	buf at: 2 put: 16r910003FD. "mov x29,sp"
	j := 3.
	n > 0 ifTrue: [
		buf at: j put: 16rD10003FF + (localBytes * 1024). "sub sp,sp,#localBytes"
		j := j + 1.
		0 to: gpSave - 1 do: [:i |
			buf at: j put: 16rF90003F3 + ((2 + i) * 1024) + i. "str x19+i,[sp,#16+i*8]"
			j := j + 1].
		0 to: fpSave - 1 do: [:i |
			buf at: j put: 16rFD0003E8 + ((fpBase quo: 8) + i * 1024) + i. "str d8+i,[sp,#fpBase+i*8]"
			j := j + 1].
		buf at: j put: 16rAA0003F3. "mov x19,x0"
		j := j + 1].
	"Keep branch sites in the emitter only. At most two per argument, plus the
	two memcmp bounds. A set of opcode bases denotes the branch widths below."
	rejectSites := self local: 'int32_t[16]'.
	failCount := 0.
	gp := 0.
	fp := 0.
	0 to: n - 1 do: [:i |
		tag := types at: i.
		helper := self wrappedArgumentHelper: tag.
		helper = 0 ifTrue: [^0].
		buf at: j put: 16rF9400260 + (i * 1024). "ldr x0,[x19,#i*8]"
		j := j + 1.
		reg := 20 + gp.
		tag <= 4 ifTrue: [
			slow := j. "tbz w0,#0,slow (not a SmallInteger)"
			buf at: j + 1 put: 16r9341FC00 + reg. "asr xReg,x0,#1"
			j := j + 2.
			tag <= 2 ifTrue: [
				rejection := (tag = 1
					ifTrue: [16r93407C09 + (reg * 32)] "sxtw x9,wReg"
					ifFalse: [16r2A0003E9 + (reg * 65536)]) asUInt32. "mov w9,wReg"
				buf at: j put: rejection.
				buf at: j + 1 put: 16rEB09001F + (reg * 32). "cmp xReg,x9"
				buf at: j + 2 put: 16r54000001. "b.ne reject"
				rejectSites at: failCount put: j + 2.
				failCount := failCount + 1.
				j := j + 3].
			tag = 4 ifTrue: [
				buf at: j put: 16rB7F80000 + reg. "tbnz xReg,#63,reject"
				rejectSites at: failCount put: j.
				failCount := failCount + 1.
				j := j + 1].
			ok := j. "b ready"
			j := j + 1.
			self arm64WrappedBranch: 16r36000000 from: slow to: j mask: 16r3FFF into: buf].
		buf at: j put: 16r910003E1. "add x1,sp,#0 (typed out slot)"
		j := j + 1.
		(tag = 5 or: [self wrappedTwoLanes: tag]) ifTrue: [
			buf at: j put: 16r910023E2. "add x2,sp,#8 (slice length out slot)"
			j := j + 1].
		j := self arm64WrappedCall: helper at: j into: buf.
		buf at: j put: 16r36000000. "tbz w0,#0,reject (C bool)"
		rejectSites at: failCount put: j.
		failCount := failCount + 1.
		j := j + 1.
		tag = 6
			ifTrue: [
				buf at: j put: 16rFD4003E8 + fp. "ldr d8+fp,[sp]"
				j := j + 1.
				fp := fp + 1]
			ifFalse: [
				buf at: j put: (tag <= 2 ifTrue: [16rB94003E0] ifFalse: [16rF94003E0]) + reg. "ldr wReg/xReg,[sp]"
				j := j + 1.
				gp := gp + 1.
				(self wrappedTwoLanes: tag) ifTrue: [
					buf at: j put: 16rF94007E0 + reg + 1. "ldr xReg+1,[sp,#8]"
					j := j + 1.
					gp := gp + 1].
				tag = 5 ifTrue: [
					buf at: j put: 16rF94007F7 + i. "ldr x23+i,[sp,#8] (memcmp only)"
					j := j + 1].
				tag <= 4 ifTrue: [
					self arm64WrappedBranch: 16r14000000 from: ok to: j mask: 16r3FFFFFF into: buf]]].
	operation = 1 ifTrue: [
		23 to: 24 do: [:bound |
			buf at: j put: 16rEB0002DF + (bound * 65536). "cmp x22,xBound (count vs length)"
			buf at: j + 1 put: 16r54000008. "b.hi reject"
			rejectSites at: failCount put: j + 1.
			failCount := failCount + 1.
			j := j + 2]].
	0 to: gp - 1 do: [:i |
		reg := 20 + i.
		buf at: j put: ((gp32 bitAnd: (1 asUInt32 << i)) ~= 0 ifTrue: [16r2A0003E0] ifFalse: [16rAA0003E0]) + (reg * 65536) + i. "mov wN,wReg / mov xN,xReg"
		j := j + 1].
	0 to: fp - 1 do: [:i |
		buf at: j put: 16r1E604100 + (i * 32) + i. "fmov dN,d8+N"
		j := j + 1].
	j := self arm64WrappedCall: target at: j into: buf.
	resultDone := -1.
	result = 1 ifTrue: [
		buf at: j put: 16r93407C00. "sxtw x0,w0"
		j := j + 1].
	result = 2 ifTrue: [
		buf at: j put: 16r2A0003E0. "mov w0,w0"
		j := j + 1].
	result >= 3 ifTrue: [
		helper := self wrappedResultHelper: result.
		helper = 0 ifTrue: [^0].
		result <= 4 ifTrue: [
			"The top two signed bits must match (unsigned: both must be zero)."
			buf at: j put: (result = 3 ifTrue: [16rCA000409] ifFalse: [16rD37EFC09]). "eor x9,x0,x0,lsl #1 / lsr x9,x0,#62"
			ok := j + 1.
			j := j + 2].
		j := self arm64WrappedCall: helper at: j into: buf.
		result <= 4 ifTrue: [
			resultDone := j. "b epilogue (helper returned a boxed oop)"
			j := j + 1.
			result = 3
				ifTrue: [self arm64WrappedBranch: 16rB6F80009 from: ok to: j mask: 16r3FFF into: buf] "tbz x9,#63"
				ifFalse: [self arm64WrappedBranch: 16rB4000009 from: ok to: j mask: 16r7FFFF into: buf]]]. "cbz x9"
	result <= 4 ifTrue: [
		buf at: j put: 16rD37FF800. "lsl x0,x0,#1"
		buf at: j + 1 put: 16r91000400. "add x0,x0,#1"
		j := j + 2].
	epilogue := j.
	resultDone >= 0 ifTrue: [
		self arm64WrappedBranch: 16r14000000 from: resultDone to: epilogue mask: 16r3FFFFFF into: buf].
	n > 0 ifTrue: [
		0 to: gpSave - 1 do: [:i |
			buf at: j put: 16rF94003F3 + ((2 + i) * 1024) + i. "ldr x19+i,[sp,#16+i*8]"
			j := j + 1].
		0 to: fpSave - 1 do: [:i |
			buf at: j put: 16rFD4003E8 + ((fpBase quo: 8) + i * 1024) + i. "ldr d8+i,[sp,#fpBase+i*8]"
			j := j + 1].
		buf at: j put: 16r910003FF + (localBytes * 1024). "add sp,sp,#localBytes"
		j := j + 1].
	buf at: j put: 16rA8C17BFD. "ldp x29,x30,[sp],#16"
	buf at: j + 1 put: 16rD65F03C0. "ret"
	j := j + 2.
	failCount > 0 ifTrue: [
		reject := j.
		buf at: j put: 16rAA1F03E0. "mov x0,xzr (only on rejection before target)"
		self arm64WrappedBranch: 16r14000000 from: j + 1 to: epilogue mask: 16r3FFFFFF into: buf.
		j := j + 2.
		0 to: failCount - 1 do: [:i |
			slow := rejectSites at: i.
			rejection := buf at: slow.
			self arm64WrappedBranch: rejection from: slow to: reject
				mask: ((rejection >> 24) = 16r54 ifTrue: [16r7FFFF] ifFalse: [16r3FFF]) asUInt32 into: buf]].
	^j asUInt32 * 4
! !
