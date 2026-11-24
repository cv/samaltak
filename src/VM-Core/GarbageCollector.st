VMCoreModule subclass: #GarbageCollector
	instanceVariableNames: 'youngLo youngHi edenLo edenHi edenBox survLo survTop survHi survOtherLo survOtherHi oldLo oldTop oldHi oldAltLo oldAltHi oldBudget maxHeapBytes heapReserve lowSpaceLevel lowSpacePending lowSpaceHash oldReserve gcEpoch statScavenges statFullGcs statScavengeUs statFullUs statAllocated statTenured statSurvived statScavengeMaxUs tenureAge tenureAdaptive ageBytes copiedBytes prevAgeBytes survivalRate gcLog remset remsetCount remsetCap startBits vlo verify toLo toTop toHi weakList weakCount weakCap finalizationPending statWeakCleared ftTop becomeFrom becomeTo updateWeakOwners invalidateWeakOwners'
	classVariableNames: 'MIN_BUDGET TENURE_AGE MAX_TENURE_AGE HUGE_PAGE'
	package: 'VM-Core'!

GarbageCollector comment: 'Generational GC: eden and two survivor spaces scavenged with a remembered set, copying full GC between two old-space reservations. Weak objects (format 4) have their indexable slots cleared when their referents die. Addresses of the spaces are plain integers. A survivor is tenured on the scavenge tenureAge says (adaptTenure, or fixed by --tenure-age); the spaces are backed by huge pages where the system has them (reserveHuge:); SAMALTAK_GC_LOG prints a line per collection.

The heap limit (maxHeapBytes) keeps back a reserve (heapReserve, an eighth of it, at most 128 MB) so that a program that fills the heap gets a catchable error and its handlers and the UI can still run: allocations Smalltalk asks for in old space (large objects: oldAllocTry:limit: with softLimit) fail with PRIM_ERR_NO_MEMORY beyond maxHeapBytes - heapReserve; small objects and Contexts may use the reserve. A full GC that leaves more than that live raises lowSpaceLevel to 1, more than maxHeapBytes - heapReserve / 4 to 2, and sets lowSpacePending: the interpreter''s next safepoint in the process that was running then (lowSpaceHash, its identity hash: the one whose allocation, or whose stack flushed at a switch, ran the GC) signals it there (Interpreter>>interruptSafepoint); a process that preempts it does not get it. The old space''s budget stops at the next level''s limit, so a full GC notices each level; one that leaves no more than softLimit live re-arms them. Only a full GC with more than maxHeapBytes live is fatal.'!

!GarbageCollector class methodsFor: 'declaring'!
cPreamble
	"Posix>>MADV_HUGEPAGE: Linux's transparent huge pages, else 0."
	^'#if defined(__linux__) && !!defined(SAMALTAK_UEFI)
#include <sys/mman.h>
#endif
#if defined(__linux__) && !!defined(SAMALTAK_UEFI) && defined(MADV_HUGEPAGE)
#define SAMALTAK_MADV_HUGEPAGE MADV_HUGEPAGE
#else
#define SAMALTAK_MADV_HUGEPAGE 0
#endif'
!
declarations
	^#((youngLo uint64_t) (youngHi uint64_t) (edenLo uint64_t) (edenHi uint64_t) (edenBox 'uint64_t[2]')
		(survLo uint64_t) (survTop uint64_t) (survHi uint64_t) (survOtherLo uint64_t) (survOtherHi uint64_t)
		(oldLo uint64_t) (oldTop uint64_t) (oldHi uint64_t) (oldAltLo uint64_t) (oldAltHi uint64_t)
		(oldBudget size_t) (maxHeapBytes size_t) (heapReserve size_t) (lowSpaceLevel int32_t) (lowSpacePending bool) (lowSpaceHash uint32_t) (oldReserve size_t) (gcEpoch uint64_t)
		(statScavenges uint64_t) (statFullGcs uint64_t) (statScavengeUs uint64_t) (statFullUs uint64_t) (statAllocated uint64_t) (statTenured uint64_t) (statSurvived uint64_t) (statScavengeMaxUs uint64_t)
		(tenureAge uint32_t) (tenureAdaptive bool) (ageBytes 'uint64_t[4]') (copiedBytes 'uint64_t[5]') (prevAgeBytes 'uint64_t[4]') (survivalRate uint32_t) (gcLog int32_t -1)
		(remset 'oop *') (remsetCount size_t) (remsetCap size_t)
		(startBits 'uint8_t *') (vlo uint64_t) (verify int32_t -1)
		(toLo uint64_t) (toTop uint64_t) (toHi uint64_t)
		(weakList 'oop *') (weakCount size_t) (weakCap size_t) (finalizationPending bool) (statWeakCleared uint64_t)
		(ftTop uint64_t) (becomeFrom oop) (becomeTo oop)
		(updateWeakOwners 'void (*)(bool (*)(oop *))') (invalidateWeakOwners 'void (*)(void)'))
