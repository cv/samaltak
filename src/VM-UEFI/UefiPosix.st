UefiModule subclass: #UefiPosix
	instanceVariableNames: 'ticksPerUs bootEpochUs sleepEvent cpu'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiPosix comment: 'The POSIX functions the core calls (Posix), on UEFI. Memory is identity-mapped: mmap allocates zeroed pages (a reservation is real memory, so --max-heap bounds what the VM takes), MAP_FIXED zeroes the range. Time is the CPU''s cycle counter, calibrated against the firmware''s Stall at start; the wall clock is the firmware''s at start plus that. usleep waits for a timer event (the firmware halts the CPU meanwhile). There are no threads (the ticker is UefiTicker''s timer events) and no processes.'!

!UefiPosix class methodsFor: 'declaring'!
declarations
	^#((ticksPerUs uint64_t) (bootEpochUs int64_t) (sleepEvent 'void *') (cpu UefiCpu))
!
replaces
	^Posix
!
typedefs
	^#((pthread_t uintptr_t) (pthread_attr_t opaque))
!
definedExternStructs
	^{Timespec. Timeval}
! !

!UefiPosix methodsFor: 'starting'!
start
	"Calibrate the cycle counter over 20 ms of Stall; read the wall clock."
	<function>
	| t0 time days y m |
	t0 := cpu cycles.
	self efi: self boot stall with: 20000.
	ticksPerUs := (cpu cycles - t0) quo: 20000.
	ticksPerUs = 0 ifTrue: [ticksPerUs := 1].
	time := self local: 'EfiTime'.
	(self efiFailed: (self efi: self runtime getTime with: time with: self null)) ifTrue: [^self].
	"days since 1970-01-01 (the civil-from-days inverse, Howard Hinnant's days_from_civil)"
	y := time year asInt64.
	m := time month asInt64.
	m <= 2 ifTrue: [y := y - 1].
	days := self daysFromCivilYear: y month: m day: time day asInt64.
	bootEpochUs := ((((days * 86400) + (time hour asInt64 * 3600)) + (time minute asInt64 * 60)) + time second asInt64) * 1000000
!
daysFromCivilYear: y month: m day: d
	"y already one less for January and February."
	| era yoe doy doe mp |
	era := y quo: 400.
	yoe := y - (era * 400).
	mp := m > 2 ifTrue: [m - 3] ifFalse: [m + 9].
	doy := (((153 * mp) + 2) quo: 5) + d - 1.
	doe := (yoe * 365) + (yoe quo: 4) - (yoe quo: 100) + doy.
	^(era * 146097) + doe - 719468
!
nowNs
	<function>
	<returns: 'int64_t'>
	^((cpu cycles * 1000) quo: ticksPerUs) asInt64
! !

!UefiPosix methodsFor: 'memory'!
mmap: addr length: n protection: prot flags: flags file: fd offset: offset
	"Anonymous memory only: fresh zeroed pages, or zeroes over [addr, addr + n) with MAP_FIXED."
	<function>
	<var: #addr type: 'void *'>
	<var: #n type: 'size_t'>
	<var: #prot type: 'int'>
	<var: #flags type: 'int'>
	<var: #fd type: 'int'>
	<var: #offset type: 'off_t'>
	<returns: 'void *'>
	| pages |
	(flags bitAnd: self MAP_FIXED) ~= 0 ifTrue: [
		libc memset: addr value: 0 size: n.
		^addr].
	pages := self local: 'uint64_t'.
	(self efiFailed: (self efi: self boot allocatePages with: EFI_ALLOCATE_ANY_PAGES with: EFI_LOADER_DATA with: (n + 4095) >> 12 with: pages)) ifTrue: [
		^self MAP_FAILED].
	libc memset: (self cCoerce: pages value to: 'void *') value: 0 size: n.
	^self cCoerce: pages value to: 'void *'
