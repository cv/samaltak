Object subclass: #UefiImageWriter
	instanceVariableNames: 'elf elfType machine entry loads low high fileHigh requestedImageBase imageBase shift relocationsStripped body relocationRvas'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiImageWriter comment: 'I convert a statically linked ELF64 executable (a static PIE linked at base 0, ET_DYN, or an ET_EXEC; x86-64 or AArch64, little-endian) into a PE32+ EFI application, the only format UEFI firmware loads:

	UefiImageWriter new convert: ''build/uefi/samaltak.elf'' to: ''esp/EFI/BOOT/BOOTX64.EFI''

Layout. All PT_LOAD segments go into one section, .text, that is readable, writable and executable (the JIT writes and runs code in a zero-filled array in the BSS), whose VirtualSize includes the BSS and whose raw data stops at the last file-backed byte, so the BSS costs nothing in the file. The segments keep their distances: an ELF address v is at RVA v + shift. A PE image''s headers sit at RVA 0 and a static PIE''s first segment (its ELF headers, .dynsym, .rela.dyn, .rodata) starts at address 0 as well, so for one linked at base 0 the shift is one page; for an image linked higher (ET_EXEC, or a PIE with --image-base) ImageBase is chosen so that ImageBase + RVA is the linked address. The preferred ImageBase of a PIE linked at 0 is 16r10000000 (imageBase: changes it).

Relocations. The dynamic relocations (PT_DYNAMIC''s DT_RELA and DT_JMPREL tables, or without PT_DYNAMIC the allocated SHT_RELA sections) must be R_X86_64_RELATIVE or R_AARCH64_RELATIVE (R_*_NONE are skipped): each word is written as ImageBase + RVA of its addend and listed in .reloc as an IMAGE_REL_BASED_DIR64 entry, so the firmware can load the image anywhere. An ET_EXEC has no such list and is marked RELOCS_STRIPPED (it loads only at its ImageBase). Anything else (other relocation types, DT_REL, DT_RELR, DT_NEEDED, PT_INTERP, PT_TLS, 32-bit or big-endian ELF, other CPUs) signals an Error saying what it is.

The headers are what EDK2''s PeCoffLoader checks: a DOS header and stub with e_lfanew, machine 16r8664 or 16rAA64, EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE, subsystem 10 (EFI application), SectionAlignment 4096, FileAlignment 512, 16 data directories (5, the base relocation table, points at .reloc), no NX_COMPAT, checksum 0.'!

!UefiImageWriter methodsFor: 'converting'!
convert: elfPath to: efiPath
	"Read the ELF executable at elfPath, write it as a PE32+ EFI application to efiPath and answer efiPath."
	File writeBytes: (self convertBytes: (File readBytes: elfPath)) to: efiPath.
	^efiPath
!
convertBytes: elfBytes
	"Answer the PE32+ EFI application (a ByteArray) for the ELF executable in elfBytes."
	elf := elfBytes asByteArray.
	self readHeader; readSegments; chooseImageBase; buildBody; applyRelocations.
	^self image
! !

!UefiImageWriter methodsFor: 'accessing'!
imageBase: anInteger
	"Prefer anInteger (a multiple of 64 KB) as the ImageBase of a position-independent image."
	(anInteger > 0 and: [anInteger \\ 16r10000 = 0]) ifFalse: [self fail: 'ImageBase must be a positive multiple of 64 KB, not ', (self hex: anInteger)].
	requestedImageBase := anInteger
!
imageBase
	"The ImageBase of the last conversion."
	^imageBase
! !

