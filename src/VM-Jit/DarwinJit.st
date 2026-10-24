CLibrary subclass: #DarwinJit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJit comment: 'The macOS calls of the code cache: MAP_JIT mappings, the per-thread write protection of JIT memory, instruction cache invalidation. Simulated, protection and invalidation do nothing but make sure an Arm64Emulator runs the simulated memory''s machine code.'!

!DarwinJit class methodsFor: 'declaring'!
headers
	^#('<pthread.h>' '<sys/mman.h>' '<libkern/OSCacheControl.h>')
! !

!DarwinJit methodsFor: 'functions'!
pthreadJitWriteProtect: enabled
	<c: 'void pthread_jit_write_protect_np(int enabled)'>
	self installEmulator
!
sysIcacheInvalidate: start size: n
	<c: 'void sys_icache_invalidate(void *start, size_t n)'>
	self installEmulator
!
PROT_EXEC
	<cMacro: 'int PROT_EXEC'>
	^4
!
MAP_JIT
	<cMacro: 'int MAP_JIT'>
	^16r800
! !

!DarwinJit methodsFor: 'simulation'!
installEmulator
	self memory machineCodeRunner isNil ifTrue: [self memory machineCodeRunner: (Arm64Emulator memory: self memory)]
! !
