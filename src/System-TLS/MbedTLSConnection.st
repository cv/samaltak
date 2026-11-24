Object subclass: #MbedTLSConnection
	instanceVariableNames: 'socket host trustStore handle session input inStart inCount output sending handshakeMilliseconds negotiated'
	classVariableNames: 'ReadySession Stores'
	package: 'System-TLS'!

MbedTLSConnection comment: 'I am a TLS 1.3 or 1.2 client connection whose protocol is mbedTLS 3.6 in the VM (the TLS engine, vm/native/tls.c, through the core_tls_* exports), the ciphertext moved by me over a connected byte socket: a RemoteSocket over the OS''s TCP or the image''s own (NetworkStack, on UEFI). Each step of the engine reads the ciphertext straight from my input buffer and writes what to send straight into my output buffer, and a read decrypts into the caller''s buffer. Entropy (SecureRandom, reseeding the engine''s CTR_DRBG at each connection), the time (Time utcMicroseconds) and the trust anchors (trustStore: a TrustStore; unless set, the roots of TrustStoreRoots, as TrustStore default has them) come from the image; the engine parses a store''s anchors once a session. The protocol of a TLS connection as TLSSocket uses it: handshakeUntil:, sendAll:, receiveInto:timeout:, close, forget, isOpen, socket; after the handshake version, cipherSuite, protocol (ALPN: http/1.1 offered). A failure signals TLSError, its text mbedTLS''s (for a certificate, why it did not verify). The engine''s state does not outlive the VM: in an image resumed from a snapshot I am closed. docs/tls.md.

	c := MbedTLSConnection on: (RemoteSocket connectTo: ''example.com'' port: 443) host: ''example.com''.
	c handshakeUntil: Time millisecondClockValue + 10000.
	c sendAll: request; receiveInto: buffer timeout: 5000; close.'!

!MbedTLSConnection class methodsFor: 'instance creation'!
on: aSocket host: aString
	^self new setSocket: aSocket host: aString
! !

!MbedTLSConnection class methodsFor: 'engine'!
isAvailable
	"Has the VM the TLS engine (a VM built before it has not)?"
	^[self ensureReady. true] on: TLSError do: [:e | e return: false]
!
ensureReady
	"Seed the engine once a session of the image (the stores of the last one are gone with its VM)."
	| r |
	ReadySession == Smalltalk session ifTrue: [^self].
	r := self new ffiSeed: (SecureRandom default nextBytes: 96).
	r == false ifTrue: [^TLSError signal: 'this VM has no TLS engine'].
	r = 0 ifFalse: [^TLSError signal: 'TLS engine: seeding failed (', r printString, ')'].
	Stores := IdentityDictionary new.
	ReadySession := Smalltalk session
