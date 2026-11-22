Object subclass: #TLS12RecordCipher
	instanceVariableNames: 'aead iv explicit sequence'
	classVariableNames: ''
	package: 'System-TLS'!

TLS12RecordCipher comment: 'I protect the records of one direction of a TLS 1.2 connection with an AEAD (RFC 5246, section 6.2.3.3): the additional data is the sequence number, the content type, the version and the plaintext''s length. AES-GCM (RFC 5288): the nonce is the 4-byte IV from the key block and 8 explicit bytes sent before the ciphertext (the sequence number); ChaCha20-Poly1305 (RFC 7905): the 12-byte IV XOR the sequence number, nothing explicit. I answer to what TLSRecordCipher does: seal:type:padding: (no padding in TLS 1.2) answers a whole record; open:header: answers {type. content}, the type the header''s, and signals TLSError: bad_record_mac if it does not decrypt, record_overflow if the plaintext is longer than 2^14 bytes.'!

!TLS12RecordCipher methodsFor: 'initialization'!
setAead: anAead iv: aByteArray explicitNonce: aBoolean
	aead := anAead.
	iv := aByteArray.
	explicit := aBoolean.
	sequence := 0
! !

!TLS12RecordCipher methodsFor: 'accessing'!
sequence
	^sequence
! !

!TLS12RecordCipher methodsFor: 'protecting'!
seal: content type: contentType padding: count
	"A protected record of content (at most 2^14 bytes) of contentType; TLS 1.2 has no padding, so count is ignored."
	| bytes seq sealed |
	bytes := content asByteArray.
	seq := self nextSequence.
	sealed := aead encrypt: bytes nonce: (self nonceFor: seq) aad: (self aadFor: seq type: contentType length: bytes size).
	explicit ifTrue: [sealed := seq, sealed].
	^(ByteArray with: contentType with: 3 with: 3 with: (sealed size bitShift: -8) with: (sealed size bitAnd: 255)), sealed
!
open: body header: header
	"{content type. content} of a record's body, given its header."
	| type seq nonce ciphertext plain |
	type := header first.
	seq := self nextSequence.
	explicit
		ifTrue: [
			body size < 24 ifTrue: [^TLSError signal: 'a record too short to decrypt (bad_record_mac)' alert: #badRecordMac].
			nonce := iv, (body copyFrom: 1 to: 8).
			ciphertext := body copyFrom: 9 to: body size]
		ifFalse: [
			body size < 16 ifTrue: [^TLSError signal: 'a record too short to decrypt (bad_record_mac)' alert: #badRecordMac].
			nonce := self nonceFor: seq.
			ciphertext := body].
	plain := [aead decrypt: ciphertext nonce: nonce aad: (self aadFor: seq type: type length: ciphertext size - 16)]
		on: CryptoError do: [:e | ^TLSError signal: 'a record does not decrypt (bad_record_mac)' alert: #badRecordMac].
	plain size > 16384 ifTrue: [^TLSError signal: 'a record longer than 2^14 bytes' alert: #recordOverflow].
	^{type. plain}
! !

!TLS12RecordCipher methodsFor: 'private'!
nextSequence
	"The 8 bytes of the sequence number of this record, which is then the next one's."
	| bytes n |
	sequence >= 16rFFFFFFFFFFFFFFFF ifTrue: [^TLSError signal: 'the sequence number would wrap' alert: #internalError].
	bytes := ByteArray new: 8.
	n := sequence.
	8 to: 1 by: -1 do: [:i |
		bytes at: i put: (n bitAnd: 255).
		n := n bitShift: -8].
	sequence := sequence + 1.
	^bytes
!
nonceFor: seq
	| nonce |
	explicit ifTrue: [^iv, seq].
	nonce := iv copy.
	1 to: 8 do: [:i | nonce at: i + 4 put: ((nonce at: i + 4) bitXor: (seq at: i))].
	^nonce
!
aadFor: seq type: type length: length
	^seq, (ByteArray with: type with: 3 with: 3 with: (length bitShift: -8) with: (length bitAnd: 255))
! !

!TLS12RecordCipher class methodsFor: 'instance creation'!
aead: anAead iv: aByteArray explicitNonce: aBoolean
	^self new setAead: anAead iv: aByteArray explicitNonce: aBoolean
! !
