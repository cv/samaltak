JitCompiler subclass: #JitTemplateCompiler
	instanceVariableNames: 'codeStart pcLabels deferred deferredPcs deferredCount slowKinds slowPcs slowDepths slowLabels slowResumes slowRegs slowCount exitSyncLabel exitPlainLabel sendLabel specialLabel interruptLabel closureLabel makeArrayLabel outerTempLabel widowLabel barrierLabel tierUpLabel counterAddr'
	classVariableNames: 'SLOW_BARRIER SLOW_EXIT SLOW_INTERRUPT SLOW_SPECIAL SLOW_TIERUP SLOW_WIDOW TPL_MAX_SLOW'
	package: 'VM-Jit'!

JitTemplateCompiler comment: 'The template compiler (--jit template): every bytecode becomes a fixed piece of machine code that works on the frame''s slots at their static offsets (BytecodeAnalysis), with no values kept in registers between bytecodes. Inline: pushes, stores (the store barrier''s fast path with --jit-flags barrier), jumps with interrupt checks on backward ones, SmallInteger + - * // \\ bitAnd: bitOr: and comparisons with tag checks and overflow branches (arith), and as in the interpreter (fuse) an arithmetic result followed by a pop into a temp stored right there and a comparison followed by a conditional jump branching directly (the consumed instruction''s own code, for slow paths and resumption, goes out of line), == and ~~, returns. Sends and everything else call the runtime (JitRuntime). thisContext, non-local returns, mustBeBoolean, stores into immutable objects and returns from the bottom frame leave to the interpreter at their pc. Slow paths are out of line, after the method''s code. It removes the interpreter''s dispatch and nothing else: the baseline of the comparison.'!

!JitTemplateCompiler class methodsFor: 'declaring'!
declarations
	^#((codeStart uint64_t) (pcLabels 'int32_t[ANA_MAX]') (deferred 'uint8_t[ANA_MAX]') (deferredPcs 'int32_t[TPL_MAX_SLOW]') (deferredCount int32_t)
		(slowKinds 'uint8_t[TPL_MAX_SLOW]') (slowPcs 'int32_t[TPL_MAX_SLOW]') (slowDepths 'int32_t[TPL_MAX_SLOW]') (slowLabels 'int32_t[TPL_MAX_SLOW]')
		(slowResumes 'int32_t[TPL_MAX_SLOW]') (slowRegs 'int32_t[TPL_MAX_SLOW]') (slowCount int32_t)
		(exitSyncLabel int32_t) (exitPlainLabel int32_t) (sendLabel int32_t) (specialLabel int32_t) (interruptLabel int32_t)
		(closureLabel int32_t) (makeArrayLabel int32_t) (outerTempLabel int32_t) (widowLabel int32_t) (barrierLabel int32_t)
		(tierUpLabel int32_t) (counterAddr uint64_t))
!
initialize
	TPL_MAX_SLOW := 16384.
	SLOW_EXIT := 1.
	SLOW_SPECIAL := 2.
	SLOW_INTERRUPT := 3.
	SLOW_WIDOW := 4.
	SLOW_BARRIER := 5.
	SLOW_TIERUP := 6
! !

!JitTemplateCompiler methodsFor: 'compiling'!
compile: m
	"Emit m's code at the assembler's pc (BytecodeAnalysis has analyzed m); answer whether every reachable bytecode got its template."
	<c: 'bool jit_template_compile(oop m)'>
	| n pc |
	codeStart := asm pc.
	n := analysis size.
	0 to: n - 1 do: [:i |
		pcLabels at: i put: -1.
		deferred at: i put: 0].
	slowCount := 0.
	deferredCount := 0.
	exitSyncLabel := asm newLabel.
	exitPlainLabel := asm newLabel.
	sendLabel := asm labelAt: stubs sendStub.
	specialLabel := asm labelAt: stubs specialStub.
	interruptLabel := asm labelAt: stubs interruptStub.
	closureLabel := asm labelAt: stubs closureStub.
	makeArrayLabel := asm labelAt: stubs makeArrayStub.
	outerTempLabel := asm labelAt: stubs outerTempStub.
	widowLabel := asm labelAt: stubs widowStub.
	barrierLabel := asm labelAt: stubs barrierStub.
	tierUpLabel := asm labelAt: stubs tierUpStub.
	counterAddr := runtime tiering ifTrue: [runtime counterAddressFor: m] ifFalse: [0].
	pc := 0.
	[pc < n] whileTrue: [
		(analysis isStart: pc)
			ifTrue: [
				(deferred at: pc) = 0 ifTrue: [(self emitAt: pc asInt32) ifFalse: [^false]].
				pc := pc + (analysis lengthAt: pc)]
			ifFalse: [pc := pc + 1]].
	0 to: deferredCount - 1 do: [:i |
		pc := deferredPcs at: i.
		(self emitAt: pc asInt32) ifFalse: [^false].
		asm b: (self labelFor: pc + (analysis lengthAt: pc))].
	(self emitSlowPaths) ifFalse: [^false].
	asm bind: exitSyncLabel.
	asm comment: 'leave to the interpreter at the stored pc'.
	asm b: (asm labelAt: stubs exitSyncAddress).
	asm bind: exitPlainLabel.
	asm comment: 'leave to the interpreter (the runtime made the frames canonical)'.
	asm b: (asm labelAt: stubs exitPlainAddress).
	^true
!
labelFor: pc
	"The label of the code of the instruction at pc."
	(pcLabels at: pc) < 0 ifTrue: [pcLabels at: pc put: asm newLabel].
	^pcLabels at: pc
