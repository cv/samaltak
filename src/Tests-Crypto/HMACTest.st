TestCase subclass: #HMACTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

HMACTest comment: 'HMAC against RFC 4231''s test cases (case 5 truncated to 128 bits, as there; cases 6 and 7 with keys longer than a block), incremental use, and ByteArray>>constantTimeEquals:.'!

!HMACTest methodsFor: 'tests'!
testRfc4231Case1
	self assert: (HMAC hash: SHA256 key: (ByteArray fromHex: '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b') message: (ByteArray fromHex: '4869205468657265')) equals: (ByteArray fromHex: 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7')
!
testRfc4231Case2
	self assert: (HMAC hash: SHA256 key: (ByteArray fromHex: '4a656665') message: (ByteArray fromHex: '7768617420646f2079612077616e7420666f72206e6f7468696e673f')) equals: (ByteArray fromHex: '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843')
!
testRfc4231Case3
	self assert: (HMAC hash: SHA256 key: (ByteArray fromHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') message: (ByteArray fromHex: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd')) equals: (ByteArray fromHex: '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe')
!
testRfc4231Case4
	self assert: (HMAC hash: SHA256 key: (ByteArray fromHex: '0102030405060708090a0b0c0d0e0f10111213141516171819') message: (ByteArray fromHex: 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd')) equals: (ByteArray fromHex: '82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b')
!
testRfc4231Case5
	self assert: ((HMAC hash: SHA256 key: (ByteArray fromHex: '0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c') message: (ByteArray fromHex: '546573742057697468205472756e636174696f6e')) copyFrom: 1 to: 16) equals: (ByteArray fromHex: 'a3b6167473100ee06e0c796c2955552b')
!
testRfc4231Case6
	self assert: (HMAC hash: SHA256 key: (ByteArray fromHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') message: (ByteArray fromHex: '54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b6579202d2048617368204b6579204669727374')) equals: (ByteArray fromHex: '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54')
!
testRfc4231Case7
	self assert: (HMAC hash: SHA256 key: (ByteArray fromHex: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') message: (ByteArray fromHex: '5468697320697320612074657374207573696e672061206c6172676572207468616e20626c6f636b2d73697a65206b657920616e642061206c6172676572207468616e20626c6f636b2d73697a6520646174612e20546865206b6579206e6565647320746f20626520686173686564206265666f7265206265696e6720757365642062792074686520484d414320616c676f726974686d2e')) equals: (ByteArray fromHex: '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2')
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
