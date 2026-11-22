Object subclass: #TLSClientHello
	instanceVariableNames: 'random sessionId cipherSuites serverName groups keyShares signatureSchemes protocols cookie versions extensionTypes bytes'
	classVariableNames: ''
	package: 'System-TLS'!

TLSClientHello comment: 'I am a TLS 1.3 ClientHello (RFC 8446, section 4.1.2): random and legacy_session_id (32 bytes each; a session id for middlebox compatibility, section D.4), the cipher suites (their numbers), and the extensions server_name (serverName, a String; nil for none, e.g. for an IP address), supported_groups (groups), signature_algorithms (signatureSchemes), application_layer_protocol_negotiation (protocols, Strings; empty for none), supported_versions (versions: 16r0304 for TLS 1.3, 16r0303 for TLS 1.2; TLS 1.3 only by default), cookie (nil but after a HelloRetryRequest), key_share (keyShares: pairs {group. public key}); with TLS 1.2 among the versions also ec_point_formats (uncompressed), extended_master_secret (RFC 7627) and an empty renegotiation_info (RFC 5746). bytes answers the handshake message, header included; extensionTypes the extensions it offers. fromBytes: parses one (to check what the client sends, or to replay a recorded one: then bytes are those bytes).

	(TLSClientHello new random: r; sessionId: s; cipherSuites: #(16r1301); serverName: ''example.com''; groups: #(16r1D); keyShares: {{16r1D. publicKey}}; signatureSchemes: #(16r0804); protocols: #(''http/1.1'')) bytes'!

!TLSClientHello methodsFor: 'accessing'!
random
	^random
!
random: aByteArray
	random := aByteArray.
	bytes := nil
!
sessionId
	^sessionId
!
sessionId: aByteArray
	sessionId := aByteArray.
	bytes := nil
!
cipherSuites
	^cipherSuites
!
cipherSuites: codes
	cipherSuites := codes.
	bytes := nil
!
serverName
	^serverName
!
serverName: aStringOrNil
	serverName := aStringOrNil.
	bytes := nil
!
groups
	^groups
!
groups: codes
	groups := codes.
	bytes := nil
!
keyShares
	^keyShares
!
keyShares: pairs
	keyShares := pairs.
	bytes := nil
!
signatureSchemes
	^signatureSchemes
!
signatureSchemes: codes
	signatureSchemes := codes.
	bytes := nil
!
protocols
	^protocols ifNil: [#()]
!
protocols: names
	protocols := names.
	bytes := nil
!
cookie
	^cookie
!
cookie: aByteArrayOrNil
	cookie := aByteArrayOrNil.
	bytes := nil
!
versions
	"The versions offered (supported_versions), the preferred first."
	^versions ifNil: [#(16r0304)]
!
versions: codes
	versions := codes.
	bytes := nil
!
extensionTypes
	"The types of the extensions I offer."
	^extensionTypes ifNil: [self extensions collect: [:each | each key]]
! !

!TLSClientHello methodsFor: 'encoding'!
bytes
	"The handshake message: type, length, body."
	bytes isNil ifTrue: [bytes := TLSWriter new u8: 1; vector24: self body; contents].
	^bytes
!
body
	^TLSWriter new
		u16: 16r0303;
		bytes: random;
		vector8: sessionId;
		vector16Do: [:w | cipherSuites do: [:each | w u16: each]];
		vector8: #[0];
		vector16Do: [:w | self extensions do: [:each | w u16: each key; vector16: each value]];
		contents
!
extensions
	"The extensions in the order they are sent: Associations of type and data."
	| list |
	list := OrderedCollection new.
	serverName isNil ifFalse: [
		list add: 0 -> (TLSWriter contentsOf: [:w | w vector16Do: [:names | names u8: 0; vector16: serverName asByteArray]])].
	(self versions includes: 16r0303) ifTrue: [list add: 11 -> #[1 0]].
	list add: 10 -> (TLSWriter contentsOf: [:w | w vector16Do: [:v | groups do: [:each | v u16: each]]]).
	list add: 13 -> (TLSWriter contentsOf: [:w | w vector16Do: [:v | signatureSchemes do: [:each | v u16: each]]]).
	self protocols isEmpty ifFalse: [
		list add: 16 -> (TLSWriter contentsOf: [:w | w vector16Do: [:v | self protocols do: [:each | v vector8: each asByteArray]]])].
	(self versions includes: 16r0303) ifTrue: [list add: 23 -> #[]].
	list add: 43 -> (TLSWriter contentsOf: [:w | w vector8Do: [:v | self versions do: [:each | v u16: each]]]).
	cookie isNil ifFalse: [list add: 44 -> (TLSWriter contentsOf: [:w | w vector16: cookie])].
	list add: 51 -> (TLSWriter contentsOf: [:w | w vector16Do: [:v | keyShares do: [:each | v u16: each first; vector16: each last]]]).
	(self versions includes: 16r0303) ifTrue: [list add: 16rFF01 -> #[0]].
	^list asArray
! !

!TLSClientHello methodsFor: 'decoding'!
readFrom: aByteArray
	| r body extensions |
	r := TLSReader on: aByteArray.
	r u8 = 1 ifFalse: [^TLSError signal: 'not a ClientHello' alert: #decodeError].
	body := r reader24.
	r expectEnd.
	body u16.
	random := body next: 32.
	sessionId := body vector8.
	cipherSuites := self class u16sIn: body reader16.
	body vector8.
	extensions := body extensions.
	body expectEnd.
	(extensions at: 0 ifAbsent: [nil]) ifNotNil: [:data | | names |
		names := (TLSReader on: data) reader16.
		names u8.
		serverName := names vector16 asString].
	groups := (extensions at: 10 ifAbsent: [nil]) ifNotNil: [:data | self class u16sIn: (TLSReader on: data) reader16].
	signatureSchemes := (extensions at: 13 ifAbsent: [nil]) ifNotNil: [:data | self class u16sIn: (TLSReader on: data) reader16].
	protocols := (extensions at: 16 ifAbsent: [nil]) ifNotNil: [:data | | list names |
		list := (TLSReader on: data) reader16.
		names := OrderedCollection new.
		[list atEnd] whileFalse: [names add: list vector8 asString].
		names asArray].
	cookie := (extensions at: 44 ifAbsent: [nil]) ifNotNil: [:data | (TLSReader on: data) vector16].
	versions := (extensions at: 43 ifAbsent: [nil]) ifNotNil: [:data | self class u16sIn: (TLSReader on: data) reader8].
	keyShares := (extensions at: 51 ifAbsent: [nil]) ifNotNil: [:data | | list shares |
		list := (TLSReader on: data) reader16.
		shares := OrderedCollection new.
		[list atEnd] whileFalse: [shares add: {list u16. list vector16}].
		shares asArray].
	extensionTypes := extensions keys asArray.
	bytes := aByteArray
! !

!TLSClientHello class methodsFor: 'instance creation'!
fromBytes: aByteArray
	"Parse the ClientHello handshake message aByteArray, header included."
	^self new readFrom: aByteArray
! !

!TLSClientHello class methodsFor: 'private'!
u16sIn: aReader
	| list |
	list := OrderedCollection new.
	[aReader atEnd] whileFalse: [list add: aReader u16].
	^list asArray
! !
