Object subclass: #X509Certificate
	instanceVariableNames: 'der tbs version serialNumber signatureAlgorithm signatureHash pssSaltLength signature issuer subject notBefore notAfter publicKeyAlgorithm publicKey extensions isCA pathLength keyUsage extKeyUsage dnsNames ipAddresses subjectKeyId authorityKeyId unhandledCriticalExtensions'
	classVariableNames: ''
	package: 'System-TLS'!

X509Certificate comment: 'I am an X.509 v3 certificate (RFC 5280), parsed from its DER encoding. TLSError if the encoding is malformed.

	cert := X509Certificate fromDer: bytes.
	cert subject; issuer.	"X509Names"
	cert serialNumber; notBefore; notAfter.	"Integers; times in seconds since 1970 UTC"
	cert publicKey.	"an RsaPublicKey or EcPublicKey (P-256, P-384); nil for another kind (P-521, Ed25519...)"
	cert isCA; pathLength; keyUsage; extKeyUsage; dnsNames; ipAddresses.
	cert isSignedBy: issuerCert.
	cert matchesHostName: ''api.example.com''.

Extensions: basicConstraints (isCA, pathLength: nil if unlimited), keyUsage (nil if absent, else an Integer whose bit n is named bit n: hasKeyUsage: #digitalSignature, #keyCertSign...), extKeyUsage (nil if absent, else an Array of OID strings: allowsServerAuth), subjectAltName (dnsNames: Strings; ipAddresses: ByteArrays of 4 or 16), subjectKeyId and authorityKeyId (ByteArrays or nil). extensions maps each OID to {critical. value bytes}; unhandledCriticalExtensions lists the critical ones I do not understand, which a validator must refuse. Signature algorithms: sha256/384/512WithRSAEncryption, RSASSA-PSS (MGF1 with the same SHA-2 hash, any salt length its parameters give), ecdsa-with-SHA256/384/512; signatureAlgorithm is a Symbol (#unsupported for another).'!

!X509Certificate methodsFor: 'accessing'!
der
	^der
!
tbsBytes
	"The signed part, as encoded."
	^tbs
!
version
	"1, 2 or 3."
	^version
!
serialNumber
	^serialNumber
!
signatureAlgorithm
	"#sha256WithRSAEncryption, #sha384WithRSAEncryption, #sha512WithRSAEncryption, #rsassaPss, #ecdsaWithSHA256, #ecdsaWithSHA384, #ecdsaWithSHA512 or #unsupported."
	^signatureAlgorithm
!
signatureHash
	"The hash class of my signature (SHA256, SHA384, SHA512), nil if unsupported."
	^signatureHash
!
signature
	^signature
!
issuer
	^issuer
!
subject
	^subject
!
notBefore
	^notBefore
!
notAfter
	^notAfter
!
publicKeyAlgorithm
	"The OID of my key's algorithm."
	^publicKeyAlgorithm
!
publicKey
	^publicKey
!
extensions
	^extensions
!
isCA
	^isCA
!
pathLength
	"basicConstraints' pathLenConstraint, nil if none."
	^pathLength
!
keyUsage
	^keyUsage
!
extKeyUsage
	^extKeyUsage
!
dnsNames
	^dnsNames
!
ipAddresses
	^ipAddresses
!
subjectKeyId
	^subjectKeyId
!
authorityKeyId
	^authorityKeyId
!
unhandledCriticalExtensions
	^unhandledCriticalExtensions
! !

!X509Certificate methodsFor: 'testing'!
isSelfIssued
	^issuer = subject
!
isValidAt: seconds
	"Whether seconds (since 1970 UTC) is within my validity period."
	^seconds between: notBefore and: notAfter
!
hasKeyUsage: aSymbol
	"Whether my keyUsage extension is absent or allows aSymbol (#digitalSignature, #nonRepudiation, #keyEncipherment, #dataEncipherment, #keyAgreement, #keyCertSign, #cRLSign, #encipherOnly, #decipherOnly)."
	| bit |
	keyUsage isNil ifTrue: [^true].
	bit := #(#digitalSignature #nonRepudiation #keyEncipherment #dataEncipherment #keyAgreement #keyCertSign #cRLSign #encipherOnly #decipherOnly) indexOf: aSymbol.
	bit = 0 ifTrue: [^self error: 'no key usage ', aSymbol printString].
	^(keyUsage bitAt: bit) = 1
!
allowsServerAuth
	"Whether my extKeyUsage extension is absent or includes serverAuth or anyExtendedKeyUsage."
	^extKeyUsage isNil or: [(extKeyUsage includes: '1.3.6.1.5.5.7.3.1') or: [extKeyUsage includes: '2.5.29.37.0']]
!
isSignedBy: issuerCertificate
	"Whether my signature verifies with issuerCertificate's public key (names are not compared)."
	^self verifySignatureWith: issuerCertificate publicKey
!
verifySignatureWith: aKey
	"Whether my signature over my tbsBytes verifies with aKey (an RsaPublicKey or EcPublicKey)."
	aKey isNil ifTrue: [^false].
	(signatureAlgorithm == #rsassaPss) ifTrue: [
		^(aKey isKindOf: RsaPublicKey) and: [aKey verifyPss: signature message: tbs hash: signatureHash saltLength: pssSaltLength]].
	(#(#sha256WithRSAEncryption #sha384WithRSAEncryption #sha512WithRSAEncryption) includes: signatureAlgorithm) ifTrue: [
		^(aKey isKindOf: RsaPublicKey) and: [aKey verifyPkcs1: signature message: tbs hash: signatureHash]].
	(#(#ecdsaWithSHA256 #ecdsaWithSHA384 #ecdsaWithSHA512) includes: signatureAlgorithm) ifTrue: [
		^(aKey isKindOf: EcPublicKey) and: [aKey verify: signature message: tbs hash: signatureHash]].
	^false
!
matchesHostName: aString
	"Whether I am a certificate for the host aString (RFC 6125, RFC 9110): an IPv4 address must be one of my IP address SANs; a DNS name must match one of my DNS SANs, ignoring ASCII case and a trailing dot, where a SAN *.rest (a wildcard as the whole leftmost label, rest of at least two labels) matches one label in its place. The subject's common name is not consulted."
	| host ip |
	host := aString asLowercase.
	(host notEmpty and: [host last = $.]) ifTrue: [host := host copyFrom: 1 to: host size - 1].
	host isEmpty ifTrue: [^false].
	ip := self class ipv4BytesOf: host.
	ip notNil ifTrue: [^ipAddresses includes: ip].
	^dnsNames anySatisfy: [:pattern | self class pattern: pattern asLowercase matchesHost: host]
! !

!X509Certificate methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [der = anObject der]
!
hash
	^der hash
! !

!X509Certificate methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an X509Certificate ('; print: subject; nextPut: $)
! !

!X509Certificate methodsFor: 'private'!
setDer: bytes
	| outer t algorithm spki ext |
	der := bytes.
	outer := Asn1Der on: bytes.
	t := outer readSequence.
	outer expectEnd.
	tbs := t readElementBytes.
	algorithm := t readElementBytes.
	self parseSignatureAlgorithm: algorithm.
	signature := t readBitString.
	t expectEnd.
	t := (Asn1Der on: tbs) readSequence.
	version := 1.
	(t nextIs: 16rA0) ifTrue: [
		ext := t readExplicit: 0.
		version := ext readInteger + 1.
		ext expectEnd.
		(version between: 2 and: 3) ifFalse: [^TLSError signal: 'X.509: unsupported version ', version printString]].
	serialNumber := t readInteger.
	t readElementBytes = algorithm ifFalse: [^TLSError signal: 'X.509: the signature algorithms differ'].
	issuer := X509Name fromDer: t readElementBytes.
	ext := t readSequence.
	notBefore := ext readTime.
	notAfter := ext readTime.
	ext expectEnd.
	subject := X509Name fromDer: t readElementBytes.
	spki := t readSequence.
	self parsePublicKey: spki.
	(t nextIs: 16r81) ifTrue: [t skip].
	(t nextIs: 16r82) ifTrue: [t skip].
	isCA := false.
	dnsNames := #().
	ipAddresses := #().
	extensions := Dictionary new.
	unhandledCriticalExtensions := OrderedCollection new.
	(t nextIs: 16rA3) ifTrue: [
		version = 3 ifFalse: [^TLSError signal: 'X.509: extensions in a version ', version printString, ' certificate'].
		ext := t readExplicit: 3.
		self parseExtensions: ext readSequence.
		ext expectEnd].
	t expectEnd.
	unhandledCriticalExtensions := unhandledCriticalExtensions asArray
!
parseSignatureAlgorithm: bytes
	| r oid params |
	r := (Asn1Der on: bytes) readSequence.
	oid := r readOid.
	signatureAlgorithm := #unsupported.
	oid = '1.2.840.113549.1.1.10' ifTrue: [
		params := r readSequence.
		r expectEnd.
		^self parsePssParameters: params].
	#(#('1.2.840.113549.1.1.11' #sha256WithRSAEncryption #SHA256)
	  #('1.2.840.113549.1.1.12' #sha384WithRSAEncryption #SHA384)
	  #('1.2.840.113549.1.1.13' #sha512WithRSAEncryption #SHA512)) do: [:each |
		(each at: 1) = oid ifTrue: [
			(r nextIs: 5) ifTrue: [r readNull].
			r expectEnd.
			signatureAlgorithm := each at: 2.
			^signatureHash := self class hashNamed: (each at: 3)]].
	#(#('1.2.840.10045.4.3.2' #ecdsaWithSHA256 #SHA256)
	  #('1.2.840.10045.4.3.3' #ecdsaWithSHA384 #SHA384)
	  #('1.2.840.10045.4.3.4' #ecdsaWithSHA512 #SHA512)) do: [:each |
		(each at: 1) = oid ifTrue: [
			r expectEnd.
			signatureAlgorithm := each at: 2.
			^signatureHash := self class hashNamed: (each at: 3)]]
