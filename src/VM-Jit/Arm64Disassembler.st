Object subclass: #Arm64Disassembler
	instanceVariableNames: 'word address wide target'
	classVariableNames: ''
	package: 'VM-Jit'!

Arm64Disassembler comment: 'I print arm64 instruction words as LLVM''s objdump does (preferred aliases, hex immediates, absolute branch targets), for the instructions the JIT uses: integer arithmetic, logic, moves, shifts, bitfields, loads and stores, branches, barriers and scalar double FP. Other words print as .word 0x...
listingOfWords:at:annotations: prints JIT output with its Arm64CodeAnnotations: bytecodes, comments, labels, symbols.

	Arm64Disassembler new textFor: 16r91003020 at: 0	"add x0, x1, #0xc"'!

!Arm64Disassembler class methodsFor: 'decoding'!
decoders
	"mask, value, selector: the first entry whose mask and value match a word decodes it"
	^#(
		16r1F800000 16r11000000 addSubImmediate
		16r1F200000 16r0B000000 addSubShifted
		16r1F200000 16r0B200000 addSubExtended
		16r1F000000 16r0A000000 logicalShifted
		16r1F800000 16r12000000 logicalImmediate
		16r1F800000 16r12800000 moveWide
		16r1F800000 16r13000000 bitfield
		16r1F800000 16r13800000 extract
		16r7FE00000 16r1AC00000 dataProcessing2
		16r7FE00000 16r5AC00000 dataProcessing1
		16r7F000000 16r1B000000 dataProcessing3
		16r3FE00000 16r1A800000 conditionalSelect
		16r3FE00410 16r3A400000 conditionalCompare
		16r3B000000 16r39000000 loadStoreUnsigned
		16r3B200000 16r38000000 loadStoreImmediate
		16r3B200C00 16r38200800 loadStoreRegister
		16r3A000000 16r28000000 loadStorePair
		16r3B000000 16r18000000 loadLiteral
		16r1F000000 16r10000000 pcRelative
		16r7C000000 16r14000000 branch
		16rFF000010 16r54000000 conditionalBranch
		16r7E000000 16r34000000 compareBranch
		16r7E000000 16r36000000 testBranch
		16rFF9FFC1F 16rD61F0000 branchRegister
		16rFFE0001F 16rD4200000 breakpoint
		16rFFFFF01F 16rD503301F barrier
		16rFFFFFFFF 16rD503201F nop
		16rFFE07C00 16r1E604000 fp1
		16rFFE00C00 16r1E600800 fp2
		16rFFE0FC07 16r1E602000 fpCompare
		16rFFE00C00 16r1E600C00 fpSelect
		16rFFE01FE0 16r1E601000 fpMoveImmediate
		16r7FE0FC00 16r1E600000 fpInteger)
! !

!Arm64Disassembler methodsFor: 'disassembling'!
textFor: aWord at: anAddress
	"objdump's text of the instruction aWord at anAddress"
	| decoders |
	word := aWord.
	address := anAddress.
	wide := (self bit: 31) = 1.
	target := nil.
	decoders := self class decoders.
	1 to: decoders size by: 3 do: [:i |
		(word bitAnd: (decoders at: i)) = (decoders at: i + 1) ifTrue: [
			^([self perform: (decoders at: i + 2)] on: Error do: [:e | e return: nil]) ifNil: [self dataWord]]].
	^self dataWord
!
target
	"the address the last instruction branches to or addresses (b, bl, b.cond, cbz, tbz, adr, ldr literal), else nil"
	^target
!
listingOfWords: anArray at: anAddress
	"Lines '0x100000: 91003020  add x0, x1, #0xc' of the words of anArray from anAddress on."
	^String new: anArray size * 40 streamContents: [:s |
		anArray doWithIndex: [:each :i | | a |
			a := anAddress + (i - 1 * 4).
			s nextPutAll: (self hex: a); nextPutAll: ': '; nextPutAll: (self hex8: each); nextPutAll: '  ';
				nextPutAll: (self textFor: each at: a); lf]]
!
listing: aSimulatedMemory from: start to: end
	"The listing of the words from address start up to (not including) end."
	^self listingOfWords: (self words: aSimulatedMemory from: start to: end) at: start
!
listing: aSimulatedMemory from: start to: end annotations: anArm64CodeAnnotations
	^self listingOfWords: (self words: aSimulatedMemory from: start to: end) at: start annotations: anArm64CodeAnnotations
!
words: aSimulatedMemory from: start to: end
	^(start to: end - 1 by: 4) collect: [:a | aSimulatedMemory uint32At: a]
