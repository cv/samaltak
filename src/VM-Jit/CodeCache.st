VMModule subclass: #CodeCache
	instanceVariableNames: 'posix jit cacheStart cacheBase cacheTop cacheLimit cacheSpace'
	classVariableNames: 'CACHE_SPACE'
	package: 'VM-Jit'!

CodeCache comment: 'I am the region generated code lives in: one executable mapping (JitPlatform: MAP_JIT on macOS), bump allocated, flushed as a whole. On macOS a thread either writes the region or executes it: beginWriting before writing code, endWritingFrom:size: after it (write protection back on, instruction cache invalidated).

	cache openWithSize: 64 * 1024 * 1024.
	entry := cache allocate: size.
	cache beginWriting.
	... write the code at entry ...
	cache endWritingFrom: entry size: size.
	(self cCoerce: entry to: ''int64_t (*)(int64_t)'') call: 42

Simulated, the region is simulated memory and its code does not run (canRunCode).'!

!CodeCache class methodsFor: 'declaring'!
declarations
	^#((posix Posix) (jit JitPlatform) (cacheStart uint64_t) (cacheBase uint64_t) (cacheTop uint64_t) (cacheLimit uint64_t) (cacheSpace 'uint8_t[CACHE_SPACE]'))
!
initialize
	"Room for the largest cache (128 MB) and a page."
	CACHE_SPACE := (128 << 20) + 16384
! !

!CodeCache methodsFor: 'region'!
canRunCode
	"Whether machine code runs: not in the simulator."
	^jit canRunCode
!
openWithSize: size
	"Map the region; answer whether it worked. It takes the place of cacheSpace (zero-fill, in the VM's own image): near the VM's data, so that adrp from the code reaches it (tiering counters, type feedback, eden's top, call caches)."
	<export>
	<var: #size type: 'uint64_t'>
	| p near |
	near := ((self cCoerce: cacheSpace to: 'uint64_t') + 16383) bitClear: 16383.
	p := jit map: (self cCoerce: near to: 'void *') size: size.
	p = posix MAP_FAILED ifTrue: [^false].
	cacheStart := self cCoerce: p to: 'uint64_t'.
	cacheBase := cacheStart.
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
	<export>
	| a |
	a := cacheTop.
	cacheLimit - a < size ifTrue: [^0].
	cacheTop := (a + size + 15) bitClear: 15.
	^a
!
flush
	"Forget all code allocated since keep (none of it may be running)."
	<export>
	cacheTop := cacheBase
!
keep
	"What is allocated so far survives flushes."
	cacheBase := cacheTop
!
resetTo: address
	"Forget the code allocated from address on (the last allocations)."
	cacheTop := address
! !

!CodeCache methodsFor: 'writing'!
beginWriting
	"Make the region writable (and not executable) for this thread."
	jit beginWriting
!
endWritingFrom: start size: size
	"Make the region executable again, with the instruction cache current for [start, start + size)."
	jit endWriting.
	jit invalidate: (self cCoerce: start to: 'void *') size: size
!
endWriting
	"Make the region executable again; only data changed (or invalidate: what did)."
	jit endWriting
!
invalidate: start size: size
	"Code changed in [start, start + size)."
	jit invalidate: (self cCoerce: start to: 'void *') size: size
! !
