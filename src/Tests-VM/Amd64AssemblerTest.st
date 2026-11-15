TestCase subclass: #Amd64AssemblerTest
	instanceVariableNames: 'sim asm buffer'
	classVariableNames: ''
	package: 'Tests-VM'!

Amd64AssemblerTest comment: 'Amd64Assembler, simulated: its x86 encodings and its lowerings of arm64 instructions against GNU as''s bytes (Amd64AssemblerCases, Amd64Reference), simulated and compiled with cc, read back by Amd64Disassembler; labels, patching, words in memory (asmRegs, the JitState), errors and notes.'!

!Amd64AssemblerTest methodsFor: 'running'!
setUp
	sim := VMSimulation modules: {Amd64Assembler}.
	asm := sim module: Amd64Assembler.
	buffer := sim memory allocate: 16r10000.
	asm beginAt: buffer limit: buffer + 16r10000
!
timeLimitMilliseconds
	^120000
! !

!Amd64AssemblerTest methodsFor: 'helpers'!
casesRun
	"What Amd64AssemblerCases prints, simulated."
	| sim2 |
	sim2 := VMSimulation modules: {Amd64AssemblerCases. Amd64Assembler}.
	"above 256 MB, so that the cases' backward branches stay at positive addresses"
	sim2 memory allocate: 16r10000000.
	self assert: (sim2 runMain: Amd64AssemblerCases arguments: #('cases')) equals: 0.
	^sim2 stdoutContents
!
assertCasesPrinted: aString
	"Amd64AssemblerCases printed each case's source and the bytes GNU as assembles it into."
	| lines wrong |
	lines := aString lines.
	self assert: lines size equals: Amd64Reference cases size.
	wrong := OrderedCollection new.
	lines with: Amd64Reference cases do: [:line :ref | | expected |
		expected := String new: 80 streamContents: [:s |
			s nextPutAll: (ref at: 1); nextPut: $:.
			1 to: (ref at: 3) size by: 2 do: [:i | | hex |
				hex := (ref at: 3) at: i.
				1 to: hex size by: 2 do: [:k | s space; nextPutAll: (hex copyFrom: k to: k + 1)]]].
		line = expected ifFalse: [wrong add: line , '   expected   ' , expected]].
	self assert: wrong isEmpty description: [wrong size printString , ' wrong:' , String lf , (wrong inject: '' into: [:a :b | a , b , String lf])]
!
bytes
	"The code emitted since beginAt:."
	| bytes |
	bytes := ByteArray new: asm codeSize.
	1 to: bytes size do: [:i | bytes at: i put: (sim memory uint8At: buffer + i - 1)].
	^bytes
!
assemble: aBlock
	"The bytes aBlock emits at the start of the buffer, or the error code."
	| error |
	asm beginAt: buffer limit: buffer + 16r10000.
	aBlock value.
	error := asm finish.
	error = 0 ifFalse: [^error].
	^self bytes
!
texts
	"Amd64Disassembler's texts of the code emitted, one instruction after the other."
	^(Amd64Disassembler new instructionsOf: self bytes at: buffer) collect: [:each | each at: 3]
!
hex: anInteger
	^'0x' , (anInteger printString: 16) asLowercase
!
effectsOf: aBlock
	"{length. kind. register. second register. offset} of each instruction aBlock emits, as effectAt: tells (the kind's name without ASM_EF_), up to one it does not know."
	| end p e list off |
	asm setState: buffer + 16r8000.
	self assemble: aBlock.
	end := asm pc.
	p := buffer.
	list := OrderedCollection new.
	[p < end] whileTrue: [
		e := asm effectAt: p.
		off := (e >> 32) bitAnd: 16rFFFFFFFF.
		off >= 16r80000000 ifTrue: [off := off - 16r100000000].
		list add: {e bitAnd: 255. #('NONE' 'LOAD' 'STORE' 'MOVE' 'WRITE' 'FORGET') at: ((e >> 8) bitAnd: 255) + 1. (e >> 16) bitAnd: 255. (e >> 24) bitAnd: 255. off}.
		p := (e bitAnd: 255) = 0 ifTrue: [end] ifFalse: [p + (e bitAnd: 255)]].
	^list asArray
!
reg: aString
	^Arm64Module classPool at: aString asSymbol
!
cond: aString
	"COND_EQ for 'EQ' ..."
	^Arm64Module classPool at: ('COND_' , aString) asSymbol
!
fromHex: aString
	| bytes |
	bytes := ByteArray new: aString size // 2.
	1 to: bytes size do: [:i | bytes at: i put: (Integer readFrom: (aString copyFrom: 2 * i - 1 to: 2 * i) asUppercase base: 16)].
	^bytes
! !

!Amd64AssemblerTest methodsFor: 'tests'!
testReferenceEncodingsSimulated
	self assertCasesPrinted: self casesRun
!
testReferenceEncodingsInC
	| dir build run |
	dir := self scratchDirectory.
	(VMTranslator modules: {Amd64AssemblerCases. Amd64Assembler} header: 'cases') writeTo: dir.
	build := OSProcess run: 'cc -std=gnu11 -O1 -Wall -Wextra -Wno-unused-parameter -Wno-unused-label -Werror -o program *.c 2>&1' in: dir.
	self assert: build succeeded description: [build output].
	run := OSProcess run: dir , '/program' in: dir.
	self assert: run exitCode equals: 0.
	self assertCasesPrinted: run output
!
testDisassemblyRoundTrip
	"The bytes of each case, decoded one instruction after the other: GNU objdump's texts."
	| disassembler wrong |
	disassembler := Amd64Disassembler new.
	wrong := OrderedCollection new.
	self casesRun lines with: Amd64Reference cases do: [:line :ref | | bytes texts expected |
		bytes := self fromHex: ((line copyAfterLast: $:) reject: [:c | c = $ ]).
		texts := (disassembler instructionsOf: bytes at: (ref at: 2)) collect: [:each | each at: 3].
		expected := (2 to: (ref at: 3) size by: 2) collect: [:i | (ref at: 3) at: i].
		texts asArray = expected asArray ifFalse: [wrong add: (ref at: 1) , ': ' , (' | ' join: texts)]].
	self assert: wrong isEmpty description: [wrong inject: '' into: [:a :b | a , b , String lf]]
!
testForwardBranches
	"Branches to a label not bound yet are rel32 (jmp, jcc, call, and the pc-relative mov and lea), their displacement patched when it is bound; backward ones in reach are rel8."
	| x0 l t |
	x0 := self reg: 'X0'.
	self assemble: [
		l := asm newLabel.
		asm b: l.
		asm b: l if: (self cond: 'EQ').
		asm bl: l.
		asm ldr: x0 label: l.
		asm adr: x0 label: l.
		asm cbz: x0 to: l.
		self assert: (asm hasBranchesTo: l).
		asm nop.
		asm bind: l.
		self deny: (asm hasBranchesTo: l).
		asm b: l.
		asm b: l if: (self cond: 'NE').
		asm ret].
	self assert: (asm addressOf: l) equals: buffer + 40.
	t := self hex: buffer + 40.
	self assert: self texts asArray equals: {
		'jmp    ' , t. 'je     ' , t. 'call   ' , t.
		'mov    rdi,QWORD PTR [rip+0x11]        # ' , t. 'lea    rdi,[rip+0xa]        # ' , t.
		'test   rdi,rdi'. 'je     ' , t. 'nop'. 'jmp    ' , t. 'jne    ' , t. 'ret'}.
	#(1 7 12 19 26 35) do: [:site | self assert: (asm branchTargetAt: buffer + site) equals: buffer + 40].
	self assert: (self bytes copyFrom: 41 to: 44) equals: #[16rEB 16rFE 16r75 16rFC]
!
testBackwardBranches
	"rel8 to a label up to 128 bytes back, rel32 beyond."
	| l |
	self assert: (self assemble: [
		l := asm newLabel.
		asm bind: l.
		126 timesRepeat: [asm nop].
		asm b: l.
		asm b: l]) asArray equals: (Array new: 126 withAll: 16r90) , #(16rEB 16r80 16rE9 16r7B 16rFF 16rFF 16rFF).
	self assert: (self assemble: [
		l := asm newLabel.
		asm bind: l.
		125 timesRepeat: [asm nop].
		asm b: l if: (self cond: 'EQ').
		asm b: l if: (self cond: 'EQ')]) asArray equals: (Array new: 125 withAll: 16r90) , #(16r74 16r81 16r0F 16r84 16r7B 16rFF 16rFF 16rFF).
	self assert: (self assemble: [asm b: asm newLabel]) equals: 4
!
testPatching
	| x0 sites |
	x0 := self reg: 'X0'.
	self assemble: [
		asm b: (asm labelAt: buffer + 4096).
		asm bl: (asm labelAt: buffer).
		asm b: (asm labelAt: buffer + 4096) if: (self cond: 'NE').
		asm ldr: x0 label: (asm labelAt: buffer + 4096).
		asm adr: x0 label: (asm labelAt: buffer + 4096).
		asm nop].
	sites := #(1 6 12 19 26).
	sites with: #(4096 0 4096 4096 4096) do: [:site :target |
		self assert: (asm branchTargetAt: buffer + site) equals: buffer + target.
		self assert: (asm patchBranchAt: buffer + site to: buffer + site - 4096).
		self assert: (asm branchTargetAt: buffer + site) equals: buffer + site - 4096.
		self assert: (asm patchBranchAt: buffer + site to: buffer + site + 16r7FFFFFFF + 4).
		self assert: (asm branchTargetAt: buffer + site) equals: buffer + site + 16r7FFFFFFF + 4.
		self assert: (asm patchBranchAt: buffer + site to: buffer + site - 4096)].
	self assert: asm finish equals: 0.
	self assert: (Amd64Disassembler new textFor: self bytes at: buffer) equals: 'jmp    ' , (self hex: buffer - 4095).
	self deny: (asm patchBranchAt: buffer + 1 to: buffer + 16r100000000).
	self assert: asm finish equals: 3.
	self assemble: [asm nop. asm mov: x0 imm64: 16r1122334455667788. asm ret].
	self assert: (asm mov64At: buffer + 1) equals: 16r1122334455667788.
	asm patchMov64At: buffer + 1 value: 16rFEDCBA9876543210.
	self assert: (asm mov64At: buffer + 1) equals: 16rFEDCBA9876543210.
	self assert: self bytes equals: (self assemble: [asm nop. asm mov: x0 imm64: 16rFEDCBA9876543210. asm ret]).
	self assert: self texts asArray equals: #('nop' 'movabs rdi,0xfedcba9876543210' 'ret')
!
testWords
	"x6 has no x86 register: its word in asmRegs, read and written pc-relative; x22-x25 the JitState and its words."
	| x0 x1 x6 x7 x22 x24 pieces regs |
	x0 := self reg: 'X0'.
	x1 := self reg: 'X1'.
	x6 := self reg: 'X6'.
	x7 := self reg: 'X7'.
	x22 := self reg: 'X22'.
	x24 := self reg: 'X24'.
	asm setState: buffer + 16r8000.
	regs := asm regsAddress.
	self assemble: [
		asm mov: x6 with: x0.
		asm mov: x1 with: x6.
		asm add: x7 with: x7 imm: 8.
		asm mov: x6 imm: 5.
		asm cmp: x6 imm: 1.
		asm ldr: x0 base: x22 offset: 16.
		asm mov: x0 with: x24].
	pieces := Amd64Disassembler new scan: self bytes at: buffer data: #().
	self assert: (pieces collect: [:each | (each at: 3) copyUpTo: $[]) asArray
		equals: #('mov    QWORD PTR ' 'mov    rsi,QWORD PTR ' 'mov    r11,QWORD PTR ' 'lea    r11,' 'mov    QWORD PTR ' 'mov    QWORD PTR ' 'cmp    QWORD PTR ' 'mov    rdi,QWORD PTR ' 'mov    rdi,QWORD PTR ').
	self assert: (pieces collect: [:each | each at: 4]) asArray
		equals: {regs + 48. regs + 48. regs + 56. nil. regs + 56. regs + 48. regs + 48. buffer + 16r8010. buffer + 16r8008}.
	self assert: ((pieces at: 4) at: 3) equals: 'lea    r11,[r11+0x8]'.
	self assert: (((pieces at: 6) at: 3) copyUpTo: $#) trimBoth equals: 'mov    QWORD PTR [rip+' , (self hex: (regs + 48 - (buffer + 43) bitAnd: 16rFFFFFFFFFFFFFFFF)) , '],0x5'
!
testEffects
	"What each instruction does to what registers hold (effectAt:, OptCodegen>>catchUp's), with arm64's registers (255: none, r11): loads and stores of x20's slots, moves, writes; calls, pushes, jumps and other stores into the frame forget all; stores into objects nothing; a short jump forward over code that does something is one FORGET over it."
	| x0 x1 x9 x20 d0 d1 l |
	x0 := self reg: 'X0'.
	x1 := self reg: 'X1'.
	x9 := self reg: 'X9'.
	x20 := self reg: 'X20'.
	d0 := self reg: 'D0'.
	d1 := self reg: 'D1'.
	self assert: (self effectsOf: [asm ldr: x0 base: x20 offset: 16]) equals: #((4 'LOAD' 0 255 16)).
	self assert: (self effectsOf: [asm str: x9 base: x20 offset: -8]) equals: #((4 'STORE' 9 255 -8)).
	self assert: (self effectsOf: [asm ldp: x0 with: x1 base: x20 offset: 16]) equals: #((4 'LOAD' 0 255 16) (4 'LOAD' 1 255 24)).
	self assert: (self effectsOf: [asm mov: x1 with: x0]) equals: #((3 'MOVE' 1 0 0)).
	self assert: (self effectsOf: [asm str: (self reg: 'X23') base: x20 offset: 32]) equals: #((7 'WRITE' 255 255 0) (4 'STORE' 255 255 32)).
	self assert: (self effectsOf: [asm add: x0 with: x20 imm: 8. asm ldr: (self reg: 'W1') base: x20 offset: 8. asm add: x20 with: x20 imm: 64]) equals: #((4 'WRITE' 0 255 0) (3 'WRITE' 1 255 0) (4 'WRITE' 20 255 0)).
	self assert: (self effectsOf: [asm cmp: x0 with: x1. asm csel: x0 with: x1 with: x9 cond: (self cond: 'LT')]) equals: #((3 'NONE' 255 255 0) (3 'MOVE' 0 9 0) (4 'WRITE' 0 255 0)).
	self assert: (self effectsOf: [asm fmov: x0 with: d0. asm fmov: d1 with: x1. asm fcvtzs: x1 with: d1. asm ldr: d0 base: x20 offset: 16]) equals: #((5 'WRITE' 0 255 0) (5 'NONE' 255 255 0) (5 'WRITE' 1 255 0) (5 'NONE' 255 255 0)).
	self assert: (self effectsOf: [asm str: x0 base: x1 offset: 8]) equals: #((4 'NONE' 255 255 0)).
	#('W0' 'XZR' 'D0') do: [:r |
		self assert: ((self effectsOf: [asm str: (self reg: r) base: x20 offset: 8]) collect: [:each | each at: 2]) equals: #('FORGET')].
	self assert: (self effectsOf: [asm str: x0 base: x20 index: x1]) equals: #((4 'FORGET' 255 255 0)).
	self assert: (self effectsOf: [asm bl: (asm labelAt: buffer + 4096). asm blr: x9. asm ret]) equals: #((5 'FORGET' 255 255 0) (2 'FORGET' 255 255 0) (1 'FORGET' 255 255 0)).
	self assert: ((self effectsOf: [asm smulh: x0 with: x0 with: x1]) first: 2) equals: #((1 'FORGET' 255 255 0) (1 'FORGET' 255 255 0)).
	self assert: (self effectsOf: [l := asm newLabel. asm fcmp: d0 with: d1. asm b: l if: (self cond: 'EQ'). asm bind: l]) equals: #((4 'NONE' 255 255 0) (2 'NONE' 255 255 0) (6 'NONE' 255 255 0)).
	self assert: (self effectsOf: [asm picCaseX64: (self reg: 'X16') classAt: buffer + 8192 target: (asm labelAt: buffer + 4096)]) equals: #((7 'NONE' 255 255 0) (7 'FORGET' 255 255 0)).
	"xchg rax, rcx: not mine"
	self assert: (self effectsOf: [asm emitBytes: 16r9148 count: 2]) equals: #((0 'NONE' 0 0 0))
!
testOneBitTests
	"tst of one bit beyond a sign-extended 32-bit immediate is bt, the bit in the carry: EQ and NE read it, other conditions cannot."
	| x16 l t |
	x16 := self reg: 'X16'.
	self assemble: [
		l := asm newLabel.
		asm bind: l.
		asm tst: x16 imm: 1 << 59.
		asm b: l if: (self cond: 'NE').
		asm tst: x16 imm: 1 << 31.
		asm b: l if: (self cond: 'EQ').
		asm tst: x16 imm: 16r7FFFFFFF.
		asm b: l if: (self cond: 'EQ')].
	t := self hex: buffer.
	self assert: self texts asArray equals: {'bt     r10,0x3b'. 'jb     ' , t. 'bt     r10,0x1f'. 'jae    ' , t. 'test   r10d,0x7fffffff'. 'je     ' , t}.
	self assert: (self assemble: [asm tst: x16 imm: 1 << 63. asm b: (asm labelAt: buffer) if: (self cond: 'MI')]) equals: 6
!
testStoresOfAWord
	"nil, true or false stored into one slot after the other: r11 loaded once (again after a label, or once something else was emitted)."
	| x20 x23 x24 stores |
	x20 := self reg: 'X20'.
	x23 := self reg: 'X23'.
	x24 := self reg: 'X24'.
	asm setState: buffer + 16r8000.
	self assemble: [
		asm str: x23 base: x20 offset: 8.
		asm str: x23 base: x20 offset: 16.
		asm str: x24 base: x20 offset: 24.
		asm bind: asm newLabel.
		asm str: x24 base: x20 offset: 32.
		asm nop.
		asm str: x24 base: x20 offset: 40].
	stores := self texts collect: [:each | (each beginsWith: 'mov    r11') ifTrue: ['load'] ifFalse: [each]].
	self assert: stores asArray equals: #('load' 'mov    QWORD PTR [rbx+0x8],r11' 'mov    QWORD PTR [rbx+0x10],r11' 'load' 'mov    QWORD PTR [rbx+0x18],r11' 'load' 'mov    QWORD PTR [rbx+0x20],r11' 'nop' 'load' 'mov    QWORD PTR [rbx+0x28],r11')
!
testErrors
	"The first error sticks: immediates and displacements beyond 32 bits, targets out of reach, flags destroyed, a full buffer."
	| x0 x1 |
	x0 := self reg: 'X0'.
	x1 := self reg: 'X1'.
	self assert: (self assemble: [asm ldr: x0 base: (self reg: 'X20') offset: 16r80000000]) equals: 2.
	self assert: (self assemble: [asm alu: 0 w: 1 dst: 7 imm: 16r80000000]) equals: 2.
	self assert: (self assemble: [asm b: (asm labelAt: asm pc + 16r100000000)]) equals: 3.
	self assert: (self assemble: [asm ubfx: x0 with: x1 lsb: 60 width: 5]) equals: 2.
	self assert: (self assemble: [asm cmp: x0 with: x1. asm lsl: x0 with: x0 imm: 3. asm cset: x1 cond: (self cond: 'EQ')]) equals: 6.
	self assert: (self assemble: [asm add: x0 with: x0 with: x1. asm b: (asm labelAt: buffer) if: (self cond: 'EQ')]) asArray equals: #(16r48 16r8D 16r3C 16r37 16r74 16rFA).
	self assert: (self assemble: [asm adds: x0 with: x0 with: x1. asm lsl: x1 with: x1 imm: 1. asm b: (asm labelAt: buffer) if: (self cond: 'EQ')]) equals: 6.
	asm beginAt: buffer limit: buffer + 16.
	9 timesRepeat: [asm nop].
	self deny: asm failed.
	asm nop.
	self assert: asm codeSize equals: 9.
	self assert: asm finish equals: 1
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
		asm str: x0 base: (self reg: 'X20') offset: 16.
		asm bytecode: 5.
		asm ret].
	notes := (0 to: asm noteCount - 1) collect: [:i | | text |
		text := asm noteTextAt: i.
		{asm noteOffsetAt: i. text isNull ifTrue: [nil] ifFalse: [sim memory stringAt: text]. asm noteValueAt: i}].
	self assert: notes asArray equals: #((0 nil 0) (0 'tag check' 0) (6 'spill stack slot %d' 2) (10 nil 5)).
	asm recordNotes: false.
	self assemble: [asm comment: 'off'. asm nop].
	self assert: asm noteCount equals: 0
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
	0 to: asm noteCount - 1 do: [:i | | text |
		text := asm noteTextAt: i.
		text isNull
			ifTrue: [notes addBytecode: (asm noteValueAt: i) text: 'bytecode' source: nil at: (asm noteOffsetAt: i)]
			ifFalse: [notes addComment: ((sim memory stringAt: text) copyReplaceAll: '%d' with: (asm noteValueAt: i) printString) at: (asm noteOffsetAt: i)]].
	notes addSymbol: 'send_miss' at: buffer + 16r4000.
	listing := Amd64Disassembler new listingOfBytes: self bytes at: buffer annotations: notes.
	self assert: listing equals: (String new: 500 streamContents: [:s | | commented |
		commented := [:line :comment | s nextPutAll: (line padRightTo: 74); nextPutAll: '  ; '; nextPutAll: comment; lf].
		s nextPutAll: 'pc 0: bytecode'; lf; nextPutAll: 'L1:'; lf.
		commented value: '  +0000  40f6c701              test   dil,0x1' value: 'SmallInteger tag check'.
		s nextPutAll: '  +0004  0f8406000000          je     L2'; lf; lf.
		s nextPutAll: 'pc 3: bytecode'; lf.
		commented value: '  +000a  48897e10              mov    QWORD PTR [rsi+0x10],rdi' value: 'spill stack slot 2'.
		s nextPutAll: '  +000e  ebf0                  jmp    L1'; lf; nextPutAll: 'L2:'; lf.
		commented value: '  +0010  e8eb3f0000            call   ' , (self hex: buffer + 16r4000) , ' <send_miss>' value: 'call runtime: send miss'.
		s nextPutAll: '  +0015  c3                    ret'; lf])
! !
