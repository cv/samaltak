TestCase subclass: #AesTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

AesTest comment: 'Aes against FIPS 197''s examples (Appendix B; C.1 to C.3: AES-128, -192, -256, both ways), the S-box''s known entries, decryption undoing encryption for many blocks and keys, in-place use, wrong key sizes.'!

!AesTest methodsFor: 'tests'!
testFips197AppendixB
	| aes |
	aes := Aes key: (ByteArray fromHex: '2b7e151628aed2a6abf7158809cf4f3c').
	self assert: (aes encryptBlock: (ByteArray fromHex: '3243f6a8885a308d313198a2e0370734')) equals: (ByteArray fromHex: '3925841d02dc09fbdc118597196a0b32').
	self assert: (aes decryptBlock: (ByteArray fromHex: '3925841d02dc09fbdc118597196a0b32')) equals: (ByteArray fromHex: '3243f6a8885a308d313198a2e0370734')
!
testFips197AppendixC1Aes128
	| aes |
	aes := Aes key: (ByteArray fromHex: '000102030405060708090a0b0c0d0e0f').
	self assert: (aes encryptBlock: (ByteArray fromHex: '00112233445566778899aabbccddeeff')) equals: (ByteArray fromHex: '69c4e0d86a7b0430d8cdb78070b4c55a').
	self assert: (aes decryptBlock: (ByteArray fromHex: '69c4e0d86a7b0430d8cdb78070b4c55a')) equals: (ByteArray fromHex: '00112233445566778899aabbccddeeff')
!
testFips197AppendixC2Aes192
	| aes |
	aes := Aes key: (ByteArray fromHex: '000102030405060708090a0b0c0d0e0f1011121314151617').
	self assert: (aes encryptBlock: (ByteArray fromHex: '00112233445566778899aabbccddeeff')) equals: (ByteArray fromHex: 'dda97ca4864cdfe06eaf70a0ec0d7191').
	self assert: (aes decryptBlock: (ByteArray fromHex: 'dda97ca4864cdfe06eaf70a0ec0d7191')) equals: (ByteArray fromHex: '00112233445566778899aabbccddeeff')
!
testFips197AppendixC3Aes256
	| aes |
	aes := Aes key: (ByteArray fromHex: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f').
	self assert: (aes encryptBlock: (ByteArray fromHex: '00112233445566778899aabbccddeeff')) equals: (ByteArray fromHex: '8ea2b7ca516745bfeafc49904b496089').
	self assert: (aes decryptBlock: (ByteArray fromHex: '8ea2b7ca516745bfeafc49904b496089')) equals: (ByteArray fromHex: '00112233445566778899aabbccddeeff')
!
testSbox
	"FIPS 197''s S-box: S(00) = 63, S(01) = 7c, S(53) = ed, S(ff) = 16."
	| aes |
	aes := Aes key: (ByteArray new: 16).
	self assert: (aes subWord: 16r00010053) equals: 16r637C63ED.
	self assert: (aes subWord: 16rFF) equals: 16r63636316
!
testRoundTrips
	| block aes |
	#(16 24 32) do: [:size |
		1 to: 20 do: [:seed |
			aes := Aes key: ((1 to: size) collect: [:i | i * seed * 37 \\ 256]) asByteArray.
			block := ((1 to: 16) collect: [:i | i * seed * 91 + 5 \\ 256]) asByteArray.
			self assert: (aes decryptBlock: (aes encryptBlock: block)) equals: block.
			self deny: (aes encryptBlock: block) = block]]
!
testInPlace
	| aes buffer expected |
	aes := Aes key: (ByteArray fromHex: '000102030405060708090a0b0c0d0e0f').
	expected := ByteArray fromHex: '69c4e0d86a7b0430d8cdb78070b4c55a'.
	buffer := ByteArray new: 20.
	buffer replaceFrom: 3 to: 18 with: (ByteArray fromHex: '00112233445566778899aabbccddeeff') startingAt: 1.
	aes encrypt: buffer at: 3 into: buffer at: 3.
	self assert: (buffer copyFrom: 3 to: 18) equals: expected.
	self assert: (buffer copyFrom: 1 to: 2) equals: #[0 0]
!
testKeySizes
	#(0 8 15 17 20 33) do: [:n | self should: [Aes key: (ByteArray new: n)] raise: CryptoError]
! !