!
defer: pc
	"The previous instruction consumed the one at pc: its own code goes out of line (slow paths and the interpreter continue there). Answer whether there was room."
	deferredCount >= TPL_MAX_SLOW ifTrue: [^false].
	"its code ends with a jump back to the next instruction, which the main line binds"
	self labelFor: pc + (analysis lengthAt: pc).
	deferred at: pc put: 1.
	deferredPcs at: deferredCount put: pc.
	deferredCount := deferredCount + 1.
	^true
!
slow: kind pc: pc depth: d resume: label reg: r
	"An out-of-line slow path, emitted after the method; answer its label (-1 if there are too many)."
	<c: 'int32_t tpl_slow(int32_t kind, int32_t pc, int32_t d, int32_t label, int32_t r)'>
	| l |
	slowCount >= TPL_MAX_SLOW ifTrue: [^-1].
	l := asm newLabel.
	slowKinds at: slowCount put: kind asUInt8.
	slowPcs at: slowCount put: pc.
	slowDepths at: slowCount put: d.
	slowLabels at: slowCount put: l.
	slowResumes at: slowCount put: label.
	slowRegs at: slowCount put: r.
	slowCount := slowCount + 1.
	^l
!
emitAt: pc
	"The template of the instruction at pc."
	<c: 'bool tpl_emit_at(int32_t pc)'>
	| op d |
	op := analysis byteAt: pc.
	d := analysis depthAt: pc.
	(pc = 0 or: [analysis isBlockStart: pc])
		ifTrue: [(self emitEntry: pc depth: d) ifFalse: [^false]]
		ifFalse: [
			((analysis isTarget: pc) or: [analysis isResume: pc]) ifTrue: [self labelFor: pc].
			(pcLabels at: pc) >= 0 ifTrue: [asm bind: (pcLabels at: pc)].
			(analysis isResume: pc) ifTrue: [runtime noteResume: pc at: asm pc - codeStart]].
	asm bytecode: pc.
	op < 16r10 ifTrue: [^self pushTemp: op depth: d].
	op < 16r20 ifTrue: [^self pushInstVar: op - 16r10 depth: d].
	op < 16r40 ifTrue: [^self pushLiteral: op - 16r20 depth: d].
	op < 16r60 ifTrue: [^self pushLiteralVariable: op - 16r40 depth: d].
	op < 16r68 ifTrue: [^self popStoreTemp: op - 16r60 depth: d].
	op = 16r70 ifTrue: [
		asm comment: 'push self'.
		asm str: X21 base: X20 offset: (self slot: d).
		^true].
	op = 16r71 ifTrue: [^self pushState: self trueOffset depth: d].
	op = 16r72 ifTrue: [^self pushState: self falseOffset depth: d].
	op = 16r73 ifTrue: [^self pushState: self nilOffset depth: d].
	op = 16r74 ifTrue: [^self pushInteger: 0 depth: d].
	op = 16r75 ifTrue: [^self pushInteger: 1 depth: d].
	op = 16r76 ifTrue: [
		asm comment: 'thisContext: the interpreter flushes the frames'.
		^self exitAt: pc depth: d].
	op = 16r77 ifTrue: [
		asm comment: 'dup'.
		asm ldr: X0 base: X20 offset: (self slot: d - 1).
		asm str: X0 base: X20 offset: (self slot: d).
		^true].
	op = 16r78 ifTrue: [
		asm comment: 'pop: nothing to do, the depth is static'.
		^true].
	(op = 16r79 or: [op = 16r7B]) ifTrue: [^self return: pc depth: d self: false].
	op = 16r7A ifTrue: [^self return: pc depth: d self: true].
	op = 16r7C ifTrue: [
		asm comment: 'non-local return: the interpreter unwinds'.
		^self exitAt: pc depth: d].
	op = 16r80 ifTrue: [^self pushTemp: (analysis byteAt: pc + 1) depth: d].
	op = 16r81 ifTrue: [^self pushInstVar: (analysis byteAt: pc + 1) depth: d].
	op = 16r82 ifTrue: [^self pushLiteral: (analysis byteAt: pc + 1) depth: d].
	op = 16r83 ifTrue: [^self pushLiteralVariable: (analysis byteAt: pc + 1) depth: d].
	op = 16r84 ifTrue: [
		asm comment: 'store temp %d' with: (analysis byteAt: pc + 1).
		asm ldr: X0 base: X20 offset: (self slot: d - 1).
		asm str: X0 base: X20 offset: (self slot: (analysis byteAt: pc + 1)).
		^true].
	op = 16r85 ifTrue: [^self storeInstVar: (analysis byteAt: pc + 1) pc: pc depth: d].
	op = 16r86 ifTrue: [^self storeLiteralVariable: (analysis byteAt: pc + 1) depth: d].
	op = 16r87 ifTrue: [^self popStoreTemp: (analysis byteAt: pc + 1) depth: d].
	op = 16r89 ifTrue: [^self storeLiteralVariable: (analysis byteAt: pc + 1) depth: d].
	(op >= 16r8A and: [op <= 16r8C]) ifTrue: [^self outerTemp: pc depth: d].
	(op = 16r8D or: [op = 16r8E or: [op >= 16rC0 and: [op < 16rF0]]]) ifTrue: [
		asm comment: (op = 16r8E ifTrue: ['super send: call the runtime'] ifFalse: ['send: call the runtime']).
		self emitSync: pc depth: d.
		self emitCall: sendLabel info: (op >= 16rC0
			ifTrue: [((((op - 16rC0) >> 4) asInt64 bitOr: 1 << 8) bitOr: (op bitAnd: 15) asInt64 << 16)]
			ifFalse: [(((analysis byteAt: pc + 2) bitOr: 3 << 8) bitOr: (analysis byteAt: pc + 1) asInt64 << 16) bitOr: (op = 16r8E ifTrue: [1 << 24] ifFalse: [0])]).
		self emitCallResult.
		^true].
	op = 16r8F ifTrue: [^self closure: pc depth: d].
	op = 16r90 ifTrue: [^self jumpTo: (analysis jumpTargetAt: pc)].
	(op = 16r91 or: [op = 16r92]) ifTrue: [^self conditionalJump: pc depth: d].
	op = 16r93 ifTrue: [^self pushInteger: (analysis int16At: pc + 1) depth: d].
	op = 16r94 ifTrue: [
		asm comment: 'make an Array: call the runtime'.
		self emitSync: pc depth: d.
		asm mov: X0 with: X19.
		asm bl: makeArrayLabel.
		asm cbnz: X0 to: exitPlainLabel.
		self emitReloadReceiver.
		^true].
	(op >= 16r97 and: [op < 16rA0]) ifTrue: [^self superinstruction: pc depth: d].
	(op >= 16rF0 and: [op < 16rFC]) ifTrue: [^self superinstruction: pc depth: d].
	(op >= 16rA0 and: [op < 16rC0]) ifTrue: [^self special: op - 16rA0 pc: pc depth: d loaded: false].
	^false
