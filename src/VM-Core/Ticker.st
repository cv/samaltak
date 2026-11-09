VMCoreModule subclass: #Ticker
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Ticker comment: 'The Scheduler''s timers: a thread of mine calls tickFired: (scheduler) whenever one fires. Timers are named by small idents (the Scheduler''s TICK_ constants, < 4); arming one again replaces it, a negative interval disarms it. KqueueTicker (macOS) and TimerfdTicker (Linux) implement me under the same C names; the build links the one of its OS (targetOS).'!

!Ticker class methodsFor: 'declaring'!
isAbstractModule
	^self == Ticker
!
isInterface
	^self == Ticker
! !

!Ticker methodsFor: 'timers'!
start
	"At startup (VM thread)."
	self subclassResponsibility
!
arm: ident microseconds: us periodic: periodic
	"Fire ident after us microseconds (every us if periodic); us < 0 disarms. VM thread."
	self subclassResponsibility
!
threadCycles
	"The calling thread's CPU cycles so far; negative if there is no counter. Only the recording clock (Scheduler) asks."
	self subclassResponsibility
! !

Ticker subclass: #KqueueTicker
	instanceVariableNames: 'kqueue kq counts'
	classVariableNames: ''
	package: 'VM-Core'!

KqueueTicker comment: 'The ticker on macOS: one kqueue of EVFILT_TIMER events, one thread waiting in kevent. Simulated (Kqueue''s timers wait with Delays).'!

!KqueueTicker class methodsFor: 'declaring'!
declarations
	^#((kqueue Kqueue) (kq int32_t -1) (counts ThreadCounts))
!
targetOS
	^#darwin
!
cPreamble
	"thread_selfcounts has no header, and another macOS may not have it (ThreadCounts): weak, so the VM starts anyway and the call answers -1."
	^'extern int thread_selfcounts(int type, void *buf, unsigned long nbytes) __attribute__((weak_import));
static inline int thread_selfcounts_checked(int type, void *buf, unsigned long nbytes) { return thread_selfcounts ? thread_selfcounts(type, buf, nbytes) : -1; }'
! !

