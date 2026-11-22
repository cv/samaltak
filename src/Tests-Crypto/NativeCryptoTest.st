TestCase subclass: #NativeCryptoTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

NativeCryptoTest comment: 'NativeCrypto and the CRC primitives (CryptoPrimitives): every way the work is done (ways: the Smalltalk code, the VM''s portable C, the CPU''s instructions where it has them) passes the standards'' vectors (the tests of vectorClasses, run again each way) and gives the same results for random inputs of the lengths around the block sizes, counter wrap included; the primitives refuse what is not theirs.'!

!NativeCryptoTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!NativeCryptoTest methodsFor: 'private'!
ways
	"Name -> a block that runs a block that way."
	^{
		'Smalltalk' -> [:aBlock | self enabled: false features: 0 do: aBlock].
		'portable C' -> [:aBlock | self enabled: true features: 0 do: aBlock].
		'instructions' -> [:aBlock | self enabled: true features: -1 do: aBlock]}
!
enabled: aBoolean features: mask do: aBlock
	| enabled previous |
	enabled := NativeCrypto enabled.
	previous := NativeCrypto useFeatures: mask.
	NativeCrypto enabled: aBoolean.
	^aBlock ensure: [
		NativeCrypto enabled: enabled.
		NativeCrypto useFeatures: previous]
!
vectorClasses
	^{SHA256Test. SHA384Test. SHA512Test. HMACTest. HKDFTest. HmacHkdfWycheproofTest. AesTest. AesGcmTest. WycheproofAeadTest}
!
randomBytes: n
	"n bytes of a fixed linear congruential sequence."
	| bytes seed |
	bytes := ByteArray new: n.
	seed := 12345.
	1 to: n do: [:i |
		seed := seed * 1103515245 + 12345 bitAnd: 16r7FFFFFFF.
		bytes at: i put: ((seed bitShift: -16) bitAnd: 255)].
	^bytes
!
lengths
	^#(0 1 15 16 17 31 55 56 63 64 65 111 112 127 128 129 255 256 257 1000 4099)