!
emitEntry: pc depth: d
	"A method's or block's prologue; pc's label and resumption point are start, after it."
	| entry after s |
	entry := asm pc.
	self emitPrologue.
	asm pc - entry = runtime prologueBytes asUInt64 ifFalse: [^false].
	asm bind: (self labelFor: pc).
	runtime noteResume: pc at: asm pc - codeStart.
	after := asm newLabel.
	s := self slow: SLOW_INTERRUPT pc: pc depth: d resume: after reg: 0.
	s < 0 ifTrue: [^false].
	self emitInterruptCheck: s.
	asm bind: after.
	(pc = 0 and: [counterAddr ~= 0]) ifTrue: [^self emitTierUpCheck: pc depth: d].
	^true
!
emitTierUpCheck: pc depth: d
	"--jit opt: count down toward optimization; at zero the runtime may continue the frame in optimized code."
	| s after |
	after := asm newLabel.
	s := self slow: SLOW_TIERUP pc: pc depth: d resume: after reg: 0.
	s < 0 ifTrue: [^false].
	self emitCountDown: counterAddr to: s.
	asm bind: after.
	^true
!
emitInterruptCheck: slowLabel
	asm comment: 'interrupt check'.
	asm ldr: W16 base: X22 offset: self interruptOffset.
	asm cbnz: W16 to: slowLabel
!
emitCall: stubLabel info: info
	"Call a send stub: x0 the frame, x1 info (JitRuntime>>send:info:site:), x2 this call's address (the site's key in the inline caches)."
	| here |
	asm mov: X0 with: X19.
	asm mov: X1 imm: info.
	here := asm newLabel.
	asm bind: here.
	asm adr: X2 label: here.
	asm bl: stubLabel
!
specialInfo: pc
	"send:info:site:'s info for the special selector the instruction at pc sends."
	| k |
	k := analysis specialIndexOf: analysis bytecodes + pc.
	^(((((analysis specialArgc: k) asInt64 bitOr: (analysis lengthAt: pc) asInt64 << 8) bitOr: k asInt64 << 16) bitOr: 2 << 24)
		bitOr: (analysis pushesOf: analysis bytecodes + pc) asInt64 << 25)
!
emitCallResult
	"After a runtime send: 0 continue, 1 leave, else call the callee's entry."
	| cont |
	cont := asm newLabel.
	asm comment: '0: done, 1: leave, else the callee''s entry'.
	asm cbz: X0 to: cont.
	asm cmp: X0 imm: 1.
	asm b: exitPlainLabel if: COND_EQ.
	asm comment: 'call the compiled callee'.
	asm blr: X0.
	asm ldr: X20 base: X19 offset: self fpOffset.
	asm bind: cont.
	self emitReloadReceiver
!
exitAt: pc depth: d
	self emitSync: pc depth: d.
	asm b: exitSyncLabel.
	^true
! !

!JitTemplateCompiler methodsFor: 'pushes and stores'!
pushTemp: i depth: d
	asm comment: 'push temp %d' with: i.
	asm ldr: X0 base: X20 offset: (self slot: i).
	asm str: X0 base: X20 offset: (self slot: d).
	^true
!
popStoreTemp: i depth: d
	asm comment: 'pop into temp %d' with: i.
	asm ldr: X0 base: X20 offset: (self slot: d - 1).
	asm str: X0 base: X20 offset: (self slot: i).
	^true
!
pushInstVar: i depth: d
	asm comment: 'push inst var %d' with: i.
	asm ldr: X0 base: X21 offset: (self fieldOffset: i).
	asm str: X0 base: X20 offset: (self slot: d).
	^true
!
pushState: offset depth: d
	asm comment: 'push nil, true or false (JitState)'.
	asm ldr: X0 base: X22 offset: offset.
	asm str: X0 base: X20 offset: (self slot: d).
	^true
!
pushInteger: v depth: d
	asm comment: 'push SmallInteger %d' with: v.
	asm mov: X0 imm: ((v asInt64 << 1) bitOr: 1) asUInt64.
	asm str: X0 base: X20 offset: (self slot: d).
	^true
!
loadLiteral: i into: r
	"r := literal i, embedded if it is an old object and the embed flag is on."
	| v site |
	i >= analysis numLiterals ifTrue: [^false].
	v := analysis literalAt: i.
	(runtime embed and: [runtime isOldObject: v]) ifTrue: [
		site := asm pc - codeStart.
		(runtime noteReference: site) ifTrue: [
			asm comment: 'literal %d, embedded' with: i.
			asm mov: r imm64: v.
			^true]].
	asm comment: 'literal %d via the frame''s lits' with: i.
	asm ldr: X16 base: X19 offset: self litsOffset.
	asm ldr: r base: X16 offset: (self slot: i).
	^true
