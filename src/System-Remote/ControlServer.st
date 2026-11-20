Object subclass: #ControlServer
	instanceVariableNames: 'socket port process connections lock ready readyIndex ownReady ownIndex host wakeAt'
	classVariableNames: 'Current HoldClock'
	package: 'System-Remote'!

ControlServer comment: 'I am the remote-control service: a TCP server on 127.0.0.1 speaking JSON lines. Each request is one JSON object on one line, {"id": 1, "cmd": "eval", "source": "3 + 4"}; each response is one line, {"id": 1, "ok": true, "printString": "7", ...} or {"id": 1, "ok": false, "error": "...", "code": 2}. Commands are RemoteControl''s.

I start when the image is started with --control (from the startup list): port from --control-port N, else $SAMALTAK_CONTROL_PORT, else 7341 (0 picks a free one); address from --control-host, else 127.0.0.1; --control-port-file path receives the port number. The listening socket and every client socket (ControlConnection) signal one Semaphore when they become readable. Without a UI my own Process, ''remote control'' (priority 50), waits on it; with one, remote control is an input device: hostOn: makes the sockets signal the input dispatcher''s Semaphore and the dispatcher calls service when it wakes, so no Process of mine exists. Each request runs in a transient Process (''remote request'') while it is handled. My Processes do not count as busy for wait idle. If no UI set a main action, the image keeps running until a quit command.'!

!ControlServer methodsFor: 'starting and stopping'!
startOn: aPort
	lock := Semaphore forMutualExclusion.
	connections := OrderedCollection new.
	ready := ownReady := Semaphore new.
	readyIndex := ownIndex := Smalltalk vm registerExternalSemaphore: ready.
	socket := RemoteSocket listenOn: aPort host: self class configuredHost backlog: 16 readSemaphore: ready index: readyIndex.
	port := socket localPort.
	self startProcess
!
startProcess
	process := [self serveLoop] forkAt: self class priority named: 'remote control'
!
serveLoop
	"My own Process (when not hosted): each wakeup accepts what is pending and lets every connection read what arrived."
	[socket notNil and: [socket isOpen] and: [host isNil]] whileTrue: [
		self service.
		ready wait]
!
service
	"Accept pending clients and let each connection read and dispatch what arrived. Never waits. Not while the image runs its startup list (requests would see it half restored): I look again soon."
	(socket isNil or: [socket isOpen not]) ifTrue: [^self].
	Smalltalk isStartingUp ifTrue: [^self wakeIn: 20].
	HoldClock == true ifTrue: [
		"--work-clock: the startup list is done; from here on the clock moves with the commands"
		HoldClock := false.
		Smalltalk vm workClockRunning: false].
	self acceptPending.
	self connections do: [:each | each pump].
	self connections do: [:each | each stepJob]
!
wakeIn: milliseconds
	"An input job wants to be stepped again in milliseconds: have the timer signal my host's (or my) Semaphore then."
	| at |
	at := Time millisecondClockValue + milliseconds.
	(wakeAt notNil and: [wakeAt > Time millisecondClockValue and: [wakeAt <= at]]) ifTrue: [^self].
	wakeAt := at.
	(Delay forMilliseconds: (milliseconds max: 1)) signal: ready
!
hostOn: aSemaphore index: anIndex by: anObject
	"Let anObject's Process serve me: my sockets signal aSemaphore (registered at anIndex) when readable and anObject sends me service after each wakeup. My own Process ends."
	host := anObject.
	self useSemaphore: aSemaphore index: anIndex.
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate].
	process := nil.
	aSemaphore signal
!
unhost
	"Serve myself again (the host stops)."
	host isNil ifTrue: [^self].
	host := nil.
	self useSemaphore: ownReady index: ownIndex.
	(socket notNil and: [socket isOpen]) ifTrue: [self startProcess]
!
host
	^host
!
useSemaphore: aSemaphore index: anIndex
	"A wakeup due on the previous Semaphore would be lost: the next wakeIn: schedules one on aSemaphore."
	ready := aSemaphore.
	readyIndex := anIndex.
	wakeAt := nil.
	socket isNil ifFalse: [socket readSemaphore: aSemaphore index: anIndex].
	self connections do: [:each | each socket readSemaphore: aSemaphore index: anIndex]
