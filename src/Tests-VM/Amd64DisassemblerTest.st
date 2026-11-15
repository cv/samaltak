TestCase subclass: #Amd64DisassemblerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

Amd64DisassemblerTest comment: 'Amd64Disassembler prints what objdump -M intel prints, and decodes the lengths it decodes (Amd64Reference); its listings, annotated as JIT code is.'!

!Amd64DisassemblerTest methodsFor: 'helpers'!
bytes: aHexString
	| bytes |
	bytes := ByteArray new: aHexString size // 2.
	1 to: bytes size do: [:i | bytes at: i put: (Integer readFrom: (aHexString copyFrom: 2 * i - 1 to: 2 * i) asUppercase base: 16)].
	^bytes
!
assertTexts: triples
	"triples: bytes in hex (one instruction, or one undecodable byte and more), address, objdump's text, ..."
	| disassembler failures |
	disassembler := Amd64Disassembler new.
	failures := OrderedCollection new.
	1 to: triples size by: 3 do: [:i | | bytes text expected |
		bytes := self bytes: (triples at: i).
		expected := triples at: i + 2.
		text := disassembler textFor: bytes at: (triples at: i + 1).
		(text = expected and: [disassembler length = ((expected beginsWith: '.byte') ifTrue: [1] ifFalse: [bytes size])]) ifFalse: [
			failures add: (triples at: i) , ': ' , text , ' (' , disassembler length printString , ' bytes) instead of ' , expected]].
	self assert: failures isEmpty description: [
		failures size printString , ' wrong: ' , ('; ' join: (failures copyFrom: 1 to: (failures size min: 20)))]
! !

