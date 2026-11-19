TestCase subclass: #UefiImageWriterTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

UefiImageWriterTest comment: 'UefiImageWriter turns a minimal static PIE built here (one PT_LOAD at address 0 with 1 MB of BSS, a PT_DYNAMIC, one R_X86_64_RELATIVE and one R_X86_64_NONE) into a PE32+ EFI application: the header fields EDK2 checks, the patched word, the DIR64 block, and the BSS left out of the file.'!

!UefiImageWriterTest methodsFor: 'helpers'!
put64: value into: bytes at: offset
	"Little-endian, at a 0-based offset."
	0 to: 7 do: [:i | bytes at: offset + i + 1 put: ((value bitShift: i * -8) bitAnd: 255)]
!
elfWithRelocationType: type
	"File offsets are addresses: ELF header at 0, PT_LOAD and PT_DYNAMIC headers at 64 and 120, the dynamic table at 176, the Rela table at 256, the relocated word at 512, the entry point at 768; 1024 bytes in the file and 1 MB more in memory."
	| elf |
	elf := ByteArray new: 1024.
	elf replaceFrom: 1 to: 8 with: #[16r7F 16r45 16r4C 16r46 2 1 1 0] startingAt: 1.
	elf uint16At: 17 put: 3; uint16At: 19 put: 62; uint32At: 21 put: 1.
	self put64: 768 into: elf at: 24.
	self put64: 64 into: elf at: 32.
	elf uint16At: 53 put: 64; uint16At: 55 put: 56; uint16At: 57 put: 2.
	"PT_LOAD RWX"
	elf uint32At: 65 put: 1; uint32At: 69 put: 7.
	self put64: 1024 into: elf at: 64 + 32.
	self put64: 1024 + 16r100000 into: elf at: 64 + 40.
	self put64: 4096 into: elf at: 64 + 48.
	"PT_DYNAMIC"
	elf uint32At: 121 put: 2; uint32At: 125 put: 6.
	self put64: 176 into: elf at: 120 + 8.
	self put64: 176 into: elf at: 120 + 16.
	self put64: 64 into: elf at: 120 + 32.
	self put64: 64 into: elf at: 120 + 40.
	#(7 256 8 48 9 24) pairsDo: [:tag :value |
		| at |
		at := 176 + ((#(7 8 9) indexOf: tag) - 1 * 16).
		self put64: tag into: elf at: at.
		self put64: value into: elf at: at + 8].
	"{r_offset 512. type. r_addend 768}, then an R_X86_64_NONE"
	self put64: 512 into: elf at: 256.
	self put64: type into: elf at: 264.
	self put64: 768 into: elf at: 272.
	elf at: 768 + 1 put: 16rC3.
	^elf
!
uint64In: bytes at: offset
	^(bytes uint32At: offset + 1) + ((bytes uint32At: offset + 5) bitShift: 32)
! !

!UefiImageWriterTest methodsFor: 'tests'!
testStaticPieBecomesEfiApplication
	| pe peOffset opt section reloc |
	pe := UefiImageWriter new convertBytes: (self elfWithRelocationType: 8).
	self assert: (pe copyFrom: 1 to: 2) equals: 'MZ' asByteArray.
	peOffset := pe uint32At: 16r3C + 1.
	self assert: (pe copyFrom: peOffset + 1 to: peOffset + 4) equals: #[16r50 16r45 0 0].
	self assert: (pe uint16At: peOffset + 5) equals: 16r8664.
	self assert: (pe uint16At: peOffset + 7) equals: 2.
	self assert: (pe uint16At: peOffset + 21) equals: 240.
	self assert: (pe uint16At: peOffset + 23) equals: 16r22.
	opt := peOffset + 24.
	self assert: (pe uint16At: opt + 1) equals: 16r20B.
	"the code moves up a page to make room for the headers"
	self assert: (pe uint32At: opt + 17) equals: 768 + 4096.
	self assert: (self uint64In: pe at: opt + 24) equals: 16r10000000.
	self assert: (pe uint32At: opt + 33) equals: 4096.
	self assert: (pe uint32At: opt + 37) equals: 512.
	self assert: (pe uint32At: opt + 57) equals: 4096 + 16r101000 + 4096.
	self assert: (pe uint32At: opt + 61) equals: 512.
	self assert: (pe uint16At: opt + 69) equals: 10.
	self assert: (pe uint16At: opt + 71) equals: 0.
	self assert: (pe uint32At: opt + 109) equals: 16.
	self assert: (pe uint32At: opt + 112 + 40 + 1) equals: 4096 + 16r101000.
	self assert: (pe uint32At: opt + 112 + 44 + 1) equals: 12.
	section := opt + 240.
	self assert: (pe copyFrom: section + 1 to: section + 5) equals: '.text' asByteArray.
	self assert: (pe uint32At: section + 9) equals: 16r101000.
	self assert: (pe uint32At: section + 13) equals: 4096.
	self assert: (pe uint32At: section + 17) equals: 1024.
	self assert: (pe uint32At: section + 21) equals: 512.
	self assert: (pe uint32At: section + 37) equals: 16rE0000060.
	"the BSS is not in the file; the word holds ImageBase + RVA of the addend"
	self assert: pe size equals: 512 + 1024 + 512.
	self assert: (self uint64In: pe at: 512 + 512) equals: 16r10000000 + 4096 + 768.
	self assert: (pe at: 512 + 768 + 1) equals: 16rC3.
	reloc := 512 + 1024.
	self assert: (pe uint32At: reloc + 1) equals: 4096.
	self assert: (pe uint32At: reloc + 5) equals: 12.
	self assert: (pe uint16At: reloc + 9) equals: 16rA000 + 512.
	self assert: (pe uint16At: reloc + 11) equals: 0
!
testUnsupportedRelocationIsAnError
	self
		should: [UefiImageWriter new convertBytes: (self elfWithRelocationType: 1)]
		raise: Error
		withExceptionDo: [:e |
			self assert: (e messageText includesSubstring: 'R_X86_64_64').
			self assert: (e messageText includesSubstring: '0x200')]
!
testNotAnElfIsAnError
	self should: [UefiImageWriter new convertBytes: (ByteArray new: 100)] raise: Error
! !
