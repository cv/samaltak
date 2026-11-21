TestCase subclass: #SHA256Test
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

SHA256Test comment: 'SHA256 against FIPS 180-4''s examples (one block, two blocks, a million a''s), messages of every length around the padding''s boundaries, incremental hashing split at every byte, digest that goes on, copy.'!

!SHA256Test methodsFor: 'support'!
bytesTo: n
	| b |
	b := ByteArray new: n.
	1 to: n do: [:i | b at: i put: i - 1 \\ 256].
	^b
!
lengthVectors
	"n and the digest of the bytes 0, 1, 2, ... (mod 256), n of them."
	^#(
		0 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		1 '6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d'
		55 '463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59'
		56 'da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562'
		57 '2fe741af801cc238602ac0ec6a7b0c3a8a87c7fc7d7f02a3fe03d1c12eac4d8f'
		63 '29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488'
		64 'fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108'
		65 '4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781'
		119 'da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6'
		120 'f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c'
		127 '92ca0fa6651ee2f97b884b7246a562fa71250fedefe5ebf270d31c546bfea976'
		128 '471fb943aa23c511f6f72f8d1652d9c880cfa392ad80503120547703e56a2be5'
		129 '5099c6a56203f9687f7d33f4bfdf576d31dc91f6b695ecea38b2770c87631135'
		200 '1901da1c9f699b48f6b2636e65cbf73abf99d0441ef67f5c540a42f7051dec6f')
! !

!SHA256Test methodsFor: 'tests'!
testFipsOneBlock
	self assert: (SHA256 hash: 'abc') equals: (ByteArray fromHex: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
!
testFipsTwoBlocks
	self assert: (SHA256 hash: 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq') equals: (ByteArray fromHex: '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')
!
testFipsMillionA
	| h chunk |
	h := SHA256 new.
	chunk := ByteArray new: 1000 withAll: $a value.
	1000 timesRepeat: [h update: chunk].
	self assert: h digest equals: (ByteArray fromHex: 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0')
!
testEmpty
	self assert: (SHA256 hash: #[]) equals: (ByteArray fromHex: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
!
testSizes
	self assert: SHA256 digestSize equals: 32.
	self assert: SHA256 blockSize equals: 64
!
testLengthsAroundPadding
	self lengthVectors pairsDo: [:n :hex |
		self assert: (SHA256 hash: (self bytesTo: n)) equals: (ByteArray fromHex: hex)]
!
testIncrementalSplits
	| m expected h |
	m := self bytesTo: 200.
	expected := SHA256 hash: m.
	0 to: m size do: [:i |
		h := SHA256 new.
		h update: (m copyFrom: 1 to: i); update: m from: i + 1 to: m size.
		self assert: h digest equals: expected]
!
testDigestGoesOn
	| h a |
	h := SHA256 new.
	h update: 'ab'.
	a := h digest.
	self assert: a equals: (SHA256 hash: 'ab').
	self assert: h digest equals: a.
	h update: 'c'.
	self assert: h digest equals: (SHA256 hash: 'abc')
!
testCopy
	| h c |
	h := SHA256 new update: (self bytesTo: 100); yourself.
	c := h copy.
	h update: 'x'.
	c update: 'y'.
	self assert: h digest equals: (SHA256 hash: (self bytesTo: 100), 'x' asByteArray).
	self assert: c digest equals: (SHA256 hash: (self bytesTo: 100), 'y' asByteArray)
!
testReset
	| h |
	h := SHA256 new update: 'garbage'; yourself.
	h reset.
	self assert: (h update: 'abc'; digest) equals: (SHA256 hash: 'abc')
! !
