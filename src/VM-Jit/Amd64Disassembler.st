Object subclass: #Amd64Disassembler
	instanceVariableNames: 'bytes start position limit address length opcode prefix66 used66 repeat usedRepeat rex rexUsed mod reg rm hasSib scale index base displacement riprel ripDisplacement ripSize target move indirect'
	classVariableNames: ''
	package: 'VM-Jit'!

Amd64Disassembler comment: 'I print x86-64 instructions as GNU objdump -d -M intel does (its mnemonics, Intel operand order, hex immediates, absolute branch targets, [rip+disp] with the address it refers to after #, the REX prefix an instruction does not use as rex.W ...), for what Amd64Assembler emits and the rest of the general purpose and scalar double instructions around it: add or adc sbb and sub xor cmp test, mov movabs lea movzx movsx movsxd xchg, inc dec not neg mul imul div idiv, shifts and rotates, bt bts btr btc, bswap, cmovcc setcc, push pop, jmp jcc call ret, cbw..cqo, nop int3 ud2; movsd movapd movupd movq movd addsd subsd mulsd divsd sqrtsd minsd maxsd ucomisd comisd cvtsi2sd cvttsd2si cvtsd2si andpd andnpd orpd xorpd. Anything else (other prefixes among them) prints as .byte 0x.. and takes one byte.
listingOfBytes:at:annotations: prints JIT output with its Arm64CodeAnnotations (bytecodes, comments, labels, symbols), the data words after its instructions (literals, an oop pool, inline caches'' words) as .quad.

	Amd64Disassembler new textFor: #[16r48 16r8B 16r7B 16r08] at: 0	"mov    rdi,QWORD PTR [rbx+0x8]"'!

!Amd64Disassembler class methodsFor: 'decoding'!
oneByteOpcodes
	"The selector that decodes each opcode, 16 a line (nil: none; 40-4F are REX, 66 F2 F3 prefixes, 0F escapes to twoByteOpcodes)."
	^#(
		alu alu alu alu alu alu nil nil alu alu alu alu alu alu nil nil
		alu alu alu alu alu alu nil nil alu alu alu alu alu alu nil nil
		alu alu alu alu alu alu nil nil alu alu alu alu alu alu nil nil
		alu alu alu alu alu alu nil nil alu alu alu alu alu alu nil nil
		nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
		pushRegister pushRegister pushRegister pushRegister pushRegister pushRegister pushRegister pushRegister popRegister popRegister popRegister popRegister popRegister popRegister popRegister popRegister
		nil nil nil movsxd nil nil nil nil pushImmediate imulImmediate pushImmediate imulImmediate nil nil nil nil
		jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort jumpShort
		group1 group1 nil group1 test test xchg xchg mov mov mov mov nil lea nil popMemory
		xchgAccumulator xchgAccumulator xchgAccumulator xchgAccumulator xchgAccumulator xchgAccumulator xchgAccumulator xchgAccumulator convert convert nil nil nil nil nil nil
		nil nil nil nil nil nil nil nil testAccumulator testAccumulator nil nil nil nil nil nil
		movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate movImmediate
		group2 group2 ret ret nil nil movMemoryImmediate movMemoryImmediate nil nil nil nil int3 nil nil nil
		group2 group2 group2 group2 nil nil nil nil nil nil nil nil nil nil nil nil
		nil nil nil nil nil nil nil nil call jump nil jump nil nil nil nil
		nil nil nil nil nil nil group3 group3 nil nil nil nil nil nil group4 group5)
!
twoByteOpcodes
	"The selector that decodes each opcode after 0F, 16 a line (nil: none)."
	^#(
		nil nil nil nil nil nil nil nil nil nil nil ud2 nil nil nil nil
		sseMove sseMove nil nil nil nil nil nil nil nil nil nil nil nil nil nop
		nil nil nil nil nil nil nil nil movapd movapd cvtsi2sd nil cvtsd2si cvtsd2si sseCompare sseCompare
		nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
		cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov cmov
		nil scalarDouble nil nil logicalDouble logicalDouble logicalDouble logicalDouble scalarDouble scalarDouble nil nil scalarDouble scalarDouble scalarDouble scalarDouble
		nil nil nil nil nil nil nil nil nil nil nil nil nil nil movdToXmm nil
		nil nil nil nil nil nil nil nil nil nil nil nil nil nil movdFromXmm nil
		jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear jumpNear
		setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc setcc
		nil nil nil bitTest nil nil nil nil nil nil nil bitTest nil nil nil imul
		nil nil nil bitTest nil nil movExtend movExtend nil nil bitTestImmediate bitTest nil nil movExtend movExtend
		nil nil nil nil nil nil nil nil bswap bswap bswap bswap bswap bswap bswap bswap
		nil nil nil nil nil nil movqToMemory nil nil nil nil nil nil nil nil nil
		nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
		nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil)
! !

!Amd64Disassembler methodsFor: 'disassembling'!
textFor: aByteArray at: anAddress
	"objdump's text of the instruction at the start of aByteArray, at anAddress (length: its size)"
	^self textFor: aByteArray from: 1 to: aByteArray size at: anAddress
!
textFor: aByteArray from: first to: last at: anAddress
	"objdump's text of the instruction at index first of aByteArray, at anAddress, read from bytes up to index last; .byte 0x.. (one byte) if I do not decode it"
	| text |
	bytes := aByteArray.
	start := first.
	limit := last.
	address := anAddress.
	text := [self decode] on: Error do: [:e | e return: nil].
	text isNil ifTrue: [
		length := 1.
		target := move := indirect := nil.
		ripSize := 0.
		^'.byte 0x' , (self bytesOf: bytes from: first - 1 size: 1)].
	^text
