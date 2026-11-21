TestCase subclass: #AesGcmTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

AesGcmTest comment: 'AesGcm against the 18 test cases of McGrew and Viega''s GCM specification (AES-128, -192, -256: empty, one block, four blocks, with aad and a partial block, 8- and 60-byte nonces), both ways; every tampering signals CryptoError; messages of every size around the block size; wrong sizes.'!

!AesGcmTest methodsFor: 'support'!
check: key plaintext: plaintext nonce: nonce aad: aad sealed: sealed
	| gcm |
	gcm := AesGcm key: key.
	self assert: (gcm encrypt: plaintext nonce: nonce aad: aad) equals: sealed.
	self assert: (gcm decrypt: sealed nonce: nonce aad: aad) equals: plaintext
!
key
	^ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308'
!
nonce
	^ByteArray fromHex: 'cafebabefacedbaddecaf888'
!
aad
	^ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2'
! !

!AesGcmTest methodsFor: 'tests'!
testGcmSpecCase1
	self check: (ByteArray fromHex: '00000000000000000000000000000000') plaintext: (ByteArray fromHex: '') nonce: (ByteArray fromHex: '000000000000000000000000') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '58e2fccefa7e3061367f1d57a4e7455a')
!
testGcmSpecCase2
	self check: (ByteArray fromHex: '00000000000000000000000000000000') plaintext: (ByteArray fromHex: '00000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf')
!
testGcmSpecCase3
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255') nonce: (ByteArray fromHex: 'cafebabefacedbaddecaf888') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e
		21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985
		4d5c2af327cd64a62cf35abd2ba6fab4')
!
testGcmSpecCase4
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: 'cafebabefacedbaddecaf888') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e
		21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc
		3221a5db94fae95ae7121a47')
!
testGcmSpecCase5
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: 'cafebabefacedbad') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '61353b4c2806934a777ff51fa22a4755699b2a714fcdc6f83766e5f97b6c7423
		73806900e49f24b22b097544d4896b424989b5e1ebac0f07c23f45983612d2e7
		9e3b0785561be14aaca2fccb')
!
testGcmSpecCase6
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: '9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728
		c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '8ce24998625615b603a033aca13fb894be9112a5c3a211a8ba262a3cca7e2ca7
		01e4a9a4fba43c90ccdcb281d48c7c6fd62875d2aca417034c34aee5619cc5ae
		fffe0bfa462af43c1699d050')
!
testGcmSpecCase7
	self check: (ByteArray fromHex: '000000000000000000000000000000000000000000000000') plaintext: (ByteArray fromHex: '') nonce: (ByteArray fromHex: '000000000000000000000000') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: 'cd33b28ac773f74ba00ed1f312572435')
!
testGcmSpecCase8
	self check: (ByteArray fromHex: '000000000000000000000000000000000000000000000000') plaintext: (ByteArray fromHex: '00000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '98e7247c07f0fe411c267e4384b0f6002ff58d80033927ab8ef4d4587514f0fb')
!
testGcmSpecCase9
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255') nonce: (ByteArray fromHex: 'cafebabefacedbaddecaf888') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '3980ca0b3c00e841eb06fac4872a2757859e1ceaa6efd984628593b40ca1e19c
		7d773d00c144c525ac619d18c84a3f4718e2448b2fe324d9ccda2710acade256
		9924a7c8587336bfb118024db8674a14')
!
testGcmSpecCase10
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: 'cafebabefacedbaddecaf888') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '3980ca0b3c00e841eb06fac4872a2757859e1ceaa6efd984628593b40ca1e19c
		7d773d00c144c525ac619d18c84a3f4718e2448b2fe324d9ccda27102519498e
		80f1478f37ba55bd6d27618c')
!
testGcmSpecCase11
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: 'cafebabefacedbad') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '0f10f599ae14a154ed24b36e25324db8c566632ef2bbb34f8347280fc4507057
		fddc29df9a471f75c66541d4d4dad1c9e93a19a58e8b473fa0f062f765dcc57f
		cf623a24094fcca40d3533f8')
!
testGcmSpecCase12
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: '9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728
		c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: 'd27e88681ce3243c4830165a8fdcf9ff1de9a1d8e6b447ef6ef7b79828666e45
		81e79012af34ddd9e2f037589b292db3e67c036745fa22e7e9b7373bdcf566ff
		291c25bbb8568fc3d376a6d9')
!
testGcmSpecCase13
	self check: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') plaintext: (ByteArray fromHex: '') nonce: (ByteArray fromHex: '000000000000000000000000') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '530f8afbc74536b9a963b4f1c4cb738b')
