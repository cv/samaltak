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

JitPlatform subclass: #DarwinJitPlatform
	instanceVariableNames: 'darwin'
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJitPlatform comment: 'The code cache on macOS (Apple Silicon): one MAP_JIT mapping; a thread either writes it or executes it (pthread_jit_write_protect_np); sys_icache_invalidate after writing. Simulated, write protection is unsupported, so no machine code runs.'!

!DarwinJitPlatform class methodsFor: 'declaring'!
declarations
	^#((darwin DarwinJit))
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
! !

JitPlatform subclass: #LinuxJitPlatform
	instanceVariableNames: 'linux'
	classVariableNames: ''
	package: 'VM-Jit'!

LinuxJitPlatform comment: 'The code cache on Linux (arm64): one private read-write-execute mapping, written and executed by any thread at any time; __builtin___clear_cache after writing. Not simulated (its code would run).'!

!LinuxJitPlatform class methodsFor: 'declaring'!
declarations
	^#((linux LinuxJit))
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
! !

CLibrary subclass: #LinuxJit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

LinuxJit comment: 'The instruction cache maintenance of the code cache on Linux: the compiler''s builtin (dc cvau / ic ivau on arm64). Not simulated.'!

!LinuxJit class methodsFor: 'declaring'!
targetOS
	^#linux
! !

!LinuxJit methodsFor: 'functions'!
clearCache: begin to: end
	<c: 'void __builtin___clear_cache(void *begin, void *end)'>
	^self error: 'not simulated'
! !