!
munmap: addr length: n
	"Pages stay allocated."
	<function>
	<var: #addr type: 'void *'>
	<var: #n type: 'size_t'>
	<returns: 'int'>
	^0
!
madvise: addr length: n advice: advice
	"Pages stay allocated (their contents too)."
	<function>
	<var: #addr type: 'void *'>
	<var: #n type: 'size_t'>
	<var: #advice type: 'int'>
	<returns: 'int'>
	^0
!
MADV_DONTNEED
	^4
!
PROT_READ
	^1
!
PROT_WRITE
	^2
!
PROT_EXEC
	^4
!
MAP_PRIVATE
	^2
!
MAP_ANON
	^16r20
!
MAP_FIXED
	^16r10
!
MAP_NORESERVE
	^16r4000
!
MAP_FAILED
	^self cCoerce: -1 to: 'void *'
! !

!UefiPosix methodsFor: 'time'!
clockGettime: clock into: ts
	"Both clocks are the cycle counter: the VM is all there runs."
	<function>
	<var: #clock type: 'int'>
	<var: #ts type: 'Timespec *'>
	<returns: 'int'>
	| ns |
	ns := self nowNs.
	ts tv_sec: (ns quo: 1000000000).
	ts tv_nsec: (ns rem: 1000000000).
	^0
!
CLOCK_MONOTONIC
	^1
!
CLOCK_THREAD_CPUTIME_ID
	^3
!
gettimeofday: tv zone: tz
	<function>
	<var: #tv type: 'Timeval *'>
	<var: #tz type: 'void *'>
	<returns: 'int'>
	| us |
	us := bootEpochUs + (self nowNs quo: 1000).
	tv tv_sec: (us quo: 1000000).
	tv tv_usec: (us rem: 1000000) asInt32.
	^0
!
usleep: us
	"Wait for a relative timer event (in 100 ns units)."
	<function>
	<var: #us type: 'uint32_t'>
	<returns: 'int'>
	| index event |
	sleepEvent isNull ifTrue: [
		event := self local: 'void *'.
		(self efiFailed: (self efi: self boot createEvent with: EFI_EVT_TIMER with: 0 with: self null with: self null with: event)) ifTrue: [
			self efi: self boot stall with: us.
			^0].
		sleepEvent := event value].
	self efi: self boot setTimer with: sleepEvent with: EFI_TIMER_RELATIVE with: (us asUInt64 * 10) + 1.
	index := self local: 'uint64_t'.
	event := self local: 'void *'.
	event value: sleepEvent.
	self efi: self boot waitForEvent with: 1 with: event with: index.
	^0
! !

!UefiPosix methodsFor: 'threads and processes'!
pthreadCreate: thread attributes: attr start: fn argument: arg
	"No threads."
	<function>
	<var: #thread type: 'pthread_t *'>
	<var: #attr type: 'const pthread_attr_t *'>
	<var: #fn type: 'void *(*)(void *)'>
	<var: #arg type: 'void *'>
	<returns: 'int'>
	^1
!
pthreadDetach: thread
	<function>
	<var: #thread type: 'pthread_t'>
	<returns: 'int'>
	^0
!
getpid
	<function>
	<returns: 'pid_t'>
	^1
!
realpath: path into: resolved
	"Paths are relative to the boot volume's root; a copy of path."
	<function>
	<var: #path type: 'const char *'>
	<var: #resolved type: 'char *'>
	<returns: 'char *'>
	^libc strdup: path
! !

VMModule subclass: #UefiCpu
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiCpu comment: 'What differs between the CPUs under UEFI, where no C library has it: the cycle counter (UefiPosix''s clock), a memory barrier (device rings), making the instruction cache current after the JIT wrote code (UefiJitPlatform), running on a stack of the VM''s own (UefiFirmware: the firmware''s is 128 KB). UefiX64Cpu and UefiArm64Cpu implement it, with what C has no builtin for in their C preambles.'!

!UefiCpu class methodsFor: 'declaring'!
isAbstractModule
	^self == UefiCpu
