UefiModule subclass: #UefiPosix
	instanceVariableNames: 'ticksPerUs bootEpochUs sleepEvent cpu'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiPosix comment: 'The POSIX functions the core calls (Posix), on UEFI. Memory is identity-mapped: mmap allocates zeroed pages (a reservation is real memory, so --max-heap bounds what the VM takes), MAP_FIXED zeroes the range. Time is the CPU''s cycle counter, calibrated against the firmware''s Stall at start; the wall clock is the firmware''s at start plus that. usleep waits for a timer event (the firmware halts the CPU meanwhile). There are no threads (the ticker is UefiTicker''s timer events; the other CPUs are UefiMp''s, outside POSIX) and no processes.'!

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
!
ticksPerUs
	"The cycle counter's ticks a microsecond (UefiMp's waits)."
	^ticksPerUs
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

!UefiCpu methodsFor: 'more than one cpu'!
call: fn with: arg onStack: top
	"Call fn(arg) with the stack pointer at top (16-byte aligned); answer what it answers."
	self subclassResponsibility
!
setThreadBlock: block size: n
	"This CPU's _Thread_local variables are in block (n bytes, 64-byte aligned, zeroed; they take at most half): its thread pointer (TPIDR_EL0; FS base)."
	self subclassResponsibility
!
waitWord: p old: v
	"Wait a little if the word at p is v: until something stores to its cache line or wake runs (arm64: WFE on the exclusive monitor, WFET for at most 1 ms; x86-64: MONITOR/MWAIT where the CPU has it, else pauses); answer the word."
	self subclassResponsibility
!
sleepOn: p old: v until: deadline
	"An application processor's longer wait, if the word at p is v: asleep (for a hypervisor too) until wake or the cycle counter's deadline. arm64 with FEAT_WFxT: at EL2 WFET (SEV and stores to the line wake it), at EL1 WFIT (a hypervisor's vCPU sleeps; nothing wakes it before the deadline); without it WFE. x86-64: HLT with an IDT of its own and its local APIC's timer for the deadline, woken by wake's IPI (else pauses)."
	self subclassResponsibility
!
wake
	"Wake the CPUs in waitWord:old: or sleepOn:old:until: (arm64: SEV; x86-64: an IPI to those asleep)."
	self subclassResponsibility
!
mpidr
	"arm64: this CPU's MPIDR_EL1 affinity fields; 0 elsewhere."
	self subclassResponsibility
!
apContext: ctx
	"arm64: what an application processor PSCI starts needs to run like this one (MpAp: the exception level, its MMU's registers and those that enable the FPU); nothing elsewhere."
	self subclassResponsibility
!
cleanToPoc: p size: n
	"arm64: [p, p + n) cleaned and invalidated to the point of coherency, for a CPU that reads it with its MMU off; nothing elsewhere."
	self subclassResponsibility
!
apEntry
	"arm64: the address PSCI CPU_ON starts an application processor at (its context id: an MpAp); NULL elsewhere."
	self subclassResponsibility
!
psci: fn with: a with: b with: c hvc: hvc
	"arm64: a PSCI call (SMC Calling Convention) by HVC or SMC; -1 (NOT_SUPPORTED) elsewhere."
	self subclassResponsibility
! !

UefiCpu subclass: #UefiX64Cpu
	instanceVariableNames: 'instructions'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiX64Cpu comment: 'x86-64: the time-stamp counter; the instruction cache follows stores by itself. An application processor sleeps with HLT (sleepOn:old:until:): its own IDT, whose interrupt gates only end the interrupt (EOI), and its local APIC''s one-shot timer for the deadline; wake sends those asleep an IPI.'!

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
	"pushq %rbp\n\tmovq %rsp, %rbp\n\tmovq %rsi, %rsp\n\tcallq *%rdi\n\tmovq %rbp, %rsp\n\tpopq %rbp\n\tretq\n");
