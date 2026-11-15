Object subclass: #HTTPTestServer
	instanceVariableNames: 'listener handler processes clients requests connectionCount'
	classVariableNames: ''
	package: 'Tests-Net'!

HTTPTestServer comment: 'I am a plain-HTTP server on 127.0.0.1 (a free port) for tests: each request (an HTTPTestRequest) on a kept-alive connection goes to my handler, which answers the raw response to send (a String or ByteArray; see the class side for building one), nil when it has written its own to the request''s socket, or #close to close the connection without an answer. I record the requests and count the connections.

	server := HTTPTestServer on: [:request | HTTPTestServer response: 200 body: ''hi''].
	(HTTPClient new get: server url, ''/x'' headers: nil) string.
	server stop'!

!HTTPTestServer methodsFor: 'running'!
setHandler: aBlock
	handler := aBlock.
	processes := OrderedCollection new.
	clients := OrderedCollection new.
	requests := OrderedCollection new.
	connectionCount := 0.
	listener := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 8.
	processes add: [self acceptLoop] fork
!
acceptLoop
	| client |
	[(client := listener accept) notNil] whileTrue: [
		connectionCount := connectionCount + 1.
		clients add: client.
		processes add: [self serve: client] fork]
!
serve: aSocket
	| pending request reply |
	pending := ByteArray new.
	[request := HTTPTestRequest readFrom: aSocket pending: pending.
	 request notNil] whileTrue: [
		pending := request leftover.
		requests add: request.
		reply := handler value: request.
		reply == #close ifTrue: [^aSocket close].
		reply isNil ifFalse: [aSocket sendAll: reply asByteArray]].
	aSocket close
!
closeConnections
	"Close the connections that are open, as a server does with idle ones."
	clients do: [:each | each close]
!
stop
	listener close.
	clients do: [:each | each close].
	processes do: [:each | each isTerminated ifFalse: [each terminate]]
! !

!HTTPTestServer methodsFor: 'accessing'!
url
	^'http://127.0.0.1:', listener localPort printString
!
requests
	^requests
!
connectionCount
	^connectionCount
! !

!HTTPTestServer class methodsFor: 'instance creation'!
on: aBlock
	^self new setHandler: aBlock
! !

!HTTPTestServer class methodsFor: 'responses'!
response: status body: aString
	^self response: status headers: '' body: aString
!
response: status headers: headerLines body: aString
	"headerLines: more header lines, each ending in CR LF."
	| bytes |
	bytes := aString utf8Encoded.
	^('HTTP/1.1 ', status printString, ' X', String crlf, 'Content-Length: ', bytes size printString, String crlf, headerLines, String crlf) asByteArray, bytes
!
chunked: status pieces: pieces
	"A chunked response of status with a chunk for each of pieces (Strings, sent UTF-8 encoded, or ByteArrays)."
	| out |
	out := WriteStream on: (ByteArray new: 256).
	out nextPutAll: ('HTTP/1.1 ', status printString, ' X', String crlf, 'Transfer-Encoding: chunked', String crlf, String crlf) asByteArray.
	pieces do: [:each | | bytes |
		bytes := each isString ifTrue: [each utf8Encoded] ifFalse: [each].
		out nextPutAll: ((bytes size printString: 16), String crlf) asByteArray; nextPutAll: bytes; nextPutAll: String crlf asByteArray].
	out nextPutAll: ('0', String crlf, String crlf) asByteArray.
	^out contents
! !
