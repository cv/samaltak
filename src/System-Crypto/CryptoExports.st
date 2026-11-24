Object subclass: #CryptoExports
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

CryptoExports comment: 'I am the VM''s cryptography, the core_crypto_* exports (vm/native/crypto.h; docs/crypto.md): libcrypto (OpenSSL 3), hosted; none on UEFI, where every call is a CryptoError (''no crypto on UEFI''). My class side calls them for System-Crypto''s classes: hashes (one-shot, and incremental on a state in the caller''s ByteArray), AEADs sealing and opening in place under a key handle, X25519, ECDSA and RSA verification under a public key''s handle, ChaCha20''s key stream. A VM without them makes every call a CryptoError. Key handles are the VM''s, a table of its own: one whose key the table dropped, or one from another session of the image, is made again (withKey:make:do:).'!

!CryptoExports class methodsFor: 'accessing'!
backend
	"The library the VM's cryptography is, with its version (e.g. 'OpenSSL 3.0.13 30 Jan 2024'); nil without it (UEFI)."
	| b n |
	b := ByteArray new: 128.
	n := self ffiBackend: {b. 1. b size}.
	(n == false or: [n < 0]) ifTrue: [^nil].
	^(b copyFrom: 1 to: n) asString
!
isAvailable
	"Whether this VM has the cryptography exports: hosted, not on UEFI."
	^Firmware current isNil and: [self backend notNil]
!
stateSize
	"The bytes of a hash's state."
	^256
! !

!CryptoExports class methodsFor: 'hashing'!
digest: algorithm size: digestSize of: bytes from: start to: stop
	| out |
	out := ByteArray new: digestSize.
	self check: (self ffiDigest: algorithm in: {bytes. start. stop - start + 1} out: {out. 1. digestSize}).
	^out
!
digestInit: algorithm state: state
	self check: (self ffiDigestInit: algorithm state: {state. 1. state size})
!
digestUpdate: algorithm state: state bytes: bytes from: start to: stop
	self check: (self ffiDigestUpdate: algorithm state: {state. 1. state size} in: {bytes. start. stop - start + 1})
!
digestFinal: algorithm size: digestSize state: state
	| out |
	out := ByteArray new: digestSize.
	self check: (self ffiDigestFinal: algorithm state: {state. 1. state size} out: {out. 1. digestSize}).
	^out
! !

!CryptoExports class methodsFor: 'keys'!
withKey: aHandleHolder make: makeBlock do: useBlock
	"useBlock's answer for the key's handle (aHandleHolder: {handle. session}, kept by the caller), made with makeBlock (answers a handle) when there is none for this session or the VM dropped it."
	| r |
	((aHandleHolder at: 1) isNil or: [(aHandleHolder at: 2) ~~ Smalltalk session]) ifTrue: [
		aHandleHolder at: 1 put: (self check: makeBlock value); at: 2 put: Smalltalk session].
	r := useBlock value: (aHandleHolder at: 1).
	r = -2 ifTrue: [
		aHandleHolder at: 1 put: (self check: makeBlock value).
		r := useBlock value: (aHandleHolder at: 1)].
	^r
!
aeadKey: algorithm bytes: key
	^self ffiAeadKey: algorithm key: {key. 1. key size}
!
aead: op nonceAad: nonceAad text: text
	^self ffiAead: op nonceAad: {nonceAad. 1. nonceAad size} text: {text. 1. text size}
!
publicKey: spki
	^self ffiPublicKey: {spki. 1. spki size}
!
verify: key params: params digest: digest signature: signature
	^self ffiVerify: key params: params digest: {digest. 1. digest size} signature: {signature. 1. signature size}
! !

!CryptoExports class methodsFor: 'operations'!
x25519: k u: u
	"{X25519(k, u). whether it is all zeros}."
	| out r |
	out := ByteArray new: 32.
	r := self check: (self ffiX25519: {k. 1. 32} u: {u. 1. 32} out: {out. 1. 32}).
	^{out. r = 1}
!
chacha20: keyNonce counter: counter xor: bytes from: start count: n
	"Xor n bytes of bytes from start, in place, with ChaCha20's key stream under keyNonce (key || nonce) from block counter."
	self check: (self ffiChacha20: {keyNonce. 1. keyNonce size} counter: counter text: {bytes. start. n})
! !

!CryptoExports class methodsFor: 'private'!
check: r
	"r of an export: a CryptoError if the VM has none, or if r says the arguments were refused or the call failed."
	r == false ifTrue: [
		Firmware current isNil ifFalse: [^CryptoError signal: 'no crypto on UEFI'].
		^CryptoError signal: 'this VM has no cryptography exports'].
	r = -3 ifTrue: [^CryptoError signal: 'the VM''s cryptography refused the arguments'].
	r = -1 ifTrue: [^CryptoError signal: 'the VM''s cryptography failed'].
	^r
! !

!CryptoExports class methodsFor: 'ffi'!
ffiDigest: algorithm in: slice out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_digest' (i64 bytesWithLength writableBytesWithLength) i64)) tryInvoke3: algorithm with: slice with: outSlice
!
ffiDigestInit: algorithm state: stateSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_digest_init' (i64 writableBytesWithLength) i64)) tryInvoke2: algorithm with: stateSlice
!
ffiDigestUpdate: algorithm state: stateSlice in: slice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_digest_update' (i64 writableBytesWithLength bytesWithLength) i64)) tryInvoke3: algorithm with: stateSlice with: slice
!
ffiDigestFinal: algorithm state: stateSlice out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_digest_final' (i64 writableBytesWithLength writableBytesWithLength) i64)) tryInvoke3: algorithm with: stateSlice with: outSlice
!
ffiAeadKey: algorithm key: keySlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_aead_key' (i64 bytesWithLength) i64)) tryInvoke2: algorithm with: keySlice
!
ffiAead: op nonceAad: nonceAadSlice text: textSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_aead' (i64 bytesWithLength writableBytesWithLength) i64)) tryInvoke3: op with: nonceAadSlice with: textSlice
!
ffiX25519: kSlice u: uSlice out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_x25519' (bytesWithLength bytesWithLength writableBytesWithLength) i64)) tryInvoke3: kSlice with: uSlice with: outSlice
!
ffiPublicKey: spkiSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_public_key' (bytesWithLength) i64)) tryInvoke1: spkiSlice
!
ffiVerify: key params: params digest: digestSlice signature: sigSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_verify' (i64 i64 bytesWithLength bytesWithLength) i64)) tryInvoke4: key with: params with: digestSlice with: sigSlice
!
ffiChacha20: keyNonceSlice counter: counter text: textSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_chacha20' (bytesWithLength i64 writableBytesWithLength) i64)) tryInvoke3: keyNonceSlice with: counter with: textSlice
!
ffiBackend: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_crypto_backend' (writableBytesWithLength) i64)) tryInvoke1: outSlice
! !