__UINT64_TYPE__ uefi_call_on_stack_with(void *fn, void *arg, void *top);
__asm__(".text\n\t.p2align 4\n\t.globl uefi_call_on_stack_with\nuefi_call_on_stack_with:\n\t"
	"pushq %rbp\n\tmovq %rsp, %rbp\n\tmovq %rdx, %rsp\n\tmovq %rdi, %rax\n\tmovq %rsi, %rdi\n\tcallq *%rax\n\tmovq %rbp, %rsp\n\tpopq %rbp\n\tretq\n");
static int uefi_mwait_ok = -1;
static inline void uefi_set_thread_block(void *block, unsigned long long n)
{
	unsigned long long tp = (unsigned long long)block + n - 64;
	*(unsigned long long *)tp = tp;
	__asm__ volatile("wrmsr" : : "c"(0xC0000100u), "a"((unsigned)tp), "d"((unsigned)(tp >> 32)) : "memory");
}
static inline unsigned long long uefi_wait_word(void *p, unsigned long long old)
{
	volatile unsigned long long *w = (volatile unsigned long long *)p;
	if (uefi_mwait_ok < 0) {
		unsigned a, b, c, d;
		__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1), "c"(0));
		uefi_mwait_ok = (c >> 3) & 1;
	}
	if (uefi_mwait_ok) {
		__asm__ volatile("monitor" : : "a"(p), "c"(0), "d"(0) : "memory");
		if (*w == old) __asm__ volatile("mwait" : : "a"(0), "c"(0) : "memory");
	} else {
		for (int i = 0; i < 64 && *w == old; i++) __builtin_ia32_pause();
	}
	return *w;
}
/* Sleeping (an application processor): HLT with interrupts on, an IDT of its own (the firmware''s exception gates, every
   interrupt an EOI), its local APIC''s one-shot timer as the deadline; uefi_x64_wake sends the CPUs asleep an IPI. */
#define UEFI_X64_VECTOR 0xE1
unsigned long long uefi_x64_eoi;
void uefi_x64_irq(void);
__asm__(".text\n\t.p2align 4\n\t.globl uefi_x64_irq\nuefi_x64_irq:\n\t"
	"pushq %rax\n\tpushq %rcx\n\tpushq %rdx\n\tmovq uefi_x64_eoi(%rip), %rax\n\ttestq %rax, %rax\n\tjz 1f\n\tmovl $0, (%rax)\n\tjmp 2f\n"
	"1:\n\tmovl $0x80b, %ecx\n\txorl %eax, %eax\n\txorl %edx, %edx\n\twrmsr\n"
	"2:\n\tpopq %rdx\n\tpopq %rcx\n\tpopq %rax\n\tiretq\n");