!
isArchInterface
	^self == UefiCpu
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiCpu methodsFor: 'cpu'!
cycles
	"A counter that ticks at a constant rate."
	self subclassResponsibility
!
invalidate: start size: size
	"Code changed in [start, start + size)."
	self subclassResponsibility
!
call: fn onStack: top
	"The result of fn (a function of no arguments answering a uint64_t), called with the stack pointer at top (16-byte aligned)."
	self subclassResponsibility
! !

UefiCpu subclass: #UefiX64Cpu
	instanceVariableNames: 'instructions'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiX64Cpu comment: 'x86-64: the time-stamp counter; the instruction cache follows stores by itself.'!

!UefiX64Cpu class methodsFor: 'declaring'!
declarations
	^#((instructions UefiX64Instructions))
!
targetArch
	^#x86_64
!
cPreamble
	^'__UINT64_TYPE__ uefi_call_on_stack(void *fn, void *top);
__asm__(".text\n\t.p2align 4\n\t.globl uefi_call_on_stack\nuefi_call_on_stack:\n\t"
	"pushq %rbp\n\tmovq %rsp, %rbp\n\tmovq %rsi, %rsp\n\tcallq *%rdi\n\tmovq %rbp, %rsp\n\tpopq %rbp\n\tretq\n");'
! !

!UefiX64Cpu methodsFor: 'cpu'!
cycles
	^instructions rdtsc
!
invalidate: start size: size
!
call: fn onStack: top
	<function>
	<var: #fn type: 'void *'>
	<var: #top type: 'void *'>
	<returns: 'uint64_t'>
	^instructions call: fn onStack: top
! !

UefiCpu subclass: #UefiArm64Cpu
	instanceVariableNames: 'instructions'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiArm64Cpu comment: 'AArch64: the virtual counter (cntvct_el0); over changed code the data cache cleaned to the point of unification, then the instruction cache invalidated.'!

!UefiArm64Cpu class methodsFor: 'declaring'!
declarations
	^#((instructions UefiArm64Instructions))
!
targetArch
	^#arm64
!
cPreamble
	^'static inline unsigned long long uefi_cntvct(void)
{
	unsigned long long t;
	__asm__ volatile("isb\n\tmrs %0, cntvct_el0" : "=r"(t) : : "memory");
	return t;
}
static inline void uefi_sync_icache(void *start, unsigned long long size)
{
	unsigned long long ctr, dline, iline, a, end = (unsigned long long)start + size;
	__asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
	dline = 4ull << ((ctr >> 16) & 15);
	iline = 4ull << (ctr & 15);
	for (a = (unsigned long long)start & ~(dline - 1); a < end; a += dline) __asm__ volatile("dc cvau, %0" : : "r"(a) : "memory");
	__asm__ volatile("dsb ish" : : : "memory");
	for (a = (unsigned long long)start & ~(iline - 1); a < end; a += iline) __asm__ volatile("ic ivau, %0" : : "r"(a) : "memory");
	__asm__ volatile("dsb ish\n\tisb" : : : "memory");
}
__UINT64_TYPE__ uefi_call_on_stack(void *fn, void *top);
__asm__(".text\n\t.p2align 2\n\t.globl uefi_call_on_stack\nuefi_call_on_stack:\n\t"
	"sub sp, sp, #16\n\tstp x29, x30, [sp]\n\tmov x29, sp\n\tmov sp, x1\n\tblr x0\n\tmov sp, x29\n\tldp x29, x30, [sp]\n\tadd sp, sp, #16\n\tret\n");'
! !

!UefiArm64Cpu methodsFor: 'cpu'!
cycles
	<function>
	<returns: 'uint64_t'>
	^instructions cntvct
!
invalidate: start size: size
	<function>
	<var: #start type: 'void *'>
	<var: #size type: 'uint64_t'>
	instructions syncIcache: start size: size