!
pushLiteral: i depth: d
	(self loadLiteral: i into: X0) ifFalse: [^false].
	asm str: X0 base: X20 offset: (self slot: d).
	^true
!
pushLiteralVariable: i depth: d
	(self loadLiteral: i into: X0) ifFalse: [^false].
	asm comment: 'its value'.
	asm ldr: X0 base: X0 offset: (self fieldOffset: ASSOC_VALUE).
	asm str: X0 base: X20 offset: (self slot: d).
	^true
!
storeInstVar: i pc: pc depth: d
	| s |
	asm comment: 'store into inst var %d' with: i.
	asm ldr: X0 base: X20 offset: (self slot: d - 1).
	asm ldr: X1 base: X21 offset: 0.
	asm comment: 'immutable receiver: the interpreter sends attemptToAssign:withIndex:'.
	s := self slow: SLOW_EXIT pc: pc depth: d resume: 0 reg: 0.
	s < 0 ifTrue: [^false].
	asm tst: X1 imm: H_IMMUTABLE.
	asm b: s if: COND_NE.
	asm str: X0 base: X21 offset: (self fieldOffset: i).
	^self barrier: X21 header: X1 value: X0
!
storeLiteralVariable: i depth: d
	(self loadLiteral: i into: X6) ifFalse: [^false].
	asm comment: 'store into its value'.
	asm ldr: X0 base: X20 offset: (self slot: d - 1).
	asm str: X0 base: X6 offset: (self fieldOffset: ASSOC_VALUE).
	asm ldr: X1 base: X6 offset: 0.
	^self barrier: X6 header: X1 value: X0
!
barrier: obj header: hdr value: v
	"The generational store barrier after storing v into obj (hdr is obj's header)."
	| done s |
	runtime barrier ifFalse: [
		asm comment: 'store barrier: call the runtime'.
		asm mov: X1 with: v.
		asm mov: X0 with: obj.
		asm bl: barrierLabel.
		^true].
	done := asm newLabel.
	s := self slow: SLOW_BARRIER pc: 0 depth: 0 resume: done reg: ((obj bitAnd: 31) bitOr: (v bitAnd: 31) * 256).
	s < 0 ifTrue: [^false].
	asm comment: 'store barrier: an immediate needs nothing'.
	asm tst: v imm: 7.
	asm b: done if: COND_NE.
	asm comment: 'nor an old value'.
	asm ldr: X2 base: X22 offset: self youngLoOffset.
	asm ldr: X3 base: X22 offset: self youngHiOffset.
	asm sub: X16 with: v with: X2.
	asm sub: X17 with: X3 with: X2.
	asm cmp: X16 with: X17.
	asm b: done if: COND_HS.
	asm comment: 'nor a young object or a remembered one'.
	asm sub: X16 with: obj with: X2.
	asm cmp: X16 with: X17.
	asm b: done if: COND_LO.
	asm tst: hdr imm: H_REMEMBERED.
	asm b: s if: COND_EQ.
	asm bind: done.
	^true
! !

!JitTemplateCompiler methodsFor: 'control'!
jumpTo: t
	"An unconditional jump; backward ones check for interrupts."
	| s |
	(analysis isLoopHead: t) ifFalse: [
		asm comment: 'jump'.
		asm b: (self labelFor: t).
		^true].
	s := self slow: SLOW_INTERRUPT pc: t depth: (analysis depthAt: t) resume: (self labelFor: t) reg: 0.
	s < 0 ifTrue: [^false].
	asm comment: 'jump back'.
	self emitInterruptCheck: s.
	counterAddr ~= 0 ifTrue: [
		s := self slow: SLOW_TIERUP pc: t depth: (analysis depthAt: t) resume: (self labelFor: t) reg: 0.
		s < 0 ifTrue: [^false].
		self emitCountDown: counterAddr to: s].
	asm b: (self labelFor: t).
	^true
!
branch: cond to: t
	"Branch to t if cond; a backward branch goes through an interrupt check."
	| skip s |
	(analysis isLoopHead: t) ifFalse: [
		asm b: (self labelFor: t) if: cond.
		^true].
	skip := asm newLabel.
	asm b: skip if: (cond bitXor: 1).
	s := self slow: SLOW_INTERRUPT pc: t depth: (analysis depthAt: t) resume: (self labelFor: t) reg: 0.
	s < 0 ifTrue: [^false].
	self emitInterruptCheck: s.
	counterAddr ~= 0 ifTrue: [
		s := self slow: SLOW_TIERUP pc: t depth: (analysis depthAt: t) resume: (self labelFor: t) reg: 0.
		s < 0 ifTrue: [^false].
		self emitCountDown: counterAddr to: s].
	asm b: (self labelFor: t).
	asm bind: skip.
	^true
!
conditionalJump: pc depth: d
	| op t s |
	op := analysis byteAt: pc.
	t := analysis jumpTargetAt: pc.
	asm comment: (op = 16r91 ifTrue: ['pop, jump if true'] ifFalse: ['pop, jump if false']).
	asm ldr: X0 base: X20 offset: (self slot: d - 1).
	asm ldr: X1 base: X22 offset: (op = 16r91 ifTrue: [self trueOffset] ifFalse: [self falseOffset]).
	asm cmp: X0 with: X1.
	(self branch: COND_EQ to: t) ifFalse: [^false].
	asm comment: 'neither true nor false: the interpreter sends mustBeBoolean'.
	s := self slow: SLOW_EXIT pc: pc depth: d resume: 0 reg: 0.
	s < 0 ifTrue: [^false].
	asm ldr: X1 base: X22 offset: (op = 16r91 ifTrue: [self falseOffset] ifFalse: [self trueOffset]).
	asm cmp: X0 with: X1.
	asm b: s if: COND_NE.
	^true
