Object subclass: #NvCubin
	instanceVariableNames: 'bytes sections symbols'
	classVariableNames: ''
	package: 'System-NV'!

NvCubin comment: 'I read a cubin: the ELF file nvcc -cubin makes, NVIDIA GPU machine code for one SM version (nvcc -cubin -arch=sm_121 for the GB10). I answer its sections, its kernels and, for each, an NvKernel: code, registers, shared memory, stack, parameters and constant banks, from the .text.<kernel>, .nv.info, .nv.info.<kernel>, .nv.shared.<kernel>, .nv.constant0.<kernel> and .nv.constant<N> sections.

	cubin := NvCubin on: aByteArray.
	cubin kernelNames.                  "#(''fill'' ''vadd'')"
	(cubin kernelNamed: ''vadd'') parameters    "#(#(0 0 8) #(1 8 8) #(2 16 8) #(3 24 4))"

.nv.info holds attributes (EIATTR_*): a format byte (1 none, 2 byte, 3 16-bit, 4 sized blob), an attribute byte, then a 16-bit value or a 16-bit size and that many bytes; info:do: walks them.'!

!NvCubin methodsFor: 'initialization'!
setBytes: aByteArray
	bytes := aByteArray.
	self readSections.
	self readSymbols
! !

!NvCubin methodsFor: 'accessing'!
bytes
	^bytes
!
sections
	^sections
!
section: aName
	^sections detect: [:s | s name = aName] ifNone: [nil]
!
symbols
	"(name value size info sectionIndex) for each symbol, in symbol table order (index 0 first)."
	^symbols
!
smVersion
	"The SM version the code is for: e_flags bits 8..15 (121 for sm_121)."
	^((self u32: 16r30) bitShift: -8) bitAnd: 255
!
kernelNames
	"The names of my kernels (global functions), sorted."
	^((symbols select: [:s | ((s at: 4) bitAnd: 15) = 2 and: [((s at: 4) bitShift: -4) = 1]])
		collect: [:s | s at: 1]) asSortedCollection asArray
