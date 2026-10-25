VMCoreModule subclass: #JitStencils
	instanceVariableNames: 'fp rcv st sp fr'
	classVariableNames: ''
	package: 'VM-Jit'!

JitStencils comment: 'The stencils of the copy-and-patch (--jit stencil) and call-threading (--jit threaded) compilers (docs/jit.md): the code of each bytecode, or of a variant of one, written once on the interpreter''s frames with its helpers. <stencil> marks one, <stencil: n> n copies (self case 0 to n - 1), <stencil: #(first last)> copies for cases first to last.

The translator makes C of each twice. For copy-and-patch a preserve_none function: the state in its arguments, holes (self hole: #A, the value JitStencilCompiler patches in for HOLE_A) the addresses of extern symbols, continuations (^self continue, jump, slow, exitSync, exitPlain, return) musttail calls of extern functions; cc compiles them when the VM is translated and JitStencilTable is read back from the object file. For call threading an ordinary function of the VM: the state in fixed registers, holes its parameters, continuations the codes it returns (CONT_NEXT ...).

The state, in the JIT''s registers: fp (x20) the frame''s slots, rcv (x21) the receiver, st (x22) the JitState, sp (x23) the top of the operand stack, fr (x24) the Frame (x19 where the shared conventions want it: calls of compiled code, returns, exits). Before a call into the runtime that is a safepoint a stencil stores the frame''s pc and sp (sync), after it it reloads rcv. self call: entry runs a compiled callee whose frame the runtime pushed; fp, sp and fr are as before afterwards.'!

!JitStencils class methodsFor: 'declaring'!
declarations
	^#((fp 'oop *') (rcv oop) (st 'JitState *') (sp 'oop *') (fr 'Frame *'))
!
registers
	"In this order the arguments of a copy-and-patch stencil (x20-x24) and the fixed registers of a threaded one."
	^#(fp rcv st sp fr)
!
stencilCompiler
	^JitStencilCompiler
!
initialize
	JitStencilCompiler initializeStencils
!
stencilSelectors
	"My stencils in table order."
	^((self selectors select: [:s | self isStencil: s]) asSortedCollection: [:a :b | a <= b]) asArray
!
isStencil: aSelector
	^((self compiledMethodAt: aSelector) pragmas ifNil: [#()]) anySatisfy: [:p | p selector == #stencil or: [p selector == #stencil:]]
!
casesOf: aSelector
	"The cases of stencil aSelector: first and last."
	| p arg |
	p := ((self compiledMethodAt: aSelector) pragmas ifNil: [#()]) detect: [:each | each selector == #stencil or: [each selector == #stencil:]].
	p selector == #stencil ifTrue: [^#(0 0)].
	arg := p arguments first.
	arg isInteger ifTrue: [^Array with: 0 with: arg - 1].
	^arg
! !

!JitStencils methodsFor: 'stencil language'!
hole: aSymbol
	"The value the compiler patches in for hole aSymbol (HOLE_aSymbol)."
	<hole>
	^self error: 'stencils are not simulated'
!
case
	"Which copy of a stencil with copies this is."
	<stencilCase>
	^self error: 'stencils are not simulated'
!
call: entry
	"Run the compiled code at entry (a callee's entry: its frame is pushed); it returns when the callee did. fp, sp and fr are as before; rcv needs reloading."
	<callCompiled>
	^self error: 'stencils are not simulated'
!
continue
	"Continue with the next instruction."
	<continuation: #NEXT>
!
jump
	"Continue at the jump target."
	<continuation: #JUMP>
!
slow
	"Continue in the instruction's out-of-line code (its slow path)."
	<continuation: #SLOW>
!
exitSync
	"Leave to the interpreter, which continues at the frame's stored pc and sp."
	<continuation: #EXIT_SYNC>
!
exitPlain
	"Leave to the interpreter: the runtime made the frames canonical."
	<continuation: #EXIT>
!
return
	"Return to the caller's code: the frame is popped (its result is in the receiver's slot)."
	<continuation: #RETURN>
! !

!JitStencils methodsFor: 'helpers'!
push: v
	sp := sp + 1.
	sp value: v
!
sync
	"The frame's pc and sp, where the runtime and the interpreter see the code."
	fr pc: (self hole: #PC) asInt32.
	fr sp: (sp - fp + 1) asInt32
!
reloadReceiver
	"After a safepoint: a GC may have moved the receiver."
	rcv := fp at: -1
!
exit
	"Leave to the interpreter, which executes this instruction."
	self sync.
	^self exitSync
!
leaveAfterInterrupt
	"The interrupt check of an entry or a backward jump: a safepoint if one is pending. Answer whether to leave."
	st interrupt = 0 ifTrue: [^false].
	self sync.
	(jit interrupt: fr) ~= 0 ifTrue: [^true].
	self reloadReceiver.
	^false
!
finishSend: r
	"After the runtime's send (receiver and arguments counted by INFO): 0 done (the result in the receiver's slot), 1 leave, else the callee's entry."
	r = 1 ifTrue: [^self exitPlain].
	sp := sp - ((self hole: #INFO) bitAnd: 255).
	r ~= 0 ifTrue: [self call: r].
	self reloadReceiver.
	^self continue
!
store: v into: o at: i
	"Slot i of o := v, with the generational barrier (its fast path on the JitState's young bounds)."
	| lo span |
	self uint64At: o + 16 + (8 * i) put: v.
	lo := st youngLo.
	span := st youngHi - lo.
	((self isPtr: v) and: [v - lo < span and: [o - lo >= span and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]]) ifTrue: [
		jit writeBarrier: o value: v]
!
answer: v
	"A binary operation's result replaces its operands."
	sp := sp - 1.
	sp value: v.
	^self continue
!
boolean: c
	^c ifTrue: [st trueOop] ifFalse: [st falseOop]
!
byteCount: o
	"The elements of byte object o (a ByteString or ByteArray)."
	^((self numSlots: o) asUInt64 * 8) - ((self formatOf: o) - F_BYTES) asUInt64
!
compare: k of: a with: b
	"Special selector k: < > <= >= = ~= on SmallIntegers, == ~~."
	k = 2 ifTrue: [^a asInt64 < b asInt64].
	k = 3 ifTrue: [^a asInt64 > b asInt64].
	k = 4 ifTrue: [^a asInt64 <= b asInt64].
	k = 5 ifTrue: [^a asInt64 >= b asInt64].
	(k = 6 or: [k = 19]) ifTrue: [^a = b].
	^a ~= b
!
compareFloat: x with: y
	| k |
	k := self case.
	k = 2 ifTrue: [^x < y].
	k = 3 ifTrue: [^x > y].
	k = 4 ifTrue: [^x <= y].
	k = 5 ifTrue: [^x >= y].
	k = 6 ifTrue: [^x = y].
	^x ~= y
!
compareJumpIf: sense
	"A comparison followed by a conditional jump: the Boolean is never pushed. Operands that are not SmallIntegers go out of line, where the comparison pushes the Boolean and the jump's own code follows."
	| a b |
	a := sp at: -1.
	b := sp value.
	(self case < 19 and: [(self isInt: (a bitAnd: b)) not]) ifTrue: [^self slow].
	sp := sp - 2.
	(self compare: self case of: a with: b) = sense ifTrue: [^self jump].
	^self continue
!
operand
	"The second operand of a superinstruction (case rem: 3): temp B (0), literal B (1), the SmallInteger VALUE (2)."
	(self case rem: 3) = 0 ifTrue: [^fp at: (self hole: #B)].
	(self case rem: 3) = 1 ifTrue: [^fr lits at: (self hole: #B)].
	^self hole: #VALUE
!
pushOperands: a and: b
	"Out of line with the operands on the stack, as the superinstruction pushes them."
	sp at: 1 put: a.
	sp at: 2 put: b.
	sp := sp + 2.
	^self slow
!
operate: k into: toTemp
	"+ (k 0) or - (1) of temp A and the operand, SmallIntegers: the result pushed, or into temp C (a following pop into a temp)."
	| a b |
	a := fp at: (self hole: #A).
	b := self operand.
	(self isInt: (a bitAnd: b)) ifTrue: [
		k = 0
			ifTrue: [a asInt64 ifNoOverflowAdd: b asInt64 - 1 do: [:r | ^self result: r asUInt64 into: toTemp]]
			ifFalse: [a asInt64 ifNoOverflowSub: b asInt64 - 1 do: [:r | ^self result: r asUInt64 into: toTemp]]].
	^self pushOperands: a and: b
!
result: v into: toTemp
	toTemp ifTrue: [fp at: (self hole: #C) put: v] ifFalse: [self push: v].
	^self continue
!
compareOperandsJumpIf: sense
	"< > <= >= ((case quo: 3) + 2) of temp A and the operand, SmallIntegers, then a conditional jump."
	| a b |
	a := fp at: (self hole: #A).
	b := self operand.
	(self isInt: (a bitAnd: b)) ifFalse: [^self pushOperands: a and: b].
	(self compare: (self case quo: 3) + 2 of: a with: b) = sense ifTrue: [^self jump].
	^self continue
!
returnValue: v
	"Pop the frame, v into the caller's slot (the receiver's), back to the caller's code. The bottom frame returns into a Context: the interpreter does it."
	(self cCoerce: fr to: 'uint64_t') = st frames ifTrue: [^self exit].
	fr ctx ~= st nilOop ifTrue: [
		self sync.
		jit widow: fr].
	fp at: -1 put: v.
	^self return
! !

!JitStencils methodsFor: 'stencils: pushes and stores'!
pushTemp
	<stencil: 16>
	self push: (fp at: self case).
	^self continue
!
pushTempX
	<stencil>
	self push: (fp at: (self hole: #A)).
	^self continue
!
pushInstVar
	<stencil: 16>
	self push: ((self slotsOf: rcv) at: self case).
	^self continue
!
pushInstVarX
	<stencil>
	self push: ((self slotsOf: rcv) at: (self hole: #A)).
	^self continue
!
pushLiteral
	<stencil: 32>
	self push: (fr lits at: self case).
	^self continue
!
pushLiteralX
	<stencil>
	self push: (fr lits at: (self hole: #A)).
	^self continue
!
pushLiteralVariable
	<stencil: 32>
	self push: ((self slotsOf: (fr lits at: self case)) at: ASSOC_VALUE).
	^self continue
!
pushLiteralVariableX
	<stencil>
	self push: ((self slotsOf: (fr lits at: (self hole: #A))) at: ASSOC_VALUE).
	^self continue
!
pushSelf
	<stencil>
	self push: rcv.
	^self continue
!
pushTrue
	<stencil>
	self push: st trueOop.
	^self continue
!
pushFalse
	<stencil>
	self push: st falseOop.
	^self continue
!
pushNil
	<stencil>
	self push: st nilOop.
	^self continue
!
pushZero
	<stencil>
	self push: (self intOop: 0).
	^self continue
!
pushOne
	<stencil>
	self push: (self intOop: 1).
	^self continue
!
pushConstant
	"An immediate (VALUE): pushInteger, the SmallInteger operand of a superinstruction."
	<stencil>
	self push: (self hole: #VALUE).
	^self continue
!
dup
	<stencil>
	sp at: 1 put: sp value.
	sp := sp + 1.
	^self continue
!
pop
	<stencil>
	sp := sp - 1.
	^self continue
!
popStoreTemp
	<stencil: 8>
	fp at: self case put: sp value.
	sp := sp - 1.
	^self continue
!
popStoreTempX
	<stencil>
	fp at: (self hole: #A) put: sp value.
	sp := sp - 1.
	^self continue
!
storeTempX
	<stencil>
	fp at: (self hole: #A) put: sp value.
	^self continue
!
storeInstVarX
	"An immutable receiver: the interpreter sends attemptToAssign:withIndex:."
	<stencil>
	(self isImmutable: rcv) ifTrue: [^self exit].
	self store: sp value into: rcv at: (self hole: #A).
	^self continue
!
storeLiteralVariableX
	<stencil>
	self store: sp value into: (fr lits at: (self hole: #A)) at: ASSOC_VALUE.
	^self continue
!
popStoreLiteralVariableX
	<stencil>
	self store: sp value into: (fr lits at: (self hole: #A)) at: ASSOC_VALUE.
	sp := sp - 1.
	^self continue
!
outerTemp
	"push (8A: case 0), store (8B: 1), pop and store (8C: 2) temp B of the Context A outer levels out: in its frame if it is married (its sender is the frame's index), else in the Context."
	<stencil: 3>
	| c k f |
	c := self loadRef: fr closure at: BC_OUTER.
	2 to: (self hole: #A) do: [:i | c := self loadRef: (self loadRef: c at: CTX_CLOSURE) at: BC_OUTER].
	k := self loadRef: c at: CTX_SENDER.
	(self isInt: k)
		ifTrue: [
			f := (self cCoerce: st frames to: 'Frame *') + (self intVal: k).
			self case = 0
				ifTrue: [self push: (f fp at: (self hole: #B))]
				ifFalse: [f fp at: (self hole: #B) put: sp value]]
		ifFalse: [
			self case = 0
				ifTrue: [self push: (self loadRef: c at: CTX_FIXED + (self hole: #B))]
				ifFalse: [self store: sp value into: c at: CTX_FIXED + (self hole: #B)]].
	self case = 2 ifTrue: [sp := sp - 1].
	^self continue
!
makeArray
	"94 A: the top A slots into an Array (the runtime)."
	<stencil>
	self sync.
	(jit makeArray: fr) ~= 0 ifTrue: [^self exitPlain].
	sp := sp - (self hole: #A) + 1.
	self reloadReceiver.
	^self continue
!
closure
	"8F: a BlockClosure (the runtime), then past the block's code (JUMP)."
	<stencil>
	self sync.
	(jit closure: fr) ~= 0 ifTrue: [^self exitPlain].
	sp := sp + 1.
	self reloadReceiver.
	^self jump
! !

!JitStencils methodsFor: 'stencils: control'!
entry
	"A method's or block's start (after the prologue): an interrupt check."
	<stencil>
	self leaveAfterInterrupt ifTrue: [^self exitPlain].
	^self continue
!
branch
	<stencil>
	^self jump
!
branchBack
	"A backward jump (PC: its target, a loop head): an interrupt check."
	<stencil>
	self leaveAfterInterrupt ifTrue: [^self exitPlain].
	^self jump
!
branchIf
	"Pop, jump if true (91: case 0) or false (92: case 1). Neither: the interpreter sends mustBeBoolean."
	<stencil: 2>
	| v |
	v := sp value.
	v = (self case = 0 ifTrue: [st trueOop] ifFalse: [st falseOop]) ifTrue: [
		sp := sp - 1.
		^self jump].
	v ~= (self case = 0 ifTrue: [st falseOop] ifFalse: [st trueOop]) ifTrue: [^self exit].
	sp := sp - 1.
	^self continue
!
returnTop
	<stencil>
	^self returnValue: sp value
!
returnSelf
	<stencil>
	^self returnValue: rcv
!
toInterpreter
	"thisContext, non-local returns: the interpreter executes the instruction."
	<stencil>
	^self exit
! !

!JitStencils methodsFor: 'stencils: sends'!
send
	"A send (8D, 8E, C0-EF; INFO and SITE as for JitRuntime>>send:info:site:) through the runtime."
	<stencil>
	self sync.
	^self finishSend: (jit send: fr info: (self hole: #INFO) site: (self hole: #SITE))
!
specialSend
	"A special selector the inline path did not handle (or has none): the runtime's fast paths, else the send."
	<stencil>
	self sync.
	^self finishSend: (jit special: fr info: (self hole: #INFO) site: (self hole: #SITE))
!
floatOperation
	"The out-of-line path of + - < > <= >= = ~= * / (case: the special selector): two numbers, at least one a Float, unboxed when the result is a SmallFloat64; else the runtime."
	<stencil: 10>
	| a b x y f |
	a := sp at: -1.
	b := sp value.
	(interpreter isFloatPair: a and: b) ifTrue: [
		x := interpreter numVal: a.
		y := interpreter numVal: b.
		(self case >= 2 and: [self case <= 7]) ifTrue: [^self answer: (self boolean: (self compareFloat: x with: y))].
		(self case ~= 9 or: [y ~= 0.0]) ifTrue: [
			f := interpreter floatImm: (self case = 0
				ifTrue: [x + y]
				ifFalse: [self case = 1 ifTrue: [x - y] ifFalse: [self case = 8 ifTrue: [x * y] ifFalse: [x / y]]]).
			f ~= 0 ifTrue: [^self answer: f]]].
	self sync.
	^self finishSend: (jit special: fr info: (self hole: #INFO) site: (self hole: #SITE))
! !

!JitStencils methodsFor: 'stencils: superinstructions'!
addOperands
	"Superinstructions: push temp A, push the operand (case: temp, literal, SmallInteger), +."
	<stencil: 3>
	^self operate: 0 into: false
!
addOperandsInto
	"The same, followed by a pop into temp C."
	<stencil: 3>
	^self operate: 0 into: true
!
subtractOperands
	<stencil: 3>
	^self operate: 1 into: false
!
subtractOperandsInto
	<stencil: 3>
	^self operate: 1 into: true
!
compareOperands
	"push temp A, push the operand (case rem: 3), < > <= >= ((case quo: 3) + 2): the Boolean pushed."
	<stencil: 12>
	| a b |
	a := fp at: (self hole: #A).
	b := self operand.
	(self isInt: (a bitAnd: b)) ifFalse: [^self pushOperands: a and: b].
	self push: (self boolean: (self compare: (self case quo: 3) + 2 of: a with: b)).
	^self continue
!
compareOperandsJumpTrue
	<stencil: 12>
	^self compareOperandsJumpIf: true
!
compareOperandsJumpFalse
	<stencil: 12>
	^self compareOperandsJumpIf: false
! !

!JitStencils methodsFor: 'stencils: special selectors'!
add
	<stencil>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [a asInt64 ifNoOverflowAdd: b asInt64 - 1 do: [:r | ^self answer: r asUInt64]].
	^self slow
!
subtract
	<stencil>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [a asInt64 ifNoOverflowSub: b asInt64 - 1 do: [:r | ^self answer: r asUInt64]].
	^self slow
!
multiply
	<stencil>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [
		(self intVal: a) ifNoOverflowMul: (self intVal: b) do: [:r | (self intFits: r) ifTrue: [^self answer: (self intOop: r)]]].
	^self slow
!
divide
	"/ of SmallIntegers that divide exactly; else out of line."
	<stencil>
	| a b x y |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [
		x := self intVal: a.
		y := self intVal: b.
		(y ~= 0 and: [(x rem: y) = 0 and: [self intFits: (x quo: y)]]) ifTrue: [^self answer: (self intOop: (x quo: y))]].
	^self slow
!
modulo
	<stencil>
	| a b |
	a := sp at: -1.
	b := sp value.
	((self isInt: (a bitAnd: b)) and: [(self intVal: b) ~= 0]) ifTrue: [
		^self answer: (self intOop: (interpreter floorMod: (self intVal: a) by: (self intVal: b)))].
	^self slow
!
floorDivide
	<stencil>
	| a b q |
	a := sp at: -1.
	b := sp value.
	((self isInt: (a bitAnd: b)) and: [(self intVal: b) ~= 0]) ifTrue: [
		q := interpreter floorDiv: (self intVal: a) by: (self intVal: b).
		(self intFits: q) ifTrue: [^self answer: (self intOop: q)]].
	^self slow
!
bitAnd
	<stencil>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [^self answer: (a bitAnd: b)].
	^self slow
!
bitOr
	<stencil>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [^self answer: (a bitOr: b)].
	^self slow
!
compare
	"< > <= >= = ~= (case: the special selector) on SmallIntegers; else out of line."
	<stencil: #(2 7)>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifFalse: [^self slow].
	^self answer: (self boolean: (self compare: self case of: a with: b))
!
compareJumpTrue
	<stencil: #(2 7)>
	^self compareJumpIf: true
!
compareJumpFalse
	<stencil: #(2 7)>
	^self compareJumpIf: false
!
identical
	"== (case 19), ~~ (20)"
	<stencil: #(19 20)>
	| a b |
	a := sp at: -1.
	b := sp value.
	^self answer: (self boolean: (self compare: self case of: a with: b))
!
identicalJumpTrue
	<stencil: #(19 20)>
	^self compareJumpIf: true
!
identicalJumpFalse
	<stencil: #(19 20)>
	^self compareJumpIf: false
!
basicAt
	"at: on an Array, a ByteString or a ByteArray; else out of line."
	<stencil>
	| a b c i |
	a := sp at: -1.
	b := sp value.
	((self isInt: b) and: [self isPtr: a]) ifFalse: [^self slow].
	i := ((self intVal: b) - 1) asUInt64.
	c := self rawClass: a.
	c = st arrayClass ifTrue: [
		i < (self numSlots: a) ifTrue: [^self answer: ((self slotsOf: a) at: i)].
		^self slow].
	(i < (self byteCount: a) and: [c = memory clsBytestring]) ifTrue: [^self answer: (self charOop: ((self bytesOf: a) at: i))].
	(i < (self byteCount: a) and: [c = memory clsBytearray]) ifTrue: [^self answer: (self intOop: ((self bytesOf: a) at: i))].
	^self slow
!
basicAtPut
	"at:put: on a mutable Array, ByteString (a Character below 256) or ByteArray (a SmallInteger 0-255); else out of line."
	<stencil>
	| a b v c i |
	a := sp at: -2.
	b := sp at: -1.
	v := sp value.
	((self isInt: b) and: [(self isPtr: a) and: [(self isImmutable: a) not]]) ifFalse: [^self slow].
	i := ((self intVal: b) - 1) asUInt64.
	c := self rawClass: a.
	c = st arrayClass
		ifTrue: [
			i < (self numSlots: a) ifFalse: [^self slow].
			self store: v into: a at: i]
		ifFalse: [
			(i < (self byteCount: a) and: [(c = memory clsBytestring and: [(self isChar: v) and: [(self charVal: v) < 256]])
				or: [c = memory clsBytearray and: [(self isInt: v) and: [(self intVal: v) asUInt64 < 256]]]]) ifFalse: [^self slow].
			(self bytesOf: a) at: i put: (c = memory clsBytestring ifTrue: [(self charVal: v) asUInt8] ifFalse: [(self intVal: v) asUInt8])].
	sp := sp - 2.
	sp value: v.
	^self continue
!
basicSize
	"size of an Array, a ByteString or a ByteArray; else out of line."
	<stencil>
	| a c |
	a := sp value.
	(self isPtr: a) ifFalse: [^self slow].
	c := self rawClass: a.
	c = st arrayClass ifTrue: [
		sp value: (self intOop: (self numSlots: a)).
		^self continue].
	(c = memory clsBytestring or: [c = memory clsBytearray]) ifTrue: [
		sp value: (self intOop: (self byteCount: a) asInt64).
		^self continue].
	^self slow
!
pointCoordinate
	"x (case 27), y (28) of a Point; else out of line."
	<stencil: #(27 28)>
	| p |
	p := sp value.
	((self isPtr: p) and: [(self rawClass: p) = st pointClass]) ifTrue: [
		sp value: ((self slotsOf: p) at: self case - 27).
		^self continue].
	^self slow
!
classOf
	"class of an object; an immediate goes out of line."
	<stencil>
	| o |
	o := sp value.
	(self isPtr: o) ifTrue: [
		sp value: (self rawClass: o).
		^self continue].
	^self slow
! !