!
return: pc depth: d self: isSelf
	"Pop the frame: the result into the receiver's slot, back to the caller's code (or to jit_enter)."
	| s w after |
	s := self slow: SLOW_EXIT pc: pc depth: d resume: 0 reg: 0.
	s < 0 ifTrue: [^false].
	after := asm newLabel.
	w := self slow: SLOW_WIDOW pc: pc depth: d resume: after reg: 0.
	w < 0 ifTrue: [^false].
	asm comment: (isSelf ifTrue: ['return self'] ifFalse: ['return top']).
	asm comment: 'the bottom frame returns into a Context: the interpreter does it'.
	asm ldr: X2 base: X22 offset: self framesOffset.
	asm cmp: X19 with: X2.
	asm b: s if: COND_EQ.
	asm comment: 'a married frame leaves its slots to its Context'.
	asm ldr: X1 base: X19 offset: self ctxOffset.
	asm ldr: X2 base: X22 offset: self nilOffset.
	asm cmp: X1 with: X2.
	asm b: w if: COND_NE.
	asm bind: after.
	asm comment: 'result into the receiver''s slot, pop the frame, return'.
	isSelf
		ifTrue: [asm mov: X0 with: X21]
		ifFalse: [asm ldr: X0 base: X20 offset: (self slot: d - 1)].
	asm str: X0 base: X20 offset: -8.
	asm sub: X19 with: X19 imm: self frameBytes.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret.
	^true
!
outerTemp: pc depth: d
	"push (8A), store (8B), pop and store (8C) temp i of the Context d outer levels out: in its frame if it is married (sender = the frame's index), else in the Context."
	| op depth i married done |
	op := analysis byteAt: pc.
	depth := analysis byteAt: pc + 1.
	i := analysis byteAt: pc + 2.
	self frameBytes = 64 ifFalse: [
		asm comment: 'outer temp: call the runtime'.
		self emitSync: pc depth: d.
		asm mov: X0 with: X19.
		asm bl: outerTempLabel.
		^true].
	asm comment: (op = 16r8A ifTrue: ['push outer temp %d'] ifFalse: ['store outer temp %d']) with: i.
	asm ldr: X6 base: X19 offset: self closureOffset.
	asm ldr: X6 base: X6 offset: (self fieldOffset: BC_OUTER).
	2 to: depth do: [:k |
		asm ldr: X7 base: X6 offset: (self fieldOffset: CTX_CLOSURE).
		asm ldr: X6 base: X7 offset: (self fieldOffset: BC_OUTER)].
	asm ldr: X7 base: X6 offset: (self fieldOffset: CTX_SENDER).
	op ~= 16r8A ifTrue: [asm ldr: X0 base: X20 offset: (self slot: d - 1)].
	married := asm newLabel.
	done := asm newLabel.
	asm tbnz: X7 bit: 0 to: married.
	asm comment: 'a Context'.
	op = 16r8A
		ifTrue: [
			asm ldr: X0 base: X6 offset: (self fieldOffset: CTX_FIXED + i).
			asm str: X0 base: X20 offset: (self slot: d)]
		ifFalse: [
			asm str: X0 base: X6 offset: (self fieldOffset: CTX_FIXED + i).
			asm ldr: X1 base: X6 offset: 0.
			(self barrier: X6 header: X1 value: X0) ifFalse: [^false]].
	asm b: done.
	asm bind: married.
	asm comment: 'married: the slot of its frame'.
	asm ldr: X3 base: X22 offset: self framesOffset.
	asm asr: X7 with: X7 imm: 1.
	asm add: X3 with: X3 with: X7 shift: SHIFT_LSL amount: 6.
	asm ldr: X3 base: X3 offset: self fpOffset.
	op = 16r8A
		ifTrue: [
			asm ldr: X0 base: X3 offset: (self slot: i).
			asm str: X0 base: X20 offset: (self slot: d)]
		ifFalse: [asm str: X0 base: X3 offset: (self slot: i)].
	asm bind: done.
	^true
!
closure: pc depth: d
	| after |
	after := pc + 6 + (((analysis byteAt: pc + 4) asInt64 << 8) bitOr: (analysis byteAt: pc + 5)).
	asm comment: 'create a BlockClosure: call the runtime'.
	self emitSync: pc depth: d.
	asm mov: X0 with: X19.
	asm bl: closureLabel.
	asm cbnz: X0 to: exitPlainLabel.
	self emitReloadReceiver.
	asm comment: 'skip the block''s code'.
	asm b: (self labelFor: after).
	^true
! !

!JitTemplateCompiler methodsFor: 'special selectors'!
superinstruction: pc depth: d
	"push temp a, push temp / literal / SmallInteger b, then a special selector: the operands go into x0, x1 and their slots."
	| op k a b |
	op := analysis byteAt: pc.
	a := analysis byteAt: pc + 1.
	b := analysis byteAt: pc + 2.
	k := analysis specialIndexOf: (analysis bytecodes + pc).
	asm comment: 'push temp %d' with: a.
	asm ldr: X0 base: X20 offset: (self slot: a).
	(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]])
		ifTrue: [
			asm comment: 'push temp %d' with: b.
			asm ldr: X1 base: X20 offset: (self slot: b)]
		ifFalse: [
			(op = 16r98 or: [op >= 16rF0 and: [op < 16rF6]])
				ifTrue: [(self loadLiteral: b into: X1) ifFalse: [^false]]
				ifFalse: [
					asm comment: 'push SmallInteger %d' with: b asInt8.
					asm mov: X1 imm: ((b asInt8 asInt64 << 1) bitOr: 1) asUInt64]].
	^self special: k pc: pc depth: d + 2 loaded: true
