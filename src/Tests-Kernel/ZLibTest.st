TestCase subclass: #ZLibTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ZLibTest comment: 'I check ZLib: Python''s zlib stream of ''hello world'' decoded and reproduced byte for byte, round trips of empty, short, repetitive, random and mixed data (across 65536-token blocks and at distances near 32 KB), the block type chosen by size (dynamic for repetitive data, stored for random), the Adler-32 checksum, and corrupt streams refused.'!

!ZLibTest methodsFor: 'tests'!
testPythonHelloWorld
	"zlib.compress(b''hello world''): one fixed Huffman block."
	| z |
	z := #[16r78 16r9C 16rCB 16r48 16rCD 16rC9 16rC9 16r57 16r28 16rCF 16r2F 16rCA 16r49 16r01 16r00 16r1A 16r0B 16r04 16r5D].
	self assert: (ZLib decompress: z) asString equals: 'hello world'.
	self assert: (ZLib compress: 'hello world' asByteArray) equals: z
!
testShortRoundTrips
	#('' 'a' 'ab' 'abc' 'aaaa' 'hello hello hello hello') do: [:each |
		self assert: (ZLib decompress: (ZLib compress: each asByteArray)) equals: each asByteArray]
!
testRepetitiveDataIsDynamic
	| data z |
	data := ByteArray new: 200000.
	1 to: data size do: [:i | data at: i put: i \\ 37 * 5 + (i // 5000) \\ 256].
	z := ZLib compress: data.
	self assert: z size < 4000.
	self assert: ((z at: 3) bitShift: -1) \\ 4 equals: 2.
	self assert: (ZLib decompress: z) equals: data
!
testRandomDataIsStored
	| data z |
	data := self randomBytes: 100000 seed: 7.
	z := ZLib compress: data.
	"zlib header and checksum, and five bytes per stored block of at most 65535 bytes"
	self assert: z size <= (data size + 6 + 15).
	self assert: ((z at: 3) bitShift: -1) \\ 4 equals: 0.
	self assert: (ZLib decompress: z) equals: data
!
testMixedDataAcrossBlocks
	"Runs, random stretches and copies from almost 32 KB back, in more than one block of tokens."
	| random data z |
	random := self randomBytes: 40000 seed: 3.
	data := ByteArray new: 400000.
	1 to: data size do: [:i |
		data at: i put: (i \\ 1000 < 400
			ifTrue: [random at: i \\ 32760 + 1]
			ifFalse: [i \\ 1000 < 700 ifTrue: [0] ifFalse: [random at: i \\ 997 + 1]])].
	z := ZLib compress: data.
	self assert: z size < (data size // 2).
	self assert: (ZLib decompress: z) equals: data
!
testAdler32
	self assert: (ZLib adler32Of: 'Wikipedia' asByteArray) equals: 16r11E60398.
	self assert: (ZLib adler32Of: ByteArray new) equals: 1
!
testCorruptStreamsAreRefused
	| z |
	z := ZLib compress: 'hello hello hello hello' asByteArray.
	self should: [ZLib decompress: (z copyFrom: 1 to: z size - 1)] raise: Error.
	self should: [ZLib decompress: (z copy at: z size put: ((z at: z size) bitXor: 1); yourself)] raise: Error.
	self should: [ZLib decompress: (z copy at: 1 put: 16r79; yourself)] raise: Error.
	self should: [ZLib decompress: #[16r78 16r9C 16rFF 16rFF 16rFF 16rFF 16rFF 16rFF]] raise: Error
! !

!ZLibTest methodsFor: 'support'!
randomBytes: n seed: anInteger
	| random bytes |
	random := Random seed: anInteger.
	bytes := ByteArray new: n.
	1 to: n do: [:i | bytes at: i put: (random nextInt: 256) - 1].
	^bytes
! !