!Amd64DisassemblerTest methodsFor: 'tests'!
testReferenceCases
	"Each instruction of each case as objdump prints it at its offset in the object file."
	| triples |
	triples := OrderedCollection new.
	Amd64Reference cases do: [:case | | offset |
		offset := case at: 2.
		1 to: (case at: 3) size by: 2 do: [:i |
			triples add: ((case at: 3) at: i); add: offset; add: ((case at: 3) at: i + 1).
			offset := offset + (((case at: 3) at: i) size // 2)]].
	self assertTexts: triples
!
testReferenceSequences
	"The bytes of each case decoded one instruction after the other."
	| disassembler wrong |
	disassembler := Amd64Disassembler new.
	wrong := OrderedCollection new.
	Amd64Reference cases do: [:case | | hex texts |
		hex := String new: 64 streamContents: [:s | 1 to: (case at: 3) size by: 2 do: [:i | s nextPutAll: ((case at: 3) at: i)]].
		texts := (disassembler instructionsOf: (self bytes: hex) at: (case at: 2)) collect: [:each | each at: 3].
		texts asArray = ((2 to: (case at: 3) size by: 2) collect: [:i | (case at: 3) at: i]) asArray
			ifFalse: [wrong add: (case at: 1)]].
	self assert: wrong isEmpty description: [', ' join: wrong]
!
testRandomInstructions
	"objdump's text of random instructions of every opcode the disassembler decodes, with random prefixes, REX bits, operands and immediates"
	self assertTexts: Amd64Reference disassembly
!
testUnsupported
	"One byte each, as .byte: instructions I do not decode, prefixes they do not use, the bytes of an instruction cut short."
	self assertTexts: #(
		'0f05' 0 '.byte 0x0f'	"syscall"
		'f3c3' 0 '.byte 0xf3'	"repz ret"
		'678b03' 0 '.byte 0x67'	"addr32"
		'2e8b03' 0 '.byte 0x2e'	"cs"
		'f0480103' 0 '.byte 0xf0'	"lock"
		'66488bc0' 0 '.byte 0x66'	"data16 mov rax,rax"
		'66668bc0' 0 '.byte 0x66'
		'f2f20f58c1' 0 '.byte 0xf2'
		'48f20f58c1' 0 '.byte 0x48'	"REX, then another prefix"
		'48488bc0' 0 '.byte 0x48'
		'c5f877' 0 '.byte 0xc5'	"vzeroupper"
		'0f10c1' 0 '.byte 0x0f'	"movups"
		'f30f10c1' 0 '.byte 0xf3'	"movss"
		'd8c1' 0 '.byte 0xd8'	"fadd st,st(1)"
		'a0efcdab8967452301' 0 '.byte 0xa0'	"movabs al,ds:0x..."
		'8dc0' 0 '.byte 0x8d'	"lea of a register"
		'0fbac705' 0 '.byte 0x0f'	"bt group, /0"
		'c6c805' 0 '.byte 0xc6'
		'8fc8' 0 '.byte 0x8f'
		'ffd8' 0 '.byte 0xff'	"far call"
		'fed0' 0 '.byte 0xfe'
		'48' 0 '.byte 0x48'
		'e80000' 0 '.byte 0xe8'
		'488b' 0 '.byte 0x48'
		'0f' 0 '.byte 0x0f')
!
testOperands
	"objdump's choices: riz, ds:, the displacement of a base without one, rip with a negative displacement, REX bits unused, byte registers with and without REX"
	self assertTexts: #(
		'8b0464' 0 'mov    eax,DWORD PTR [rsp+riz*2]'
		'8b442008' 0 'mov    eax,DWORD PTR [rax+riz*1+0x8]'
		'8b0424' 0 'mov    eax,DWORD PTR [rsp]'
		'418b0424' 0 'mov    eax,DWORD PTR [r12]'
		'488b3cf5f0ffffff' 0 'mov    rdi,QWORD PTR [rsi*8-0x10]'
		'488b3c25f0ffffff' 0 'mov    rdi,QWORD PTR ds:0xfffffffffffffff0'
		'418b04e510000000' 0 'mov    eax,DWORD PTR [riz*8+0x10]'
		'488b7d00' 0 'mov    rdi,QWORD PTR [rbp+0x0]'
		'488b3d00ffffff' 16r1000 'mov    rdi,QWORD PTR [rip+0xffffffffffffff00]        # 0xf07'
		'418b0500000000' 0 'mov    eax,DWORD PTR [rip+0x0]        # 0x7'
		'428b03' 0 'rex.X mov eax,DWORD PTR [rbx]'
		'408bc0' 0 'rex mov eax,eax'
		'4c0f1f00' 0 'rex.WR nop QWORD PTR [rax]'
		'4899' 0 'cqo'
		'4999' 0 'rex.WB cqo'
		'88e0' 0 'mov    al,ah'
		'4088e0' 0 'mov    al,spl'
		'4188e3' 0 'mov    r11b,spl'
		'4088c0' 0 'rex mov al,al'
		'48b088' 0 'rex.W mov al,0x88'
		'ebfe' 0 'jmp    0x0'
		'ebfd' 0 'jmp    0xffffffffffffffff'
		'e8fbffffff' 16r7FFF00001000 'call   0x7fff00001000'
		'6690' 0 'xchg   ax,ax'
		'664890' 0 'xchg   rax,rax'
		'4190' 0 'xchg   r8d,eax'
		'4890' 0 'rex.W nop'
		'664f6344ced2' 0 'movsxd r8,DWORD PTR [r14+r9*8-0x2e]'
		'c20800' 0 'ret    0x8'
		'0f0b' 0 'ud2')
!
testListing
	self
		assert: (Amd64Disassembler new listingOfBytes: (self bytes: '488d7e0cc3ebfd0f05') at: 16r1000)
		equals: '0x1000: 488d7e0c              lea    rdi,[rsi+0xc]
0x1004: c3                    ret
0x1005: ebfd                  jmp    0x1004
0x1007: 0f                    .byte 0x0f
0x1008: 05                    .byte 0x05
'
!
testInstructionsOf
	"offset, size and text of each instruction, one after the other; undecodable bytes one at a time"
	self
		assert: (Amd64Disassembler new instructionsOf: (self bytes: '4889c766c39066c3') at: 0) asArray
		equals: #((0 3 'mov    rdi,rax') (3 1 '.byte 0x66') (4 1 'ret') (5 1 'nop') (6 1 '.byte 0x66') (7 1 'ret'))
!
testAnnotatedListing
	"bytecode headers, comments (one inside an instruction), labels for a forward and a backward branch and a literal, calls by name (call rel32, call r10 after a movabs, jmp rax after a load of a literal), a branch outside, the literal as .quad with its name, a comment at the end"
	| notes bytes |
	notes := Arm64CodeAnnotations new.
	notes addBytecode: 0 text: 'pushTemp: 0' source: 'x + 1' at: 0.
	notes addComment: 'load receiver' at: 0.
	notes addComment: 'second comment' at: 0.
	notes addComment: 'inside' at: 16r10.
	notes addBytecode: 2 text: 'send: #+' source: nil at: 16r12.
	notes addComment: 'loop' at: 16r12.
	notes addComment: 'end' at: 16r38.
	notes addSymbol: 'send_miss' at: 16r14000.
	notes addSymbol: 'trampoline' at: 16r23000.
	notes addSymbol: 'stub' at: 16r24000.
	bytes := self bytes: '488b7b08' , '4885ff' , '0f8407000000' , 'e8ee3f0000' , '75ec' , '49ba0030020000000000' , '41ffd2' ,
		'488b0508000000' , 'ffe0' , 'e9d17fffff' , 'c3' , '0040020000000000'.
	self
		assert: (Amd64Disassembler new listingOfBytes: bytes at: 16r10000 annotations: notes)
		equals: 'pc 0: pushTemp: 0  -- x + 1
L1:
  +0000  488b7b08              mov    rdi,QWORD PTR [rbx+0x8]               ; load receiver
                                                                            ; second comment
  +0004  4885ff                test   rdi,rdi
  +0007  0f8407000000          je     L2
  +000d  e8ee3f0000            call   0x14000 <send_miss>                   ; inside

pc 2: send: #+
  +0012  75ec                  jne    L1                                    ; loop
L2:
  +0014  49ba0030020000000000  movabs r10,0x23000
  +001e  41ffd2                call   r10 <trampoline>
  +0021  488b0508000000        mov    rax,QWORD PTR [rip+0x8]        # L3
  +0028  ffe0                  jmp    rax <stub>
  +002a  e9d17fffff            jmp    0x8000
  +002f  c3                    ret
L3:
  +0030  0040020000000000      .quad 0x24000 <stub>
                                                                            ; end
'
!
testDataWords
	"As the JIT lays out a method: code, int3 up to a multiple of 8, words (literals, an oop pool, inline caches' words) to the end. The words begin after the int3 padding, or after the last instruction, a jmp or ret no branch passes, before the first word an instruction refers to; without int3 nor such a word nothing is data."
	| texts |
	texts := [:hex | ((Amd64Disassembler new piecesOf: (self bytes: hex) at: 0) collect: [:each | each at: 3]) asArray].
	self assert: (texts value: '488b0511000000' , '90' , 'c3' , 'cccccccccccccc' , '0102030405060708' , '1122334455667788' , 'c3c3c3c3c3c3c3c3')
		equals: #('mov    rax,QWORD PTR [rip+0x11]        # 0x18' 'nop' 'ret' 'int3' 'int3' 'int3' 'int3' 'int3' 'int3' 'int3'
			'.quad 0x807060504030201' '.quad 0x8877665544332211' '.quad 0xc3c3c3c3c3c3c3c3').
	self assert: (texts value: '488b0511000000' , 'c3' , '0102030405060708' , 'c3c3c3c3c3c3c3c3' , '1122334455667788')
		equals: #('mov    rax,QWORD PTR [rip+0x11]        # 0x18' 'ret' '.quad 0x807060504030201' '.quad 0xc3c3c3c3c3c3c3c3' '.quad 0x8877665544332211').
	self assert: (texts value: 'c3' , 'cccccccccccccc' , '0102030405060708') equals: #('ret' 'int3' 'int3' 'int3' 'int3' 'int3' 'int3' 'int3' '.quad 0x807060504030201').
	self assert: (texts value: 'c3' , '9090909090909090') equals: #('ret' 'nop' 'nop' 'nop' 'nop' 'nop' 'nop' 'nop' 'nop').
	self assert: (texts value: '7406' , 'c3' , 'cccccccccc' , '9090909090909090') equals: #('je     0x8' 'ret' 'int3' 'int3' 'int3' 'int3' 'int3' 'nop' 'nop' 'nop' 'nop' 'nop' 'nop' 'nop' 'nop')
