!UefiFFIStubMemory methodsFor: 'static crypto wrappers'!
staticCryptoEntry: name signature: signature
	"The cryptography's core_crypto_* exports (FFIPrimitives-crypto), or 0."
	<function>
	<var: #name type: 'const char *'>
	<var: #signature type: 'uint32_t'>
	<returns: 'uint64_t'>
	(signature = 16r3893 and: [(libc strcmp: name with: 'core_crypto_digest') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoDigest:) to: 'uint64_t'].
	(signature = 16r393 and: [(libc strcmp: name with: 'core_crypto_digest_init') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoDigestInit:) to: 'uint64_t'].
	(signature = 16r3983 and: [(libc strcmp: name with: 'core_crypto_digest_update') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoDigestUpdate:) to: 'uint64_t'].
	(signature = 16r3993 and: [(libc strcmp: name with: 'core_crypto_digest_final') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoDigestFinal:) to: 'uint64_t'].
	(signature = 16r383 and: [(libc strcmp: name with: 'core_crypto_aead_key') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoAeadKey:) to: 'uint64_t'].
	(signature = 16r3893 and: [(libc strcmp: name with: 'core_crypto_aead') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoAead:) to: 'uint64_t'].
	(signature = 16r8893 and: [(libc strcmp: name with: 'core_crypto_x25519') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoX25519:) to: 'uint64_t'].
	(signature = 16r83 and: [(libc strcmp: name with: 'core_crypto_public_key') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoPublicKey:) to: 'uint64_t'].
	(signature = 16r33883 and: [(libc strcmp: name with: 'core_crypto_verify') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoVerify:) to: 'uint64_t'].
	(signature = 16r8393 and: [(libc strcmp: name with: 'core_crypto_chacha20') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoChacha20:) to: 'uint64_t'].
	(signature = 16r93 and: [(libc strcmp: name with: 'core_crypto_backend') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticCryptoBackend:) to: 'uint64_t'].
	^0
!
staticCryptoDigest: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| algId inBytes inBytesLen outBytes outBytesLen |
	algId := self local: 'int64_t'.
	inBytes := self local: 'uint64_t'.
	inBytesLen := self local: 'uint64_t'.
	outBytes := self local: 'uint64_t'.
	outBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: algId) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: inBytes length: inBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: outBytes length: outBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoDigest: algId value in: (self cCoerce: inBytes value to: 'const uint8_t *') length: inBytesLen value out: (self cCoerce: outBytes value to: 'uint8_t *') length: outBytesLen value)
!
staticCryptoDigestInit: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| algId stateBytes stateBytesLen |
	algId := self local: 'int64_t'.
	stateBytes := self local: 'uint64_t'.
	stateBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: algId) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: stateBytes length: stateBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoDigestInit: algId value state: (self cCoerce: stateBytes value to: 'uint8_t *') length: stateBytesLen value)
!
staticCryptoDigestUpdate: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| algId stateBytes stateBytesLen inBytes inBytesLen |
	algId := self local: 'int64_t'.
	stateBytes := self local: 'uint64_t'.
	stateBytesLen := self local: 'uint64_t'.
	inBytes := self local: 'uint64_t'.
	inBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: algId) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: stateBytes length: stateBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 2) into: inBytes length: inBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoDigestUpdate: algId value state: (self cCoerce: stateBytes value to: 'uint8_t *') length: stateBytesLen value in: (self cCoerce: inBytes value to: 'const uint8_t *') length: inBytesLen value)
!
staticCryptoDigestFinal: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| algId stateBytes stateBytesLen outBytes outBytesLen |
	algId := self local: 'int64_t'.
	stateBytes := self local: 'uint64_t'.
	stateBytesLen := self local: 'uint64_t'.
	outBytes := self local: 'uint64_t'.
	outBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: algId) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: stateBytes length: stateBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: outBytes length: outBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoDigestFinal: algId value state: (self cCoerce: stateBytes value to: 'uint8_t *') length: stateBytesLen value out: (self cCoerce: outBytes value to: 'uint8_t *') length: outBytesLen value)
