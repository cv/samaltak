CLibrary subclass: #PosixThreads
	instanceVariableNames: 'mutexes conditions'
	classVariableNames: ''
	package: 'VM-Platform'!

PosixThreads comment: 'Mutexes, condition variables and nanosleep for the platform layer''s helper threads (pthread_create is Posix''s). Simulated with Semaphores, keyed by the address of the mutex or condition.'!

!PosixThreads class methodsFor: 'declaring'!
headers
	^#('<pthread.h>' '<time.h>')
!
typedefs
	^#((pthread_mutex_t opaque) (pthread_mutexattr_t opaque) (pthread_cond_t opaque) (pthread_condattr_t opaque))
! !

!PosixThreads methodsFor: 'simulation'!
mutexAt: m
	mutexes isNil ifTrue: [mutexes := Dictionary new].
	^mutexes at: (self memory addressOf: m) ifAbsentPut: [Semaphore forMutualExclusion]
!
waitersAt: c
	conditions isNil ifTrue: [conditions := Dictionary new].
	^conditions at: (self memory addressOf: c) ifAbsentPut: [OrderedCollection new]
! !

!PosixThreads methodsFor: 'mutexes'!
mutexInit: m attributes: attr
	<c: 'int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *attr)'>
	self mutexAt: m.
	^0
!
mutexLock: m
	<c: 'int pthread_mutex_lock(pthread_mutex_t *m)'>
	(self mutexAt: m) wait.
	^0
!
mutexUnlock: m
	<c: 'int pthread_mutex_unlock(pthread_mutex_t *m)'>
	(self mutexAt: m) signal.
	^0
! !

!PosixThreads methodsFor: 'conditions'!
condInit: c attributes: attr
	<c: 'int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *attr)'>
	self waitersAt: c.
	^0
!
condWait: c mutex: m
	<c: 'int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m)'>
	| s |
	s := Semaphore new.
	(self waitersAt: c) add: s.
	(self mutexAt: m) signal.
	s wait.
	(self mutexAt: m) wait.
	^0
!
condSignal: c
	<c: 'int pthread_cond_signal(pthread_cond_t *c)'>
	| waiters |
	waiters := self waitersAt: c.
	waiters isEmpty ifFalse: [waiters removeFirst signal].
	^0
!
condBroadcast: c
	<c: 'int pthread_cond_broadcast(pthread_cond_t *c)'>
	| waiters |
	waiters := self waitersAt: c.
	[waiters isEmpty] whileFalse: [waiters removeFirst signal].
	^0
! !

!PosixThreads methodsFor: 'time'!
nanosleep: duration remaining: rem
	<c: 'int nanosleep(const struct timespec *duration, struct timespec *rem)'>
	(Delay forMilliseconds: ((duration tv_sec * 1000) + (duration tv_nsec // 1000000) max: 1)) wait.
	^0
! !
