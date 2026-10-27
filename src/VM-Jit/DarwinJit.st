CLibrary subclass: #DarwinJit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJit comment: 'The macOS calls of the code cache: MAP_JIT mappings (taking the place of an unmapped range), the per-thread write protection of JIT memory, instruction cache invalidation. Simulated, write protection is unsupported (machine code does not run in the simulator); protection and invalidation do nothing.'!

!DarwinJit class methodsFor: 'declaring'!
headers
	^#('<pthread.h>' '<sys/mman.h>' '<libkern/OSCacheControl.h>')
! !

!DarwinJit methodsFor: 'functions'!
pthreadJitWriteProtectSupported
	<c: 'int pthread_jit_write_protect_supported_np(void)'>
	^0
!
pthreadJitWriteProtect: enabled
	<c: 'void pthread_jit_write_protect_np(int enabled)'>
!
sysIcacheInvalidate: start size: n
	<c: 'void sys_icache_invalidate(void *start, size_t n)'>
!
PROT_EXEC
	<cMacro: 'int PROT_EXEC'>
	^4
!
MAP_JIT
	<cMacro: 'int MAP_JIT'>
	^16r800
!
munmap: addr length: n
	<c: 'int munmap(void *addr, size_t n)'>
	^0
! !
