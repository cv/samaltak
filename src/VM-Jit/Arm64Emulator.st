Object subclass: #Arm64Emulator
	instanceVariableNames: 'memory regs fregs nzcv pc ipc stackTop depth prototypes'
	classVariableNames: ''
	package: 'VM-Jit'!

Arm64Emulator comment: 'I execute arm64 machine code stored in a SimulatedMemory, so that JIT-generated code runs in the simulator. call:type:arguments: calls code as a C function (AAPCS64); code that branches (blr, br) to the address of a FunctionPointer calls that Lowtalk function, typed by its <c:> pragma. Calls may nest.

Registers hold non-negative integers below 2^64: regs are x0-x30 and sp (index 32), fregs the 64 bits of d0-d31, nzcv is N<<3|Z<<2|C<<1|V. The supported instructions are the integer, load/store, branch and scalar double subset the JIT uses; anything else signals Arm64EmulationError.'!

Error subclass: #Arm64EmulationError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

Arm64EmulationError comment: 'The emulated code did something I do not emulate: an unsupported instruction, brk, an unsupported call signature.'!

!Arm64Emulator class methodsFor: 'instance creation'!
memory: aSimulatedMemory
	^self new setMemory: aSimulatedMemory
! !

!Arm64Emulator methodsFor: 'initialization'!
setMemory: aSimulatedMemory
	| size |
	memory := aSimulatedMemory.
	regs := Array new: 32 withAll: 0.
	fregs := Array new: 32 withAll: 0.
	nzcv := 0.
	pc := 0.
	depth := 0.
	prototypes := Dictionary new.
	size := 1024 * 1024.
	stackTop := (memory allocate: size) + size.
	regs at: 32 put: stackTop
! !

!Arm64Emulator methodsFor: 'accessing'!
memory
	^memory
!
x: n
	^regs at: n + 1
!
x: n put: anInteger
	regs at: n + 1 put: (self wrap64: anInteger)
!
w: n
	^(regs at: n + 1) bitAnd: 16rFFFFFFFF
!
d: n
	^Float fromIEEEBits: (fregs at: n + 1)
!
d: n put: aNumber
	fregs at: n + 1 put: aNumber asFloat asIEEEBits
!
dBits: n
	^fregs at: n + 1
!
dBits: n put: anInteger
	fregs at: n + 1 put: anInteger
!
sp
	^regs at: 32
!
sp: anInteger
	regs at: 32 put: anInteger
!
pc
	^pc
!
pc: anInteger
	pc := anInteger
!
nzcv
	^nzcv
!
nzcv: anInteger
	nzcv := anInteger
!
stackTop
	^stackTop
!
returnAddress
	"Where call:type:arguments: returns to: in no segment."
	^16r7E0000000000
! !

!Arm64Emulator methodsFor: 'running'!
step
	"Execute one instruction."
	ipc := pc.
	pc := pc + 4.
	self execute: (memory uint32At: ipc)
!
runUntil: stopAddress
	[pc = stopAddress] whileFalse: [self step]
!
runFrom: anAddress until: stopAddress
	pc := anAddress.
	self runUntil: stopAddress
! !

!Arm64Emulator methodsFor: 'calling'!
call: anAddress type: aFunctionType arguments: anArray
	"Call the code at anAddress as a C function of aFunctionType; answer its result as a Lowtalk value. A nested call (from a Lowtalk function the code called) runs below the caller's frames and leaves the caller's registers as they were."
	| saved ints floats |
	aFunctionType isVariadic ifTrue: [^self fail: 'variadic functions are not supported'].
	anArray size = aFunctionType parameterTypes size ifFalse: [^self fail: 'wrong number of arguments'].
	saved := depth > 0 ifTrue: [{regs copy. fregs copy. nzcv. pc}] ifFalse: [nil].
	^[
		depth = 0 ifTrue: [regs at: 32 put: stackTop].
		depth := depth + 1.
		ints := 0.
		floats := 0.
		aFunctionType parameterTypes with: anArray do: [:type :arg |
			(self isDouble: type)
				ifTrue: [
					floats := floats + 1.
					floats > 8 ifTrue: [^self fail: 'more than 8 double arguments'].
					fregs at: floats put: arg asFloat asIEEEBits]
				ifFalse: [
					ints := ints + 1.
					ints > 8 ifTrue: [^self fail: 'more than 8 integer arguments'].
					regs at: ints put: (self bitsOf: arg as: type)]].
		regs at: 31 put: self returnAddress.
		pc := anAddress.
		self runUntil: self returnAddress.
		self resultOfType: aFunctionType returnType]
			ensure: [
				depth := depth - 1.
				saved isNil ifFalse: [
					regs := saved at: 1.
					fregs := saved at: 2.
					nzcv := saved at: 3.
					pc := saved at: 4]]
!
callHost: aFunctionPointer
	"Call a Lowtalk function with the arguments in x0-x7 and d0-d7; its result goes to x0 or d0."
	| type ints floats args result |
	type := self prototypeOf: aFunctionPointer.
	ints := 0.
	floats := 0.
	args := type parameterTypes collect: [:t |
		(self isDouble: t)
			ifTrue: [
				floats := floats + 1.
				floats > 8 ifTrue: [^self fail: 'more than 8 double arguments'].
				Float fromIEEEBits: (fregs at: floats)]
			ifFalse: [
				ints := ints + 1.
				ints > 8 ifTrue: [^self fail: 'more than 8 integer arguments'].
				self valueOf: (regs at: ints) as: t]].
	result := aFunctionPointer callWithArguments: args.
	type returnType isVoid ifTrue: [^self].
	(self isDouble: type returnType)
		ifTrue: [fregs at: 1 put: result asFloat asIEEEBits]
		ifFalse: [regs at: 1 put: (self bitsOf: result as: type returnType)]
