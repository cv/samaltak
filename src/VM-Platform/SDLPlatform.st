PlatformInterface subclass: #SDLPlatform
	instanceVariableNames: 'common events windows gpu files sockets vsync sdl posixIO posixThreads initDone wakeEvent inWait wPipe wMu wCv wState wFds wNfds wStarted wStop posixProcesses quitSignal quitSender sdlTerm sdlInt'
	classVariableNames: 'POLL_FDS'
	package: 'VM-Platform'!

SDLPlatform comment: 'The platform of the GUI VM: SDL3 windows and input, sockets and pseudo-terminals polled while the VM runs and while it waits.

While Smalltalk runs, platform_interface_poll pumps SDL at most once per ms, polls the armed sockets and signals the semaphores. platform_interface_wait blocks in SDL_WaitEventTimeout; a watcher thread poll()s the armed sockets meanwhile and wakes SDL with the wake event, as wake does for any thread (the display link''s). Without video it poll()s the sockets and the wake pipe.'!

!SDLPlatform class methodsFor: 'declaring'!
declarations
	^#((common PlatformCommon) (events PlatformEvents) (windows PlatformWindows) (gpu PlatformGPU) (files PlatformFiles)
		(sockets PlatformSockets) (vsync PlatformVsync) (sdl SDL) (posixIO PosixIO) (posixThreads PosixThreads)
		(initDone bool) (wakeEvent atomic_int) (inWait atomic_bool) (wPipe 'int32_t[2]' #(-1 -1))
		(wMu 'pthread_mutex_t[1]') (wCv 'pthread_cond_t[1]') (wState int32_t) (wFds 'struct pollfd[POLL_FDS]') (wNfds int32_t)
		(wStarted bool) (wStop atomic_bool)
		(posixProcesses PosixProcesses) (quitSignal atomic_int) (quitSender atomic_int) (sdlTerm sig_t) (sdlInt sig_t))
!
initialize
	"the wake pipe and up to 128 sockets"
	POLL_FDS := 129
! !

!SDLPlatform methodsFor: 'platform'!
init
	"Idempotent."
	<export>
	initDone ifTrue: [^self].
	initDone := true.
	"broken sockets and FIFOs report EPIPE instead"
	posixIO signal: posixIO SIGPIPE handler: posixIO SIG_IGN.
	common nowMs.
	posixThreads mutexInit: wMu attributes: self null.
	posixThreads condInit: wCv attributes: self null.
	gpu init.
	(posixIO pipe: wPipe) = 0 ifTrue: [
		posixIO fcntl: (wPipe at: 0) command: posixIO F_SETFL value: posixIO O_NONBLOCK.
		posixIO fcntl: (wPipe at: 1) command: posixIO F_SETFL value: posixIO O_NONBLOCK]
!
poll
	<export>
	"Pumping Cocoa costs tens of µs; at most once per ms is plenty for input."
	(windows videoInited and: [sdl getTicksNS - events lastPumpNs >= 1000000]) ifTrue: [events pump].
	sockets anyArmed ifTrue: [sockets poll: 0].
	events signalReady