static unsigned long long uefi_x64_idt[512] __attribute__((aligned(16)));
static int uefi_x64_idt_state;
static unsigned long long uefi_x64_apic;
static unsigned uefi_x64_apic_ids[64];
static unsigned long long uefi_x64_sleepers;
static int uefi_x64_slots;
static _Thread_local int uefi_x64_me;
static _Thread_local unsigned long long uefi_x64_timer_per_1k;
static inline unsigned long long uefi_rdmsr(unsigned m)
{
	unsigned a, d;
	__asm__ volatile("rdmsr" : "=a"(a), "=d"(d) : "c"(m));
	return ((unsigned long long)d << 32) | a;
}
static inline void uefi_wrmsr(unsigned m, unsigned long long v)
{
	__asm__ volatile("wrmsr" : : "c"(m), "a"((unsigned)v), "d"((unsigned)(v >> 32)) : "memory");
}
static inline unsigned uefi_apic_get(unsigned r)
{
	return uefi_x64_apic ? *(volatile unsigned *)(uefi_x64_apic + r) : (unsigned)uefi_rdmsr(0x800 + (r >> 4));
}
static inline void uefi_apic_put(unsigned r, unsigned v)
{
	if (uefi_x64_apic) *(volatile unsigned *)(uefi_x64_apic + r) = v;
	else uefi_wrmsr(0x800 + (r >> 4), v);
}
/* This CPU''s slot + 1 among the sleepers, -1 if it cannot sleep so (the boot CPU, no local APIC, no timer). */
static int uefi_x64_sleep_setup(void)
{
	unsigned long long b = uefi_rdmsr(0x1B), t0, h, n, idtBase;
	unsigned char d[10];
	unsigned short cs;
	int s, i, none = 0;
	struct __attribute__((packed)) { unsigned short limit; unsigned long long base; } r;
	if ((b & (1ull << 8)) || !!(b & (1ull << 11))) return -1;
	if (b & (1ull << 10)) { uefi_x64_apic = 0; uefi_x64_eoi = 0; }
	else { uefi_x64_apic = b & 0xFFFFFF000ull; uefi_x64_eoi = uefi_x64_apic + 0xB0; }
	s = __atomic_fetch_add(&uefi_x64_slots, 1, __ATOMIC_SEQ_CST);
	if (s >= 64) return -1;
	uefi_x64_apic_ids[s] = uefi_x64_apic ? uefi_apic_get(0x20) >> 24 : uefi_apic_get(0x20);
	if (__atomic_compare_exchange_n(&uefi_x64_idt_state, &none, 1, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
		__asm__ volatile("sidt %0" : "=m"(d));
		__builtin_memcpy(&idtBase, d + 2, 8);
		for (i = 0; i < 64 && (unsigned)(i * 8 + 7) <= (unsigned)(d[0] | (d[1] << 8)); i++) uefi_x64_idt[i] = ((volatile unsigned long long *)idtBase)[i];
		__asm__ volatile("mov %%cs, %0" : "=r"(cs));
		h = (unsigned long long)uefi_x64_irq;
		for (i = 32; i < 256; i++) {
			uefi_x64_idt[2 * i] = (h & 0xFFFF) | ((unsigned long long)cs << 16) | (0x8Eull << 40) | (((h >> 16) & 0xFFFF) << 48);
			uefi_x64_idt[2 * i + 1] = h >> 32;
		}
		__atomic_store_n(&uefi_x64_idt_state, 2, __ATOMIC_RELEASE);
	}
	while (__atomic_load_n(&uefi_x64_idt_state, __ATOMIC_ACQUIRE) !!= 2) __builtin_ia32_pause();
	r.limit = 4095;
	r.base = (unsigned long long)uefi_x64_idt;
	__asm__ volatile("lidt %0" : : "m"(r) : "memory");
	uefi_apic_put(0xF0, uefi_apic_get(0xF0) | 0x100);
	uefi_apic_put(0x3E0, 0xB);
	uefi_apic_put(0x320, (1u << 16) | UEFI_X64_VECTOR);
	uefi_apic_put(0x380, 0xFFFFFFFFu);
	t0 = __builtin_ia32_rdtsc();
	while (__builtin_ia32_rdtsc() - t0 < (1ull << 20)) __builtin_ia32_pause();
	n = 0xFFFFFFFFu - uefi_apic_get(0x390);
	uefi_apic_put(0x380, 0);
	uefi_x64_timer_per_1k = n >> 10;
	if (uefi_x64_timer_per_1k == 0) return -1;
	uefi_apic_put(0x320, UEFI_X64_VECTOR);
	return s + 1;
}
static inline void uefi_sleep_until(void *p, unsigned long long old, unsigned long long deadline)
{
	volatile unsigned long long *w = (volatile unsigned long long *)p;
	unsigned long long now, bit, n;
	if (*w !!= old) return;
	if (uefi_x64_me == 0) uefi_x64_me = uefi_x64_sleep_setup();
	now = __builtin_ia32_rdtsc();
	if (deadline <= now) return;
	if (uefi_x64_me < 0) {
		for (int i = 0; i < 2000 && *w == old; i++) __builtin_ia32_pause();
		return;
	}
	bit = 1ull << (uefi_x64_me - 1);
	__atomic_fetch_or(&uefi_x64_sleepers, bit, __ATOMIC_SEQ_CST);
	if (*w == old) {
		n = ((deadline - now) >> 10) * uefi_x64_timer_per_1k;
		if (n > 0xFFFFFFFFu) n = 0xFFFFFFFFu;
		if (n == 0) n = 1;
		uefi_apic_put(0x380, (unsigned)n);
		__asm__ volatile("sti\n\thlt\n\tcli" : : : "memory");
		uefi_apic_put(0x380, 0);
	}
	__atomic_fetch_and(&uefi_x64_sleepers, ~bit, __ATOMIC_SEQ_CST);
}
static inline void uefi_x64_wake(void)
{
	unsigned long long m;
	__atomic_thread_fence(__ATOMIC_SEQ_CST);
	m = __atomic_load_n(&uefi_x64_sleepers, __ATOMIC_SEQ_CST);
	while (m) {
		unsigned id = uefi_x64_apic_ids[__builtin_ctzll(m)];
		m &= m - 1;
		if (uefi_x64_apic) {
			while (uefi_apic_get(0x300) & (1u << 12)) __builtin_ia32_pause();
			uefi_apic_put(0x310, id << 24);
			uefi_apic_put(0x300, 0x4000 | UEFI_X64_VECTOR);
		} else
			uefi_wrmsr(0x830, ((unsigned long long)id << 32) | 0x4000 | UEFI_X64_VECTOR);
	}
}'
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

!UefiX64Cpu methodsFor: 'more than one cpu'!
call: fn with: arg onStack: top
	<function>
	<var: #fn type: 'void *'>
	<var: #arg type: 'void *'>
	<var: #top type: 'void *'>
	<returns: 'uint64_t'>
	^instructions call: fn with: arg onStack: top
!
setThreadBlock: block size: n
	<function>
	<var: #block type: 'void *'>
	<var: #n type: 'uint64_t'>
	instructions setThreadBlock: block size: n
!
waitWord: p old: v
	<function>
	<var: #p type: 'void *'>
	<var: #v type: 'uint64_t'>
	<returns: 'uint64_t'>
	^instructions waitWord: p old: v
!
sleepOn: p old: v until: deadline
	<function>
	<var: #p type: 'void *'>
	<var: #v type: 'uint64_t'>
	<var: #deadline type: 'uint64_t'>
	instructions sleepOn: p old: v until: deadline
!
wake
	<function>
	instructions wake
!
mpidr
	^0
!
apContext: ctx
!
cleanToPoc: p size: n
!
apEntry
	^self null
!
psci: fn with: a with: b with: c hvc: hvc
	^-1
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
	"sub sp, sp, #16\n\tstp x29, x30, [sp]\n\tmov x29, sp\n\tmov sp, x1\n\tblr x0\n\tmov sp, x29\n\tldp x29, x30, [sp]\n\tadd sp, sp, #16\n\tret\n");
