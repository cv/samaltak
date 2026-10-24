Object subclass: #InstructionStream
	instanceVariableNames: 'method pc'
	classVariableNames: ''
	package: 'System-Debugging'!

InstructionStream comment: 'I decode the bytecodes of a CompiledMethod (see docs/implementation.md, Bytecodes), starting at a 0-based pc. interpretNextInstructionFor: decodes one instruction, advances my pc past it and sends the client one message describing it (pushTemporaryVariable:, send:super:numArgs:, jump:if:, ...). A block push (pushClosureNumArgs:numTemps:frameSize:blockSize:) leaves my pc at the start of the block body; the client skips it. My clients are the Simulator (executes the messages) and the Disassembler (prints them). I also answer what the next instruction will do (willSend, willReturn, willStore, ...), which the debugger uses to decide where to stop.'!

!InstructionStream methodsFor: 'accessing'!
method
	^method
!
pc
	^pc
!
pc: anInteger
	pc := anInteger
!
atEnd
	^pc >= method bytecodes size
!
nextOpcode
	"Answer the opcode at my pc without moving."
	^method bytecodes at: pc + 1
! !

!InstructionStream methodsFor: 'private'!
setMethod: aCompiledMethod pc: anInteger
	method := aCompiledMethod.
	pc := anInteger
!
nextByte
	pc := pc + 1.
	^method bytecodes at: pc
!
nextInt16
	| value |
	value := self nextByte.
	value := value + (self nextByte * 256).
	^value >= 32768 ifTrue: [value - 65536] ifFalse: [value]
!
literalAt: index
	"index is 0-based."
	^method literals at: index + 1
! !

!InstructionStream methodsFor: 'decoding'!
interpretNextInstructionFor: client
	"Decode the instruction at pc, move past it and send client the message that describes it. Answer the client's answer."
	| message |
	message := self nextInstruction.
	^client perform: message selector withArguments: message arguments
