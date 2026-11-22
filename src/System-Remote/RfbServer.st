Object subclass: #RfbServer
	instanceVariableNames: 'socket port host process connections lock source token password allowNone maxClients authLock failures blockedUntil backoffMs desktopName maxRate'
	classVariableNames: 'Current MadePassword'
	package: 'System-Remote'!

RfbServer comment: 'I am the remote display: an RFB (VNC) server (RFC 6143) serving the screen of a frame source (RfbFrameSource) to viewers such as macOS Screen Sharing and TigerVNC, one RfbConnection each. docs/remote.md: bound to 127.0.0.1 by default like the control service; through an SSH tunnel or on a trusted network, since nothing is encrypted.

Authentication, by what each client speaks:
	RFB 3.3 (Screen Sharing): the server picks: VNC authentication (2) with my password, a separate random 8 characters, never derived from the token (DES of a challenge: anyone who sees one exchange can search the password offline).
	RFB 3.7/3.8 (TigerVNC): a list: VeNCrypt (19) with its Plain subtype (256), the password being the session token (ControlServer''s), and VNC authentication if I have a password.
	None (1) only when allowNone is set (tests) and I listen on 127.0.0.1 only: TigerVNC picks None whenever it is offered.
Each failed authentication makes the next wait: 1 s, doubling to 32 s, back to none after a success (authenticate:). At most maxClients (4) clients at once: one more is told why and closed; a client that asks for exclusive access (ClientInit shared = 0) disconnects the others.

Started by --display (from the startup list): --display-port N (5900; 0 picks a free one), --display-host address (127.0.0.1), --display-port-file path, --display-vnc-auth (offer VNC authentication, for Screen Sharing; the password from --display-password-file path, else made and shown once: display: password ...), --display-allow-none (tests, honoured on 127.0.0.1 only), --display-rate N (updates a second, 60).

My Process (''rfb server'', priority 45, below the network stack and the compositor) accepts; each connection runs its own two.'!

!RfbServer methodsFor: 'initialization'!
initialize
	host := '127.0.0.1'.
	lock := Semaphore forMutualExclusion.
	authLock := Semaphore forMutualExclusion.
	connections := OrderedCollection new.
	failures := 0.
	blockedUntil := 0
! !

!RfbServer methodsFor: 'starting and stopping'!
startOn: aPort host: aHost source: aSource
	host := aHost.
	source := aSource.
	socket := RemoteSocket listenOn: aPort host: aHost backlog: 8.
	port := socket localPort.
	process := [self acceptLoop] forkAt: self class priority named: 'rfb server'
!
acceptLoop
	| client |
	[(client := socket accept) notNil] whileTrue: [
		[(self newConnectionOn: client) start] on: Error do: [:e | client close. e return: nil]]
!
newConnectionOn: aSocket
	| connection |
	connection := RfbConnection server: self socket: aSocket.
	lock critical: [connections add: connection].
	^connection
!
removeConnection: aConnection
	lock critical: [connections remove: aConnection ifAbsent: []]
!
stop
	| all |
	socket isNil ifFalse: [socket close].
	all := lock critical: [connections copy].
	all do: [:each | each close].
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate]
!
abandon
	"In an image resumed from a snapshot: the sockets died with the old VM; forget them."
	| all |
	socket isNil ifFalse: [socket forget].
	all := lock critical: [connections copy].
	all do: [:each | each abandon].
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate]
!
writePortTo: aPath
	| tmp |
	tmp := aPath, '.tmp'.
	File writeText: port printString, (String with: Character lf) to: tmp.
	File rename: tmp to: aPath
! !

!RfbServer methodsFor: 'accessing'!
host: aString
	host := aString
!
port
	^port
!
host
	^host
!
source
	^source
!
source: anRfbFrameSource
	source := anRfbFrameSource
!
connections
	^lock critical: [connections copy]
!
isRunning
	^socket notNil and: [socket isOpen]
!
desktopName
	^desktopName ifNil: ['Samaltak']
!
desktopName: aString
	desktopName := aString
!
maxClients
	^maxClients ifNil: [4]
!
maxClients: anInteger
	maxClients := anInteger
!
maxRate
	"Updates a second to a client, at most."
	^maxRate ifNil: [60]