!KqueueTicker methodsFor: 'timers'!
start
	<export>
	| t |
	kq := kqueue kqueue.
	kq < 0 ifTrue: [self fatal: 'cannot create the ticker''s kqueue'].
	t := self local: 'pthread_t'.
	(posix pthreadCreate: t attributes: self null start: (self functionPointer: #run:) argument: self null) ~= 0 ifTrue: [
		self fatal: 'cannot start the ticker thread'].
	posix pthreadDetach: t value
!
arm: ident microseconds: us periodic: periodic
	"us < 0 disarms (an already fired one-shot is gone: ENOENT, ignored). Critical: in the background role macOS would coalesce a 1 ms timer to about 60 ms."
	<export>
	| ch res zero |
	ch := self local: 'KEvent'.
	res := self local: 'KEvent'.
	zero := self local: 'Timespec'.
	ch ident: ident asUInt64.
	ch filter: kqueue EVFILT_TIMER.
	us < 0
		ifTrue: [ch flags: (kqueue EV_DELETE bitOr: kqueue EV_RECEIPT)]
		ifFalse: [
			ch flags: ((kqueue EV_ADD bitOr: kqueue EV_RECEIPT) bitOr: (periodic ifTrue: [0] ifFalse: [kqueue EV_ONESHOT])).
			ch fflags: (kqueue NOTE_USECONDS bitOr: kqueue NOTE_CRITICAL).
			ch data: us].
	kqueue kevent: kq changes: ch count: 1 events: res count: 1 timeout: zero
!
threadCycles
	<export>
	| counters |
	counters := self local: 'uint64_t[2]'.
	(counts threadSelfcounts: 1 into: counters size: 16) ~= 0 ifTrue: [^-1].
	^(counters at: 1) asInt64
!
run: arg
	"The ticker thread."
	<function>
	| ev |
	ev := self local: 'KEvent'.
	[(kqueue kevent: kq changes: self null count: 0 events: ev count: 1 timeout: self null) > 0 ifTrue: [
		scheduler tickFired: ev ident asInt32]] repeat
! !

Ticker subclass: #TimerfdTicker
	instanceVariableNames: 'timerfd fds'
	classVariableNames: ''
	package: 'VM-Core'!

TimerfdTicker comment: 'The ticker on Linux: a timerfd (CLOCK_MONOTONIC) per timer, opened when it is first armed, each with a thread blocked in read until it expires. Not simulated (KqueueTicker is).'!

!TimerfdTicker class methodsFor: 'declaring'!
declarations
	^#((timerfd Timerfd) (fds 'int32_t[4]' #(-1 -1 -1 -1)))
!
targetOS
	^#linux
!
isSimulated
	^false
! !

!TimerfdTicker methodsFor: 'timers'!
start
	"Each timer gets its timerfd and thread when it is first armed."
	<export>
!
arm: ident microseconds: us periodic: periodic
	<export>
	| spec value n |
	(ident < 1 or: [ident > 3]) ifTrue: [self fatal: 'no ticker timer %d' with: ident].
	(fds at: ident) < 0 ifTrue: [
		us < 0 ifTrue: [^self].
		self open: ident].
	spec := self local: 'ITimerspec'.
	us >= 0 ifTrue: [
		n := us < 1 ifTrue: [1] ifFalse: [us].
		value := spec fieldAddress: #it_value.
		value tv_sec: (n quo: 1000000).
		value tv_nsec: (n rem: 1000000) * 1000.
		periodic ifTrue: [(spec fieldAddress: #it_interval) copyStructFrom: value]].
	timerfd settime: (fds at: ident) flags: 0 new: spec old: self null
!
threadCycles
	<export>
	^-1
!
open: ident
	"The timerfd of ident and its thread."
	| fd t |
	fd := timerfd create: posix CLOCK_MONOTONIC flags: timerfd TFD_CLOEXEC.
	fd < 0 ifTrue: [self fatal: 'cannot create the ticker''s timerfd'].
	fds at: ident put: fd.
	t := self local: 'pthread_t'.
	(posix pthreadCreate: t attributes: self null start: (self functionPointer: #run:) argument: (self cCoerce: ident asInt64 to: 'void *')) ~= 0 ifTrue: [
		self fatal: 'cannot start a ticker thread'].
	posix pthreadDetach: t value
!
run: arg
	"The thread of one timer (arg: its ident)."
	<function>
	| ident expirations |
	ident := (self cCoerce: arg to: 'int64_t') asInt32.
	expirations := self local: 'uint64_t'.
	[(fds at: ident) >= 0] whileTrue: [
		(timerfd read: (fds at: ident) into: expirations count: 8) = 8 ifTrue: [scheduler tickFired: ident]].
	^self null
! !

CLibrary subclass: #ThreadCounts
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

ThreadCounts comment: 'The calling thread''s retired instructions and cycles (element 0 and 1 of the answer): thread_selfcounts, a private XNU syscall that the C library exports without a header. Only the recording clock calls it (Scheduler, while workClockOn), never a normal run; if it fails (another macOS) the clock falls back to CPU time and says so. Simulated: the simulator''s clock at that rate.'!

!ThreadCounts class methodsFor: 'declaring'!
targetOS
	^#darwin
! !

!ThreadCounts methodsFor: 'counting'!
threadSelfcounts: type into: buf size: nbytes
	<c: 'int thread_selfcounts_checked(int type, uint64_t *buf, size_t nbytes)'>
	buf at: 0 put: 0.
	buf at: 1 put: sim microsecondClock * 3300.
	^0
! !

CLibrary subclass: #Kqueue
	instanceVariableNames: 'kqueues'
	classVariableNames: ''
	package: 'VM-Core'!

Kqueue comment: 'The BSD kqueue timers of KqueueTicker. Simulated: a kqueue keeps timers and kevent waits for them with Delays.'!

!Kqueue class methodsFor: 'declaring'!
headers
	^#('<sys/event.h>')
!
targetOS
	^#darwin
! !

!Kqueue methodsFor: 'kqueue'!
kqueue
	<c: 'int kqueue(void)'>
	kqueues isNil ifTrue: [kqueues := OrderedCollection new].
	kqueues add: (SimulatedKQueue simulation: sim).
	^kqueues size + 2
!
kevent: kq changes: changes count: nchanges events: events count: nevents timeout: timeout
	<c: 'int kevent(int kq, const struct kevent *changes, int nchanges, struct kevent *events, int nevents, const struct timespec *timeout)'>
	| q |
	q := kqueues at: kq - 2.
	0 to: nchanges - 1 do: [:i | q apply: (changes at: i) kqueue: self].
	(timeout notNull and: [nchanges > 0]) ifTrue: [^0].
	nevents = 0 ifTrue: [^0].
	^q waitInto: events timeout: timeout
!
EVFILT_TIMER
	<cMacro: 'int16_t EVFILT_TIMER'>
	^-7
!
EV_ADD
	<cMacro: 'uint16_t EV_ADD'>
	^1
!
EV_DELETE
	<cMacro: 'uint16_t EV_DELETE'>
	^2
!
EV_ONESHOT
	<cMacro: 'uint16_t EV_ONESHOT'>
	^16r10
!
EV_RECEIPT
	<cMacro: 'uint16_t EV_RECEIPT'>
	^16r40
!
NOTE_USECONDS
	<cMacro: 'uint32_t NOTE_USECONDS'>
	^2
!
NOTE_CRITICAL
	<cMacro: 'uint32_t NOTE_CRITICAL'>
	^16r20
! !

Object subclass: #SimulatedKQueue
	instanceVariableNames: 'timers changed simulation'
	classVariableNames: ''
	package: 'VM-Core'!

SimulatedKQueue comment: 'A kqueue of the simulated VM: its timers (ident -> {deadline µs. interval µs or nil}).'!

!SimulatedKQueue class methodsFor: 'instance creation'!
simulation: aVMSimulation
	^self new setSimulation: aVMSimulation
! !

!SimulatedKQueue methodsFor: 'initialization'!
setSimulation: aVMSimulation
	simulation := aVMSimulation.
	timers := Dictionary new.
	changed := Semaphore new
! !

!SimulatedKQueue methodsFor: 'events'!
apply: aKEvent kqueue: aKqueue
	(aKEvent flags bitAnd: aKqueue EV_DELETE) ~= 0 ifTrue: [
		timers removeKey: aKEvent ident ifAbsent: [].
		^changed signal].
	(aKEvent flags bitAnd: aKqueue EV_ADD) ~= 0 ifTrue: [
		timers at: aKEvent ident put: (Array
			with: simulation microsecondClock + aKEvent data
			with: ((aKEvent flags bitAnd: aKqueue EV_ONESHOT) ~= 0 ifTrue: [nil] ifFalse: [aKEvent data])).
		changed signal]
!
waitInto: events timeout: aTimespec
	"Wait for the earliest timer (forever if timeout is NULL); fill events at: 0."
	| next now |
	[timers isEmpty
		ifTrue: [
			aTimespec notNull ifTrue: [^0].
			changed wait]
		ifFalse: [
			next := timers associations inject: nil into: [:a :b | (a isNil or: [(b value at: 1) < (a value at: 1)]) ifTrue: [b] ifFalse: [a]].
			now := simulation microsecondClock.
			(next value at: 1) <= now
				ifTrue: [
					(events at: 0) ident: next key.
					(next value at: 2) isNil
						ifTrue: [timers removeKey: next key]
						ifFalse: [next value at: 1 put: now + (next value at: 2)].
					^1]
				ifFalse: [
					aTimespec notNull ifTrue: [^0].
					changed waitTimeoutMSecs: ((next value at: 1) - now + 999 // 1000 max: 1)]]] repeat
! !

ExternStruct subclass: #KEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!KEvent class methodsFor: 'declaring'!
cName
	^'struct kevent'
!
fields
	^#((ident uintptr_t) (filter int16_t) (flags uint16_t) (fflags uint32_t) (data intptr_t) (udata 'void *'))
! !

CLibrary subclass: #Timerfd
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Timerfd comment: 'The Linux timerfd calls of TimerfdTicker. Not simulated.'!

!Timerfd class methodsFor: 'declaring'!
headers
	^#('<sys/timerfd.h>' '<unistd.h>')
!
targetOS
	^#linux
! !

!Timerfd methodsFor: 'timerfd'!
create: clock flags: flags
	<c: 'int timerfd_create(int clock, int flags)'>
	^self error: 'not simulated'
!
settime: fd flags: flags new: newValue old: oldValue
	<c: 'int timerfd_settime(int fd, int flags, const struct itimerspec *new_value, struct itimerspec *old_value)'>
	^self error: 'not simulated'
!
read: fd into: buf count: n
	<c: 'ssize_t read(int fd, void *buf, size_t n)'>
	^self error: 'not simulated'
!
TFD_CLOEXEC
	<cMacro: 'int TFD_CLOEXEC'>
	^16r80000
! !

ExternStruct subclass: #ITimerspec
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!ITimerspec class methodsFor: 'declaring'!
cName
	^'struct itimerspec'
!
fields
	^#((it_interval 'struct timespec') (it_value 'struct timespec'))
! !