!
kernelNamed: aString
	"An NvKernel for the kernel aString; error if I have none."
	| text kernel symbolIndex params shared bank0 relocs |
	text := self section: '.text.', aString.
	text isNil ifTrue: [^self error: 'no kernel ', aString, ' in the cubin'].
	symbolIndex := symbols findFirst: [:s | (s at: 1) = aString].
	kernel := NvKernel new setName: aString code: text data.
	kernel smVersion: self smVersion.
	kernel cubin: bytes.
	self info: '.nv.info' do: [:attr :value |
		"Function attributes: (symbol index, value)."
		((value isKindOf: ByteArray) and: [value size >= 8 and: [(value uint32At: 1) = (symbolIndex - 1)]]) ifTrue: [
			attr = 16r2F ifTrue: [kernel registerCount: (value uint32At: 5)].
			attr = 16r11 ifTrue: [kernel frameSize: (value uint32At: 5)].
			attr = 16r12 ifTrue: [kernel minStackSize: (value uint32At: 5)]]].
	params := OrderedCollection new.
	self info: '.nv.info.', aString do: [:attr :value |
		attr = 16r17 ifTrue: [
			params add: (Array
				with: (value uint16At: 5)
				with: (value uint16At: 7)
				with: ((value uint32At: 9) bitShift: -18))].
		attr = 16r0A ifTrue: [kernel parameterOffset: (value uint16At: 5) size: (value uint16At: 7)].
		attr = 16r05 ifTrue: [kernel maxThreads: (value uint32At: 1) * (value uint32At: 5) * (value uint32At: 9)].
		attr = 16r1C ifTrue: [kernel exitOffsets: ((1 to: value size // 4) collect: [:i | value uint32At: i * 4 - 3])]].
	kernel parameters: (params asSortedCollection: [:a :b | (a at: 1) <= (b at: 1)]) asArray.
	shared := self section: '.nv.shared.', aString.
	shared notNil ifTrue: [kernel sharedSize: shared size].
	bank0 := self section: '.nv.constant0.', aString.
	bank0 notNil ifTrue: [kernel constantBanks at: 0 put: bank0 data].
	"The other banks: .nv.constantN, the cubin's (__constant__ data, shared by its kernels), and .nv.constantN.<kernel>,
	the kernel's own (constants the compiler placed there: a switch's jump table)."
	sections do: [:s | | rest dot n |
		(s name beginsWith: '.nv.constant') ifTrue: [
			rest := s name copyFrom: 13 to: s name size.
			dot := rest indexOf: $..
			n := dot = 0
				ifTrue: [rest asNumber]
				ifFalse: [(rest copyFrom: dot + 1 to: rest size) = aString ifTrue: [(rest copyFrom: 1 to: dot - 1) asNumber]].
			(n isInteger and: [n > 0]) ifTrue: [kernel constantBanks at: n put: s data]]].
	relocs := OrderedCollection new.
	#('.rela.text.' '.rel.text.') do: [:prefix | | r |
		r := self section: prefix, aString.
		(r notNil and: [r entrySize > 0]) ifTrue: [
			0 to: r size // r entrySize - 1 do: [:i | | at |
				at := i * r entrySize + 1.
				relocs add: (Array with: (self u64In: r data at: at) with: (self u64In: r data at: at + 8))]]].
	kernel relocations: relocs asArray.
	self bankRelocationsFor: aString into: kernel.
	^kernel
!
bankRelocationsFor: aString into: aKernel
	"The relocations of the constant banks aKernel uses (.rela.nv.constantN, the cubin's, and .rela.nv.constantN.<kernel>):
	(bank offset section value type), the 64-bit address of value bytes into the data section (.nv.global.init: libdevice's
	tables, such as sinf's for large arguments; .nv.global: zeroes) to be written at offset; and that data."
	| out |
	out := OrderedCollection new.
	sections do: [:s | | rest dot bank |
		(s name beginsWith: '.rela.nv.constant') ifTrue: [
			rest := s name copyFrom: 18 to: s name size.
			dot := rest indexOf: $..
			bank := dot = 0
				ifTrue: [rest asNumber]
				ifFalse: [(rest copyFrom: dot + 1 to: rest size) = aString ifTrue: [(rest copyFrom: 1 to: dot - 1) asNumber]].
			(bank isInteger and: [s entrySize > 0]) ifTrue: [
				0 to: s size // s entrySize - 1 do: [:i | | at info sym target addend |
					at := i * s entrySize + 1.
					info := self u64In: s data at: at + 8.
					addend := self u64In: s data at: at + 16.
					addend >= (1 bitShift: 63) ifTrue: [addend := addend - (1 bitShift: 64)].
					sym := symbols at: (info bitShift: -32) + 1.
					target := sections at: (sym at: 5) + 1.
					out add: (Array with: bank with: (self u64In: s data at: at) with: target name with: (sym at: 2) + addend with: (info bitAnd: 16rFFFFFFFF)).
					(aKernel globals includesKey: target name) ifFalse: [
						aKernel globals at: target name put: (target type = 8 ifTrue: [ByteArray new: target size] ifFalse: [target data])]]]]].
	aKernel bankRelocations: out asArray
!
info: aSectionName do: aBlock
	"Evaluate aBlock with each attribute of the .nv.info section aSectionName and its value: an Integer, or a
	ByteArray for sized ones. Nothing if there is no such section."
	| s d at format attr n |
	s := self section: aSectionName.
	s isNil ifTrue: [^self].
	d := s data.
	at := 1.
	[at + 3 <= d size] whileTrue: [
		format := d at: at.
		attr := d at: at + 1.
		n := d uint16At: at + 2.
		format = 4
			ifTrue: [aBlock value: attr value: (d copyFrom: at + 4 to: at + 3 + n). at := at + 4 + n]
			ifFalse: [aBlock value: attr value: n. at := at + 4]]
! !

!NvCubin methodsFor: 'reading'!
u16: offset
	^bytes uint16At: offset + 1
!
u32: offset
	^bytes uint32At: offset + 1
!
u64: offset
	^(self u32: offset) + ((self u32: offset + 4) bitShift: 32)
!
u64In: aByteArray at: index
	^(aByteArray uint32At: index) + ((aByteArray uint32At: index + 4) bitShift: 32)
!
cString: offset
	| end |
	end := offset + 1.
	[(bytes at: end) ~= 0] whileTrue: [end := end + 1].
	^(bytes copyFrom: offset + 1 to: end - 1) asString
!
readSections
	| shoff shentsize shnum shstrndx headers names |
	(bytes size >= 64 and: [(bytes copyFrom: 1 to: 4) = #[127 69 76 70]]) ifFalse: [^self error: 'not an ELF file'].
	((bytes at: 5) = 2 and: [(bytes at: 6) = 1]) ifFalse: [^self error: 'not a little-endian 64-bit ELF file'].
	(self u16: 16r12) = 190 ifFalse: [^self error: 'not CUDA code (ELF machine ', (self u16: 16r12) printString, ')'].
	shoff := self u64: 16r28.
	shentsize := self u16: 16r3A.
	shnum := self u16: 16r3C.
	shstrndx := self u16: 16r3E.
	headers := (0 to: shnum - 1) collect: [:i | shoff + (i * shentsize)].
	names := self u64: (headers at: shstrndx + 1) + 24.
	sections := headers collect: [:h | | type off size |
		type := self u32: h + 4.
		off := self u64: h + 24.
		size := self u64: h + 32.
		NvElfSection new
			setName: (self cString: names + (self u32: h))
			type: type
			flags: (self u64: h + 8)
			address: (self u64: h + 16)
			offset: off
			size: size
			link: (self u32: h + 40)
			info: (self u32: h + 44)
			entrySize: (self u64: h + 56)
			data: (type = 8 ifTrue: [ByteArray new] ifFalse: [bytes copyFrom: off + 1 to: off + size])]
!
readSymbols
	| symtab strtab d |
	symtab := sections detect: [:s | s type = 2] ifNone: [nil].
	symtab isNil ifTrue: [symbols := #(). ^self].
	strtab := sections at: symtab link + 1.
	d := symtab data.
	symbols := (0 to: d size // 24 - 1) collect: [:i | | at nameOffset end |
		at := i * 24 + 1.
		nameOffset := (d uint32At: at) + 1.
		end := nameOffset.
		[(strtab data at: end) ~= 0] whileTrue: [end := end + 1].
		Array
			with: (strtab data copyFrom: nameOffset to: end - 1) asString
			with: (self u64In: d at: at + 8)
			with: (self u64In: d at: at + 16)
			with: (d at: at + 4)
			with: (d uint16At: at + 6)]
! !

!NvCubin class methodsFor: 'instance creation'!
on: aByteArray
	^self new setBytes: aByteArray
! !
