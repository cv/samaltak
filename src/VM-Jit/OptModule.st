JitCompiler subclass: #OptModule
	instanceVariableNames: 'memory interpreter gc libc feedback'
	classVariableNames: 'BF_DEOPT BF_LOOP BF_SEALED LOC_CONST LOC_DREG LOC_INT LOC_REG LOC_SLOT LOC_SMI LOC_SUNK NF_ALLOC NF_DEAD NF_GUARD NF_PURE O_BRANCH O_CALL O_CAST O_CHECKINT O_CLASSIS O_CLASSOF O_CLOSURE O_CONST O_OUTERLOAD O_OUTERSTORE O_UNBOXF O_BOXF O_FARITH O_FCMP O_BOTHINT O_FSQRT O_DEOPT O_EQ O_GOTO O_GUARDCLASS O_GUARDINT E_BYTE E_CHAR E_PTR O_IADD O_IAND O_ICMP O_INDEXLOAD O_INDEXSTORE O_SIZE O_IMUL O_IOR O_ISUB O_LOADFIELD O_NE O_NOP O_PARAM O_PHI O_RETURN O_SEND O_STOREFIELD O_LAST OPT_ANA_MAX OPT_DEF_SIZE OPT_MAX_ACTS OPT_MAX_BLOCKS OPT_MAX_EDGES OPT_MAX_NODES OPT_MAX_OPERANDS OPT_MAX_STATES OPT_PCB_MAX R_DBL R_INT R_NONE R_OOP SP_CALL SP_ENTRY SP_GUARD SP_LOOP T_ANY T_BOOL T_CHAR T_FLOAT T_NIL T_OBJ T_SMI'
	package: 'VM-Jit'!

OptModule comment: 'I am the abstract class of the optimizing tier''s modules (docs/jit.md, Optimizing tier): I connect them to the VM and to each other, and hold their shared constants (the IR''s opcodes, representations, types, flags; the deoptimization metadata''s location kinds) and the object model''s helpers they need (as VMCoreModule does for the VM''s core).

The IR (OptIR): a control flow graph of blocks of SSA nodes. A node has an opcode (O_*), the representation of its result (R_OOP a tagged object pointer, R_INT an untagged 64-bit integer, R_DBL a raw double, R_NONE none), a static type (T_* and, for T_OBJ, an exact class), operands (a, b, c; variadic ones in the operand array), a frame state if it may deoptimize or is a safepoint, and its register allocation. Frame states (OptState) describe, for deoptimization, every inlined activation (OptAct) from the outermost: its method, pc, receiver, closure and slots.'!

!OptModule class methodsFor: 'declaring'!
declarations
	^#((memory ObjectMemory) (interpreter Interpreter) (gc GarbageCollector) (libc LibC) (feedback JitFeedback))
!
isAbstractModule
	^self == OptModule
