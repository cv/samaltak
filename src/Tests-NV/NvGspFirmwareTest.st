TestCase subclass: #NvGspFirmwareTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspFirmwareTest comment: 'Tests NvElf and NvGspFirmware''s loading on a gsp_ga10x.bin made here (a RISC-V ELF with .fwimage, .fwversion and signature sections, as the real one has): the GB10B signature section is the one taken, the version and the descriptor are checked, and problems says what is wrong. NvGspFirmwareFileTest reads the real files (make test-nv). Needs no GPU.'!

!NvGspFirmwareTest class methodsFor: 'fixtures'!
elfWith: sections
	"A little-endian ELF64 (machine RISC-V, 243) of {name. bytes} sections, its section headers last."
	| strtab names data offsets out shoff all |
	all := sections, {{'.shstrtab'. nil}}.
	strtab := WriteStream on: ByteArray new.
	strtab nextPut: 0.
	names := all collect: [:s | | at | at := strtab position. strtab nextPutAll: s first asByteArray; nextPut: 0. at].
	strtab := strtab contents.
	data := all collect: [:s | s last ifNil: [strtab]].
	out := ByteArray new: 64.
	offsets := OrderedCollection new.
	data do: [:d | offsets add: out size. out := out, d].
	shoff := out size + 7 // 8 * 8.
	out := out, (ByteArray new: shoff - out size), (ByteArray new: 64 * (all size + 1)).
	out replaceFrom: 1 to: 6 with: #[127 69 76 70 2 1] startingAt: 1.
	out uint16At: 16r10 + 1 put: 1; uint16At: 16r12 + 1 put: 243.
	out uint32At: 16r28 + 1 put: shoff.
	out uint16At: 16r3A + 1 put: 64; uint16At: 16r3C + 1 put: all size + 1; uint16At: 16r3E + 1 put: all size.
	all doWithIndex: [:s :i | | h |
		h := shoff + (64 * i) + 1.
		out uint32At: h put: (names at: i); uint32At: h + 4 put: (s last isNil ifTrue: [3] ifFalse: [1]).
		out uint32At: h + 24 put: (offsets at: i); uint32At: h + 32 put: (data at: i) size].
	^out
!
firmwareFrom: elf
	| boot |
	boot := NvGspBootTest firmware.
	^NvGspFirmware gspBin: elf fmcImage: boot fmcImage hash: boot fmcHash signature: boot fmcSignature publicKey: boot fmcPublicKey
		bootImage: boot bootImage descriptor: boot bootDescriptor bytes
! !

!NvGspFirmwareTest methodsFor: 'tests'!
testElfSections
	| elf |
	elf := NvElf on: (self class elfWith: {{'.fwimage'. #[1 2 3 4 5]}. {'.fwversion'. '580.178.04' asByteArray, #[0]}}).
	self assert: elf machine equals: 243.
	self assert: elf sectionNames asArray equals: #('' '.fwimage' '.fwversion' '.shstrtab').
	self assert: (elf sectionNamed: '.fwimage') equals: #[1 2 3 4 5].
	self assert: (elf sectionNamed: '.nothing') isNil.
	self should: [NvElf on: #[1 2 3]] raise: Error
!
testLoading
	| f |
	f := self class firmwareFrom: (self class elfWith: {
		{'.fwimage'. ByteArray new: 9000 withAll: 9}.
		{'.fwversion'. '580.178.04' asByteArray, #[0]}.
		{'.fwsignature_ga10x'. ByteArray new: 4096 withAll: 1}.
		{'.fwsignature_cc_gb10x'. ByteArray new: 4096 withAll: 2}.
		{'.fwsignature_gb10y'. ByteArray new: 4096 withAll: 3}}).
	self assert: f gspVersion equals: '580.178.04'.
	self assert: f gspImage size equals: 9000.
	self assert: (f gspSignature allSatisfy: [:b | b = 3]).
	self assert: (f bootDescriptor at: 'appVersion') equals: 16r3456.
	self assert: f problems isEmpty.
	"It boots, against the fake GB10."
	[:memory | [(NvGspBoot registers: (NvFakeGb10 memory: memory firmware: f) memory: memory firmware: f) sysmemHeapSize: 4096; boot]
		ensure: [memory release]] value: NvFakeDmaMemory new
!
testWhatIsWrong
	| f |
	self should: [self class firmwareFrom: (self class elfWith: {{'.fwversion'. #[0]}})] raise: Error.
	self should: [self class firmwareFrom: (self class elfWith: {{'.fwimage'. #[1]}. {'.fwversion'. #[0]}. {'.fwsignature_gb10x'. #[1]}})] raise: Error.
	f := self class firmwareFrom: (self class elfWith: {{'.fwimage'. #[1]}. {'.fwversion'. '570.144' asByteArray, #[0]}. {'.fwsignature_gb10y'. #[1]}}).
	self assert: f problems asArray equals: #('GSP-RM is version ''570.144'', not 580.178.04')
! !
