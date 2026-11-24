TestCase subclass: #SecureRandomTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

SecureRandomTest comment: 'SecureRandom: the platform''s entropy (/dev/urandom hosted, EFI_RNG_PROTOCOL on UEFI) is there; known answers from a fixed source (computed outside the image with an independent ChaCha20 and SHA-256: the seed, fast key erasure, the reseed after a MB); a new session (the image started, from a snapshot or after writing one) reseeds every generator, so a resumed snapshot does not replay what its key would answer; a stuck source and no entropy are errors, never weak output; the output''s bits and bytes are balanced, at bounds a sound generator crosses once in 10^8 runs (tests/boot/resume_rng_test.sh resumes a real snapshot twice).'!

!SecureRandomTest methodsFor: 'support'!
counterSource
	"Blocks 0 1 2 .. 31, then 32 33 .. 63, and so on (mod 256): sound for the health checks, known for the answers."
	| next |
	next := 0.
	^[:n | | bytes |
		bytes := ((0 to: n - 1) collect: [:j | next + j \\ 256]) asByteArray.
		next := next + n.
		bytes]
!
hex: aString
	^ByteArray fromHex: aString
! !

!SecureRandomTest methodsFor: 'tests'!
testPlatformEntropy
	| a b |
	a := SecureRandom platformEntropy: 32.
	b := SecureRandom platformEntropy: 32.
	self assert: a size equals: 32.
	self deny: a = b.
	self deny: a = (ByteArray new: 32).
	self assert: a asSet size >= 8
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
testDirectWithoutCryptography
	"Without the VM's cryptography (UEFI) the source's blocks are answered as they come, checked, one block more drawn for the next check."
	| r stuck |
	r := SecureRandom new source: self counterSource; direct: true; yourself.
	self assert: (r nextBytes: 40) equals: ((0 to: 39) collect: [:i | i \\ 256]) asByteArray.
	self assert: (r nextBytes: 4) equals: #[96 97 98 99].
	stuck := SecureRandom new source: [:n | ByteArray new: n withAll: 7]; direct: true; yourself.
	self should: [stuck nextBytes: 8] raise: CryptoError.
	stuck := SecureRandom new source: [:n | (1 to: n) asByteArray]; direct: true; yourself.
	self should: [stuck nextBytes: 8] raise: CryptoError
!
testKnownAnswers
	"The key is SHA-256 of the source's first two blocks; each request answers ChaCha20's stream after its first 32 bytes, which are the next key; after a MB the key is SHA-256 of the key and a third block."
	| r |
	r := SecureRandom new source: self counterSource; yourself.
	self assert: (r nextBytes: 64) equals: (self hex: 'ea1f4599c7399496cdee25566f80df873a461e388c95356fa0c9011c689715715ca86ade7acf366a0de714e53effd2c3590940440aecfef9020970ce5e6c05d7').
	self assert: (r nextBytes: 16) equals: (self hex: '7ddadb43846ebdecc4cdd2b7c67a6e28').
	r nextBytes: 16r100000 - 80.
	self assert: (r nextBytes: 16) equals: (self hex: '1f75f906c103b3140ead1d7b7381fd13')
!
testFastKeyErasure
	"The stream after a request is ChaCha20 under that request's first 32 bytes of key stream."
	| seed r first k1 |
	r := SecureRandom new source: self counterSource; yourself.
	seed := SHA256 new update: (0 to: 31) asByteArray; update: (32 to: 63) asByteArray; digest.
	first := r nextBytes: 100.
	self assert: first equals: (((ChaCha20 key: seed nonce: (ByteArray new: 12)) xor: (ByteArray new: 132)) copyFrom: 33 to: 132).
	k1 := (ChaCha20 key: seed nonce: (ByteArray new: 12)) xor: (ByteArray new: 32).
	self assert: (r nextBytes: 10) equals: (((ChaCha20 key: k1 nonce: (ByteArray new: 12)) xor: (ByteArray new: 42)) copyFrom: 33 to: 42)
!
testANewSessionReseeds
	| calls r |
	calls := 0.
	r := SecureRandom new source: [:n | calls := calls + 1. ((1 to: n) collect: [:i | calls * 37 + i \\ 256]) asByteArray]; yourself.
	r nextBytes: 8; nextBytes: 8.
	self assert: calls equals: 2.
	Smalltalk renewSession.
	r nextBytes: 8.
	self assert: calls equals: 4
