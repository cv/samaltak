Error subclass: #TLSError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-TLS'!

TLSError comment: 'I am a failure of TLS or of what it rests on: malformed DER (Asn1Der), a certificate that cannot be parsed (X509Certificate), a connection of the VM''s TLS engine that fails (MbedTLSConnection: mbedTLS''s reason, for a certificate also why it did not verify; a timeout, a closed connection). messageText says why.'!
