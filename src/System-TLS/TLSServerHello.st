Object subclass: #TLSServerHello
	instanceVariableNames: 'version random sessionId cipherSuite compression extensions'
	classVariableNames: ''
	package: 'System-TLS'!

TLSServerHello comment: 'I am a ServerHello or HelloRetryRequest (RFC 8446, sections 4.1.3 and 4.1.4) as parsed from its body (fromBody:): legacy version, random, the session id echoed, the cipher suite (a number), legacy compression and the extensions (type -> data), which I decode on demand: selectedVersion (supported_versions), keyShare ({group. public key}), selectedGroup (a HelloRetryRequest''s key_share), cookie. isHelloRetryRequest tells which of the two I am (by the random). Answers nil for an extension that is not there; malformed ones signal TLSError (decode_error).'!

!TLSServerHello methodsFor: 'initialization'!
readFrom: aByteArray
	| r |
	r := TLSReader on: aByteArray.
	version := r u16.
	random := r next: 32.
	sessionId := r vector8.
	sessionId size > 32 ifTrue: [^TLSError signal: 'decode error: a session id longer than 32 bytes' alert: #decodeError].
	cipherSuite := r u16.
	compression := r u8.
	extensions := r atEnd ifTrue: [Dictionary new] ifFalse: [r extensions].
	r expectEnd
! !

!TLSServerHello methodsFor: 'accessing'!
version
	^version
!
random
	^random
!
sessionId
	^sessionId
!
cipherSuite
	^cipherSuite
!
compression
	^compression
!
extensions
	^extensions
!
selectedVersion
	^self extension: 43 do: [:r | r u16]
!
keyShare
	"The server's share: {group. public key}."
	^self extension: 51 do: [:r | {r u16. r vector16}]
!
selectedGroup
	"The group a HelloRetryRequest asks for."
	^self extension: 51 do: [:r | r u16]
!
cookie
	^self extension: 44 do: [:r | | c |
		c := r vector16.
		c isEmpty ifTrue: [^TLSError signal: 'decode error: an empty cookie' alert: #decodeError].
		c]
! !

!TLSServerHello methodsFor: 'testing'!
isHelloRetryRequest
	^random = self class helloRetryRandom
! !

!TLSServerHello methodsFor: 'private'!
extension: type do: aBlock
	"The value of aBlock on a reader of the extension's data, which it must read whole; nil if there is no such extension."
	| r result |
	r := TLSReader on: (extensions at: type ifAbsent: [^nil]).
	result := aBlock value: r.
	r expectEnd.
	^result
! !

!TLSServerHello class methodsFor: 'instance creation'!
fromBody: aByteArray
	^self new readFrom: aByteArray
! !

!TLSServerHello class methodsFor: 'constants'!
helloRetryRandom
	"SHA-256 of ''HelloRetryRequest'': the random of a HelloRetryRequest (section 4.1.3)."
	^#[16rCF 16r21 16rAD 16r74 16rE5 16r9A 16r61 16r11 16rBE 16r1D 16r8C 16r02 16r1E 16r65 16rB8 16r91 16rC2 16rA2 16r11 16r16 16r7A 16rBB 16r8C 16r5E 16r07 16r9E 16r09 16rE2 16rC8 16rA8 16r33 16r9C]
! !