!
nextInstruction
	"Decode the instruction at pc, move past it and answer a Message describing it."
	| op |
	op := self nextByte.
	op < 16r10 ifTrue: [^Message selector: #pushTemporaryVariable: argument: op].
	op < 16r20 ifTrue: [^Message selector: #pushReceiverVariable: argument: op - 16r10].
	op < 16r40 ifTrue: [^Message selector: #pushConstant: argument: (self literalAt: op - 16r20)].
	op < 16r60 ifTrue: [^Message selector: #pushLiteralVariable: argument: (self literalAt: op - 16r40)].
	op < 16r68 ifTrue: [^Message selector: #popIntoTemporaryVariable: argument: op - 16r60].
	op = 16r70 ifTrue: [^Message selector: #pushReceiver].
	op = 16r71 ifTrue: [^Message selector: #pushConstant: argument: true].
	op = 16r72 ifTrue: [^Message selector: #pushConstant: argument: false].
	op = 16r73 ifTrue: [^Message selector: #pushConstant: argument: nil].
	op = 16r74 ifTrue: [^Message selector: #pushConstant: argument: 0].
	op = 16r75 ifTrue: [^Message selector: #pushConstant: argument: 1].
	op = 16r76 ifTrue: [^Message selector: #pushActiveContext].
	op = 16r77 ifTrue: [^Message selector: #doDup].
	op = 16r78 ifTrue: [^Message selector: #doPop].
	op = 16r79 ifTrue: [^Message selector: #methodReturnTop].
	op = 16r7A ifTrue: [^Message selector: #methodReturnReceiver].
	op = 16r7B ifTrue: [^Message selector: #blockReturnTop].
	op = 16r7C ifTrue: [^Message selector: #nonLocalReturnTop].
	op = 16r80 ifTrue: [^Message selector: #pushTemporaryVariable: argument: self nextByte].
	op = 16r81 ifTrue: [^Message selector: #pushReceiverVariable: argument: self nextByte].
	op = 16r82 ifTrue: [^Message selector: #pushConstant: argument: (self literalAt: self nextByte)].
	op = 16r83 ifTrue: [^Message selector: #pushLiteralVariable: argument: (self literalAt: self nextByte)].
	op = 16r84 ifTrue: [^Message selector: #storeIntoTemporaryVariable: argument: self nextByte].
	op = 16r85 ifTrue: [^Message selector: #storeIntoReceiverVariable: argument: self nextByte].
	op = 16r86 ifTrue: [^Message selector: #storeIntoLiteralVariable: argument: (self literalAt: self nextByte)].
	op = 16r87 ifTrue: [^Message selector: #popIntoTemporaryVariable: argument: self nextByte].
	op = 16r89 ifTrue: [^Message selector: #popIntoLiteralVariable: argument: (self literalAt: self nextByte)].
	(op between: 16r8A and: 16r8C) ifTrue: [| depth index |
		depth := self nextByte.
		index := self nextByte.
		^Message
			selector: (#(#pushOuterTemp:depth: #storeIntoOuterTemp:depth: #popIntoOuterTemp:depth:) at: op - 16r89)
			arguments: (Array with: index with: depth)].
	(op = 16r8D or: [op = 16r8E]) ifTrue: [| lit n |
		lit := self literalAt: self nextByte.
		n := self nextByte.
		^Message selector: #send:super:numArgs: arguments: (Array with: lit with: op = 16r8E with: n)].
	op = 16r8F ifTrue: [| a t f size |
		a := self nextByte.
		t := self nextByte.
		f := self nextByte.
		size := self nextByte * 256.
		size := size + self nextByte.
		^Message selector: #pushClosureNumArgs:numTemps:frameSize:blockSize: arguments: (Array with: a with: t with: f with: size)].
	op = 16r90 ifTrue: [^Message selector: #jump: argument: self nextInt16].
	op = 16r91 ifTrue: [^Message selector: #jump:if: arguments: (Array with: self nextInt16 with: true)].
	op = 16r92 ifTrue: [^Message selector: #jump:if: arguments: (Array with: self nextInt16 with: false)].
	op = 16r93 ifTrue: [^Message selector: #pushConstant: argument: self nextInt16].
	op = 16r94 ifTrue: [^Message selector: #pushNewArrayOfSize: argument: self nextByte].
	((op between: 16r97 and: 16r9F) or: [op between: 16rF0 and: 16rFB]) ifTrue: [| a b kind special second |
		"superinstruction: push temp a, push temp | literal | int8 b, send the special selector (doAll: performs them in order)"
		a := self nextByte.
		b := self nextByte.
		op <= 16r99
			ifTrue: [kind := op - 16r97. special := self nextByte - 16rA0 + 1]
			ifFalse: [
				op <= 16r9F
					ifTrue: [kind := 0. special := op - 16r9A + 1]
					ifFalse: [kind := op - 16rF0 // 6 + 1. special := op - 16rF0 \\ 6 + 1]].
		second := kind = 0
			ifTrue: [Message selector: #pushTemporaryVariable: argument: b]
			ifFalse: [
				Message selector: #pushConstant: argument: (kind = 1
					ifTrue: [self literalAt: b]
					ifFalse: [b > 127 ifTrue: [b - 256] ifFalse: [b]])].
		^Message selector: #doAll: argument: (Array
			with: (Message selector: #pushTemporaryVariable: argument: a)
			with: second
			with: (Message selector: #sendSpecial:numArgs: arguments: (Array with: special with: 1)))].
	(op between: 16rA0 and: 16rBF) ifTrue: [| index |
		index := op - 16rA0 + 1.
		^Message selector: #sendSpecial:numArgs: arguments: (Array with: index with: (CompiledMethod specialSelectorAt: index) numArgs)].
	(op between: 16rC0 and: 16rEF) ifTrue: [
		^Message selector: #send:super:numArgs: arguments: (Array with: (self literalAt: (op bitAnd: 16r0F)) with: false with: op - 16rC0 // 16)].
	^self error: 'Unknown bytecode ', op printString, ' at pc ', (pc - 1) printString
!
peekInstruction
	"Answer the Message describing the instruction at pc, without moving."
	| saved message |
	saved := pc.
	message := self nextInstruction.
	pc := saved.
	^message
!
followingPc
	"Answer the pc after the instruction at pc (a block push counts without its body)."
	^pc + (CompiledMethod instructionLengthAt: self nextOpcode)
! !

!InstructionStream methodsFor: 'testing'!
willSend
	"Answer whether the next instruction is a message send (including the special selectors == ~~ class, which the VM never sends)."
	| op |
	op := self nextOpcode.
	^op = 16r8D or: [op = 16r8E or: [(op between: 16rA0 and: 16rEF) or: [(op between: 16r97 and: 16r9F) or: [op between: 16rF0 and: 16rFB]]]]
!
willReallySend
	"Like willSend, but not for == ~~ class."
	| op |
	op := self nextOpcode.
	^self willSend and: [(#(16rB3 16rB4 16rBD) includes: op) not]
!
willReturn
	^self nextOpcode between: 16r79 and: 16r7C
!
willStore
	| op |
	op := self nextOpcode.
	^(op between: 16r60 and: 16r67)
		or: [(op between: 16r84 and: 16r87)
		or: [op = 16r89 or: [op = 16r8B or: [op = 16r8C]]]]
!
willStoreIntoReceiver
	^self nextOpcode = 16r85
!
willCreateBlock
	^self nextOpcode = 16r8F
!
willJump
	^self nextOpcode between: 16r90 and: 16r92
!
willSendOrReturnOrStore
	"The places the debugger stops at: sends, returns, stores and block creation (the instructions the compiler maps to source)."
	^self willSend or: [self willReturn or: [self willStore or: [self willCreateBlock]]]
! !

!InstructionStream class methodsFor: 'instance creation'!
on: aCompiledMethod
	^self on: aCompiledMethod pc: aCompiledMethod initialPC
!
on: aCompiledMethod pc: anInteger
	^self basicNew setMethod: aCompiledMethod pc: anInteger
! !
