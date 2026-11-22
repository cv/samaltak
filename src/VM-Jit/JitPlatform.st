VMModule subclass: #JitPlatform
	instanceVariableNames: 'posix'
	classVariableNames: ''
	package: 'VM-Jit'!

JitPlatform comment: 'What the code cache needs from the operating system: an executable mapping, write access to it, instruction cache maintenance; and what the optimizing tier''s background compilation needs (OptRuntime, docs/jit.md Background compilation): one helper thread, a mutex and a condition it waits on. DarwinJitPlatform (MAP_JIT, per-thread write protection) and LinuxJitPlatform (a plain read-write-execute mapping) implement it under the same C names; the build links the one of its OS (targetOS). UefiJitPlatform''s helper is an application processor (UefiMp), its mutex a spin lock; without one compilation stays on the VM''s thread.'!

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
!
mapForPerf: path
	"Map the file at path executable and keep it mapped, so that perf record notes it (the jitdump's marker; JitRuntime>>openPerfMap); nothing where there is no perf."
	self subclassResponsibility
! !

!JitPlatform methodsFor: 'helper thread'!
jitThreadsAvailable
	"Whether a helper thread can run beside the VM's thread: the OS has threads and the VM may run on more than one CPU."
	self subclassResponsibility
!
jitStartThread: fn
	"Start a detached thread running fn (a void *(*)(void *), its argument NULL) and make the worker's mutex and condition; answer whether it started."
	self subclassResponsibility
!
jitWorkerLock
	self subclassResponsibility
!
jitWorkerUnlock
	self subclassResponsibility
!
jitWorkerWait
	"With the worker's mutex held: wait for jitWorkerWake (or a spurious wakeup)."
	self subclassResponsibility
!
jitWorkerWake
	"With the worker's mutex held: wake whoever waits."
	self subclassResponsibility
! !

JitPlatform subclass: #DarwinJitPlatform
	instanceVariableNames: 'darwin posixThreads workerMutex workerCond'
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJitPlatform comment: 'The code cache on macOS (Apple Silicon): one MAP_JIT mapping; a thread either writes it or executes it (pthread_jit_write_protect_np); sys_icache_invalidate after writing. Simulated, write protection is unsupported, so no machine code runs.'!

!DarwinJitPlatform class methodsFor: 'declaring'!
declarations
	^#((darwin DarwinJit) (posixThreads PosixThreads) (workerMutex 'pthread_mutex_t[1]') (workerCond 'pthread_cond_t[1]'))
!
targetOS
	^#darwin
! !

!DarwinJitPlatform methodsFor: 'region'!
canRunCode
	<export>
	^darwin pthreadJitWriteProtectSupported ~= 0
