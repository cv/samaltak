Object subclass: #Disassembler
	instanceVariableNames: 'method bytes stream instructions'
	classVariableNames: ''
	package: 'Compiler'!

Disassembler comment: 'I print the bytecodes of a CompiledMethod, one instruction per line: pc, bytes, mnemonic. Block bodies follow their closure instruction inline. InstructionStream decodes; I print each instruction message it sends me.'!

!Disassembler class methodsFor: 'printing'!
disassemble: aCompiledMethod
	^self new disassemble: aCompiledMethod
! !

!Disassembler methodsFor: 'printing'!
disassemble: aCompiledMethod
	method := aCompiledMethod.
	bytes := method bytecodes.
	instructions := InstructionStream on: method pc: 0.
	stream := WriteStream on: (String new: 200).
	[instructions atEnd] whileFalse: [self printInstruction].
	^stream contents
!
printInstruction
	"Print the instruction at the stream's pc on one line and move past it."
	| pc next mnemonic |
	pc := instructions pc.
	next := instructions followingPc min: bytes size.
	mnemonic := [instructions interpretNextInstructionFor: self] on: Error do: [:e | e return: 'unknown'].
	instructions pc: next.
	self print: pc padded: 4.
	stream nextPutAll: ' <'.
	pc to: next - 1 do: [:i |
		i > pc ifTrue: [stream space].
		self printHex: (bytes at: i + 1)].
	stream nextPutAll: '> '.
	stream nextPutAll: mnemonic.
	stream nextPut: (Character value: 10)
! !

!Disassembler methodsFor: 'instructions'!
pushTemporaryVariable: index
	^'pushTemp: ' , index printString
!
pushReceiverVariable: index
	^'pushInstVar: ' , index printString
!
pushConstant: anObject
	^'pushConstant: ' , anObject printString
!
pushLiteralVariable: anAssociation
	^'pushLitVar: ' , (self variableString: anAssociation)
!
pushReceiver
	^'pushSelf'
!
pushActiveContext
	^'pushThisContext'
!
pushNewArrayOfSize: n
	^'makeArray: ' , n printString
!
pushOuterTemp: index depth: depth
	^'pushOuterTemp: ' , index printString , ' depth: ' , depth printString
!
pushClosureNumArgs: numArgs numTemps: numTemps frameSize: frameSize blockSize: size
	^'pushClosure numArgs: ' , numArgs printString
		, ' numTemps: ' , numTemps printString
		, ' frameSize: ' , frameSize printString
		, ' to: ' , (instructions pc + size) printString
!
storeIntoTemporaryVariable: index
	^'storeIntoTemp: ' , index printString
!
storeIntoReceiverVariable: index
	^'storeIntoInstVar: ' , index printString
!
storeIntoLiteralVariable: anAssociation
	^'storeIntoLitVar: ' , (self variableString: anAssociation)
!
storeIntoOuterTemp: index depth: depth
	^'storeIntoOuterTemp: ' , index printString , ' depth: ' , depth printString
!
popIntoTemporaryVariable: index
	^'popIntoTemp: ' , index printString
!
popIntoLiteralVariable: anAssociation
	^'popIntoLitVar: ' , (self variableString: anAssociation)
!
popIntoOuterTemp: index depth: depth
	^'popIntoOuterTemp: ' , index printString , ' depth: ' , depth printString
!
doDup
	^'dup'
!
doPop
	^'pop'
!
methodReturnTop
	^'returnTop'
!
methodReturnReceiver
	^'returnSelf'
!
blockReturnTop
	^'blockReturnTop'
!
nonLocalReturnTop
	^'nonLocalReturnTop'
!
send: selector super: isSuper numArgs: n
	^(isSuper ifTrue: ['superSend: '] ifFalse: ['send: ']) , selector printString , ' numArgs: ' , n printString
!
sendSpecial: index numArgs: n
	^'send: ' , (CompiledMethod specialSelectorAt: index) printString
!
jump: offset
	^'jumpTo: ' , (instructions pc + offset) printString
!
jump: offset if: aBoolean
	^(aBoolean ifTrue: ['jumpTrueTo: '] ifFalse: ['jumpFalseTo: ']) , (instructions pc + offset) printString
! !

!Disassembler methodsFor: 'private'!
variableString: anAssociation
	^(anAssociation respondsTo: #key)
		ifTrue: [anAssociation key printString]
		ifFalse: [anAssociation printString]
!
print: anInteger padded: width
	| s |
	s := anInteger printString.
	s size + 1 to: width do: [:i | stream space].
	stream nextPutAll: s
!
printHex: aByte
	| digits |
	digits := '0123456789ABCDEF'.
	stream nextPut: (digits at: aByte // 16 + 1); nextPut: (digits at: aByte \\ 16 + 1)
! !