!
staticCryptoAeadKey: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| algId keyBytes keyBytesLen |
	algId := self local: 'int64_t'.
	keyBytes := self local: 'uint64_t'.
	keyBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: algId) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: keyBytes length: keyBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoAeadKey: algId value key: (self cCoerce: keyBytes value to: 'const uint8_t *') length: keyBytesLen value)
!
staticCryptoAead: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| opBits nonceAadBytes nonceAadBytesLen textBytes textBytesLen |
	opBits := self local: 'int64_t'.
	nonceAadBytes := self local: 'uint64_t'.
	nonceAadBytesLen := self local: 'uint64_t'.
	textBytes := self local: 'uint64_t'.
	textBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: opBits) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: nonceAadBytes length: nonceAadBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: textBytes length: textBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoAead: opBits value nonceAad: (self cCoerce: nonceAadBytes value to: 'const uint8_t *') length: nonceAadBytesLen value text: (self cCoerce: textBytes value to: 'uint8_t *') length: textBytesLen value)
!
staticCryptoX25519: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| kBytes kBytesLen uBytes uBytesLen outBytes outBytesLen |
	kBytes := self local: 'uint64_t'.
	kBytesLen := self local: 'uint64_t'.
	uBytes := self local: 'uint64_t'.
	uBytesLen := self local: 'uint64_t'.
	outBytes := self local: 'uint64_t'.
	outBytesLen := self local: 'uint64_t'.
	(wrappers ffiBorrowSlice: (args at: 0) into: kBytes length: kBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: uBytes length: uBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: outBytes length: outBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoX25519: (self cCoerce: kBytes value to: 'const uint8_t *') length: kBytesLen value u: (self cCoerce: uBytes value to: 'const uint8_t *') length: uBytesLen value out: (self cCoerce: outBytes value to: 'uint8_t *') length: outBytesLen value)
!
staticCryptoPublicKey: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| spkiBytes spkiBytesLen |
	spkiBytes := self local: 'uint64_t'.
	spkiBytesLen := self local: 'uint64_t'.
	(wrappers ffiBorrowSlice: (args at: 0) into: spkiBytes length: spkiBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoPublicKey: (self cCoerce: spkiBytes value to: 'const uint8_t *') length: spkiBytesLen value)
!
staticCryptoVerify: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| keyId verifyParams digestBytes digestBytesLen sigBytes sigBytesLen |
	keyId := self local: 'int64_t'.
	verifyParams := self local: 'int64_t'.
	digestBytes := self local: 'uint64_t'.
	digestBytesLen := self local: 'uint64_t'.
	sigBytes := self local: 'uint64_t'.
	sigBytesLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: keyId) ifFalse: [^0].
	(wrappers ffiUnboxI64: (args at: 1) into: verifyParams) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 2) into: digestBytes length: digestBytesLen) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 3) into: sigBytes length: sigBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoVerify: keyId value params: verifyParams value digest: (self cCoerce: digestBytes value to: 'const uint8_t *') length: digestBytesLen value signature: (self cCoerce: sigBytes value to: 'const uint8_t *') length: sigBytesLen value)
!
staticCryptoChacha20: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| keyNonceBytes keyNonceBytesLen blockCounter textBytes textBytesLen |
	keyNonceBytes := self local: 'uint64_t'.
	keyNonceBytesLen := self local: 'uint64_t'.
	blockCounter := self local: 'int64_t'.
	textBytes := self local: 'uint64_t'.
	textBytesLen := self local: 'uint64_t'.
	(wrappers ffiBorrowSlice: (args at: 0) into: keyNonceBytes length: keyNonceBytesLen) ifFalse: [^0].
	(wrappers ffiUnboxI64: (args at: 1) into: blockCounter) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: textBytes length: textBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoChacha20: (self cCoerce: keyNonceBytes value to: 'const uint8_t *') length: keyNonceBytesLen value counter: blockCounter value text: (self cCoerce: textBytes value to: 'uint8_t *') length: textBytesLen value)
!
staticCryptoBackend: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| outBytes outBytesLen |
	outBytes := self local: 'uint64_t'.
	outBytesLen := self local: 'uint64_t'.
	(wrappers ffiBorrowWritableSlice: (args at: 0) into: outBytes length: outBytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeCryptoBackend: (self cCoerce: outBytes value to: 'uint8_t *') length: outBytesLen value)
! !