!
prototypeOf: aFunctionPointer
	"The CFunctionType of the <c:> pragma of the function's method."
	^prototypes at: aFunctionPointer ifAbsent: [
		| method pragma type |
		method := aFunctionPointer receiver class lookupSelector: aFunctionPointer selector.
		pragma := method isNil ifTrue: [nil] ifFalse: [method pragmaAt: #c:].
		pragma isNil ifTrue: [^self fail: 'no C prototype for ' , aFunctionPointer printString].
		type := (CTypeRegistry default parsePrototype: (pragma arguments at: 1)) at: 2.
		type isVariadic ifTrue: [^self fail: 'variadic functions are not supported: ' , aFunctionPointer printString].
		prototypes at: aFunctionPointer put: type]
!
isDouble: aCType
	aCType isFloat ifFalse: [^false].
	aCType size = 8 ifFalse: [^self fail: 'float arguments are not supported'].
	^true
!
bitsOf: aValue as: aCType
	"aValue (a Lowtalk value of aCType) in a 64-bit register."
	aCType isBool ifTrue: [^aValue ifTrue: [1] ifFalse: [0]].
	aCType isInteger ifTrue: [^self wrap64: aValue].
	aCType isPointer ifTrue: [^self wrap64: (memory addressOf: aValue)].
	^self fail: 'unsupported C type ' , aCType name
!
valueOf: anInteger as: aCType
	"A 64-bit register as a Lowtalk value of aCType."
	aCType isBool ifTrue: [^(anInteger bitAnd: 255) ~= 0].
	aCType isInteger ifTrue: [^aCType wrap: anInteger].
	aCType isPointer ifTrue: [^memory pointerTo: aCType target at: anInteger].
	^self fail: 'unsupported C type ' , aCType name
!
resultOfType: aCType
	aCType isVoid ifTrue: [^nil].
	(self isDouble: aCType) ifTrue: [^Float fromIEEEBits: (fregs at: 1)].
	^self valueOf: (regs at: 1) as: aCType
!
jumpTo: anAddress
	"Branch to anAddress, or call the Lowtalk function there and return to x30."
	| fp |
	fp := memory objectAt: anAddress ifAbsent: [nil].
	(fp isKindOf: FunctionPointer) ifFalse: [^pc := anAddress].
	self callHost: fp.
	pc := regs at: 31
! !

!Arm64Emulator methodsFor: 'errors'!
fail: aString
	^Arm64EmulationError signal: aString
!
unsupported: w
	pc := ipc.
	^self fail: 'unsupported instruction 16r' , (w printStringBase: 16) , ' at 16r' , (ipc printStringBase: 16)
! !

!Arm64Emulator methodsFor: 'private-values'!
wrap64: v
	(v >= 0 and: [v <= 16rFFFFFFFFFFFFFFFF]) ifTrue: [^v].
	^v bitAnd: 16rFFFFFFFFFFFFFFFF
!
wrap: v sf: sf
	sf = 1 ifTrue: [^self wrap64: v].
	^v bitAnd: 16rFFFFFFFF
!
mask: sf
	^sf = 1 ifTrue: [16rFFFFFFFFFFFFFFFF] ifFalse: [16rFFFFFFFF]
!
signed: v sf: sf
	sf = 1 ifTrue: [^v >= 16r8000000000000000 ifTrue: [v - 16r10000000000000000] ifFalse: [v]].
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
!
signExtend: v bits: n
	^v >= (1 bitShift: n - 1) ifTrue: [v - (1 bitShift: n)] ifFalse: [v]
!
r: n
	"Register n, 31 is the zero register."
	n = 31 ifTrue: [^0].
	^regs at: n + 1
!
r: n sf: sf
	n = 31 ifTrue: [^0].
	sf = 1 ifTrue: [^regs at: n + 1].
	^(regs at: n + 1) bitAnd: 16rFFFFFFFF
!
rsp: n sf: sf
	"Register n, 31 is sp."
	sf = 1 ifTrue: [^regs at: n + 1].
	^(regs at: n + 1) bitAnd: 16rFFFFFFFF
!
r: n put: v
	n = 31 ifFalse: [regs at: n + 1 put: v]
!
rsp: n put: v
	regs at: n + 1 put: v
!
condition: cond
	| base result |
	base := cond bitShift: -1.
	base = 0 ifTrue: [result := (nzcv bitAnd: 4) ~= 0].
	base = 1 ifTrue: [result := (nzcv bitAnd: 2) ~= 0].
	base = 2 ifTrue: [result := (nzcv bitAnd: 8) ~= 0].
	base = 3 ifTrue: [result := (nzcv bitAnd: 1) ~= 0].
	base = 4 ifTrue: [result := (nzcv bitAnd: 6) = 2].
	base = 5 ifTrue: [result := (nzcv bitShift: -3) = (nzcv bitAnd: 1)].
	base = 6 ifTrue: [result := (nzcv bitAnd: 4) = 0 and: [(nzcv bitShift: -3) = (nzcv bitAnd: 1)]].
	base = 7 ifTrue: [^true].
	(cond bitAnd: 1) = 1 ifTrue: [^result not].
	^result
!
add: x to: y carry: c sf: sf flags: setFlags
	"AddWithCarry of the ARM ARM; x and y fit the data size."
	| size sum result half |
	size := sf = 1 ifTrue: [16r10000000000000000] ifFalse: [16r100000000].
	sum := x + y + c.
	result := sum >= size ifTrue: [sum - size] ifFalse: [sum].
	setFlags ifTrue: [
		half := size bitShift: -1.
		nzcv := (result >= half ifTrue: [8] ifFalse: [0])
			+ (result = 0 ifTrue: [4] ifFalse: [0])
			+ (sum >= size ifTrue: [2] ifFalse: [0])
			+ (((x >= half) = (y >= half) and: [(result >= half) ~= (x >= half)]) ifTrue: [1] ifFalse: [0])].
	^result
!
shift: v type: t amount: a sf: sf
	"LSL, LSR, ASR, ROR of a data-size value."
	a = 0 ifTrue: [^v].
	t = 0 ifTrue: [^self wrap: (v bitShift: a) sf: sf].
	t = 1 ifTrue: [^v bitShift: a negated].
	t = 2 ifTrue: [^self wrap: ((self signed: v sf: sf) bitShift: a negated) sf: sf].
	^self wrap: ((v bitShift: a negated) bitOr: (v bitShift: (sf = 1 ifTrue: [64] ifFalse: [32]) - a)) sf: sf
!
extend: v option: option
	"UXTB UXTH UXTW UXTX SXTB SXTH SXTW SXTX; signed results may be negative."
	option = 0 ifTrue: [^v bitAnd: 16rFF].
	option = 1 ifTrue: [^v bitAnd: 16rFFFF].
	option = 2 ifTrue: [^v bitAnd: 16rFFFFFFFF].
	option = 3 ifTrue: [^v].
	option = 4 ifTrue: [^self signExtend: (v bitAnd: 16rFF) bits: 8].
	option = 5 ifTrue: [^self signExtend: (v bitAnd: 16rFFFF) bits: 16].
	option = 6 ifTrue: [^self signExtend: (v bitAnd: 16rFFFFFFFF) bits: 32].
	^self signExtend: v bits: 64
!
logical: opc n: n m: m sf: sf
	"AND ORR EOR ANDS"
	| result |
	opc = 1 ifTrue: [^n bitOr: m].
	opc = 2 ifTrue: [^n bitXor: m].
	result := n bitAnd: m.
	opc = 3 ifTrue: [
		nzcv := (result >= (sf = 1 ifTrue: [16r8000000000000000] ifFalse: [16r80000000]) ifTrue: [8] ifFalse: [0])
			+ (result = 0 ifTrue: [4] ifFalse: [0])].
	^result
!
decodeBitMasks: nbit immr: immr imms: imms size: datasize
	"The logical immediate N:immr:imms stands for (DecodeBitMasks of the ARM ARM); nil if reserved."
	| len levels s r esize welem result |
	len := ((nbit bitShift: 6) bitOr: (imms bitXor: 63)) highBit - 1.
	len < 1 ifTrue: [^nil].
	levels := (1 bitShift: len) - 1.
	s := imms bitAnd: levels.
	s = levels ifTrue: [^nil].
	r := immr bitAnd: levels.
	esize := 1 bitShift: len.
	esize > datasize ifTrue: [^nil].
	welem := (1 bitShift: s + 1) - 1.
	welem := ((welem bitShift: r negated) bitOr: (welem bitShift: esize - r)) bitAnd: (1 bitShift: esize) - 1.
	result := welem.
	[esize < datasize] whileTrue: [
		result := result bitOr: (result bitShift: esize).
		esize := esize * 2].
	^result
! !

!Arm64Emulator methodsFor: 'private-decoding'!
execute: w
	| op |
	op := (w bitShift: -25) bitAnd: 15.
	(op bitAnd: 14) = 8 ifTrue: [^self dataImmediate: w].
	(op bitAnd: 14) = 10 ifTrue: [^self branch: w].
	(op bitAnd: 5) = 4 ifTrue: [^self loadStore: w].
	(op bitAnd: 7) = 5 ifTrue: [^self dataRegister: w].
	(op bitAnd: 7) = 7 ifTrue: [^self floatingPoint: w].
	^self unsupported: w
!
dataImmediate: w
	| op |
	op := (w bitShift: -23) bitAnd: 7.
	op <= 1 ifTrue: [^self pcRelative: w].
	op = 2 ifTrue: [^self addSubImmediate: w].
	op = 4 ifTrue: [^self logicalImmediate: w].
	op = 5 ifTrue: [^self moveWide: w].
	op = 6 ifTrue: [^self bitfield: w].
	op = 7 ifTrue: [^self extract: w].
	^self unsupported: w
!
dataRegister: w
	| op2 |
	op2 := (w bitShift: -21) bitAnd: 15.
	((w bitShift: -28) bitAnd: 1) = 0 ifTrue: [
		(op2 bitAnd: 8) = 0 ifTrue: [^self logicalShifted: w].
		(op2 bitAnd: 1) = 0 ifTrue: [^self addSubShifted: w].
		^self addSubExtended: w].
	op2 = 4 ifTrue: [^self conditionalSelect: w].
	op2 = 6 ifTrue: [
		^((w bitShift: -30) bitAnd: 1) = 0
			ifTrue: [self dataProcessing2: w]
			ifFalse: [self dataProcessing1: w]].
	op2 >= 8 ifTrue: [^self dataProcessing3: w].
	^self unsupported: w
!
branch: w
	| op |
	(w bitAnd: 16r7C000000) = 16r14000000 ifTrue: [
		(w bitShift: -31) = 1 ifTrue: [regs at: 31 put: pc].
		^pc := self wrap64: ipc + ((self signExtend: (w bitAnd: 16r3FFFFFF) bits: 26) * 4)].
	(w bitAnd: 16r7E000000) = 16r34000000 ifTrue: [^self compareAndBranch: w].
	(w bitAnd: 16r7E000000) = 16r36000000 ifTrue: [^self testAndBranch: w].
	(w bitAnd: 16rFF000010) = 16r54000000 ifTrue: [
		^(self condition: (w bitAnd: 15)) ifTrue: [pc := self branchTarget19: w]].
	(w bitAnd: 16rFF9FFC1F) = 16rD61F0000 ifTrue: [
		op := (w bitShift: -21) bitAnd: 3.
		op = 3 ifTrue: [^self unsupported: w].
		op = 2 ifTrue: [^pc := self r: ((w bitShift: -5) bitAnd: 31)].
		^self jumpTo: (self r: ((w bitShift: -5) bitAnd: 31)) link: op = 1].
	(w bitAnd: 16rFFE0001F) = 16rD4200000 ifTrue: [
		pc := ipc.
		^self fail: 'brk #16r' , (((w bitShift: -5) bitAnd: 16rFFFF) printStringBase: 16) , ' at 16r' , (ipc printStringBase: 16)].
	(w bitAnd: 16rFFFFF01F) = 16rD503201F ifTrue: [^self "hint: nop"].
	((w bitAnd: 16rFFFFF01F) = 16rD503301F and: [((w bitShift: -5) bitAnd: 7) between: 4 and: 6]) ifTrue: [^self "dsb dmb isb"].
	^self unsupported: w
!
jumpTo: anAddress link: aBoolean
	aBoolean ifTrue: [regs at: 31 put: pc].
	self jumpTo: anAddress
!
branchTarget19: w
	^self wrap64: ipc + ((self signExtend: ((w bitShift: -5) bitAnd: 16r7FFFF) bits: 19) * 4)
!
compareAndBranch: w
	"cbz cbnz"
	| zero |
	zero := (self r: (w bitAnd: 31) sf: (w bitShift: -31)) = 0.
	zero = (((w bitShift: -24) bitAnd: 1) = 0) ifTrue: [pc := self branchTarget19: w]
!
testAndBranch: w
	"tbz tbnz"
	| bit |
	bit := ((self r: (w bitAnd: 31)) bitShift: (((w bitShift: -26) bitAnd: 32) + ((w bitShift: -19) bitAnd: 31)) negated) bitAnd: 1.
	bit = ((w bitShift: -24) bitAnd: 1) ifTrue: [
		pc := self wrap64: ipc + ((self signExtend: ((w bitShift: -5) bitAnd: 16r3FFF) bits: 14) * 4)]
! !

!Arm64Emulator methodsFor: 'private-data processing'!
pcRelative: w
	"adr adrp"
	| imm |
	imm := self signExtend: (((w bitShift: -3) bitAnd: 16r1FFFFC) bitOr: ((w bitShift: -29) bitAnd: 3)) bits: 21.
	(w bitShift: -31) = 0
		ifTrue: [self r: (w bitAnd: 31) put: (self wrap64: ipc + imm)]
		ifFalse: [self r: (w bitAnd: 31) put: (self wrap64: (ipc bitClear: 16rFFF) + (imm bitShift: 12))]
!
addSubImmediate: w
	| sf imm |
	sf := w bitShift: -31.
	imm := (w bitShift: -10) bitAnd: 16rFFF.
	((w bitShift: -22) bitAnd: 1) = 1 ifTrue: [imm := imm bitShift: 12].
	self addSub: w n: (self rsp: ((w bitShift: -5) bitAnd: 31) sf: sf) m: imm sf: sf rdSP: true
!
addSubShifted: w
	| sf type amount m |
	sf := w bitShift: -31.
	type := (w bitShift: -22) bitAnd: 3.
	amount := (w bitShift: -10) bitAnd: 63.
	(type = 3 or: [sf = 0 and: [amount >= 32]]) ifTrue: [^self unsupported: w].
	m := self shift: (self r: ((w bitShift: -16) bitAnd: 31) sf: sf) type: type amount: amount sf: sf.
	self addSub: w n: (self r: ((w bitShift: -5) bitAnd: 31) sf: sf) m: m sf: sf rdSP: false
!
addSubExtended: w
	| sf amount m |
	sf := w bitShift: -31.
	amount := (w bitShift: -10) bitAnd: 7.
	(((w bitShift: -22) bitAnd: 3) ~= 0 or: [amount > 4]) ifTrue: [^self unsupported: w].
	m := self wrap: ((self extend: (self r: ((w bitShift: -16) bitAnd: 31)) option: ((w bitShift: -13) bitAnd: 7)) bitShift: amount) sf: sf.
	self addSub: w n: (self rsp: ((w bitShift: -5) bitAnd: 31) sf: sf) m: m sf: sf rdSP: true
!
addSub: w n: n m: m sf: sf rdSP: aBoolean
	"add sub adds subs (op bit 30, S bit 29); without S the immediate and extended forms write sp for register 31."
	| setFlags result rd |
	setFlags := ((w bitShift: -29) bitAnd: 1) = 1.
	result := ((w bitShift: -30) bitAnd: 1) = 1
		ifTrue: [self add: n to: (self mask: sf) - m carry: 1 sf: sf flags: setFlags]
		ifFalse: [self add: n to: m carry: 0 sf: sf flags: setFlags].
	rd := w bitAnd: 31.
	(aBoolean and: [setFlags not]) ifTrue: [^self rsp: rd put: result].
	self r: rd put: result
!
logicalImmediate: w
	| sf nbit imm opc result |
	sf := w bitShift: -31.
	nbit := (w bitShift: -22) bitAnd: 1.
	(sf = 0 and: [nbit = 1]) ifTrue: [^self unsupported: w].
	imm := self decodeBitMasks: nbit immr: ((w bitShift: -16) bitAnd: 63) imms: ((w bitShift: -10) bitAnd: 63) size: (sf = 1 ifTrue: [64] ifFalse: [32]).
	imm isNil ifTrue: [^self unsupported: w].
	opc := (w bitShift: -29) bitAnd: 3.
	result := self logical: opc n: (self r: ((w bitShift: -5) bitAnd: 31) sf: sf) m: imm sf: sf.
	opc = 3 ifTrue: [^self r: (w bitAnd: 31) put: result].
	self rsp: (w bitAnd: 31) put: result
!
logicalShifted: w
	"and orr eor ands, with N: bic orn eon bics"
	| sf amount m |
	sf := w bitShift: -31.
	amount := (w bitShift: -10) bitAnd: 63.
	(sf = 0 and: [amount >= 32]) ifTrue: [^self unsupported: w].
	m := self shift: (self r: ((w bitShift: -16) bitAnd: 31) sf: sf) type: ((w bitShift: -22) bitAnd: 3) amount: amount sf: sf.
	((w bitShift: -21) bitAnd: 1) = 1 ifTrue: [m := (self mask: sf) - m].
	self r: (w bitAnd: 31) put: (self logical: ((w bitShift: -29) bitAnd: 3) n: (self r: ((w bitShift: -5) bitAnd: 31) sf: sf) m: m sf: sf)
!
moveWide: w
	"movn movz movk"
	| sf opc hw shift imm rd |
	sf := w bitShift: -31.
	opc := (w bitShift: -29) bitAnd: 3.
	hw := (w bitShift: -21) bitAnd: 3.
	(opc = 1 or: [sf = 0 and: [hw >= 2]]) ifTrue: [^self unsupported: w].
	shift := hw * 16.
	imm := ((w bitShift: -5) bitAnd: 16rFFFF) bitShift: shift.
	rd := w bitAnd: 31.
	opc = 0 ifTrue: [^self r: rd put: (self mask: sf) - imm].
	opc = 2 ifTrue: [^self r: rd put: imm].
	self r: rd put: (((self r: rd sf: sf) bitAnd: (self mask: sf) - (16rFFFF bitShift: shift)) bitOr: imm)
!
bitfield: w
	"sbfm bfm ubfm"
	| sf opc size r s src width field lsb fieldMask result |
	sf := w bitShift: -31.
	opc := (w bitShift: -29) bitAnd: 3.
	size := sf = 1 ifTrue: [64] ifFalse: [32].
	r := (w bitShift: -16) bitAnd: 63.
	s := (w bitShift: -10) bitAnd: 63.
	(opc = 3 or: [((w bitShift: -22) bitAnd: 1) ~= sf or: [r >= size or: [s >= size]]]) ifTrue: [^self unsupported: w].
	src := self r: ((w bitShift: -5) bitAnd: 31) sf: sf.
	s >= r
		ifTrue: [
			width := s - r + 1.
			field := (src bitShift: r negated) bitAnd: (1 bitShift: width) - 1.
			lsb := 0]
		ifFalse: [
			width := s + 1.
			field := src bitAnd: (1 bitShift: width) - 1.
			lsb := size - r].
	opc = 1
		ifTrue: [
			fieldMask := ((1 bitShift: width) - 1) bitShift: lsb.
			result := ((self r: (w bitAnd: 31) sf: sf) bitAnd: (self mask: sf) - fieldMask) bitOr: (field bitShift: lsb)]
		ifFalse: [
			opc = 0 ifTrue: [field := self signExtend: field bits: width].
			result := self wrap: (field bitShift: lsb) sf: sf].
	self r: (w bitAnd: 31) put: result
!
extract: w
	"extr"
	| sf size lsb n m |
	sf := w bitShift: -31.
	size := sf = 1 ifTrue: [64] ifFalse: [32].
	lsb := (w bitShift: -10) bitAnd: 63.
	(((w bitShift: -22) bitAnd: 1) ~= sf or: [((w bitShift: -29) bitAnd: 3) ~= 0 or: [((w bitShift: -21) bitAnd: 1) = 1 or: [lsb >= size]]])
		ifTrue: [^self unsupported: w].
	n := self r: ((w bitShift: -5) bitAnd: 31) sf: sf.
	m := self r: ((w bitShift: -16) bitAnd: 31) sf: sf.
	self r: (w bitAnd: 31) put: (self wrap: (((n bitShift: size) bitOr: m) bitShift: lsb negated) sf: sf)
!
conditionalSelect: w
	"csel csinc csinv csneg"
	| sf result |
	sf := w bitShift: -31.
	(((w bitShift: -29) bitAnd: 1) = 1 or: [((w bitShift: -11) bitAnd: 1) = 1]) ifTrue: [^self unsupported: w].
	(self condition: ((w bitShift: -12) bitAnd: 15))
		ifTrue: [result := self r: ((w bitShift: -5) bitAnd: 31) sf: sf]
		ifFalse: [
			result := self r: ((w bitShift: -16) bitAnd: 31) sf: sf.
			((w bitShift: -30) bitAnd: 1) = 1 ifTrue: [result := (self mask: sf) - result].
			((w bitShift: -10) bitAnd: 1) = 1 ifTrue: [result := self wrap: result + 1 sf: sf]].
	self r: (w bitAnd: 31) put: result
!
dataProcessing1: w
	"clz"
	| sf |
	sf := w bitShift: -31.
	(((w bitShift: -29) bitAnd: 1) = 0 and: [((w bitShift: -10) bitAnd: 16r7FF) = 4]) ifFalse: [^self unsupported: w].
	self r: (w bitAnd: 31) put: (sf = 1 ifTrue: [64] ifFalse: [32]) - (self r: ((w bitShift: -5) bitAnd: 31) sf: sf) highBit
!
dataProcessing2: w
	"udiv sdiv lslv lsrv asrv rorv"
	| sf opcode n m rd |
	sf := w bitShift: -31.
	opcode := (w bitShift: -10) bitAnd: 63.
	((w bitShift: -29) bitAnd: 1) = 1 ifTrue: [^self unsupported: w].
	n := self r: ((w bitShift: -5) bitAnd: 31) sf: sf.
	m := self r: ((w bitShift: -16) bitAnd: 31) sf: sf.
	rd := w bitAnd: 31.
	opcode = 2 ifTrue: [^self r: rd put: (m = 0 ifTrue: [0] ifFalse: [n // m])].
	opcode = 3 ifTrue: [
		^self r: rd put: (m = 0
			ifTrue: [0]
			ifFalse: [self wrap: ((self signed: n sf: sf) quo: (self signed: m sf: sf)) sf: sf])].
	(opcode between: 8 and: 11) ifTrue: [
		^self r: rd put: (self shift: n type: opcode - 8 amount: (m bitAnd: (sf = 1 ifTrue: [63] ifFalse: [31])) sf: sf)].
	self unsupported: w
!
dataProcessing3: w
	"madd msub smulh umulh"
	| sf op31 o0 n m a |
	sf := w bitShift: -31.
	((w bitShift: -29) bitAnd: 3) = 0 ifFalse: [^self unsupported: w].
	op31 := (w bitShift: -21) bitAnd: 7.
	o0 := (w bitShift: -15) bitAnd: 1.
	n := self r: ((w bitShift: -5) bitAnd: 31) sf: sf.
	m := self r: ((w bitShift: -16) bitAnd: 31) sf: sf.
	op31 = 0 ifTrue: [
		a := self r: ((w bitShift: -10) bitAnd: 31) sf: sf.
		^self r: (w bitAnd: 31) put: (self wrap: (o0 = 0 ifTrue: [a + (n * m)] ifFalse: [a - (n * m)]) sf: sf)].
	(sf = 1 and: [o0 = 0]) ifTrue: [
		op31 = 2 ifTrue: [^self r: (w bitAnd: 31) put: (self wrap64: ((self signed: n sf: 1) * (self signed: m sf: 1) bitShift: -64))].
		op31 = 6 ifTrue: [^self r: (w bitAnd: 31) put: (n * m bitShift: -64)]].
	self unsupported: w
! !

!Arm64Emulator methodsFor: 'private-loads and stores'!
loadStore: w
	(w bitAnd: 16r3B000000) = 16r18000000 ifTrue: [^self loadLiteral: w].
	(w bitAnd: 16r3A000000) = 16r28000000 ifTrue: [^self loadStorePair: w].
	(w bitAnd: 16r3A000000) = 16r38000000 ifTrue: [^self loadStoreRegister: w].
	^self unsupported: w
!
load: size at: anAddress
	size = 0 ifTrue: [^memory uint8At: anAddress].
	size = 1 ifTrue: [^memory uint16At: anAddress].
	size = 2 ifTrue: [^memory uint32At: anAddress].
	^memory uint64At: anAddress
!
loadSigned: size at: anAddress
	size = 0 ifTrue: [^memory int8At: anAddress].
	size = 1 ifTrue: [^memory int16At: anAddress].
	^memory int32At: anAddress
!
store: v size: size at: anAddress
	size = 0 ifTrue: [^memory uint8At: anAddress put: (v bitAnd: 16rFF)].
	size = 1 ifTrue: [^memory uint16At: anAddress put: (v bitAnd: 16rFFFF)].
	size = 2 ifTrue: [^memory uint32At: anAddress put: (v bitAnd: 16rFFFFFFFF)].
	memory uint64At: anAddress put: v
!
loadLiteral: w
	"ldr w, x, d and ldrsw (literal); prfm"
	| opc address rt |
	opc := w bitShift: -30.
	address := self branchTarget19: w.
	rt := w bitAnd: 31.
	((w bitShift: -26) bitAnd: 1) = 1 ifTrue: [
		opc = 1 ifFalse: [^self unsupported: w].
		^fregs at: rt + 1 put: (memory uint64At: address)].
	opc = 0 ifTrue: [^self r: rt put: (memory uint32At: address)].
	opc = 1 ifTrue: [^self r: rt put: (memory uint64At: address)].
	opc = 2 ifTrue: [^self r: rt put: (self wrap64: (memory int32At: address))]
!
loadStoreRegister: w
	"ldr str of all widths and signs, and ldr str d: unsigned offset, unscaled, pre and post index, register offset"
	| size v opc rn rt base address writeback kind option |
	size := w bitShift: -30.
	v := (w bitShift: -26) bitAnd: 1.
	opc := (w bitShift: -22) bitAnd: 3.
	(v = 1
		ifTrue: [size ~= 3 or: [opc > 1]]
		ifFalse: [opc = 3 and: [size >= 2]]) ifTrue: [^self unsupported: w].
	rn := (w bitShift: -5) bitAnd: 31.
	rt := w bitAnd: 31.
	base := regs at: rn + 1.
	((w bitShift: -24) bitAnd: 1) = 1
		ifTrue: [address := base + (((w bitShift: -10) bitAnd: 16rFFF) bitShift: size)]
		ifFalse: [
			kind := (w bitShift: -10) bitAnd: 3.
			((w bitShift: -21) bitAnd: 1) = 0
				ifTrue: [
					kind = 2 ifTrue: [^self unsupported: w].
					address := self wrap64: base + (self signExtend: ((w bitShift: -12) bitAnd: 511) bits: 9).
					kind = 1 ifTrue: [writeback := address. address := base].
					kind = 3 ifTrue: [writeback := address]]
				ifFalse: [
					option := (w bitShift: -13) bitAnd: 7.
					(kind = 2 and: [(option bitAnd: 2) = 2]) ifFalse: [^self unsupported: w].
					address := self wrap64: base + ((self extend: (self r: ((w bitShift: -16) bitAnd: 31)) option: option)
						bitShift: ((w bitShift: -12) bitAnd: 1) * size)]].
	v = 1
		ifTrue: [
			opc = 0
				ifTrue: [memory uint64At: address put: (fregs at: rt + 1)]
				ifFalse: [fregs at: rt + 1 put: (memory uint64At: address)]]
		ifFalse: [
			opc = 0 ifTrue: [self store: (self r: rt) size: size at: address].
			opc = 1 ifTrue: [self r: rt put: (self load: size at: address)].
			(opc = 2 and: [size < 3]) ifTrue: [self r: rt put: (self wrap64: (self loadSigned: size at: address))].
			opc = 3 ifTrue: [self r: rt put: ((self loadSigned: size at: address) bitAnd: 16rFFFFFFFF)]].
	writeback isNil ifFalse: [regs at: rn + 1 put: writeback]
!
loadStorePair: w
	"ldp stp of w, x and d registers, ldpsw: offset, pre and post index"
	| opc v load mode scale size offset rn rt rt2 base address a b |
	opc := w bitShift: -30.
	v := (w bitShift: -26) bitAnd: 1.
	load := ((w bitShift: -22) bitAnd: 1) = 1.
	mode := (w bitShift: -23) bitAnd: 3.
	(v = 1
		ifTrue: [opc ~= 1]
		ifFalse: [opc = 3 or: [opc = 1 and: [load not]]]) ifTrue: [^self unsupported: w].
	scale := (v = 1 or: [opc = 2]) ifTrue: [3] ifFalse: [2].
	size := 1 bitShift: scale.
	offset := (self signExtend: ((w bitShift: -15) bitAnd: 127) bits: 7) bitShift: scale.
	rn := (w bitShift: -5) bitAnd: 31.
	rt := w bitAnd: 31.
	rt2 := (w bitShift: -10) bitAnd: 31.
	base := regs at: rn + 1.
	address := mode = 1 ifTrue: [base] ifFalse: [self wrap64: base + offset].
	v = 1
		ifTrue: [
			load
				ifTrue: [
					fregs at: rt + 1 put: (memory uint64At: address).
					fregs at: rt2 + 1 put: (memory uint64At: address + 8)]
				ifFalse: [
					memory uint64At: address put: (fregs at: rt + 1).
					memory uint64At: address + 8 put: (fregs at: rt2 + 1)]]
		ifFalse: [
			load
				ifTrue: [
					opc = 1
						ifTrue: [
							a := self wrap64: (memory int32At: address).
							b := self wrap64: (memory int32At: address + 4)]
						ifFalse: [
							a := self load: scale at: address.
							b := self load: scale at: address + size].
					self r: rt put: a.
					self r: rt2 put: b]
				ifFalse: [
					a := self r: rt.
					b := self r: rt2.
					self store: a size: scale at: address.
					self store: b size: scale at: address + size]].
	mode = 1 ifTrue: [^regs at: rn + 1 put: (self wrap64: base + offset)].
	mode = 3 ifTrue: [regs at: rn + 1 put: address]
! !

!Arm64Emulator methodsFor: 'private-floating point'!
floatingPoint: w
	"Scalar double: data processing, compare, select, immediate, conversions."
	(w bitAnd: 16r7F200000) = 16r1E200000 ifFalse: [^self unsupported: w].
	((w bitShift: -22) bitAnd: 3) = 1 ifFalse: [^self unsupported: w].
	(w bitAnd: 16rFC00) = 0 ifTrue: [^self floatConvert: w].
	(w bitShift: -31) = 1 ifTrue: [^self unsupported: w].
	(w bitAnd: 16rC00) = 16rC00 ifTrue: [
		^fregs at: (w bitAnd: 31) + 1 put: ((self condition: ((w bitShift: -12) bitAnd: 15))
			ifTrue: [fregs at: ((w bitShift: -5) bitAnd: 31) + 1]
			ifFalse: [fregs at: ((w bitShift: -16) bitAnd: 31) + 1])].
	(w bitAnd: 16rC00) = 16r800 ifTrue: [^self floatDataProcessing2: w].
	(w bitAnd: 16r1C00) = 16r1000 ifTrue: [^self floatImmediate: w].
	(w bitAnd: 16r3C00) = 16r2000 ifTrue: [^self floatCompare: w].
	(w bitAnd: 16r7C00) = 16r4000 ifTrue: [^self floatDataProcessing1: w].
	self unsupported: w
!
defaultNaN
	^16r7FF8000000000000
!
quiet: bits
	^bits bitOr: 16r8000000000000
!
bitsOf: aFloat
	"An operation's result; NaNs it makes are the default NaN."
	aFloat isNaN ifTrue: [^self defaultNaN].
	^aFloat asIEEEBits
!
nanOf: a and: b
	"FPProcessNaNs: the first signaling NaN, else the first quiet one, quieted."
	| an bn |
	an := (Float fromIEEEBits: a) isNaN.
	bn := (Float fromIEEEBits: b) isNaN.
	(an and: [(a bitAnd: 16r8000000000000) = 0]) ifTrue: [^self quiet: a].
	(bn and: [(b bitAnd: 16r8000000000000) = 0]) ifTrue: [^self quiet: b].
	^an ifTrue: [a] ifFalse: [b]
!
floatDataProcessing2: w
	"fmul fdiv fadd fsub"
	| opcode a b x y result |
	opcode := (w bitShift: -12) bitAnd: 15.
	opcode > 3 ifTrue: [^self unsupported: w].
	a := fregs at: ((w bitShift: -5) bitAnd: 31) + 1.
	b := fregs at: ((w bitShift: -16) bitAnd: 31) + 1.
	x := Float fromIEEEBits: a.
	y := Float fromIEEEBits: b.
	(x isNaN or: [y isNaN])
		ifTrue: [result := self nanOf: a and: b]
		ifFalse: [
			opcode = 0 ifTrue: [result := self bitsOf: x * y].
			opcode = 1 ifTrue: [
				result := y = 0.0
					ifTrue: [
						x = 0.0
							ifTrue: [self defaultNaN]
							ifFalse: [(a >= 16r8000000000000000) = (b >= 16r8000000000000000) ifTrue: [16r7FF0000000000000] ifFalse: [16rFFF0000000000000]]]
					ifFalse: [self bitsOf: x / y]].
			opcode = 2 ifTrue: [result := self bitsOf: x + y].
			opcode = 3 ifTrue: [result := self bitsOf: x - y]].
	fregs at: (w bitAnd: 31) + 1 put: result
!
floatDataProcessing1: w
	"fmov fabs fneg fsqrt frintn frintp frintm frintz"
	| opcode a x result |
	opcode := (w bitShift: -15) bitAnd: 63.
	a := fregs at: ((w bitShift: -5) bitAnd: 31) + 1.
	opcode = 0 ifTrue: [result := a].
	opcode = 1 ifTrue: [result := a >= 16r8000000000000000 ifTrue: [a - 16r8000000000000000] ifFalse: [a]].
	opcode = 2 ifTrue: [result := a >= 16r8000000000000000 ifTrue: [a - 16r8000000000000000] ifFalse: [a + 16r8000000000000000]].
	opcode = 3 ifTrue: [
		x := Float fromIEEEBits: a.
		result := x isNaN
			ifTrue: [self quiet: a]
			ifFalse: [
				x = 0.0
					ifTrue: [a]
					ifFalse: [x < 0.0 ifTrue: [self defaultNaN] ifFalse: [x sqrt asIEEEBits]]]].
	(opcode between: 8 and: 11) ifTrue: [result := self round: a mode: opcode - 8].
	result isNil ifTrue: [^self unsupported: w].
	fregs at: (w bitAnd: 31) + 1 put: result
!
round: a mode: mode
	"frintn (ties to even), frintp, frintm, frintz; integral results keep the sign of a."
	| x t |
	x := Float fromIEEEBits: a.
	x isNaN ifTrue: [^self quiet: a].
	(x isInfinite or: [x abs >= 4503599627370496.0]) ifTrue: [^a].
	mode = 0 ifTrue: [
		t := x floor.
		((x - t) > 0.5 or: [(x - t) = 0.5 and: [t odd]]) ifTrue: [t := t + 1]].
	mode = 1 ifTrue: [t := x ceiling].
	mode = 2 ifTrue: [t := x floor].
	mode = 3 ifTrue: [t := x truncated].
	t = 0 ifTrue: [^a >= 16r8000000000000000 ifTrue: [16r8000000000000000] ifFalse: [0]].
	^t asFloat asIEEEBits
!
floatCompare: w
	"fcmp fcmpe, with a register or #0.0"
	| x y |
	(w bitAnd: 7) = 0 ifFalse: [^self unsupported: w].
	x := Float fromIEEEBits: (fregs at: ((w bitShift: -5) bitAnd: 31) + 1).
	y := (w bitAnd: 8) = 0 ifTrue: [Float fromIEEEBits: (fregs at: ((w bitShift: -16) bitAnd: 31) + 1)] ifFalse: [0.0].
	(x isNaN or: [y isNaN]) ifTrue: [^nzcv := 2r0011].
	x = y ifTrue: [^nzcv := 2r0110].
	x < y ifTrue: [^nzcv := 2r1000].
	nzcv := 2r0010
!
floatImmediate: w
	"fmov d, #imm (VFPExpandImm)"
	| imm8 b6 exponent |
	((w bitShift: -5) bitAnd: 31) = 0 ifFalse: [^self unsupported: w].
	imm8 := (w bitShift: -13) bitAnd: 255.
	b6 := (imm8 bitShift: -6) bitAnd: 1.
	exponent := ((b6 bitXor: 1) bitShift: 10) + (b6 * 2r1111111100) + ((imm8 bitShift: -4) bitAnd: 3).
	fregs at: (w bitAnd: 31) + 1 put: ((imm8 bitShift: -7) bitShift: 63) + (exponent bitShift: 52) + ((imm8 bitAnd: 15) bitShift: 48)
!
floatConvert: w
	"fmov between x and d, scvtf ucvtf (from w or x), fcvtzs fcvtzu (to w or x)"
	| sf mode opcode rn rd |
	sf := w bitShift: -31.
	mode := (w bitShift: -19) bitAnd: 3.
	opcode := (w bitShift: -16) bitAnd: 7.
	rn := (w bitShift: -5) bitAnd: 31.
	rd := w bitAnd: 31.
	mode = 0 ifTrue: [
		(sf = 1 and: [opcode = 6]) ifTrue: [^self r: rd put: (fregs at: rn + 1)].
		(sf = 1 and: [opcode = 7]) ifTrue: [^fregs at: rd + 1 put: (self r: rn)].
		opcode = 2 ifTrue: [^fregs at: rd + 1 put: (self signed: (self r: rn sf: sf) sf: sf) asFloat asIEEEBits].
		opcode = 3 ifTrue: [^fregs at: rd + 1 put: (self r: rn sf: sf) asFloat asIEEEBits]].
	mode = 3 ifTrue: [
		opcode = 0 ifTrue: [
			^self r: rd put: (self wrap: (self truncate: (fregs at: rn + 1) min: (1 bitShift: (sf = 1 ifTrue: [63] ifFalse: [31])) negated max: (self mask: sf) // 2) sf: sf)].
		opcode = 1 ifTrue: [^self r: rd put: (self truncate: (fregs at: rn + 1) min: 0 max: (self mask: sf))]].
	self unsupported: w
!
truncate: bits min: min max: max
	"Round toward zero, saturating; NaN is 0."
	| x |
	x := Float fromIEEEBits: bits.
	x isNaN ifTrue: [^0].
	x >= 1.0e20 ifTrue: [^max].
	x <= -1.0e20 ifTrue: [^min].
	^(x truncated max: min) min: max
! !