!
call: fn onStack: top
	<function>
	<var: #fn type: 'void *'>
	<var: #top type: 'void *'>
	<returns: 'uint64_t'>
	^instructions call: fn onStack: top
! !

CLibrary subclass: #UefiX64Instructions
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiX64Instructions comment: 'The time-stamp counter (the compiler''s builtin) and UefiX64Cpu''s C preamble.'!

!UefiX64Instructions class methodsFor: 'declaring'!
targetOS
	^#uefi
! !

!UefiX64Instructions methodsFor: 'functions'!
rdtsc
	<c: 'unsigned long long __builtin_ia32_rdtsc(void)'>
	^self error: 'not simulated'
!
call: fn onStack: top
	<c: 'uint64_t uefi_call_on_stack(void *fn, void *top)'>
	^self error: 'not simulated'
! !

CLibrary subclass: #UefiArm64Instructions
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiArm64Instructions comment: 'UefiArm64Cpu''s C preamble.'!

!UefiArm64Instructions class methodsFor: 'declaring'!
targetOS
	^#uefi
! !

!UefiArm64Instructions methodsFor: 'functions'!
cntvct
	<c: 'unsigned long long uefi_cntvct(void)'>
	^self error: 'not simulated'
!
syncIcache: start size: size
	<c: 'void uefi_sync_icache(void *start, unsigned long long size)'>
	^self error: 'not simulated'
!
call: fn onStack: top
	<c: 'uint64_t uefi_call_on_stack(void *fn, void *top)'>
	^self error: 'not simulated'
! !

Ticker subclass: #UefiTicker
	instanceVariableNames: 'firmware events'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiTicker comment: 'The Scheduler''s timers on UEFI: a timer event per ident whose notification (run by the firmware''s timer interrupt, at TPL_CALLBACK) calls tickFired:, which only stores atomics. The firmware''s timer ticks every 10 ms on OVMF: shorter intervals round up to it.'!

!UefiTicker class methodsFor: 'declaring'!
declarations
	^#((firmware UefiFirmware) (events 'void *[4]'))
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiTicker methodsFor: 'timers'!
start
	<export>
!
arm: ident microseconds: us periodic: periodic
	<export>
	(ident < 1 or: [ident > 3]) ifTrue: [self fatal: 'no ticker timer %d' with: ident].
	(events at: ident) isNull ifTrue: [
		us < 0 ifTrue: [^self].
		events at: ident put: (firmware timerNotifying: (self cCoerce: (self functionPointer: #notify:context:) to: 'void *') context: (self cCoerce: ident asInt64 to: 'void *')).
		(events at: ident) isNull ifTrue: [self fatal: 'cannot create the ticker''s event %d' with: ident]].
	firmware setTimer: (events at: ident) microseconds: us periodic: periodic
!
notify: event context: ident
	"The firmware's notification of timer ident (its context)."
	<function>
	<abi: 'ms_abi'>
	<var: #event type: 'void *'>
	<var: #ident type: 'void *'>
	scheduler tickFired: (self cCoerce: ident to: 'int64_t') asInt32
!
threadCycles
	<export>
	<returns: 'int64_t'>
	^-1
! !

JitPlatform subclass: #UefiJitPlatform
	instanceVariableNames: 'libc cpu'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiJitPlatform comment: 'The code cache on UEFI: the zero-fill array the VM image reserves for it is already writable and executable (UefiImageWriter makes the image one read-write-execute section); the CPU makes the instruction cache current (UefiCpu).'!

!UefiJitPlatform class methodsFor: 'declaring'!
declarations
	^#((libc LibC) (cpu UefiCpu))
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiJitPlatform methodsFor: 'region'!
canRunCode
	<export>
	^true
!
map: near size: size
	<export>
	libc memset: near value: 0 size: size.
	^near
!
beginWriting
	<export>
!
endWriting
	<export>
!
invalidate: start size: size
	<export>
	cpu invalidate: start size: size
! !