!
maxRate: anInteger
	maxRate := anInteger
!
isFull
	"More connections than maxClients (the newest is refused)."
	^self connections size > self maxClients
!
disconnectOthers: aConnection
	"ClientInit with shared = 0: aConnection (authenticated) wants the screen to itself."
	self connections do: [:each | each == aConnection ifFalse: [each close]]
! !

!RfbServer methodsFor: 'authentication'!
token: aString
	"VeNCrypt-Plain's password: the session token (nil: no VeNCrypt)."
	token := aString isNil ifFalse: [self class normalized: aString]
!
password: aString
	"VNC authentication's password (nil: no VNC authentication); only its first 8 characters count."
	password := aString
!
allowNone: aBoolean
	allowNone := aBoolean
!
backoffMs: anInteger
	"The first wait after a failed authentication (1000), doubling with each failure."
	backoffMs := anInteger
!
isLoopbackOnly
	^host = '127.0.0.1' or: [host = 'localhost']
!
offersNone
	^allowNone == true and: [self isLoopbackOnly]
!
securityTypes
	"RFB 3.7/3.8's list, the strongest first; never None unless offersNone."
	| types |
	types := OrderedCollection new.
	token isNil ifFalse: [types add: 19].
	password isNil ifFalse: [types add: 2].
	self offersNone ifTrue: [types add: 1].
	^types asArray
!
securityTypeV3
	"RFB 3.3: the server picks: VNC authentication if I have a password, else None if offered, else nil (refused)."
	password isNil ifFalse: [^2].
	self offersNone ifTrue: [^1].
	^nil
!
authenticate: aBlock
	"Run aBlock (it answers whether the client proved who it is) after waiting out the backoff of earlier failures, one at a time, and update the backoff. Answer aBlock's verdict."
	^authLock critical: [| wait ok |
		wait := blockedUntil - Time millisecondClockValue.
		wait > 0 ifTrue: [(Delay forMilliseconds: wait) wait].
		ok := [aBlock value] on: Error do: [:e | e return: false].
		ok == true
			ifTrue: [failures := 0. blockedUntil := 0]
			ifFalse: [
				failures := failures + 1.
				blockedUntil := Time millisecondClockValue + ((backoffMs ifNil: [1000]) * (1 bitShift: (failures - 1 min: 5)))].
		ok == true]