__UINT64_TYPE__ uefi_call_on_stack_with(void *fn, void *arg, void *top);
__asm__(".text\n\t.p2align 2\n\t.globl uefi_call_on_stack_with\nuefi_call_on_stack_with:\n\t"
	"sub sp, sp, #16\n\tstp x29, x30, [sp]\n\tmov x29, sp\n\tmov sp, x2\n\tmov x3, x0\n\tmov x0, x1\n\tblr x3\n\tmov sp, x29\n\tldp x29, x30, [sp]\n\tadd sp, sp, #16\n\tret\n");
static int uefi_wfxt = -1;
static inline int uefi_has_wfxt(void)
{
	unsigned long long r;
	if (uefi_wfxt < 0) {
		__asm__ volatile("mrs %0, S3_0_C0_C6_2" : "=r"(r));
		uefi_wfxt = (r & 15) >= 2;
	}
	return uefi_wfxt;
}
static inline unsigned long long uefi_cntfrq(void)
{
	unsigned long long f;
	__asm__ volatile("mrs %0, cntfrq_el0" : "=r"(f));
	return f;
}
static inline unsigned long long uefi_wait_word(void *p, unsigned long long old)
{
	unsigned long long v;
	__asm__ volatile("ldaxr %0, [%1]" : "=r"(v) : "r"(p) : "memory");
	if (v == old) {
		if (uefi_has_wfxt()) {
			register unsigned long long t __asm__("x9") = uefi_cntvct() + uefi_cntfrq() / 1000;
			__asm__ volatile(".inst 0xd5031009" : : "r"(t) : "memory");
		} else
			__asm__ volatile("wfe" : : : "memory");
	} else
		__asm__ volatile("clrex" : : : "memory");
	return v;
}
static int uefi_el = -1;
static inline int uefi_at_el2(void)
{
	unsigned long long el;
	if (uefi_el < 0) {
		__asm__ volatile("mrs %0, CurrentEL" : "=r"(el));
		uefi_el = (int)((el >> 2) & 3);
	}
	return uefi_el == 2;
}
/* At EL2 the CPU is ours: WFET, which SEV and stores to the line wake. At EL1 a hypervisor runs us: its WFE trap only
   yields (the vCPU spins), so WFIT, which sleeps the vCPU to the deadline (SEV cannot wake it). */
