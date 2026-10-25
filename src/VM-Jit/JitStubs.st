JitCompiler subclass: #JitStubs
	instanceVariableNames: 'enterAddr exitSyncAddr exitPlainAddr sendStub specialStub interruptStub closureStub makeArrayStub outerTempStub widowStub barrierStub tierUpStub optSendStub optDeoptStub optDeoptReturnStub optStackFullStub optReturnStub symbolAddrs symbolNames symbolCount'
	classVariableNames: 'STUB_MAX_SYMBOLS'
	package: 'VM-Jit'!

JitStubs comment: 'The code every compiled method shares, generated into the code cache when it is opened (it survives flushes):

jit_enter(frame, address): int64_t (the interpreter''s way into machine code) saves the callee-saved registers, sets x19-x22 from frame, remembers the native stack pointer in the JitState, pushes x29/x30 as a compiled method''s prologue would and branches to address. A compiled method returning from that first activation lands back here and answers its caller''s Frame + 1. exitSync (machine code stored the frame''s pc and sp) answers the frame; exitPlain (the runtime made the state canonical) answers 0. Both reset the native stack to jit_enter''s and return to the interpreter (JitRuntime>>run:at:).

One stub per runtime function (ldr x16, =function; br x16), so that compiled code reaches it with bl; the disassembler names them.'!

!JitStubs class methodsFor: 'declaring'!
declarations
	^#((enterAddr uint64_t) (exitSyncAddr uint64_t) (exitPlainAddr uint64_t)
		(sendStub uint64_t) (specialStub uint64_t) (interruptStub uint64_t) (closureStub uint64_t) (makeArrayStub uint64_t)
		(outerTempStub uint64_t) (widowStub uint64_t) (barrierStub uint64_t) (tierUpStub uint64_t) (optSendStub uint64_t) (optDeoptStub uint64_t) (optDeoptReturnStub uint64_t) (optStackFullStub uint64_t) (optReturnStub uint64_t)
		(symbolAddrs 'uint64_t[STUB_MAX_SYMBOLS]') (symbolNames 'const char *[STUB_MAX_SYMBOLS]') (symbolCount int32_t))
!
initialize
	STUB_MAX_SYMBOLS := 32
! !

!JitStubs methodsFor: 'accessing'!
enterAddress
	^enterAddr
!
exitSyncAddress
	^exitSyncAddr
!
exitPlainAddress
	^exitPlainAddr
!
sendStub
	^sendStub
!
specialStub
	^specialStub
!
interruptStub
	^interruptStub
!
closureStub
	^closureStub
!
makeArrayStub
	^makeArrayStub
!
outerTempStub
	^outerTempStub
!
widowStub
	^widowStub
!
barrierStub
	^barrierStub
!
tierUpStub
	^tierUpStub
!
optSendStub
	^optSendStub
!
optDeoptStub
	^optDeoptStub
!
optReturnStub
	^optReturnStub
!
optDeoptReturnStub
	^optDeoptReturnStub
!
optStackFullStub
	^optStackFullStub
!
symbolCount
	^symbolCount
!
symbolAddressAt: i
	^symbolAddrs at: i
!
symbolNameAt: i
	^symbolNames at: i
! !