!
special: k pc: pc depth: d loaded: loaded
	"Special selector k with its operands at the top of the d slots (and in x0, x1 if loaded)."
	<var: #s type: 'int32_t'>
	| next s compare cond exact |
	next := pc + (analysis lengthAt: pc).
	compare := (k >= 2 and: [k <= 7]) or: [k = 19 or: [k = 20]].
	((k = 19 or: [k = 20]) or: [runtime arith and: [compare or: [k <= 10 or: [(k >= 13 and: [k <= 18]) or: [k >= 27 and: [k <= 29]]]]]]) ifFalse: [
		loaded ifTrue: [
			asm comment: 'the operands into their slots'.
			asm stp: X0 with: X1 base: X20 offset: (self slot: d - 2)].
		asm comment: 'special selector: call the runtime'.
		self emitSync: pc depth: d.
		self emitCall: specialLabel info: (self specialInfo: pc).
		self emitCallResult.
		^true].
	(k = 11 or: [k = 12]) ifTrue: [^self callSpecial: pc depth: d loaded: loaded].
	(k >= 16 and: [k ~= 19 and: [k ~= 20]]) ifTrue: [
		loaded ifTrue: [
			asm comment: 'the operands into their slots'.
			asm stp: X0 with: X1 base: X20 offset: (self slot: d - 2)].
		^self objectSpecial: k pc: pc depth: d].
	loaded ifFalse: [
		asm comment: 'receiver and argument'.
		asm ldp: X0 with: X1 base: X20 offset: (self slot: d - 2)].
	s := -1.
	(k ~= 19 and: [k ~= 20]) ifTrue: [
		s := self slow: SLOW_SPECIAL pc: pc depth: d resume: (self labelFor: next)
			reg: ((loaded ifTrue: [1] ifFalse: [0]) bitOr: (k <= 9 ifTrue: [(k + 1) * 256] ifFalse: [0])).
		s < 0 ifTrue: [^false].
		k = 9 ifTrue: [
			asm comment: '/: Floats out of line, else call the runtime'.
			asm b: s.
			^true].
		asm comment: 'SmallInteger tag check: else Floats out of line, else call the runtime'.
		asm and: X2 with: X0 with: X1.
		asm tst: X2 imm: 1.
		asm b: s if: COND_EQ].
	compare ifTrue: [
		cond := self conditionOf: k.
		asm cmp: X0 with: X1.
		(runtime fuse and: [(analysis isStart: next) and: [(analysis byteAt: next) = 16r91 or: [(analysis byteAt: next) = 16r92]]]) ifTrue: [
			^self fusedJump: next cond: cond].
		asm comment: 'the Boolean'.
		asm ldr: X3 base: X22 offset: self trueOffset.
		asm ldr: X4 base: X22 offset: self falseOffset.
		asm csel: X3 with: X3 with: X4 cond: cond.
		^self storeResult: X3 depth: d next: next].
	k = 0 ifTrue: [
		asm comment: '+: overflow calls the runtime'.
		asm sub: X2 with: X1 imm: 1.
		asm adds: X3 with: X0 with: X2.
		asm b: s if: COND_VS].
	k = 1 ifTrue: [
		asm comment: '-: overflow calls the runtime'.
		asm sub: X2 with: X1 imm: 1.
		asm subs: X3 with: X0 with: X2.
		asm b: s if: COND_VS].
	k = 8 ifTrue: [
		asm comment: '*: a 128-bit product that does not fit calls the runtime'.
		asm asr: X2 with: X0 imm: 1.
		asm sub: X4 with: X1 imm: 1.
		asm mul: X3 with: X2 with: X4.
		asm smulh: X5 with: X2 with: X4.
		asm cmp: X5 with: X3 shift: SHIFT_ASR amount: 63.
		asm b: s if: COND_NE.
		asm orr: X3 with: X3 imm: 1].
	(k = 10 or: [k = 13]) ifTrue: [
		exact := asm newLabel.
		asm comment: (k = 13 ifTrue: ['//: the quotient rounded toward negative infinity'] ifFalse: ['\\: the remainder with the divisor''s sign']).
		asm asr: X2 with: X0 imm: 1.
		asm asr: X4 with: X1 imm: 1.
		asm cbz: X4 to: s.
		asm sdiv: X5 with: X2 with: X4.
		asm msub: X6 with: X5 with: X4 sub: X2.
		asm cbz: X6 to: exact.
		asm eor: X7 with: X6 with: X4.
		asm tbz: X7 bit: 63 to: exact.
		k = 13
			ifTrue: [asm sub: X5 with: X5 imm: 1]
			ifFalse: [asm add: X6 with: X6 with: X4].
		asm bind: exact.
		k = 13
			ifTrue: [
				asm comment: 'the quotient must be a SmallInteger'.
				asm add: X3 with: X5 with: X5.
				asm cmp: X5 with: X3 shift: SHIFT_ASR amount: 1.
				asm b: s if: COND_NE]
			ifFalse: [asm add: X3 with: X6 with: X6].
		asm orr: X3 with: X3 imm: 1].
	k = 14 ifTrue: [
		asm comment: 'bitAnd:'.
		asm and: X3 with: X0 with: X1].
	k = 15 ifTrue: [
		asm comment: 'bitOr:'.
		asm orr: X3 with: X0 with: X1].
	^self storeResult: X3 depth: d next: next