static inline void uefi_sleep_until(void *p, unsigned long long old, unsigned long long deadline)
{
	unsigned long long v;
	__asm__ volatile("ldaxr %0, [%1]" : "=r"(v) : "r"(p) : "memory");
	if (v !!= old) {
		__asm__ volatile("clrex" : : : "memory");
		return;
	}
	if (!!uefi_has_wfxt()) {
		__asm__ volatile("wfe" : : : "memory");
		return;
	}
	register unsigned long long t __asm__("x9") = deadline;
	if (uefi_at_el2()) __asm__ volatile(".inst 0xd5031009" : : "r"(t) : "memory");
	else __asm__ volatile(".inst 0xd5031029" : : "r"(t) : "memory");
}
static inline void uefi_sev(void)
{
	__asm__ volatile("dsb ish\n\tsev" : : : "memory");
}
static inline void uefi_set_thread_block(void *block, unsigned long long n)
{
	__asm__ volatile("msr tpidr_el0, %0" : : "r"(block) : "memory");
}
static inline unsigned long long uefi_mpidr(void)
{
	unsigned long long m;
	__asm__ volatile("mrs %0, mpidr_el1" : "=r"(m));
	return m & 0xff00ffffffull;
}
#define UEFI_MRS(reg, i) __asm__ volatile("mrs %0, " #reg : "=r"(v)); c[i] = v
static void uefi_ap_context(void *ctx)
{
	unsigned long long *c = (unsigned long long *)ctx, el, v;
	__asm__ volatile("mrs %0, CurrentEL" : "=r"(el));
	el = (el >> 2) & 3;
	c[0] = el;
	if (el == 2) {
		UEFI_MRS(mair_el2, 1); UEFI_MRS(tcr_el2, 2); UEFI_MRS(ttbr0_el2, 3); UEFI_MRS(sctlr_el2, 4);
		UEFI_MRS(vbar_el2, 5); UEFI_MRS(hcr_el2, 6); UEFI_MRS(cptr_el2, 7);
		c[10] = 0;
	} else {
		UEFI_MRS(mair_el1, 1); UEFI_MRS(tcr_el1, 2); UEFI_MRS(ttbr0_el1, 3); UEFI_MRS(sctlr_el1, 4);
		UEFI_MRS(vbar_el1, 5); UEFI_MRS(cpacr_el1, 7); UEFI_MRS(ttbr1_el1, 10);
		c[6] = 0;
		c[7] |= 3ull << 20;
	}
}
static void uefi_clean_to_poc(void *p, unsigned long long n)
{
	unsigned long long ctr, line, a, end = (unsigned long long)p + n;
	__asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
	line = 4ull << ((ctr >> 16) & 15);
	for (a = (unsigned long long)p & ~(line - 1); a < end; a += line) __asm__ volatile("dc civac, %0" : : "r"(a) : "memory");
	__asm__ volatile("dsb sy" : : : "memory");
}
#define UEFI_PSCI_CLOBBERS "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17", "memory"
static unsigned long long uefi_psci(unsigned long long fn, unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long hvc)
{
	register unsigned long long x0 __asm__("x0") = fn;
	register unsigned long long x1 __asm__("x1") = a;
	register unsigned long long x2 __asm__("x2") = b;
	register unsigned long long x3 __asm__("x3") = c;
	if (hvc) __asm__ volatile("hvc #0" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3) : : UEFI_PSCI_CLOBBERS);
	else __asm__ volatile("smc #0" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3) : : UEFI_PSCI_CLOBBERS);
	return x0;
}
/* An application processor from PSCI CPU_ON, x0 its MpAp, MMU and caches off: its MMU as the boot CPU''s, the FPU on, the stack, then the MpAp''s entry (UefiMp>>apMain:). */
void uefi_ap_entry(void);
__asm__(".text\n\t.p2align 3\n\t.globl uefi_ap_entry\nuefi_ap_entry:\n\t"
	"ldr x1, [x0]\n\tcmp x1, #2\n\tb.eq 2f\n\t"
	"ldr x2, [x0, #8]\n\tmsr mair_el1, x2\n\tldr x2, [x0, #16]\n\tmsr tcr_el1, x2\n\t"
	"ldr x2, [x0, #24]\n\tmsr ttbr0_el1, x2\n\tldr x2, [x0, #80]\n\tmsr ttbr1_el1, x2\n\t"
	"ldr x2, [x0, #40]\n\tmsr vbar_el1, x2\n\tldr x2, [x0, #56]\n\tmsr cpacr_el1, x2\n\tisb\n\t"
	"tlbi vmalle1\n\tic iallu\n\tdsb nsh\n\tisb\n\tldr x2, [x0, #32]\n\tmsr sctlr_el1, x2\n\tisb\n\tb 3f\n"
	"2:\n\tldr x2, [x0, #48]\n\tmsr hcr_el2, x2\n\tisb\n\t"
	"ldr x2, [x0, #8]\n\tmsr mair_el2, x2\n\tldr x2, [x0, #16]\n\tmsr tcr_el2, x2\n\t"
	"ldr x2, [x0, #24]\n\tmsr ttbr0_el2, x2\n\tldr x2, [x0, #40]\n\tmsr vbar_el2, x2\n\t"
	"ldr x2, [x0, #56]\n\tmsr cptr_el2, x2\n\tisb\n\t"
	"tlbi alle2\n\tic iallu\n\tdsb nsh\n\tisb\n\tldr x2, [x0, #32]\n\tmsr sctlr_el2, x2\n\tisb\n"
	"3:\n\tldr x2, [x0, #64]\n\tmov sp, x2\n\tmov x29, #0\n\tmov x30, #0\n\tldr x2, [x0, #72]\n\tblr x2\n"
	"4:\n\twfe\n\tb 4b\n");