!JitStubs methodsFor: 'generating'!
generate
	"Generate the trampolines and stubs at the code cache's top; answer whether they fit."
	<c: 'bool jit_generate_stubs(void)'>
	| start push restore exit |
	start := cache top.
	symbolCount := 0.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: false.
	enterAddr := self symbol: 'jit_enter'.
	asm stp: X29 with: X30 base: SP preIndex: -160.
	asm mov: X29 with: SP.
	asm stp: X19 with: X20 base: SP offset: 16.
	asm stp: X21 with: X22 base: SP offset: 32.
	asm stp: X23 with: X24 base: SP offset: 48.
	asm stp: X25 with: X26 base: SP offset: 64.
	asm stp: X27 with: X28 base: SP offset: 80.
	asm stp: D8 with: D9 base: SP offset: 96.
	asm stp: D10 with: D11 base: SP offset: 112.
	asm stp: D12 with: D13 base: SP offset: 128.
	asm stp: D14 with: D15 base: SP offset: 144.
	asm mov: X19 with: X0.
	asm mov: X22 imm64: runtime stateAddress.
	asm ldr: X20 base: X19 offset: self fpOffset.
	asm ldr: X21 base: X20 offset: -8.
	asm mov: X16 with: SP.
	asm str: X16 base: X22 offset: self exitSpOffset.
	push := asm newLabel.
	restore := asm newLabel.
	exit := asm newLabel.
	asm bl: push.
	"the first activation returned: x19 is its caller's frame"
	asm orr: X0 with: X19 imm: 1.
	asm b: restore.
	asm bind: push.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm br: X1.
	exitSyncAddr := self symbol: 'exit (sync)'.
	asm mov: X0 with: X19.
	asm b: exit.
	exitPlainAddr := self symbol: 'exit'.
	asm mov: X0 imm: 0.
	asm bind: exit.
	asm ldr: X16 base: X22 offset: self exitSpOffset.
	asm mov: SP with: X16.
	asm bind: restore.
	asm ldp: D14 with: D15 base: SP offset: 144.
	asm ldp: D12 with: D13 base: SP offset: 128.
	asm ldp: D10 with: D11 base: SP offset: 112.
	asm ldp: D8 with: D9 base: SP offset: 96.
	asm ldp: X27 with: X28 base: SP offset: 80.
	asm ldp: X25 with: X26 base: SP offset: 64.
	asm ldp: X23 with: X24 base: SP offset: 48.
	asm ldp: X21 with: X22 base: SP offset: 32.
	asm ldp: X19 with: X20 base: SP offset: 16.
	asm ldp: X29 with: X30 base: SP postIndex: 160.
	asm ret.
	sendStub := self stub: runtime sendFunction named: 'send'.
	specialStub := self stub: runtime specialFunction named: 'special send'.
	interruptStub := self stub: runtime interruptFunction named: 'interrupt check'.
	closureStub := self stub: runtime closureFunction named: 'closure'.
	makeArrayStub := self stub: runtime makeArrayFunction named: 'make array'.
	outerTempStub := self stub: runtime outerTempFunction named: 'outer temp'.
	widowStub := self stub: runtime widowFunction named: 'widow'.
	barrierStub := self stub: runtime writeBarrierFunction named: 'write barrier'.
	tierUpStub := self stub: runtime tierUpFunction named: 'tier up'.
	optSendStub := self stub: runtime optSendFunction named: 'optimized send'.
	optDeoptReturnStub := self stub: runtime optDeoptReturnFunction named: 'deoptimize after a send'.
	optStackFullStub := self stub: runtime optStackFullFunction named: 'no room for the frame'.
	optDeoptStub := self dumpingStub: runtime optDeoptFunction named: 'deoptimize'.
	optReturnStub := self dumpingStub: runtime optReturnFunction named: 'return from the bottom frame'.
	asm finish = ASM_OK ifFalse: [^false].
	cache allocate: asm codeSize.
	cache endWritingFrom: start size: asm codeSize.
	^true
!
dumpingStub: fn named: name
	"Optimized code branches here with a safepoint in w17 (a guard failed, the bottom frame returns): the registers into the JitState's dump, then the runtime function fn(frame, safepoint) does the rest, then the interpreter continues."
	| a dump lit |
	a := self symbol: name.
	dump := self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #dump) to: 'int64_t'.
	asm add: X16 with: X22 imm: dump.
	0 to: 14 do: [:i | asm stp: 2 * i with: 2 * i + 1 base: X16 offset: 16 * i].
	0 to: 15 do: [:i | asm stp: D0 + (2 * i) with: D0 + (2 * i) + 1 base: X16 offset: 256 + (16 * i)].
	asm mov: X0 with: X19.
	asm mov: W1 with: W17.
	lit := asm newLabel.
	asm ldr: X16 label: lit.
	asm blr: X16.
	asm b: (asm labelAt: exitPlainAddr).
	asm bind: lit.
	asm emit64: fn.
	^a
!
symbol: name
	"The address of the next instruction, named name in disassemblies."
	symbolCount < STUB_MAX_SYMBOLS ifTrue: [
		symbolAddrs at: symbolCount put: asm pc.
		symbolNames at: symbolCount put: name.
		symbolCount := symbolCount + 1].
	^asm pc
!
stub: function named: name
	"ldr x16, =function; br x16"
	| lit a |
	a := self symbol: name.
	lit := asm newLabel.
	asm ldr: X16 label: lit.
	asm br: X16.
	asm bind: lit.
	asm emit64: function.
	^a
! !