!
testAnnotatedListingWithoutAnnotations
	"A label at the end; undecodable bytes, and decoding on after them."
	self
		assert: (Amd64Disassembler new listingOfBytes: (self bytes: '7503' , '0f' , '05' , 'c3') at: 0 annotations: nil)
		equals: '  +0000  7503                  jne    L1
  +0002  0f                    .byte 0x0f
  +0003  05                    .byte 0x05
  +0004  c3                    ret
L1:
'
!
testScanner
	"MachineCodeScanner (Tools, late-bound) tokenizes an x86 listing: registers, sizes, immediates, displacements, targets."
	| scanner listing tokens typeOf |
	scanner := Smalltalk at: #MachineCodeScanner ifAbsent: [^self].
	listing := 'Foo>>bar  opt, 16 bytes at 16r100' , String lf , String lf ,
		'  +0000  488b7b08              mov    rdi,QWORD PTR [rbx-0x8]        ; load' , String lf ,
		'  +0004  4c8b15b58d4dff        mov    r10d,DWORD PTR [rip+0xffffffffff4d8db5]        # 0x559e62e80130' , String lf ,
		'  +000b  40f6c707              test   sil,0x7' , String lf ,
		'  +000f  e84391c6ff            call   0x559e63610524 <baseline miss>' , String lf ,
		'  +0014  f2440f114c2438        movsd  QWORD PTR [rsp+r12*8+0x38],xmm9' , String lf ,
		'  +001b  0f8407000000          je     L2' , String lf ,
		'  +0021  0f94c0                sete   al' , String lf ,
		'  +0024  0040020000000000      .quad 0x24000 <stub>'.
	tokens := OrderedCollection new.
	scanner highlight: listing do: [:type :start :stop | tokens add: type -> (listing copyFrom: start to: stop)].
	self assert: (tokens inject: '' into: [:all :each | all , each value]) equals: listing.
	typeOf := [:text | (tokens detect: [:each | each value = text] ifNone: [nil -> nil]) key].
	#(
		'+0000' #self '488b7b08' #self 'mov' #keyword 'rdi' #symbol 'QWORD PTR' #keyword 'rbx' #symbol '-0x8' #global '; load' #comment
		'4c8b15b58d4dff' #self 'r10d' #symbol 'DWORD PTR' #keyword 'rip' #symbol '0xffffffffff4d8db5' #global '0x559e62e80130' #global
		'sil' #symbol '0x7' #global '0x559e63610524' #global '<baseline miss>' #global 'movsd' #keyword 'rsp' #symbol 'r12' #symbol
		'0x38' #global 'xmm9' #symbol 'je' #keyword 'L2' #global 'sete' #keyword 'al' #symbol '.quad' #keyword '0x24000' #global)
		pairsDo: [:text :type | self assert: (typeOf value: text) = type description: [text , ': ' , (typeOf value: text) printString]]
! !