!
checkVncResponse: aResponse challenge: aChallenge
	"Whether aResponse is aChallenge encrypted with my password (DES, VNC's bit-reversed key), compared in constant time."
	| expected |
	password isNil ifTrue: [^false].
	expected := (Smalltalk at: #Des) vncResponseTo: aChallenge password: password.
	^self class constantTime: expected equals: aResponse
!
checkToken: aString
	"Whether aString is my token (blanks and dashes aside), compared in constant time."
	token isNil ifTrue: [^false].
	^self class constantTime: token asByteArray equals: (self class normalized: aString) asByteArray
! !

!RfbServer class methodsFor: 'authentication'!
normalized: aString
	^aString asString reject: [:c | c isSeparator or: [c = $-]]
!
constantTime: expected equals: given
	"Whether given (bytes) equals expected; the work depends only on expected's size."
	| diff |
	diff := expected size bitXor: given size.
	1 to: expected size do: [:i | | c |
		c := given isEmpty ifTrue: [0] ifFalse: [given at: i - 1 \\ given size + 1].
		diff := diff bitOr: ((expected at: i) bitXor: c)].
	^diff = 0
!
newPassword
	"8 characters from SecureRandom, letters and digits that read unambiguously."
	| alphabet bytes |
	alphabet := 'abcdefghijkmnpqrstuvwxyzACDEFGHJKLMNPQRTUVWXY34679'.
	bytes := (Smalltalk at: #SecureRandom) default nextBytes: 8.
	^String new: 8 streamContents: [:s | bytes do: [:b | s nextPut: (alphabet at: b \\ alphabet size + 1)]]
! !

!RfbServer class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self.
	Smalltalk addToShutDownList: self
! !

!RfbServer class methodsFor: 'system startup'!
startUp: resuming
	resuming ifTrue: [
		Current isNil ifFalse: [Current abandon].
		Current := nil].
	(Current isNil and: [Smalltalk vm arguments includes: '--display']) ifTrue: [self startFromCommandLine]
!
shutDown: quitting
	quitting ifTrue: [self stop]
!
startFromCommandLine
	| server file h p |
	server := [
		h := self configuredHost.
		p := self configuredPort.
		server := self new.
		server token: self configuredToken.
		(Smalltalk vm arguments includes: '--display-vnc-auth') ifTrue: [server password: self displayPassword].
		server allowNone: (Smalltalk vm arguments includes: '--display-allow-none').
		(Smalltalk argumentAfter: '--display-rate') ifNotNil: [:r | server maxRate: (Integer readFrom: r ifFail: [60])].
		server startOn: p host: h source: self defaultSource] on: Error do: [:e |
			Smalltalk vm stderrWrite: 'display: ', e messageText, (String with: Character lf).
			e return: nil].
	server isNil ifTrue: [^self].
	Current := server.
	file := Smalltalk argumentAfter: '--display-port-file'.
	file isNil ifFalse: [server writePortTo: file].
	Smalltalk vm stdoutWrite: 'display: listening on ', h, ':', server port printString, ' (RFB)', (String with: Character lf).
	(Smalltalk vm arguments includes: '--display-vnc-auth') ifTrue: [self announcePasswordIfMade: server vncPassword]
!
defaultSource
	"On UEFI the frame tap's screen (the firmware screen's shadow and damage); hosted, for now, the World's through screenshots: the compositor's tap reads back its window's surface, which does not hold the composed frame."
	^(Machine hasFirmware and: [Smalltalk includesKey: #FrameTap]) ifTrue: [RfbTapSource new] ifFalse: [RfbWorldSource new]
!
displayPassword
	"The session's display password (SessionToken's), else --display-password-file's, else a new one."
	(Smalltalk at: #SessionToken ifAbsent: [nil]) ifNotNil: [:c | ^c displayPassword].
	^self configuredPassword ifNil: [MadePassword := self newPassword]
!
announcePasswordIfMade: aString
	(Smalltalk at: #SessionToken ifAbsent: [nil]) ifNotNil: [:c | ^c announceDisplayPassword].
	aString = MadePassword ifTrue: [self announcePassword: aString]
!
configuredHost
	^(Smalltalk argumentAfter: '--display-host') ifNil: ['127.0.0.1']
!
configuredPort
	| value |
	value := Smalltalk argumentAfter: '--display-port'.
	(value isNil or: [value isEmpty]) ifTrue: [^self defaultPort].
	^Integer readFrom: value ifFail: [self defaultPort]
!
defaultPort
	^5900
!
configuredToken
	"The session's token (SessionToken), else the control service's: the running one, else the one its options give."
	(Smalltalk at: #SessionToken ifAbsent: [nil]) ifNotNil: [:c | ^c current value].
	ControlServer current isNil ifFalse: [^ControlServer current token].
	^[ControlServer configuredToken] on: Error do: [:e | e return: nil]
!
configuredPassword
	"VNC authentication's password from --display-password-file (its first line, blanks aside), else nil."
	| file |
	file := Smalltalk argumentAfter: '--display-password-file'.
	file isNil ifTrue: [^nil].
	^((File readText: file) lines detect: [:l | l trimBoth notEmpty] ifNone: ['']) trimBoth
!
announcePassword: aString
	| text |
	text := 'display: password ', aString, ' (VNC authentication; made at start, shown once)'.
	Smalltalk vm stdoutWrite: text, (String with: Character lf).
	Machine hasFirmware ifTrue: [[(Smalltalk at: #FirmwareDiagnostics) new echoOnScreen: text] on: Error do: [:e | e return: nil]]
!
priority
	^45
! !

!RfbServer methodsFor: 'private'!
vncPassword
	^password
! !

!RfbServer class methodsFor: 'accessing'!
current
	^Current
!
startOn: aPort source: aSource
	"A server on 127.0.0.1 (aPort 0: a free one), replacing a running one; configure auth before clients come."
	self stop.
	Current := self new.
	Current startOn: aPort host: '127.0.0.1' source: aSource.
	^Current
!
stop
	Current isNil ifFalse: [Current stop].
	Current := nil
! !
