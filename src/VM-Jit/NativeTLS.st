CLibrary subclass: #NativeTLS
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

NativeTLS comment: 'The TLS engine (vm/native/tls.c): a TLS 1.3 and 1.2 client on mbedTLS (vm/third_party/mbedtls) over memory buffers, the ciphertext moved by the image over its own TCP or the OS''s. FFIPrimitives exports it to the image as core_tls_* (FFIPrimitives-tls). docs/tls.md. Not simulated.'!

!NativeTLS class methodsFor: 'declaring'!
headers
	^#('"tls.h"')
! !

!NativeTLS methodsFor: 'calls'!
seed: bytes length: bytesLen
	<c: 'int64_t samaltak_tls_seed(const uint8_t *bytes, uint64_t bytesLen)'>
	^-1
!
setTime: seconds
	<c: 'int64_t samaltak_tls_set_time(int64_t seconds)'>
	^-1
!
storeNew
	<c: 'int64_t samaltak_tls_store_new(void)'>
	^-1
!
storeAdd: storeId der: der length: derLen
	<c: 'int64_t samaltak_tls_store_add(int64_t storeHandle, const uint8_t *der, uint64_t derLen)'>
	^-1
!
storeFree: storeId
	<c: 'int64_t samaltak_tls_store_free(int64_t storeHandle)'>
	^-1
!
open: storeId host: host length: hostLen
	<c: 'int64_t samaltak_tls_new(int64_t storeHandle, const uint8_t *host, uint64_t hostLen)'>
	^-1
!
handshake: h in: in length: inLen out: out length: outLen
	<c: 'int64_t samaltak_tls_handshake(int64_t h, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen)'>
	^-1
!
read: h into: plain length: plainLen in: in length: inLen
	<c: 'int64_t samaltak_tls_read(int64_t h, uint8_t *plain, uint64_t plainLen, const uint8_t *in, uint64_t inLen)'>
	^-1
!
write: h bytes: plain length: plainLen out: out length: outLen
	<c: 'int64_t samaltak_tls_write(int64_t h, const uint8_t *plain, uint64_t plainLen, uint8_t *out, uint64_t outLen)'>
	^-1
!
take: h out: out length: outLen
	<c: 'int64_t samaltak_tls_take(int64_t h, uint8_t *out, uint64_t outLen)'>
	^-1
!
close: h out: out length: outLen
	<c: 'int64_t samaltak_tls_close(int64_t h, uint8_t *out, uint64_t outLen)'>
	^-1
!
info: h what: what into: out length: outLen
	<c: 'int64_t samaltak_tls_info(int64_t h, int64_t what, uint8_t *out, uint64_t outLen)'>
	^-1
!
release: h
	<c: 'int64_t samaltak_tls_free(int64_t h)'>
	^-1
! !
