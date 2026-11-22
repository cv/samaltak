TestCase subclass: #DesTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

DesTest comment: 'Tests Des against known answers (FIPS 46''s worked example, all-zero and all-one blocks, a classic textbook vector) and RFB''s VNC authentication (the bit-reversed key), checked against OpenSSL''s DES.'!

!DesTest methodsFor: 'tests'!
testKnownAnswers
	#(#('133457799BBCDFF1' '0123456789ABCDEF' '85e813540f0ab405')
	  #('0000000000000000' '0000000000000000' '8ca64de9c1b123a7')
	  #('FFFFFFFFFFFFFFFF' 'FFFFFFFFFFFFFFFF' '7359b2163e4edc58')) do: [:v |
		self assert: ((Des key: (ByteArray fromHex: v first)) encryptBlock: (ByteArray fromHex: (v at: 2))) hex asLowercase
			equals: (v at: 3)].
	self assert: ((Des key: (ByteArray fromHex: '0123456789ABCDEF')) encryptBlock: 'Now is t' asByteArray) hex asLowercase
		equals: '3fa40e8a984d4815'
!
testDecryptInverts
	| des block |
	des := Des key: (ByteArray fromHex: '0E329232EA6D0D73').
	block := ByteArray fromHex: '8787878787878787'.
	self assert: (des decryptBlock: (des encryptBlock: block)) equals: block.
	self assert: (des encryptBlock: block) hex asLowercase equals: '0000000000000000'
!
testEcb
	| des |
	des := Des key: (ByteArray fromHex: '133457799BBCDFF1').
	self assert: (des encrypt: (ByteArray fromHex: '0123456789ABCDEF0123456789ABCDEF')) hex asLowercase
		equals: '85e813540f0ab40585e813540f0ab405'.
	self should: [des encrypt: (ByteArray new: 7)] raise: CryptoError.
	self should: [Des key: (ByteArray new: 7)] raise: CryptoError
!
testVncKey
	"Each byte's bits reversed; short passwords zero-padded, long ones cut at 8."
	self assert: (Des vncKeyFrom: 'password') hex asLowercase equals: '0e86ceceeef64e26'.
	self assert: (Des vncKeyFrom: 'ab') hex asLowercase equals: '8646000000000000'.
	self assert: (Des vncKeyFrom: 'passwordLONGER') equals: (Des vncKeyFrom: 'password')
!
testVncResponse
	self assert: (Des vncResponseTo: (ByteArray withAll: (0 to: 15)) password: 'password') hex asLowercase
		equals: 'b866924125c8eebb9debc1db61c538e2'.
	self assert: (Des vncResponseTo: (ByteArray fromHex: 'd1e2f3a4b5c6d7e8f90a1b2c3d4e5f60') password: 'Sm4ltak!!') hex asLowercase
		equals: 'f339a427629423a7edba6dbe4441da23'
! !
