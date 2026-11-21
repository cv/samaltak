Object subclass: #CertificateValidator
	instanceVariableNames: 'trustStore maxLength failure failureDepth'
	classVariableNames: ''
	package: 'System-TLS'!

CertificateValidator comment: 'I validate a TLS server''s certificate chain (RFC 5280, section 6, as browsers apply it) against a TrustStore, for a host name, at a time:

	path := CertificateValidator new
		trustStore: TrustStore default;	"the default"
		validate: certificates host: ''inference-api.nvidia.com'' at: secondsSince1970.

certificates is what the server sent, leaf first: X509Certificates or their DERs. I answer the path, an Array from the leaf to a trust anchor, or signal TLSError saying which certificate failed and why; validate:host: checks at the current time.

The leaf must match the host (X509Certificate>>matchesHostName:, subjectAltName only), be within its validity, allow digitalSignature if it has keyUsage and serverAuth if it has extKeyUsage. Then I build a path depth-first from the leaf: at each certificate first to an anchor whose subject is its issuer and whose key verifies its signature (so an anchor also ends a path where the server sent a cross-signed copy of it), else through each certificate the server sent with that subject (in any order, each at most once), backtracking on failure. Every certificate above the leaf must be within its validity, a CA (basicConstraints; an anchor without extensions counts as one), allowed keyCertSign if it has keyUsage, serverAuth if it has extKeyUsage, with no more CAs below it than its pathLenConstraint; no certificate may have a critical extension I do not understand. Paths are at most maxLength (8) certificates long. When every path fails, the reason given is that of the longest attempt.'!

!CertificateValidator methodsFor: 'accessing'!
trustStore
	^trustStore ifNil: [trustStore := TrustStore default]
!
trustStore: aTrustStore
	trustStore := aTrustStore
!
maxLength
	^maxLength ifNil: [8]
!
maxLength: anInteger
	maxLength := anInteger
! !

!CertificateValidator methodsFor: 'validating'!
validate: certificates host: hostName
	"As validate:host:at:, now."
	^self validate: certificates host: hostName at: Time utcMicroseconds // 1000000
!
validate: certificates host: hostName at: seconds
	"The path from the leaf (first of certificates) to a trust anchor, an Array; TLSError if there is none for hostName at seconds (since 1970 UTC)."
	| chain leaf path |
	chain := certificates asArray collect: [:each |
		(each isKindOf: X509Certificate) ifTrue: [each] ifFalse: [X509Certificate fromDer: each]].
	chain isEmpty ifTrue: [^TLSError signal: 'no certificate'].
	leaf := chain first.
	(leaf matchesHostName: hostName) ifFalse: [
		^TLSError signal: (self describe: leaf), ' is not for ', hostName, ' (names: ', (leaf dnsNames inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ' ', b]]), ')'].
	self check: leaf at: seconds ifBad: [:reason | ^TLSError signal: reason].
	(leaf hasKeyUsage: #digitalSignature) ifFalse: [^TLSError signal: (self describe: leaf), ': its key usage does not allow signatures'].
	leaf allowsServerAuth ifFalse: [^TLSError signal: (self describe: leaf), ' is not for server authentication (extKeyUsage)'].
	failure := nil.
	failureDepth := 0.
	path := self extend: {leaf} with: (chain copyFrom: 2 to: chain size) at: seconds.
	path isNil ifTrue: [^TLSError signal: failure].
	^path
! !

!CertificateValidator methodsFor: 'private'!
extend: path with: candidates at: seconds
	"A path to an anchor that begins with path, nil if none (failure then says why)."
	| cert reason |
	cert := path last.
	(self trustStore includes: cert) ifTrue: [^path].
	path size >= self maxLength ifTrue: [^self failed: 'the chain is longer than ', self maxLength printString, ' certificates' depth: path size].
	(self trustStore issuersOf: cert) do: [:anchor |
		reason := self checkIssuer: anchor of: cert below: path size - 1 at: seconds anchor: true.
		reason isNil ifTrue: [^path copyWith: anchor].
		self failed: reason depth: path size + 1].
	candidates do: [:next | | found |
		(next subject = cert issuer and: [(path includes: next) not]) ifTrue: [
			reason := self checkIssuer: next of: cert below: path size - 1 at: seconds anchor: false.
			reason isNil
				ifTrue: [
					found := self extend: (path copyWith: next) with: candidates at: seconds.
					found notNil ifTrue: [^found]]
				ifFalse: [self failed: reason depth: path size + 1]]].
	^self failed: (self describe: cert), ' is issued by ', cert issuer printString, ', which is not trusted' depth: path size
!
checkIssuer: issuer of: cert below: intermediates at: seconds anchor: isAnchor
	"Nil if issuer may have issued cert, intermediates being the number of CA certificates between it and the leaf; else why not."
	(cert isSignedBy: issuer) ifFalse: [
		^'the signature of ', (self describe: cert), ' does not verify with the key of ', (self describe: issuer)].
	self check: issuer at: seconds ifBad: [:reason | ^reason].
	(issuer isCA or: [isAnchor and: [issuer version < 3]]) ifFalse: [^(self describe: issuer), ' is not a CA'].
	(issuer pathLength notNil and: [intermediates > issuer pathLength]) ifTrue: [
		^(self describe: issuer), ' allows ', issuer pathLength printString, ' intermediate CAs below it, the chain has ', intermediates printString].
	(issuer hasKeyUsage: #keyCertSign) ifFalse: [^(self describe: issuer), ': its key usage does not allow signing certificates'].
	issuer allowsServerAuth ifFalse: [^(self describe: issuer), ' is not for server authentication (extKeyUsage)'].
	^nil
!
check: cert at: seconds ifBad: aBlock
	"Evaluate aBlock with a reason if cert is outside its validity at seconds or has a critical extension I do not understand."
	seconds < cert notBefore ifTrue: [^aBlock value: (self describe: cert), ' is not valid before ', (self class printTime: cert notBefore)].
	seconds > cert notAfter ifTrue: [^aBlock value: (self describe: cert), ' expired at ', (self class printTime: cert notAfter)].
	cert unhandledCriticalExtensions isEmpty ifFalse: [
		^aBlock value: (self describe: cert), ' has an unsupported critical extension ', cert unhandledCriticalExtensions first]
!
failed: reason depth: depth
	"Keep reason if it comes from the longest attempt so far; answer nil."
	depth > failureDepth ifTrue: [
		failure := reason.
		failureDepth := depth].
	^nil
!
describe: cert
	^'certificate ', cert subject printString
! !

!CertificateValidator class methodsFor: 'printing'!
printTime: seconds
	"seconds since 1970 UTC as YYYY-MM-DD hh:mm:ss UTC."
	| s |
	s := seconds \\ 86400.
	^(Date fromDays: seconds // 86400) printString, ' ',
		((s // 3600) printPaddedWith: $0 to: 2), ':',
		((s // 60 \\ 60) printPaddedWith: $0 to: 2), ':',
		((s \\ 60) printPaddedWith: $0 to: 2), ' UTC'
! !
