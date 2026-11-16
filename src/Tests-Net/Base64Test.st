TestCase subclass: #Base64Test
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Net'!

Base64Test comment: 'Tests Base64 decoding: both alphabets, padding or none.'!

!Base64Test methodsFor: 'tests'!
testDecode
	self assert: (Base64 decode: 'aGVsbG8=') asString equals: 'hello'.
	self assert: (Base64 decode: 'aGVsbG8') asString equals: 'hello'.
	self assert: (Base64 decode: 'aGk=') asString equals: 'hi'.
	self assert: (Base64 decode: 'aGk') asString equals: 'hi'.
	self assert: (Base64 decode: '') isEmpty
!
testAlphabets
	self assert: (Base64 decode: '+/8=') equals: #[251 255].
	self assert: (Base64 decode: '-_8') equals: #[251 255]
!
testJWTClaims
	"The payload of a JSON Web Token: URL alphabet, no padding."
	| claims |
	claims := JSON parse: (Base64 decode: 'eyJlbWFpbCI6ImFAZXhhbXBsZS5jb20iLCJuIjoiw7wifQ') utf8Decoded.
	self assert: (claims at: 'email') equals: 'a@example.com'.
	self assert: (claims at: 'n') equals: (String with: (Character value: 252))
!
testBadCharacter
	self should: [Base64 decode: 'ab*c'] raise: Error
!
testEncode
	self assert: (Base64 encode: #[]) equals: ''.
	self assert: (Base64 encode: #[102]) equals: 'Zg=='.
	self assert: (Base64 encode: #[102 111]) equals: 'Zm8='.
	self assert: (Base64 encode: #[102 111 111]) equals: 'Zm9v'.
	self assert: (Base64 decode: (Base64 encode: (ByteArray withAll: (0 to: 255)))) equals: (ByteArray withAll: (0 to: 255))
! !
