TestCase subclass: #Arm64DisassemblerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

Arm64DisassemblerTest comment: 'Arm64Disassembler prints what objdump prints (Arm64Reference).'!

!Arm64DisassemblerTest methodsFor: 'helpers'!
assertTexts: triples
	"triples: word, address, objdump's text, ..."
	| disassembler failures |
	disassembler := Arm64Disassembler new.
	failures := OrderedCollection new.
	1 to: triples size by: 3 do: [:i | | text |
		text := disassembler textFor: (triples at: i) at: (triples at: i + 1).
		text = (triples at: i + 2) ifFalse: [
			failures add: ((triples at: i) printString: 16) , ': ' , text , ' instead of ' , (triples at: i + 2)]].
	self assert: failures isEmpty description: [
		failures size printString , ' wrong: ' , ('; ' join: (failures copyFrom: 1 to: (failures size min: 20)))]
! !

!Arm64DisassemblerTest methodsFor: 'tests'!
testReferenceCases
	| triples |
	triples := OrderedCollection new.
	Arm64Reference cases do: [:case |
		(case at: 3) doWithIndex: [:word :i |
			triples add: word; add: (case at: 2) + (i - 1 * 4); add: ((case at: 4) at: i)]].
	self assertTexts: triples
!
testLogicalImmediates
	| triples |
	triples := OrderedCollection new.
	#(64 32) do: [:width | | pairs |
		pairs := width = 64 ifTrue: [Arm64Reference logicalImmediates64] ifFalse: [Arm64Reference logicalImmediates32].
		1 to: pairs size by: 2 do: [:i |
			triples
				add: ((width = 64 ifTrue: [16r92000020] ifFalse: [16r12000020]) bitOr: ((pairs at: i + 1) bitShift: 10));
				add: 0;
				add: (width = 64 ifTrue: ['and x0, x1, #0x'] ifFalse: ['and w0, w1, #0x']) , ((pairs at: i) printString: 16) asLowercase]].
	self assertTexts: triples
!
testRandomWords
	"objdump's text of random words of the instruction classes the disassembler decodes"
	| pairs triples |
	pairs := Arm64Reference disassembly.
	triples := OrderedCollection new.
	1 to: pairs size by: 2 do: [:i | triples add: (pairs at: i); add: i - 1 * 2; add: (pairs at: i + 1)].
	self assertTexts: triples
!
testUnsupported
	self assertTexts: #(
		16r00000000 0 '.word 0x00000000'
		16rFFFFFFFF 0 '.word 0xffffffff'
		16r9AC24C20 0 '.word 0x9ac24c20'	"crc32x"
		16rF9800020 0 '.word 0xf9800020'	"prfm"
		16r1E204020 0 '.word 0x1e204020'	"fmov s0, s1"
		16r3DC00020 0 '.word 0x3dc00020'	"ldr q0, [x1]"
		16r9B227C20 0 '.word 0x9b227c20'	"smull"
		16rA8400420 0 '.word 0xa8400420'	"ldnp"
		16rD503203F 0 '.word 0xd503203f'	"yield"
		16r4E083C20 0 '.word 0x4e083c20')	"mov x0, v1.d[0]"
!
testListing
	| memory start |
	memory := SimulatedMemory new.
	start := memory allocate: 16.
	#(16r91003020 16rD65F03C0 16r17FFFFFE 16r00000000) doWithIndex: [:w :i | memory uint32At: start + (i - 1 * 4) put: w].
	self
		assert: (Arm64Disassembler new listing: memory from: start to: start + 16)
		equals: ('{1}: 91003020  add x0, x1, #0xc
{2}: d65f03c0  ret
{3}: 17fffffe  b {1}
{4}: 00000000  .word 0x00000000
' format: ((0 to: 3) collect: [:i | '0x' , ((start + (i * 4)) printString: 16) asLowercase]))
!
testAnnotatedListing
	"bytecode headers, comments, labels for a forward and a backward branch, calls by name (bl, and blr after movz/movk), a branch outside"
	| notes |
	notes := Arm64CodeAnnotations new.
	notes addBytecode: 0 text: 'pushTemp: 0' source: 'x + 1' at: 0.
	notes addComment: 'load receiver' at: 0.
	notes addComment: 'second comment' at: 0.
	notes addBytecode: 2 text: 'send: #+' source: nil at: 12.
	notes addComment: 'loop' at: 12.
	notes addComment: 'end' at: 36.
	notes addSymbol: 'send_miss' at: 16r20000.
	notes addSymbol: 'trampoline' at: 16r23000.
	self
		assert: (Arm64Disassembler new
			listingOfWords: #(16rF9400020 16rB4000060 16r94003FFE 16r54FFFFA1 16rD2860010 16rF2A00050 16rD63F0200 16r17FFDFF9 16rD65F03C0)
			at: 16r10000
			annotations: notes)
		equals: 'pc 0: pushTemp: 0  -- x + 1
L1:
  +0000  f9400020  ldr x0, [x1]                     ; load receiver
                                                    ; second comment
  +0004  b4000060  cbz x0, L2
  +0008  94003ffe  bl 0x20000 <send_miss>

pc 2: send: #+
  +000c  54ffffa1  b.ne L1                          ; loop
L2:
  +0010  d2860010  mov x16, #0x3000
  +0014  f2a00050  movk x16, #0x2, lsl #16
  +0018  d63f0200  blr x16 <trampoline>
  +001c  17ffdff9  b 0x8000
  +0020  d65f03c0  ret
                                                    ; end
'
!
testAnnotatedListingWithoutAnnotations
	| memory start |
	memory := SimulatedMemory new.
	start := memory allocate: 8.
	memory uint32At: start put: 16r35000020; uint32At: start + 4 put: 16rD65F03C0.
	self
		assert: (Arm64Disassembler new listing: memory from: start to: start + 8 annotations: nil)
		equals: '  +0000  35000020  cbnz w0, L1
L1:
  +0004  d65f03c0  ret
'
! !
