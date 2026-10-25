JitCompiler subclass: #JitStubs
	instanceVariableNames: 'enterAddr exitSyncAddr exitPlainAddr sendStub specialStub interruptStub closureStub makeArrayStub outerTempStub widowStub barrierStub blEnter blExitSync blMiss blBlock blMega blEntrySlow blPrim blRemember blNlr blReturnSlow blBox symbolAddrs symbolNames symbolCount'
	classVariableNames: 'STUB_MAX_SYMBOLS'
	package: 'VM-Jit'!

JitStubs comment: 'The code every compiled method shares, generated into the code cache when it is opened (it survives flushes):

jit_enter(frame, address): int64_t (the interpreter''s way into machine code) saves the callee-saved registers, sets x19-x22 from frame, remembers the native stack pointer in the JitState, pushes x29/x30 as a compiled method''s prologue would and branches to address. A compiled method returning from that first activation lands back here and answers its caller''s Frame + 1. exitSync (machine code stored the frame''s pc and sp) answers the frame; exitPlain (the runtime made the state canonical) answers 0. Both reset the native stack to jit_enter''s and return to the interpreter (JitRuntime>>run:at:). Baseline code has its own of both (emitEnter:restore:; its exitSync makes the frames below canonical first).

One stub per runtime function (ldr x16, =function; br x16), so that compiled code reaches it with bl; the disassembler names them.'!

!JitStubs class methodsFor: 'declaring'!
declarations
	^#((enterAddr uint64_t) (exitSyncAddr uint64_t) (exitPlainAddr uint64_t)
		(sendStub uint64_t) (specialStub uint64_t) (interruptStub uint64_t) (closureStub uint64_t) (makeArrayStub uint64_t)
		(outerTempStub uint64_t) (widowStub uint64_t) (barrierStub uint64_t)
		(blEnter uint64_t) (blExitSync uint64_t) (blMiss uint64_t) (blBlock uint64_t) (blMega uint64_t) (blEntrySlow uint64_t) (blPrim uint64_t) (blRemember uint64_t) (blNlr uint64_t) (blReturnSlow uint64_t) (blBox uint64_t)
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
blEnterAddress
	^blEnter
!
blExitSyncAddress
	^blExitSync
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
blMissStub
	^blMiss
!
blBlockStub
	^blBlock
!
blMegaStub
	^blMega
!
blEntrySlowStub
	^blEntrySlow
!
blPrimStub
	^blPrim
!
blRememberStub
	^blRemember
!
blNlrStub
	^blNlr
!
blReturnSlowStub
	^blReturnSlow
!
blBoxStub
	^blBox
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

!JitStubs methodsFor: 'layout'!
baseFrameOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #baseFrame) to: 'int64_t'
!
baseRecordOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #baseRecord) to: 'int64_t'
!
tagClassesOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #tagClasses) to: 'int64_t'
!
megaCacheOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #megaCache) to: 'int64_t'
!
blockCacheOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #blockCache) to: 'int64_t'
!
nlrFrameOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #nlrFrame) to: 'int64_t'
!
nlrFpOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #nlrFp) to: 'int64_t'
!
resultOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #result) to: 'int64_t'
!
primRetOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #primRet) to: 'int64_t'
!
emitReloadPinned
	"Baseline code keeps nil, true and false in x23, x24, x25."
	asm ldp: X23 with: X24 base: X22 offset: self nilOffset.
	asm ldr: X25 base: X22 offset: self falseOffset
! !

