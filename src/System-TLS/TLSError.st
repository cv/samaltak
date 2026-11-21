Error subclass: #TLSError
	instanceVariableNames: 'alert fromPeer'
	classVariableNames: ''
	package: 'System-TLS'!

TLSError comment: 'I am a failure of TLS or of what it rests on: malformed DER (Asn1Der), a certificate that cannot be parsed (X509Certificate), a chain that does not validate (CertificateValidator: the message text says which certificate and why), a protocol error of the connection (TLSClientConnection: a message that does not decode, a signature or MAC that does not verify, an alert from the peer, a timeout). messageText says why. alert is the alert (RFC 8446, section 6) to send the peer about it, a Symbol such as #decodeError or #badCertificate (alertCode is its number), or nil to send none (a timeout, a closed connection, an alert the peer sent: isFromPeer).

	TLSError signal: ''decode error: message truncated'' alert: #decodeError.
	TLSError peerAlert: 40	"the peer sent handshake_failure"'!

!TLSError methodsFor: 'accessing'!
alert
	"The alert to send the peer (a Symbol), or nil."
	^alert
!
alert: aSymbol
	alert := aSymbol
!
alertCode
	"The number of my alert on the wire."
	^self class codeOf: alert
!
isFromPeer
	"Did the peer send the alert I report?"
	^fromPeer == true
!
setPeerAlert: aSymbol
	alert := aSymbol.
	fromPeer := true
! !

!TLSError class methodsFor: 'signalling'!
signal: aString alert: aSymbol
	^self new alert: aSymbol; signal: aString
!
peerAlert: code
	"The peer sent the fatal alert numbered code."
	| name |
	name := self nameOf: code.
	^self new setPeerAlert: name; signal: 'the server sent the alert ', (name isSymbol ifTrue: [self wireNameOf: name] ifFalse: [code printString])
! !

!TLSError class methodsFor: 'alerts'!
alerts
	"Pairs of alert name and number (RFC 8446, section 6)."
	^#(#closeNotify 0 #unexpectedMessage 10 #badRecordMac 20 #recordOverflow 22 #handshakeFailure 40 #badCertificate 42
		#unsupportedCertificate 43 #certificateRevoked 44 #certificateExpired 45 #certificateUnknown 46 #illegalParameter 47
		#unknownCa 48 #accessDenied 49 #decodeError 50 #decryptError 51 #protocolVersion 70 #insufficientSecurity 71
		#internalError 80 #inappropriateFallback 86 #userCanceled 90 #missingExtension 109 #unsupportedExtension 110
		#unrecognizedName 112 #badCertificateStatusResponse 113 #unknownPskIdentity 115 #certificateRequired 116
		#noApplicationProtocol 120)
!
codeOf: aSymbol
	| pairs |
	pairs := self alerts.
	1 to: pairs size by: 2 do: [:i | (pairs at: i) == aSymbol ifTrue: [^pairs at: i + 1]].
	^80
!
nameOf: code
	"The alert's name, or code itself if it has none."
	| pairs |
	pairs := self alerts.
	2 to: pairs size by: 2 do: [:i | (pairs at: i) = code ifTrue: [^pairs at: i - 1]].
	^code
!
wireNameOf: aSymbol
	"As RFC 8446 spells it: #badRecordMac is bad_record_mac."
	^String new: aSymbol size + 4 streamContents: [:s |
		aSymbol do: [:c |
			c isUppercase
				ifTrue: [s nextPut: $_; nextPut: c asLowercase]
				ifFalse: [s nextPut: c]]]
! !
