TestCase subclass: #X509CertificateTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

X509CertificateTest comment: 'Tests X509Certificate: the fields and extensions of real certificates (TLSRealChains) and generated ones (TLSTestCertificates), every root of TrustStore default parses, signatures across a chain, host name matching, malformed DER.'!

!X509CertificateTest methodsFor: 'tests'!
testRealLeaf
	| chain leaf |
	chain := TLSRealChains nvidia collect: [:der | X509Certificate fromDer: der].
	leaf := chain first.
	self assert: leaf version equals: 3.
	self assert: leaf subject commonName equals: '*.nvidia.com'.
	self assert: leaf issuer printString equals: 'CN=Amazon RSA 2048 M01, O=Amazon, C=US'.
	self assert: leaf issuer equals: (chain at: 2) subject.
	self assert: leaf serialNumber equals: 16r02911FC25ECA5ACAED621D8EEE784145.
	self assert: leaf notBefore equals: 1768867200.
	self assert: leaf signatureAlgorithm equals: #sha256WithRSAEncryption.
	self assert: leaf signatureHash equals: SHA256.
	self assert: leaf publicKey bitLength equals: 2048.
	self assert: leaf publicKey exponent equals: 65537.
	self deny: leaf isCA.
	self assert: leaf dnsNames equals: #('*.nvidia.com').
	self assert: leaf allowsServerAuth.
	self assert: (leaf hasKeyUsage: #digitalSignature).
	self deny: (leaf hasKeyUsage: #keyCertSign).
	self assert: leaf unhandledCriticalExtensions isEmpty.
	self assert: (chain at: 2) isCA.
	self assert: (chain at: 2) pathLength equals: 0.
	self assert: (chain at: 2) subjectKeyId equals: leaf authorityKeyId
!
testRealSignatures
	| rsa ec |
	rsa := TLSRealChains nvidia collect: [:der | X509Certificate fromDer: der].
	self assert: (rsa first isSignedBy: (rsa at: 2)).
	self assert: ((rsa at: 2) isSignedBy: (rsa at: 3)).
	self deny: (rsa first isSignedBy: (rsa at: 3)).
	ec := TLSRealChains letsEncrypt collect: [:der | X509Certificate fromDer: der].
	self assert: ec first publicKey curve name equals: #p256.
	self assert: ec first signatureAlgorithm equals: #ecdsaWithSHA384.
	self assert: (ec first isSignedBy: (ec at: 2)).
	self assert: ((ec at: 2) isSignedBy: (ec at: 3)).
	self assert: ((ec at: 4) signatureAlgorithm) equals: #sha256WithRSAEncryption.
	self deny: ((ec at: 3) isSignedBy: (ec at: 2))
!
testGeneratedCertificates
	| leaf rsaLeaf |
	leaf := self cert: #leaf.
	self assert: leaf dnsNames equals: #('test.example.com' '*.wild.example.com').
	self assert: leaf ipAddresses equals: {#[10 0 2 2]}.
	self assert: leaf signatureAlgorithm equals: #ecdsaWithSHA384.
	self assert: (leaf isSignedBy: (self cert: #intermediate)).
	self assert: ((self cert: #intermediate) publicKey curve name) equals: #p384.
	self assert: ((self cert: #root) isSignedBy: (self cert: #root)).
	self assert: (self cert: #root) isSelfIssued.
	self assert: (self cert: #criticalLeaf) unhandledCriticalExtensions equals: #('1.3.6.1.4.1.55555.1').
	rsaLeaf := self cert: #rsaLeaf.
	self assert: rsaLeaf signatureAlgorithm equals: #rsassaPss.
	self assert: (rsaLeaf isSignedBy: (self cert: #rsaIntermediate)).
	self assert: (self cert: #rsaIntermediate) signatureAlgorithm equals: #sha384WithRSAEncryption.
	self assert: ((self cert: #rsaIntermediate) isSignedBy: (self cert: #rsaRoot)).
	self assert: (self cert: #rsaRoot) signatureAlgorithm equals: #sha512WithRSAEncryption.
	self assert: ((self cert: #rsaRoot) isSignedBy: (self cert: #rsaRoot))
!
testAllRootsParse
	| store |
	store := TrustStore fromRoots.
	self assert: store size equals: TrustStoreRoots namesAndCertificates size // 2.
	store certificates do: [:each |
		self assert: each notAfter > each notBefore.
		self assert: each subject attributes notEmpty]
!
testHostNames
	| leaf |
	leaf := self cert: #leaf.
	self assert: (leaf matchesHostName: 'test.example.com').
	self assert: (leaf matchesHostName: 'TEST.Example.COM.').
	self assert: (leaf matchesHostName: 'a.wild.example.com').
	self deny: (leaf matchesHostName: 'wild.example.com').
	self deny: (leaf matchesHostName: 'a.b.wild.example.com').
	self deny: (leaf matchesHostName: 'example.com').
	self deny: (leaf matchesHostName: 'xtest.example.com').
	self deny: (leaf matchesHostName: '').
	self assert: (leaf matchesHostName: '10.0.2.2').
	self deny: (leaf matchesHostName: '10.0.2.3').
	self assert: (X509Certificate pattern: '*.nvidia.com' matchesHost: 'inference-api.nvidia.com').
	self deny: (X509Certificate pattern: '*.com' matchesHost: 'nvidia.com').
	self deny: (X509Certificate pattern: 'f*.nvidia.com' matchesHost: 'foo.nvidia.com').
	self deny: (X509Certificate pattern: '*.*.com' matchesHost: 'a.b.com').
	self deny: (X509Certificate pattern: '*.nvidia.com' matchesHost: '.nvidia.com')
!
testMalformed
	| der |
	der := TLSRealChains nvidia first.
	self should: [X509Certificate fromDer: (der copyFrom: 1 to: der size - 1)] raise: TLSError.
	self should: [X509Certificate fromDer: der, #[0]] raise: TLSError.
	self should: [X509Certificate fromDer: #[16r30 0]] raise: TLSError.
	self should: [X509Certificate fromDer: #[]] raise: TLSError
!
testPem
	| pem certs |
	pem := String new writeStream.
	TLSRealChains nvidia do: [:der |
		pem nextPutAll: '-----BEGIN CERTIFICATE-----'; nextPut: Character lf.
		pem nextPutAll: (Base64 encode: der); nextPut: Character lf; nextPutAll: '-----END CERTIFICATE-----'; nextPut: Character lf].
	certs := X509Certificate allFromPem: pem contents.
	self assert: certs size equals: 3.
	self assert: certs first der equals: TLSRealChains nvidia first
! !

!X509CertificateTest methodsFor: 'private'!
cert: aSymbol
	^X509Certificate fromDer: (TLSTestCertificates named: aSymbol)
! !
