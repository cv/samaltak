Object subclass: #NvElf
	instanceVariableNames: 'bytes sections'
	classVariableNames: ''
	package: 'System-NV'!

NvElf comment: 'I read the sections of a little-endian 64-bit ELF file, any machine (gsp_ga10x.bin is a RISC-V relocatable file: GSP-RM''s image, version and signatures as sections; NvCubin reads cubins). sectionNamed: answers a section''s bytes, nil if there is none.

	(NvElf on: (File readBytes: ''/lib/firmware/nvidia/580.178.04/gsp_ga10x.bin'')) sectionNames'!

!NvElf class methodsFor: 'instance creation'!
on: aByteArray
	^self new setBytes: aByteArray
! !

!NvElf methodsFor: 'initialization'!
setBytes: aByteArray
	| shoff shentsize shnum names |
	bytes := aByteArray.
	(bytes size >= 64 and: [(bytes copyFrom: 1 to: 4) = #[127 69 76 70]]) ifFalse: [^self error: 'not an ELF file'].
	((bytes at: 5) = 2 and: [(bytes at: 6) = 1]) ifFalse: [^self error: 'not a little-endian 64-bit ELF file'].
	shoff := self u64: 16r28.
	shentsize := self u16: 16r3A.
	shnum := self u16: 16r3C.
	shoff + (shnum * shentsize) > bytes size ifTrue: [^self error: 'ELF section headers past the end of the file'].
	names := self u64: shoff + ((self u16: 16r3E) * shentsize) + 24.
	sections := (0 to: shnum - 1) collect: [:i | | h off size |
		h := shoff + (i * shentsize).
		off := self u64: h + 24.
		size := self u64: h + 32.
		((self u32: h + 4) ~= 8 and: [off + size > bytes size]) ifTrue: [^self error: 'ELF section ', i printString, ' past the end of the file'].
		Array with: (self cString: names + (self u32: h)) with: (self u32: h + 4) with: off with: size]
! !

!NvElf methodsFor: 'accessing'!
machine
	^self u16: 16r12
!
sectionNames
	^sections collect: [:s | s first]
!
sectionNamed: aString
	"The bytes of the section named aString, or nil."
	sections do: [:s | (s first = aString and: [(s at: 2) ~= 8]) ifTrue: [^bytes copyFrom: (s at: 3) + 1 to: (s at: 3) + (s at: 4)]].
	^nil
! !

!NvElf methodsFor: 'private'!
u16: offset
	^bytes uint16At: offset + 1
!
u32: offset
	^bytes uint32At: offset + 1
!
u64: offset
	^(self u32: offset) + ((self u32: offset + 4) bitShift: 32)
!
cString: offset
	| end |
	end := offset + 1.
	[end <= bytes size and: [(bytes at: end) ~= 0]] whileTrue: [end := end + 1].
	^(bytes copyFrom: offset + 1 to: end - 1) asString
! !
