Object subclass: #MachSection
	instanceVariableNames: 'name segment address size align type bytes relocations number'
	classVariableNames: ''
	package: 'VM-Translator'!

MachSection comment: 'A section of a MachObjectFile: its address in the object, size, alignment, type (S_ZEROFILL ...), bytes and relocations (MachRelocation).'!

!MachSection methodsFor: 'initialization'!
setName: aString segment: aSegmentName address: anAddress size: aSize align: anAlign type: aType
	name := aString.
	segment := aSegmentName.
	address := anAddress.
	size := aSize.
	align := anAlign.
	type := aType.
	relocations := #()
! !

!MachSection methodsFor: 'accessing'!
name
	^name
!
segment
	^segment
!
address
	^address
!
size
	^size
!
align
	^align
!
bytes
	"Zero-fill sections have no bytes in the file: zeros."
	^bytes ifNil: [ByteArray new: size]
!
bytes: aByteArray
	bytes := aByteArray
!
relocations
	^relocations
!
relocations: aCollection
	relocations := aCollection
!
number
	"Sections are numbered from 1 (symbols' n_sect, non-extern relocations)."
	^number
!
number: n
	number := n
!
isZeroFill
	"S_ZEROFILL, S_GB_ZEROFILL, S_THREAD_LOCAL_ZEROFILL"
	^#(1 12 18) includes: type
!
includes: anAddress
	^anAddress >= address and: [anAddress < (address + size)]
!
wordAt: offset
	"The little-endian 32-bit word at offset (0-based) in the section."
	^self bytes uint32At: offset + 1
!
printOn: aStream
	aStream nextPutAll: segment; nextPut: $,; nextPutAll: name
! !

Object subclass: #MachSymbol
	instanceVariableNames: 'name type section value'
	classVariableNames: ''
	package: 'VM-Translator'!

MachSymbol comment: 'A symbol (nlist_64) of a MachObjectFile: name, type bits (N_EXT, N_TYPE), section number (0: undefined) and value (its address).'!

!MachSymbol methodsFor: 'initialization'!
setName: aString type: aType section: aSection value: aValue
	name := aString.
	type := aType.
	section := aSection.
	value := aValue
! !

!MachSymbol methodsFor: 'accessing'!
name
	^name
!
section
	^section
!
value
	^value
!
isExternal
	^(type bitAnd: 1) ~= 0
!
isDefined
	"N_SECT"
	^(type bitAnd: 16r0E) = 16r0E
!
isUndefined
	^(type bitAnd: 16r0E) = 0
!
isDebug
	"N_STAB"
	^(type bitAnd: 16rE0) ~= 0
!
printOn: aStream
	aStream nextPutAll: name
! !

Object subclass: #MachRelocation
	instanceVariableNames: 'address info symbol'
	classVariableNames: ''
	package: 'VM-Translator'!

MachRelocation comment: 'A relocation_info of a MachObjectFile section: address (offset in the section), and from info its symbol (extern) or section number, pc-relative, length and type (ARM64_RELOC_UNSIGNED 0, SUBTRACTOR 1, BRANCH26 2, PAGE21 3, PAGEOFF12 4, GOT_LOAD_PAGE21 5, GOT_LOAD_PAGEOFF12 6, POINTER_TO_GOT 7, TLVP_LOAD_PAGE21 8, TLVP_LOAD_PAGEOFF12 9, ADDEND 10).'!

!MachRelocation class methodsFor: 'instance creation'!
address: anInteger info: aWord
	^self new setAddress: anInteger info: aWord
! !

!MachRelocation methodsFor: 'initialization'!
setAddress: anInteger info: aWord
	address := anInteger.
	info := aWord
! !

!MachRelocation methodsFor: 'accessing'!
address
	^address
!
index
	"The symbol's index (extern) or the section's number; ADDEND's addend."
	^info bitAnd: 16rFFFFFF
!
addend
	"ADDEND: the 24-bit signed addend of the next relocation."
	| v |
	v := self index.
	^v >= 16r800000 ifTrue: [v - 16r1000000] ifFalse: [v]
!
isPcRelative
	^((info bitShift: -24) bitAnd: 1) = 1
!
length
	"log2 of the size: 2 (4 bytes), 3 (8 bytes)"
	^(info bitShift: -25) bitAnd: 3
!
isExtern
	^((info bitShift: -27) bitAnd: 1) = 1
!
type
	^info bitShift: -28
!
typeName
	^#('UNSIGNED' 'SUBTRACTOR' 'BRANCH26' 'PAGE21' 'PAGEOFF12' 'GOT_LOAD_PAGE21' 'GOT_LOAD_PAGEOFF12' 'POINTER_TO_GOT' 'TLVP_LOAD_PAGE21' 'TLVP_LOAD_PAGEOFF12' 'ADDEND' 'AUTHENTICATED_POINTER') at: self type + 1 ifAbsent: ['?']
!
symbol
	^symbol
!
symbol: aMachSymbol
	symbol := aMachSymbol
!
printOn: aStream
	aStream nextPutAll: self typeName; space; print: address; space.
	symbol isNil ifTrue: [aStream nextPutAll: 'section '; print: self index] ifFalse: [aStream print: symbol]
! !

Object subclass: #MachObjectFile
	instanceVariableNames: 'bytes sections symbols hints'
	classVariableNames: ''
	package: 'VM-Translator'!

MachObjectFile comment: 'I read a 64-bit Mach-O object file (MH_OBJECT, arm64), as cc writes it: its sections, each with its bytes and relocations, its symbol table and the compiler''s linker optimization hints (which adrp and ldr make one GOT load the linker may relax). StencilTable makes the copy-and-patch stencil table of what I read.

	(MachObjectFile fromBytes: (File readBytes: ''jit_stencils.o'')) sections'!