!
acceptPending
	| client |
	[(client := socket acceptNow) notNil] whileTrue: [
		client := RemoteSocket onHandle: client readSemaphore: ready index: readyIndex.
		lock critical: [connections add: (ControlConnection server: self socket: client)]]
!
poke
	"Wake my Process or my host's (a connection finished a request: it may have more lines)."
	ready signal
!
removeConnection: aConnection
	lock critical: [connections remove: aConnection ifAbsent: []]
!
stop
	| all |
	socket isNil ifFalse: [socket close].
	all := lock critical: [connections copy].
	all do: [:each | each close].
	RemoteSocket unregister: ownReady at: ownIndex.
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate]
!
abandon
	"In an image resumed from a snapshot taken while I ran: my sockets died with the old VM (their handles may name new sockets now, so they are forgotten, not closed); end my Process."
	| all |
	socket isNil ifFalse: [socket forget].
	all := lock critical: [connections copy].
	all do: [:each | each abandon].
	RemoteSocket unregister: ownReady at: ownIndex.
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate]
!
writePortTo: aPath
	"Write my port number to aPath (via a temporary file, so readers never see a partial number)."
	| tmp |
	tmp := aPath, '.tmp'.
	File writeText: port printString, (String with: Character lf) to: tmp.
	File rename: tmp to: aPath
! !

!ControlServer methodsFor: 'accessing'!
port
	^port
!
connections
	^lock critical: [connections copy]
!
isRunning
	^socket notNil and: [socket isOpen]
! !

!ControlServer class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self.
	Smalltalk addToShutDownList: self
! !

!ControlServer class methodsFor: 'system startup'!
startUp: resuming
	"A saved server's sockets died with the old VM: start afresh. After a snapshot the image continues with the server it had (same port, same clients), so Save image does not cut off the client that asked for it."
	resuming ifTrue: [
		Current isNil ifFalse: [Current abandon].
		Current := nil].
	(Current isNil and: [Smalltalk vm arguments includes: '--control']) ifTrue: [self startFromCommandLine]
!
shutDown: quitting
	quitting ifTrue: [self stop]
!
startFromCommandLine
	| server file |
	server := [self startOn: self configuredPort] on: Error do: [:e |
		Smalltalk vm stderrWrite: 'control: ', e messageText, (String with: Character lf).
		e return: nil].
	server isNil ifTrue: [^self].
	(Smalltalk vm arguments includes: '--work-clock') ifTrue: [
		Smalltalk vm workClockStart: 0 semaphore: 0.
		HoldClock := true].
	file := Smalltalk argumentAfter: '--control-port-file'.
	file isNil ifFalse: [server writePortTo: file].
	Smalltalk vm stdoutWrite: 'control: listening on ', self configuredHost, ':', server port printString, (String with: Character lf).
	self keepImageRunning
!
configuredHost
	"--control-host address, else 127.0.0.1. 0.0.0.0 lets everyone on the network evaluate Smalltalk: for a VM with no loopback (UEFI) reached through a forwarded port."
	^(Smalltalk argumentAfter: '--control-host') ifNil: ['127.0.0.1']
!
configuredPort
	| value |
	value := Smalltalk argumentAfter: '--control-port'.
	value isNil ifTrue: [value := Smalltalk vm getenv: 'SAMALTAK_CONTROL_PORT'].
	(value isNil or: [value isEmpty]) ifTrue: [^self defaultPort].
	^Integer readFrom: value ifFail: [self defaultPort]
!
defaultPort
	^7341
!
priority
	^Processor userInterruptPriority
!
keepImageRunning
	"Without a main action (no UI) a start would quit right away; serve until a quit command instead."
	(SystemDictionary classPool at: #MainAction ifAbsent: [nil]) isNil ifTrue: [
		Smalltalk mainAction: [self serveUntilQuit]]
!
serveUntilQuit
	Current isNil ifTrue: [^Smalltalk quit: 0].
	Semaphore new wait
! !

!ControlServer class methodsFor: 'accessing'!
current
	^Current
!
startOn: aPort
	"Start the server on aPort (0: a free port), replacing a running one; answer it."
	self stop.
	Current := self new startOn: aPort.
	^Current
!
stop
	Current isNil ifFalse: [Current stop].
	Current := nil
! !
