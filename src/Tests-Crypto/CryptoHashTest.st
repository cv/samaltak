TestCase subclass: #CryptoHashTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

CryptoHashTest comment: 'What every CryptoHash must do, for each subclass of mine (its hashClass): FIPS 180-4''s examples (one block, two blocks, a million a''s), the empty message, messages of every length around the padding''s boundaries (from Python''s hashlib), incremental hashing split at every byte and in small pieces, digest that goes on, copy, reset, Strings as UTF-8.'!

!CryptoHashTest class methodsFor: 'testing'!
isAbstract
	^self == CryptoHashTest
! !

!CryptoHashTest methodsFor: 'vectors'!
hashClass
	^self subclassResponsibility
!
oneBlockDigest
	"Of 'abc'."
	^self subclassResponsibility
!
twoBlockMessage
	^self subclassResponsibility
!
twoBlockDigest
	^self subclassResponsibility
!
millionADigest
	^self subclassResponsibility
!
emptyDigest
	^self subclassResponsibility
!
lengthVectors
	"n and the digest of the bytes 0, 1, 2, ... (mod 256), n of them."
	^self subclassResponsibility
!
sizes
	"digestSize and blockSize."
	^self subclassResponsibility
! !

!CryptoHashTest methodsFor: 'support'!
bytesTo: n
	| b |
	b := ByteArray new: n.
	1 to: n do: [:i | b at: i put: i - 1 \\ 256].
	^b
! !

!CryptoHashTest methodsFor: 'tests'!
testFipsOneBlock
	self assert: (self hashClass hash: 'abc') equals: (ByteArray fromHex: self oneBlockDigest)
!
testFipsTwoBlocks
	self assert: (self hashClass hash: self twoBlockMessage) equals: (ByteArray fromHex: self twoBlockDigest)
!
testFipsMillionA
	| h chunk |
	h := self hashClass new.
	chunk := ByteArray new: 1000 withAll: $a value.
	1000 timesRepeat: [h update: chunk].
	self assert: h digest equals: (ByteArray fromHex: self millionADigest)
!
testEmpty
	self assert: (self hashClass hash: #[]) equals: (ByteArray fromHex: self emptyDigest).
	self assert: self hashClass new digest equals: (ByteArray fromHex: self emptyDigest)
!
testSizes
	self assert: {self hashClass digestSize. self hashClass blockSize} equals: self sizes.
	self assert: (self hashClass hash: 'x') size equals: self hashClass digestSize
!
testLengthsAroundPadding
	self lengthVectors pairsDo: [:n :hex |
		self assert: (self hashClass hash: (self bytesTo: n)) equals: (ByteArray fromHex: hex)]
!
testIncrementalSplits
	| m expected h |
	m := self bytesTo: 300.
	expected := self hashClass hash: m.
	0 to: m size do: [:i |
		h := self hashClass new.
		h update: (m copyFrom: 1 to: i); update: m from: i + 1 to: m size.
		self assert: h digest equals: expected]
!
testManySmallUpdates
	| m h |
	m := self bytesTo: 1000.
	h := self hashClass new.
	1 to: m size by: 7 do: [:i | h update: m from: i to: (i + 6 min: m size)].
	self assert: h digest equals: (self hashClass hash: m)
!
testDigestGoesOn
	| h a |
	h := self hashClass new.
	h update: 'ab'.
	a := h digest.
	self assert: a equals: (self hashClass hash: 'ab').
	self assert: h digest equals: a.
	h update: 'c'.
	self assert: h digest equals: (ByteArray fromHex: self oneBlockDigest)
!
testCopy
	| h c |
	h := self hashClass new update: (self bytesTo: 100); yourself.
	c := h copy.
	h update: 'x'.
	c update: 'y'.
	self assert: h digest equals: (self hashClass hash: (self bytesTo: 100), 'x' asByteArray).
	self assert: c digest equals: (self hashClass hash: (self bytesTo: 100), 'y' asByteArray)
!
testReset
	| h |
	h := self hashClass new update: 'garbage'; yourself.
	h reset.
	self assert: (h update: 'abc'; digest) equals: (ByteArray fromHex: self oneBlockDigest)
!
testString
	"A String is hashed as its UTF-8."
	self assert: (self hashClass hash: (String with: (Character value: 233))) equals: (self hashClass hash: #[16rC3 16rA9])
! !
