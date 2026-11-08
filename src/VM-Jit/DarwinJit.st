CLibrary subclass: #DarwinJit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJit comment: 'The macOS calls of the code cache (DarwinJitPlatform): MAP_JIT mappings, the per-thread write protection of JIT memory, instruction cache invalidation. Simulated, write protection is unsupported (machine code does not run in the simulator); protection and invalidation do nothing.'!

!DarwinJit class methodsFor: 'declaring'!
headers
	^#('<pthread.h>' '<sys/mman.h>' '<libkern/OSCacheControl.h>')
!
targetOS
	^#darwin
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
MAP_JIT
	<cMacro: 'int MAP_JIT'>
	^16r800
! !