!
initialize
	MIN_BUDGET := 64 << 20.
	HUGE_PAGE := 2 << 20.
	TENURE_AGE := 2.
	MAX_TENURE_AGE := 4
! !

!GarbageCollector methodsFor: 'accessing'!
tenureAge
	"The age at which the next scavenge tenures a survivor: how many scavenges it has survived, counting that one."
	^tenureAge
!
tenureAge: n
	"1 to 4: tenure on the nth scavenge survived; 0: adaptive (adaptTenure)."
	<function>
	tenureAdaptive := n = 0.
	tenureAge := n = 0 ifTrue: [TENURE_AGE] ifFalse: [n asUInt32]
!
statSurvived
	^statSurvived
!
statScavengeMaxUs
	^statScavengeMaxUs
!
youngLo
	^youngLo
!
youngHi
	^youngHi
!
edenLo
	^edenLo
!
edenHi
	^edenHi
!
edenTop
	^edenBox at: 0
!
edenTop: a
	edenBox at: 0 put: a
!
allocLimit
	^edenBox at: 1
!
allocLimit: a
	edenBox at: 1 put: a
!
edenBoxAddress
	"Where eden's top and the allocation limit are (machine code allocates there)."
	^self cCoerce: edenBox to: 'uint64_t'
!
survLo
	^survLo
!
survTop
	^survTop
!
oldLo
	^oldLo
!
oldTop
	^oldTop
!
oldTop: a
	oldTop := a
!
oldBudget
	^oldBudget
!
oldBudget: n
	oldBudget := n
!
maxHeapBytes
	^maxHeapBytes
!
heapReserve
	^heapReserve
!
softLimit
	"Old space that Smalltalk's large allocations may fill: the heap limit less the reserve."
	^maxHeapBytes - heapReserve
!
lowSpaceLimit: level
	"The live bytes beyond which a full GC raises lowSpaceLevel past level."
	<function>
	level = 0 ifTrue: [^maxHeapBytes - heapReserve].
	level = 1 ifTrue: [^maxHeapBytes - (heapReserve quo: 4)].
	^maxHeapBytes
!
lowSpacePending
	^lowSpacePending
!
lowSpacePending: aBoolean
	lowSpacePending := aBoolean
!
lowSpaceHash
	"The identity hash of the process that gets the pending signal."
	^lowSpaceHash
!
lowSpaceLevel
	^lowSpaceLevel
!
gcEpoch
	^gcEpoch
!
gcEpoch: n
	gcEpoch := n
!
statScavenges
	^statScavenges
!
statFullGcs
	^statFullGcs
!
statScavengeUs
	^statScavengeUs
!
statFullUs
	^statFullUs
!
statAllocated
	^statAllocated
!
statAllocated: n
	statAllocated := n
!
statTenured
	^statTenured
!
remsetCount
	^remsetCount
!
finalizationPending
	^finalizationPending
!
finalizationPending: aBoolean
	finalizationPending := aBoolean
!
statWeakCleared
	^statWeakCleared
! !

