CLibrary subclass: #Posix
	instanceVariableNames: 'kqueues'
	classVariableNames: ''
	package: 'VM-Core'!

Posix comment: 'The POSIX and BSD calls of the VM core: memory mappings, clocks, threads, kqueue timers. Simulated: mmap reserves simulated memory, a thread is a Process of the host, a kqueue keeps timers and kevent waits for them with Delays.'!

!Posix class methodsFor: 'declaring'!
headers
	^#('<sys/mman.h>' '<sys/event.h>' '<sys/time.h>' '<time.h>' '<pthread.h>' '<unistd.h>' '<stdlib.h>' '<limits.h>')
!
typedefs
	^#((pthread_t uintptr_t) (pthread_attr_t opaque) (clockid_t int32_t) (useconds_t uint32_t))
! !

!Posix methodsFor: 'memory mappings'!
mmap: addr length: n protection: prot flags: flags file: fd offset: offset
	<c: 'void *mmap(void *addr, size_t n, int prot, int flags, int fd, off_t offset)'>
	(flags bitAnd: self MAP_FIXED) ~= 0 ifTrue: [
		self memory zero: (self memory addressOf: addr) size: n.
		^addr].
	^self memory pointerTo: CVoidType new at: (self memory allocate: n)
!
PROT_READ
	<cMacro: 'int PROT_READ'>
	^1
!
PROT_WRITE
	<cMacro: 'int PROT_WRITE'>
	^2
!
MAP_PRIVATE
	<cMacro: 'int MAP_PRIVATE'>
	^2
!
MAP_ANON
	<cMacro: 'int MAP_ANON'>
	^16r1000
!
MAP_FIXED
	<cMacro: 'int MAP_FIXED'>
	^16r10
!
MAP_FAILED
	<cMacro: 'void *MAP_FAILED'>
	^CPointer memory: self memory address: 16rFFFFFFFFFFFFFFFF type: CVoidType new
! !

!Posix methodsFor: 'time'!
clockGettime: clock into: ts
	<c: 'int clock_gettime(clockid_t clock, struct timespec *ts)'>
	| us |
	us := sim microsecondClock.
	ts tv_sec: us // 1000000.
	ts tv_nsec: us \\ 1000000 * 1000.
	^0
!
CLOCK_MONOTONIC
	<cMacro: 'int CLOCK_MONOTONIC'>
	^6
!
CLOCK_THREAD_CPUTIME_ID
	<cMacro: 'int CLOCK_THREAD_CPUTIME_ID'>
	^16
!
gettimeofday: tv zone: tz
	<c: 'int gettimeofday(struct timeval *tv, void *tz)'>
	| us |
	us := Time utcMicroseconds.
	tv tv_sec: us // 1000000.
	tv tv_usec: us \\ 1000000.
	^0
