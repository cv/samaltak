Object subclass: #ControlConnection
	instanceVariableNames: 'server socket process line pending handler buffer jobRequest moved'
	classVariableNames: ''
	package: 'System-Remote'!

ControlConnection comment: 'I serve one remote-control client for the ControlServer: when my socket is readable the server (in its host''s Process, the input dispatcher, or its own) lets me read (pump) without waiting; I split the bytes into lines. With a host, input commands run right there (RemoteControl begin:; an input command''s RemoteInputJob is stepped by my host without waiting, stepJob); eval, wait, screenshot, record and quit, and every request without a host, run in a Process of their own (''remote request'', priority 50). Each response is one JSON line. My further requests wait meanwhile, so the requests of one client are answered in order; other clients are not held up.'!

!ControlConnection methodsFor: 'initialization'!
setServer: aServer socket: aSocket
	server := aServer.
	socket := aSocket
! !

!ControlConnection methodsFor: 'running'!
pump
	"The server's Process (or its host's): read what arrived (never waiting), handle the complete lines; close at end of stream."
	| count |
	line isNil ifTrue: [line := WriteStream on: (ByteArray new: 256). pending := OrderedCollection new].
	buffer isNil ifTrue: [buffer := ByteArray new: 16384].
	[[(count := socket receiveNowInto: buffer) notNil and: [count > 0]] whileTrue: [
		1 to: count do: [:i | | byte |
			byte := buffer at: i.
			byte = 10
				ifTrue: [
					pending add: line contents.
					line := WriteStream on: (ByteArray new: 256)]
				ifFalse: [line nextPut: byte]]].
	 self handlePending.
	 count = 0 ifTrue: [handler isNil ifTrue: [self close]]]
		on: Error do: [:e |
			Smalltalk vm stderrWrite: 'control: connection failed: ', (RemoteControl describeError: e), (String with: Character lf).
			self close]
!
handlePending
	[handler isNil and: [pending notEmpty]] whileTrue: [self handleLine: pending removeFirst]
!
handleLine: aByteArray
	| bytes request |
	bytes := (aByteArray notEmpty and: [aByteArray last = 13]) ifTrue: [aByteArray allButLast] ifFalse: [aByteArray].
	bytes isEmpty ifTrue: [^self].
	request := self requestFrom: bytes.
	request isDictionary ifTrue: [^self respond: request to: nil].
	(server notNil and: [server host notNil and: [(self class transientCommands includes: request command) not]])
		ifTrue: [^self beginInline: request].
	moved := RemoteControl commandStarted: request.
	"Without a host every request runs in a Process of its own while it is handled: commands play input and wait for it, which the input dispatcher (my host) must be free to deliver."
	handler := [
		[self respond: (RemoteControl dispatch: request) to: request]
			ensure: [handler := nil. server isNil ifFalse: [server poke]]] newProcess.
	handler priority: ControlServer priority; name: 'remote request'.
	handler resume
!
beginInline: aRequest
	"In my host's Process (the input dispatcher): answer at once, or start the input command's job, which stepJob continues without ever waiting."
	| r |
	Smalltalk vm workClockQuerying: true.
	r := [RemoteControl begin: aRequest] ensure: [Smalltalk vm workClockQuerying: false].
	r isDictionary ifTrue: [^self respond: r to: aRequest].
	moved := RemoteControl commandStarted: aRequest.
	handler := r.
	jobRequest := aRequest.
	self stepJob
!
stepJob
	"Continue my running input job (host's Process): respond once it is done, else ask the server to wake its host when it is due."
	| r |
	(handler isKindOf: RemoteInputJob) ifFalse: [^self].
	r := RemoteControl step: handler request: jobRequest.
	r isDictionary ifFalse: [^server wakeIn: r].
	handler := nil.
	self respond: r to: jobRequest.
	jobRequest := nil.
	self handlePending
!
respond: aDictionary to: aRequestOrNil
	moved == true ifTrue: [
		moved := false.
		RemoteControl commandFinished].
	socket sendAll: ((JSON render: aDictionary), (String with: Character lf)) utf8Encoded.
	(aRequestOrNil notNil and: [aRequestOrNil afterResponse notNil]) ifTrue: [aRequestOrNil afterResponse value]
!
requestFrom: aByteArray
	"Answer a RemoteRequest, or an error response Dictionary for a malformed line."
	| json |
	json := [JSON parse: (String fromUTF8: aByteArray)] on: Error do: [:e |
		^RemoteControl errorResponse: 'bad request: ', e messageText code: 1].
	json isDictionary ifFalse: [^RemoteControl errorResponse: 'bad request: not a JSON object' code: 1].
	^RemoteRequest on: json connection: self
!
close
	socket close.
	server isNil ifFalse: [server removeConnection: self]
!
abandon
	"My socket died with the VM that saved the image: forget it and end my request's Process."
	socket forget.
	server isNil ifFalse: [server removeConnection: self].
	((handler isKindOf: Process) and: [handler isActiveProcess not]) ifTrue: [handler terminate]
! !

!ControlConnection methodsFor: 'accessing'!
socket
	^socket
!
process
	"The Process handling my current long request, or nil."
	^handler
! !

!ControlConnection class methodsFor: 'commands'!
transientCommands
	"Commands that may wait for long (an evaluation, a wait condition, the compositor): they run in a Process of their own even when the input dispatcher hosts remote control. All other commands are input (or read the widget tree) and run in the host's Process without waiting."
	^#('eval' 'wait' 'screenshot' 'record' 'advance' 'quit')
! !

!ControlConnection class methodsFor: 'instance creation'!
server: aServer socket: aSocket
	^self new setServer: aServer socket: aSocket
! !