!
length
	"The size in bytes of the instruction decoded last."
	^length
!
target
	"The address the instruction decoded last branches to (jmp, jcc, call) or refers to ([rip+disp]), else nil."
	^target
!
targetSize
	"The size in bits of the memory at target that the instruction decoded last reads or writes (0: lea, a branch)."
	^ripSize
!
move
	"{register. value} if the instruction decoded last is a mov of a constant into a 32- or 64-bit register (value #rip: the 64-bit word at target), else nil."
	^move
!
indirect
	"The register the instruction decoded last calls or jumps through (call rax: 0), else nil."
	^indirect
!
instructionsOf: aByteArray at: anAddress
	"{offset. size. text} of each instruction of aByteArray, decoded one after the other from anAddress on."
	^(self scan: aByteArray at: anAddress data: #()) collect: [:each | each first: 3]
!
listingOfBytes: aByteArray at: anAddress
	"Lines '0x1000: 488b7b08              mov    rdi,QWORD PTR [rbx+0x8]' of the instructions of aByteArray from anAddress on."
	^String new: aByteArray size * 30 streamContents: [:s |
		(self instructionsOf: aByteArray at: anAddress) do: [:each |
			s nextPutAll: (self hex: anAddress + each first); nextPutAll: ': ';
				nextPutAll: ((self bytesOf: aByteArray from: each first size: (each at: 2)) padRightTo: 20); nextPutAll: '  ';
				nextPutAll: (each at: 3); lf]]
!
listing: aSimulatedMemory from: startAddress to: endAddress
	"The listing of the bytes from address startAddress up to (not including) endAddress."
	^self listingOfBytes: (self bytes: aSimulatedMemory from: startAddress to: endAddress) at: startAddress
!
listing: aSimulatedMemory from: startAddress to: endAddress annotations: anArm64CodeAnnotations
	^self listingOfBytes: (self bytes: aSimulatedMemory from: startAddress to: endAddress) at: startAddress annotations: anArm64CodeAnnotations
!
bytes: aSimulatedMemory from: startAddress to: endAddress
	| result |
	result := ByteArray new: endAddress - startAddress.
	1 to: result size do: [:i | result at: i put: (aSimulatedMemory uint8At: startAddress + i - 1)].
	^result
! !

!Amd64Disassembler methodsFor: 'annotated listing'!
listingOfBytes: aByteArray at: anAddress annotations: anArm64CodeAnnotations
	"The code of aByteArray at anAddress with the annotations (or nil): a header line 'pc 3: send: #+  -- source' before
	the code of each bytecode, lines '  +0004  0f85af010000          jne    L1' with the comments at their offset in a column
	on the right, labels Ln: at the targets inside the code, named targets (call 0x... <name>, call rax <name> after a
	mov of the address into rax), and the data words after the instructions as .quad (literals, an oop pool, inline
	caches' words: dataOffsetsIn:at:size:)."
	| notes size pieces labels known |
	notes := anArm64CodeAnnotations ifNil: [Arm64CodeAnnotations new].
	size := aByteArray size.
	pieces := self piecesOf: aByteArray at: anAddress.
	labels := self labelsOf: pieces at: anAddress size: size.
	known := Dictionary new.
	^String new: pieces size * 70 streamContents: [:s |
		pieces do: [:piece | | offset comments |
			offset := piece first.
			comments := OrderedCollection new.
			offset to: offset + (piece at: 2) - 1 do: [:o |
				known := self header: o notes: notes labels: labels known: known on: s.
				comments addAll: (notes commentsAt: o)].
			self
				annotate: '  +' , ((offset printString: 16) asLowercase padLeftTo: 4 with: $0) , '  ' ,
					((self bytesOf: aByteArray from: offset size: (piece at: 2)) padRightTo: 20) , '  ' ,
					(self annotated: piece bytes: aByteArray at: anAddress labels: labels symbols: notes known: known)
				with: comments
				on: s].
		self header: size notes: notes labels: labels known: known on: s.
		self annotate: nil with: (notes commentsAt: size) on: s]
!
header: offset notes: notes labels: labels known: known on: aStream
	"The bytecode headers and the label at offset; answer the registers known to hold constants from there on."
	(notes bytecodesAt: offset) do: [:each |
		aStream position > 0 ifTrue: [aStream lf].
		aStream nextPutAll: 'pc '; print: (each at: 1); nextPutAll: ': '; nextPutAll: (each at: 2).
		(each at: 3) ifNotNil: [:source | aStream nextPutAll: '  -- '; nextPutAll: source].
		aStream lf].
	(labels at: offset ifAbsent: [nil]) ifNotNil: [:label |
		aStream nextPutAll: label; nextPut: $:; lf.
		^Dictionary new].
	^known
!
scan: aByteArray at: anAddress data: dataOffsets
	"{offset. size. text. target. target size. move. indirect} of each piece of aByteArray: the instructions, decoded
	one after the other (none across a data word), and the 8-byte words at dataOffsets ('.quad 0x...')."
	| pieces offset size starts next |
	pieces := OrderedCollection new.
	size := aByteArray size.
	starts := dataOffsets asSortedCollection asArray.
	next := 1.
	offset := 0.
	[offset < size] whileTrue: [
		[next <= starts size and: [(starts at: next) < offset]] whileTrue: [next := next + 1].
		(next <= starts size and: [(starts at: next) = offset])
			ifTrue: [
				pieces add: {offset. 8. '.quad ' , (self hex: (self wordOf: aByteArray at: offset)). nil. 0. nil. nil}.
				offset := offset + 8]
			ifFalse: [| text |
				text := self textFor: aByteArray from: offset + 1 to: (next <= starts size ifTrue: [starts at: next] ifFalse: [size]) at: anAddress + offset.
				pieces add: {offset. length. text. target. ripSize. move. indirect}.
				offset := offset + length]].
	^pieces
!
piecesOf: aByteArray at: anAddress
	"scan:at:data: of aByteArray with its data words (dataOffsetsIn:at:size:) as data: decoded again, those words skipped,
	until the data words stay the same."
	| offsets pieces found |
	offsets := #().
	4 timesRepeat: [
		pieces := self scan: aByteArray at: anAddress data: offsets.
		found := self dataOffsetsIn: pieces at: anAddress size: aByteArray size.
		found = offsets ifTrue: [^pieces].
		offsets := found].
	^self scan: aByteArray at: anAddress data: offsets
!
dataOffsetsIn: pieces at: anAddress size: size
	"The offsets of the data words in code laid out as the JIT lays out a method's: instructions, int3 up to a multiple
	of 8, then 8-byte words to the end (literals, an oop pool, inline caches' words) that only instructions before them
	refer to, pc-relative (QWORD PTR [rip+...]). They begin where the instructions end: after the first jmp or ret (and
	the int3 after it) that no branch before it passes, a multiple of 8 bytes before the first word an instruction
	before it refers to, or with int3 between if none does; with no such end, they are the words from the first an
	instruction refers to to the last."
	| first last limit branches start |
	pieces do: [:piece | | offset |
		((piece at: 4) notNil and: [(piece at: 5) = 64]) ifTrue: [
			offset := (piece at: 4) - anAddress.
			(offset > piece first and: [offset + 8 <= size]) ifTrue: [
				first := first isNil ifTrue: [offset] ifFalse: [first min: offset].
				last := last isNil ifTrue: [offset] ifFalse: [last max: offset]]]].
	limit := first ifNil: [size].
	branches := Set new.
	pieces doWithIndex: [:piece :i |
		(start isNil and: [piece first < limit]) ifTrue: [
			((piece at: 4) notNil and: [(piece at: 5) = 0 and: [((piece at: 3) beginsWith: 'lea') not]])
				ifTrue: [branches add: (piece at: 4) - anAddress].
			(((piece at: 3) beginsWith: 'jmp') or: [(piece at: 3) beginsWith: 'ret']) ifTrue: [| j end |
				end := piece first + (piece at: 2).
				j := i + 1.
				[j <= pieces size and: [((pieces at: j) at: 3) = 'int3']] whileTrue: [
					end := end + 1.
					j := j + 1].
				((first notNil or: [j > (i + 1)]) and: [end <= limit and: [(limit - end) \\ 8 = 0 and: [
					(branches anySatisfy: [:t | t >= end and: [t < size]]) not]]]) ifTrue: [start := end]]]].
	start notNil ifTrue: [^(start to: size - 8 by: 8) asArray].
	first isNil ifTrue: [^#()].
	^(first to: last by: 8) asArray
!
labelsOf: pieces at: anAddress size: size
	"offset -> 'Ln' for the targets inside the code (its end included), numbered in address order"
	| offsets labels |
	offsets := Set new.
	pieces do: [:piece |
		(piece at: 4) ifNotNil: [:t | | offset |
			offset := t - anAddress.
			(offset >= 0 and: [offset <= size]) ifTrue: [offsets add: offset]]].
	labels := Dictionary new.
	offsets asSortedCollection doWithIndex: [:offset :i | labels at: offset put: 'L' , i printString].
	^labels
!
annotated: piece bytes: aByteArray at: anAddress labels: labels symbols: notes known: known
	"The text of piece with a target inside the code as its label and a named target as 'text <name>'; known maps
	registers to the constants the instructions before loaded into them (movabs, mov of a literal)."
	| text name t |
	text := piece at: 3.
	(t := piece at: 4) notNil ifTrue: [
		(labels at: t - anAddress ifAbsent: [nil]) ifNotNil: [:label |
			text := (text copyFrom: 1 to: text size - (self hex: t) size) , label].
		name := notes symbolAt: t].
	(piece at: 7) ifNotNil: [:r | (known at: r ifAbsent: [nil]) ifNotNil: [:value | name := notes symbolAt: value]].
	((text beginsWith: '.quad ') and: [(piece at: 2) = 8]) ifTrue: [name := notes symbolAt: (self wordOf: aByteArray at: piece first)].
	self track: piece known: known bytes: aByteArray at: anAddress.
	^name ifNil: [text] ifNotNil: [text , ' <' , name , '>']
!
track: piece known: known bytes: aByteArray at: anAddress
	"Update known after piece: the register a mov of a constant or of a literal loads, else nothing is known."
	| value offset |
	(piece at: 6) ifNil: [^known removeAll].
	value := (piece at: 6) last.
	value = #rip ifTrue: [
		offset := (piece at: 4) - anAddress.
		(offset >= 0 and: [offset + 8 <= aByteArray size]) ifFalse: [^known removeKey: (piece at: 6) first ifAbsent: [nil]].
		value := self wordOf: aByteArray at: offset].
	known at: (piece at: 6) first put: value
!
annotate: aStringOrNil with: comments on: aStream
	"aStringOrNil (an instruction line) and comments in the comment column, one per line"
	| line |
	line := aStringOrNil ifNil: [''].
	comments isEmpty ifTrue: [aStringOrNil ifNotNil: [aStream nextPutAll: line; lf]. ^self].
	comments do: [:each |
		aStream nextPutAll: (line padRightTo: self commentColumn - 2); nextPutAll: '  ; '; nextPutAll: each; lf.
		line := '']
!
commentColumn
	^76
!
bytesOf: aByteArray from: offset size: n
	"The bytes at offset (0-based) in hex, without spaces."
	^String new: 2 * n streamContents: [:s |
		offset + 1 to: offset + n do: [:i | s nextPutAll: ((((aByteArray at: i) printString: 16) asLowercase) padLeftTo: 2 with: $0)]]
!
wordOf: aByteArray at: offset
	"The little-endian 64-bit word at offset (0-based)."
	| value |
	value := 0.
	8 to: 1 by: -1 do: [:i | value := (value bitShift: 8) + (aByteArray at: offset + i)].
	^value
! !

!Amd64Disassembler methodsFor: 'decoding'!
decode
	"objdump's text of the instruction at start, nil if I do not decode it; length its size. Prefixes: 66, F2 and F3
	(once each, before the REX prefix), then REX; others, and a prefix the instruction does not use, are not decoded."
	| op selector result |
	position := start.
	prefix66 := used66 := usedRepeat := false.
	repeat := nil.
	rex := rexUsed := 0.
	ripDisplacement := nil.
	ripSize := 0.
	target := move := indirect := nil.
	op := self next.
	[op = 16r66 or: [op = 16rF2 or: [op = 16rF3]]] whileTrue: [
		op = 16r66
			ifTrue: [
				prefix66 ifTrue: [^nil].
				prefix66 := true]
			ifFalse: [
				repeat notNil ifTrue: [^nil].
				repeat := op].
		op := self next].
	(op bitAnd: 16rF0) = 16r40 ifTrue: [
		rex := op.
		op := self next].
	op = 16r0F
		ifTrue: [
			opcode := self next.
			selector := self class twoByteOpcodes at: opcode + 1]
		ifFalse: [
			opcode := op.
			selector := self class oneByteOpcodes at: opcode + 1].
	selector isNil ifTrue: [^nil].
	result := self perform: selector.
	result isNil ifTrue: [^nil].
	(prefix66 and: [used66 not]) ifTrue: [^nil].
	(repeat notNil and: [usedRepeat not]) ifTrue: [^nil].
	length := position - start.
	^self format: result
!
format: anArray
	"objdump's layout of {mnemonic. operands}: the REX prefix the instruction does not use, the mnemonic padded to 6, a
	space, the operands separated by commas; the address a [rip+disp] operand refers to after #."
	| mnemonic text |
	mnemonic := anArray first.
	(rex ~= 0 and: [rex ~= rexUsed]) ifTrue: [mnemonic := (self rexName: rex) , ' ' , mnemonic].
	text := (anArray at: 2) isEmpty
		ifTrue: [mnemonic]
		ifFalse: [(mnemonic padRightTo: 6) , ' ' , (',' join: (anArray at: 2))].
	ripDisplacement notNil ifTrue: [
		target := address + length + ripDisplacement bitAnd: 16rFFFFFFFFFFFFFFFF.
		text := text , '        # ' , (self hex: target)].
	^text
!
op: mnemonic with: operands
	^Array with: mnemonic with: operands
! !

!Amd64Disassembler methodsFor: 'integer'!
alu
	"00-3D: add or adc sbb and sub xor cmp, as Eb,Gb Ev,Gv Gb,Eb Gv,Ev AL,Ib rAX,Iz"
	| name form size |
	name := self aluName: (opcode bitShift: -3).
	form := opcode bitAnd: 7.
	size := (form bitAnd: 1) = 0 ifTrue: [8] ifFalse: [self operandSize].
	form >= 4 ifTrue: [^self op: name with: {self register: 0 size: size. self immediate: size}].
	self modrm.
	^(form bitAnd: 2) = 0
		ifTrue: [self op: name with: {self rm: size. self reg: size}]
		ifFalse: [self op: name with: {self reg: size. self rm: size}]
!
group1
	"80 Eb,Ib; 81 Ev,Iz; 83 Ev,Ib sign-extended"
	| size |
	size := opcode = 16r80 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	^self op: (self aluName: reg)
		with: {self rm: size. opcode = 16r81 ifTrue: [self immediate: size] ifFalse: [self signedByte: size]}
!
test
	"84 test Eb,Gb; 85 test Ev,Gv"
	| size |
	size := opcode = 16r84 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	^self op: 'test' with: {self rm: size. self reg: size}
!
testAccumulator
	"A8 test al,Ib; A9 test rAX,Iz"
	| size |
	size := opcode = 16rA8 ifTrue: [8] ifFalse: [self operandSize].
	^self op: 'test' with: {self register: 0 size: size. self immediate: size}
!
xchg
	"86 xchg Eb,Gb; 87 xchg Ev,Gv"
	| size |
	size := opcode = 16r86 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	^self op: 'xchg' with: {self rm: size. self reg: size}
!
xchgAccumulator
	"90 nop; 90-97 xchg r,rAX (90 with REX.B or 66 too: objdump takes the 66 of 90 as part of it even before REX.W)"
	| n size |
	n := (opcode bitAnd: 7) + (self extension: 1).
	(n = 0 and: [prefix66 not]) ifTrue: [^self op: 'nop' with: #()].
	size := self operandSize.
	opcode = 16r90 ifTrue: [used66 := prefix66].
	^self op: 'xchg' with: {self register: n size: size. self register: 0 size: size}
!
convert
	"98 cbw cwde cdqe; 99 cwd cdq cqo"
	| size |
	size := self operandSize.
	^self op: ((opcode = 16r98 ifTrue: [#('cbw' 'cwde' 'cdqe')] ifFalse: [#('cwd' 'cdq' 'cqo')]) at: size highBit - 4) with: #()
!
group2
	"C0 C1 (by Ib), D0 D1 (by 1), D2 D3 (by cl): rol ror rcl rcr shl shr shl sar"
	| size |
	size := (opcode bitAnd: 1) = 0 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	^self op: (#('rol' 'ror' 'rcl' 'rcr' 'shl' 'shr' 'shl' 'sar') at: reg + 1)
		with: {self rm: size. opcode < 16rD0 ifTrue: [self immediate: 8] ifFalse: [opcode < 16rD2 ifTrue: ['1'] ifFalse: ['cl']]}
!
group3
	"F6 Eb, F7 Ev: test (with an immediate) not neg mul imul div idiv"
	| size |
	size := opcode = 16rF6 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	reg < 2 ifTrue: [^self op: 'test' with: {self rm: size. self immediate: size}].
	^self op: (#('not' 'neg' 'mul' 'imul' 'div' 'idiv') at: reg - 1) with: {self rm: size}
!
group4
	"FE: inc dec Eb"
	self modrm.
	reg < 2 ifFalse: [^nil].
	^self op: (#('inc' 'dec') at: reg + 1) with: {self rm: 8}
!
group5
	"FF: inc dec Ev, call jmp push Eq"
	self modrm.
	reg < 2 ifTrue: [^self op: (#('inc' 'dec') at: reg + 1) with: {self rm: self operandSize}].
	reg = 6 ifTrue: [^self op: 'push' with: {self rm: 64}].
	(reg = 2 or: [reg = 4]) ifFalse: [^nil].
	mod = 3 ifTrue: [indirect := rm + (self extension: 1)].
	^self op: (reg = 2 ifTrue: ['call'] ifFalse: ['jmp']) with: {self rm: 64}
!
imul
	"0F AF imul Gv,Ev"
	| size |
	size := self operandSize.
	self modrm.
	^self op: 'imul' with: {self reg: size. self rm: size}
!
imulImmediate
	"69 imul Gv,Ev,Iz; 6B imul Gv,Ev,Ib sign-extended"
	| size |
	size := self operandSize.
	self modrm.
	^self op: 'imul' with: {self reg: size. self rm: size. opcode = 16r69 ifTrue: [self immediate: size] ifFalse: [self signedByte: size]}
!
bitTest
	"0F A3 AB B3 BB: bt bts btr btc Ev,Gv"
	| size |
	size := self operandSize.
	self modrm.
	^self op: (#('bt' 'bts' 'btr' 'btc') at: (opcode - 16rA3 bitShift: -3) + 1) with: {self rm: size. self reg: size}
!
bitTestImmediate
	"0F BA /4-/7: bt bts btr btc Ev,Ib"
	| size |
	size := self operandSize.
	self modrm.
	reg < 4 ifTrue: [^nil].
	^self op: (#('bt' 'bts' 'btr' 'btc') at: reg - 3) with: {self rm: size. self immediate: 8}
! !

!Amd64Disassembler methodsFor: 'moves'!
mov
	"88 mov Eb,Gb; 89 Ev,Gv; 8A Gb,Eb; 8B Gv,Ev"
	| size |
	size := (opcode bitAnd: 1) = 0 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	opcode < 16r8A ifTrue: [^self op: 'mov' with: {self rm: size. self reg: size}].
	(size = 64 and: [riprel]) ifTrue: [move := {reg + (self extension: 4). #rip}].
	^self op: 'mov' with: {self reg: size. self rm: size}
!
movImmediate
	"B0-B7 mov r8,Ib; B8-BF mov r,Iv (movabs r64,imm64 with REX.W)"
	| n size value |
	n := (opcode bitAnd: 7) + (self extension: 1).
	opcode < 16rB8 ifTrue: [^self op: 'mov' with: {self register: n size: 8. self immediate: 8}].
	size := self operandSize.
	size = 64 ifTrue: [
		value := self uint64.
		move := {n. value}.
		^self op: 'movabs' with: {self register: n size: 64. self hex: value}].
	size = 16 ifTrue: [^self op: 'mov' with: {self register: n size: 16. self immediate: 16}].
	value := self uint32.
	move := {n. value}.
	^self op: 'mov' with: {self register: n size: 32. self hex: value}
!
movMemoryImmediate
	"C6 /0 mov Eb,Ib; C7 /0 mov Ev,Iz"
	| size value operand |
	size := opcode = 16rC6 ifTrue: [8] ifFalse: [self operandSize].
	self modrm.
	reg = 0 ifFalse: [^nil].
	operand := self rm: size.
	size < 32 ifTrue: [^self op: 'mov' with: {operand. self immediate: size}].
	value := self int32 bitAnd: (size = 64 ifTrue: [16rFFFFFFFFFFFFFFFF] ifFalse: [16rFFFFFFFF]).
	mod = 3 ifTrue: [move := {rm + (self extension: 1). value}].
	^self op: 'mov' with: {operand. self hex: value}
!
lea
	"8D lea Gv,M"
	| size |
	size := self operandSize.
	self modrm.
	mod = 3 ifTrue: [^nil].
	^self op: 'lea' with: {self reg: size. self memory: nil}
!
movsxd
	"63 movsxd Gv,Ed (objdump takes a 66 prefix before REX.W as part of it)"
	| size |
	size := self operandSize.
	used66 := prefix66.
	self modrm.
	^self op: 'movsxd' with: {self reg: size. self rm: 32}
!
movExtend
	"0F B6 B7 movzx, BE BF movsx: Gv,Eb and Gv,Ew"
	| size |
	size := self operandSize.
	self modrm.
	^self op: ((opcode bitAnd: 8) = 0 ifTrue: ['movzx'] ifFalse: ['movsx'])
		with: {self reg: size. self rm: ((opcode bitAnd: 1) = 0 ifTrue: [8] ifFalse: [16])}
!
cmov
	"0F 40-4F cmovcc Gv,Ev"
	| size |
	size := self operandSize.
	self modrm.
	^self op: 'cmov' , (self condition: (opcode bitAnd: 15)) with: {self reg: size. self rm: size}
!
bswap
	"0F C8-CF bswap r32 (r64 with REX.W)"
	^self op: 'bswap' with: {self register: (opcode bitAnd: 7) + (self extension: 1) size: self operandSize}
!
setcc
	"0F 90-9F setcc Eb"
	self modrm.
	^self op: 'set' , (self condition: (opcode bitAnd: 15)) with: {self rm: 8}
!
pushRegister
	"50-57 push r64"
	^self op: 'push' with: {self register: (opcode bitAnd: 7) + (self extension: 1) size: 64}
!
popRegister
	"58-5F pop r64"
	^self op: 'pop' with: {self register: (opcode bitAnd: 7) + (self extension: 1) size: 64}
!
pushImmediate
	"68 push Iz, 6A push Ib, sign-extended to 64 bits"
	^self op: 'push' with: {opcode = 16r68 ifTrue: [self immediate: 64] ifFalse: [self signedByte: 64]}
!
popMemory
	"8F /0 pop Eq"
	self modrm.
	reg = 0 ifFalse: [^nil].
	^self op: 'pop' with: {self rm: 64}
! !

!Amd64Disassembler methodsFor: 'branches'!
jumpShort
	"70-7F jcc rel8"
	^self op: 'j' , (self condition: (opcode bitAnd: 15)) with: {self branch: self int8}
!
jumpNear
	"0F 80-8F jcc rel32"
	^self op: 'j' , (self condition: (opcode bitAnd: 15)) with: {self branch: self int32}
!
jump
	"E9 jmp rel32, EB jmp rel8"
	^self op: 'jmp' with: {self branch: (opcode = 16rE9 ifTrue: [self int32] ifFalse: [self int8])}
!
call
	"E8 call rel32"
	^self op: 'call' with: {self branch: self int32}
!
ret
	"C3 ret, C2 ret Iw"
	opcode = 16rC2 ifTrue: [^self op: 'ret' with: {self hex: self uint16}].
	^self op: 'ret' with: #()
!
int3
	^self op: 'int3' with: #()
!
ud2
	^self op: 'ud2' with: #()
!
nop
	"0F 1F nop Ev"
	| size |
	size := self operandSize.
	self modrm.
	^self op: 'nop' with: {self rm: size}
! !

!Amd64Disassembler methodsFor: 'floating point'!
sseMove
	"0F 10 and 11: movsd (F2), movupd (66), loads and stores"
	| name size |
	name := self mandatoryPrefix.
	name = 16rF2 ifTrue: [name := 'movsd'. size := 64] ifFalse: [
		name = 16r66 ifFalse: [^nil].
		name := 'movupd'.
		size := 128].
	self modrm.
	^opcode = 16r10
		ifTrue: [self op: name with: {self xmmReg. self xmmRm: size}]
		ifFalse: [self op: name with: {self xmmRm: size. self xmmReg}]
!
movapd
	"66 0F 28 movapd load, 29 store"
	self mandatoryPrefix = 16r66 ifFalse: [^nil].
	self modrm.
	^opcode = 16r28
		ifTrue: [self op: 'movapd' with: {self xmmReg. self xmmRm: 128}]
		ifFalse: [self op: 'movapd' with: {self xmmRm: 128. self xmmReg}]
!
scalarDouble
	"F2 0F 51 58 59 5C 5D 5E 5F: sqrtsd addsd mulsd subsd minsd divsd maxsd xmm,xmm/m64"
	self mandatoryPrefix = 16rF2 ifFalse: [^nil].
	self modrm.
	^self op: (#('sqrtsd' nil nil nil nil nil nil 'addsd' 'mulsd' nil nil 'subsd' 'minsd' 'divsd' 'maxsd') at: opcode - 16r50)
		with: {self xmmReg. self xmmRm: 64}
!
logicalDouble
	"66 0F 54-57: andpd andnpd orpd xorpd"
	self mandatoryPrefix = 16r66 ifFalse: [^nil].
	self modrm.
	^self op: (#('andpd' 'andnpd' 'orpd' 'xorpd') at: opcode - 16r53) with: {self xmmReg. self xmmRm: 128}
!
sseCompare
	"66 0F 2E ucomisd, 2F comisd"
	self mandatoryPrefix = 16r66 ifFalse: [^nil].
	self modrm.
	^self op: (opcode = 16r2E ifTrue: ['ucomisd'] ifFalse: ['comisd']) with: {self xmmReg. self xmmRm: 64}
!
cvtsi2sd
	"F2 0F 2A cvtsi2sd xmm,r/m32 (r/m64 with REX.W)"
	| size |
	self mandatoryPrefix = 16rF2 ifFalse: [^nil].
	size := self wideSize.
	self modrm.
	^self op: 'cvtsi2sd' with: {self xmmReg. self rm: size}
!
cvtsd2si
	"F2 0F 2C cvttsd2si, 2D cvtsd2si: r32 (r64 with REX.W), xmm/m64"
	| size |
	self mandatoryPrefix = 16rF2 ifFalse: [^nil].
	size := self wideSize.
	self modrm.
	^self op: (opcode = 16r2C ifTrue: ['cvttsd2si'] ifFalse: ['cvtsd2si']) with: {self reg: size. self xmmRm: 64}
!
movdToXmm
	"66 0F 6E movd xmm,r/m32; movq xmm,r/m64 (REX.W)"
	| size |
	self mandatoryPrefix = 16r66 ifFalse: [^nil].
	size := self wideSize.
	self modrm.
	^self op: (size = 64 ifTrue: ['movq'] ifFalse: ['movd']) with: {self xmmReg. self rm: size}
!
movdFromXmm
	"66 0F 7E movd r/m32,xmm; movq r/m64,xmm (REX.W); F3 0F 7E movq xmm,xmm/m64"
	| prefix size |
	prefix := self mandatoryPrefix.
	prefix = 16rF3 ifTrue: [
		self modrm.
		^self op: 'movq' with: {self xmmReg. self xmmRm: 64}].
	prefix = 16r66 ifFalse: [^nil].
	size := self wideSize.
	self modrm.
	^self op: (size = 64 ifTrue: ['movq'] ifFalse: ['movd']) with: {self rm: size. self xmmReg}
!
movqToMemory
	"66 0F D6 movq xmm/m64,xmm"
	self mandatoryPrefix = 16r66 ifFalse: [^nil].
	self modrm.
	^self op: 'movq' with: {self xmmRm: 64. self xmmReg}
! !

!Amd64Disassembler methodsFor: 'operands'!
modrm
	"Read the ModRM byte, then the SIB byte and the displacement of a memory operand."
	| b |
	b := self next.
	mod := b bitShift: -6.
	reg := (b bitShift: -3) bitAnd: 7.
	rm := b bitAnd: 7.
	hasSib := riprel := false.
	displacement := 0.
	mod = 3 ifTrue: [^self].
	rm = 4 ifTrue: [
		b := self next.
		hasSib := true.
		scale := b bitShift: -6.
		index := (b bitShift: -3) bitAnd: 7.
		base := b bitAnd: 7].
	mod = 1 ifTrue: [^displacement := self int8].
	mod = 2 ifTrue: [^displacement := self int32].
	hasSib
		ifTrue: [base = 5 ifTrue: [displacement := self int32]]
		ifFalse: [
			rm = 5 ifTrue: [
				riprel := true.
				displacement := self int32]]
!
reg: size
	"The register of the ModRM reg field (REX.R) at size bits."
	^self register: reg + (self extension: 4) size: size
!
rm: size
	"The ModRM r/m operand: a register at size bits (REX.B), or memory with size's PTR."
	mod = 3 ifTrue: [^self register: rm + (self extension: 1) size: size].
	^self memory: size
!
xmmReg
	^'xmm' , (reg + (self extension: 4)) printString
!
xmmRm: size
	mod = 3 ifTrue: [^'xmm' , (rm + (self extension: 1)) printString].
	^self memory: size
!
memory: size
	"A memory operand as objdump prints it: 'QWORD PTR [rbx+rsi*8+0x10]' (no size for lea: nil), [rip+0x...] (the
	address it refers to is printed after the instruction), riz for a SIB byte without an index where one is needed,
	ds:0x... without base and index."
	| prefix baseNumber indexNumber haveBase haveIndex |
	prefix := size isNil ifTrue: [''] ifFalse: [(self sizeName: size) , ' PTR '].
	baseNumber := (hasSib ifTrue: [base] ifFalse: [rm]) + (self extension: 1).
	riprel ifTrue: [
		ripDisplacement := displacement.
		ripSize := size ifNil: [0].
		^prefix , '[rip+' , (self hex: (displacement bitAnd: 16rFFFFFFFFFFFFFFFF)) , ']'].
	hasSib ifFalse: [
		^prefix , '[' , (self register: baseNumber size: 64) ,
			(mod = 0 ifTrue: [''] ifFalse: [self displacement: displacement]) , ']'].
	indexNumber := index + (self extension: 2).
	haveIndex := indexNumber ~= 4.
	haveBase := mod ~= 0 or: [base ~= 5].
	(haveBase or: [haveIndex or: [scale ~= 0]]) ifFalse: [
		^prefix , 'ds:' , (self hex: (displacement bitAnd: 16rFFFFFFFFFFFFFFFF))].
	^String new: 40 streamContents: [:s |
		s nextPutAll: prefix; nextPut: $[.
		haveBase ifTrue: [s nextPutAll: (self register: baseNumber size: 64)].
		(scale ~= 0 or: [haveIndex or: [haveBase and: [base ~= 4]]]) ifTrue: [
			haveBase ifTrue: [s nextPut: $+].
			s nextPutAll: (haveIndex ifTrue: [self register: indexNumber size: 64] ifFalse: ['riz']); nextPut: $*; print: (1 bitShift: scale)].
		(displacement ~= 0 or: [mod ~= 0 or: [base = 5]]) ifTrue: [s nextPutAll: (self displacement: displacement)].
		s nextPut: $]]
!
register: n size: size
	"General register n at size bits; byte registers 4-7 are spl-dil with a REX prefix, else ah-bh."
	size = 64 ifTrue: [^#('rax' 'rcx' 'rdx' 'rbx' 'rsp' 'rbp' 'rsi' 'rdi' 'r8' 'r9' 'r10' 'r11' 'r12' 'r13' 'r14' 'r15') at: n + 1].
	size = 32 ifTrue: [^#('eax' 'ecx' 'edx' 'ebx' 'esp' 'ebp' 'esi' 'edi' 'r8d' 'r9d' 'r10d' 'r11d' 'r12d' 'r13d' 'r14d' 'r15d') at: n + 1].
	size = 16 ifTrue: [^#('ax' 'cx' 'dx' 'bx' 'sp' 'bp' 'si' 'di' 'r8w' 'r9w' 'r10w' 'r11w' 'r12w' 'r13w' 'r14w' 'r15w') at: n + 1].
	(n bitAnd: 4) ~= 0 ifTrue: [self useRex: 0].
	rex = 0 ifTrue: [^#('al' 'cl' 'dl' 'bl' 'ah' 'ch' 'dh' 'bh') at: n + 1].
	^#('al' 'cl' 'dl' 'bl' 'spl' 'bpl' 'sil' 'dil' 'r8b' 'r9b' 'r10b' 'r11b' 'r12b' 'r13b' 'r14b' 'r15b') at: n + 1
!
immediate: size
	"An immediate of size bits (64: 32 bits sign-extended)."
	size = 8 ifTrue: [^self hex: self next].
	size = 16 ifTrue: [^self hex: self uint16].
	size = 32 ifTrue: [^self hex: self uint32].
	^self hex: (self int32 bitAnd: 16rFFFFFFFFFFFFFFFF)
!
signedByte: size
	"An 8-bit immediate sign-extended to size bits."
	^self hex: (self int8 bitAnd: (1 bitShift: size) - 1)
!
branch: offset
	"The address offset bytes after the instruction (its last field just read), printed."
	target := address + (position - start) + offset bitAnd: 16rFFFFFFFFFFFFFFFF.
	^self hex: target
!
operandSize
	"The size of a v operand: 64 with REX.W, 16 with the 66 prefix, else 32."
	(rex bitAnd: 8) ~= 0 ifTrue: [
		self useRex: 8.
		^64].
	prefix66 ifTrue: [
		used66 := true.
		^16].
	^32
!
wideSize
	"The size of a y operand: 64 with REX.W, else 32."
	(rex bitAnd: 8) ~= 0 ifTrue: [
		self useRex: 8.
		^64].
	^32
!
mandatoryPrefix
	"The prefix that selects an SSE instruction: F2 or F3 if there is one, else 66, else 0."
	repeat notNil ifTrue: [
		usedRepeat := true.
		^repeat].
	prefix66 ifTrue: [
		used66 := true.
		^16r66].
	^0
!
extension: bit
	"8 if REX has bit (4 R, 2 X, 1 B: the high bit of a register number), else 0."
	(rex bitAnd: bit) = 0 ifTrue: [^0].
	self useRex: bit.
	^8
!
useRex: bit
	"The instruction uses REX's bit (8 W, 4 R, 2 X, 1 B), or the REX prefix itself (0: spl-dil)."
	bit = 0
		ifTrue: [rex ~= 0 ifTrue: [rexUsed := rexUsed bitOr: 16r40]]
		ifFalse: [(rex bitAnd: bit) ~= 0 ifTrue: [rexUsed := rexUsed bitOr: (bit bitOr: 16r40)]]
! !

!Amd64Disassembler methodsFor: 'private'!
next
	| b |
	position > limit ifTrue: [^self error: 'the instruction does not end in the bytes'].
	b := bytes at: position.
	position := position + 1.
	^b
!
int8
	| b |
	b := self next.
	^b >= 128 ifTrue: [b - 256] ifFalse: [b]
!
uint16
	^self next + (self next bitShift: 8)
!
uint32
	^self next + (self next bitShift: 8) + (self next bitShift: 16) + (self next bitShift: 24)
!
int32
	| v |
	v := self uint32.
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
!
uint64
	^self uint32 + (self uint32 bitShift: 32)
! !

!Amd64Disassembler methodsFor: 'printing'!
hex: anInteger
	^'0x' , (anInteger printString: 16) asLowercase
!
displacement: anInteger
	"+0x10 or -0x10"
	anInteger < 0 ifTrue: [^'-' , (self hex: anInteger negated)].
	^'+' , (self hex: anInteger)
!
sizeName: size
	size = 8 ifTrue: [^'BYTE'].
	size = 16 ifTrue: [^'WORD'].
	size = 32 ifTrue: [^'DWORD'].
	size = 64 ifTrue: [^'QWORD'].
	^'XMMWORD'
!
aluName: n
	^#('add' 'or' 'adc' 'sbb' 'and' 'sub' 'xor' 'cmp') at: n + 1
!
condition: cc
	^#('o' 'no' 'b' 'ae' 'e' 'ne' 'be' 'a' 's' 'ns' 'p' 'np' 'l' 'ge' 'le' 'g') at: cc + 1
!
rexName: aByte
	"rex, rex.W, rex.WRXB, ... as objdump names a REX prefix"
	| name |
	name := ''.
	#(8 4 2 1) with: #('W' 'R' 'X' 'B') do: [:bit :letter | (aByte bitAnd: bit) ~= 0 ifTrue: [name := name , letter]].
	^name isEmpty ifTrue: ['rex'] ifFalse: ['rex.' , name]
! !