!JitStubs methodsFor: 'generating'!
generate
	"Generate the trampolines and stubs at the code cache's top; answer whether they fit."
	<c: 'bool jit_generate_stubs(void)'>
	| start restore exit |
	start := cache top.
	symbolCount := 0.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: false.
	restore := asm newLabel.
	exit := asm newLabel.
	enterAddr := self symbol: 'jit_enter'.
	self emitEnter: false restore: restore.
	blEnter := self symbol: 'jit_enter (baseline)'.
	self emitEnter: true restore: restore.
	exitSyncAddr := self symbol: 'exit (sync)'.
	asm mov: X0 with: X19.
	asm b: exit.
	blExitSync := self symbol: 'exit (sync, baseline)'.
	"the frames below become canonical before the native stack goes"
	asm mov: X0 with: X19.
	asm mov: X16 imm64: runtime exitSyncFunction.
	asm blr: X16.
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
	self generateBaseline.
	asm finish = ASM_OK ifFalse: [^false].
	cache allocate: asm codeSize.
	cache endWritingFrom: start size: asm codeSize.
	^true
!
emitEnter: baseline restore: restore
	"jit_enter; baseline code also wants nil, true and false pinned, the first Frame and native record, and the first activation's result stored."
	| push |
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
	baseline ifTrue: [
		self emitReloadPinned.
		asm str: X19 base: X22 offset: self baseFrameOffset].
	asm mov: X16 with: SP.
	asm str: X16 base: X22 offset: self exitSpOffset.
	push := asm newLabel.
	asm bl: push.
	"the first activation returned: x19 is its caller's frame (baseline: x0 the result, x20 the returning frame's fp)"
	baseline ifTrue: [asm stur: X0 base: X20 offset: -8].
	asm orr: X0 with: X19 imm: 1.
	asm b: restore.
	asm bind: push.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	baseline ifTrue: [
		asm mov: X16 with: SP.
		asm str: X16 base: X22 offset: self baseRecordOffset].
	asm br: X1
