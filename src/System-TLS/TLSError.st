Error subclass: #TLSError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-TLS'!

TLSError comment: 'I am a failure of TLS or of what it rests on: malformed DER (Asn1Der), a certificate that cannot be parsed (X509Certificate), a chain that does not validate (CertificateValidator: the message text says which certificate and why), a protocol error.'!
