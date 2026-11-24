CLibrary subclass: #CryptoBackend
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

CryptoBackend comment: 'The cryptography of vm/native/crypto.h: libcrypto hosted (crypto_openssl.c), mbedTLS on UEFI (crypto_mbedtls.c). FFIPrimitives exports it to the image as core_crypto_* (FFIPrimitives-crypto). docs/crypto.md. Not simulated.'!

!CryptoBackend class methodsFor: 'declaring'!
headers
	^#('"crypto.h"')
! !

!CryptoBackend methodsFor: 'calls'!
digest: algId in: inBytes length: inBytesLen out: outBytes length: outBytesLen
	<c: 'int64_t samaltak_crypto_digest(int64_t algId, const uint8_t *inBytes, uint64_t inBytesLen, uint8_t *outBytes, uint64_t outBytesLen)'>
	^-1
!
digestInit: algId state: stateBytes length: stateBytesLen
	<c: 'int64_t samaltak_crypto_digest_init(int64_t algId, uint8_t *stateBytes, uint64_t stateBytesLen)'>
	^-1
!
digestUpdate: algId state: stateBytes length: stateBytesLen in: inBytes length: inBytesLen
	<c: 'int64_t samaltak_crypto_digest_update(int64_t algId, uint8_t *stateBytes, uint64_t stateBytesLen, const uint8_t *inBytes, uint64_t inBytesLen)'>
	^-1
!
digestFinal: algId state: stateBytes length: stateBytesLen out: outBytes length: outBytesLen
	<c: 'int64_t samaltak_crypto_digest_final(int64_t algId, uint8_t *stateBytes, uint64_t stateBytesLen, uint8_t *outBytes, uint64_t outBytesLen)'>
	^-1
!
aeadKey: algId key: keyBytes length: keyBytesLen
	<c: 'int64_t samaltak_crypto_aead_key(int64_t algId, const uint8_t *keyBytes, uint64_t keyBytesLen)'>
	^-1
!
aead: opBits nonceAad: nonceAadBytes length: nonceAadBytesLen text: textBytes length: textBytesLen
	<c: 'int64_t samaltak_crypto_aead(int64_t opBits, const uint8_t *nonceAadBytes, uint64_t nonceAadBytesLen, uint8_t *textBytes, uint64_t textBytesLen)'>
	^-1
!
x25519: kBytes length: kBytesLen u: uBytes length: uBytesLen out: outBytes length: outBytesLen
	<c: 'int64_t samaltak_crypto_x25519(const uint8_t *kBytes, uint64_t kBytesLen, const uint8_t *uBytes, uint64_t uBytesLen, uint8_t *outBytes, uint64_t outBytesLen)'>
	^-1
!
publicKey: spkiBytes length: spkiBytesLen
	<c: 'int64_t samaltak_crypto_public_key(const uint8_t *spkiBytes, uint64_t spkiBytesLen)'>
	^-1
!
verify: keyId params: verifyParams digest: digestBytes length: digestBytesLen signature: sigBytes length: sigBytesLen
	<c: 'int64_t samaltak_crypto_verify(int64_t keyId, int64_t verifyParams, const uint8_t *digestBytes, uint64_t digestBytesLen, const uint8_t *sigBytes, uint64_t sigBytesLen)'>
	^-1
!
chacha20: keyNonceBytes length: keyNonceBytesLen counter: blockCounter text: textBytes length: textBytesLen
	<c: 'int64_t samaltak_crypto_chacha20(const uint8_t *keyNonceBytes, uint64_t keyNonceBytesLen, int64_t blockCounter, uint8_t *textBytes, uint64_t textBytesLen)'>
	^-1
!
backend: outBytes length: outBytesLen
	<c: 'int64_t samaltak_crypto_backend(uint8_t *outBytes, uint64_t outBytesLen)'>
	^-1
! !
