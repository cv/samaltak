Object subclass: #TLSSurvey
	instanceVariableNames: 'trustStore timeout parallel lock'
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSSurvey comment: 'I try the VM''s TLS engine (MbedTLSConnection) on real servers, for tools/tls-survey (which compares my verdicts with OpenSSL''s) and by hand; nothing in the test suite uses me, as I need the internet.

	TLSSurvey new probe: ''github.com''.	"a line: host, ok or fail, details"
	TLSSurvey new run: #(''github.com'' ''example.com:443'') parallel: 8.	"a line each on the Transcript, as they finish"
	TLSSurvey new download: ''https://speed.cloudflare.com/__down?bytes=100000000''.	"throughput, the engine and OpenSSL''s"
	TLSSurvey new repeat: 50 host: ''example.com''.	"sequential connections: handshake times"

probe: connects (trusting trustStore, the default roots unless set), does the handshake, sends HEAD / with Connection: close and reads until the server closes. Its line is tab-separated: host, ok or fail, handshake ms, cipher suite, the version, ALPN, the response''s status line, bytes received, and for a failure why.'!

!TLSSurvey methodsFor: 'accessing'!
trustStore: aTrustStore
	trustStore := aTrustStore
!
timeout
	"Milliseconds for the connect and handshake, and again for the response."
	^timeout ifNil: [15000]
!
timeout: milliseconds
	timeout := milliseconds
! !

!TLSSurvey methodsFor: 'probing'!
probe: hostSpec
	"A tab-separated line about a TLS connection to hostSpec (host or host:port)."
	| host port deadline plain connection fields response received |
	host := hostSpec copyUpTo: $:.
	port := (hostSpec includes: $:) ifTrue: [(hostSpec copyAfter: $:) asNumber] ifFalse: [443].
	fields := OrderedCollection with: hostSpec.
	deadline := Time millisecondClockValue + self timeout.
	plain := [RemoteSocket connectTo: host port: port until: deadline] on: Error do: [:e |
		^self line: (fields add: 'fail'; add: 'connect: ', e messageText asString; yourself)].
	connection := MbedTLSConnection on: plain host: host.
	trustStore isNil ifFalse: [connection trustStore: trustStore].
	[connection handshakeUntil: deadline] on: TLSError do: [:e |
		connection close.
		^self line: (fields add: 'fail'; add: e messageText asString; yourself)].
	fields add: 'ok'; add: connection handshakeMilliseconds printString.
	fields add: connection cipherSuite; add: connection version; add: (connection protocol ifNil: ['-']).
	[response := self head: host over: connection] on: Error do: [:e |
		connection close.
		^self line: (fields add: 'after the handshake: ', e messageText asString; yourself)].
	received := response first.
	fields add: ((received copyUpTo: Character cr) copyUpTo: Character lf); add: received size printString.
	response last isNil ifFalse: [fields add: response last].
	^self line: fields
!
head: host over: connection
	"{the response (a String). nil, or why it ended badly} to HEAD / with Connection: close."
	| out buffer n deadline |
	connection sendAll: 'HEAD / HTTP/1.1', String crlf, 'Host: ', host, String crlf, 'User-Agent: samaltak-tls-survey', String crlf,
		'Accept: */*', String crlf, 'Connection: close', String crlf, String crlf.
	out := WriteStream on: String new.
	buffer := ByteArray new: 16384.
	deadline := Time millisecondClockValue + self timeout.
	[n := [connection receiveInto: buffer timeout: (deadline - Time millisecondClockValue max: 0)] on: TLSError do: [:e |
		(e messageText includesSubstring: 'without close_notify') ifFalse: [e pass].
		^{out contents. 'no close_notify'}].
	 n isNil ifTrue: [connection close. ^{out contents. 'no close within ', self timeout printString, ' ms'}].
	 n > 0] whileTrue: [out nextPutAll: (buffer copyFrom: 1 to: n) asString].
	connection close.
	^{out contents. nil}
