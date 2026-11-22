Object subclass: #NativeCrypto
	instanceVariableNames: ''
	classVariableNames: 'Disabled'
	package: 'System-Crypto'!

NativeCrypto comment: 'I am the VM''s cryptographic primitives (CryptoPrimitives, docs/crypto.md): SHA-256 and SHA-512 compression of whole blocks, AES encryption of blocks and in counter mode, GHASH; in C, with the CPU''s instructions where it has them (Armv8''s AES, PMULL, SHA-256 and SHA-512; x86-64''s AES-NI, PCLMULQDQ and SHA-NI). SHA256, SHA512, Aes and AesGcm call me first and do the work in Smalltalk, their reference, where I answer false: a VM without the primitives, arguments they refuse, or enabled false (enabled: false runs the Smalltalk code alone, as the tests do). Indices are 1-based. Class side: features, the bits (featureNames) of the work the CPU''s instructions do (the rest is portable C), nil without the primitives; useFeatures: mask lets them do only that (0: the portable C alone, -1: all) and answers the previous mask. Crc32 and Crc32c (System-Storage) call the CRC primitives themselves.'!

!NativeCrypto class methodsFor: 'switching'!
enabled
	"Whether the classes of System-Crypto call the primitives (true unless set otherwise)."
	^Disabled ~~ true
!
enabled: aBoolean
	Disabled := aBoolean not
!
features
	"The bits of featureNames whose work the CPU's instructions do in the VM; nil if the VM has no such primitives."
	<primitive: 'cryptoFeatures'>
	^nil
!
useFeatures: mask
	"Let the CPU's instructions do only the features of mask (0: the VM's portable C alone, -1: all it has); answer the previous mask, nil if the VM has no such primitives."
	<primitive: 'cryptoFeatures'>
	^nil
!
featureNames
	"Bit i - 1 of features is the i-th."
	^#(#aes #ghash #sha256 #sha512 #crc32 #crc32c)
! !

!NativeCrypto class methodsFor: 'operations'!
sha256: state bytes: bytes from: start blocks: n
	"Compress the n 64-byte blocks of bytes from start into state, SHA256's Array of eight 32-bit words; false if the VM does not."
	^self enabled and: [(self primSha256: state bytes: bytes from: start blocks: n) == true]
!
sha512: state bytes: bytes from: start blocks: n
	"Compress the n 128-byte blocks of bytes from start into state, SHA512's Array of eight 64-bit words as sixteen 32-bit halves, the high one first; false if the VM does not."
	^self enabled and: [(self primSha512: state bytes: bytes from: start blocks: n) == true]
!
aes: roundKeys encrypt: input from: start into: output at: outStart blocks: n
	"Encrypt the n 16-byte blocks of input from start into output from outStart with AES's round keys as bytes (Aes>>roundKeys); false if the VM does not."
	^self enabled and: [(self primAes: roundKeys encrypt: input from: start into: output at: outStart blocks: n) == true]
!
aes: roundKeys ctr: counterBlock input: input from: start to: stop into: output at: outStart
	"Xor input from start to stop into output from outStart with AES's key stream in counter mode: the encryptions of the 16 bytes of counterBlock, then of it with its last 32 bits (big-endian) incremented modulo 2^32 (GCM's inc32), and so on; false if the VM does not."
	^self enabled and: [(self primAes: roundKeys ctr: counterBlock input: input from: start into: output at: outStart count: stop - start + 1) == true]
!
ghash: y key: h bytes: bytes from: start to: stop
	"y := (y xor each 16-byte block of bytes from start to stop, the last padded with zeros) times h in GF(2^128), block after block: GHASH (NIST SP 800-38D), y and h 16-byte ByteArrays; false if the VM does not."
	^self enabled and: [(self primGhash: y key: h bytes: bytes from: start count: stop - start + 1) == true]
! !

!NativeCrypto class methodsFor: 'primitives'!
primSha256: state bytes: bytes from: start blocks: n
	<primitive: 'cryptoSha256'>
	^false
!
primSha512: state bytes: bytes from: start blocks: n
	<primitive: 'cryptoSha512'>
	^false
!
primAes: roundKeys encrypt: input from: start into: output at: outStart blocks: n
	<primitive: 'cryptoAesEncrypt'>
	^false
!
primAes: roundKeys ctr: counterBlock input: input from: start into: output at: outStart count: n
	<primitive: 'cryptoAesCtr'>
	^false
!
primGhash: y key: h bytes: bytes from: start count: n
	<primitive: 'cryptoGhash'>
	^false
! !