!
conditionOf: k
	"The condition of comparison k (< > <= >= = ~= == ~~) after cmp or fcmp."
	^k caseOf: {
		[2] -> [COND_LT]. [3] -> [COND_GT]. [4] -> [COND_LE]. [5] -> [COND_GE].
		[6] -> [COND_EQ]. [7] -> [COND_NE]. [19] -> [COND_EQ]}
		otherwise: [COND_NE]
!
callSpecial: pc depth: d loaded: loaded
	loaded ifTrue: [
		asm comment: 'the operands into their slots'.
		asm stp: X0 with: X1 base: X20 offset: (self slot: d - 2)].
	asm comment: 'special selector: call the runtime'.
	self emitSync: pc depth: d.
	self emitCall: specialLabel info: (self specialInfo: pc).
	self emitCallResult.
	^true
!
objectSpecial: k pc: pc depth: d
	"at: at:put: size on Arrays, x y on Points, class of objects: inline; anything else calls the runtime."
	<var: #s type: 'int32_t'>
	| next s n |
	next := pc + (analysis lengthAt: pc).
	n := k = 17 ifTrue: [3] ifFalse: [k = 16 ifTrue: [2] ifFalse: [1]].
	s := self slow: SLOW_SPECIAL pc: pc depth: d resume: (self labelFor: next) reg: 0.
	s < 0 ifTrue: [^false].
	asm comment: 'the receiver: an object (else call the runtime)'.
	asm ldr: X0 base: X20 offset: (self slot: d - n).
	asm tst: X0 imm: 7.
	asm b: s if: COND_NE.
	asm ldr: X2 base: X0 offset: 8.
	k = 29 ifTrue: [
		asm comment: 'class: its class word'.
		asm str: X2 base: X20 offset: (self slot: d - 1).
		^true].
	(k = 27 or: [k = 28]) ifTrue: [
		asm comment: (k = 27 ifTrue: ['x of a Point'] ifFalse: ['y of a Point']).
		asm ldr: X3 base: X22 offset: self pointClassOffset.
		asm cmp: X2 with: X3.
		asm b: s if: COND_NE.
		asm ldr: X3 base: X0 offset: (self fieldOffset: k - 27).
		asm str: X3 base: X20 offset: (self slot: d - 1).
		^true].
	asm comment: 'an Array (else call the runtime)'.
	asm ldr: X3 base: X22 offset: self arrayClassOffset.
	asm cmp: X2 with: X3.
	asm b: s if: COND_NE.
	asm ldr: X4 base: X0 offset: 0.
	k = 18 ifTrue: [
		asm comment: 'size: its slot count as a SmallInteger'.
		asm ubfx: X3 with: X4 lsb: 0 width: 32.
		asm add: X3 with: X3 with: X3.
		asm orr: X3 with: X3 imm: 1.
		asm str: X3 base: X20 offset: (self slot: d - 1).
		^true].
	asm comment: 'a SmallInteger index within its slots'.
	asm ldr: X1 base: X20 offset: (self slot: d - n + 1).
	asm tst: X1 imm: 1.
	asm b: s if: COND_EQ.
	asm asr: X5 with: X1 imm: 1.
	asm sub: X5 with: X5 imm: 1.
	asm ubfx: X3 with: X4 lsb: 0 width: 32.
	asm cmp: X5 with: X3.
	asm b: s if: COND_HS.
	asm add: X6 with: X0 imm: 16.
	k = 16 ifTrue: [
		asm ldr: X3 base: X6 index: X5 extend: EXT_LSL shift: 3.
		^self storeResult: X3 depth: d next: next].
	asm comment: 'not immutable; store and answer the value'.
	asm tst: X4 imm: H_IMMUTABLE.
	asm b: s if: COND_NE.
	asm ldr: X7 base: X20 offset: (self slot: d - 1).
	asm str: X7 base: X6 index: X5 extend: EXT_LSL shift: 3.
	asm str: X7 base: X20 offset: (self slot: d - 3).
	^self barrier: X0 header: X4 value: X7
!
emitFloat: k depth: d call: callLabel
	"The slow path of SmallInteger arithmetic or a comparison (k): two numbers, at least one a SmallFloat64, the other one too or a SmallInteger, without boxing; else branch to callLabel. The result goes where the runtime's would."
	| zero store |
	asm comment: 'Floats: SmallFloat64 or SmallInteger operands, at least one a Float'.
	asm and: X2 with: X0 with: X1.
	asm tst: X2 imm: 1.
	asm b: callLabel if: COND_NE.
	self emitToDouble: X0 into: D0 call: callLabel.
	self emitToDouble: X1 into: D1 call: callLabel.
	(k >= 2 and: [k <= 7]) ifTrue: [
		asm fcmp: D0 with: D1.
		asm ldr: X3 base: X22 offset: self trueOffset.
		asm ldr: X4 base: X22 offset: self falseOffset.
		asm csel: X3 with: X3 with: X4 cond: (self conditionOf: k).
		asm str: X3 base: X20 offset: (self slot: d - 2).
		^true].
	k = 0 ifTrue: [asm fadd: D0 with: D0 with: D1].
	k = 1 ifTrue: [asm fsub: D0 with: D0 with: D1].
	k = 8 ifTrue: [asm fmul: D0 with: D0 with: D1].
	k = 9 ifTrue: [
		asm fcmpZero: D1.
		asm b: callLabel if: COND_EQ.
		asm fdiv: D0 with: D0 with: D1].
	asm comment: 'the result as a SmallFloat64 if it is one, else call the runtime'.
	zero := asm newLabel.
	store := asm newLabel.
	asm fmov: X2 with: D0.
	asm lsl: X3 with: X2 imm: 1.
	asm cbz: X3 to: zero.
	asm ubfx: X4 with: X2 lsb: 52 width: 11.
	asm sub: X4 with: X4 imm: 897.
	asm cmp: X4 imm: 253.
	asm b: callLabel if: COND_HI.
	asm ror: X3 with: X2 imm: 63.
	asm mov: X16 imm: 16r7000000000000000.
	asm sub: X3 with: X3 with: X16.
	asm b: store.
	asm bind: zero.
	asm lsr: X3 with: X2 imm: 63.
	asm bind: store.
	asm lsl: X3 with: X3 imm: 3.
	asm orr: X3 with: X3 imm: 4.
	asm str: X3 base: X20 offset: (self slot: d - 2).
	^true
