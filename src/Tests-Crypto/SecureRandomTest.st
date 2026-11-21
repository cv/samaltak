TestCase subclass: #SecureRandomTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

SecureRandomTest comment: 'SecureRandom: the platform''s entropy (/dev/urandom hosted, EFI_RNG_PROTOCOL on UEFI) is there; the DRBG against ChaCha20 itself from a known seed (fast key erasure: each key is the last request''s first 32 bytes of key stream); reseeding when the image starts and after a MB; no entropy is an error, never weak output; the output''s bits are balanced.'!

!SecureRandomTest methodsFor: 'tests'!
testPlatformEntropy
	| a b |
	a := SecureRandom platformEntropy: 32.
	b := SecureRandom platformEntropy: 32.
	self assert: a size equals: 32.
	self deny: a = b.
	self deny: a = (ByteArray new: 32)
!
testDefault
	| a b |
	self assert: SecureRandom default identicalTo: SecureRandom default.
	a := SecureRandom default nextBytes: 32.
	b := SecureRandom default nextBytes: 32.
	self assert: a size equals: 32.
	self deny: a = b.
	self assert: (SecureRandom default nextBytes: 0) equals: #[].
	self assert: (SecureRandom default nextBytes: 1000) size equals: 1000
!
testKnownSeed
	| seed r first second k1 |
	seed := (1 to: 32) asByteArray.
	r := SecureRandom new source: [:n | seed copyFrom: 1 to: n]; yourself.
	first := r nextBytes: 100.
	self assert: first equals: (((ChaCha20 key: seed nonce: (ByteArray new: 12)) xor: (ByteArray new: 132)) copyFrom: 33 to: 132).
	k1 := ((ChaCha20 key: seed nonce: (ByteArray new: 12)) xor: (ByteArray new: 32)).
	second := r nextBytes: 10.
	self assert: second equals: (((ChaCha20 key: k1 nonce: (ByteArray new: 12)) xor: (ByteArray new: 42)) copyFrom: 33 to: 42)
!
testReseedsWhenTheImageStarts
	| calls r |
	calls := 0.
	r := SecureRandom new source: [:n | calls := calls + 1. ByteArray new: n withAll: calls]; yourself.
	r nextBytes: 8; nextBytes: 8.
	self assert: calls equals: 1.
	SecureRandom startUp: true.
	r nextBytes: 8.
	self assert: calls equals: 2
!
testReseedsAfterAMegabyte
	| calls r |
	calls := 0.
	r := SecureRandom new source: [:n | calls := calls + 1. ByteArray new: n withAll: calls]; yourself.
	r nextBytes: 16r100000.
	self assert: calls equals: 1.
	r nextBytes: 1.
	self assert: calls equals: 2
!
testNoEntropyFailsLoudly
	| r |
	r := SecureRandom new source: [:n | nil]; yourself.
	self should: [r nextBytes: 16] raise: CryptoError.
	self should: [r nextBytes: 16] raise: CryptoError.
	r source: [:n | ByteArray new: n - 1].
	self should: [r nextBytes: 16] raise: CryptoError.
	r source: [:n | ByteArray new: n].
	self assert: (r nextBytes: 16) size equals: 16.
	self should: [r nextBytes: -1] raise: CryptoError
!
testBitsBalanced
	"80000 bits: their ones within 1% of half (about 5.7 standard deviations); every byte value occurs."
	| bytes ones seen |
	bytes := SecureRandom new nextBytes: 10000.
	ones := 0.
	seen := Set new.
	bytes do: [:b |
		seen add: b.
		0 to: 7 do: [:i | ones := ones + ((b bitShift: 0 - i) bitAnd: 1)]].
	self assert: (ones - 40000) abs < 400.
	self assert: seen size equals: 256
! !
