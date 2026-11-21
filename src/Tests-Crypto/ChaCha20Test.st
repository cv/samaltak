TestCase subclass: #ChaCha20Test
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

ChaCha20Test comment: 'ChaCha20 against RFC 8439''s test vectors: the block function (A.1), encryption (2.4.2, A.2), Poly1305 key generation (2.6.2, A.4); calls split at blocks, the counter, wrong sizes.'!

!ChaCha20Test methodsFor: 'tests'!
testRfc8439BlockVector1
	self assert: (ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') counter: 0) nextBlock equals: (ByteArray fromHex: '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7
		da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586')
!
testRfc8439BlockVector2
	self assert: (ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') counter: 1) nextBlock equals: (ByteArray fromHex: '9f07e7be5551387a98ba977c732d080dcb0f29a048e3656912c6533e32ee7aed
		29b721769ce64e43d57133b074d839d531ed1f28510afb45ace10a1f4b794d6f')
!
testRfc8439BlockVector3
	self assert: (ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000001') nonce: (ByteArray fromHex: '000000000000000000000000') counter: 1) nextBlock equals: (ByteArray fromHex: '3aeb5224ecf849929b9d828db1ced4dd832025e8018b8160b82284f3c949aa5a
		8eca00bbb4a73bdad192b5c42f73f2fd4e273644c8b36125a64addeb006c13a0')
!
testRfc8439BlockVector4
	self assert: (ChaCha20 key: (ByteArray fromHex: '00ff000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') counter: 2) nextBlock equals: (ByteArray fromHex: '72d54dfbf12ec44b362692df94137f328fea8da73990265ec1bbbea1ae9af0ca
		13b25aa26cb4a648cb9b9d1be65b2c0924a66c54d545ec1b7374f4872e99f096')
!
testRfc8439BlockVector5
	self assert: (ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000002') counter: 0) nextBlock equals: (ByteArray fromHex: 'c2c64d378cd536374ae204b9ef933fcd1a8b2288b3dfa49672ab765b54ee27c7
		8a970e0e955c14f3a88e741b97c286f75f8fc299e8148362fa198a39531bed6d')
!
testRfc8439EncryptionVector1
	| plaintext ciphertext |
	plaintext := (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000
		0000000000000000000000000000000000000000000000000000000000000000').
	ciphertext := (ByteArray fromHex: '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7
		da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586').
	self assert: ((ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') counter: 0) xor: plaintext) equals: ciphertext.
	self assert: ((ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000') counter: 0) xor: ciphertext) equals: plaintext
!
testRfc8439EncryptionVector2
	| plaintext ciphertext |
	plaintext := (ByteArray fromHex: '416e79207375626d697373696f6e20746f20746865204945544620696e74656e
		6465642062792074686520436f6e7472696275746f7220666f72207075626c69
		636174696f6e20617320616c6c206f722070617274206f6620616e2049455446
		20496e7465726e65742d4472616674206f722052464320616e6420616e792073
		746174656d656e74206d6164652077697468696e2074686520636f6e74657874
		206f6620616e204945544620616374697669747920697320636f6e7369646572
		656420616e20224945544620436f6e747269627574696f6e222e205375636820
		73746174656d656e747320696e636c756465206f72616c2073746174656d656e
		747320696e20494554462073657373696f6e732c2061732077656c6c20617320
		7772697474656e20616e6420656c656374726f6e696320636f6d6d756e696361
		74696f6e73206d61646520617420616e792074696d65206f7220706c6163652c
		207768696368206172652061646472657373656420746f').
	ciphertext := (ByteArray fromHex: 'a3fbf07df3fa2fde4f376ca23e82737041605d9f4f4f57bd8cff2c1d4b7955ec
		2a97948bd3722915c8f3d337f7d370050e9e96d647b7c39f56e031ca5eb6250d
		4042e02785ececfa4b4bb5e8ead0440e20b6e8db09d881a7c6132f420e527950
		42bdfa7773d8a9051447b3291ce1411c680465552aa6c405b7764d5e87bea85a
		d00f8449ed8f72d0d662ab052691ca66424bc86d2df80ea41f43abf937d3259d
		c4b2d0dfb48a6c9139ddd7f76966e928e635553ba76c5c879d7b35d49eb2e62b
		0871cdac638939e25e8a1e0ef9d5280fa8ca328b351c3c765989cbcf3daa8b6c
		cc3aaf9f3979c92b3720fc88dc95ed84a1be059c6499b9fda236e7e818b04b0b
		c39c1e876b193bfe5569753f88128cc08aaa9b63d1a16f80ef2554d7189c411f
		5869ca52c5b83fa36ff216b9c1d30062bebcfd2dc5bce0911934fda79a86f6e6
		98ced759c3ff9b6477338f3da4f9cd8514ea9982ccafb341b2384dd902f3d1ab
		7ac61dd29c6f21ba5b862f3730e37cfdc4fd806c22f221').
	self assert: ((ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000001') nonce: (ByteArray fromHex: '000000000000000000000002') counter: 1) xor: plaintext) equals: ciphertext.
	self assert: ((ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000001') nonce: (ByteArray fromHex: '000000000000000000000002') counter: 1) xor: ciphertext) equals: plaintext
!
testRfc8439EncryptionVector3
	| plaintext ciphertext |
	plaintext := (ByteArray fromHex: '2754776173206272696c6c69672c20616e642074686520736c6974687920746f
		7665730a446964206779726520616e642067696d626c6520696e207468652077
		6162653a0a416c6c206d696d737920776572652074686520626f726f676f7665
		732c0a416e6420746865206d6f6d65207261746873206f757467726162652e').
	ciphertext := (ByteArray fromHex: '62e6347f95ed87a45ffae7426f27a1df5fb69110044c0d73118effa95b01e5cf
		166d3df2d721caf9b21e5fb14c616871fd84c54f9d65b283196c7fe4f60553eb
		f39c6402c42234e32a356b3e764312a61a5532055716ead6962568f87d3f3f77
		04c6a8d1bcd1bf4d50d6154b6da731b187b58dfd728afa36757a797ac188d1').
	self assert: ((ChaCha20 key: (ByteArray fromHex: '1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0') nonce: (ByteArray fromHex: '000000000000000000000002') counter: 42) xor: plaintext) equals: ciphertext.
	self assert: ((ChaCha20 key: (ByteArray fromHex: '1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0') nonce: (ByteArray fromHex: '000000000000000000000002') counter: 42) xor: ciphertext) equals: plaintext
!
testRfc8439Sunscreen
	self assert: ((ChaCha20 key: (ByteArray fromHex: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f') nonce: (ByteArray fromHex: '000000000000004a00000000') counter: 1) xor: 'Ladies and Gentlemen of the class of ''99: If I could offer you only one tip for the future, sunscreen would be it.' asByteArray) equals: (ByteArray fromHex: '6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b
		f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8
		07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736
		5af90bbf74a35be6b40b8eedf2785e42874d')
!
testRfc8439PolyKeyVector1
	self assert: ((ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000000') nonce: (ByteArray fromHex: '000000000000000000000000')) nextBlock copyFrom: 1 to: 32) equals: (ByteArray fromHex: '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7')
!
testRfc8439PolyKeyVector2
	self assert: ((ChaCha20 key: (ByteArray fromHex: '0000000000000000000000000000000000000000000000000000000000000001') nonce: (ByteArray fromHex: '000000000000000000000002')) nextBlock copyFrom: 1 to: 32) equals: (ByteArray fromHex: 'ecfa254f845f647473d3cb140da9e87606cb33066c447b87bc2666dde3fbb739')
!
testRfc8439PolyKeyVector3
	self assert: ((ChaCha20 key: (ByteArray fromHex: '1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0') nonce: (ByteArray fromHex: '000000000000000000000002')) nextBlock copyFrom: 1 to: 32) equals: (ByteArray fromHex: '965e3bc6f9ec7ed9560808f4d229f94b137ff275ca9b3fcbdd59deaad23310ae')
!
testRfc8439PolyKeyGeneration
	self assert: ((ChaCha20 key: (ByteArray fromHex: '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f') nonce: (ByteArray fromHex: '000000000001020304050607')) nextBlock copyFrom: 1 to: 32) equals: (ByteArray fromHex: '8ad5a08b905f81cc815040274ab29471a833b637e3fd0da508dbb8e2fdd1a646')
!
testSplitAtBlocks
	| key nonce data whole c |
	key := (1 to: 32) asByteArray.
	nonce := (1 to: 12) asByteArray.
	data := (ByteArray new: 300) atAllPut: 7; yourself.
	whole := (ChaCha20 key: key nonce: nonce) xor: data.
	c := ChaCha20 key: key nonce: nonce.
	self assert: (c xor: (data copyFrom: 1 to: 128)), (c xor: (data copyFrom: 129 to: 300)) equals: whole.
	self assert: c counter equals: 5.
	self assert: ((ChaCha20 key: key nonce: nonce counter: 2) xor: (data copyFrom: 129 to: 300)) equals: (whole copyFrom: 129 to: 300)
!
testXorInto
	| key nonce data out |
	key := (1 to: 32) asByteArray.
	nonce := (1 to: 12) asByteArray.
	data := (0 to: 99) asByteArray.
	out := ByteArray new: 110.
	(ChaCha20 key: key nonce: nonce) xor: data from: 3 to: 99 into: out at: 11.
	self assert: (out copyFrom: 11 to: 107) equals: ((ChaCha20 key: key nonce: nonce) xor: (data copyFrom: 3 to: 99)).
	self assert: (out copyFrom: 1 to: 10) equals: (ByteArray new: 10)
!
testCounterWraps
	| c |
	c := ChaCha20 key: (ByteArray new: 32) nonce: (ByteArray new: 12) counter: 16rFFFFFFFF.
	c nextBlock.
	self should: [c nextBlock] raise: CryptoError.
	self should: [c counter: -1] raise: CryptoError.
	self should: [c counter: 16r100000000] raise: CryptoError
!
testSizes
	self should: [ChaCha20 key: (ByteArray new: 16) nonce: (ByteArray new: 12)] raise: CryptoError.
	self should: [ChaCha20 key: (ByteArray new: 32) nonce: (ByteArray new: 8)] raise: CryptoError
! !
