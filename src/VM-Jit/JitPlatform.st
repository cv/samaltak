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
	instanceVariableNames: 'darwin cache jitMapping jitMappingAttempted'
	classVariableNames: ''
	package: 'VM-Jit'!

DarwinJitPlatform comment: 'One MAP_JIT mapping on macOS (Apple Silicon), with a fixed FFI prefix outside the ordinary code cache. A thread either writes or executes it (pthread_jit_write_protect_np); sys_icache_invalidate after writing. Simulated, write protection is unsupported, so no machine code runs.'!

!DarwinJitPlatform class methodsFor: 'declaring'!
declarations
	^#((darwin DarwinJit) (cache CodeCache) (jitMapping 'void *') (jitMappingAttempted bool))
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