!
generateBaseline
	"The baseline compiler's stubs (JitBaselineCompiler, JitBaselineRuntime)."
	| exit imm have miss lnot |
	exit := asm labelAt: exitPlainAddr.
	blMiss := self symbol: 'baseline miss'.
	"x0 the receiver, x30 back to the send, x19 the sender's frame, x20 the callee's fp"
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm mov: X1 with: X0.
	asm mov: X2 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt missFunction.
	asm blr: X16.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	self emitContinueOrExit: exit.
	miss := asm labelAt: blMiss.
	blMega := self symbol: 'baseline megamorphic'.
	"x0 the receiver, x9 the selector: probe the megamorphic cache by class and selector"
	imm := asm newLabel.
	have := asm newLabel.
	asm and: X16 with: X0 imm: 7.
	asm cbnz: X16 to: imm.
	asm ldr: X16 base: X0 offset: 8.
	asm bind: have.
	asm eor: X10 with: X16 with: X9.
	asm lsr: X10 with: X10 imm: 3.
	asm ldr: X11 base: X22 offset: self megaCacheOffset.
	asm and: X10 with: X10 imm: brt megaMask.
	asm add: X11 with: X11 with: X10 shift: SHIFT_LSL amount: 5.
	asm ldp: X12 with: X13 base: X11 offset: 0.
	asm cmp: X12 with: X16.
	asm b: miss if: COND_NE.
	asm cmp: X13 with: X9.
	asm b: miss if: COND_NE.
	asm ldr: X16 base: X11 offset: 16.
	asm br: X16.
	asm bind: imm.
	asm add: X17 with: X22 imm: self tagClassesOffset.
	asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
	asm b: have.
	blBlock := self symbol: 'baseline block value'.
	"x0 a closure with the right argument count: its code by home method and startpc in the block cache"
	lnot := asm newLabel.
	asm ldr: X16 base: X0 offset: (self fieldOffset: BC_OUTER).
	asm ldr: X16 base: X16 offset: (self fieldOffset: CTX_METHOD).
	asm ldr: X17 base: X0 offset: (self fieldOffset: BC_STARTPC).
	asm eor: X10 with: X17 with: X16 shift: SHIFT_LSR amount: 3.
	asm ldr: X11 base: X22 offset: self blockCacheOffset.
	asm and: X10 with: X10 imm: brt blockMask.
	asm add: X11 with: X11 with: X10 shift: SHIFT_LSL amount: 5.
	asm ldp: X12 with: X13 base: X11 offset: 0.
	asm cmp: X12 with: X16.
	asm b: lnot if: COND_NE.
	asm cmp: X13 with: X17.
	asm b: lnot if: COND_NE.
	asm ldr: X16 base: X11 offset: 16.
	asm br: X16.
	asm bind: lnot.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm mov: X1 with: X0.
	asm mov: X2 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt blockFunction.
	asm blr: X16.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	self emitContinueOrExit: exit.
	blEntrySlow := self symbol: 'baseline entry slow path'.
	"x10 where to retry, x30 back to the send: the stack is full or an interrupt is pending"
	asm stp: X10 with: X30 base: SP preIndex: -16.
	asm mov: X1 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt entrySlowFunction.
	asm blr: X16.
	asm ldp: X10 with: X30 base: SP postIndex: 16.
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	self emitReloadPinned.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	blPrim := self symbol: 'baseline primitive'.
	"x2 the primitive's function, x3 its argument count | leaf << 8, x10 where a failure continues, x30 back to the send"
	lnot := asm newLabel.
	asm stp: X10 with: X30 base: SP preIndex: -16.
	asm str: X30 base: X22 offset: self primRetOffset.
	asm mov: X1 with: X20.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt primFunction.
	asm blr: X16.
	asm ldp: X10 with: X30 base: SP postIndex: 16.
	self emitReloadPinned.
	asm cbnz: X0 to: lnot.
	asm ldr: X0 base: X22 offset: self resultOffset.
	asm ret.
	asm bind: lnot.
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	blRemember := self symbol: 'baseline remember'.
	"x16 an old object, x17 the young value stored into it: every register but x16, x17 preserved"
	asm stp: X0 with: X1 base: SP preIndex: -144.
	asm stp: X2 with: X3 base: SP offset: 16.
	asm stp: X4 with: X5 base: SP offset: 32.
	asm stp: X6 with: X7 base: SP offset: 48.
	asm stp: X8 with: X9 base: SP offset: 64.
	asm stp: X10 with: X11 base: SP offset: 80.
	asm stp: X12 with: X13 base: SP offset: 96.
	asm stp: X14 with: X15 base: SP offset: 112.
	asm stp: X29 with: X30 base: SP offset: 128.
	asm mov: X0 with: X16.
	asm mov: X1 with: X17.
	asm mov: X16 imm64: runtime writeBarrierFunction.
	asm blr: X16.
	asm ldp: X29 with: X30 base: SP offset: 128.
	asm ldp: X14 with: X15 base: SP offset: 112.
	asm ldp: X12 with: X13 base: SP offset: 96.
	asm ldp: X10 with: X11 base: SP offset: 80.
	asm ldp: X8 with: X9 base: SP offset: 64.
	asm ldp: X6 with: X7 base: SP offset: 48.
	asm ldp: X4 with: X5 base: SP offset: 32.
	asm ldp: X2 with: X3 base: SP offset: 16.
	asm ldp: X0 with: X1 base: SP postIndex: 144.
	asm ret.
	blNlr := self symbol: 'baseline non-local return'.
	"the frame's pc and sp stored: the runtime answers the home frame's record (0: leave)"
	lnot := asm newLabel.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt nlrFunction.
	asm blr: X16.
	asm cbz: X0 to: exit.
	asm mov: SP with: X0.
	asm ldr: X19 base: X22 offset: self nlrFrameOffset.
	asm ldr: X20 base: X22 offset: self nlrFpOffset.
	asm ldr: X0 base: X22 offset: self resultOffset.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret.
	blReturnSlow := self stub: brt returnSlowFunction named: 'baseline return slow path'.
	blBox := self stub: brt boxFunction named: 'baseline box Float'
!
emitContinueOrExit: exit
	"x0: 1 leave, else the code to continue at with the receiver in x0 again (x30 back to the send)."
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm mov: X16 with: X0.
	self emitReloadPinned.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X16
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
