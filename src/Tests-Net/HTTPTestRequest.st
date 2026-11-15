Object subclass: #HTTPTestRequest
	instanceVariableNames: 'method path headers body socket leftover'
	classVariableNames: ''
	package: 'Tests-Net'!

HTTPTestRequest comment: 'I am a request an HTTPTestServer received: method, path, headers (lowercase names), body bytes (Content-Length), and the socket to answer on.'!

!HTTPTestRequest methodsFor: 'initialization'!
setHead: aString body: bytes socket: aSocket leftover: moreBytes
	| lines first colon |
	lines := aString lines.
	first := lines first subStrings: ' '.
	method := first first.
	path := first at: 2.
	headers := Dictionary new.
	lines allButFirst do: [:line |
		colon := line indexOf: $:.
		colon > 0 ifTrue: [headers at: (line copyFrom: 1 to: colon - 1) asLowercase put: (line copyFrom: colon + 1 to: line size) trimBoth]].
	body := bytes.
	socket := aSocket.
	leftover := moreBytes
! !

!HTTPTestRequest methodsFor: 'accessing'!
method
	^method
!
path
	^path
!
headers
	^headers
!
headerAt: aString
	^headers at: aString asLowercase ifAbsent: [nil]
!
body
	^body
!
json
	^JSON parse: body utf8Decoded
!
form
	"The body as application/x-www-form-urlencoded fields."
	| fields |
	fields := Dictionary new.
	(body asString subStrings: '&') do: [:pair |
		| i |
		i := pair indexOf: $=.
		fields at: (self class percentDecode: (pair copyFrom: 1 to: i - 1)) put: (self class percentDecode: (pair copyFrom: i + 1 to: pair size))].
	^fields
!
socket
	^socket
!
leftover
	^leftover
! !

!HTTPTestRequest class methodsFor: 'reading'!
readFrom: aSocket pending: bytes
	"The next request on aSocket (bytes: what was read past the previous one), or nil when the connection ends."
	| all chunk n headEnd head length |
	all := bytes.
	chunk := ByteArray new: 4096.
	[(headEnd := all indexOfSubCollection: #[13 10 13 10]) = 0] whileTrue: [
		n := aSocket receiveInto: chunk.
		n = 0 ifTrue: [^nil].
		all := all, (chunk copyFrom: 1 to: n)].
	head := (all copyFrom: 1 to: headEnd - 1) asString.
	length := ((head lines detect: [:l | l asLowercase beginsWith: 'content-length:'] ifNone: ['x:0']) copyAfter: $:) trimBoth asInteger.
	[all size < (headEnd + 3 + length)] whileTrue: [
		n := aSocket receiveInto: chunk.
		n = 0 ifTrue: [^nil].
		all := all, (chunk copyFrom: 1 to: n)].
	^self new
		setHead: head
		body: (all copyFrom: headEnd + 4 to: headEnd + 3 + length)
		socket: aSocket
		leftover: (all copyFrom: headEnd + 4 + length to: all size)
!
percentDecode: aString
	| out i |
	out := WriteStream on: (ByteArray new: aString size).
	i := 1.
	[i <= aString size] whileTrue: [
		(aString at: i) = $%
			ifTrue: [
				out nextPut: ((aString at: i + 1) digitValue * 16) + (aString at: i + 2) digitValue.
				i := i + 3]
			ifFalse: [
				out nextPut: ((aString at: i) = $+ ifTrue: [32] ifFalse: [(aString at: i) value]).
				i := i + 1]].
	^out contents utf8Decoded
! !