!
parsePssParameters: r
	"RSASSA-PSS-params (RFC 4055): the hash, MGF1 with the same hash, the salt length, trailer field 1. Defaults (SHA-1) are unsupported."
	| hashOid mgf mgfHash e trailer |
	(r nextIs: 16rA0) ifFalse: [^self].
	e := r readExplicit: 0.
	hashOid := self class readHashAlgorithm: e.
	e expectEnd.
	(r nextIs: 16rA1) ifFalse: [^self].
	e := r readExplicit: 1.
	mgf := e readSequence.
	e expectEnd.
	mgf readOid = '1.2.840.113549.1.1.8' ifFalse: [^self].
	mgfHash := self class readHashAlgorithm: mgf.
	mgf expectEnd.
	pssSaltLength := 20.
	(r nextIs: 16rA2) ifTrue: [
		e := r readExplicit: 2.
		pssSaltLength := e readInteger.
		e expectEnd].
	(r nextIs: 16rA3) ifTrue: [
		e := r readExplicit: 3.
		trailer := e readInteger.
		e expectEnd.
		trailer = 1 ifFalse: [^self]].
	r expectEnd.
	(hashOid = mgfHash and: [pssSaltLength >= 0]) ifFalse: [^self].
	signatureHash := self class hashNamed: (self class hashNameOfOid: hashOid).
	signatureHash isNil ifFalse: [signatureAlgorithm := #rsassaPss]
!
parsePublicKey: spki
	| alg params key r |
	alg := spki readSequence.
	publicKeyAlgorithm := alg readOid.
	params := alg atEnd ifTrue: [nil] ifFalse: [alg readElementBytes].
	alg expectEnd.
	key := spki readBitString.
	spki expectEnd.
	publicKey := nil.
	(publicKeyAlgorithm = '1.2.840.113549.1.1.1' or: [publicKeyAlgorithm = '1.2.840.113549.1.1.10']) ifTrue: [
		r := (Asn1Der on: key) readSequence.
		publicKey := [RsaPublicKey modulus: r readInteger exponent: r readInteger] on: CryptoError do: [:e | nil].
		r expectEnd.
		^self].
	(publicKeyAlgorithm = '1.2.840.10045.2.1' and: [params notNil]) ifTrue: [
		r := Asn1Der on: params.
		(r nextIs: 6) ifFalse: [^self].
		params := r readOid.
		r expectEnd.
		params := params = '1.2.840.10045.3.1.7' ifTrue: [#p256] ifFalse: [params = '1.3.132.0.34' ifTrue: [#p384] ifFalse: [^self]].
		publicKey := [EcPublicKey curve: params point: key] on: CryptoError do: [:e | nil]]
!
parseExtensions: r
	| e oid critical value |
	r atEnd ifTrue: [^TLSError signal: 'X.509: empty extensions'].
	[r atEnd] whileFalse: [
		e := r readSequence.
		oid := e readOid.
		critical := (e nextIs: 1) ifTrue: [e readBoolean] ifFalse: [false].
		value := e readOctetString.
		e expectEnd.
		(extensions includesKey: oid) ifTrue: [^TLSError signal: 'X.509: duplicate extension ', oid].
		extensions at: oid put: {critical. value}.
		((self parseExtension: oid value: value) not and: [critical]) ifTrue: [unhandledCriticalExtensions add: oid]]
!
parseExtension: oid value: bytes
	"Parse the extension oid; answer whether I understand it."
	| r s tag names ips |
	r := Asn1Der on: bytes.
	oid = '2.5.29.19' ifTrue: [
		s := r readSequence.
		(s nextIs: 1) ifTrue: [isCA := s readBoolean].
		(s nextIs: 2) ifTrue: [
			pathLength := s readInteger.
			pathLength < 0 ifTrue: [^TLSError signal: 'X.509: negative pathLenConstraint']].
		s expectEnd.
		r expectEnd.
		^true].
	oid = '2.5.29.15' ifTrue: [
		keyUsage := r readNamedBits.
		r expectEnd.
		^true].
	oid = '2.5.29.37' ifTrue: [
		s := r readSequence.
		extKeyUsage := OrderedCollection new.
		[s atEnd] whileFalse: [extKeyUsage add: s readOid].
		extKeyUsage := extKeyUsage asArray.
		r expectEnd.
		^true].
	oid = '2.5.29.17' ifTrue: [
		s := r readSequence.
		names := OrderedCollection new.
		ips := OrderedCollection new.
		[s atEnd] whileFalse: [
			tag := s peekTag.
			tag = 16r82
				ifTrue: [names add: (s readContentsOf: 16r82) asString]
				ifFalse: [tag = 16r87
					ifTrue: [ips add: (s readContentsOf: 16r87)]
					ifFalse: [s skip]]].
		r expectEnd.
		dnsNames := names asArray.
		ipAddresses := ips asArray.
		^true].
	oid = '2.5.29.14' ifTrue: [
		subjectKeyId := r readOctetString.
		r expectEnd.
		^true].
	oid = '2.5.29.35' ifTrue: [
		s := r readSequence.
		(s nextIs: 16r80) ifTrue: [authorityKeyId := s readContentsOf: 16r80].
		^true].
	"Certificate policies and policy constraints: understood as accepting any policy, as browsers do."
	^#('2.5.29.32' '2.5.29.36' '2.5.29.54') includes: oid
! !

!X509Certificate class methodsFor: 'instance creation'!
fromDer: bytes
	"The certificate encoded in bytes. TLSError if they are not one."
	^self new setDer: bytes asByteArray
!
fromPem: aString
	"The first certificate in PEM text (between BEGIN and END CERTIFICATE lines)."
	^(self allFromPem: aString) first
!
allFromPem: aString
	"Every certificate in PEM text, in order."
	| certs inside body |
	certs := OrderedCollection new.
	inside := false.
	aString lines do: [:line |
		(line beginsWith: '-----BEGIN CERTIFICATE-----')
			ifTrue: [inside := true. body := WriteStream on: String new]
			ifFalse: [(line beginsWith: '-----END CERTIFICATE-----')
				ifTrue: [
					inside ifTrue: [certs add: (self fromDer: (Base64 decode: body contents))].
					inside := false]
				ifFalse: [inside ifTrue: [body nextPutAll: line]]]].
	^certs asArray
! !

!X509Certificate class methodsFor: 'private'!
hashNamed: aSymbol
	"The hash class aSymbol names (SHA256, SHA384, SHA512), nil if absent."
	^aSymbol isNil ifTrue: [nil] ifFalse: [Smalltalk at: aSymbol ifAbsent: [nil]]
!
hashNameOfOid: oidString
	| i |
	i := #('2.16.840.1.101.3.4.2.1' '2.16.840.1.101.3.4.2.2' '2.16.840.1.101.3.4.2.3') indexOf: oidString.
	^i = 0 ifTrue: [nil] ifFalse: [#(#SHA256 #SHA384 #SHA512) at: i]
!
readHashAlgorithm: r
	"The OID of a hash's AlgorithmIdentifier (parameters absent or NULL)."
	| s oid |
	s := r readSequence.
	oid := s readOid.
	(s nextIs: 5) ifTrue: [s readNull].
	s expectEnd.
	^oid
!
ipv4BytesOf: aString
	"The 4 bytes of a dotted-decimal IPv4 address, nil if aString is not one."
	| parts |
	parts := aString substrings: '.'.
	(parts size = 4 and: [(aString occurrencesOf: $.) = 3]) ifFalse: [^nil].
	(parts allSatisfy: [:p | p notEmpty and: [p size <= 3 and: [(p allSatisfy: [:c | c isDigit]) and: [p asNumber <= 255]]]])
		ifFalse: [^nil].
	^ByteArray withAll: (parts collect: [:p | p asNumber])
!
pattern: pattern matchesHost: host
	"RFC 6125, section 6.4.3, as browsers do it: exact, or a wildcard that is the whole leftmost label matching one non-empty label."
	| p rest i |
	p := (pattern notEmpty and: [pattern last = $.]) ifTrue: [pattern copyFrom: 1 to: pattern size - 1] ifFalse: [pattern].
	(p includes: $*) ifFalse: [^p = host].
	(p beginsWith: '*.') ifFalse: [^false].
	rest := p copyFrom: 3 to: p size.
	((rest includes: $*) or: [(rest occurrencesOf: $.) < 1]) ifTrue: [^false].
	i := host indexOf: $..
	i <= 1 ifTrue: [^false].
	^(host copyFrom: i + 1 to: host size) = rest
! !