!
testGcmSpecCase14
	self check: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') plaintext: (ByteArray fromHex: '00000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: 'cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919')
!
testGcmSpecCase15
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255') nonce: (ByteArray fromHex: 'cafebabefacedbaddecaf888') aad: (ByteArray fromHex: '') sealed: (ByteArray fromHex: '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa
		8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad
		b094dac5d93471bdec1a502270e3cc6c')
!
testGcmSpecCase16
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: 'cafebabefacedbaddecaf888') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa
		8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece
		0f4e1768cddf8853bb2d551b')
!
testGcmSpecCase17
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: 'cafebabefacedbad') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: 'c3762df1ca787d32ae47c13bf19844cbaf1ae14d0b976afac52ff7d79bba9de0
		feb582d33934a4f0954cc2363bc73f7862ac430e64abe499f47c9b1f3a337dbf
		46a792c45e454913fe2ea8f2')
!
testGcmSpecCase18
	self check: (ByteArray fromHex: 'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308') plaintext: (ByteArray fromHex: 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72
		1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39') nonce: (ByteArray fromHex: '9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728
		c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b') aad: (ByteArray fromHex: 'feedfacedeadbeeffeedfacedeadbeefabaddad2') sealed: (ByteArray fromHex: '5a8def2f0c9e53f1f75d7853659e2a20eeb2b22aafde6419a058ab4f6f746bf4
		0fc0c3b780f244452da3ebf1c5d82cdea2418997200ef82e44ae7e3fa44a8266
		ee1c8eb0c8b5d4cf5ae9f19a')
!
testTampering
	| gcm sealed bad |
	gcm := AesGcm key: self key.
	sealed := gcm encrypt: (1 to: 60) asByteArray nonce: self nonce aad: self aad.
	#(1 17 60 61 76) do: [:i |
		bad := sealed copy.
		bad at: i put: ((bad at: i) bitXor: 16r80).
		self should: [gcm decrypt: bad nonce: self nonce aad: self aad] raise: CryptoError].
	bad := self aad copy.
	bad at: 20 put: ((bad at: 20) bitXor: 1).
	self should: [gcm decrypt: sealed nonce: self nonce aad: bad] raise: CryptoError.
	self should: [gcm decrypt: sealed nonce: self nonce aad: #[]] raise: CryptoError.
	bad := self nonce copy.
	bad at: 1 put: ((bad at: 1) bitXor: 1).
	self should: [gcm decrypt: sealed nonce: bad aad: self aad] raise: CryptoError.
	self should: [gcm decrypt: (sealed copyFrom: 1 to: sealed size - 1) nonce: self nonce aad: self aad] raise: CryptoError.
	self should: [gcm decrypt: #[1 2 3] nonce: self nonce aad: self aad] raise: CryptoError.
	self should: [(AesGcm key: (ByteArray new: 16)) decrypt: sealed nonce: self nonce aad: self aad] raise: CryptoError
!
testRoundTripSizes
	| gcm p |
	#(16 32) do: [:size |
		gcm := AesGcm key: (ByteArray new: size withAll: 5).
		#(0 1 15 16 17 31 32 33 100) do: [:n |
			p := ((1 to: n) collect: [:i | i \\ 256]) asByteArray.
			self assert: (gcm decrypt: (gcm encrypt: p nonce: self nonce aad: p) nonce: self nonce aad: p) equals: p]]
!
testSizes
	self should: [AesGcm key: (ByteArray new: 20)] raise: CryptoError.
	self should: [(AesGcm key: self key) encrypt: #[1] nonce: #[] aad: #[]] raise: CryptoError.
	self assert: {AesGcm nonceSize. AesGcm tagSize} equals: #(12 16)
!
testLengthLimit
	"At most 2^32 - 2 blocks (SP 800-38D), else the 32-bit counter wraps onto J0: refused before any work (an Interval is a cheap collection of that size)."
	| gcm |
	gcm := AesGcm key: (ByteArray new: 16).
	self should: [gcm encrypt: (1 to: AesGcm maxPlaintextSize + 1) nonce: (ByteArray new: 12) aad: #[]] raise: CryptoError.
	self should: [gcm decrypt: (1 to: AesGcm maxPlaintextSize + 17) nonce: (ByteArray new: 12) aad: #[]] raise: CryptoError.
	self assert: AesGcm maxPlaintextSize equals: (1 bitShift: 32) - 2 * 16
! !