!
storeFor: aTrustStoreOrNil
	"The engine's handle of aTrustStoreOrNil's anchors (nil: TrustStoreRoots', which the engine parses from their DER, without TrustStore default), made once a session and again when the TrustStore grows."
	| key size entry probe h |
	self ensureReady.
	key := aTrustStoreOrNil ifNil: [#default].
	size := aTrustStoreOrNil isNil ifTrue: [0] ifFalse: [aTrustStoreOrNil size].
	entry := Stores at: key ifAbsent: [nil].
	(entry notNil and: [entry last = size]) ifTrue: [^entry first].
	entry isNil ifFalse: [self forgetStore: key].
	Stores size >= 8 ifTrue: [
		(Stores keys reject: [:each | each == #default]) do: [:each | self forgetStore: each]].
	probe := self new.
	h := probe ffiStoreNew.
	(h == false or: [h < 1]) ifTrue: [^TLSError signal: 'TLS engine: no trust store (', h printString, ')'].
	(self anchorDersOf: aTrustStoreOrNil) do: [:der | probe ffiStore: h add: der].
	Stores at: key put: {h. size}.
	^h
!
anchorDersOf: aTrustStoreOrNil
	| pairs |
	aTrustStoreOrNil isNil ifFalse: [^aTrustStoreOrNil certificates collect: [:each | each der]].
	pairs := TrustStoreRoots namesAndCertificates.
	^(2 to: pairs size by: 2) collect: [:i | Base64 decode: (pairs at: i)]
!
forgetStore: aTrustStore
	"Let the engine free aTrustStore's anchors once no connection uses them."
	| entry |
	entry := Stores removeKey: aTrustStore ifAbsent: [^self].
	self new ffiStoreFree: entry first
! !

!MbedTLSConnection methodsFor: 'initialization'!
setSocket: aSocket host: aString
	socket := aSocket.
	host := aString.
	input := ByteArray new: 32768.
	inStart := 1.
	inCount := 0.
	output := ByteArray new: 66560.
	sending := Semaphore forMutualExclusion
! !

!MbedTLSConnection methodsFor: 'configuring'!
trustStore: aTrustStore
	"Trust just aTrustStore's anchors (before the handshake; TrustStore default unless set)."
	trustStore := aTrustStore
! !

!MbedTLSConnection methodsFor: 'accessing'!
socket
	^socket
!
host
	^host
!
handshakeMilliseconds
	^handshakeMilliseconds
!
version
	"The version negotiated: 'TLSv1.3' or 'TLSv1.2' (nil before the handshake)."
	^negotiated ifNotNil: [:n | n first]
!
cipherSuite
	"The cipher suite negotiated, by its IANA name as mbedTLS writes it (TLS1-3-AES-128-GCM-SHA256)."
	^negotiated ifNotNil: [:n | n at: 2]
!
protocol
	"The application protocol ALPN chose, or nil."
	| p |
	p := negotiated ifNotNil: [:n | n last].
	^(p isNil or: [p isEmpty]) ifTrue: [nil] ifFalse: [p]
!
isOpen
	^self isLive and: [socket isOpen]
! !

!MbedTLSConnection methodsFor: 'connection'!
handshakeUntil: deadline
	"Do the handshake, verifying the server's certificate for my host, unless deadline (a millisecondClockValue) passes first; TLSError if it fails, after closing the socket."
	| t0 store r |
	t0 := Time millisecondClockValue.
	store := self class storeFor: trustStore.
	self ffiSeed: (SecureRandom default nextBytes: 96).
	self ffiSetTime: Time utcMicroseconds // 1000000.
	r := self ffiNew: store host: host asByteArray.
	(r == false or: [r < 1]) ifTrue: [socket close. ^TLSError signal: 'TLS engine: no connection (', r printString, ')'].
	handle := r.
	session := Smalltalk session.
	[r := self ffiHandshake: handle in: self inputSlice out: {output. 1. output size}.
	 self step: r.
	 ((self produced: r) > 0 and: [(socket sendAll: output from: 1 to: (self produced: r)) not]) ifTrue: [
		self abort. ^TLSError signal: 'the connection closed'].
	 ((self flags: r) anyMask: 2) ifTrue: [self flushPending].
	 (self flags: r) anyMask: 1] whileFalse: [
		((self flags: r) anyMask: 8) ifTrue: [^self fail].
		(self fillUntil: deadline) ifFalse: [
			self abort.
			^TLSError signal: ((deadline notNil and: [Time millisecondClockValue >= deadline])
				ifTrue: ['timed out'] ifFalse: ['the connection closed'])]].
	handshakeMilliseconds := Time millisecondClockValue - t0.
	negotiated := (0 to: 2) collect: [:i | self info: i]
!
receiveInto: aByteArray timeout: milliseconds
	"Decrypt what arrives into aByteArray from its start: answer the count, 0 at the end (also an end without close_notify, as OpenSSL's TLSSocket reads it), nil if nothing arrived within milliseconds (nil: wait forever)."
	| deadline r n |
	deadline := milliseconds isNil ifFalse: [Time millisecondClockValue + milliseconds].
	[self isLive ifFalse: [^0].
	 r := self ffiRead: handle into: {aByteArray. 1. aByteArray size} in: self inputSlice.
	 self step: r.
	 ((self flags: r) anyMask: 2) ifTrue: [self flushPending].
	 n := self produced: r.
	 n > 0 ifTrue: [^n].
	 ((self flags: r) anyMask: 8) ifTrue: [^self fail].
	 ((self flags: r) anyMask: 1) ifTrue: [^0].
	 n := self receiveWithin: (deadline isNil ifFalse: [(deadline - Time millisecondClockValue) max: 0]).
	 n isNil ifTrue: [^nil].
	 n = 0 ifTrue: [^0]] repeat
!
sendAll: bytes
	"Encrypt and send all of bytes (a ByteArray or ByteString); false once the connection is gone."
	| all start r |
	all := bytes isString ifTrue: [bytes asByteArray] ifFalse: [bytes].
	start := 1.
	^sending critical: [
		[start <= all size and: [self isLive]] whileTrue: [
			r := self ffiWrite: handle bytes: {all. start. all size - start + 1} out: {output. 1. output size}.
			(r == false or: [r < 0]) ifTrue: [^false].
			(socket sendAll: output from: 1 to: (self produced: r)) ifFalse: [^false].
			(((self flags: r) anyMask: 2) and: [self sendPending not]) ifTrue: [^false].
			((self flags: r) anyMask: 8) ifTrue: [^false].
			start := start + (self consumed: r)].
		start > all size]
!
close
	"Send close_notify, then close the socket."
	| r |
	self isLive ifTrue: [
		sending critical: [
			r := self ffiClose: handle out: {output. 1. output size}.
			(r ~~ false and: [r >= 0]) ifTrue: [
				socket sendAll: output from: 1 to: (self produced: r)]]].
	self abort
!
forget
	"In an image resumed from a snapshot: the engine's connection and the socket belonged to the VM that saved it."
	handle := nil.
	socket forget
! !

!MbedTLSConnection methodsFor: 'private'!
isLive
	^handle notNil and: [session == Smalltalk session]
!
inputSlice
	^{input. inStart. inCount}
!
produced: r
	"What a step of the engine produced: plaintext read, or ciphertext into output."
	^r bitAnd: 16rFFFFFF
!
consumed: r
	"What a step consumed: ciphertext from input, or plaintext written."
	^(r bitShift: -24) bitAnd: 16rFFFFFF
!
flags: r
	"1: the handshake is done (a read: close_notify), 2: ciphertext waits in the engine, 4: it needs input, 8: it failed."
	^r bitShift: -48
!
step: r
	"Take what a step of the engine that reads answered: drop the ciphertext it consumed, send what waits in it."
	r == false ifTrue: [self abort. ^TLSError signal: 'this VM has no TLS engine'].
	r < 0 ifTrue: [self abort. ^TLSError signal: 'TLS engine: ', r printString].
	inCount := inCount - (self consumed: r).
	inStart := inCount = 0 ifTrue: [1] ifFalse: [inStart + (self consumed: r)]
!
fail
	"The engine failed the connection: send its alert, close, signal why."
	| why |
	why := self info: 3.
	self flushPending.
	self abort.
	^TLSError signal: why
!
abort
	handle isNil ifFalse: [
		self isLive ifTrue: [self ffiFree: handle].
		handle := nil].
	socket close
!
info: what
	| b n |
	self isLive ifFalse: [^nil].
	b := ByteArray new: 512.
	n := self ffiInfo: handle what: what into: {b. 1. b size}.
	(n == false or: [n < 0]) ifTrue: [^nil].
	^(b copyFrom: 1 to: n) asString
!
flushPending
	"Send what waits in the engine (an alert, a handshake's tail); false if the socket is gone."
	^sending critical: [self sendPending]
!
sendPending
	"flushPending, sending held."
	| r |
	self isLive ifFalse: [^false].
	[r := self ffiTake: handle out: {output. 1. output size}.
	 (r ~~ false and: [r > 0 and: [(self produced: r) > 0]])] whileTrue: [
		(socket sendAll: output from: 1 to: (self produced: r)) ifFalse: [^false]].
	^true
!
fillUntil: deadline
	"More ciphertext from the socket by deadline: false if it closed or deadline passed."
	| n |
	n := self receiveWithin: (deadline isNil ifFalse: [(deadline - Time millisecondClockValue) max: 1]).
	^n notNil and: [n > 0]
!
receiveWithin: milliseconds
	"Receive ciphertext after what input holds (moved to its start): the count, 0 at the end, nil after milliseconds."
	| n |
	(inCount > 0 and: [inStart > 1]) ifTrue: [
		input replaceFrom: 1 to: inCount with: input startingAt: inStart.
		inStart := 1].
	inCount = input size ifTrue: [input := input , (ByteArray new: input size)].
	n := socket receiveInto: input start: inStart + inCount count: input size - inCount - inStart + 1 timeout: milliseconds.
	(n notNil and: [n > 0]) ifTrue: [inCount := inCount + n].
	^n
! !

!MbedTLSConnection methodsFor: 'ffi'!
ffiSeed: bytes
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_seed' (bytesWithLength) i64)) tryInvoke1: {bytes. 1. bytes size}
!
ffiSetTime: seconds
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_set_time' (i64) i64)) tryInvoke1: seconds
!
ffiStoreNew
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_store_new' () i64)) tryInvoke0
!
ffiStore: h add: der
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_store_add' (i64 bytesWithLength) i64)) tryInvoke2: h with: {der. 1. der size}
!
ffiStoreFree: h
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_store_free' (i64) i64)) tryInvoke1: h
!
ffiNew: store host: hostBytes
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_new' (i64 bytesWithLength) i64)) tryInvoke2: store with: {hostBytes. 1. hostBytes size}
!
ffiHandshake: h in: inSlice out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_handshake' (i64 bytesWithLength writableBytesWithLength) i64)) tryInvoke3: h with: inSlice with: outSlice
!
ffiRead: h into: plainSlice in: inSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_read' (i64 writableBytesWithLength bytesWithLength) i64)) tryInvoke3: h with: plainSlice with: inSlice
!
ffiWrite: h bytes: plainSlice out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_write' (i64 bytesWithLength writableBytesWithLength) i64)) tryInvoke3: h with: plainSlice with: outSlice
!
ffiTake: h out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_take' (i64 writableBytesWithLength) i64)) tryInvoke2: h with: outSlice
!
ffiClose: h out: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_close' (i64 writableBytesWithLength) i64)) tryInvoke2: h with: outSlice
!
ffiInfo: h what: what into: slice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_info' (i64 i64 writableBytesWithLength) i64)) tryInvoke3: h with: what with: slice
!
ffiFree: h
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_tls_free' (i64) i64)) tryInvoke1: h
! !