!
run: hostSpecs parallel: count
	"Probe each of hostSpecs, count at a time; show each line on the Transcript as it comes; answer the lines in hostSpecs' order."
	| queue lines done |
	queue := SharedQueue new.
	hostSpecs doWithIndex: [:each :i | queue nextPut: i -> each].
	lines := Array new: hostSpecs size.
	lock := Semaphore forMutualExclusion.
	done := Semaphore new.
	count timesRepeat: [
		[| job line |
		 [(job := queue nextOrNil) notNil] whileTrue: [
			line := [self probe: job value] on: Error do: [:e | job value, '	fail	error: ', e class name, ': ', e messageText asString].
			lines at: job key put: line.
			lock critical: [Transcript show: line; cr]].
		 done signal] fork].
	count timesRepeat: [done wait].
	^lines
! !

!TLSSurvey methodsFor: 'probing'!
runFile: path parallel: count
	"run:parallel: on the hosts of the file at path, one a line (the first word; # comments)."
	| specs |
	specs := OrderedCollection new.
	(File readText: path) lines do: [:each | | words |
		words := each substrings: (String with: Character space with: Character tab).
		(words notEmpty and: [words first first ~= $#]) ifTrue: [specs add: words first]].
	^self run: specs asArray parallel: count
! !

!TLSSurvey methodsFor: 'load'!
download: url
	"Get url with my engine and then with OpenSSL's (where there is one), reading and dropping the body: a line each with the bytes, the milliseconds and the MB/s."
	| results |
	results := OrderedCollection new.
	results add: (self download: url engine: #mbedtls).
	results add: (self download: url engine: #platform).
	^results
!
download: url engine: aSymbol
	"GET url with Connection: close over a TLSSocket, counting what comes until the server closes."
	| old target start socket buffer n bytes ms status first |
	target := HTTPClient parse: url.
	old := TLSSocket engine.
	TLSSocket engine: aSymbol.
	bytes := 0.
	start := Time millisecondClockValue.
	status := [socket := TLSSocket connectTo: (target at: 2) port: (target at: 3) timeout: self timeout.
		socket sendAll: 'GET ', (target at: 4), ' HTTP/1.1', String crlf, 'Host: ', (target at: 2), String crlf,
			'User-Agent: samaltak-tls-survey', String crlf, 'Connection: close', String crlf, String crlf.
		buffer := ByteArray new: 65536.
		[(n := socket receiveInto: buffer timeout: self timeout) notNil and: [n > 0]] whileTrue: [
			first isNil ifTrue: [first := ((buffer copyFrom: 1 to: (n min: 64)) asString copyUpTo: Character cr)].
			bytes := bytes + n].
		socket close.
		n isNil ifTrue: ['stalled after ', bytes printString] ifFalse: [first]]
			on: Error do: [:e | e messageText asString].
	TLSSocket engine: old.
	ms := Time millisecondClockValue - start max: 1.
	^(aSymbol == #platform ifTrue: ['openssl'] ifFalse: [aSymbol]), '	', status asString, '	', bytes printString, ' bytes	', ms printString, ' ms	',
		(bytes / 1000.0 / ms roundTo: 0.01) printString, ' MB/s'
!
repeat: count host: hostSpec
	"Probe hostSpec count times in a row: the number that worked, and the handshake times' minimum, median and maximum."
	| times failures lines |
	times := OrderedCollection new.
	failures := Bag new.
	count timesRepeat: [| line fields |
		line := self probe: hostSpec.
		fields := line substrings: (String with: Character tab).
		(fields at: 2) = 'ok'
			ifTrue: [times add: (fields at: 3) asNumber]
			ifFalse: [failures add: fields last]].
	times := times asSortedCollection asArray.
	lines := hostSpec, ': ', times size printString, ' of ', count printString, ' ok'.
	times isEmpty ifFalse: [
		lines := lines, ', handshake ms min ', times first printString, ' median ', (times at: times size + 1 // 2) printString, ' max ', times last printString].
	failures isEmpty ifFalse: [lines := lines, ', failures: ', failures asSet asArray printString].
	^lines
! !

!TLSSurvey methodsFor: 'private'!
line: fields
	^fields inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, (String with: Character tab), b]]
! !