!
testAResumedSnapshotDoesNotReplay
	"A copy of a generator is what a snapshot keeps of it: in the same session it answers the same bytes; once the image starts again (a new session), each copy draws a key of its own from the platform."
	| r twin |
	r := SecureRandom new.
	r nextBytes: 16.
	twin := r copy.
	self assert: (r copy nextBytes: 32) equals: (twin copy nextBytes: 32).
	Smalltalk renewSession.
	self deny: (r nextBytes: 32) = (twin nextBytes: 32)
!
testReseedsAfterAMegabyte
	| calls r |
	calls := 0.
	r := SecureRandom new source: [:n | calls := calls + 1. ((1 to: n) collect: [:i | calls * 37 + i \\ 256]) asByteArray]; yourself.
	r nextBytes: 16r100000.
	self assert: calls equals: 2.
	r nextBytes: 1.
	self assert: calls equals: 3
!
testNoEntropyFailsLoudly
	| r |
	r := SecureRandom new source: [:n | nil]; yourself.
	self should: [r nextBytes: 16] raise: CryptoError.
	self should: [r nextBytes: 16] raise: CryptoError.
	r source: [:n | ByteArray new: n - 1].
	self should: [r nextBytes: 16] raise: CryptoError.
	r source: self counterSource.
	self assert: (r nextBytes: 16) size equals: 16.
	self should: [r nextBytes: -1] raise: CryptoError
!
testStuckSourceFailsLoudly
	"A source that answers zeros, few values, or the same block again is stuck: no output, now or after a new session, until it answers sound blocks again."
	| r block |
	r := SecureRandom new source: [:n | ByteArray new: n]; yourself.
	self should: [r nextBytes: 16] raise: CryptoError.
	r source: [:n | ((1 to: n) collect: [:i | i \\ 7]) asByteArray].
	self should: [r nextBytes: 16] raise: CryptoError.
	block := SecureRandom platformEntropy: 32.
	r source: [:n | block copy].
	self should: [r nextBytes: 16] raise: CryptoError.
	Smalltalk renewSession.
	self should: [r nextBytes: 16] raise: CryptoError.
	r source: self counterSource.
	self assert: (r nextBytes: 16) size equals: 16.
	r source: [:n | SecureRandom platformEntropy: n].
	self assert: (r nextBytes: 16) size equals: 16
!
testStuckSourceAtReseedFailsLoudly
	"Past a MB the generator mixes in a fresh block: a source stuck by then stops it, and it does not go on with its old key."
	| r stuck |
	stuck := false.
	r := SecureRandom new source: [:n | stuck ifTrue: [ByteArray new: n] ifFalse: [SecureRandom platformEntropy: n]]; yourself.
	r nextBytes: 16r100000.
	stuck := true.
	self should: [r nextBytes: 1] raise: CryptoError.
	self should: [r nextBytes: 1] raise: CryptoError
!
testBitsBalanced
	"80000 bits: their ones within 850 of half (6 standard deviations: a sound generator fails once in 5 * 10^8 runs; the bound was 400, 2.8 deviations, which failed one run in 210); every byte value occurs."
	| bytes ones seen |
	bytes := SecureRandom new nextBytes: 10000.
	ones := 0.
	seen := Set new.
	bytes do: [:b |
		seen add: b.
		0 to: 7 do: [:i | ones := ones + ((b bitShift: 0 - i) bitAnd: 1)]].
	self assert: (ones - 40000) abs < 850.
	self assert: seen size equals: 256
!
testBytesUniform
	"64 KB: the byte histogram's chi-square (255 degrees of freedom) below 400, which a sound generator exceeds once in 6 * 10^7 runs (a biased one, such as a source passed through unconditioned with a stuck bit, far above)."
	| bytes counts chi expected |
	bytes := SecureRandom new nextBytes: 65536.
	counts := Array new: 256 withAll: 0.
	bytes do: [:b | counts at: b + 1 put: (counts at: b + 1) + 1].
	expected := 256.
	chi := counts inject: 0 into: [:sum :c | sum + ((c - expected) squared / expected)].
	self assert: chi < 400
! !
