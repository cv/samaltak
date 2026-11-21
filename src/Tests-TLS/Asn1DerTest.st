TestCase subclass: #Asn1DerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

Asn1DerTest comment: 'Tests Asn1Der: the values it reads, and that it refuses what DER forbids (non-minimal lengths and integers, indefinite lengths, lengths beyond the enclosing element, bad BOOLEANs and BIT STRINGs, too deep nesting) with TLSError.'!

!Asn1DerTest methodsFor: 'tests'!
testIntegers
	self assert: (self reader: #[2 1 0]) readInteger equals: 0.
	self assert: (self reader: #[2 1 127]) readInteger equals: 127.
	self assert: (self reader: #[2 2 0 128]) readInteger equals: 128.
	self assert: (self reader: #[2 1 128]) readInteger equals: -128.
	self assert: (self reader: #[2 2 255 127]) readInteger equals: -129.
	self assert: (self reader: #[2 9 1 0 0 0 0 0 0 0 0]) readInteger equals: (1 bitShift: 64).
	self should: [(self reader: #[2 2 0 1]) readInteger] raise: TLSError.
	self should: [(self reader: #[2 2 255 128]) readInteger] raise: TLSError.
	self should: [(self reader: #[2 0]) readInteger] raise: TLSError
!
testLengths
	| bytes r |
	bytes := ByteArray new: 203.
	bytes at: 1 put: 4; at: 2 put: 16r81; at: 3 put: 200.
	self assert: (self reader: bytes) readOctetString size equals: 200.
	self should: [(self reader: #[4 16r81 3 1 2 3]) readOctetString] raise: TLSError.
	self should: [(self reader: #[4 16r82 0 3 1 2 3]) readOctetString] raise: TLSError.
	self should: [(self reader: #[16r30 16r80 0 0]) readSequence] raise: TLSError.
	self should: [(self reader: #[4 4 1 2 3]) readOctetString] raise: TLSError.
	r := (self reader: #[16r30 3 4 2 1 2 1 1 0]) readSequence.
	self should: [r readOctetString] raise: TLSError.
	self should: [(self reader: #[4]) readOctetString] raise: TLSError.
	self should: [(self reader: #[16r1F 1 0]) skip] raise: TLSError
!
testSequences
	| r s |
	r := self reader: #[16r30 8 2 1 5 1 1 255 5 0].
	s := r readSequence.
	self assert: r atEnd.
	self assert: s readInteger equals: 5.
	self assert: s readBoolean.
	self assert: s readNull isNil.
	self assert: s atEnd.
	r := self reader: #[16r30 3 2 1 5 2 1 6].
	self assert: r readElementBytes equals: #[16r30 3 2 1 5].
	self assert: (r nextIs: 2).
	self should: [r expectEnd] raise: TLSError.
	r := self reader: #[16rA0 3 2 1 2].
	self assert: (r readOptionalExplicit: 1) isNil.
	self assert: (r readOptionalExplicit: 0) readInteger equals: 2.
	self should: [(self reader: #[2 1 0]) readSequence] raise: TLSError
!
testNestingLimit
	| bytes deep |
	deep := [:n | bytes := #[5 0]. n timesRepeat: [bytes := #[16r30], (ByteArray with: bytes size), bytes]. bytes].
	self shouldnt: [self readNested: (deep value: Asn1Der maxDepth)] raise: TLSError.
	self should: [self readNested: (deep value: Asn1Der maxDepth + 1)] raise: TLSError
!
testBooleansAndNull
	self deny: (self reader: #[1 1 0]) readBoolean.
	self should: [(self reader: #[1 1 1]) readBoolean] raise: TLSError.
	self should: [(self reader: #[1 2 0 0]) readBoolean] raise: TLSError.
	self assert: (self reader: #[5 0]) readNull isNil.
	self should: [(self reader: #[5 1 0]) readNull] raise: TLSError
!
testOids
	self assert: (self reader: #[6 9 16r2A 16r86 16r48 16r86 16rF7 16r0D 1 1 16r0B]) readOid equals: '1.2.840.113549.1.1.11'.
	self assert: (self reader: #[6 3 16r55 4 3]) readOid equals: '2.5.4.3'.
	self assert: (self reader: #[6 5 16r2B 16r81 4 0 16r22]) readOid equals: '1.3.132.0.34'.
	self assert: (self reader: #[6 2 16r88 16r37]) readOid equals: '2.999'.
	self should: [(self reader: #[6 2 16r55 16r84]) readOid] raise: TLSError.
	self should: [(self reader: #[6 3 16r55 16r80 4]) readOid] raise: TLSError
!
testBitStrings
	self assert: (self reader: #[3 3 0 1 2]) readBitString equals: #[1 2].
	self should: [(self reader: #[3 2 1 2]) readBitString] raise: TLSError.
	"keyUsage digitalSignature, keyCertSign, cRLSign: bits 0, 5, 6"
	self assert: (self reader: #[3 2 1 16r86]) readNamedBits equals: 2r1100001.
	self assert: (self reader: #[3 3 7 16r80 16r80]) readNamedBits equals: 2r100000001.
	self should: [(self reader: #[3 2 1 16r87]) readNamedBits] raise: TLSError.
	self should: [(self reader: #[3 1 1]) readNamedBits] raise: TLSError
!
testTimes
	self assert: (self reader: (#[23 13], '491231235959Z' asByteArray)) readTime equals: 2524607999.
	self assert: (self reader: (#[23 13], '500101000000Z' asByteArray)) readTime equals: -631152000.
	self assert: (self reader: (#[23 13], '700101000000Z' asByteArray)) readTime equals: 0.
	self assert: (self reader: (#[24 15], '20380119031408Z' asByteArray)) readTime equals: 2147483648.
	self assert: (self reader: (#[24 15], '20240229120000Z' asByteArray)) readTime equals: 1709208000.
	self should: [(self reader: (#[24 15], '20230229120000Z' asByteArray)) readTime] raise: TLSError.
	self should: [(self reader: (#[23 11], '7001010000Z' asByteArray)) readTime] raise: TLSError.
	self should: [(self reader: (#[24 19], '20240101000000.123Z' asByteArray)) readTime] raise: TLSError.
	self should: [(self reader: (#[23 13], '700101000000+' asByteArray)) readTime] raise: TLSError
!
testStrings
	self assert: (self reader: (#[19 2], 'US' asByteArray)) readString equals: 'US'.
	self assert: (self reader: (#[12 2], (String with: (Character value: 233)) utf8Encoded)) readString equals: (String with: (Character value: 233)).
	self assert: (self reader: #[30 4 0 65 4 16r10]) readString equals: (String with: $A with: (Character value: 16r410)).
	self should: [(self reader: #[30 3 0 65 0]) readString] raise: TLSError.
	self should: [(self reader: #[2 1 0]) readString] raise: TLSError
! !

!Asn1DerTest methodsFor: 'private'!
reader: bytes
	^Asn1Der on: bytes asByteArray
!
readNested: bytes
	| r |
	r := self reader: bytes.
	[r nextIs: 16r30] whileTrue: [r := r readSequence].
	r readNull
! !