!
resultsFor: data
	"Every operation on data, as a flat Array."
	| out gcm128 gcm256 wrap |
	out := OrderedCollection new.
	gcm128 := AesGcm key: (data copyFrom: 1 to: 16).
	gcm256 := AesGcm key: (data copyFrom: 17 to: 48).
	wrap := (data copyFrom: 49 to: 64) netUint32At: 13 put: 16rFFFFFFFD; yourself.
	self lengths do: [:n | | m |
		m := data copyFrom: 7 to: 6 + n.
		out add: (SHA256 hash: m); add: (SHA384 hash: m); add: (SHA512 hash: m).
		out add: ((SHA256 new) update: data from: 3 to: 2 + n; update: data from: 1 to: n; digest).
		out add: ((SHA512 new) update: data from: 5 to: 4 + n; update: data from: 2 to: n; digest).
		out add: (gcm128 encrypt: m nonce: (data copyFrom: 65 to: 76) aad: (data copyFrom: 3 to: 3 + (n \\ 37))).
		out add: (gcm256 encrypt: m nonce: (data copyFrom: 80 to: 80 + (n \\ 20)) aad: #[]).
		out add: (gcm256 ctr: data from: 9 to: 8 + n into: (ByteArray new: n + 3) at: 2 counter: wrap startingAt: 1).
		out add: ((Aes key: (data copyFrom: 1 to: 24)) encryptBlock: (data copyFrom: n + 1 to: n + 16))].
	^out asArray
! !

!NativeCryptoTest methodsFor: 'tests'!
testFeatures
	| features |
	features := NativeCrypto features.
	self assert: features notNil description: 'the VM has no cryptographic primitives'.
	self assert: (features bitAnd: (1 bitShift: NativeCrypto featureNames size) - 1) equals: features.
	self assert: (NativeCrypto useFeatures: 0) equals: -1 \\ 64.
	[self assert: NativeCrypto features equals: 0] ensure: [NativeCrypto useFeatures: -1].
	self assert: NativeCrypto features equals: features
!
testVectorsEveryWay
	self ways do: [:way |
		way value value: [
			self vectorClasses do: [:class |
				class suite do: [:test | | outcome |
					outcome := TestResult new outcomeOf: test.
					self assert: outcome key == #passed description: [way key, ': ', test printString, ' ', outcome value printString]]]]]
!
testRandomInputsAgree
	| data reference |
	data := self randomBytes: 5000.
	reference := (self ways first value) value: [self resultsFor: data].
	self ways allButFirst do: [:way | | results |
		results := way value value: [self resultsFor: data].
		self assert: results size equals: reference size.
		1 to: results size do: [:i |
			self assert: (results at: i) = (reference at: i) description: [way key, ': result ', i printString, ' differs']]]
!
testCrcEveryWay
	| data |
	data := self randomBytes: 5000.
	(self ways allButFirst) do: [:way |
		way value value: [
			self assert: (Crc32 checksumOf: '123456789' asByteArray) equals: 16rCBF43926.
			self assert: (Crc32c checksumOf: '123456789' asByteArray) equals: 16rE3069283.
			self assert: (Crc32 checksumOf: #[]) equals: 0.
			self lengths do: [:n |
				self assert: (Crc32 update: n bytes: data from: 9 to: 8 + n) equals: (Crc32 tableUpdate: n bytes: data from: 9 to: 8 + n).
				self assert: (Crc32c update: 16rFFFFFFFF - n bytes: data from: 3 to: 2 + n) equals: (Crc32c tableUpdate: 16rFFFFFFFF - n bytes: data from: 3 to: 2 + n)]]]
!
testPrimitivesCheckTheirArguments
	| state keys out |
	state := (1 to: 8) asArray.
	self assert: (NativeCrypto sha256: state bytes: (ByteArray new: 64) from: 1 blocks: 1).
	self deny: (NativeCrypto sha256: state bytes: (ByteArray new: 64) from: 2 blocks: 1).
	self deny: (NativeCrypto sha256: state bytes: (ByteArray new: 64) from: 0 blocks: 1).
	self deny: (NativeCrypto sha256: state bytes: (ByteArray new: 64) from: 1 blocks: -1).
	self deny: (NativeCrypto sha256: (Array new: 7) bytes: (ByteArray new: 64) from: 1 blocks: 1).
	self deny: (NativeCrypto sha256: ((1 to: 8) asArray at: 3 put: (1 bitShift: 32); yourself) bytes: (ByteArray new: 64) from: 1 blocks: 1).
	self deny: (NativeCrypto sha256: state bytes: (Array new: 64) from: 1 blocks: 1).
	self deny: (NativeCrypto sha512: (1 to: 16) asArray bytes: (ByteArray new: 127) from: 1 blocks: 1).
	keys := (Aes key: (ByteArray new: 16)) roundKeys.
	self assert: keys size equals: 176.
	out := ByteArray new: 32.
	self assert: (NativeCrypto aes: keys encrypt: (ByteArray new: 32) from: 1 into: out at: 1 blocks: 2).
	self deny: (NativeCrypto aes: (keys copyFrom: 1 to: 175) encrypt: (ByteArray new: 32) from: 1 into: out at: 1 blocks: 1).
	self deny: (NativeCrypto aes: keys encrypt: (ByteArray new: 32) from: 1 into: out at: 18 blocks: 1).
	self deny: (NativeCrypto aes: keys encrypt: (ByteArray new: 32) from: 1 into: (out copy beReadOnlyObject; yourself) at: 1 blocks: 1).
	self deny: (NativeCrypto aes: keys ctr: (ByteArray new: 15) input: out from: 1 to: 16 into: out at: 1).
	self deny: (NativeCrypto ghash: (ByteArray new: 16) key: (ByteArray new: 15) bytes: out from: 1 to: 16).
	self deny: (NativeCrypto ghash: (ByteArray new: 16) key: (ByteArray new: 16) bytes: out from: 1 to: 33).
	self assert: (Crc32 primUpdate: (1 bitShift: 32) bytes: out from: 1 count: 1) isNil.
	self assert: (Crc32 primUpdate: 0 bytes: out from: 1 count: 33) isNil
! !
