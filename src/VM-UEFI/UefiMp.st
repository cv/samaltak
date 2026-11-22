UefiModule subclass: #UefiMp
	instanceVariableNames: 'cpu atomics posix sharedLine mpAps mpTls mpSlots mpWorkers mpHow mpHotTicks mpNapTicks mpEl mpHvc'
	classVariableNames: 'MP_AP_BYTES MP_HOT_MS MP_MAX_CPUS MP_NAP_MS MP_NONE MP_PART_MASK MP_PSCI MP_SERVICES MP_STACK_BYTES MP_TLS_BYTES'
	package: 'VM-UEFI'!

UefiMp comment: 'The application processors: the CPUs besides the boot CPU, running only the VM''s C (no heap, no allocation, no firmware services: UEFI allows them on the boot CPU alone), for CpuWorkers (UefiCpuWorkers: PlatformRaster''s bands) and the JIT''s helper thread (UefiJitPlatform: background optimizing compilation). docs/uefi.md, More than one CPU.

Starting them (start, on the boot CPU at start): with the firmware''s EFI_MP_SERVICES_PROTOCOL where it has one (OVMF; edk2''s CpuDxe, ArmPsciMpServicesDxe), StartupThisAP of apStart: on each enabled one, non-blocking, never returning; else on arm64 PSCI CPU_ON of each enabled CPU of the ACPI MADT, by HVC or SMC as the FADT says (QEMU''s AAVMF; firmware following Arm''s SBBR), at UefiArm64Cpu''s entry stub, which sets up the MMU as the boot CPU''s from the MpAp it gets. Each runs apMain: on a stack of its own (MP_STACK_BYTES) with its own block of _Thread_local variables (MP_TLS_BYTES; VMModule class>>threadLocalVariables), the boot CPU too.

Work: a parallel job (parallel:context:count:) is a function, its context and a number of parts, published in one word of MpShared (seq << 40 | count << 20 | next part); the boot CPU and any application processor take the next part by a compare-and-swap of that word, run it and count it done; the boot CPU returns once all are. A part taken by a CPU that compiles meanwhile is simply taken by another. Waiting: on the job word''s cache line (UefiCpu>>waitWord:old:: WFE on the exclusive monitor, WFET; MONITOR/MWAIT) while work came in the last MP_HOT_MS ms, then asleep (UefiCpu>>sleepOn:old:until:) for a sixteenth of the time idle, at most MP_NAP_MS ms: arm64 at EL2 in WFET, which the boot CPU''s SEV ends; under a hypervisor (EL1) in WFIT, whose vCPU sleeps to the deadline (KVM''s WFE trap only yields, and halt polling spins through naps shorter than its window: 0.5 ms naps cost a quarter of a host core each); x86-64 in HLT, which wake''s IPI ends. Idle application processors cost the host next to nothing; the boot CPU waits only for the last parts of its own job. Atomics are C11''s (UefiAtomics), acquire and release where the protocol needs them.

The JIT''s helper: startJit: gives its thread function to the last application processor online; its lock is a spin lock, its condition a counter it waits on as above, taking parts of parallel jobs meanwhile.'!

!UefiMp class methodsFor: 'declaring'!
declarations
	^#((cpu UefiCpu) (atomics UefiAtomics) (posix UefiPosix) (sharedLine 'MpShared *') (mpAps 'MpAp *') (mpTls 'uint8_t *')
		(mpSlots int64_t) (mpWorkers int64_t) (mpHow int32_t) (mpHotTicks uint64_t) (mpNapTicks uint64_t) (mpEl int64_t) (mpHvc bool))
!
cPreamble
	^'static inline unsigned long long uefi_load_acquire(void *p) { return __atomic_load_n((unsigned long long *)p, __ATOMIC_ACQUIRE); }