static inline void *uefi_ap_entry_address(void)
{
	return (void *)uefi_ap_entry;
}'
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

!UefiArm64Cpu methodsFor: 'more than one cpu'!
call: fn with: arg onStack: top
	<function>
	<var: #fn type: 'void *'>
	<var: #arg type: 'void *'>
	<var: #top type: 'void *'>
	<returns: 'uint64_t'>
	^instructions call: fn with: arg onStack: top
!
setThreadBlock: block size: n
	<function>
	<var: #block type: 'void *'>
	<var: #n type: 'uint64_t'>
	instructions setThreadBlock: block size: n
!
waitWord: p old: v
	<function>
	<var: #p type: 'void *'>
	<var: #v type: 'uint64_t'>
	<returns: 'uint64_t'>
	^instructions waitWord: p old: v
!
sleepOn: p old: v until: deadline
	<function>
	<var: #p type: 'void *'>
	<var: #v type: 'uint64_t'>
	<var: #deadline type: 'uint64_t'>
	instructions sleepOn: p old: v until: deadline
!
wake
	<function>
	instructions sev
!
mpidr
	<function>
	<returns: 'uint64_t'>
	^instructions mpidr
!
apContext: ctx
	<function>
	<var: #ctx type: 'void *'>
	instructions apContext: ctx
!
cleanToPoc: p size: n
	<function>
	<var: #p type: 'void *'>
	<var: #n type: 'uint64_t'>
	instructions cleanToPoc: p size: n
!
apEntry
	<function>
	<returns: 'void *'>
	^instructions apEntryAddress