! !

!Arm64Disassembler methodsFor: 'annotated listing'!
listingOfWords: anArray at: anAddress annotations: anArm64CodeAnnotations
	"The code of anArray at anAddress with the annotations (or nil): a header line 'pc 3: send: #+  -- source' before
	the code of each bytecode, lines '  +0004  54000060  b.ne L1' with the comments at their offset in a column on the
	right, labels Ln: at the targets inside the code, and named targets (bl 0x... <name>, blr x16 <name>)."
	| notes size labels known |
	notes := anArm64CodeAnnotations ifNil: [Arm64CodeAnnotations new].
	size := anArray size * 4.
	labels := self labelsOf: anArray at: anAddress.
	known := Dictionary new.
	^String new: anArray size * 60 streamContents: [:s |
		0 to: size by: 4 do: [:offset |
			(notes bytecodesAt: offset) do: [:each |
				s position > 0 ifTrue: [s lf].
				s nextPutAll: 'pc '; print: (each at: 1); nextPutAll: ': '; nextPutAll: (each at: 2).
				(each at: 3) ifNotNil: [:source | s nextPutAll: '  -- '; nextPutAll: source].
				s lf].
			(labels at: offset ifAbsent: [nil]) ifNotNil: [:label |
				known := Dictionary new.
				s nextPutAll: label; nextPut: $:; lf].
			self
				annotate: (offset < size ifTrue: [
					'  +' , ((offset printString: 16) asLowercase padLeftTo: 4 with: $0) , '  ' ,
						(self hex8: (anArray at: offset // 4 + 1)) , '  ' ,
						(self annotatedText: anArray at: anAddress offset: offset labels: labels symbols: notes known: known)])
				with: (notes commentsAt: offset)
				on: s]]
!
labelsOf: anArray at: anAddress
	"offset -> 'Ln' for the targets inside the code (its end included), numbered in address order"
	| offsets labels |
	offsets := Set new.
	anArray doWithIndex: [:each :i | | offset |
		self textFor: each at: anAddress + (i - 1 * 4).
		target ifNotNil: [
			offset := target - anAddress.
			(offset >= 0 and: [offset <= (anArray size * 4) and: [offset \\ 4 = 0]]) ifTrue: [offsets add: offset]]].
	labels := Dictionary new.
	offsets asSortedCollection doWithIndex: [:offset :i | labels at: offset put: 'L' , i printString].
	^labels
!
annotatedText: anArray at: anAddress offset: offset labels: labels symbols: notes known: known
	"textFor:at: with targets inside the code as labels and named targets as 'text <name>'; known maps registers to
	the constants the preceding movz/movk/movn or ldr literal sequence loaded"
	| text name |
	text := self textFor: (anArray at: offset // 4 + 1) at: anAddress + offset.
	target ifNotNil: [
		(labels at: target - anAddress ifAbsent: [nil]) ifNotNil: [:label |
			text := (text copyFrom: 1 to: text size - (self address: target) size) , label].
		name := notes symbolAt: target].
	(word bitAnd: 16rFFDFFC1F) = 16rD61F0000 ifTrue: [
		(known at: (self field: 5 width: 5) ifAbsent: [nil]) ifNotNil: [:value | name := notes symbolAt: value]].
	self track: known words: anArray at: anAddress.
	^name ifNil: [text] ifNotNil: [text , ' <' , name , '>']
!
track: known words: anArray at: anAddress
	"Update known after the instruction just decoded: x registers loaded by movz, movn, movk or ldr literal."
	| rd shift value offset |
	rd := self field: 0 width: 5.
	((word bitAnd: 16rFF800000) = 16rD2800000 or: [(word bitAnd: 16rFF800000) = 16r92800000]) ifTrue: [
		value := (self field: 5 width: 16) bitShift: (self field: 21 width: 2) * 16.
		(self bit: 30) = 0 ifTrue: [value := value bitInvert bitAnd: 16rFFFFFFFFFFFFFFFF].
		^known at: rd put: value].
	(word bitAnd: 16rFF800000) = 16rF2800000 ifTrue: [
		shift := (self field: 21 width: 2) * 16.
		value := known at: rd ifAbsent: [^known removeKey: rd ifAbsent: [nil]].
		^known at: rd put: ((value bitClear: (16rFFFF bitShift: shift)) bitOr: ((self field: 5 width: 16) bitShift: shift))].
	((word bitAnd: 16rFF000000) = 16r58000000 and: [target notNil]) ifTrue: [
		offset := target - anAddress.
		(offset >= 0 and: [offset + 8 <= (anArray size * 4) and: [offset \\ 4 = 0]]) ifTrue: [
			^known at: rd put: (anArray at: offset // 4 + 1) + ((anArray at: offset // 4 + 2) bitShift: 32)]].
	known removeAll
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
	^52
! !

!Arm64Disassembler methodsFor: 'integer'!
addSubImmediate
	| op s imm rd rn |
	op := self bit: 30.
	s := self bit: 29.
	imm := Array with: (self imm: (self field: 10 width: 12)).
	(self bit: 22) = 1 ifTrue: [imm := imm , #('lsl #12')].
	rd := self field: 0 width: 5.
	rn := self field: 5 width: 5.
	(op = 0 and: [s = 0 and: [(self field: 10 width: 13) = 0 and: [rd = 31 or: [rn = 31]]]])
		ifTrue: [^self op: 'mov' with: {self rsp: rd. self rsp: rn}].
	(s = 1 and: [rd = 31]) ifTrue: [^self op: (#('cmn' 'cmp') at: op + 1) with: {self rsp: rn} , imm].
	^self op: (#('add' 'adds' 'sub' 'subs') at: op * 2 + s + 1)
		with: {s = 1 ifTrue: [self r: rd] ifFalse: [self rsp: rd]. self rsp: rn} , imm
!
addSubShifted
	| op s shift rd rn rm |
	(self field: 22 width: 2) = 3 ifTrue: [^nil].
	(shift := self shift) ifNil: [^nil].
	op := self bit: 30.
	s := self bit: 29.
	rd := self r: (self field: 0 width: 5).
	rn := self field: 5 width: 5.
	rm := self r: (self field: 16 width: 5).
	(s = 1 and: [(self field: 0 width: 5) = 31])
		ifTrue: [^self op: (#('cmn' 'cmp') at: op + 1) with: {self r: rn. rm} , shift].
	(op = 1 and: [rn = 31]) ifTrue: [^self op: (#('neg' 'negs') at: s + 1) with: {rd. rm} , shift].
	^self op: (#('add' 'adds' 'sub' 'subs') at: op * 2 + s + 1) with: {rd. self r: rn. rm} , shift
!
addSubExtended
	| op s option amount rd rn rm extend |
	(self field: 22 width: 2) = 0 ifFalse: [^nil].
	(amount := self field: 10 width: 3) > 4 ifTrue: [^nil].
	op := self bit: 30.
	s := self bit: 29.
	option := self field: 13 width: 3.
	rd := self field: 0 width: 5.
	rn := self field: 5 width: 5.
	rm := self field: 16 width: 5.
	rm := (wide and: [(option bitAnd: 3) = 3]) ifTrue: [self x: rm] ifFalse: [self w: rm].
	extend := (option = (wide ifTrue: [3] ifFalse: [2]) and: [rn = 31 or: [s = 0 and: [rd = 31]]])
		ifTrue: [amount = 0 ifTrue: [#()] ifFalse: [{'lsl #' , amount printString}]]
		ifFalse: [{(#('uxtb' 'uxth' 'uxtw' 'uxtx' 'sxtb' 'sxth' 'sxtw' 'sxtx') at: option + 1) ,
			(amount = 0 ifTrue: [''] ifFalse: [' #' , amount printString])}].
	(s = 1 and: [rd = 31]) ifTrue: [^self op: (#('cmn' 'cmp') at: op + 1) with: {self rsp: rn. rm} , extend].
	^self op: (#('add' 'adds' 'sub' 'subs') at: op * 2 + s + 1)
		with: {s = 1 ifTrue: [self r: rd] ifFalse: [self rsp: rd]. self rsp: rn. rm} , extend
!
logicalShifted
	| opc n shift rd rn rm |
	(shift := self shift) ifNil: [^nil].
	opc := self field: 29 width: 2.
	n := self bit: 21.
	rd := self field: 0 width: 5.
	rn := self field: 5 width: 5.
	rm := self r: (self field: 16 width: 5).
	(opc = 1 and: [rn = 31]) ifTrue: [
		n = 1 ifTrue: [^self op: 'mvn' with: {self r: rd. rm} , shift].
		shift isEmpty ifTrue: [^self op: 'mov' with: {self r: rd. rm}]].
	(opc = 3 and: [n = 0 and: [rd = 31]]) ifTrue: [^self op: 'tst' with: {self r: rn. rm} , shift].
	^self op: (#('and' 'bic' 'orr' 'orn' 'eor' 'eon' 'ands' 'bics') at: opc * 2 + n + 1)
		with: {self r: rd. self r: rn. rm} , shift
!
logicalImmediate
	| opc value rd rn |
	(wide not and: [(self bit: 22) = 1]) ifTrue: [^nil].
	(value := self bitmask: (self field: 10 width: 13)) ifNil: [^nil].
	opc := self field: 29 width: 2.
	rd := self field: 0 width: 5.
	rn := self field: 5 width: 5.
	(opc = 3 and: [rd = 31]) ifTrue: [^self op: 'tst' with: {self r: rn. '#' , (self hex: value)}].
	(opc = 1 and: [rn = 31 and: [(self isMoveWide: value) not]])
		ifTrue: [^self op: 'mov' with: {self rsp: rd. self imm: (self signed: value bits: self width)}].
	^self op: (#('and' 'orr' 'eor' 'ands') at: opc + 1)
		with: {opc = 3 ifTrue: [self r: rd] ifFalse: [self rsp: rd]. self r: rn. '#' , (self hex: value)}
!
moveWide
	| opc shift imm value rd |
	opc := self field: 29 width: 2.
	opc = 1 ifTrue: [^nil].
	shift := (self field: 21 width: 2) * 16.
	shift >= self width ifTrue: [^nil].
	imm := self field: 5 width: 16.
	rd := self r: (self field: 0 width: 5).
	value := imm bitShift: shift.
	opc = 0 ifTrue: [value := value bitInvert bitAnd: self mask].
	((opc = 2 and: [self isMove: value shift: shift])
		or: [opc = 0 and: [(self isAnyMove: value) not and: [self isMove: (value bitInvert bitAnd: self mask) shift: shift]]])
			ifTrue: [^self op: 'mov' with: {rd. self imm: (self signed: value bits: self width)}].
	^self op: (#('movn' nil 'movz' 'movk') at: opc + 1)
		with: {rd. self imm: imm} , (shift = 0 ifTrue: [#()] ifFalse: [{'lsl #' , shift printString}])
!
bitfield
	| opc immr imms size rd rn |
	opc := self field: 29 width: 2.
	opc = 3 ifTrue: [^nil].
	(self bit: 22) = (self bit: 31) ifFalse: [^nil].
	size := self width.
	immr := self field: 16 width: 6.
	imms := self field: 10 width: 6.
	(immr >= size or: [imms >= size]) ifTrue: [^nil].
	rd := self r: (self field: 0 width: 5).
	rn := self r: (self field: 5 width: 5).
	opc = 1 ifTrue: [
		^imms < immr
			ifTrue: [self op: 'bfi' with: {rd. rn. '#' , (size - immr) printString. '#' , (imms + 1) printString}]
			ifFalse: [self op: 'bfxil' with: {rd. rn. '#' , immr printString. '#' , (imms - immr + 1) printString}]].
	immr = 0 ifTrue: [| name |
		name := imms = 7 ifTrue: ['xtb'] ifFalse: [imms = 15 ifTrue: ['xth'] ifFalse: [imms = 31 ifTrue: ['xtw']]].
		(name notNil and: [opc = 0 ifTrue: [wide or: [imms < 31]] ifFalse: [wide not and: [imms < 31]]])
			ifTrue: [^self op: (opc = 0 ifTrue: ['s'] ifFalse: ['u']) , name with: {rd. self w: (self field: 5 width: 5)}]].
	imms = (size - 1) ifTrue: [^self op: (opc = 0 ifTrue: ['asr'] ifFalse: ['lsr']) with: {rd. rn. '#' , immr printString}].
	(opc = 2 and: [imms + 1 = immr]) ifTrue: [^self op: 'lsl' with: {rd. rn. '#' , (size - 1 - imms) printString}].
	^immr > imms
		ifTrue: [self op: (opc = 0 ifTrue: ['sbfiz'] ifFalse: ['ubfiz'])
			with: {rd. rn. '#' , (size - immr) printString. '#' , (imms + 1) printString}]
		ifFalse: [self op: (opc = 0 ifTrue: ['sbfx'] ifFalse: ['ubfx'])
			with: {rd. rn. '#' , immr printString. '#' , (imms - immr + 1) printString}]
!
extract
	| imms rn rm |
	((self field: 29 width: 2) = 0 and: [(self bit: 21) = 0 and: [(self bit: 22) = (self bit: 31)]]) ifFalse: [^nil].
	imms := self field: 10 width: 6.
	imms >= self width ifTrue: [^nil].
	rn := self field: 5 width: 5.
	rm := self field: 16 width: 5.
	rn = rm ifTrue: [^self op: 'ror' with: {self r: (self field: 0 width: 5). self r: rn. self imm: imms}].
	^self op: 'extr' with: {self r: (self field: 0 width: 5). self r: rn. self r: rm. self imm: imms}
!
dataProcessing2
	| name |
	name := #(nil nil 'udiv' 'sdiv' nil nil nil nil 'lsl' 'lsr' 'asr' 'ror') at: (self field: 10 width: 6) + 1 ifAbsent: [nil].
	name ifNil: [^nil].
	^self op: name with: (#(0 5 16) collect: [:lsb | self r: (self field: lsb width: 5)])
!
dataProcessing1
	(self field: 10 width: 11) = 4 ifFalse: [^nil].
	^self op: 'clz' with: (#(0 5) collect: [:lsb | self r: (self field: lsb width: 5)])
!
dataProcessing3
	| op31 o0 regs |
	op31 := self field: 21 width: 3.
	o0 := self bit: 15.
	regs := #(0 5 16) collect: [:lsb | self r: (self field: lsb width: 5)].
	op31 = 0 ifTrue: [
		^(self field: 10 width: 5) = 31
			ifTrue: [self op: (#('mul' 'mneg') at: o0 + 1) with: regs]
			ifFalse: [self op: (#('madd' 'msub') at: o0 + 1) with: regs , {self r: (self field: 10 width: 5)}]].
	(wide and: [o0 = 0 and: [op31 = 2 or: [op31 = 6]]]) ifFalse: [^nil].
	^self op: (op31 = 2 ifTrue: ['smulh'] ifFalse: ['umulh']) with: regs
!
conditionalSelect
	| kind cond rd rn rm |
	(self field: 11 width: 1) = 1 ifTrue: [^nil].
	kind := (self bit: 30) * 2 + (self bit: 10).
	cond := self field: 12 width: 4.
	rd := self r: (self field: 0 width: 5).
	rn := self field: 5 width: 5.
	rm := self field: 16 width: 5.
	(kind > 0 and: [rn = rm and: [cond < 14]]) ifTrue: [| inverse |
		inverse := self condition: (cond bitXor: 1).
		(rn = 31 and: [kind < 3]) ifTrue: [^self op: (#('cset' 'csetm') at: kind) with: {rd. inverse}].
		^self op: (#('cinc' 'cinv' 'cneg') at: kind) with: {rd. self r: rn. inverse}].
	^self op: (#('csel' 'csinc' 'csinv' 'csneg') at: kind + 1)
		with: {rd. self r: rn. self r: rm. self condition: cond}
!
conditionalCompare
	| m |
	m := self field: 16 width: 5.
	^self op: ((self bit: 30) = 1 ifTrue: ['ccmp'] ifFalse: ['ccmn'])
		with: {self r: (self field: 5 width: 5).
			(self bit: 11) = 1 ifTrue: [self imm: m] ifFalse: [self r: m].
			self imm: (self field: 0 width: 4).
			self condition: (self field: 12 width: 4)}
! !

!Arm64Disassembler methodsFor: 'memory'!
loadStoreUnsigned
	| kind |
	(kind := self loadStoreKind) ifNil: [^nil].
	^self memory: kind at: (self base: ((self field: 10 width: 12) bitShift: (kind at: 3)) suffix: '')
!
loadStoreImmediate
	| kind index offset |
	(kind := self loadStoreKind) ifNil: [^nil].
	index := self field: 10 width: 2.
	index = 2 ifTrue: [^nil].
	offset := self signed: (self field: 12 width: 9) bits: 9.
	index = 0 ifTrue: [
		kind at: 1 put: ((kind at: 1) copyReplaceAll: 'r' with: 'ur').
		^self memory: kind at: (self base: offset suffix: '')].
	index = 1 ifTrue: [^self memory: kind at: '[' , (self xsp: (self field: 5 width: 5)) , '], ' , (self imm: offset)].
	^self memory: kind at: (self base: offset suffix: '!!')
!
loadStoreRegister
	| kind option rm shift extend |
	(kind := self loadStoreKind) ifNil: [^nil].
	option := self field: 13 width: 3.
	(option bitAnd: 2) = 0 ifTrue: [^nil].
	rm := self field: 16 width: 5.
	rm := (option bitAnd: 1) = 1 ifTrue: [self x: rm] ifFalse: [self w: rm].
	shift := (self bit: 12) = 1 ifTrue: [' #' , (kind at: 3) printString] ifFalse: [''].
	extend := option = 3
		ifTrue: [shift isEmpty ifTrue: [''] ifFalse: [', lsl' , shift]]
		ifFalse: [', ' , (#('uxtw' nil nil nil 'sxtw' 'sxtx') at: option - 1) , shift].
	^self memory: kind at: '[' , (self xsp: (self field: 5 width: 5)) , ', ' , rm , extend , ']'
!
loadStorePair
	| opc index register scale offset |
	opc := self field: 30 width: 2.
	index := self field: 23 width: 2.
	index = 0 ifTrue: [^nil].
	(self bit: 26) = 1
		ifTrue: [opc = 1 ifFalse: [^nil]. register := #d:. scale := 3]
		ifFalse: [(opc bitAnd: 1) = 1 ifTrue: [^nil]. register := opc = 0 ifTrue: [#w:] ifFalse: [#x:]. scale := opc // 2 + 2].
	offset := (self signed: (self field: 15 width: 7) bits: 7) bitShift: scale.
	^self op: (#('stp' 'ldp') at: (self bit: 22) + 1)
		with: {self perform: register with: (self field: 0 width: 5).
			self perform: register with: (self field: 10 width: 5).
			index = 1
				ifTrue: ['[' , (self xsp: (self field: 5 width: 5)) , '], ' , (self imm: offset)]
				ifFalse: [self base: offset suffix: (index = 3 ifTrue: ['!!'] ifFalse: [''])]}
!
loadLiteral
	| opc rt |
	opc := self field: 30 width: 2.
	rt := self field: 0 width: 5.
	(self bit: 26) = 1
		ifTrue: [opc = 1 ifFalse: [^nil]. rt := self d: rt]
		ifFalse: [opc = 3 ifTrue: [^nil]. rt := opc = 0 ifTrue: [self w: rt] ifFalse: [self x: rt]].
	^self op: (opc = 2 ifTrue: ['ldrsw'] ifFalse: ['ldr']) with: {rt. self target: (self field: 5 width: 19) bits: 19}
!
loadStoreKind
	"{mnemonic. register selector. log2 of the access size} of a load or store with an immediate or register offset"
	| size opc name |
	size := self field: 30 width: 2.
	opc := self field: 22 width: 2.
	(self bit: 26) = 1 ifTrue: [
		^(size = 3 and: [opc < 2]) ifTrue: [{#('str' 'ldr') at: opc + 1. #d:. 3}]].
	name := (#(('strb' 'ldrb' 'ldrsb' 'ldrsb') ('strh' 'ldrh' 'ldrsh' 'ldrsh') ('str' 'ldr' 'ldrsw' nil) ('str' 'ldr' nil nil))
		at: size + 1) at: opc + 1.
	name ifNil: [^nil].
	^{name. (opc = 2 or: [size = 3]) ifTrue: [#x:] ifFalse: [#w:]. size}
!
memory: kind at: aString
	^self op: (kind at: 1) with: {self perform: (kind at: 2) with: (self field: 0 width: 5). aString}
!
base: offset suffix: aString
	"[xn], [xn, #off] or [xn, #off]!!"
	| base |
	base := '[' , (self xsp: (self field: 5 width: 5)).
	(offset = 0 and: [aString isEmpty]) ifTrue: [^base , ']'].
	^base , ', ' , (self imm: offset) , ']' , aString
! !

!Arm64Disassembler methodsFor: 'branches'!
pcRelative
	| offset |
	offset := self signed: ((self field: 5 width: 19) bitShift: 2) + (self field: 29 width: 2) bits: 21.
	^(self bit: 31) = 0
		ifTrue: [self op: 'adr' with: {self x: (self field: 0 width: 5). self targetAddress: address + offset}]
		ifFalse: [self op: 'adrp' with: {self x: (self field: 0 width: 5). self address: (address bitClear: 16rFFF) + (offset bitShift: 12)}]
!
branch
	^self op: (#('b' 'bl') at: (self bit: 31) + 1) with: {self target: (self field: 0 width: 26) bits: 26}
!
conditionalBranch
	^self op: 'b.' , (self condition: (self field: 0 width: 4)) with: {self target: (self field: 5 width: 19) bits: 19}
!
compareBranch
	^self op: (#('cbz' 'cbnz') at: (self bit: 24) + 1)
		with: {self r: (self field: 0 width: 5). self target: (self field: 5 width: 19) bits: 19}
!
testBranch
	^self op: (#('tbz' 'tbnz') at: (self bit: 24) + 1)
		with: {self r: (self field: 0 width: 5).
			self imm: (self bit: 31) * 32 + (self field: 19 width: 5).
			self target: (self field: 5 width: 14) bits: 14}
!
branchRegister
	| opc rn |
	opc := self field: 21 width: 2.
	rn := self field: 5 width: 5.
	opc = 3 ifTrue: [^nil].
	(opc = 2 and: [rn = 30]) ifTrue: [^'ret'].
	^self op: (#('br' 'blr' 'ret') at: opc + 1) with: {self x: rn}
!
breakpoint
	| imm |
	imm := self field: 5 width: 16.
	^self op: 'brk' with: {imm = 0 ifTrue: ['#0'] ifFalse: [self imm: imm]}
!
barrier
	| crm op2 |
	crm := self field: 8 width: 4.
	op2 := self field: 5 width: 3.
	op2 = 6 ifTrue: [^crm = 15 ifTrue: ['isb'] ifFalse: ['isb #' , crm printString]].
	(op2 = 1 and: [(crm bitAnd: 3) = 2])
		ifTrue: [^'dsb ' , (#('oshnxs' 'nshnxs' 'ishnxs' 'synxs') at: crm // 4 + 1)].
	(op2 = 4 and: [crm \\ 4 = 0 and: [crm ~= 8]]) ifTrue: [^#('ssbb' 'pssbb' nil 'dfb') at: crm // 4 + 1].
	(op2 = 4 or: [op2 = 5]) ifFalse: [^nil].
	^(op2 = 4 ifTrue: ['dsb '] ifFalse: ['dmb ']) ,
		((#(nil 'oshld' 'oshst' 'osh' nil 'nshld' 'nshst' 'nsh' nil 'ishld' 'ishst' 'ish' nil 'ld' 'st' 'sy') at: crm + 1)
			ifNil: ['#' , crm printString])
!
nop
	^'nop'
! !

!Arm64Disassembler methodsFor: 'floating point'!
fp1
	| name |
	name := #('fmov' 'fabs' 'fneg' 'fsqrt' nil nil nil nil 'frintn' 'frintp' 'frintm' 'frintz')
		at: (self field: 15 width: 6) + 1 ifAbsent: [nil].
	name ifNil: [^nil].
	^self op: name with: (#(0 5) collect: [:lsb | self d: (self field: lsb width: 5)])
!
fp2
	| name |
	name := #('fmul' 'fdiv' 'fadd' 'fsub') at: (self field: 12 width: 4) + 1 ifAbsent: [nil].
	name ifNil: [^nil].
	^self op: name with: (#(0 5 16) collect: [:lsb | self d: (self field: lsb width: 5)])
!
fpCompare
	(self bit: 4) = 1 ifTrue: [^nil].
	^self op: 'fcmp' with: {self d: (self field: 5 width: 5).
		(self bit: 3) = 1 ifTrue: ['#0.0'] ifFalse: [self d: (self field: 16 width: 5)]}
!
fpSelect
	^self op: 'fcsel' with: (#(0 5 16) collect: [:lsb | self d: (self field: lsb width: 5)]) ,
		{self condition: (self field: 12 width: 4)}
!
fpMoveImmediate
	"imm8 = a:b:cd:efgh is (-1)^a * (16 + efgh) / 16 * 2^n, n = cd + 1 (b = 0) or cd - 3 (b = 1); printed with 8 decimals"
	| imm n scaled |
	imm := self field: 13 width: 8.
	n := (imm bitShift: -4) \\ 4 + ((imm bitAt: 7) = 0 ifTrue: [1] ifFalse: [-3]).
	scaled := (16 + (imm \\ 16)) * (1 bitShift: n + 3) * 781250.
	^self op: 'fmov' with: {self d: (self field: 0 width: 5).
		'#' , ((imm bitAt: 8) = 1 ifTrue: ['-'] ifFalse: ['']) , (scaled // 100000000) printString , '.' ,
			((scaled \\ 100000000) printString padLeftTo: 8 with: $0)}
!
fpInteger
	| opcode rd rn |
	opcode := self field: 16 width: 5.
	rd := self field: 0 width: 5.
	rn := self field: 5 width: 5.
	(opcode = 2 or: [opcode = 3]) ifTrue: [^self op: (#('scvtf' 'ucvtf') at: opcode - 1) with: {self d: rd. self r: rn}].
	opcode = 24 ifTrue: [^self op: 'fcvtzs' with: {self r: rd. self d: rn}].
	wide ifFalse: [^nil].
	opcode = 6 ifTrue: [^self op: 'fmov' with: {self x: rd. self d: rn}].
	opcode = 7 ifTrue: [^self op: 'fmov' with: {self d: rd. self x: rn}].
	^nil
! !

!Arm64Disassembler methodsFor: 'private'!
bit: n
	^(word bitShift: n negated) bitAnd: 1
!
field: lsb width: n
	^(word bitShift: lsb negated) bitAnd: (1 bitShift: n) - 1
!
signed: value bits: n
	^value >= (1 bitShift: n - 1) ifTrue: [value - (1 bitShift: n)] ifFalse: [value]
!
width
	^wide ifTrue: [64] ifFalse: [32]
!
mask
	^(1 bitShift: self width) - 1
!
shift
	"the shift operands of a shifted register form (none for lsl #0), nil if the amount is out of range"
	| amount type |
	amount := self field: 10 width: 6.
	amount >= self width ifTrue: [^nil].
	type := self field: 22 width: 2.
	(type = 0 and: [amount = 0]) ifTrue: [^#()].
	^{(#('lsl' 'lsr' 'asr' 'ror') at: type + 1) , ' #' , amount printString}
!
bitmask: nImmrImms
	"the value of a logical immediate, nil if the encoding is reserved"
	| length size levels s r element value |
	length := ((nImmrImms bitShift: -6) bitAnd: 2r1000000) + (nImmrImms bitAnd: 63) bitXor: 63.
	length := length highBit - 1.
	length < 1 ifTrue: [^nil].
	size := 1 bitShift: length.
	levels := size - 1.
	s := nImmrImms bitAnd: levels.
	r := (nImmrImms bitShift: -6) bitAnd: levels.
	s = levels ifTrue: [^nil].
	element := (1 bitShift: s + 1) - 1.
	element := ((element bitShift: r negated) bitOr: (element bitShift: size - r)) bitAnd: (1 bitShift: size) - 1.
	value := 0.
	0 to: self width - 1 by: size do: [:i | value := value bitOr: (element bitShift: i)].
	^value
!
isMove: value shift: shift
	"whether movz with shift moves value (LLVM prefers lsl #0 for 0)"
	(value = 0 and: [shift ~= 0]) ifTrue: [^false].
	^(value bitClear: (16rFFFF bitShift: shift)) = 0
!
isAnyMove: value
	0 to: self width - 16 by: 16 do: [:shift | (self isMove: value shift: shift) ifTrue: [^true]].
	^false
!
isMoveWide: value
	"whether movz or movn moves value"
	^(self isAnyMove: value) or: [self isAnyMove: (value bitInvert bitAnd: self mask)]
!
dataWord
	^'.word 0x' , (self hex8: word)
! !

!Arm64Disassembler methodsFor: 'printing'!
op: mnemonic with: operands
	^mnemonic , ' ' , (', ' join: operands)
!
hex: anInteger
	anInteger < 0 ifTrue: [^'-' , (self hex: anInteger negated)].
	^'0x' , (anInteger printString: 16) asLowercase
!
hex8: anInteger
	^((anInteger printString: 16) asLowercase padLeftTo: 8 with: $0)
!
imm: anInteger
	^'#' , (self hex: anInteger)
!
address: anInteger
	^self hex: (anInteger bitAnd: 16rFFFFFFFFFFFFFFFF)
!
target: offset bits: n
	"the address of a branch: offset words (an n-bit field) from me"
	^self targetAddress: address + ((self signed: offset bits: n) * 4)
!
targetAddress: anInteger
	target := anInteger bitAnd: 16rFFFFFFFFFFFFFFFF.
	^self hex: target
!
condition: cond
	^#('eq' 'ne' 'hs' 'lo' 'mi' 'pl' 'vs' 'vc' 'hi' 'ls' 'ge' 'lt' 'gt' 'le' 'al' 'nv') at: cond + 1
!
r: n
	"general register n at the instruction's width, 31 the zero register"
	^wide ifTrue: [self x: n] ifFalse: [self w: n]
!
rsp: n
	"general register n at the instruction's width, 31 the stack pointer"
	n = 31 ifTrue: [^wide ifTrue: ['sp'] ifFalse: ['wsp']].
	^self r: n
!
x: n
	^n = 31 ifTrue: ['xzr'] ifFalse: ['x' , n printString]
!
w: n
	^n = 31 ifTrue: ['wzr'] ifFalse: ['w' , n printString]
!
xsp: n
	^n = 31 ifTrue: ['sp'] ifFalse: ['x' , n printString]
!
d: n
	^'d' , n printString
! !
