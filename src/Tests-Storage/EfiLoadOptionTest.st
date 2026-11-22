TestCase subclass: #EfiLoadOptionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Storage'!

EfiLoadOptionTest comment: 'EfiLoadOption: the bytes of a Boot#### value with an HD() node and a file path, as efibootmgr writes them, and parsed back.'!

!EfiLoadOptionTest methodsFor: 'helpers'!
esp
	^GptPartition number: 1 type: (GptDisk guidBytes: GptDisk efiSystemType) unique: (GptDisk guidBytes: '01234567-89ab-cdef-0123-456789abcdef') first: 2048 last: 133119 name: 'EFI'
! !

!EfiLoadOptionTest methodsFor: 'tests'!
testBytes
	| o b |
	o := EfiLoadOption description: 'Sam' partition: self esp file: '\EFI\x'.
	b := o bytes.
	self assert: (b copyFrom: 1 to: 4) equals: #[1 0 0 0].
	self assert: (b uint16At: 5) equals: 42 + 18 + 4.
	self assert: (b copyFrom: 7 to: 14) equals: #[83 0 97 0 109 0 0 0].
	self assert: (b copyFrom: 15 to: 22) equals: #[4 1 42 0 1 0 0 0].
	self assert: (b uint64At: 23) equals: 2048.
	self assert: (b uint64At: 31) equals: 131072.
	self assert: (b copyFrom: 39 to: 54) equals: (GptDisk guidBytes: '01234567-89ab-cdef-0123-456789abcdef').
	self assert: (b copyFrom: 55 to: 56) equals: #[2 2].
	self assert: (b copyFrom: 57 to: 60) equals: #[4 4 18 0].
	self assert: (b copyFrom: 61 to: 72) equals: #[92 0 69 0 70 0 73 0 92 0 120 0].
	self assert: (b copyFrom: b size - 3 to: b size) equals: #[16r7F 16rFF 4 0].
	self assert: b size equals: 6 + 8 + 64
!
testParsesBack
	| o p |
	o := EfiLoadOption description: 'Samaltak' partition: self esp file: '/EFI/samaltak/BOOTAA64.EFI'.
	p := EfiLoadOption fromBytes: o bytes.
	self assert: p description equals: 'Samaltak'.
	self assert: p isActive.
	self assert: p filePath equals: '\EFI\samaltak\BOOTAA64.EFI'.
	self assert: (p isFile: '\efi\SAMALTAK\bootaa64.efi').
	self assert: p partitionNumber equals: 1.
	self assert: p partitionGuid equals: self esp uniqueGuid.
	self assert: p bytes equals: o bytes.
	self assert: (EfiLoadOption fromBytes: #[1 0]) isNil
! !