!
psci: fn with: a with: b with: c hvc: hvc
	<function>
	<var: #fn type: 'uint64_t'>
	<var: #a type: 'uint64_t'>
	<var: #b type: 'uint64_t'>
	<var: #c type: 'uint64_t'>
	<var: #hvc type: 'bool'>
	<returns: 'int64_t'>
	^(instructions psci: fn with: a with: b with: c hvc: (hvc ifTrue: [1] ifFalse: [0]) asUInt64) asInt64
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
!
call: fn with: arg onStack: top
	<c: 'uint64_t uefi_call_on_stack_with(void *fn, void *arg, void *top)'>
	^self error: 'not simulated'
!
setThreadBlock: block size: n
	<c: 'void uefi_set_thread_block(void *block, unsigned long long n)'>
	^self error: 'not simulated'
!
waitWord: p old: v
	<c: 'unsigned long long uefi_wait_word(void *p, unsigned long long old)'>
	^self error: 'not simulated'
!
sleepOn: p old: v until: deadline
	<c: 'void uefi_sleep_until(void *p, unsigned long long old, unsigned long long deadline)'>
	^self error: 'not simulated'
!
wake
	<c: 'void uefi_x64_wake(void)'>
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
!
call: fn with: arg onStack: top
	<c: 'uint64_t uefi_call_on_stack_with(void *fn, void *arg, void *top)'>
	^self error: 'not simulated'
!
setThreadBlock: block size: n
	<c: 'void uefi_set_thread_block(void *block, unsigned long long n)'>
	^self error: 'not simulated'
!
waitWord: p old: v
	<c: 'unsigned long long uefi_wait_word(void *p, unsigned long long old)'>
	^self error: 'not simulated'
!
sleepOn: p old: v until: deadline
	<c: 'void uefi_sleep_until(void *p, unsigned long long old, unsigned long long deadline)'>
	^self error: 'not simulated'
!
sev
	<c: 'void uefi_sev(void)'>
	^self error: 'not simulated'
!
mpidr
	<c: 'unsigned long long uefi_mpidr(void)'>
	^self error: 'not simulated'
!
apContext: ctx
	<c: 'void uefi_ap_context(void *ctx)'>
	^self error: 'not simulated'
!
cleanToPoc: p size: n
	<c: 'void uefi_clean_to_poc(void *p, unsigned long long n)'>
	^self error: 'not simulated'
!
apEntryAddress
	<c: 'void *uefi_ap_entry_address(void)'>
	^self error: 'not simulated'
!
psci: fn with: a with: b with: c hvc: hvc
	<c: 'unsigned long long uefi_psci(unsigned long long fn, unsigned long long a, unsigned long long b, unsigned long long c, unsigned long long hvc)'>
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
	instanceVariableNames: 'libc cpu mp'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiJitPlatform comment: 'The code cache on UEFI: the zero-fill array the VM image reserves for it is already writable and executable (UefiImageWriter makes the image one read-write-execute section); the CPU makes the instruction cache current (UefiCpu). The helper thread of background compilation is an application processor (UefiMp>>startJit:), its mutex a spin lock and its condition a counter it waits on; without one (one CPU, firmware without MP services or PSCI) the VM''s thread compiles.'!

!UefiJitPlatform class methodsFor: 'declaring'!
declarations
	^#((libc LibC) (cpu UefiCpu) (mp UefiMp))
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
!
mapForPerf: path
	<export>
	<var: #path type: 'const char *'>
! !

!UefiJitPlatform methodsFor: 'helper thread'!
jitThreadsAvailable
	"An application processor runs the helper (UefiMp)."
	<export>
	^mp workerCount > 0
!
jitStartThread: fn
	<export>
	<var: #fn type: 'void *(*)(void *)'>
	^mp startJit: fn
!
jitWorkerLock
	<export>
	mp jitLock
!
jitWorkerUnlock
	<export>
	mp jitUnlock
!
jitWorkerWait
	<export>
	mp jitWait
!
jitWorkerWake
	<export>
	mp jitWake
! !
