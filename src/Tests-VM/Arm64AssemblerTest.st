TestCase subclass: #Arm64AssemblerTest
	instanceVariableNames: 'sim asm buffer'
	classVariableNames: ''
	package: 'Tests-VM'!

Arm64AssemblerTest comment: 'Arm64Assembler, simulated: its encodings against the system assembler''s (Arm64Reference), its encoders, labels, errors and patching.'!

!Arm64AssemblerTest methodsFor: 'running'!
setUp
	sim := VMSimulation modules: {Arm64Assembler}.
	asm := sim module: Arm64Assembler.
	buffer := sim memory allocate: 16r10000.
	asm beginAt: buffer limit: buffer + 16r10000
! !

!Arm64AssemblerTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!Arm64AssemblerTest methodsFor: 'helpers'!
casesRun
	"What Arm64AssemblerCases prints, simulated."
	| sim2 |
	sim2 := VMSimulation modules: {Arm64AssemblerCases. Arm64Assembler}.
	"above 256 MB, so that the cases' backward branches stay at positive addresses"
	sim2 memory allocate: 16r10000000.
	self assert: (sim2 runMain: Arm64AssemblerCases arguments: #('cases')) equals: 0.
	^sim2 stdoutContents
!
assertCasesPrinted: aString
	"Arm64AssemblerCases printed each case's source and the system assembler's words for it."
	| lines wrong |
	lines := aString lines.
	self assert: lines size equals: Arm64Reference cases size.
	wrong := OrderedCollection new.
	lines with: Arm64Reference cases do: [:line :ref |
		| expected |
		expected := String new: 80 streamContents: [:s |
			s nextPutAll: (ref at: 1); nextPut: $:.
			(ref at: 3) do: [:w | s space; nextPutAll: ((w printStringBase: 16) asLowercase padLeftTo: 8 with: $0)]].
		line = expected ifFalse: [wrong add: line , '   expected   ' , expected]].
	self assert: wrong isEmpty description: [wrong inject: '' into: [:a :b | a , b , String lf]]
!
words
	^(0 to: asm codeSize // 4 - 1) collect: [:i | sim memory uint32At: buffer + (4 * i)]
!
assemble: aBlock
	"The words aBlock emits at the start of the buffer, or the error code."
	| error |
	asm beginAt: buffer limit: buffer + 16r10000.
	aBlock value.
	error := asm finish.
	error = 0 ifFalse: [^error].
	^self words asArray
!
reg: aString
	^Arm64Module classPool at: aString asSymbol
!
decodeBitMasks: enc width: width
	"The value of a logical immediate N:immr:imms (DecodeBitMasks of the ARM ARM)."
	| n immr imms len size ones elem v |
	n := enc bitShift: -12.
	immr := (enc bitShift: -6) bitAnd: 63.
	imms := enc bitAnd: 63.
	len := ((n bitShift: 6) bitOr: (imms bitXor: 63)) highBit - 1.
	len < 1 ifTrue: [^nil].
	size := 1 bitShift: len.
	ones := (imms bitAnd: size - 1) + 1.
	(ones = size or: [immr >= size]) ifTrue: [^nil].
	elem := (1 bitShift: ones) - 1.
	elem := ((elem bitShift: immr negated) bitOr: (elem bitShift: size - immr)) bitAnd: (1 bitShift: size) - 1.
	v := 0.
	0 to: width // size - 1 do: [:i | v := v bitOr: (elem bitShift: i * size)].
	^v
! !

!Arm64AssemblerTest methodsFor: 'tests'!
testReferenceEncodingsSimulated
	self assertCasesPrinted: self casesRun
!
testReferenceEncodingsInC
	| dir build run |
	dir := self scratchDirectory.
	(VMTranslator modules: {Arm64AssemblerCases. Arm64Assembler} header: 'cases') writeTo: dir.
	build := OSProcess run: 'cc -std=gnu11 -O1 -Wall -Wextra -Wno-unused-parameter -Wno-unused-label -Werror -o program *.c 2>&1' in: dir.
	self assert: build succeeded description: [build output].
	run := OSProcess run: dir , '/program' in: dir.
	self assert: run exitCode equals: 0.
	self assertCasesPrinted: run output
!
testLogicalImmediates
	#(64 32) do: [:width |
		| pairs |
		pairs := width = 64 ifTrue: [Arm64Reference logicalImmediates64] ifFalse: [Arm64Reference logicalImmediates32].
		1 to: pairs size by: 2 do: [:i |
			self assert: (asm logicalImmediate: (pairs at: i) width: width) equals: (pairs at: i + 1)].
		(width = 64 ifTrue: [Arm64Reference unencodableLogical64] ifFalse: [Arm64Reference unencodableLogical32]) do: [:v |
			self assert: (asm logicalImmediate: v width: width) equals: -1]]
!
testLogicalImmediatesRoundTrip
	"Every encoding decodes to a value that encodes back to it."
	| count |
	count := 0.
	#(64 32) do: [:width |
		0 to: (width = 64 ifTrue: [16r1FFF] ifFalse: [16rFFF]) do: [:enc |
			| v |
			v := self decodeBitMasks: enc width: width.
			v notNil ifTrue: [
				count := count + 1.
				self assert: (asm logicalImmediate: v width: width) equals: enc]]].
	self assert: count equals: 5334 + 1302.
	self assert: (asm logicalImmediate: 0 width: 64) equals: -1.
	self assert: (asm logicalImmediate: 16rFFFFFFFFFFFFFFFF width: 64) equals: -1.
	self assert: (asm logicalImmediate: 16rFFFFFFFF width: 32) equals: -1.
	self assert: (asm logicalImmediate: 16rFFFFFFFF width: 64) equals: 16r101F