!GarbageCollector methodsFor: 'spaces'!
reserve: n
	"Address space for a space, not memory: unaccounted (MAP_NORESERVE), so that forking (a pty, an external program) needs no RAM and swap for the whole maximum heap."
	<function>
	<var: #n type: 'size_t'>
	| p |
	p := posix mmap: self null length: n protection: (posix PROT_READ bitOr: posix PROT_WRITE) flags: ((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: posix MAP_NORESERVE) file: -1 offset: 0.
	p = posix MAP_FAILED ifTrue: [self fatal: 'cannot reserve %zu bytes' with: n].
	^self cCoerce: p to: 'uint64_t'
!
reserveHuge: n
	"As reserve:, aligned to 2 MB and backed by huge pages where the system has them (Linux): bump allocation into a space then faults a page in per 2 MB instead of per 4 KB (a 64 MB eden: 32 faults, not 16,384), and the mutator and the collector miss the TLB less."
	<function>
	<var: #n type: 'size_t'>
	| p |
	posix MADV_HUGEPAGE = 0 ifTrue: [^self reserve: n].
	p := ((self reserve: n + HUGE_PAGE) + HUGE_PAGE - 1) bitClear: HUGE_PAGE - 1.
	self adviseHuge: p size: n.
	^p
!
adviseHuge: p size: n
	<function>
	(posix MADV_HUGEPAGE ~= 0 and: [(libc getenv: 'SAMALTAK_GC_NO_THP') isNull]) ifTrue: [posix madvise: (self ptr: p) length: n advice: posix MADV_HUGEPAGE]
!
releasePages: address size: n
	"Tell the system the whole pages in [address, address + n) are not needed: their memory goes back to it until they are touched again. Their contents are undefined afterwards (zeroes on Linux, kept on macOS and UEFI): only for memory whose contents do not matter."
	<export>
	<var: #address type: 'void *'>
	<var: #n type: 'uint64_t'>
	| lo hi |
	lo := ((self cCoerce: address to: 'uint64_t') + 16383) bitClear: 16383.
	hi := ((self cCoerce: address to: 'uint64_t') + n) bitClear: 16383.
	hi > lo ifTrue: [posix madvise: (self ptr: lo) length: hi - lo advice: posix MADV_DONTNEED]
!
releaseFreeMemory
	"Scavenge, then give back the pages of eden and of the empty survivor space: what an idle program holds only because it once allocated. They are touched again as it allocates."
	<export>
	self scavenge.
	self releasePages: (self ptr: edenLo) size: edenHi - edenLo.
	self releasePages: (self ptr: survOtherLo) size: survOtherHi - survOtherLo
!
discard: p size: n
	"Give the pages back (a fresh anonymous mapping over them)."
	<function>
	| m |
	m := (n + 16383) bitClear: 16383.
	m ~= 0 ifTrue: [
		posix mmap: (self ptr: p) length: m protection: (posix PROT_READ bitOr: posix PROT_WRITE)
			flags: (((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: posix MAP_FIXED) bitOr: posix MAP_NORESERVE) file: -1 offset: 0.
		self adviseHuge: p size: m]
!
init: edenBytes survivor: survBytes maxHeap: maxHeap
	"Reserve the spaces: eden, two survivor spaces of survBytes (0: a quarter of eden), old space."
	<function>
	| surv young |
	surv := survBytes = 0 ifTrue: [edenBytes quo: 4] ifFalse: [(survBytes + 7) bitClear: 7].
	tenureAge = 0 ifTrue: [self tenureAge: TENURE_AGE].
	survivalRate := 100.
	young := edenBytes + (2 * surv).
	youngLo := self reserveHuge: young.
	youngHi := youngLo + young.
	edenLo := youngLo.
	self edenTop: youngLo.
	edenHi := edenLo + edenBytes.
	self allocLimit: edenHi.
	survLo := survTop := edenHi.
	survHi := survLo + surv.
	survOtherLo := survHi.
	survOtherHi := survOtherLo + surv.
	maxHeapBytes := maxHeap.
	heapReserve := (maxHeap quo: 8) < (128 << 20) ifTrue: [maxHeap quo: 8] ifFalse: [128 << 20].
	lowSpaceLevel := 0.
	lowSpacePending := false.
	oldReserve := maxHeap + young + (1 << 20).
	oldLo := oldTop := self reserveHuge: oldReserve.
	oldHi := oldLo + oldReserve.
	oldAltLo := self reserveHuge: oldReserve.
	oldAltHi := oldAltLo + oldReserve.
	oldBudget := MIN_BUDGET
! !

!GarbageCollector methodsFor: 'remembered set'!
remember: o
	<function>
	self header: o put: ((self header: o) bitOr: H_REMEMBERED).
	remsetCount = remsetCap ifTrue: [
		remsetCap := remsetCap = 0 ifTrue: [4096] ifFalse: [remsetCap * 2].
		remset := self cCoerce: (libc realloc: remset size: remsetCap * 8) to: 'oop *'.
		remset isNull ifTrue: [self fatal: 'out of memory growing the remembered set to %zu entries' with: remsetCap]].
	remset at: remsetCount put: o.
	remsetCount := remsetCount + 1
!
rememberIfOld: o
	((self isPtr: o) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]) ifTrue: [self remember: o]
! !

!GarbageCollector methodsFor: 'roots'!
forEachRoot: fn
	"The VM's roots: the variables holding oops (through a copy in memory, so fn gets pointers to them), the temporary roots, the scheduler's ledger, the pushed roots and the interpreter's frames."
	<function>
	| r |
	r := self local: 'oop[6]'.
	r at: 0 put: memory specialsOop.
	r at: 1 put: interpreter activeCtx.
	r at: 2 put: scheduler lastPreempted.
	r at: 3 put: scheduler allocSampleClass.
	r at: 4 put: interpreter primResult.
	r at: 5 put: interpreter resendSelector.
	0 to: 5 do: [:i | fn call: r + i].
	memory specialsOop: (r at: 0).
	interpreter activeCtx: (r at: 1).
	scheduler lastPreempted: (r at: 2).
	scheduler allocSampleClass: (r at: 3).
	interpreter primResult: (r at: 4).
	interpreter resendSelector: (r at: 5).
	0 to: 3 do: [:i | fn call: interpreter tmpRoots + i].
	0 to: scheduler ledgerN - 1 do: [:i | fn call: scheduler ledgerProcs + i].
	0 to: memory rootCount - 1 do: [:i | fn call: (memory rootAt: i)].
	interpreter roots: fn
!
registerWeakOwners: update invalidate: invalidate
	"Register the native weak-owner table's two hooks. Neither runs Smalltalk."
	<function>
	<var: #update type: 'void (*)(bool (*)(oop *))'>
	<var: #invalidate type: 'void (*)(void)'>
	updateWeakOwners := update.
	invalidateWeakOwners := invalidate
!
invalidateNativeWeakOwners
	<function>
	invalidateWeakOwners notNull ifTrue: [invalidateWeakOwners call]
! !

!GarbageCollector methodsFor: 'verification'!
markStartsFrom: lo to: hi
	<function>
	| p k |
	p := lo.
	[p < hi] whileTrue: [
		k := (p - vlo) quo: 8.
		startBits at: (k quo: 8) put: ((startBits at: (k quo: 8)) bitOr: 1 << (k rem: 8)) asUInt8.
		p := p + (self objBytes: p)]
!
validRef: v
	<function>
	| inOld inSurv inEden k |
	(self isPtr: v) ifFalse: [^true].
	inOld := v >= oldLo and: [v < oldTop].
	inSurv := v >= survLo and: [v < survTop].
	inEden := v >= edenLo and: [v < self edenTop].
	inEden ifTrue: [^true].
	(inOld or: [inSurv]) ifFalse: [^false].
	k := (v - vlo) quo: 8.
	^((startBits at: (k quo: 8)) bitAnd: 1 << (k rem: 8)) ~= 0
!
verifySpaceFrom: lo to: hi old: isOld
	<function>
	| p young v |
	p := lo.
	[p < hi] whileTrue: [
		((self header: p) bitAnd: H_FORWARDED) ~= 0 ifTrue: [self fatal: 'verify: forwarded object %p' with: (self ptr: p)].
		((self isPtr: (self rawClass: p)) and: [self validRef: (self rawClass: p)]) ifFalse: [self fatal: 'verify: bad class in %p' with: (self ptr: p)].
		young := self isYoung: (self rawClass: p).
		(self fmtHasPointers: (self formatOf: p)) ifTrue: [
			0 to: (self numSlots: p) asInt64 - 1 do: [:i |
				v := (self slotsOf: p) at: i.
				(self validRef: v) ifFalse: [self fatal: 'verify: bad slot in %p: %p' with: (self ptr: p) with: (self ptr: v)].
				((self isPtr: v) and: [self isYoung: v]) ifTrue: [young := true]]].
		(isOld and: [young and: [((self header: p) bitAnd: H_REMEMBERED) = 0]]) ifTrue: [
			self fatal: 'verify: unremembered old object %p' with: (self ptr: p)].
		p := p + (self objBytes: p)]
!
verifyHeap
	<function>
	| lo hi n |
	lo := oldLo < youngLo ifTrue: [oldLo] ifFalse: [youngLo].
	hi := oldTop > youngHi ifTrue: [oldTop] ifFalse: [youngHi].
	vlo := lo.
	n := ((hi - lo) quo: 64) + 1.
	startBits := self cCoerce: (libc calloc: n size: 1) to: 'uint8_t *'.
	startBits isNull ifTrue: [self fatal: 'verify: out of memory'].
	self markStartsFrom: oldLo to: oldTop.
	self markStartsFrom: survLo to: survTop.
	self verifySpaceFrom: oldLo to: oldTop old: true.
	self verifySpaceFrom: survLo to: survTop old: false.
	((self validRef: memory specialsOop) and: [self validRef: interpreter activeCtx]) ifFalse: [self fatal: 'verify: bad root'].
	(interpreter framesValid: (self functionPointer: #validRef:)) ifFalse: [self fatal: 'verify: bad frame slot'].
	(jit headersValid: (self functionPointer: #validRef:)) ifFalse: [self fatal: 'verify: bad compiled method'].
	libc free: startBits
!
afterGC
	<function>
	verify < 0 ifTrue: [verify := (libc getenv: 'SAMALTAK_VERIFY_GC') notNull ifTrue: [1] ifFalse: [0]].
	verify ~= 0 ifTrue: [self verifyHeap].
	gcEpoch := gcEpoch + 1.
	memory refreshSpecials.
	interpreter flushMethodCache.
	interpreter afterGC.
	jit afterGC.
	memory resetAllocLimit
! !

!GarbageCollector methodsFor: 'scavenging'!
scavCopy: o
	<function>
	| h bytes age dst |
	h := self header: o.
	(h bitAnd: H_FORWARDED) ~= 0 ifTrue: [^self rawClass: o].
	bytes := self objBytes: o.
	age := (((h >> H_AGE_SHIFT) bitAnd: 3) + 1) asUInt32.
	copiedBytes at: age put: (copiedBytes at: age) + bytes.
	(age >= tenureAge or: [toTop + bytes > toHi])
		ifTrue: [
			dst := oldTop.
			oldTop := oldTop + bytes.
			statTenured := statTenured + bytes.
			libc memcpy: (self ptr: dst) from: (self ptr: o) size: bytes.
			self header: dst put: (h bitClear: H_GCBITS)]
		ifFalse: [
			dst := toTop.
			toTop := toTop + bytes.
			ageBytes at: age put: (ageBytes at: age) + bytes.
			libc memcpy: (self ptr: dst) from: (self ptr: o) size: bytes.
			self header: dst put: ((h bitClear: H_GCBITS) bitOr: age asUInt64 << H_AGE_SHIFT)].
	self header: o put: (h bitOr: H_FORWARDED).
	self rawClass: o put: dst.
	^dst
!
scavRoot: p
	<function>
	| v |
	v := p value.
	((self isPtr: v) and: [self isYoung: v]) ifTrue: [p value: (self scavCopy: v)]
!
isContext: o
	<function>
	| c ctx |
	c := self rawClass: o.
	ctx := memory clsContext.
	^c = ctx or: [((self header: ctx) bitAnd: H_FORWARDED) ~= 0 and: [c = (self rawClass: ctx)]]
!
tracedSlots: o
	"Number of leading slots the collector traces. A context's slots above stackp are stale and are cleared (the interpreter writes back stackp before anything can allocate); a weak object's indexable slots are left for clearWeakSlots."
	<function>
	| f sp n live |
	f := self formatOf: o.
	(self fmtHasPointers: f) ifFalse: [^0].
	(f = F_FIXVAR and: [self isContext: o]) ifTrue: [
		sp := (self slotsOf: o) at: CTX_STACKP.
		n := self numSlots: o.
		((self isInt: sp) not or: [(self intVal: sp) < 0 or: [(self intVal: sp) > (n - CTX_FIXED) asInt64]]) ifTrue: [^n].
		live := (CTX_FIXED + (self intVal: sp)) asUInt32.
		live to: n asInt64 - 1 do: [:i | (self slotsOf: o) at: i put: memory nilOop].
		^live].
	f ~= F_WEAK ifTrue: [^self numSlots: o].
	weakCount = weakCap ifTrue: [
		weakCap := weakCap = 0 ifTrue: [256] ifFalse: [weakCap * 2].
		weakList := self cCoerce: (libc realloc: weakList size: weakCap * 8) to: 'oop *'.
		weakList isNull ifTrue: [self fatal: 'out of memory growing the weak object list to %zu entries' with: weakCap]].
	weakList at: weakCount put: o.
	weakCount := weakCount + 1.
	^memory fixedFields: o
!
refersToYoung: o
	<function>
	| v |
	(self isYoung: (self rawClass: o)) ifTrue: [^true].
	0 to: (self numSlots: o) asInt64 - 1 do: [:i |
		v := (self slotsOf: o) at: i.
		((self isPtr: v) and: [self isYoung: v]) ifTrue: [^true]].
	^false
!
clearWeakSlots: isDead
	"isDead answers whether *v was not reached, updating *v to its new address otherwise."
	<function>
	| nl w s |
	nl := memory nilOop.
	0 to: weakCount asInt64 - 1 do: [:k |
		w := weakList at: k.
		s := self slotsOf: w.
		(memory fixedFields: w) to: (self numSlots: w) asInt64 - 1 do: [:i |
			((self isPtr: (s at: i)) and: [(s at: i) ~= 0]) ifTrue: [
				(isDead call: s + i) ifTrue: [
					s at: i put: nl.
					statWeakCleared := statWeakCleared + 1.
					finalizationPending := true]]]].
	finalizationPending ifTrue: [scheduler requestInterruptCheck]
!
scavDead: v
	<function>
	((self isYoung: v value) not or: [v value >= toLo and: [v value < toHi]]) ifTrue: [^false].
	((self header: v value) bitAnd: H_FORWARDED) = 0 ifTrue: [^true].
	v value: (self rawClass: v value).
	^false
!
scavScan: o
	"Copy young referents of o; answer whether o still refers to young objects (weak slots excluded)."
	<function>
	| young c s v |
	young := false.
	c := self rawClass: o.
	(self isYoung: c) ifTrue: [
		c := self scavCopy: c.
		self rawClass: o put: c.
		young := young or: [self isYoung: c]].
	s := self slotsOf: o.
	0 to: (self tracedSlots: o) asInt64 - 1 do: [:i |
		v := s at: i.
		((self isPtr: v) and: [self isYoung: v]) ifTrue: [
			v := self scavCopy: v.
			s at: i put: v.
			young := young or: [self isYoung: v]]].
	^young
!
scavenge
	<function>
	| t0 tenureScan kept o scan w tenured0 us |
	interpreter beforeGC.
	t0 := scheduler workClockHeldUs.
	tenured0 := statTenured.
	0 to: 3 do: [:a | ageBytes at: a put: 0].
	0 to: 4 do: [:a | copiedBytes at: a put: 0].
	statScavenges := statScavenges + 1.
	statAllocated := statAllocated + (self edenTop - edenLo).
	toLo := toTop := survOtherLo.
	toHi := survOtherHi.
	tenureScan := oldTop.
	weakCount := 0.
	self forEachRoot: (self functionPointer: #scavRoot:).
	jit youngRoots: (self functionPointer: #scavRoot:).
	kept := 0.
	0 to: remsetCount asInt64 - 1 do: [:i |
		o := remset at: i.
		self header: o put: ((self header: o) bitClear: H_REMEMBERED).
		((self scavScan: o) and: [(self formatOf: o) ~= F_WEAK]) ifTrue: [
			self header: o put: ((self header: o) bitOr: H_REMEMBERED).
			remset at: kept put: o.
			kept := kept + 1]].
	remsetCount := kept asUInt64.
	scan := toLo.
	[scan < toTop or: [tenureScan < oldTop]] whileTrue: [
		[scan < toTop] whileTrue: [
			self scavScan: scan.
			scan := scan + (self objBytes: scan)].
		[tenureScan < oldTop] whileTrue: [
			((self scavScan: tenureScan) and: [((self header: tenureScan) bitAnd: H_REMEMBERED) = 0]) ifTrue: [self remember: tenureScan].
			tenureScan := tenureScan + (self objBytes: tenureScan)]].
	self clearWeakSlots: (self functionPointer: #scavDead:).
	updateWeakOwners notNull ifTrue: [updateWeakOwners call: (self functionPointer: #scavDead:)].
	0 to: weakCount asInt64 - 1 do: [:k |
		w := weakList at: k.
		((self isYoung: w) not and: [((self header: w) bitAnd: H_REMEMBERED) = 0 and: [self refersToYoung: w]]) ifTrue: [self remember: w]].
	survOtherLo := survLo.
	survOtherHi := survHi.
	survLo := toLo.
	survTop := toTop.
	survHi := toHi.
	self edenTop: edenLo.
	statSurvived := statSurvived + (survTop - survLo).
	tenureAdaptive ifTrue: [self adaptTenure].
	self rememberIfOld: interpreter activeCtx.
	self afterGC.
	us := (scheduler workClockHeldUs - t0) asUInt64.
	statScavengeUs := statScavengeUs + us.
	us > statScavengeMaxUs ifTrue: [statScavengeMaxUs := us].
	self logGC ifTrue: [
		libc fprintf: libc stderr format: 'gc: scavenge %llu us survived %llu tenured %llu remset %llu' with: us with: survTop - survLo with: statTenured - tenured0 with: remsetCount asUInt64.
		libc fprintf: libc stderr format: ' old %llu age %u survival %u%%' with: oldTop - oldLo with: tenureAge with: survivalRate.
		libc fprintf: libc stderr format: ' copied %llu %llu' with: (copiedBytes at: 1) with: (copiedBytes at: 2).
		libc fprintf: libc stderr format: ' %llu %llu
' with: (copiedBytes at: 3) with: (copiedBytes at: 4)]
!
adaptTenure
	"Choose the next scavenge's tenure age. survivalRate is the share, in percent, of the survivors of one scavenge (age 1) that live through the next one too (a running average; 100 until measured). Where most do, survivors are long-lived: tenure them at age 2 (copied once). Where most die, they are medium-lived (alive across a scavenge or two): keep them young up to age MAX_TENURE_AGE, so that they die in the survivor spaces instead of growing old space towards a full GC, as long as the younger ones fill no more than half the survivor space (its overflow is tenured at once)."
	<function>
	| desired cum t s |
	(prevAgeBytes at: 1) >= (64 << 10) ifTrue: [
		s := ((copiedBytes at: 2) * 100) quo: (prevAgeBytes at: 1).
		s > 100 ifTrue: [s := 100].
		survivalRate := ((survivalRate * 3) + s asUInt32) quo: 4].
	desired := (survHi - survLo) quo: 2.
	t := survivalRate >= 50 ifTrue: [2] ifFalse: [MAX_TENURE_AGE].
	cum := 0 asUInt64.
	1 to: MAX_TENURE_AGE - 1 do: [:a |
		cum := cum + (ageBytes at: a).
		(a + 1 < t and: [cum > desired]) ifTrue: [t := a + 1].
		prevAgeBytes at: a put: (ageBytes at: a)].
	tenureAge := t asUInt32
!
logGC
	"Whether SAMALTAK_GC_LOG asks for a line on stderr per collection."
	<function>
	gcLog < 0 ifTrue: [gcLog := (libc getenv: 'SAMALTAK_GC_LOG') notNull ifTrue: [1] ifFalse: [0]].
	^gcLog ~= 0
! !

!GarbageCollector methodsFor: 'full GC'!
fullCopy: o
	<function>
	| h bytes dst |
	h := self header: o.
	(h bitAnd: H_FORWARDED) ~= 0 ifTrue: [^self rawClass: o].
	bytes := self objBytes: o.
	dst := ftTop.
	ftTop := ftTop + bytes.
	libc memcpy: (self ptr: dst) from: (self ptr: o) size: bytes.
	self header: dst put: (h bitClear: H_GCBITS).
	self header: o put: (h bitOr: H_FORWARDED).
	self rawClass: o put: dst.
	^dst
!
fullRoot: p
	<function>
	| v |
	v := p value.
	((self isPtr: v) and: [v ~= 0]) ifTrue: [p value: (self fullCopy: v)]
!
fullDead: v
	<function>
	((self header: v value) bitAnd: H_FORWARDED) = 0 ifTrue: [^true].
	v value: (self rawClass: v value).
	^false
!
fullGC
	<function>
	| t0 oldUsed scan s lo hi live classSlot nl |
	interpreter beforeGC.
	t0 := scheduler workClockHeldUs.
	statFullGcs := statFullGcs + 1.
	statAllocated := statAllocated + (self edenTop - edenLo).
	oldUsed := oldTop - oldLo.
	ftTop := oldAltLo.
	weakCount := 0.
	nl := self local: 'oop'.
	nl value: memory nilOop.
	self fullRoot: nl.
	memory nilOop: nl value.
	self forEachRoot: (self functionPointer: #fullRoot:).
	jit allRoots: (self functionPointer: #fullRoot:).
	scan := oldAltLo.
	[scan < ftTop] whileTrue: [
		classSlot := self cCoerce: scan + 8 to: 'oop *'.
		self fullRoot: classSlot.
		s := self slotsOf: scan.
		0 to: (self tracedSlots: scan) asInt64 - 1 do: [:i | self fullRoot: s + i].
		scan := scan + (self objBytes: scan)].
	self clearWeakSlots: (self functionPointer: #fullDead:).
	updateWeakOwners notNull ifTrue: [updateWeakOwners call: (self functionPointer: #fullDead:)].
	self discard: oldLo size: oldUsed.
	lo := oldLo.
	hi := oldHi.
	oldLo := oldAltLo.
	oldHi := oldAltHi.
	oldTop := ftTop.
	oldAltLo := lo.
	oldAltHi := hi.
	self edenTop: edenLo.
	survTop := survLo.
	0 to: 3 do: [:a | prevAgeBytes at: a put: 0].
	remsetCount := 0.
	live := oldTop - oldLo.
	self noteLive: live.
	oldBudget := live * 2 > MIN_BUDGET ifTrue: [live * 2] ifFalse: [MIN_BUDGET].
	oldBudget > (self lowSpaceLimit: lowSpaceLevel) ifTrue: [oldBudget := self lowSpaceLimit: lowSpaceLevel].
	self rememberIfOld: interpreter activeCtx.
	self afterGC.
	statFullUs := statFullUs + (scheduler workClockHeldUs - t0) asUInt64.
	self logGC ifTrue: [libc fprintf: libc stderr format: 'gc: full %llu us live %llu
' with: (scheduler workClockHeldUs - t0) asUInt64 with: live].
	live > maxHeapBytes ifTrue: [self fatal: 'out of memory (%llu MB live, limit %zu MB)' with: live >> 20 with: maxHeapBytes >> 20]
!
collectGarbage: need
	"Scavenge or full GC so that need bytes fit in eden: a full GC when old space is over its budget, or would be if the survivors were tenured (most of eden dies, so its size does not count), or, near the next low-space limit, if all of the young generation were (so that a full GC notices the limit before a scavenge takes old space past it)."
	<function>
	| oldUsed youngUsed |
	oldUsed := oldTop - oldLo.
	youngUsed := (self edenTop - edenLo) + (survTop - survLo).
	(oldUsed + (survTop - survLo) > oldBudget or: [oldUsed + youngUsed > oldBudget and: [oldUsed + youngUsed > (self lowSpaceLimit: lowSpaceLevel)]])
		ifTrue: [self fullGC]
		ifFalse: [
			self scavenge.
			oldTop - oldLo > oldBudget ifTrue: [self fullGC]]
!
noteLive: live
	"After a full GC: raise lowSpaceLevel past each limit live exceeds (then a safepoint signals it), or re-arm."
	<function>
	live <= (self lowSpaceLimit: 0)
		ifTrue: [
			lowSpaceLevel := 0.
			lowSpacePending := false]
		ifFalse: [
			[lowSpaceLevel < 2 and: [live > (self lowSpaceLimit: lowSpaceLevel)]] whileTrue: [
				lowSpaceLevel := lowSpaceLevel + 1.
				lowSpacePending := true.
				lowSpaceHash := self hashOf: scheduler activeProcess].
			lowSpacePending ifTrue: [scheduler requestInterruptCheck]]
!
oldAllocTry: bytes limit: limit
	"May full GC; 0 if it cannot fit within limit (the heap limit, or softLimit for Smalltalk's allocations)."
	<function>
	| want p |
	bytes > limit ifTrue: [^0].
	(oldTop - oldLo) + bytes > oldBudget ifTrue: [
		self fullGC.
		want := 2 * ((oldTop - oldLo) + bytes).
		want > oldBudget ifTrue: [oldBudget := want < limit ifTrue: [want] ifFalse: [limit]]].
	(oldTop - oldLo) + bytes > limit ifTrue: [^0].
	p := oldTop.
	oldTop := oldTop + bytes.
	^p
! !

!GarbageCollector methodsFor: 'become'!
becomeRoot: p
	<function>
	p value = becomeFrom ifTrue: [p value: becomeTo]
!
becomeForward: from to: to
	"One-way become; call right after a full GC (no young objects)."
	<function>
	| p s |
	interpreter beforeGC.
	becomeFrom := from.
	becomeTo := to.
	self invalidateNativeWeakOwners.
	jit becomeMethod: from.
	self forEachRoot: (self functionPointer: #becomeRoot:).
	jit allRoots: (self functionPointer: #becomeRoot:).
	p := oldLo.
	[p < oldTop] whileTrue: [
		self becomeRoot: (self cCoerce: p + 8 to: 'oop *').
		(self fmtHasPointers: (self formatOf: p)) ifTrue: [
			s := self slotsOf: p.
			0 to: (self numSlots: p) asInt64 - 1 do: [:i | (s at: i) = from ifTrue: [s at: i put: to]]].
		p := p + (self objBytes: p)].
	self afterGC
!
walkYoungSpace: fn data: data
	"fn on every object of the survivor space and of eden."
	<function>
	| p |
	p := survLo.
	[p < survTop] whileTrue: [
		fn call: p with: data.
		p := p + (self objBytes: p)].
	p := edenLo.
	[p < self edenTop] whileTrue: [
		fn call: p with: data.
		p := p + (self objBytes: p)]
!
walkOldSpace: fn data: data
	<function>
	| end p |
	end := oldTop.
	p := oldLo.
	[p < end] whileTrue: [
		fn call: p with: data.
		p := p + (self objBytes: p)]
! !
