VMModule subclass: #JitPlatform
	instanceVariableNames: 'posix'
	classVariableNames: ''
	package: 'VM-Jit'!

JitPlatform comment: 'What the code cache needs from the operating system: an executable mapping, write access to it, instruction cache maintenance. DarwinJitPlatform (MAP_JIT, per-thread write protection) and LinuxJitPlatform (a plain read-write-execute mapping) implement it under the same C names; the build links the one of its OS (targetOS).'!

!JitPlatform class methodsFor: 'declaring'!
declarations
	^#((posix Posix))
!
isAbstractModule
	^self == JitPlatform
!
isInterface
	^self == JitPlatform
! !

!JitPlatform methodsFor: 'region'!
canRunCode
	"Whether machine code runs (not in the simulator)."
	self subclassResponsibility
!
map: near size: size
	"An executable mapping of size bytes in place of [near, near + size) (unmapped first), or MAP_FAILED."
	self subclassResponsibility
!
beginWriting
	"Make the mapping writable for this thread."
	self subclassResponsibility
!
endWriting
	"Make the mapping executable again for this thread."
	self subclassResponsibility
!
invalidate: start size: size
	"Code changed in [start, start + size): make the instruction cache current."
	self subclassResponsibility
! !

!JitPlatform methodsFor: 'worker'!
jitWorkerStart: fn
	<var: #fn type: 'void *(*)(void *)'>
	<returns: 'bool'>
	self subclassResponsibility
!
jitWorkerJoin
	self subclassResponsibility
!
jitWorkerLock
	self subclassResponsibility
!
jitWorkerUnlock
	self subclassResponsibility
!
jitWorkerWait
	self subclassResponsibility
!
jitWorkerWake
	self subclassResponsibility
! !

PosixThreads subclass: #JitWorkerLib
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

!JitWorkerLib methodsFor: 'worker'!
join: t result: out
	<c: 'int pthread_join(pthread_t t, void **out)'>
	^self error: 'not simulated'
!
mutexDestroy: m
	<c: 'int pthread_mutex_destroy(pthread_mutex_t *m)'>
	^self error: 'not simulated'
!
condDestroy: c
	<c: 'int pthread_cond_destroy(pthread_cond_t *c)'>
	^self error: 'not simulated'
!
onlineCPUs
	<cMacro: 'int _SC_NPROCESSORS_ONLN'>
	^0
!
sysconf: n
	<c: 'long sysconf(int n)'>
	^self error: 'not simulated'
! !

JitPlatform subclass: #DarwinJitPlatform
	instanceVariableNames: 'darwin cache jitMapping jitMappingAttempted workerLib workerThread workerMutex workerCond'
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJitPlatform comment: 'One MAP_JIT mapping on macOS (Apple Silicon), with a fixed FFI prefix outside the ordinary code cache. A thread either writes or executes it (pthread_jit_write_protect_np); sys_icache_invalidate after writing. Simulated, write protection is unsupported, so no machine code runs.'!

!DarwinJitPlatform class methodsFor: 'declaring'!
declarations
	^#((darwin DarwinJit) (cache CodeCache) (jitMapping 'void *') (jitMappingAttempted bool) (workerLib JitWorkerLib) (workerThread 'pthread_t[1]') (workerMutex 'pthread_mutex_t[1]') (workerCond 'pthread_cond_t[1]'))
!
targetOS
	^#darwin
! !

!DarwinJitPlatform methodsFor: 'worker'!
jitWorkerStart: fn
	<export>
	<var: #fn type: 'void *(*)(void *)'>
	self workerCpusAvailable ifFalse: [^false].
	(workerLib mutexInit: workerMutex attributes: self null) ~= 0 ifTrue: [^false].
	(workerLib condInit: workerCond attributes: self null) ~= 0 ifTrue: [
		workerLib mutexDestroy: workerMutex.
		^false].
	(posix pthreadCreate: workerThread attributes: self null start: fn argument: self null) = 0 ifTrue: [^true].
	workerLib condDestroy: workerCond.
	workerLib mutexDestroy: workerMutex.
	^false
!
jitWorkerJoin
	<export>
	workerLib join: (workerThread at: 0) result: self null.
	workerLib condDestroy: workerCond.
	workerLib mutexDestroy: workerMutex
!
jitWorkerLock
	<export>
	workerLib mutexLock: workerMutex
!
jitWorkerUnlock
	<export>
	workerLib mutexUnlock: workerMutex
!
jitWorkerWait
	<export>
	workerLib condWait: workerCond mutex: workerMutex
!
jitWorkerWake
	<export>
	workerLib condSignal: workerCond
!
workerCpusAvailable
	^self canRunCode and: [(workerLib sysconf: workerLib onlineCPUs) > 1]
! !

!DarwinJitPlatform methodsFor: 'region'!
canRunCode
	<export>
	^darwin pthreadJitWriteProtectSupported ~= 0
!
map: near size: size
	<export>
	| p |
	size > cache maxCacheBytes ifTrue: [^posix MAP_FAILED].
	p := self ensureJitMappingNear: near.
	p = posix MAP_FAILED ifTrue: [^p].
	^self cCoerce: (self cCoerce: p to: 'uint8_t *') + cache ffiArenaBytes to: 'void *'
