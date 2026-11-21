TestCase subclass: #HmacHkdfWycheproofTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

HmacHkdfWycheproofTest comment: 'Tests HMAC and HKDF against Wycheproof subsets (WycheproofVectors: modified and truncated tags, HKDF lengths beyond the limit), and their handling of Strings and bad lengths. The AEADs are WycheproofAeadTest''s.'!

!HmacHkdfWycheproofTest methodsFor: 'tests'!
testHmac
	| count |
	count := 0.
	{WycheproofVectors hmacSha256 -> SHA256. WycheproofVectors hmacSha384 -> SHA384. WycheproofVectors hmacSha512 -> SHA512} do: [:each |
		each key do: [:row | | tag mac |
			tag := ByteArray fromHex: (row at: 4).
			mac := HMAC hash: each value key: (ByteArray fromHex: (row at: 2)) message: (ByteArray fromHex: (row at: 3)).
			self assert: ((mac copyFrom: 1 to: tag size) constantTimeEquals: tag) = (row at: 5) description: 'Wycheproof tcId ', (row at: 1) printString.
			count := count + 1]].
	self assert: count > 30
!
testHkdf
	| count |
	count := 0.
	{WycheproofVectors hkdfSha256 -> SHA256. WycheproofVectors hkdfSha384 -> SHA384. WycheproofVectors hkdfSha512 -> SHA512} do: [:each |
		each key do: [:row | | okm prk |
			prk := HKDF hash: each value extract: (ByteArray fromHex: (row at: 3)) ikm: (ByteArray fromHex: (row at: 2)).
			okm := [HKDF hash: each value expand: prk info: (ByteArray fromHex: (row at: 4)) length: (row at: 5)] on: CryptoError do: [:e | nil].
			(row at: 7)
				ifTrue: [self assert: okm = (ByteArray fromHex: (row at: 6)) description: 'Wycheproof tcId ', (row at: 1) printString]
				ifFalse: [self assert: okm isNil description: 'Wycheproof tcId ', (row at: 1) printString].
			count := count + 1]].
	self assert: count > 30
!
testStringsAndLengths
	"A String key is its UTF-8, as a String message is; a negative HKDF length is a CryptoError."
	self
		assert: (HMAC hash: SHA256 key: 'key' message: 'The quick brown fox jumps over the lazy dog')
		equals: (ByteArray fromHex: 'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8').
	self assert: (HMAC hash: SHA256 key: 'key' message: 'x') equals: (HMAC hash: SHA256 key: 'key' asByteArray message: 'x' asByteArray).
	self should: [HKDF hash: SHA256 expand: (ByteArray new: 32) info: #[] length: -1] raise: CryptoError.
	self assert: (HKDF hash: SHA256 expand: (ByteArray new: 32) info: #[] length: 0) isEmpty
! !
