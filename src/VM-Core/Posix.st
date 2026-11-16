CLibrary subclass: #Posix
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Posix comment: 'The POSIX calls of the VM core: memory mappings, clocks, threads. Simulated: mmap reserves simulated memory, a thread is a Process of the host.'!

!Posix class methodsFor: 'declaring'!
headers
	^#('<sys/mman.h>' '<sys/time.h>' '<time.h>' '<pthread.h>' '<unistd.h>' '<stdlib.h>' '<limits.h>')
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
PROT_EXEC
	<cMacro: 'int PROT_EXEC'>
	^4
!
munmap: addr length: n
	<c: 'int munmap(void *addr, size_t n)'>
	^0
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
MAP_NORESERVE
	<cMacro: 'int MAP_NORESERVE'>
	^16r40
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

!Posix methodsFor: 'processes'!
getpid
	<c: 'pid_t getpid(void)'>
	^1
! !

!Posix methodsFor: 'files'!
realpath: path into: resolved
	<c: 'char *realpath(const char *path, char *resolved)'>
	| p |
	p := self memory stringAt: path.
	(p beginsWith: '/') ifFalse: [p := File join: File primCwd with: p].
	^self memory pointerTo: (CTypeRegistry default at: 'char') at: (self memory newCString: p)
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
			[in atEnd not and: [in peek between: $0 and: $9]] whileTrue: [mantissa := mantissa * 10 + in next digitValue].
			(in atEnd not and: [in peek = $.]) ifTrue: [
				in next.
				[in atEnd not and: [in peek between: $0 and: $9]] whileTrue: [mantissa := mantissa * 10 + in next digitValue. scale := scale - 1]].
			exp := 0.
			(in atEnd not and: [in peek = $e or: [in peek = $E]]) ifTrue: [
				in next.
				expNegative := false.
				(in atEnd not and: [in peek = $- or: [in peek = $+]]) ifTrue: [expNegative := in next = $-].
				[in atEnd not and: [in peek between: $0 and: $9]] whileTrue: [exp := exp * 10 + in next digitValue].
				expNegative ifTrue: [exp := exp negated]].
			v := (mantissa * (10 raisedTo: scale + exp)) asFloat.
			negative ifTrue: [v := v negated]].
	consumed := in position.
	endp notNull ifTrue: [endp value: s + consumed].
	^v
! !
