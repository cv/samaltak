TestCase subclass: #HTTPClientTest
	instanceVariableNames: 'server client'
	classVariableNames: ''
	package: 'Tests-Net'!

HTTPClientTest comment: 'Tests HTTPClient against an HTTPTestServer over plain TCP: Content-Length and chunked bodies, streaming, keep-alive and reconnecting, request bodies, cancelling by close (also while connecting).

liveTestHTTPS is not in the suite (it needs the network): run it with (HTTPClientTest selector: #liveTestHTTPS) run.'!

!HTTPClientTest methodsFor: 'running'!
serve: aBlock
	server := HTTPTestServer on: aBlock.
	client := HTTPClient new
!
tearDown
	client isNil ifFalse: [client close].
	server isNil ifFalse: [server stop]
!
lambda
	^String with: (Character value: 955)
! !

!HTTPClientTest methodsFor: 'tests'!
testContentLength
	| r |
	self serve: [:request | HTTPTestServer response: 200 headers: 'X-Thing: a', String crlf body: 'hello ', self lambda].
	r := client get: server url, '/a?b=1' headers: nil.
	self assert: r status equals: 200.
	self assert: r isSuccess.
	self assert: r string equals: 'hello ', self lambda.
	self assert: (r headerAt: 'x-thing') equals: 'a'.
	self assert: server requests first path equals: '/a?b=1'.
	self assert: (server requests first headerAt: 'host') equals: '127.0.0.1:', (server url copyAfterLast: $:)
!
testChunked
	| r |
	self serve: [:request | HTTPTestServer chunked: 200 pieces: {'one '. 'two '. self lambda}].
	r := client get: server url, '/' headers: nil.
	self assert: r string equals: 'one two ', self lambda
!
testPostJSONAndForm
	| r form |
	self serve: [:request | HTTPTestServer response: 201 body: '{"ok":true}'].
	r := client post: server url, '/j' json: (Dictionary new at: 'a' put: self lambda; yourself) headers: (Dictionary new at: 'X-Y' put: 'z'; yourself).
	self assert: r status equals: 201.
	self assert: (r json at: 'ok').
	self assert: server requests first method equals: 'POST'.
	self assert: (server requests first headerAt: 'content-type') equals: 'application/json'.
	self assert: (server requests first headerAt: 'x-y') equals: 'z'.
	self assert: (server requests first json at: 'a') equals: self lambda.
	client post: server url, '/f' form: (Dictionary new at: 'code' put: 'a b&c=d/', self lambda; at: 'x' put: '1'; yourself) headers: nil.
	self assert: ((server requests at: 2) headerAt: 'content-type') equals: 'application/x-www-form-urlencoded'.
	form := (server requests at: 2) form.
	self assert: (form at: 'code') equals: 'a b&c=d/', self lambda.
	self assert: (form at: 'x') equals: '1'
!
testStreaming
	"Pieces reach the block as they arrive; a character split across chunks is delivered whole."
	| pieces bytes r |
	bytes := self lambda utf8Encoded.
	self serve: [:request |
		request socket sendAll: ('HTTP/1.1 200 OK', String crlf, 'Transfer-Encoding: chunked', String crlf, String crlf) asByteArray.
		request socket sendAll: ('3', String crlf, 'ab') asByteArray, (bytes copyFrom: 1 to: 1), String crlf asByteArray.
		(Delay forMilliseconds: 50) wait.
		request socket sendAll: ('2', String crlf) asByteArray, (bytes copyFrom: 2 to: 2), ('c', String crlf, '0', String crlf, String crlf) asByteArray.
		nil].
	pieces := OrderedCollection new.
	r := client post: server url, '/s' json: #() headers: nil do: [:s | pieces add: s].
	self assert: r status equals: 200.
	self assert: r body isEmpty.
	self assert: pieces size >= 2.
	self assert: pieces first equals: 'ab'.
	self assert: (pieces inject: '' into: [:all :each | all, each]) equals: 'ab', self lambda, 'c'
!
testStreamingCollectsAnErrorBody
	| called r |
	self serve: [:request | HTTPTestServer response: 400 body: '{"detail":"no"}'].
	called := false.
	r := client post: server url, '/s' json: #() headers: nil do: [:s | called := true].
	self deny: called.
	self assert: r status equals: 400.
	self assert: (r json at: 'detail') equals: 'no'
!
testKeepAlive
	self serve: [:request | HTTPTestServer response: 200 body: request path].
	self assert: (client get: server url, '/1' headers: nil) string equals: '/1'.
	self assert: (client get: server url, '/2' headers: nil) string equals: '/2'.
	self assert: server connectionCount equals: 1
!
testReconnectsWhenTheServerClosedTheConnection
	self serve: [:request | HTTPTestServer response: 200 body: request path].
	self assert: (client get: server url, '/1' headers: nil) string equals: '/1'.
	server closeConnections.
	(Delay forMilliseconds: 20) wait.
	self assert: (client get: server url, '/2' headers: nil) string equals: '/2'.
	self assert: server connectionCount equals: 2
!
testCancelByClose
	| started outcome process |
	self serve: [:request |
		request socket sendAll: ('HTTP/1.1 200 OK', String crlf, 'Transfer-Encoding: chunked', String crlf, String crlf, '1', String crlf, 'a', String crlf) asByteArray.
		nil].
	started := Semaphore new.
	process := self fork: [
		outcome := [client post: server url, '/s' json: #() headers: nil do: [:s | started signal]. #completed]
			on: HTTPError do: [:e | e return: e messageText]].
	self deny: (started waitTimeoutMSecs: 5000).
	client close.
	self assert: (self waitFor: [outcome notNil]).
	self assert: outcome equals: 'request cancelled'
!
testCancelByCloseWhileConnecting
	"The TLS handshake stalls (the server waits for a request); close ends the request when the connect times out."
	| outcome |
	self serve: [:request | nil].
	self fork: [
		outcome := [client get: 'https://127.0.0.1:', (server url copyAfterLast: $:), '/' headers: nil. #completed]
			on: HTTPError do: [:e | e return: e messageText]].
	self assert: (self waitFor: [server connectionCount = 1]).
	client close.
	self assert: (self waitFor: [outcome notNil] timeout: RemoteSocket connectTimeout + 3000).
	self assert: outcome equals: 'request cancelled'
!
testConnectionRefused
	| url |
	self serve: [:request | nil].
	url := server url.
	server stop.
	server := nil.
	self should: [client get: url, '/' headers: nil] raise: HTTPError
!
testCompleteUTF8Size
	| bytes |
	bytes := ('a', self lambda, (String with: (Character value: 16r1F600))) utf8Encoded.
	self assert: (HTTPClient completeUTF8Size: bytes) equals: 7.
	self assert: (HTTPClient completeUTF8Size: (bytes copyFrom: 1 to: 2)) equals: 1.
	self assert: (HTTPClient completeUTF8Size: (bytes copyFrom: 1 to: 3)) equals: 3.
	self assert: (HTTPClient completeUTF8Size: (bytes copyFrom: 1 to: 6)) equals: 3.
	self assert: (HTTPClient completeUTF8Size: ByteArray new) equals: 0
! !

!HTTPClientTest methodsFor: 'live tests'!
liveTestHTTPS
	"Needs the network: a verified GET, then a wrong host name and an expired certificate refused."
	| r |
	client := HTTPClient new.
	r := client get: 'https://example.com/' headers: nil.
	self assert: r status equals: 200.
	self assert: (r string includesSubstring: 'Example Domain').
	self should: [HTTPClient new get: 'https://wrong.host.badssl.com/' headers: nil] raise: HTTPError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'certificate verify failed')].
	self should: [HTTPClient new get: 'https://expired.badssl.com/' headers: nil] raise: HTTPError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'certificate verify failed')]
! !