!
usleep: us
	<c: 'int usleep(useconds_t us)'>
	(Delay forMilliseconds: us + 999 // 1000) wait.
	^0
! !

!Posix methodsFor: 'threads'!
pthreadCreate: thread attributes: attr start: fn argument: arg
	<c: 'int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*fn)(void *), void *arg)'>
	| p |
	p := [fn call: arg] forkAt: Processor activePriority + 1.
	thread value: (self memory registerObject: p).
	^0
!
pthreadDetach: thread
	<c: 'int pthread_detach(pthread_t thread)'>
	^0
! !

!Posix methodsFor: 'kqueue'!
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
	0 to: nchanges - 1 do: [:i | q apply: (changes at: i) posix: self].
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
! !

!Posix methodsFor: 'files'!
realpath: path into: resolved
	<c: 'char *realpath(const char *path, char *resolved)'>
	| p |
	p := self memory stringAt: path.
	(p beginsWith: '/') ifFalse: [p := File join: File primCwd with: p].
	^self memory pointerTo: (CTypeRegistry default at: 'char') at: (self memory newCString: p)
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
apply: aKEvent posix: aPosix
	(aKEvent flags bitAnd: aPosix EV_DELETE) ~= 0 ifTrue: [
		timers removeKey: aKEvent ident ifAbsent: [].
		^changed signal].
	(aKEvent flags bitAnd: aPosix EV_ADD) ~= 0 ifTrue: [
		timers at: aKEvent ident put: (Array
			with: simulation microsecondClock + aKEvent data
			with: ((aKEvent flags bitAnd: aPosix EV_ONESHOT) ~= 0 ifTrue: [nil] ifFalse: [aKEvent data])).
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

ExternStruct subclass: #Timespec
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!Timespec class methodsFor: 'declaring'!
cName
	^'struct timespec'
!
fields
	^#((tv_sec int64_t) (tv_nsec int64_t))
! !

ExternStruct subclass: #Timeval
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!Timeval class methodsFor: 'declaring'!
cName
	^'struct timeval'
!
fields
	^#((tv_sec int64_t) (tv_usec int32_t))
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

CLibrary subclass: #LibM
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

LibM comment: 'The C math library functions of the float primitives.'!

!LibM class methodsFor: 'declaring'!
headers
	^#('<math.h>')
! !

!LibM methodsFor: 'functions'!
sqrt: x
	<c: 'double sqrt(double x)'>
	^x sqrt
!
sin: x
	<c: 'double sin(double x)'>
	^x sin
!
cos: x
	<c: 'double cos(double x)'>
	^x cos
!
atan: x
	<c: 'double atan(double x)'>
	^x arcTan
!
log: x
	<c: 'double log(double x)'>
	^x ln
!
exp: x
	<c: 'double exp(double x)'>
	^x exp
!
trunc: x
	<c: 'double trunc(double x)'>
	^x truncated asFloat
!
fabs: x
	<c: 'double fabs(double x)'>
	^x abs
!
modf: x integralPart: ip
	<c: 'double modf(double x, double *ip)'>
	ip value: x truncated asFloat.
	^x - x truncated
!
frexp: x exponent: e
	<c: 'double frexp(double x, int *e)'>
	| ex |
	x = 0.0 ifTrue: [e value: 0. ^x].
	ex := x exponent + 1.
	e value: ex.
	^x timesTwoPower: ex negated
!
ilogb: x
	<c: 'int ilogb(double x)'>
	^x exponent
!
ldexp: x exponent: e
	<c: 'double ldexp(double x, int e)'>
	^x timesTwoPower: e
!
strtod: s end: endp
	<c: 'double strtod(const char *s, char **endp)'>
	"Simulated: decimal floating point (sign, digits, point, exponent), converted exactly and rounded once."
	| str in negative mantissa scale exp expNegative consumed v |
	str := self memory stringAt: s.
	in := ReadStream on: str.
	[in atEnd not and: [in peek isSeparator]] whileTrue: [in next].
	negative := false.
	(in atEnd not and: [in peek = $- or: [in peek = $+]]) ifTrue: [negative := in next = $-].
	(str copyFrom: in position + 1 to: (in position + 3 min: str size)) asLowercase = 'inf' ifTrue: [
		in skip: 3.
		v := negative ifTrue: [Float infinity negated] ifFalse: [Float infinity]]
		ifFalse: [
			mantissa := 0.
			scale := 0.
			[in atEnd not and: [in peek isDigit]] whileTrue: [mantissa := mantissa * 10 + in next digitValue].
			(in atEnd not and: [in peek = $.]) ifTrue: [
				in next.
				[in atEnd not and: [in peek isDigit]] whileTrue: [mantissa := mantissa * 10 + in next digitValue. scale := scale - 1]].
			exp := 0.
			(in atEnd not and: [in peek = $e or: [in peek = $E]]) ifTrue: [
				in next.
				expNegative := false.
				(in atEnd not and: [in peek = $- or: [in peek = $+]]) ifTrue: [expNegative := in next = $-].
				[in atEnd not and: [in peek isDigit]] whileTrue: [exp := exp * 10 + in next digitValue].
				expNegative ifTrue: [exp := exp negated]].
			v := (mantissa * (10 raisedTo: scale + exp)) asFloat.
			negative ifTrue: [v := v negated]].
	consumed := in position.
	endp notNull ifTrue: [endp value: s + consumed].
	^v
! !
