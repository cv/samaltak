VMModule subclass: #CodeCache
	instanceVariableNames: 'posix jit cacheStart cacheTop cacheLimit'
	classVariableNames: ''
	package: 'VM-Jit'!

CodeCache comment: 'I am the region generated code lives in: one MAP_JIT mapping, bump allocated, flushed as a whole. On macOS a thread either writes the region or executes it: beginWriting before writing code, endWritingFrom:size: after it (write protection back on, instruction cache invalidated).

	cache openWithSize: 64 * 1024 * 1024.
	entry := cache allocate: size.
	cache beginWriting.
	... write the code at entry ...
	cache endWritingFrom: entry size: size.
	(self cCoerce: entry to: ''int64_t (*)(int64_t)'') call: 42

Simulated, the region is simulated memory, and calls of a pointer into it run the code in an Arm64Emulator (see DarwinJit).'!

!CodeCache class methodsFor: 'declaring'!
declarations
	^#((posix Posix) (jit DarwinJit) (cacheStart uint64_t) (cacheTop uint64_t) (cacheLimit uint64_t))
! !

!CodeCache methodsFor: 'region'!
openWithSize: size
	"Map the region; answer whether it worked."
	<c: 'bool code_cache_open(uint64_t size)'>
	<export>
	| p |
	p := posix mmap: self null length: size protection: ((posix PROT_READ bitOr: posix PROT_WRITE) bitOr: jit PROT_EXEC) flags: ((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: jit MAP_JIT) file: -1 offset: 0.
	p = posix MAP_FAILED ifTrue: [^false].
	cacheStart := self cCoerce: p to: 'uint64_t'.
	cacheTop := cacheStart.
	cacheLimit := cacheStart + size.
	^true
!
start
	^cacheStart
!
top
	"Where the next allocation starts."
	^cacheTop
!
limit
	^cacheLimit
!
allocate: size
	"Answer the address of size bytes for code (16-byte aligned), 0 if the cache is full."
	<c: 'uint64_t code_cache_allocate(uint64_t size)'>
	<export>
	| a |
	a := cacheTop.
	cacheLimit - a < size ifTrue: [^0].
	cacheTop := (a + size + 15) bitClear: 15.
	^a
!
flush
	"Forget all code (none may be running)."
	<c: 'void code_cache_flush(void)'>
	<export>
	cacheTop := cacheStart
! !

!CodeCache methodsFor: 'writing'!
beginWriting
	"Make the region writable (and not executable) for this thread."
	jit pthreadJitWriteProtect: 0
!
endWritingFrom: start size: size
	"Make the region executable again, with the instruction cache current for [start, start + size)."
	jit pthreadJitWriteProtect: 1.
	jit sysIcacheInvalidate: (self cCoerce: start to: 'void *') size: size
! !