!
ffiArenaBase
	<function>
	<returns: 'void *'>
	^self ensureJitMappingNear: cache mappingHint
!
ensureJitMappingNear: near
	"Either user may be first. Never remap over published code or reopen a hole after mmap failure."
	<function>
	<var: #near type: 'void *'>
	<returns: 'void *'>
	| total |
	jitMappingAttempted ifTrue: [^jitMapping].
	jitMappingAttempted := true.
	jitMapping := posix MAP_FAILED.
	total := cache maxCacheBytes + cache ffiArenaBytes.
	(posix munmap: near length: total) = 0 ifTrue: [
		jitMapping := posix mmap: near length: total
			protection: ((posix PROT_READ bitOr: posix PROT_WRITE) bitOr: posix PROT_EXEC)
			flags: ((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: darwin MAP_JIT) file: -1 offset: 0].
	^jitMapping
!
beginWriting
	<export>
	darwin pthreadJitWriteProtect: 0
!
endWriting
	<export>
	darwin pthreadJitWriteProtect: 1
!
invalidate: start size: size
	<export>
	darwin sysIcacheInvalidate: start size: size
! !

JitPlatform subclass: #LinuxJitPlatform
	instanceVariableNames: 'linux workerLib workerThread workerMutex workerCond'
	classVariableNames: ''
	package: 'VM-Jit'!

LinuxJitPlatform comment: 'The code cache on Linux (arm64): one private read-write-execute mapping, written and executed by any thread at any time; __builtin___clear_cache after writing. Not simulated (its code would run).'!

!LinuxJitPlatform class methodsFor: 'declaring'!
declarations
	^#((linux LinuxJit) (workerLib JitWorkerLib) (workerThread 'pthread_t[1]') (workerMutex 'pthread_mutex_t[1]') (workerCond 'pthread_cond_t[1]'))
!
targetOS
	^#linux
!
isSimulated
	^false
! !

!LinuxJitPlatform methodsFor: 'worker'!
jitWorkerStart: fn
	<export>
	<var: #fn type: 'void *(*)(void *)'>
	self workerCpusAvailable ifFalse: [^false].
	(workerLib mutexInit: workerMutex attributes: self null) ~= 0 ifTrue: [^false].
	(workerLib condInit: workerCond attributes: self null) ~= 0 ifTrue: [
		workerLib mutexDestroy: workerMutex.
		^false].
	(posix pthreadCreate: workerThread attributes: self null start: fn argument: self null) = 0 ifTrue: [^true].
	workerLib condDestroy: workerCond.
	workerLib mutexDestroy: workerMutex.
	^false
!
jitWorkerJoin
	<export>
	workerLib join: (workerThread at: 0) result: self null.
	workerLib condDestroy: workerCond.
	workerLib mutexDestroy: workerMutex
!
jitWorkerLock
	<export>
	workerLib mutexLock: workerMutex
!
jitWorkerUnlock
	<export>
	workerLib mutexUnlock: workerMutex
!
jitWorkerWait
	<export>
	workerLib condWait: workerCond mutex: workerMutex
!
jitWorkerWake
	<export>
	workerLib condSignal: workerCond
!
workerCpusAvailable
	"Respect process affinity (including taskset); an unknown mask size is a safe synchronous fallback."
	| set |
	set := self local: 'cpu_set_t'.
	^(linux schedGetAffinity: 0 size: (self sizeof: 'cpu_set_t') mask: set) = 0 and: [(linux cpuCount: set) > 1]
! !

!LinuxJitPlatform methodsFor: 'region'!
canRunCode
	<export>
	^true
!
map: near size: size
	<export>
	posix munmap: near length: size.
	^posix mmap: near length: size protection: ((posix PROT_READ bitOr: posix PROT_WRITE) bitOr: posix PROT_EXEC) flags: (posix MAP_PRIVATE bitOr: posix MAP_ANON) file: -1 offset: 0
!
beginWriting
	<export>
!
endWriting
	<export>
!
invalidate: start size: size
	<export>
	linux clearCache: start to: (self cCoerce: start to: 'char *') + size
! !

CLibrary subclass: #LinuxJit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

LinuxJit comment: 'The instruction cache maintenance of the code cache on Linux: the compiler''s builtin (dc cvau / ic ivau on arm64). Not simulated.'!

!LinuxJit class methodsFor: 'declaring'!
headers
	^#('<sched.h>')
!
typedefs
	^#((cpu_set_t opaque))
!
targetOS
	^#linux
! !

!LinuxJit methodsFor: 'functions'!
clearCache: begin to: end
	<c: 'void __builtin___clear_cache(void *begin, void *end)'>
	^self error: 'not simulated'
!
schedGetAffinity: pid size: n mask: set
	<c: 'int sched_getaffinity(int pid, size_t n, cpu_set_t *set)'>
	^self error: 'not simulated'
!
cpuCount: set
	<c: 'int CPU_COUNT(const cpu_set_t *set)'>
	^self error: 'not simulated'
! !
