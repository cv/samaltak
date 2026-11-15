CLibrary subclass: #OpenSSL
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

OpenSSL comment: 'The OpenSSL 3 calls of the platform layer''s TLS client (PlatformTLS). C''s long and unsigned long are declared as 64-bit (the VM''s targets are LP64). Not simulated.'!

!OpenSSL class methodsFor: 'declaring'!
headers
	^#('<openssl/ssl.h>' '<openssl/err.h>' '<openssl/x509.h>')
!
typedefs
	^#((SSL opaque) (SSL_CTX opaque) (SSL_METHOD opaque))
! !

!OpenSSL methodsFor: 'simulation'!
notSimulated
	^self error: 'OpenSSL is not simulated'
! !

!OpenSSL methodsFor: 'contexts'!
clientMethod
	<c: 'const SSL_METHOD *TLS_client_method(void)'>
	^self notSimulated
!
newContext: method
	<c: 'SSL_CTX *SSL_CTX_new(const SSL_METHOD *method)'>
	^self notSimulated
!
setDefaultVerifyPaths: ctx
	<c: 'int SSL_CTX_set_default_verify_paths(SSL_CTX *ctx)'>
	^self notSimulated
!
setVerify: ctx mode: mode callback: callback
	<c: 'void SSL_CTX_set_verify(SSL_CTX *ctx, int mode, void *callback)'>
	^self notSimulated
!
setMode: ctx mode: mode
	<c: 'int64_t SSL_CTX_set_mode(SSL_CTX *ctx, int64_t mode)'>
	^self notSimulated
!
setOptions: ctx options: options
	<c: 'uint64_t SSL_CTX_set_options(SSL_CTX *ctx, uint64_t options)'>
	^self notSimulated
!
SSL_VERIFY_PEER
	<cMacro: 'int SSL_VERIFY_PEER'>
	^1
!
SSL_MODE_ENABLE_PARTIAL_WRITE
	<cMacro: 'int64_t SSL_MODE_ENABLE_PARTIAL_WRITE'>
	^1
!
SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER
	<cMacro: 'int64_t SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER'>
	^2
!
SSL_OP_IGNORE_UNEXPECTED_EOF
	<cMacro: 'uint64_t SSL_OP_IGNORE_UNEXPECTED_EOF'>
	^128
! !

!OpenSSL methodsFor: 'connections'!
newSSL: ctx
	<c: 'SSL *SSL_new(SSL_CTX *ctx)'>
	^self notSimulated
!
freeSSL: ssl
	<c: 'void SSL_free(SSL *ssl)'>
	^self notSimulated
!
setFd: ssl fd: fd
	<c: 'int SSL_set_fd(SSL *ssl, int fd)'>
	^self notSimulated
!
setServerName: ssl name: name
	"SNI."
	<c: 'int64_t SSL_set_tlsext_host_name(SSL *ssl, const char *name)'>
	^self notSimulated
!
setHost: ssl name: name
	"The name the certificate must match."
	<c: 'int SSL_set1_host(SSL *ssl, const char *name)'>
	^self notSimulated
!
serverName: ssl type: type
	<c: 'const char *SSL_get_servername(const SSL *ssl, const int type)'>
	^self notSimulated
!
setConnectState: ssl
	<c: 'void SSL_set_connect_state(SSL *ssl)'>
	^self notSimulated
!
connect: ssl
	<c: 'int SSL_connect(SSL *ssl)'>
	^self notSimulated
!
read: ssl into: buf count: n done: done
	<c: 'int SSL_read_ex(SSL *ssl, void *buf, size_t n, size_t *done)'>
	^self notSimulated
!
write: ssl bytes: buf count: n done: done
	<c: 'int SSL_write_ex(SSL *ssl, const void *buf, size_t n, size_t *done)'>
	^self notSimulated
!
error: ssl result: r
	<c: 'int SSL_get_error(const SSL *ssl, int r)'>
	^self notSimulated
!
verifyResult: ssl
	<c: 'int64_t SSL_get_verify_result(const SSL *ssl)'>
	^self notSimulated
!
SSL_ERROR_ZERO_RETURN
	<cMacro: 'int SSL_ERROR_ZERO_RETURN'>
	^6
!
SSL_ERROR_WANT_READ
	<cMacro: 'int SSL_ERROR_WANT_READ'>
	^2
!
SSL_ERROR_WANT_WRITE
	<cMacro: 'int SSL_ERROR_WANT_WRITE'>
	^3
!
SSL_ERROR_SYSCALL
	<cMacro: 'int SSL_ERROR_SYSCALL'>
	^5
!
TLSEXT_NAMETYPE_host_name
	<cMacro: 'int TLSEXT_NAMETYPE_host_name'>
	^0
!
X509_V_OK
	<cMacro: 'int64_t X509_V_OK'>
	^0
! !

!OpenSSL methodsFor: 'errors'!
getError
	<c: 'uint64_t ERR_get_error(void)'>
	^self notSimulated
!
clearError
	<c: 'void ERR_clear_error(void)'>
	^self notSimulated
!
errorString: e into: buf size: n
	<c: 'void ERR_error_string_n(uint64_t e, char *buf, size_t n)'>
	^self notSimulated
!
verifyErrorString: code
	<c: 'const char *X509_verify_cert_error_string(int64_t code)'>
	^self notSimulated
! !