!
map: near size: size
	<export>
	posix munmap: near length: size.
	^posix mmap: near length: size protection: ((posix PROT_READ bitOr: posix PROT_WRITE) bitOr: posix PROT_EXEC) flags: ((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: darwin MAP_JIT) file: -1 offset: 0
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
!
mapForPerf: path
	<export>
	<var: #path type: 'const char *'>
! !

!DarwinJitPlatform methodsFor: 'helper thread'!
jitThreadsAvailable
	<export>
	^self canRunCode
!
jitStartThread: fn
	<export>
	<var: #fn type: 'void *(*)(void *)'>
	| t |
	posixThreads mutexInit: workerMutex attributes: self null.
	posixThreads condInit: workerCond attributes: self null.
	t := self local: 'pthread_t'.
	(posix pthreadCreate: t attributes: self null start: fn argument: self null) ~= 0 ifTrue: [^false].
	posix pthreadDetach: t value.
	^true
!
jitWorkerLock
	<export>
	posixThreads mutexLock: workerMutex
!
jitWorkerUnlock
	<export>
	posixThreads mutexUnlock: workerMutex
!
jitWorkerWait
	<export>
	posixThreads condWait: workerCond mutex: workerMutex
!
jitWorkerWake
	<export>
	posixThreads condSignal: workerCond
! !

JitPlatform subclass: #LinuxJitPlatform
	instanceVariableNames: 'linux posixThreads workerMutex workerCond'
	classVariableNames: ''
	package: 'VM-Jit'!

LinuxJitPlatform comment: 'The code cache on Linux (arm64): one private read-write-execute mapping, written and executed by any thread at any time; __builtin___clear_cache after writing. Not simulated (its code would run).'!

!LinuxJitPlatform class methodsFor: 'declaring'!
declarations
	^#((linux LinuxJit) (posixThreads PosixThreads) (workerMutex 'pthread_mutex_t[1]') (workerCond 'pthread_cond_t[1]'))
!
targetOS
	^#linux
!
isSimulated
	^false
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
!
mapForPerf: path
	<export>
	<var: #path type: 'const char *'>
	| fd |
	fd := linux open: path flags: linux O_RDONLY.
	fd < 0 ifTrue: [^self].
	posix mmap: self null length: 4096 protection: (posix PROT_READ bitOr: posix PROT_EXEC) flags: posix MAP_PRIVATE file: fd offset: 0.
	linux close: fd
! !

!LinuxJitPlatform methodsFor: 'helper thread'!
jitThreadsAvailable
	"Not when the VM is pinned to one CPU (taskset): the helper would only take turns with it."
	<export>
	| set got n |
	set := self local: 'uint64_t[16]'.
	got := linux syscall: linux SYS_sched_getaffinity pid: 0 size: 128 mask: set.
	got <= 0 ifTrue: [^true].
	n := 0.
	0 to: (got quo: 8) - 1 do: [:i | n := n + (linux popcount: (set at: i))].
	^n > 1
!
jitStartThread: fn
	<export>
	<var: #fn type: 'void *(*)(void *)'>
	| t |
	posixThreads mutexInit: workerMutex attributes: self null.
	posixThreads condInit: workerCond attributes: self null.
	t := self local: 'pthread_t'.
	(posix pthreadCreate: t attributes: self null start: fn argument: self null) ~= 0 ifTrue: [^false].
	posix pthreadDetach: t value.
	^true
!
jitWorkerLock
	<export>
	posixThreads mutexLock: workerMutex
!
jitWorkerUnlock
	<export>
	posixThreads mutexUnlock: workerMutex
!
jitWorkerWait
	<export>
	posixThreads condWait: workerCond mutex: workerMutex
!
jitWorkerWake
	<export>
	posixThreads condSignal: workerCond
! !

CLibrary subclass: #LinuxJit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

LinuxJit comment: 'The instruction cache maintenance of the code cache on Linux: the compiler''s builtin (dc cvau / ic ivau on arm64); open and close for the jitdump''s marker mapping. Not simulated.'!

!LinuxJit class methodsFor: 'declaring'!
headers
	^#('<fcntl.h>' '<unistd.h>' '<sys/syscall.h>')
!
targetOS
	^#linux
! !

!LinuxJit methodsFor: 'functions'!
clearCache: begin to: end
	<c: 'void __builtin___clear_cache(void *begin, void *end)'>
	^self error: 'not simulated'
!
open: path flags: flags
	<c: 'int open(const char *path, int flags)'>
	^self error: 'not simulated'
!
close: fd
	<c: 'int close(int fd)'>
	^self error: 'not simulated'
!
O_RDONLY
	<cMacro: 'int O_RDONLY'>
	^0
!
syscall: number pid: pid size: n mask: set
	"sched_getaffinity without _GNU_SOURCE (the system call: it answers the bytes of the mask it wrote)"
	<c: 'long syscall(long number, long pid, long n, uint64_t *set)'>
	^self error: 'not simulated'
!
SYS_sched_getaffinity
	<cMacro: 'long SYS_sched_getaffinity'>
	^204
!
popcount: x
	<c: 'int __builtin_popcountll(unsigned long long x)'>
	^self error: 'not simulated'
! !