!
emitToDouble: r into: dr call: callLabel
	"dr := the SmallFloat64 or SmallInteger in r; else branch to callLabel."
	| int done |
	int := asm newLabel.
	done := asm newLabel.
	asm tbnz: r bit: 0 to: int.
	asm and: X2 with: r imm: 7.
	asm cmp: X2 imm: 4.
	asm b: callLabel if: COND_NE.
	asm lsr: X2 with: r imm: 3.
	asm mov: X16 imm: 16r7000000000000000.
	asm add: X3 with: X2 with: X16.
	asm cmp: X2 imm: 1.
	asm csel: X2 with: X2 with: X3 cond: COND_LS.
	asm ror: X2 with: X2 imm: 1.
	asm fmov: dr with: X2.
	asm b: done.
	asm bind: int.
	asm asr: X2 with: r imm: 1.
	asm scvtf: dr with: X2.
	asm bind: done
!
storeResult: r depth: d next: next
	"The result of a binary operation: into a following pop into a temp, else onto the stack."
	| op t |
	op := analysis byteAt: next.
	(runtime fuse and: [(analysis isStart: next) and: [(op >= 16r60 and: [op < 16r68]) or: [op = 16r87]]]) ifTrue: [
		t := op = 16r87 ifTrue: [analysis byteAt: next + 1] ifFalse: [op - 16r60].
		(self defer: next) ifTrue: [
			asm comment: 'the result straight into temp %d (fused with the pop)' with: t.
			asm str: r base: X20 offset: (self slot: t).
			^true]].
	asm str: r base: X20 offset: (self slot: d - 2).
	^true
!
fusedJump: j cond: cond
	"The flags hold a comparison; the conditional jump at j consumes it without a Boolean."
	| t taken |
	t := analysis jumpTargetAt: j.
	taken := (analysis byteAt: j) = 16r91 ifTrue: [cond] ifFalse: [cond bitXor: 1].
	(self defer: j) ifFalse: [^false].
	asm comment: 'compare and branch (fused with the jump)'.
	^self branch: taken to: t
! !

!JitTemplateCompiler methodsFor: 'slow paths'!
emitSlowPaths
	| kind l |
	0 to: slowCount - 1 do: [:i |
		kind := slowKinds at: i.
		asm bind: (slowLabels at: i).
		kind = SLOW_EXIT ifTrue: [
			asm comment: 'leave to the interpreter at this pc'.
			self exitAt: (slowPcs at: i) depth: (slowDepths at: i)].
		kind = SLOW_INTERRUPT ifTrue: [
			asm comment: 'interrupt: call the runtime'.
			self emitSync: (slowPcs at: i) depth: (slowDepths at: i).
			asm mov: X0 with: X19.
			asm bl: interruptLabel.
			asm cbnz: X0 to: exitPlainLabel.
			self emitReloadReceiver.
			asm b: (slowResumes at: i)].
		kind = SLOW_SPECIAL ifTrue: [
			(slowRegs at: i) >> 8 ~= 0 ifTrue: [
				l := asm newLabel.
				(self emitFloat: ((slowRegs at: i) >> 8) - 1 depth: (slowDepths at: i) call: l) ifFalse: [^false].
				asm b: (slowResumes at: i).
				asm bind: l].
			asm comment: 'call the runtime'.
			((slowRegs at: i) bitAnd: 1) ~= 0 ifTrue: [asm stp: X0 with: X1 base: X20 offset: (self slot: (slowDepths at: i) - 2)].
			self emitSync: (slowPcs at: i) depth: (slowDepths at: i).
			self emitCall: specialLabel info: (self specialInfo: (slowPcs at: i)).
			self emitCallResult.
			asm b: (slowResumes at: i)].
		kind = SLOW_TIERUP ifTrue: [
			asm comment: 'tier up: the runtime answers 0 (go on), 1 (leave) or where the frame continues'.
			self emitSync: (slowPcs at: i) depth: (slowDepths at: i).
			asm mov: X0 with: X19.
			asm bl: tierUpLabel.
			l := asm newLabel.
			asm cbz: X0 to: l.
			asm cmp: X0 imm: 1.
			asm b: exitPlainLabel if: COND_EQ.
			asm br: X0.
			asm bind: l.
			self emitReloadReceiver.
			asm b: (slowResumes at: i)].
		kind = SLOW_WIDOW ifTrue: [
			asm comment: 'married: call the runtime'.
			self emitSync: (slowPcs at: i) depth: (slowDepths at: i).
			asm mov: X0 with: X19.
			asm bl: widowLabel.
			asm b: (slowResumes at: i)].
		kind = SLOW_BARRIER ifTrue: [
			asm comment: 'remember the old object: call the runtime'.
			asm mov: X1 with: ((slowRegs at: i) >> 8).
			asm mov: X0 with: ((slowRegs at: i) bitAnd: 255).
			asm bl: barrierLabel.
			asm b: (slowResumes at: i)]].
	^true
! !
