TestCase subclass: #CertificateValidatorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

CertificateValidatorTest comment: 'Tests CertificateValidator on real chains (TLSRealChains) against TrustStore default, and on generated ones (TLSTestCertificates) against a store of their root, one broken rule at a time: wrong host, expired, not yet valid, wrong issuer, bad signature, a non-CA issuer, a path length exceeded, an issuer without keyCertSign, a client-only leaf, an unknown critical extension; also unordered chains, cross-signed roots, RSA-PSS.'!

!CertificateValidatorTest methodsFor: 'tests'!
testNvidiaChain
	"*.nvidia.com <- Amazon RSA 2048 M01 <- Amazon Root CA 1, whose copy cross-signed by Starfield G2 the server also sends."
	| path |
	path := CertificateValidator new validate: TLSRealChains nvidia host: 'inference-api.nvidia.com' at: (self year: 2026 month: 6).
	self assert: (path collect: [:each | each subject commonName]) equals: #('*.nvidia.com' 'Amazon RSA 2048 M01' 'Amazon Root CA 1').
	self assert: (TrustStore default includes: path last).
	self deny: path last = (X509Certificate fromDer: TLSRealChains nvidia last).
	self should: [CertificateValidator new validate: TLSRealChains nvidia host: 'nvidia.com' at: (self year: 2026 month: 6)] raise: TLSError.
	self assert: (self reasonFor: TLSRealChains nvidia host: 'inference-api.nvidia.com' at: (self year: 2027 month: 6) store: TrustStore default)
		equals: 'certificate CN=*.nvidia.com expired at 2027-02-18 23:59:59 UTC'
!
testNvidiaChainThroughStarfield
	"Without Amazon Root CA 1 the path goes through its cross-signed copy to Starfield Services G2."
	| store path |
	store := TrustStore new.
	store add: (TrustStore default certificates detect: [:each | each subject commonName = 'Starfield Services Root Certificate Authority - G2']).
	path := CertificateValidator new trustStore: store; validate: TLSRealChains nvidia host: 'inference-api.nvidia.com' at: (self year: 2026 month: 6).
	self assert: path size equals: 4.
	self assert: path last subject commonName equals: 'Starfield Services Root Certificate Authority - G2'
!
testLetsEncryptChain
	| path |
	path := CertificateValidator new validate: TLSRealChains letsEncrypt host: 'www.letsencrypt.org' at: (self year: 2026 month: 12).
	self assert: (path collect: [:each | each subject commonName]) equals: #('letsencrypt.org' 'YE2' 'Root YE' 'ISRG Root X2').
	self assert: (self reasonFor: TLSRealChains letsEncrypt host: 'letsencrypt.org' at: (self year: 2026 month: 12) store: TrustStore new)
		equals: 'certificate CN=ISRG Root X2, O=Internet Security Research Group, C=US is issued by CN=ISRG Root X1, O=Internet Security Research Group, C=US, which is not trusted'
