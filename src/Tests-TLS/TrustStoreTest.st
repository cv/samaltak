TestCase subclass: #TrustStoreTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

TrustStoreTest comment: 'Tests TrustStore: the default holds the roots TLS to inference-api.nvidia.com and Let''s Encrypt needs; a store of one''s own.'!

!TrustStoreTest methodsFor: 'tests'!
testDefaultRoots
	| store names |
	store := TrustStore default.
	self assert: store size > 100.
	names := store commonNames.
	#('Amazon Root CA 1' 'Starfield Services Root Certificate Authority - G2' 'ISRG Root X1' 'ISRG Root X2') do: [:each |
		self assert: (names includes: each) description: each].
	self assert: TrustStore default == store
!
testOwnStore
	| store root |
	store := TrustStore new.
	self assert: store size equals: 0.
	root := store add: (TLSTestCertificates named: #root).
	self assert: (root isKindOf: X509Certificate).
	store add: root.
	self assert: store size equals: 1.
	self assert: (store includes: root).
	self deny: (store includes: (X509Certificate fromDer: (TLSTestCertificates named: #otherRoot))).
	self assert: (store issuersOf: (X509Certificate fromDer: (TLSTestCertificates named: #intermediate))) equals: {root}.
	self assert: (store issuersOf: root) equals: {root}
! !