!
testFmovImmediates
	"Each of the 256 immediates: ±(16 + f)/16 * 2^e, e in -3..4."
	0 to: 255 do: [:imm8 |
		| sign exp frac d |
		sign := (imm8 bitAnd: 128) = 0 ifTrue: [1] ifFalse: [-1].
		exp := ((imm8 bitShift: -4) bitAnd: 7) bitXor: 4.
		exp := exp - 3.
		frac := imm8 bitAnd: 15.
		d := (16 + frac) / 16 * (2 raisedTo: exp) * sign.
		self assert: (asm fmovImmediate: d asFloat) equals: imm8].
	#(0.0 0.1 32.0 0.0625 1.03125 -0.0) do: [:d | self assert: (asm fmovImmediate: d) equals: -1]
!
testUnencodable
	"The first error sticks."
	| x0 x1 d0 |
	x0 := self reg: 'X0'.
	x1 := self reg: 'X1'.
	d0 := self reg: 'D0'.
	self assert: (self assemble: [asm add: x0 with: x1 imm: 4097]) equals: 2.
	self assert: (self assemble: [asm sub: x0 with: x1 imm: 16r1000000]) equals: 2.
	self assert: (self assemble: [asm and: x0 with: x1 imm: 0]) equals: 2.
	self assert: (self assemble: [asm orr: x0 with: x1 imm: 5]) equals: 2.
	self assert: (self assemble: [asm ldr: x0 base: x1 offset: 32768]) equals: 2.
	self assert: (self assemble: [asm ldr: x0 base: x1 offset: 257]) equals: 2.
	self assert: (self assemble: [asm ldr: x0 base: x1 preIndex: 256]) equals: 2.
	self assert: (self assemble: [asm ldp: x0 with: x1 base: x1 offset: 4]) equals: 2.
	self assert: (self assemble: [asm ldp: x0 with: x1 base: x1 offset: 512]) equals: 2.
	self assert: (self assemble: [asm fmov: d0 imm: 0.1]) equals: 2.
	self assert: (self assemble: [asm movz: x0 imm: 16r10000 shift: 0]) equals: 2.
	self assert: (self assemble: [asm movk: (self reg: 'W0') imm: 1 shift: 32]) equals: 2.
	self assert: (self assemble: [asm ubfx: x0 with: x1 lsb: 60 width: 5]) equals: 2.
	self assert: (self assemble: [asm lsl: x0 with: x1 imm: 64]) equals: 2.
	self assert: (self assemble: [asm add: x0 with: x1 with: x1 shift: (Arm64Module classPool at: #SHIFT_ROR) amount: 1]) equals: 5.
	self assert: (self assemble: [asm ldr: x0 base: x1 index: x1 extend: (Arm64Module classPool at: #EXT_LSL) shift: 2]) equals: 5.
	self assert: (self assemble: [asm b: (asm labelAt: asm pc + 134217728)]) equals: 3.
	self assert: (self assemble: [asm cbz: x0 to: (asm labelAt: asm pc + 16r100000)]) equals: 3.
	self assert: (self assemble: [asm tbz: x0 bit: 1 to: (asm labelAt: asm pc - 32772)]) equals: 3.
	self assert: (self assemble: [asm adr: x0 label: (asm labelAt: asm pc + 16r100000)]) equals: 3.
	self assert: (self assemble: [asm add: x0 with: x1 imm: 4097. asm nop. asm b: (asm labelAt: asm pc + 16r10000000)]) equals: 2
!
testBufferFull
	| x0 |
	x0 := self reg: 'X0'.
	asm beginAt: buffer limit: buffer + 8.
	asm nop; nop.
	self assert: asm failed not.
	asm mov: x0 imm: 16r123456789.
	self assert: asm codeSize equals: 8.
	self assert: asm finish equals: 1
!
testLabels
	"Forward branches are patched when their label is bound; each kind matches its backward encoding."
	| x0 w3 kinds |
	x0 := self reg: 'X0'.
	w3 := self reg: 'W3'.
	kinds := {
		[:l | asm b: l]. [:l | asm bl: l]. [:l | asm b: l if: 11]. [:l | asm cbz: x0 to: l]. [:l | asm cbnz: w3 to: l].
		[:l | asm tbz: x0 bit: 37 to: l]. [:l | asm tbnz: w3 bit: 2 to: l]. [:l | asm ldr: x0 label: l].
		[:l | asm adr: x0 label: l]. [:l | asm adrp: x0 label: l]}.
	kinds do: [:emit |
		| forward known |
		forward := self assemble: [
			| l |
			l := asm newLabel.
			emit value: l.
			asm nop.
			emit value: l.
			100 timesRepeat: [asm nop].
			asm bind: l.
			asm nop].
		known := self assemble: [
			emit value: (asm labelAt: buffer + 412).
			asm nop.
			emit value: (asm labelAt: buffer + 412)].
		self assert: (forward first: 3) equals: known.
		self assert: (asm branchTargetAt: buffer + 8) equals: (emit == kinds last ifTrue: [buffer] ifFalse: [buffer + 412])].
	self assert: (self assemble: [asm b: asm newLabel]) equals: 4.
	self assert: (self assemble: [| l | l := asm newLabel. asm bind: l. asm b: l. asm b: l if: 0]) equals: #(16r14000000 16r54FFFFE0)
!
testPatching
	| x0 site |
	x0 := self reg: 'X0'.
	self assemble: [
		asm b: (asm labelAt: buffer + 64).
		asm bl: (asm labelAt: buffer).
		asm b: (asm labelAt: buffer + 64) if: 1.
		asm cbz: x0 to: (asm labelAt: buffer + 64).
		asm tbnz: x0 bit: 63 to: (asm labelAt: buffer + 64).
		asm ldr: x0 label: (asm labelAt: buffer + 64).
		asm adr: x0 label: (asm labelAt: buffer + 63).
		asm adrp: x0 label: (asm labelAt: buffer + 16r5000).
		asm nop].
	#(64 0 64 64 64 64 63 16r5000) doWithIndex: [:target :i |
		site := buffer + (4 * (i - 1)).
		self assert: (asm branchTargetAt: site) equals: buffer + target.
		self assert: (asm patchBranchAt: site to: site - 4096).
		self assert: (asm branchTargetAt: site) equals: (i = 8 ifTrue: [buffer - 4096] ifFalse: [site - 4096])].
	self assert: (asm branchTargetAt: buffer + 32) equals: 0.
	self deny: (asm patchBranchAt: buffer + 16 to: buffer + 16 + 32768).
	self deny: (asm patchBranchAt: buffer + 32 to: buffer).
	self assemble: [asm nop. asm mov: x0 imm64: 16r1122334455667788. asm ret].
	self assert: (asm mov64At: buffer + 4) equals: 16r1122334455667788.
	asm patchMov64At: buffer + 4 value: 16rFEDCBA9876543210.
	self assert: (asm mov64At: buffer + 4) equals: 16rFEDCBA9876543210.
	self assert: (self words first: 6) equals: (self assemble: [asm nop. asm mov: x0 imm64: 16rFEDCBA9876543210. asm ret])
!
testNotes
	| x0 notes |
	x0 := self reg: 'X0'.
	self assemble: [asm comment: 'off'. asm bytecode: 1. asm nop].
	self assert: asm noteCount equals: 0.
	asm recordNotes: true.
	self assemble: [
		asm bytecode: 0.
		asm comment: 'tag check'.
		asm tbz: x0 bit: 0 to: (asm labelAt: buffer + 64).
		asm comment: 'spill stack slot %d' with: 2.
		asm str: x0 base: x0 offset: 16.
		asm bytecode: 5.
		asm ret].
	notes := (0 to: asm noteCount - 1) collect: [:i |
		| text |
		text := asm noteTextAt: i.
		{asm noteOffsetAt: i. text isNull ifTrue: [nil] ifFalse: [sim memory stringAt: text]. asm noteValueAt: i}].
	self assert: notes asArray equals: #((0 nil 0) (0 'tag check' 0) (4 'spill stack slot %d' 2) (8 nil 5)).
	asm recordNotes: false.
	self assemble: [asm comment: 'off'. asm nop].
	self assert: asm noteCount equals: 0
!
testDisassemblyRoundTrip
	"Assemble each case, disassemble the words: the system assembler's text."
	| disassembler wrong |
	disassembler := Arm64Disassembler new.
	wrong := OrderedCollection new.
	self casesRun lines with: Arm64Reference cases do: [:line :ref |
		| words |
		words := ((line copyAfterLast: $:) substrings: ' ') collect: [:hex | Integer readFrom: hex asUppercase base: 16].
		words doWithIndex: [:w :i |
			| text |
			text := disassembler textFor: w at: (ref at: 2) + (4 * (i - 1)).
			text = ((ref at: 4) at: i) ifFalse: [wrong add: (ref at: 1) , ': ' , text]]].
	self assert: wrong isEmpty description: [wrong inject: '' into: [:a :b | a , b , String lf]]
!
testAnnotatedListing
	"Notes recorded while assembling, as Arm64CodeAnnotations, in the disassembler's listing."
	| x0 x1 notes loop exit listing |
	x0 := self reg: 'X0'.
	x1 := self reg: 'X1'.
	asm recordNotes: true.
	self assemble: [
		loop := asm newLabel.
		exit := asm newLabel.
		asm bytecode: 0.
		asm bind: loop.
		asm comment: 'SmallInteger tag check'.
		asm tbz: x0 bit: 0 to: exit.
		asm bytecode: 3.
		asm comment: 'spill stack slot %d' with: 2.
		asm str: x0 base: x1 offset: 16.
		asm b: loop.
		asm bind: exit.
		asm comment: 'call runtime: send miss'.
		asm bl: (asm labelAt: buffer + 16r4000).
		asm ret].
	notes := Arm64CodeAnnotations new.
	0 to: asm noteCount - 1 do: [:i |
		| text |
		text := asm noteTextAt: i.
		text isNull
			ifTrue: [notes addBytecode: (asm noteValueAt: i) text: 'bytecode' source: nil at: (asm noteOffsetAt: i)]
			ifFalse: [notes addComment: ((sim memory stringAt: text) copyReplaceAll: '%d' with: (asm noteValueAt: i) printString) at: (asm noteOffsetAt: i)]].
	notes addSymbol: 'send_miss' at: buffer + 16r4000.
	listing := Arm64Disassembler new listingOfWords: self words at: buffer annotations: notes.
	self assert: listing equals: ('pc 0: bytecode
L1:
  +0000  36000060  tbz w0, #0x0, L2                 ; SmallInteger tag check

pc 3: bytecode
  +0004  f9000820  str x0, [x1, #0x10]              ; spill stack slot 2
  +0008  17fffffe  b L1
L2:
  +000c  94000ffd  bl 0x{1} <send_miss>          ; call runtime: send miss
  +0010  d65f03c0  ret
' format: {((buffer + 16r4000) printStringBase: 16) asLowercase})
! !
