Object subclass: #TLSRecordCipher
	instanceVariableNames: 'aead iv sequence'
	classVariableNames: ''
	package: 'System-TLS'!

TLSRecordCipher comment: 'I protect the records of one direction of a TLS 1.3 connection under one traffic key (RFC 8446, section 5.2): an AEAD, the IV, and the sequence number of the next record, from 0. The nonce of a record is the IV XOR its sequence number (left-padded); the additional data is its header. seal:type:padding: answers a whole record (header and ciphertext) of content of a content type, followed by zeros of padding; open:header: answers {type. content} of the ciphertext of a record, its padding stripped, and signals a TLSError (bad_record_mac) if it does not decrypt, unexpected_message if it has no content type, record_overflow if its plaintext is longer than 2^14 bytes.

	(TLSRecordCipher aead: (AesGcm key: key) iv: iv) seal: ''GET /'' asByteArray type: 23 padding: 0'!

!TLSRecordCipher methodsFor: 'initialization'!
setAead: anAead iv: aByteArray
	aead := anAead.
	iv := aByteArray.
	sequence := 0
! !

!TLSRecordCipher methodsFor: 'accessing'!
sequence
	"The sequence number of the next record."
	^sequence
! !

!TLSRecordCipher methodsFor: 'protecting'!
seal: content type: contentType padding: count
	"A protected record of content (at most 2^14 bytes, with count bytes of padding) of contentType."
	| inner header record |
	inner := ByteArray new: content size + 1 + count.
	inner replaceFrom: 1 to: content size with: content asByteArray startingAt: 1.
	inner at: content size + 1 put: contentType.
	header := ByteArray new: 5.
	header at: 1 put: 23; at: 2 put: 3; at: 3 put: 3.
	header at: 4 put: ((inner size + 16) bitShift: -8); at: 5 put: ((inner size + 16) bitAnd: 255).
	record := header, (aead encrypt: inner nonce: self nextNonce aad: header).
	^record
!
open: ciphertext header: header
	"Answer {content type. content} of a record's ciphertext, given its header."
	| inner end |
	inner := [aead decrypt: ciphertext nonce: self nextNonce aad: header]
		on: CryptoError do: [:e | ^TLSError signal: 'a record does not decrypt (bad_record_mac)' alert: #badRecordMac].
	end := inner size.
	[end > 0 and: [(inner at: end) = 0]] whileTrue: [end := end - 1].
	end = 0 ifTrue: [^TLSError signal: 'a protected record without a content type' alert: #unexpectedMessage].
	end - 1 > 16384 ifTrue: [^TLSError signal: 'a record longer than 2^14 bytes' alert: #recordOverflow].
	^{inner at: end. inner copyFrom: 1 to: end - 1}
! !

!TLSRecordCipher methodsFor: 'private'!
nextNonce
	"The nonce of the record at sequence, which is then the next one's."
	| nonce n i |
	sequence >= 16rFFFFFFFFFFFFFFFF ifTrue: [^TLSError signal: 'the sequence number would wrap' alert: #internalError].
	nonce := iv copy.
	n := sequence.
	i := nonce size.
	[n > 0] whileTrue: [
		nonce at: i put: ((nonce at: i) bitXor: (n bitAnd: 255)).
		n := n bitShift: -8.
		i := i - 1].
	sequence := sequence + 1.
	^nonce
! !

!TLSRecordCipher class methodsFor: 'instance creation'!
aead: anAead iv: aByteArray
	^self new setAead: anAead iv: aByteArray
! !