!MachObjectFile class methodsFor: 'instance creation'!
fromBytes: aByteArray
	^self new setBytes: aByteArray
! !

!MachObjectFile methodsFor: 'initialization'!
setBytes: aByteArray
	| ncmds off cmd |
	bytes := aByteArray.
	(self u32: 0) = 16rFEEDFACF ifFalse: [^self error: 'not a 64-bit Mach-O file'].
	(self u32: 4) = 16r0100000C ifFalse: [^self error: 'not an arm64 Mach-O file'].
	(self u32: 12) = 1 ifFalse: [^self error: 'not an object file (MH_OBJECT)'].
	sections := OrderedCollection new.
	symbols := #().
	hints := OrderedCollection new.
	ncmds := self u32: 16.
	off := 32.
	ncmds timesRepeat: [
		cmd := self u32: off.
		cmd = 16r19 ifTrue: [self readSegmentAt: off].
		cmd = 2 ifTrue: [self readSymbolTableAt: off].
		cmd = 16r2E ifTrue: [self readHintsAt: off].
		off := off + (self u32: off + 4)].
	sections do: [:s | s relocations do: [:r | r isExtern ifTrue: [r symbol: (symbols at: r index + 1)]]]
!
readSegmentAt: off
	"LC_SEGMENT_64: its section_64 records."
	| n s |
	n := self u32: off + 64.
	s := off + 72.
	n timesRepeat: [
		| section reloff nreloc |
		section := MachSection new
			setName: (self nameAt: s) segment: (self nameAt: s + 16) address: (self u64: s + 32) size: (self u64: s + 40)
			align: (1 bitShift: (self u32: s + 52)) type: ((self u32: s + 64) bitAnd: 16rFF).
		section isZeroFill ifFalse: [section bytes: (bytes copyFrom: (self u32: s + 48) + 1 to: (self u32: s + 48) + section size)].
		reloff := self u32: s + 56.
		nreloc := self u32: s + 60.
		section relocations: ((0 to: nreloc - 1) collect: [:i | MachRelocation address: (self i32: reloff + (8 * i)) info: (self u32: reloff + (8 * i) + 4)]).
		section number: sections size + 1.
		sections add: section.
		s := s + 80]
!
readHintsAt: off
	"LC_LINKER_OPTIMIZATION_HINT: ULEB128 kind, count, addresses; a kind 0 ends it."
	| p end kind n args |
	p := Array with: (self u32: off + 8).
	end := (p at: 1) + (self u32: off + 12).
	[(p at: 1) < end and: [(kind := self uleb: p) ~= 0]] whileTrue: [
		n := self uleb: p.
		args := (1 to: n) collect: [:i | self uleb: p].
		hints add: kind -> args]
!
uleb: aCursor
	"The ULEB128 at aCursor's offset (its first element), which moves past it."
	| v shift b |
	v := 0.
	shift := 0.
	[b := bytes at: (aCursor at: 1) + 1.
	 aCursor at: 1 put: (aCursor at: 1) + 1.
	 v := v + ((b bitAnd: 127) bitShift: shift).
	 shift := shift + 7.
	 b >= 128] whileTrue.
	^v
!
readSymbolTableAt: off
	"LC_SYMTAB: the nlist_64 records and their names."
	| symoff nsyms stroff |
	symoff := self u32: off + 8.
	nsyms := self u32: off + 12.
	stroff := self u32: off + 16.
	symbols := (0 to: nsyms - 1) collect: [:i |
		| e |
		e := symoff + (16 * i).
		MachSymbol new setName: (self cStringAt: stroff + (self u32: e)) type: (bytes at: e + 5) section: (bytes at: e + 6) value: (self u64: e + 8)]
! !

!MachObjectFile methodsFor: 'accessing'!
sections
	^sections
!
symbols
	^symbols
!
hints
	"kind -> addresses: LOH_ARM64_ADRP_LDR_GOT 8 (adrp, ldr), ADRP_LDR_GOT_LDR 4 and ADRP_LDR_GOT_STR 6 (adrp, ldr, the access) ..."
	^hints
!
gotLoadPairs
	"adrp address -> ldr address of the GOT loads the compiler marked as relaxable."
	| d |
	d := Dictionary new.
	hints do: [:h | (#(4 6 8) includes: h key) ifTrue: [d at: (h value at: 1) put: (h value at: 2)]].
	^d
!
section: aSegmentName named: aSectionName
	^sections detect: [:s | s segment = aSegmentName and: [s name = aSectionName]] ifNone: [nil]
!
sectionNumbered: n
	^sections at: n
! !

!MachObjectFile methodsFor: 'reading'!
u32: offset
	"The little-endian 32-bit word at offset (0-based)."
	^bytes uint32At: offset + 1
!
i32: offset
	| v |
	v := self u32: offset.
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
!
u64: offset
	^(self u32: offset) + ((self u32: offset + 4) bitShift: 32)
!
nameAt: offset
	"A 16-byte, NUL-padded name."
	| end |
	end := offset.
	[end < (offset + 16) and: [(bytes at: end + 1) ~= 0]] whileTrue: [end := end + 1].
	^(bytes copyFrom: offset + 1 to: end) asString
!
cStringAt: offset
	| end |
	end := offset.
	[(bytes at: end + 1) ~= 0] whileTrue: [end := end + 1].
	^(bytes copyFrom: offset + 1 to: end) asString
! !
