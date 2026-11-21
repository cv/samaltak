TestCase subclass: #HMACTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

HMACTest comment: 'HMAC-SHA-256, -384 and -512 against RFC 4231''s test cases (case 5 truncated to 128 bits, as there; cases 6 and 7 with keys longer than a block), incremental use, and ByteArray>>constantTimeEquals:.'!

!HMACTest methodsFor: 'tests'!
testRfc4231Case1
	| key data |
	key := ByteArray fromHex: '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'.
	data := ByteArray fromHex: '4869205468657265'.
	self assert: (HMAC hash: SHA256 key: key message: data) equals: (ByteArray fromHex: 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7').
	self assert: (HMAC hash: SHA384 key: key message: data) equals: (ByteArray fromHex: 'afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6').
	self assert: (HMAC hash: SHA512 key: key message: data) equals: (ByteArray fromHex: '87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854')
!
testRfc4231Case2
	| key data |
	key := ByteArray fromHex: '4a656665'.
	data := ByteArray fromHex: '7768617420646f2079612077616e7420666f72206e6f7468696e673f'.
	self assert: (HMAC hash: SHA256 key: key message: data) equals: (ByteArray fromHex: '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843').
	self assert: (HMAC hash: SHA384 key: key message: data) equals: (ByteArray fromHex: 'af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649').
	self assert: (HMAC hash: SHA512 key: key message: data) equals: (ByteArray fromHex: '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737')
!
testRfc4231Case3
	| key data |
	key := ByteArray fromHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'.
	data := ByteArray fromHex: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'.
	self assert: (HMAC hash: SHA256 key: key message: data) equals: (ByteArray fromHex: '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe').
	self assert: (HMAC hash: SHA384 key: key message: data) equals: (ByteArray fromHex: '88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b2a5ab39dc13814b94e3ab6e101a34f27').
	self assert: (HMAC hash: SHA512 key: key message: data) equals: (ByteArray fromHex: 'fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb')
!
testRfc4231Case4
	| key data |
	key := ByteArray fromHex: '0102030405060708090a0b0c0d0e0f10111213141516171819'.
	data := ByteArray fromHex: 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd'.
	self assert: (HMAC hash: SHA256 key: key message: data) equals: (ByteArray fromHex: '82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b').
	self assert: (HMAC hash: SHA384 key: key message: data) equals: (ByteArray fromHex: '3e8a69b7783c25851933ab6290af6ca77a9981480850009cc5577c6e1f573b4e6801dd23c4a7d679ccf8a386c674cffb').
	self assert: (HMAC hash: SHA512 key: key message: data) equals: (ByteArray fromHex: 'b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3dba91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd')
!
testRfc4231Case5
	| key data |
	key := ByteArray fromHex: '0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c'.
	data := ByteArray fromHex: '546573742057697468205472756e636174696f6e'.
	self assert: ((HMAC hash: SHA256 key: key message: data) copyFrom: 1 to: 16) equals: (ByteArray fromHex: 'a3b6167473100ee06e0c796c2955552b').
	self assert: ((HMAC hash: SHA384 key: key message: data) copyFrom: 1 to: 16) equals: (ByteArray fromHex: '3abf34c3503b2a23a46efc619baef897').
	self assert: ((HMAC hash: SHA512 key: key message: data) copyFrom: 1 to: 16) equals: (ByteArray fromHex: '415fad6271580a531d4179bc891d87a6')
!
testRfc4231Case6
	| key data |
	key := ByteArray fromHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'.
	data := ByteArray fromHex: '54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b6579202d2048617368204b6579204669727374'.
	self assert: (HMAC hash: SHA256 key: key message: data) equals: (ByteArray fromHex: '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54').
	self assert: (HMAC hash: SHA384 key: key message: data) equals: (ByteArray fromHex: '4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952').
	self assert: (HMAC hash: SHA512 key: key message: data) equals: (ByteArray fromHex: '80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598')
!
testRfc4231Case7
	| key data |
	key := ByteArray fromHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'.
	data := ByteArray fromHex: '5468697320697320612074657374207573696e672061206c6172676572207468616e20626c6f636b2d73697a65206b657920616e642061206c6172676572207468616e20626c6f636b2d73697a6520646174612e20546865206b6579206e6565647320746f20626520686173686564206265666f7265206265696e6720757365642062792074686520484d414320616c676f726974686d2e'.
	self assert: (HMAC hash: SHA256 key: key message: data) equals: (ByteArray fromHex: '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2').
	self assert: (HMAC hash: SHA384 key: key message: data) equals: (ByteArray fromHex: '6617178e941f020d351e2f254e8fd32c602420feb0b8fb9adccebb82461e99c5a678cc31e799176d3860e6110c46523e').
	self assert: (HMAC hash: SHA512 key: key message: data) equals: (ByteArray fromHex: 'e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58')
!
testIncremental
	| key m mac |
	key := ByteArray fromHex: '4a656665'.
	m := 'what do ya want for nothing?'.
	mac := HMAC hash: SHA256 key: key.
	mac update: (m copyFrom: 1 to: 10); update: (m copyFrom: 11 to: m size).
	self assert: mac digest equals: (HMAC hash: SHA256 key: key message: m).
	self assert: mac digest equals: (HMAC hash: SHA256 key: key message: m)
!
testConstantTimeEquals
	self assert: (#[1 2 3] constantTimeEquals: #[1 2 3]).
	self deny: (#[1 2 3] constantTimeEquals: #[1 2 4]).
	self deny: (#[1 2 3] constantTimeEquals: #[129 2 3]).
	self deny: (#[1 2 3] constantTimeEquals: #[1 2]).
	self assert: (#[] constantTimeEquals: #[])
!
testFromHex
	self assert: (ByteArray fromHex: '00ff7F a0') equals: #[0 255 127 160].
	self should: [ByteArray fromHex: 'abc'] raise: Error.
	self should: [ByteArray fromHex: 'zz'] raise: Error
! !