static inline void uefi_store_release(void *p, unsigned long long v) { __atomic_store_n((unsigned long long *)p, v, __ATOMIC_RELEASE); }
static inline _Bool uefi_cas(void *p, unsigned long long old, unsigned long long new_) { return __atomic_compare_exchange_n((unsigned long long *)p, &old, new_, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE); }
static inline unsigned long long uefi_fetch_add(void *p, unsigned long long v) { return __atomic_fetch_add((unsigned long long *)p, v, __ATOMIC_ACQ_REL); }
static inline unsigned long long uefi_swap(void *p, unsigned long long v) { return __atomic_exchange_n((unsigned long long *)p, v, __ATOMIC_ACQUIRE); }'
!
initialize
	"At most MP_MAX_CPUS CPUs; per CPU an MpAp of MP_AP_BYTES, MP_TLS_BYTES of thread-local variables, a stack of MP_STACK_BYTES; parts of a job at most MP_PART_MASK. How they were started: mpHow."
	MP_MAX_CPUS := 64.
	MP_AP_BYTES := 128.
	MP_TLS_BYTES := 8192.
	MP_STACK_BYTES := 4 * 1024 * 1024.
	MP_HOT_MS := 2.
	MP_NAP_MS := 10.
	MP_PART_MASK := 16rFFFFF.
	MP_NONE := 0.
	MP_SERVICES := 1.
	MP_PSCI := 2
! !