!
wait: timeoutUs
	<export>
	| ms socks p n watching |
	self init.
	events pump.
	(windows videoInited and: [(self atomicLoad: #wakeEvent) = 0]) ifTrue: [
		self atomicStore: #wakeEvent value: (sdl registerEvents: 1) asInt32].
	self atomicStore: #inWait value: true.
	ms := (events pending or: [vsync pending])
		ifTrue: [0]
		ifFalse: [timeoutUs < 0 ifTrue: [-1] ifFalse: [((timeoutUs + 999) quo: 1000) asInt32]].
	socks := sockets anyArmed.
	windows videoInited
		ifTrue: [
			watching := socks and: [self watcherStart].
			ms ~= 0 ifTrue: [sdl waitEvent: self null timeout: ms].
			watching ifTrue: [self watcherStop].
			events pump]
		ifFalse: [
			p := self local: 'struct pollfd[POLL_FDS]'.
			p fd: (wPipe at: 0).
			p events: posixIO POLLIN.
			n := socks ifTrue: [1 + (sockets pollFds: p + 1 max: POLL_FDS - 1)] ifFalse: [1].
			ms ~= 0 ifTrue: [posixIO poll: p count: n asUInt32 timeout: ms]].
	self atomicStore: #inWait value: false.
	self drainPipe.
	socks ifTrue: [sockets poll: 0].
	events signalReady
!
shutdown
	<export>
	gpu shutdown.
	windows shutdown.
	windows videoInited ifTrue: [sdl quit]
! !

!SDLPlatform methodsFor: 'quit signals'!
catchQuitSignals
	"After SDL_Init. SDL catches SIGTERM and SIGINT (when they have the default action) and makes them a quit event, which the World answers with Smalltalk quit: 0, so a VM killed so used to exit with 0, as if it had finished: a test run cut short by someone's pkill looked like one that had ended normally, but without its summary. Wrap SDL's handlers: the quit then says which signal asked for it and from which process, and the VM exits with 128 + the signal, as the signal's default action would have (quitStatus:)."
	<export>
	sdlTerm := self wrapQuitSignal: posixProcesses SIGTERM.
	sdlInt := self wrapQuitSignal: posixProcesses SIGINT
!
wrapQuitSignal: sig
	"Put onQuitSignal:info:context: in place of SDL's handler of sig; answer SDL's handler, or NULL (nothing changed) if sig has none."
	<function>
	<var: #sig type: 'int'>
	<returns: 'sig_t'>
	| old act |
	old := self local: 'struct sigaction'.
	(posixProcesses sigaction: sig action: self null old: old) ~= 0 ifTrue: [^self null].
	(old sa_flags bitAnd: posixProcesses SA_SIGINFO) ~= 0 ifTrue: [^self null].
	(old sa_handler = posixProcesses SIG_DFL or: [old sa_handler = posixIO SIG_IGN]) ifTrue: [^self null].
	act := self local: 'struct sigaction'.
	act sa_sigaction: (self functionPointer: #onQuitSignal:info:context:).
	act sa_flags: (old sa_flags bitOr: posixProcesses SA_SIGINFO).
	(posixProcesses sigaction: sig action: act old: self null) ~= 0 ifTrue: [^self null].
	^old sa_handler
!
onQuitSignal: sig info: info context: context
	"The handler of SIGTERM and SIGINT (async-signal-safe): note the signal and its sender, then run SDL's handler, which makes the quit event."
	<function>
	<var: #sig type: 'int'>
	<var: #info type: 'siginfo_t *'>
	<var: #context type: 'void *'>
	| next |
	self atomicStore: #quitSender value: info si_pid.
	self atomicStore: #quitSignal value: sig.
	next := sig = posixProcesses SIGTERM ifTrue: [sdlTerm] ifFalse: [sdlInt].
	next isNull ifFalse: [next call: sig]
!
quitStatus: code
	"128 + the signal if SIGTERM or SIGINT asked for the quit (onQuitSignal:info:context:), said on stderr with the sender's command line (from /proc: ? where there is none, or once the sender has gone); else code."
	<export>
	<var: #code type: 'int'>
	<returns: 'int'>
	<var: #sig type: 'int'>
	<var: #pid type: 'int'>
	| sig pid path buf fd n |
	sig := self atomicLoad: #quitSignal.
	sig = 0 ifTrue: [^code].
	pid := self atomicLoad: #quitSender.
	path := self local: 'char[40]'.
	buf := self local: 'char[256]'.
	libc snprintf: path size: 40 format: '/proc/%d/cmdline' with: pid.
	n := 0.
	fd := posixIO open: path flags: posixIO O_RDONLY mode: 0.
	fd >= 0 ifTrue: [
		n := posixIO read: fd into: buf count: 255.
		posixIO close: fd].
	n < 0 ifTrue: [n := 0].
	[n > 0 and: [(buf at: n - 1) = 0]] whileTrue: [n := n - 1].
	0 to: n - 1 do: [:i | (buf at: i) = 0 ifTrue: [buf at: i put: 32]].
	buf at: n put: 0.
	libc fprintf: libc stderr format: 'samaltak: quit on %s from pid %d (%s): exit status %d
' with: (sig = posixProcesses SIGTERM ifTrue: ['SIGTERM'] ifFalse: ['SIGINT']) with: pid with: (n > 0 ifTrue: [buf] ifFalse: ['?']) with: 128 + sig.
	^128 + sig
! !

!SDLPlatform methodsFor: 'waking'!
wake
	"Any thread: end a platform_interface_wait in progress."
	<export>
	| t e |
	(self atomicLoad: #inWait) ifFalse: [^self].
	t := self atomicLoad: #wakeEvent.
	t ~= 0 ifTrue: [
		e := self local: 'SDL_Event'.
		e type: t asUInt32.
		sdl pushEvent: e].
	posixIO write: (wPipe at: 1) bytes: 'w' count: 1
!
drainPipe
	<function>
	| buf |
	buf := self local: 'char[64]'.
	[(posixIO read: (wPipe at: 0) into: buf count: 64) > 0] whileTrue
! !

!SDLPlatform methodsFor: 'watcher'!
watchMain: arg
	"The watcher thread: while the VM thread sleeps in SDL_WaitEventTimeout, poll() the armed sockets and wake SDL by pushing the wake event."
	<function>
	| r woken e |
	[posixThreads mutexLock: wMu.
	 [wState ~= 1] whileTrue: [posixThreads condWait: wCv mutex: wMu].
	 wState := 2.
	 posixThreads mutexUnlock: wMu.
	 "wStop is set before the stop byte is written, so a drained stop byte is always followed by seeing wStop"
	 woken := false.
	 [woken not and: [(self atomicLoad: #wStop) not]] whileTrue: [
		r := posixIO poll: wFds count: wNfds asUInt32 timeout: -1.
		1 to: wNfds - 1 do: [:i | (r > 0 and: [(wFds at: i) revents ~= 0]) ifTrue: [woken := true]].
		woken
			ifTrue: [
				e := self local: 'SDL_Event'.
				e type: (self atomicLoad: #wakeEvent) asUInt32.
				sdl pushEvent: e]
			ifFalse: [self drainPipe "a stop request or a stray wake byte"]].
	 posixThreads mutexLock: wMu.
	 wState := 0.
	 posixThreads condBroadcast: wCv.
	 posixThreads mutexUnlock: wMu] repeat
!
watcherStart
	"Hand the armed sockets to the watcher thread (started on first use)."
	<function>
	| t |
	wStarted ifFalse: [
		(wPipe at: 0) < 0 ifTrue: [^false].
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #watchMain:) argument: self null) ~= 0 ifTrue: [^false].
		wStarted := true].
	wFds fd: (wPipe at: 0).
	wFds events: posixIO POLLIN.
	wFds revents: 0.
	wNfds := 1 + (sockets pollFds: wFds + 1 max: POLL_FDS - 1).
	self atomicStore: #wStop value: false.
	posixThreads mutexLock: wMu.
	wState := 1.
	posixThreads condBroadcast: wCv.
	posixThreads mutexUnlock: wMu.
	^true
!
watcherStop
	<function>
	self atomicStore: #wStop value: true.
	posixIO write: (wPipe at: 1) bytes: 'x' count: 1.
	posixThreads mutexLock: wMu.
	[wState ~= 0] whileTrue: [posixThreads condWait: wCv mutex: wMu].
	posixThreads mutexUnlock: wMu
! !