!
initialize
	OPT_MAX_NODES := 16384.
	OPT_MAX_BLOCKS := 2048.
	OPT_MAX_EDGES := 8192.
	OPT_MAX_OPERANDS := 131072.
	OPT_MAX_STATES := 4096.
	OPT_MAX_ACTS := 512.
	OPT_DEF_SIZE := 131072.
	OPT_ANA_MAX := 65536.
	OPT_PCB_MAX := 131072.
	"opcodes"
	O_NOP := 0.
	O_CONST := 1.
	O_PARAM := 2.
	O_PHI := 3.
	O_LOADFIELD := 4.
	O_STOREFIELD := 5.
	O_CLASSOF := 6.
	O_EQ := 7.
	O_NE := 8.
	O_IADD := 9.
	O_ISUB := 10.
	O_IMUL := 11.
	O_ICMP := 12.
	O_IAND := 13.
	O_IOR := 14.
	O_GUARDCLASS := 15.
	O_GUARDINT := 16.
	O_SEND := 17.
	O_CALL := 18.
	O_CHECKINT := 19.
	O_CLASSIS := 20.
	O_CAST := 21.
	O_INDEXLOAD := 22.
	O_INDEXSTORE := 23.
	O_SIZE := 24.
	O_CLOSURE := 25.
	O_OUTERLOAD := 26.
	O_OUTERSTORE := 27.
	O_UNBOXF := 28.
	O_BOXF := 29.
	O_FARITH := 30.
	O_FCMP := 31.
	O_BOTHINT := 32.
	O_FSQRT := 33.
	O_GOTO := 40.
	O_BRANCH := 41.
	O_RETURN := 42.
	O_DEOPT := 43.
	O_LAST := 43.
	"indexed element kinds"
	E_PTR := 0.
	E_BYTE := 1.
	E_CHAR := 2.
	"representations"
	R_NONE := 0.
	R_OOP := 1.
	R_INT := 2.
	R_DBL := 3.
	"types"
	T_ANY := 0.
	T_SMI := 1.
	T_FLOAT := 2.
	T_BOOL := 3.
	T_NIL := 4.
	T_OBJ := 5.
	T_CHAR := 6.
	"node flags"
	NF_PURE := 1.
	NF_DEAD := 2.
	NF_GUARD := 4.
	NF_ALLOC := 8.
	"block flags"
	BF_SEALED := 1.
	BF_LOOP := 2.
	BF_DEOPT := 4.
	"safepoint kinds"
	SP_GUARD := 1.
	SP_CALL := 2.
	SP_LOOP := 3.
	SP_ENTRY := 4.
	"deoptimization metadata: where a value is (low 3 bits)"
	LOC_SLOT := 0.
	LOC_REG := 1.
	LOC_CONST := 2.
	LOC_SMI := 3.
	LOC_INT := 4.
	LOC_DREG := 5.
	LOC_SUNK := 6
! !

!OptModule methodsFor: 'object model'!
storeRef: o at: i put: v
	"The generational write barrier, as VMCoreModule's."
	self uint64At: o + 16 + (8 * i) put: v.
	((self isPtr: v) and: [(self isYoung: v) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]])
		ifTrue: [gc remember: o]
!
isInt: o
	^(o bitAnd: 1) ~= 0
!
intVal: o
	^o asInt64 >> 1
!
intOop: v
	^((v asInt64 << 1) bitOr: 1) asUInt64
!
isPtr: o
	^(o bitAnd: 7) = 0
!
header: o
	^self uint64At: o
!
numSlots: o
	^(self header: o) asUInt32
!
formatOf: o
	^(((self header: o) >> H_FMT_SHIFT) bitAnd: H_FMT_MASK) asInt32
!
hashOf: o
	^(((self header: o) >> H_HASH_SHIFT) bitAnd: H_HASH_MASK) asUInt32
!
rawClass: o
	^self uint64At: o + 8
!
slotsOf: o
	^self cCoerce: o + 16 to: 'oop *'
!
bytesOf: o
	^self cCoerce: o + 16 to: 'uint8_t *'
!
loadRef: o at: i
	^self uint64At: o + 16 + (8 * i)
!
isYoung: o
	^(o - gc youngLo) asUInt64 < (gc youngHi - gc youngLo)
!
classOf: o
	"The class of any oop."
	(o bitAnd: 1) ~= 0 ifTrue: [^memory clsSmallint].
	(o bitAnd: 7) = 0 ifTrue: [^self rawClass: o].
	(o bitAnd: 7) = 2 ifTrue: [^memory clsChar].
	(o bitAnd: 7) = 4 ifTrue: [^memory clsSmallfloat].
	^memory nilOop
!
methodBytecodes: m
	^self bytesOf: (self loadRef: m at: CM_BYTECODES)
!
methodSize: m
	^(memory byteSize: (self loadRef: m at: CM_BYTECODES)) asInt32
!
methodLiteral: m at: i
	^self loadRef: (self loadRef: m at: CM_LITERALS) at: i
!
methodPrimitive: m
	| p |
	p := self loadRef: m at: CM_PRIMITIVE.
	^(self isInt: p) ifTrue: [((self intVal: p) bitAnd: CM_PRIM_MASK) asInt32] ifFalse: [0]
! !