!UefiMp methodsFor: 'starting'!
start
	"On the boot CPU at start, with the firmware's boot services: its thread-local variables, then the application processors."
	<function>
	| pages bytes p |
	mpSlots := 1.
	mpWorkers := 0.
	mpHow := MP_NONE.
	(self sizeof: 'MpAp') > MP_AP_BYTES ifTrue: [self fatal: 'MpAp is too large'].
	bytes := 4096 + (MP_MAX_CPUS * MP_AP_BYTES) + (MP_MAX_CPUS * MP_TLS_BYTES).
	pages := self local: 'uint64_t'.
	(self efiFailed: (self efi: self boot allocatePages with: EFI_ALLOCATE_ANY_PAGES with: EFI_LOADER_DATA with: (bytes + 4095) >> 12 with: pages)) ifTrue: [
		self fatal: 'no memory for the CPUs'].
	p := self cCoerce: pages value to: 'uint8_t *'.
	libc memset: p value: 0 size: bytes asUInt64.
	sharedLine := self cCoerce: p to: 'MpShared *'.
	mpAps := self cCoerce: p + 4096 to: 'MpAp *'.
	mpTls := p + 4096 + (MP_MAX_CPUS * MP_AP_BYTES).
	cpu setThreadBlock: mpTls size: MP_TLS_BYTES.
	mpHotTicks := posix ticksPerUs * 1000 * MP_HOT_MS.
	mpNapTicks := posix ticksPerUs * 1000 * MP_NAP_MS.
	sharedLine jitAp: -1.
	self startWithServices ifFalse: [self startWithPsci].
	mpHow = MP_PSCI
		ifTrue: [libc fprintf: libc stderr format: 'samaltak: %d CPUs (PSCI by %s at EL%d)
' with: mpWorkers + 1 with: (mpHvc ifTrue: ['HVC'] ifFalse: ['SMC']) with: mpEl]
		ifFalse: [libc fprintf: libc stderr format: 'samaltak: %d CPUs (%s)
' with: mpWorkers + 1 with: (mpHow = MP_SERVICES ifTrue: ['MP services'] ifFalse: ['no MP services or PSCI'])]
!
newAp
	"The next application processor's MpAp: its index, thread-local block, stack and entry (apMain:); NULL if there is no room."
	<function>
	<returns: 'MpAp *'>
	| ap stack |
	mpSlots >= MP_MAX_CPUS ifTrue: [^self null].
	stack := self local: 'uint64_t'.
	(self efiFailed: (self efi: self boot allocatePages with: EFI_ALLOCATE_ANY_PAGES with: EFI_LOADER_DATA with: MP_STACK_BYTES >> 12 with: stack)) ifTrue: [^self null].
	ap := self ap: mpSlots.
	ap cpuIndex: mpSlots.
	ap tls: mpTls + (mpSlots * MP_TLS_BYTES).
	ap stackTop: stack value + MP_STACK_BYTES.
	ap entry: (self cCoerce: (self functionPointer: #apMain:) to: 'void *').
	mpSlots := mpSlots + 1.
	^ap
!
ap: i
	^self cCoerce: (self cCoerce: mpAps to: 'uint8_t *') + (i * MP_AP_BYTES) to: 'MpAp *'
!
waitOnline: ap
	"Whether ap's CPU comes online within half a second (counted in mpWorkers)."
	<function>
	<var: #ap type: 'MpAp *'>
	<returns: 'bool'>
	| deadline |
	deadline := cpu cycles + (posix ticksPerUs * 500000).
	[cpu cycles < deadline] whileTrue: [
		(atomics loadAcquire: (ap fieldAddress: #online)) ~= 0 ifTrue: [
			mpWorkers := mpWorkers + 1.
			^true].
		cpu waitWord: (ap fieldAddress: #online) old: 0].
	^false
!
startWithServices
	"EFI_MP_SERVICES_PROTOCOL: StartupThisAP of apStart: on each enabled application processor, non-blocking (a wait event that is never signaled: apStart: never returns). Answer whether the firmware has the protocol."
	<function>
	<returns: 'bool'>
	| guid mp n enabled me info event ap |
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16r3FDDA605 data2: 16rA76E data3: 16r4F46 data4: 16rAD2912F4531B3D08.
	mp := self local: 'EfiMpServices *'.
	(self efiFailed: (self efi: self boot locateProtocol with: guid with: self null with: mp)) ifTrue: [^false].
	mpHow := MP_SERVICES.
	n := self local: 'uint64_t'.
	enabled := self local: 'uint64_t'.
	me := self local: 'uint64_t'.
	(self efiFailed: (self efi: mp value getNumberOfProcessors with: mp value with: n with: enabled)) ifTrue: [^true].
	(self efiFailed: (self efi: mp value whoAmI with: mp value with: me)) ifTrue: [^true].
	info := self local: 'uint64_t[32]'.
	event := self local: 'void *'.
	0 to: n value asInt64 - 1 do: [:i |
		(i asUInt64 ~= me value
			and: [(self efiFailed: (self efi: mp value getProcessorInfo with: mp value with: i with: info)) not
			and: [((info at: 1) bitAnd: 2) ~= 0]]) ifTrue: [
				ap := self newAp.
				(ap notNull and: [(self efiFailed: (self efi: self boot createEvent with: 0 with: 0 with: self null with: self null with: event)) not]) ifTrue: [
					ap procNumber: i asUInt64.
					(self efiFailed: (self efi: mp value startupThisAp with: mp value with: (self functionPointer: #apStart:) with: i
						with: event value with: 0 with: ap with: self null)) ifFalse: [self waitOnline: ap]]]].
	^true
!
startWithPsci
	"Without MP services (arm64): PSCI CPU_ON, by HVC or SMC as the ACPI FADT's ARM_BOOT_ARCH flags say, of each enabled CPU in the ACPI MADT's GICC entries but this one, at UefiArm64Cpu's entry stub with its MpAp (cleaned to the point of coherency: it reads it with its MMU off)."
	<function>
	| rsdp xsdt fadt madt flags hvc e end mpidr mine ap r |
	cpu apEntry isNull ifTrue: [^self].
	rsdp := self acpiRoot.
	rsdp isNull ifTrue: [^self].
	(rsdp at: 15) < 2 ifTrue: [^self].
	xsdt := self cCoerce: (self le: rsdp + 24 size: 8) to: 'uint8_t *'.
	xsdt isNull ifTrue: [^self].
	fadt := self acpi: xsdt table: 16r50434146.
	madt := self acpi: xsdt table: 16r43495041.
	(fadt isNull or: [madt isNull]) ifTrue: [^self].
	(self le: fadt + 4 size: 4) < 131 ifTrue: [^self].
	flags := self le: fadt + 129 size: 2.
	(flags bitAnd: 1) = 0 ifTrue: [^self].
	hvc := (flags bitAnd: 2) ~= 0.
	mpHvc := hvc.
	ap := self local: 'MpAp'.
	cpu apContext: ap.
	mpEl := ap el asInt64.
	mpHow := MP_PSCI.
	mine := cpu mpidr.
	cpu cleanToPoc: cpu apEntry size: 512.
	e := madt + 44.
	end := madt + (self le: madt + 4 size: 4).
	[e + 2 <= end and: [(e at: 1) >= 2]] whileTrue: [
		((e at: 0) = 11 and: [(e at: 1) >= 76 and: [((self le: e + 12 size: 4) bitAnd: 1) ~= 0]]) ifTrue: [
			mpidr := (self le: e + 68 size: 8) bitAnd: 16rFF00FFFFFF.
			mpidr ~= mine ifTrue: [
				ap := self newAp.
				ap notNull ifTrue: [
					ap mpidr: mpidr.
					cpu apContext: ap.
					cpu cleanToPoc: ap size: MP_AP_BYTES.
					r := cpu psci: 16rC4000003 with: mpidr with: (self cCoerce: cpu apEntry to: 'uint64_t') with: (self cCoerce: ap to: 'uint64_t') hvc: hvc.
					r = 0 ifTrue: [self waitOnline: ap]]]].
		e := e + (e at: 1)]
!
acpiRoot
	"The ACPI 2.0 RSDP in the firmware's configuration table, NULL if there is none."
	<function>
	<returns: 'uint8_t *'>
	| t e |
	t := self cCoerce: firmware systemTable configurationTable to: 'uint8_t *'.
	0 to: firmware systemTable tableEntries asInt64 - 1 do: [:i |
		e := t + (24 * i).
		((self le: e size: 8) = 16r11D3E4F18868E871 and: [(self le: e + 8 size: 8) = 16r81883CC7800022BC]) ifTrue: [
			^self cCoerce: (self le: e + 16 size: 8) to: 'uint8_t *']].
	^self null
!
acpi: xsdt table: signature
	"The table the XSDT lists whose signature (its first four bytes, little-endian) is signature; NULL if none."
	<function>
	<var: #xsdt type: 'uint8_t *'>
	<var: #signature type: 'uint64_t'>
	<returns: 'uint8_t *'>
	| n t |
	n := ((self le: xsdt + 4 size: 4) asInt64 - 36) quo: 8.
	0 to: n - 1 do: [:i |
		t := self cCoerce: (self le: xsdt + 36 + (8 * i) size: 8) to: 'uint8_t *'.
		(t notNull and: [(self le: t size: 4) = signature]) ifTrue: [^t]].
	^self null
!
le: p size: n
	"The n-byte little-endian integer at p (at any alignment)."
	| v |
	v := self cCoerce: 0 to: 'uint64_t'.
	n - 1 to: 0 by: -1 do: [:i | v := (v << 8) bitOr: (p at: i) asUInt64].
	^v
! !

!UefiMp methodsFor: 'application processors'!
apStart: arg
	"An application processor from the firmware's MP services (the procedure, ms_abi; arg its MpAp): onto its own stack, to apMain:."
	<function>
	<abi: 'ms_abi'>
	<var: #arg type: 'void *'>
	| ap |
	ap := self cCoerce: arg to: 'MpAp *'.
	cpu call: ap entry with: arg onStack: (self cCoerce: ap stackTop to: 'void *')
!
apMain: ap
	"An application processor on its own stack: its thread-local variables, online, then work, forever."
	<function>
	<var: #ap type: 'MpAp *'>
	cpu setThreadBlock: ap tls size: MP_TLS_BYTES.
	atomics store: (ap fieldAddress: #online) releasing: 1.
	self work: ap cpuIndex
!
work: index
	"An application processor's loop: parts of parallel jobs, the JIT's helper thread if it is given to this CPU (it never returns), waiting in between."
	<function>
	<var: #index type: 'int64_t'>
	| seen last fn |
	seen := self local: 'uint64_t'.
	last := cpu cycles.
	[(self helpOnce: seen)
		ifTrue: [last := cpu cycles]
		ifFalse: [
			fn := atomics loadAcquire: (sharedLine fieldAddress: #jitFn).
			(fn ~= 0 and: [sharedLine jitAp = index]) ifTrue: [(self cCoerce: fn to: 'void *(*)(void *)') call: self null].
			self idle: seen value since: last]] repeat
!
idle: seen since: last
	"Wait for work: on the job word's line (seen: its value last looked at) while work came in the last MP_HOT_MS ms, else asleep for a sixteenth of the time since, at most MP_NAP_MS ms (UefiCpu>>sleepOn:old:until:)."
	| now nap |
	now := cpu cycles.
	(now - last) < mpHotTicks ifTrue: [
		cpu waitWord: (sharedLine fieldAddress: #job) old: seen.
		^self].
	nap := (now - last) >> 4.
	nap > mpNapTicks ifTrue: [nap := mpNapTicks].
	cpu sleepOn: (sharedLine fieldAddress: #job) old: seen until: now + nap
!
helpOnce: seen
	"Take the parallel job's next part if one is left and run it; answer whether there was one (seen: the job word looked at)."
	<function>
	<var: #seen type: 'uint64_t *'>
	<returns: 'bool'>
	| w next fn |
	w := atomics loadAcquire: (sharedLine fieldAddress: #job).
	seen value: w.
	next := w bitAnd: MP_PART_MASK.
	next >= ((w >> 20) bitAnd: MP_PART_MASK) ifTrue: [^false].
	(atomics compare: (sharedLine fieldAddress: #job) and: w swap: w + 1) ifFalse: [^true].
	fn := sharedLine fn.
	fn call: sharedLine ctx with: next asInt64.
	atomics fetch: (sharedLine fieldAddress: #done) add: 1.
	^true
! !

!UefiMp methodsFor: 'parallel jobs'!
workerCount
	"The application processors online."
	<function>
	<returns: 'int64_t'>
	^mpWorkers
!
parallel: fn context: ctx count: n
	"fn(ctx, i) for 0 <= i < n on this CPU and the application processors; answer when all are done (CpuWorkers>>parallelRun:context:count:). The boot CPU's alone."
	<function>
	<var: #fn type: 'void (*)(void *, int64_t)'>
	<var: #ctx type: 'void *'>
	<var: #n type: 'int64_t'>
	| seq seen d |
	(mpWorkers = 0 or: [n < 2 or: [n > MP_PART_MASK]]) ifTrue: [
		0 to: n - 1 do: [:i | fn call: ctx with: i].
		^self].
	sharedLine fn: fn.
	sharedLine ctx: ctx.
	atomics store: (sharedLine fieldAddress: #done) releasing: 0.
	seq := (((atomics loadAcquire: (sharedLine fieldAddress: #job)) >> 40) + 1) bitAnd: 16rFFFFFF.
	atomics store: (sharedLine fieldAddress: #job) releasing: ((seq << 40) bitOr: (n asUInt64 << 20)).
	cpu wake.
	seen := self local: 'uint64_t'.
	[self helpOnce: seen] whileTrue.
	d := atomics loadAcquire: (sharedLine fieldAddress: #done).
	[d < n asUInt64] whileTrue: [
		cpu waitWord: (sharedLine fieldAddress: #done) old: d.
		d := atomics loadAcquire: (sharedLine fieldAddress: #done)]
! !

!UefiMp methodsFor: 'the JIT''s helper'!
startJit: fn
	"Give the JIT's helper thread (fn, called with NULL; it never returns) to the last application processor online; answer whether there is one."
	<function>
	<var: #fn type: 'void *(*)(void *)'>
	<returns: 'bool'>
	| last |
	last := -1.
	1 to: mpSlots - 1 do: [:i | (atomics loadAcquire: ((self ap: i) fieldAddress: #online)) ~= 0 ifTrue: [last := i]].
	last < 0 ifTrue: [^false].
	sharedLine jitAp: last.
	atomics store: (sharedLine fieldAddress: #jitFn) releasing: (self cCoerce: fn to: 'uint64_t').
	cpu wake.
	^true
!
jitLock
	<function>
	[(atomics swap: (sharedLine fieldAddress: #jitLock) with: 1) = 0] whileFalse: [
		[(atomics loadAcquire: (sharedLine fieldAddress: #jitLock)) ~= 0] whileTrue: [
			cpu waitWord: (sharedLine fieldAddress: #jitLock) old: 1]]
!
jitUnlock
	<function>
	atomics store: (sharedLine fieldAddress: #jitLock) releasing: 0.
	cpu wake
!
jitWait
	"With the lock held: let go of it, wait until jitWake (taking parts of parallel jobs meanwhile), take it again."
	<function>
	| old seen last |
	old := atomics loadAcquire: (sharedLine fieldAddress: #jitWake).
	self jitUnlock.
	seen := self local: 'uint64_t'.
	last := cpu cycles.
	[(atomics loadAcquire: (sharedLine fieldAddress: #jitWake)) = old] whileTrue: [
		(self helpOnce: seen)
			ifTrue: [last := cpu cycles]
			ifFalse: [self idle: seen value since: last]].
	self jitLock
!
jitWake
	"With the lock held: wake whoever waits in jitWait."
	<function>
	atomics fetch: (sharedLine fieldAddress: #jitWake) add: 1.
	cpu wake
! !

CpuWorkers subclass: #UefiCpuWorkers
	instanceVariableNames: 'mp'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiCpuWorkers comment: 'The other CPUs on UEFI: the application processors UefiMp started.'!

!UefiCpuWorkers class methodsFor: 'declaring'!
declarations
	^#((mp UefiMp))
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiCpuWorkers methodsFor: 'parallel'!
parallelWorkers
	<export>
	<returns: 'int64_t'>
	^mp workerCount
!
parallelRun: fn context: ctx count: n
	<export>
	<var: #fn type: 'void (*)(void *, int64_t)'>
	<var: #ctx type: 'void *'>
	<var: #n type: 'int64_t'>
	mp parallel: fn context: ctx count: n
! !

CLibrary subclass: #UefiAtomics
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiAtomics comment: 'C11''s atomics on 64-bit words for UefiMp (its C preamble: the compiler''s __atomic builtins): LDAXR/STLXR or LSE on arm64, LOCK-prefixed instructions on x86-64.'!

!UefiAtomics class methodsFor: 'declaring'!
targetOS
	^#uefi
! !

!UefiAtomics methodsFor: 'functions'!
loadAcquire: p
	<c: 'unsigned long long uefi_load_acquire(void *p)'>
	^self error: 'not simulated'
!
store: p releasing: v
	<c: 'void uefi_store_release(void *p, unsigned long long v)'>
	^self error: 'not simulated'
!
compare: p and: old swap: new
	<c: 'bool uefi_cas(void *p, unsigned long long old, unsigned long long new_)'>
	^self error: 'not simulated'
!
fetch: p add: v
	<c: 'unsigned long long uefi_fetch_add(void *p, unsigned long long v)'>
	^self error: 'not simulated'
!
swap: p with: v
	<c: 'unsigned long long uefi_swap(void *p, unsigned long long v)'>
	^self error: 'not simulated'
! !

VMStruct subclass: #MpShared
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

MpShared comment: 'What the CPUs share (UefiMp), in one cache line: the parallel job''s word (seq << 40 | count << 20 | next part), its parts done, function and context; the JIT helper''s wake counter, lock, thread function and CPU.'!

!MpShared class methodsFor: 'declaring'!
fields
	^#((job uint64_t) (done uint64_t) (jitWake uint64_t) (fn 'void (*)(void *, int64_t)') (ctx 'void *')
		(jitLock uint64_t) (jitFn uint64_t) (jitAp int64_t))
! !

VMStruct subclass: #MpAp
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

MpAp comment: 'An application processor (UefiMp): first the words UefiArm64Cpu''s entry stub reads with the MMU off (the exception level, MAIR, TCR, TTBR0, SCTLR, VBAR, HCR, CPACR or CPTR, the stack, the entry, TTBR1), then its index, MPIDR, whether it is online, its thread-local block and its number for the MP services.'!

!MpAp class methodsFor: 'declaring'!
fields
	^#((el uint64_t) (mair uint64_t) (tcr uint64_t) (ttbr0 uint64_t) (sctlr uint64_t) (vbar uint64_t) (hcr uint64_t) (cpacr uint64_t)
		(stackTop uint64_t) (entry 'void *') (ttbr1 uint64_t) (cpuIndex int64_t) (mpidr uint64_t) (online uint64_t) (tls 'uint8_t *') (procNumber uint64_t))
! !

VMStruct subclass: #EfiMpServices
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiMpServices comment: 'EFI_MP_SERVICES_PROTOCOL (UEFI PI 1.8, volume 2, 13.4).'!

!EfiMpServices class methodsFor: 'declaring'!
fields
	^#((getNumberOfProcessors 'void *') (getProcessorInfo 'void *') (startupAllAps 'void *') (startupThisAp 'void *')
		(switchBsp 'void *') (enableDisableAp 'void *') (whoAmI 'void *'))
! !