!
testGeneratedChain
	| path |
	path := self validate: #(#leaf #intermediate) host: 'test.example.com'.
	self assert: path size equals: 3.
	self assert: path last equals: (self cert: #root).
	self assert: (self validate: #(#leaf #intermediate) host: 'x.wild.example.com') size equals: 3.
	self assert: (self validate: #(#leaf #intermediate) host: '10.0.2.2') size equals: 3.
	self assert: (self validate: #(#leaf #otherRoot #rsaRoot #intermediate #root) host: 'test.example.com') size equals: 3.
	self assert: (self validate: #(#rsaLeaf #rsaIntermediate) host: 'rsa.example.com' store: #(#rsaRoot)) size equals: 3
!
testCrossSignedRoot
	"The server sends the cross root signed by the test root: trusted through it, or directly when the store has the cross root."
	self assert: (self validate: #(#crossLeaf #crossRootByRoot) host: 'cross.example.com') size equals: 3.
	self assert: (self validate: #(#crossLeaf #crossRootByRoot) host: 'cross.example.com' store: #(#crossRoot)) last
		equals: (self cert: #crossRoot).
	self assert: (self validate: #(#crossLeaf) host: 'cross.example.com' store: #(#crossRoot)) size equals: 2
!
testWrongHost
	self assert: ((self reason: #(#leaf #intermediate) host: 'other.example.com') beginsWith: 'certificate CN=test.example.com, O=Samaltak Test, C=US is not for other.example.com').
	self assert: ((self reason: #(#leaf #intermediate) host: 'a.b.wild.example.com') includesSubstring: 'is not for').
	self assert: ((self reason: #(#leaf #intermediate) host: '10.0.2.3') includesSubstring: 'is not for')
!
testExpired
	self assert: (self reason: #(#expiredLeaf #intermediate) host: 'test.example.com')
		equals: 'certificate CN=test.example.com, O=Samaltak Test, C=US expired at 2021-01-01 00:00:00 UTC'.
	self assert: (self reason: #(#futureLeaf #intermediate) host: 'test.example.com')
		equals: 'certificate CN=test.example.com, O=Samaltak Test, C=US is not valid before 2030-01-01 00:00:00 UTC'.
	self assert: (self reasonFor: (self ders: #(#leaf #intermediate)) host: 'test.example.com' at: (self year: 2039 month: 6) store: (self store: #(#root)))
		equals: 'certificate CN=test.example.com, O=Samaltak Test, C=US expired at 2034-01-01 00:00:00 UTC'.
	self assert: (self reasonFor: (self ders: #(#crossLeaf #crossRootByRoot)) host: 'cross.example.com' at: (self year: 2033 month: 6) store: (self store: #(#root))) isNil.
	self assert: (self reasonFor: (self ders: #(#leaf #intermediate)) host: 'test.example.com' at: (self year: 2033 month: 6) store: (self store: #(#root))) isNil
!
testWrongIssuer
	self assert: ((self reason: #(#otherLeaf) host: 'test.example.com') includesSubstring: 'does not verify with the key of certificate CN=Samaltak Test Root').
	self assert: ((self reason: #(#leaf) host: 'test.example.com') includesSubstring: 'is issued by CN=Samaltak Test Intermediate, O=Samaltak Test, C=US, which is not trusted').
	self assert: ((self reason: #(#leaf #intermediate) host: 'test.example.com' store: #(#otherRoot)) includesSubstring: 'does not verify').
	self assert: ((self reason: #(#rsaLeaf #rsaIntermediate) host: 'rsa.example.com') includesSubstring: 'is issued by CN=Samaltak RSA Root')
!
testBadSignature
	| ders leaf |
	ders := self ders: #(#leaf #intermediate).
	leaf := (ders at: 1) copy.
	leaf at: leaf size put: ((leaf at: leaf size) bitXor: 1).
	ders at: 1 put: leaf.
	self assert: (self reasonFor: ders host: 'test.example.com' at: (self year: 2025 month: 6) store: (self store: #(#root)))
		equals: 'the signature of certificate CN=test.example.com, O=Samaltak Test, C=US does not verify with the key of certificate CN=Samaltak Test Intermediate, O=Samaltak Test, C=US'
!
testNonCAIssuer
	self assert: (self reason: #(#leafOfEndEntity #endEntityIssuer) host: 'test.example.com')
		equals: 'certificate CN=Samaltak Test End Entity, O=Samaltak Test, C=US is not a CA'
!
testPathLength
	self assert: (self reason: #(#leafOfIntermediate2 #intermediate2 #intermediate) host: 'test.example.com')
		equals: 'certificate CN=Samaltak Test Intermediate, O=Samaltak Test, C=US allows 0 intermediate CAs below it, the chain has 1'
!
testKeyUsage
	self assert: (self reason: #(#leafOfNoCertSign #noCertSignIssuer) host: 'test.example.com')
		equals: 'certificate CN=Samaltak Test No Cert Sign, O=Samaltak Test, C=US: its key usage does not allow signing certificates'
!
testExtendedKeyUsage
	self assert: (self reason: #(#clientLeaf #intermediate) host: 'test.example.com')
		equals: 'certificate CN=test.example.com, O=Samaltak Test, C=US is not for server authentication (extKeyUsage)'
!
testCriticalExtension
	self assert: (self reason: #(#criticalLeaf #intermediate) host: 'test.example.com')
		equals: 'certificate CN=test.example.com, O=Samaltak Test, C=US has an unsupported critical extension 1.3.6.1.4.1.55555.1'
!
testChainLength
	| validator |
	validator := CertificateValidator new trustStore: (self store: #(#root)); maxLength: 2.
	self should: [validator validate: (self ders: #(#leaf #intermediate)) host: 'test.example.com' at: (self year: 2025 month: 6)] raise: TLSError.
	self should: [CertificateValidator new validate: #() host: 'test.example.com' at: 0] raise: TLSError.
	self should: [CertificateValidator new validate: {#[1 2 3]} host: 'test.example.com' at: 0] raise: TLSError
! !

!CertificateValidatorTest methodsFor: 'private'!
year: y month: m
	^Asn1Der secondsForYear: y month: m day: 1 hour: 0 minute: 0 second: 0 ifInvalid: [nil]
!
cert: aSymbol
	^X509Certificate fromDer: (TLSTestCertificates named: aSymbol)
!
ders: symbols
	^symbols asArray collect: [:each | TLSTestCertificates named: each]
!
store: symbols
	^TrustStore new addAll: (self ders: symbols); yourself
!
validate: symbols host: host
	^self validate: symbols host: host store: #(#root)
!
validate: symbols host: host store: anchors
	^CertificateValidator new
		trustStore: (self store: anchors);
		validate: (self ders: symbols) host: host at: (self year: 2025 month: 6)
!
reason: symbols host: host
	^self reason: symbols host: host store: #(#root)
!
reason: symbols host: host store: anchors
	^self reasonFor: (self ders: symbols) host: host at: (self year: 2025 month: 6) store: (self store: anchors)
!
reasonFor: ders host: host at: seconds store: aTrustStore
	"Why validating fails, nil if it does not."
	^[CertificateValidator new trustStore: aTrustStore; validate: ders host: host at: seconds. nil]
		on: TLSError do: [:e | e messageText]
! !
