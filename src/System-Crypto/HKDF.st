Object subclass: #HKDF
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

HKDF comment: 'I am HKDF (RFC 5869) over a CryptoHash class, on my class side: HKDF hash: SHA256 extract: salt ikm: ikm answers the pseudorandom key (digestSize bytes; an empty or nil salt is digestSize zeros), HKDF hash: SHA256 expand: prk info: info length: n answers n bytes of key material, n at most 255 × digestSize (else CryptoError). TLS 1.3''s HKDF-Expand-Label is expand:info:length: with the label''s HkdfLabel as info.'!

!HKDF class methodsFor: 'deriving'!
hash: aHashClass extract: salt ikm: ikm
	^HMAC hash: aHashClass key: ((salt isNil or: [salt isEmpty]) ifTrue: [ByteArray new: aHashClass digestSize] ifFalse: [salt]) message: ikm
!
hash: aHashClass expand: prk info: info length: n
	| okm t i mac |
	n > (255 * aHashClass digestSize) ifTrue: [^CryptoError signal: 'HKDF: more than 255 blocks of output'].
	n < 0 ifTrue: [^CryptoError signal: 'HKDF: a negative length'].
	okm := ByteArray new: n.
	t := #[].
	i := 0.
	[i * aHashClass digestSize < n] whileTrue: [
		i := i + 1.
		mac := HMAC hash: aHashClass key: prk.
		mac update: t; update: info; update: (ByteArray with: i).
		t := mac digest.
		okm replaceFrom: (i - 1) * t size + 1 to: (i * t size min: n) with: t startingAt: 1].
	^okm
! !
