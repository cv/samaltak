!FFIPrimitives methodsFor: 'crypto exports'!
nativeCryptoDigest: algId in: inBytes length: inBytesLen out: outBytes length: outBytesLen
	<function>
	<approvedFFI: 720 symbol: 'core_crypto_digest' arguments: #(3 8 9) result: 3>
	<var: #algId type: 'int64_t'>
	<var: #inBytes type: 'const uint8_t *'>
	<var: #inBytesLen type: 'uint64_t'>
	<var: #outBytes type: 'uint8_t *'>
	<var: #outBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend digest: algId in: inBytes length: inBytesLen out: outBytes length: outBytesLen
!
nativeCryptoDigestInit: algId state: stateBytes length: stateBytesLen
	<function>
	<approvedFFI: 721 symbol: 'core_crypto_digest_init' arguments: #(3 9) result: 3>
	<var: #algId type: 'int64_t'>
	<var: #stateBytes type: 'uint8_t *'>
	<var: #stateBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend digestInit: algId state: stateBytes length: stateBytesLen
!
nativeCryptoDigestUpdate: algId state: stateBytes length: stateBytesLen in: inBytes length: inBytesLen
	<function>
	<approvedFFI: 722 symbol: 'core_crypto_digest_update' arguments: #(3 9 8) result: 3>
	<var: #algId type: 'int64_t'>
	<var: #stateBytes type: 'uint8_t *'>
	<var: #stateBytesLen type: 'uint64_t'>
	<var: #inBytes type: 'const uint8_t *'>
	<var: #inBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend digestUpdate: algId state: stateBytes length: stateBytesLen in: inBytes length: inBytesLen
!
nativeCryptoDigestFinal: algId state: stateBytes length: stateBytesLen out: outBytes length: outBytesLen
	<function>
	<approvedFFI: 723 symbol: 'core_crypto_digest_final' arguments: #(3 9 9) result: 3>
	<var: #algId type: 'int64_t'>
	<var: #stateBytes type: 'uint8_t *'>
	<var: #stateBytesLen type: 'uint64_t'>
	<var: #outBytes type: 'uint8_t *'>
	<var: #outBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend digestFinal: algId state: stateBytes length: stateBytesLen out: outBytes length: outBytesLen
!
nativeCryptoAeadKey: algId key: keyBytes length: keyBytesLen
	<function>
	<approvedFFI: 724 symbol: 'core_crypto_aead_key' arguments: #(3 8) result: 3>
	<var: #algId type: 'int64_t'>
	<var: #keyBytes type: 'const uint8_t *'>
	<var: #keyBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend aeadKey: algId key: keyBytes length: keyBytesLen
!
nativeCryptoAead: opBits nonceAad: nonceAadBytes length: nonceAadBytesLen text: textBytes length: textBytesLen
	<function>
	<approvedFFI: 725 symbol: 'core_crypto_aead' arguments: #(3 8 9) result: 3>
	<var: #opBits type: 'int64_t'>
	<var: #nonceAadBytes type: 'const uint8_t *'>
	<var: #nonceAadBytesLen type: 'uint64_t'>
	<var: #textBytes type: 'uint8_t *'>
	<var: #textBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend aead: opBits nonceAad: nonceAadBytes length: nonceAadBytesLen text: textBytes length: textBytesLen
!
nativeCryptoX25519: kBytes length: kBytesLen u: uBytes length: uBytesLen out: outBytes length: outBytesLen
	<function>
	<approvedFFI: 726 symbol: 'core_crypto_x25519' arguments: #(8 8 9) result: 3>
	<var: #kBytes type: 'const uint8_t *'>
	<var: #kBytesLen type: 'uint64_t'>
	<var: #uBytes type: 'const uint8_t *'>
	<var: #uBytesLen type: 'uint64_t'>
	<var: #outBytes type: 'uint8_t *'>
	<var: #outBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend x25519: kBytes length: kBytesLen u: uBytes length: uBytesLen out: outBytes length: outBytesLen
!
nativeCryptoPublicKey: spkiBytes length: spkiBytesLen
	<function>
	<approvedFFI: 727 symbol: 'core_crypto_public_key' arguments: #(8) result: 3>
	<var: #spkiBytes type: 'const uint8_t *'>
	<var: #spkiBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend publicKey: spkiBytes length: spkiBytesLen
!
nativeCryptoVerify: keyId params: verifyParams digest: digestBytes length: digestBytesLen signature: sigBytes length: sigBytesLen
	<function>
	<approvedFFI: 728 symbol: 'core_crypto_verify' arguments: #(3 3 8 8) result: 3>
	<var: #keyId type: 'int64_t'>
	<var: #verifyParams type: 'int64_t'>
	<var: #digestBytes type: 'const uint8_t *'>
	<var: #digestBytesLen type: 'uint64_t'>
	<var: #sigBytes type: 'const uint8_t *'>
	<var: #sigBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend verify: keyId params: verifyParams digest: digestBytes length: digestBytesLen signature: sigBytes length: sigBytesLen
!
nativeCryptoChacha20: keyNonceBytes length: keyNonceBytesLen counter: blockCounter text: textBytes length: textBytesLen
	<function>
	<approvedFFI: 729 symbol: 'core_crypto_chacha20' arguments: #(8 3 9) result: 3>
	<var: #keyNonceBytes type: 'const uint8_t *'>
	<var: #keyNonceBytesLen type: 'uint64_t'>
	<var: #blockCounter type: 'int64_t'>
	<var: #textBytes type: 'uint8_t *'>
	<var: #textBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend chacha20: keyNonceBytes length: keyNonceBytesLen counter: blockCounter text: textBytes length: textBytesLen
!
nativeCryptoBackend: outBytes length: outBytesLen
	<function>
	<approvedFFI: 730 symbol: 'core_crypto_backend' arguments: #(9) result: 3>
	<var: #outBytes type: 'uint8_t *'>
	<var: #outBytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^cryptoBackend backend: outBytes length: outBytesLen
! !
