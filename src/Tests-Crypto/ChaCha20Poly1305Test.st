TestCase subclass: #ChaCha20Poly1305Test
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

ChaCha20Poly1305Test comment: 'ChaCha20Poly1305 against RFC 8439''s AEAD example (2.8.2) and decryption vector (A.5); every tampering (a bit of the ciphertext, of the tag, of the aad, another nonce or key, a truncated message) signals CryptoError; empty messages and aad; wrong sizes.'!

!ChaCha20Poly1305Test methodsFor: 'vectors'!
key
	^(ByteArray fromHex: '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f')
!
nonce
	^(ByteArray fromHex: '070000004041424344454647')
!
aad
	^(ByteArray fromHex: '50515253c0c1c2c3c4c5c6c7')
!
plaintext
	^(ByteArray fromHex: '4c616469657320616e642047656e746c656d656e206f662074686520636c6173
		73206f66202739393a204966204920636f756c64206f6666657220796f75206f
		6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73
		637265656e20776f756c642062652069742e')
!
sealed
	"The ciphertext and the tag."
	^(ByteArray fromHex: 'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6
		3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36
		92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc
		3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd060
		0691')
! !

!ChaCha20Poly1305Test methodsFor: 'tests'!
testRfc8439Encrypt
	self assert: ((ChaCha20Poly1305 key: self key) encrypt: self plaintext nonce: self nonce aad: self aad) equals: self sealed
!
testRfc8439Decrypt
	self assert: ((ChaCha20Poly1305 key: self key) decrypt: self sealed nonce: self nonce aad: self aad) equals: self plaintext
!
testRfc8439DecryptionVector
	| sealed |
	sealed := (ByteArray fromHex: '64a0861575861af460f062c79be643bd5e805cfd345cf389f108670ac76c8cb2
		4c6cfc18755d43eea09ee94e382d26b0bdb7b73c321b0100d4f03b7f355894cf
		332f830e710b97ce98c8a84abd0b948114ad176e008d33bd60f982b1ff37c855
		9797a06ef4f0ef61c186324e2b3506383606907b6a7c02b0f9f6157b53c867e4
		b9166c767b804d46a59b5216cde7a4e99040c5a40433225ee282a1b0a06c523e
		af4534d7f83fa1155b0047718cbc546a0d072b04b3564eea1b422273f548271a
		0bb2316053fa76991955ebd63159434ecebb4e466dae5a1073a6727627097a10
		49e617d91d361094fa68f0ff77987130305beaba2eda04df997b714d6c6f2c29
		a6ad5cb4022b02709b'), (ByteArray fromHex: 'eead9d67890cbb22392336fea1851f38').
	self assert: ((ChaCha20Poly1305 key: (ByteArray fromHex: '1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0')) decrypt: sealed nonce: (ByteArray fromHex: '000000000102030405060708') aad: (ByteArray fromHex: 'f33388860000000000004e91')) equals: (ByteArray fromHex: '496e7465726e65742d4472616674732061726520647261667420646f63756d65
		6e74732076616c696420666f722061206d6178696d756d206f6620736978206d
		6f6e74687320616e64206d617920626520757064617465642c207265706c6163
		65642c206f72206f62736f6c65746564206279206f7468657220646f63756d65
		6e747320617420616e792074696d652e20497420697320696e617070726f7072
		6961746520746f2075736520496e7465726e65742d4472616674732061732072
		65666572656e6365206d6174657269616c206f7220746f206369746520746865
		6d206f74686572207468616e206173202fe2809c776f726b20696e2070726f67
		726573732e2fe2809d')
!
testTampering
	| aead sealed bad |
	aead := ChaCha20Poly1305 key: self key.
	sealed := self sealed.
	#(1 50 114 115 130) do: [:i |
		bad := sealed copy.
		bad at: i put: ((bad at: i) bitXor: 1).
		self should: [aead decrypt: bad nonce: self nonce aad: self aad] raise: CryptoError].
	bad := self aad copy.
	bad at: 1 put: ((bad at: 1) bitXor: 128).
	self should: [aead decrypt: sealed nonce: self nonce aad: bad] raise: CryptoError.
	self should: [aead decrypt: sealed nonce: self nonce aad: #[]] raise: CryptoError.
	bad := self nonce copy.
	bad at: 12 put: ((bad at: 12) bitXor: 1).
	self should: [aead decrypt: sealed nonce: bad aad: self aad] raise: CryptoError.
	self should: [aead decrypt: (sealed copyFrom: 1 to: sealed size - 1) nonce: self nonce aad: self aad] raise: CryptoError.
	self should: [aead decrypt: (sealed copyFrom: 1 to: 15) nonce: self nonce aad: self aad] raise: CryptoError.
	bad := self key copy.
	bad at: 1 put: ((bad at: 1) bitXor: 1).
	self should: [(ChaCha20Poly1305 key: bad) decrypt: sealed nonce: self nonce aad: self aad] raise: CryptoError
!
testEmpty
	| aead sealed |
	aead := ChaCha20Poly1305 key: self key.
	sealed := aead encrypt: #[] nonce: self nonce aad: #[].
	self assert: sealed size equals: 16.
	self assert: (aead decrypt: sealed nonce: self nonce aad: #[]) equals: #[].
	sealed := aead encrypt: #[] nonce: self nonce aad: self aad.
	self assert: (aead decrypt: sealed nonce: self nonce aad: self aad) equals: #[]
!
testRoundTripSizes
	| aead p |
	aead := ChaCha20Poly1305 key: self key.
	#(1 15 16 17 63 64 65 200) do: [:n |
		p := (1 to: n) asByteArray.
		self assert: (aead decrypt: (aead encrypt: p nonce: self nonce aad: p) nonce: self nonce aad: p) equals: p]
!
testSizes
	self should: [ChaCha20Poly1305 key: (ByteArray new: 16)] raise: CryptoError.
	self should: [(ChaCha20Poly1305 key: self key) encrypt: #[1] nonce: (ByteArray new: 8) aad: #[]] raise: CryptoError.
	self assert: {ChaCha20Poly1305 keySize. ChaCha20Poly1305 nonceSize. ChaCha20Poly1305 tagSize} equals: #(32 12 16)
! !