!UefiImageWriter methodsFor: 'reading the ELF'!
readHeader
	(elf size >= 64 and: [(elf copyFrom: 1 to: 4) = #[16r7F 16r45 16r4C 16r46]]) ifFalse: [self fail: 'not an ELF file'].
	(elf at: 5) = 2 ifFalse: [self fail: 'not a 64-bit ELF (ELFCLASS ', (elf at: 5) printString, ')'].
	(elf at: 6) = 1 ifFalse: [self fail: 'not a little-endian ELF (ELFDATA ', (elf at: 6) printString, ')'].
	elfType := self u16: 16.
	(elfType = 2 or: [elfType = 3]) ifFalse: [self fail: 'ELF type ', elfType printString, ' is neither ET_EXEC (2) nor ET_DYN (3): link an executable or a static PIE'].
	machine := self u16: 18.
	(machine = 62 or: [machine = 183]) ifFalse: [self fail: 'ELF machine ', machine printString, ' is neither x86-64 (62) nor AArch64 (183)'].
	entry := self u64: 24.
	(self u16: 54) = 56 ifFalse: [self fail: 'unexpected program header size ', (self u16: 54) printString]
!
readSegments
	"Collect the PT_LOAD segments as {vaddr. file offset. filesz. memsz}, sorted by address."
	| phoff phnum |
	phoff := self u64: 32.
	phnum := self u16: 56.
	phnum = 16rFFFF ifTrue: [self fail: 'more than 65534 program headers (PN_XNUM) are not supported'].
	loads := OrderedCollection new.
	0 to: phnum - 1 do: [:i |
		| ph type offset vaddr filesz memsz |
		ph := phoff + (i * 56).
		type := self u32: ph.
		offset := self u64: ph + 8.
		vaddr := self u64: ph + 16.
		filesz := self u64: ph + 32.
		memsz := self u64: ph + 40.
		type = 3 ifTrue: [self fail: 'the ELF has a PT_INTERP (a dynamic loader): link with --no-dynamic-linker'].
		type = 7 ifTrue: [self fail: 'thread-local storage (PT_TLS) is not supported'].
		(type = 1 and: [memsz > 0]) ifTrue: [
			filesz > memsz ifTrue: [self fail: 'PT_LOAD at ', (self hex: vaddr), ' has p_filesz > p_memsz'].
			offset + filesz > elf size ifTrue: [self fail: 'PT_LOAD at ', (self hex: vaddr), ' extends past the end of the file'].
			loads add: {vaddr. offset. filesz. memsz}]].
	loads isEmpty ifTrue: [self fail: 'the ELF has no PT_LOAD segment'].
	loads := loads asSortedCollection: [:a :b | a first <= b first].
	loads := loads asArray.
	1 to: loads size - 1 do: [:i |
		| a b |
		a := loads at: i.
		b := loads at: i + 1.
		a first + (a at: 4) > b first ifTrue: [self fail: 'PT_LOAD segments at ', (self hex: a first), ' and ', (self hex: b first), ' overlap']].
	low := loads first first bitClear: 4095.
	high := self align: (loads inject: 0 into: [:m :s | m max: s first + (s at: 4)]) to: 4096.
	fileHigh := loads inject: low into: [:m :s | (s at: 3) > 0 ifTrue: [m max: s first + (s at: 3)] ifFalse: [m]].
	(entry >= low and: [entry < high]) ifFalse: [self fail: 'the entry point ', (self hex: entry), ' is outside the PT_LOAD segments']
!
fileOffsetOf: vaddr size: n
	"Answer the file offset of the n bytes at ELF address vaddr, which must lie in the file-backed part of a PT_LOAD segment."
	loads do: [:s |
		(vaddr >= s first and: [vaddr + n <= (s first + (s at: 3))]) ifTrue: [^vaddr - s first + (s at: 2)]].
	^self fail: 'address ', (self hex: vaddr), ' is not in the file-backed part of a PT_LOAD segment'
! !

!UefiImageWriter methodsFor: 'layout'!
headerSpace
	"The headers' RVA range: they fit in SizeOfHeaders, and the first section starts at the next page."
	^4096
!
chooseImageBase
	"Choose ImageBase and the shift from ELF addresses to RVAs (see the class comment)."
	| linked |
	relocationsStripped := elfType = 2.
	linked := (low - self headerSpace) bitClear: 16rFFFF.
	relocationsStripped
		ifTrue: [
			linked > 0 ifFalse: [self fail: 'an ET_EXEC must be linked at or above ', (self hex: 16r10000 + self headerSpace), ' to leave room for the PE headers, it starts at ', (self hex: low)].
			imageBase := linked.
			shift := linked negated]
		ifFalse: [
			(requestedImageBase isNil and: [linked > 0])
				ifTrue: [
					imageBase := linked.
					shift := linked negated]
				ifFalse: [
					imageBase := requestedImageBase ifNil: [16r10000000].
					shift := self headerSpace - low]].
	high + shift > 16rFFFFFFFF ifTrue: [self fail: 'the image is larger than 4 GB']
!
buildBody
	"The section's file-backed bytes: every segment's file contents at its place, zeros between them."
	body := ByteArray new: (self align: fileHigh - low to: self fileAlignment).
	loads do: [:s |
		(s at: 3) > 0 ifTrue: [
			body replaceFrom: s first - low + 1 to: s first - low + (s at: 3) with: elf startingAt: (s at: 2) + 1]]
!
sectionAlignment
	^4096
!
fileAlignment
	^512
! !

!UefiImageWriter methodsFor: 'relocations'!
applyRelocations
	"Patch every relative word to ImageBase + RVA of its addend and collect the patched words' RVAs."
	relocationRvas := Set new.
	self relocationTables do: [:table |
		| offset size entsize |
		offset := table first.
		size := table at: 2.
		entsize := table at: 3.
		entsize = 24 ifFalse: [self fail: 'unexpected Elf64_Rela entry size ', entsize printString].
		size \\ 24 = 0 ifFalse: [self fail: 'the relocation table at file offset ', (self hex: offset), ' is not a whole number of entries'].
		offset + size > elf size ifTrue: [self fail: 'the relocation table at file offset ', (self hex: offset), ' extends past the end of the file'].
		0 to: size - 1 by: 24 do: [:e |
			self relocate: (self u64: offset + e) type: ((self u64: offset + e + 8) bitAnd: 16rFFFFFFFF) addend: (self s64: offset + e + 16)]].
	relocationRvas := relocationRvas asSortedCollection asArray
!
relocate: vaddr type: type addend: addend
	| value |
	(self isNoneRelocation: type) ifTrue: [^self].
	(self isRelativeRelocation: type) ifFalse: [
		self fail: 'unsupported relocation type ', type printString, ' (', (self relocationName: type), ') at ', (self hex: vaddr), '; only ', (self relocationName: self relativeRelocationType), ' can be converted'].
	(vaddr >= low and: [vaddr + 8 <= fileHigh and: [(self fileOffsetOf: vaddr size: 8) notNil]]) ifFalse: [
		self fail: 'relocation at ', (self hex: vaddr), ' is not in the file-backed part of a PT_LOAD segment'].
	value := imageBase + shift + addend.
	(value between: 0 and: 16rFFFFFFFFFFFFFFFF) ifFalse: [self fail: 'relocated value at ', (self hex: vaddr), ' does not fit 64 bits'].
	self put64: value into: body at: vaddr - low.
	relocationRvas add: vaddr + shift
!
relocationTables
	"Answer the dynamic relocation tables as {file offset. size. entry size}: PT_DYNAMIC's DT_RELA and DT_JMPREL, or without PT_DYNAMIC the allocated SHT_RELA sections."
	| dynamic |
	dynamic := self dynamicEntries.
	dynamic isNil ifTrue: [^self relocationSections].
	(dynamic includesKey: 1) ifTrue: [self fail: 'the ELF needs shared libraries (DT_NEEDED): link it statically'].
	((dynamic at: 18 ifAbsent: [0]) > 0) ifTrue: [self fail: 'DT_REL relocations (without addends) are not supported'].
	((dynamic at: 35 ifAbsent: [0]) > 0) ifTrue: [self fail: 'packed DT_RELR relocations are not supported: link without -z pack-relative-relocs / --pack-dyn-relocs=relr'].
	^Array streamContents: [:tables |
		((dynamic at: 8 ifAbsent: [0]) > 0) ifTrue: [
			tables nextPut: {self fileOffsetOf: (dynamic at: 7) size: (dynamic at: 8). dynamic at: 8. dynamic at: 9 ifAbsent: [24]}].
		((dynamic at: 2 ifAbsent: [0]) > 0) ifTrue: [
			(dynamic at: 20 ifAbsent: [7]) = 7 ifFalse: [self fail: 'PLT relocations of type DT_REL are not supported'].
			tables nextPut: {self fileOffsetOf: (dynamic at: 23) size: (dynamic at: 2). dynamic at: 2. 24}]]
!
dynamicEntries
	"Answer PT_DYNAMIC's entries as a Dictionary tag -> value (the first of each tag), nil if there is no PT_DYNAMIC."
	| phoff dict |
	phoff := self u64: 32.
	0 to: (self u16: 56) - 1 do: [:i |
		| ph |
		ph := phoff + (i * 56).
		(self u32: ph) = 2 ifTrue: [
			| offset size |
			offset := self u64: ph + 8.
			size := self u64: ph + 32.
			dict := Dictionary new.
			0 to: size - 16 by: 16 do: [:e |
				| tag |
				tag := self u64: offset + e.
				tag = 0 ifTrue: [^dict].
				(dict includesKey: tag) ifFalse: [dict at: tag put: (self u64: offset + e + 8)]].
			^dict]].
	^nil
!
relocationSections
	| shoff shnum |
	shoff := self u64: 40.
	shnum := self u16: 60.
	(shoff = 0 or: [shnum = 0]) ifTrue: [^#()].
	(self u16: 58) = 64 ifFalse: [self fail: 'unexpected section header size ', (self u16: 58) printString].
	^Array streamContents: [:tables |
		0 to: shnum - 1 do: [:i |
			| sh type allocated size |
			sh := shoff + (i * 64).
			type := self u32: sh + 4.
			allocated := ((self u64: sh + 8) bitAnd: 2) ~= 0.
			size := self u64: sh + 32.
			(allocated and: [size > 0]) ifTrue: [
				type = 9 ifTrue: [self fail: 'SHT_REL relocations (without addends) are not supported'].
				type = 4 ifTrue: [tables nextPut: {self u64: sh + 24. size. self u64: sh + 56}]]]]
!
isNoneRelocation: type
	^type = 0 or: [machine = 183 and: [type = 256]]
!
isRelativeRelocation: type
	^type = self relativeRelocationType
!
relativeRelocationType
	^machine = 62 ifTrue: [8] ifFalse: [1027]
!
relocationName: type
	machine = 62 ifTrue: [
		^#('R_X86_64_NONE' 'R_X86_64_64' 'R_X86_64_PC32' 'R_X86_64_GOT32' 'R_X86_64_PLT32' 'R_X86_64_COPY' 'R_X86_64_GLOB_DAT' 'R_X86_64_JUMP_SLOT' 'R_X86_64_RELATIVE') at: type + 1 ifAbsent: [
			type = 37 ifTrue: ['R_X86_64_IRELATIVE'] ifFalse: [(type between: 16 and: 19) ifTrue: ['a TLS relocation'] ifFalse: ['R_X86_64 type ', type printString]]]].
	type = 257 ifTrue: [^'R_AARCH64_ABS64'].
	type = 1024 ifTrue: [^'R_AARCH64_COPY'].
	type = 1025 ifTrue: [^'R_AARCH64_GLOB_DAT'].
	type = 1026 ifTrue: [^'R_AARCH64_JUMP_SLOT'].
	type = 1027 ifTrue: [^'R_AARCH64_RELATIVE'].
	type = 1032 ifTrue: [^'R_AARCH64_IRELATIVE'].
	(type between: 1028 and: 1031) ifTrue: [^'a TLS relocation'].
	^'R_AARCH64 type ', type printString
!
relocationBlocks
	"Answer the .reloc contents: per 4 KB page {page RVA. block size. DIR64 entries}, each block padded with an ABSOLUTE entry to a multiple of 4 bytes. Without relocations one block of two ABSOLUTE entries keeps the directory non-empty."
	| pages bytes at |
	pages := OrderedCollection new.
	relocationRvas do: [:rva |
		(pages isEmpty or: [pages last first ~= (rva bitClear: 4095)]) ifTrue: [pages add: {rva bitClear: 4095. OrderedCollection new}].
		pages last last add: (10 bitShift: 12) + (rva bitAnd: 4095)].
	pages isEmpty ifTrue: [pages add: {low + shift. OrderedCollection with: 0 with: 0}].
	pages do: [:p | p last size odd ifTrue: [p last add: 0]].
	bytes := ByteArray new: (pages inject: 0 into: [:sum :p | sum + 8 + (2 * p last size)]).
	at := 0.
	pages do: [:p |
		self put32: p first into: bytes at: at.
		self put32: 8 + (2 * p last size) into: bytes at: at + 4.
		at := at + 8.
		p last do: [:entryValue | self put16: entryValue into: bytes at: at. at := at + 2]].
	^bytes
! !

!UefiImageWriter methodsFor: 'writing the PE'!
image
	"Answer the PE32+ file: headers, .text (the segments), .reloc unless the relocations are stripped."
	| relocs sections sizeOfHeaders textRva textSize relocRva relocRaw sizeOfImage out pe opt |
	relocs := relocationsStripped ifFalse: [self relocationBlocks].
	sections := relocs isNil ifTrue: [1] ifFalse: [2].
	pe := 16r80.
	opt := pe + 4 + 20.
	sizeOfHeaders := self align: opt + 240 + (40 * sections) to: self fileAlignment.
	textRva := low + shift.
	textSize := high - low.
	relocRva := textRva + textSize.
	sizeOfImage := relocs isNil
		ifTrue: [relocRva]
		ifFalse: [relocRva + (self align: relocs size to: self sectionAlignment)].
	relocRaw := relocs isNil ifTrue: [0] ifFalse: [self align: relocs size to: self fileAlignment].
	out := ByteArray new: sizeOfHeaders + body size + relocRaw.
	self writeDosHeaderInto: out peOffset: pe.
	"PE signature and COFF file header"
	out replaceFrom: pe + 1 to: pe + 4 with: #[16r50 16r45 0 0] startingAt: 1.
	self put16: (machine = 62 ifTrue: [16r8664] ifFalse: [16rAA64]) into: out at: pe + 4.
	self put16: sections into: out at: pe + 6.
	self put16: 240 into: out at: pe + 20.
	"EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE, RELOCS_STRIPPED for an ET_EXEC"
	self put16: (16r22 bitOr: (relocationsStripped ifTrue: [1] ifFalse: [0])) into: out at: pe + 22.
	"PE32+ optional header"
	self put16: 16r20B into: out at: opt.
	self put32: body size into: out at: opt + 4.
	self put32: relocRaw into: out at: opt + 8.
	self put32: textSize - body size into: out at: opt + 12.
	self put32: entry + shift into: out at: opt + 16.
	self put32: textRva into: out at: opt + 20.
	self put64: imageBase into: out at: opt + 24.
	self put32: self sectionAlignment into: out at: opt + 32.
	self put32: self fileAlignment into: out at: opt + 36.
	self put32: sizeOfImage into: out at: opt + 56.
	self put32: sizeOfHeaders into: out at: opt + 60.
	self put16: 10 into: out at: opt + 68.
	self put64: 16r100000 into: out at: opt + 72.
	self put64: 16r1000 into: out at: opt + 80.
	self put64: 16r100000 into: out at: opt + 88.
	self put64: 16r1000 into: out at: opt + 96.
	self put32: 16 into: out at: opt + 108.
	relocs isNil ifFalse: [
		self put32: relocRva into: out at: opt + 112 + (5 * 8).
		self put32: relocs size into: out at: opt + 112 + (5 * 8) + 4].
	"Section table"
	self writeSection: '.text' into: out at: opt + 240
		virtualSize: textSize rva: textRva rawSize: body size rawOffset: sizeOfHeaders
		characteristics: 16rE0000060.
	relocs isNil ifFalse: [
		self writeSection: '.reloc' into: out at: opt + 240 + 40
			virtualSize: relocs size rva: relocRva rawSize: relocRaw rawOffset: sizeOfHeaders + body size
			characteristics: 16r42000040].
	out replaceFrom: sizeOfHeaders + 1 to: sizeOfHeaders + body size with: body startingAt: 1.
	relocs isNil ifFalse: [
		out replaceFrom: sizeOfHeaders + body size + 1 to: sizeOfHeaders + body size + relocs size with: relocs startingAt: 1].
	^out
!
writeDosHeaderInto: out peOffset: pe
	"An MZ header whose e_lfanew points at the PE signature, and the classic stub that says the program cannot run in DOS."
	| stub |
	out replaceFrom: 1 to: 2 with: #[16r4D 16r5A] startingAt: 1.
	self put16: 16r90 into: out at: 2.
	self put16: 3 into: out at: 4.
	self put16: 4 into: out at: 8.
	self put16: 16rFFFF into: out at: 12.
	self put16: 16rB8 into: out at: 16.
	self put16: 16r40 into: out at: 24.
	self put32: pe into: out at: 60.
	stub := #[16r0E 16r1F 16rBA 16r0E 16r00 16rB4 16r09 16rCD 16r21 16rB8 16r01 16r4C 16rCD 16r21] , 'This program cannot be run in DOS mode.' asByteArray , #[13 13 10 16r24].
	out replaceFrom: 16r41 to: 16r40 + stub size with: stub startingAt: 1
!
writeSection: name into: out at: offset virtualSize: virtualSize rva: rva rawSize: rawSize rawOffset: rawOffset characteristics: characteristics
	out replaceFrom: offset + 1 to: offset + name size with: name asByteArray startingAt: 1.
	self put32: virtualSize into: out at: offset + 8.
	self put32: rva into: out at: offset + 12.
	self put32: rawSize into: out at: offset + 16.
	self put32: rawOffset into: out at: offset + 20.
	self put32: characteristics into: out at: offset + 36
! !

!UefiImageWriter methodsFor: 'bytes'!
u16: offset
	"The little-endian unsigned integers of the ELF at 0-based byte offsets."
	offset + 2 > elf size ifTrue: [self truncated].
	^elf uint16At: offset + 1
!
u32: offset
	offset + 4 > elf size ifTrue: [self truncated].
	^elf uint32At: offset + 1
!
u64: offset
	offset + 8 > elf size ifTrue: [self truncated].
	^(elf uint32At: offset + 1) + ((elf uint32At: offset + 5) bitShift: 32)
!
s64: offset
	| v |
	v := self u64: offset.
	^v >= (1 bitShift: 63) ifTrue: [v - (1 bitShift: 64)] ifFalse: [v]
!
put16: value into: bytes at: offset
	bytes at: offset + 1 put: (value bitAnd: 255).
	bytes at: offset + 2 put: ((value bitShift: -8) bitAnd: 255)
!
put32: value into: bytes at: offset
	(value between: 0 and: 16rFFFFFFFF) ifFalse: [self fail: 'value ', (self hex: value), ' does not fit a 32-bit header field'].
	0 to: 3 do: [:i | bytes at: offset + i + 1 put: ((value bitShift: i * -8) bitAnd: 255)]
!
put64: value into: bytes at: offset
	0 to: 7 do: [:i | bytes at: offset + i + 1 put: ((value bitShift: i * -8) bitAnd: 255)]
!
align: n to: alignment
	^n + alignment - 1 // alignment * alignment
!
hex: anInteger
	^'0x', (anInteger printString: 16)
! !

!UefiImageWriter methodsFor: 'errors'!
fail: aString
	^Error signal: 'UefiImageWriter: ', aString
!
truncated
	^self fail: 'the ELF file is truncated'
! !
