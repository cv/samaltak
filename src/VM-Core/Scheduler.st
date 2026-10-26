VMCoreModule subclass: #Scheduler
	instanceVariableNames: 'interruptPending lastPreempted allocSampleClass allocSampleSize allocSampleInterval allocSampleCountdown allocSampleSema statProcessSwitches allocSamplePending inIdle preemptToFront allocSampleUnread samplerTickUnread timerMs samplerIntervalUs samplerNextUs lastSwitchUs startUs samplerSema pendingExt pendingExtN pendingExtCap tickIdle tickPollUs tickArmedPoll tickArmedDeadline tickDeadlineFired tickKq'
	classVariableNames: 'TICK_DEADLINE TICK_POLL'
	package: 'VM-Core'!

Scheduler comment: 'Process scheduler, semaphores and interrupts: the timer, the CPU and allocation samplers, external semaphore signals.

While Smalltalk runs, a kqueue timer serviced by the ticker thread requests an interrupt check when the timer or the CPU sampler is due, and a periodic one every tickPollUs if the platform asked for polls (requestPeriodicPoll:). While the VM waits in the platform''s wait both are disarmed: the wait''s timeout covers the timer and the sampler, and the platform wakes it for events. tickUpdate (VM thread) re-arms after any change.'!

!Scheduler class methodsFor: 'declaring'!
declarations
	^#((interruptPending atomic_int) (lastPreempted oop) (allocSampleClass oop) (allocSampleSize int64_t)
		(allocSampleInterval int64_t) (allocSampleCountdown int64_t) (allocSampleSema int32_t) (statProcessSwitches uint64_t)
		(allocSamplePending bool) (inIdle bool) (preemptToFront bool) (allocSampleUnread bool) (samplerTickUnread bool)
		(timerMs int64_t -1) (samplerIntervalUs int64_t) (samplerNextUs int64_t) (lastSwitchUs int64_t) (startUs int64_t)
		(samplerSema int32_t) (pendingExt 'int32_t *') (pendingExtN int32_t) (pendingExtCap int32_t)
		(tickIdle bool) (tickPollUs int64_t) (tickArmedPoll int64_t) (tickArmedDeadline int64_t 16r7FFFFFFFFFFFFFFF)
		(tickDeadlineFired atomic_bool) (tickKq int32_t -1))
!
initialize
	TICK_DEADLINE := 1.
	TICK_POLL := 2
! !

!Scheduler methodsFor: 'accessing'!
interruptPendingRelaxed
	^self atomicLoad: #interruptPending
!
lastPreempted
	^lastPreempted
!
lastPreempted: o
	lastPreempted := o
!
allocSampleClass
	^allocSampleClass
!
allocSampleClass: o
	allocSampleClass := o
!
allocSampleSize
	^allocSampleSize
!
allocSampleInterval
	^allocSampleInterval
!
allocSampleInterval: n
	allocSampleInterval := n
!
allocSampleCountdown
	^allocSampleCountdown
!
allocSampleCountdown: n
	allocSampleCountdown := n
!
allocSampleSema: n
	allocSampleSema := n
!
allocSampleUnread
	^allocSampleUnread
!
allocSampleUnread: aBoolean
	allocSampleUnread := aBoolean
!
samplerTickUnread
	^samplerTickUnread
!
samplerTickUnread: aBoolean
	samplerTickUnread := aBoolean
!
statProcessSwitches
	^statProcessSwitches
! !

!Scheduler methodsFor: 'time'!
rawNowUs
	<c: 'int64_t raw_now_us(void)'>
	| ts |
	ts := self local: 'Timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
!
nowUs
	<c: 'int64_t now_us(void)'>
	^self rawNowUs - startUs
!
nowMs
	<c: 'int64_t now_ms(void)'>
	^self nowUs quo: 1000
!
threadCpuUs
	"The VM thread's CPU time, which Processes are charged: wall time would charge the running one while the OS runs other threads."
	<c: 'int64_t thread_cpu_us(void)'>
	| ts |
	ts := self local: 'Timespec'.
	posix clockGettime: posix CLOCK_THREAD_CPUTIME_ID into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
! !

!Scheduler methodsFor: 'interrupts'!
requestInterruptCheck
	"Any thread."
	<c: 'void request_interrupt_check(void)'>
	self atomicStore: #interruptPending value: 1.
	jit requestInterrupt
!
signalExternalSemaphore: index
	"1-based index into externalObjects; VM thread only, queued."
	<c: 'void signal_external_semaphore(int index)'>
	<export>
	pendingExtN = pendingExtCap ifTrue: [
		pendingExtCap := pendingExtCap = 0 ifTrue: [64] ifFalse: [pendingExtCap * 2].
		pendingExt := self cCoerce: (libc realloc: pendingExt size: 4 * pendingExtCap asUInt64) to: 'int32_t *'.
		pendingExt isNull ifTrue: [self fatal: 'out of memory queueing external semaphore signals']].
	pendingExt at: pendingExtN put: index.
	pendingExtN := pendingExtN + 1.
	self requestInterruptCheck
! !

!Scheduler methodsFor: 'ticker'!
tickArm: ident microseconds: us periodic: periodic
	"us < 0 disarms (an already fired one-shot is gone: ENOENT, ignored)."
	<c: 'void tick_arm(int ident, int64_t us, bool periodic)'>
	| ch res zero |
	ch := self local: 'KEvent'.
	res := self local: 'KEvent'.
	zero := self local: 'Timespec'.
	ch ident: ident asUInt64.
	ch filter: posix EVFILT_TIMER.
	us < 0
		ifTrue: [ch flags: (posix EV_DELETE bitOr: posix EV_RECEIPT)]
		ifFalse: [
			ch flags: ((posix EV_ADD bitOr: posix EV_RECEIPT) bitOr: (periodic ifTrue: [0] ifFalse: [posix EV_ONESHOT])).
			ch fflags: posix NOTE_USECONDS.
			ch data: us].
	posix kevent: tickKq changes: ch count: 1 events: res count: 1 timeout: zero
!
ticker: arg
	"The ticker thread: request an interrupt check whenever a timer fires."
	<c: 'void *ticker(void *arg)'>
	| ev |
	ev := self local: 'KEvent'.
	[(posix kevent: tickKq changes: self null count: 0 events: ev count: 1 timeout: self null) > 0 ifTrue: [
		ev ident = TICK_DEADLINE ifTrue: [self atomicStore: #tickDeadlineFired value: true].
		self requestInterruptCheck]] repeat
!
tickerStart
	<c: 'void ticker_start(void)'>
	| t |
	tickKq := posix kqueue.
	tickKq < 0 ifTrue: [self fatal: 'cannot create the ticker''s kqueue'].
	t := self local: 'pthread_t'.
	(posix pthreadCreate: t attributes: self null start: (self functionPointer: #ticker:) argument: self null) ~= 0 ifTrue: [
		self fatal: 'cannot start the ticker thread'].
	posix pthreadDetach: t value
!
tickUpdate
	"A pending one-shot is not armed twice; one that fired before its deadline (clock skew) is armed again."
	<c: 'void tick_update(void)'>
	| due poll now |
	due := 16r7FFFFFFFFFFFFFFF.
	poll := tickIdle ifTrue: [0] ifFalse: [tickPollUs].
	now := self nowUs.
	tickIdle ifFalse: [
		(timerMs >= 0 and: [timerMs < (16r7FFFFFFFFFFFFFFF quo: 1000)]) ifTrue: [due := timerMs * 1000].
		(samplerIntervalUs > 0 and: [samplerNextUs < due]) ifTrue: [due := samplerNextUs]].
	((self atomicExchange: #tickDeadlineFired value: false) or: [due ~= tickArmedDeadline]) ifTrue: [
		due <= now ifTrue: [self requestInterruptCheck].
		self tickArm: TICK_DEADLINE microseconds: ((due = 16r7FFFFFFFFFFFFFFF or: [due <= now]) ifTrue: [-1] ifFalse: [due - now]) periodic: false.
		tickArmedDeadline := due].
	poll ~= tickArmedPoll ifTrue: [
		self tickArm: TICK_POLL microseconds: (poll ~= 0 ifTrue: [poll] ifFalse: [-1]) periodic: true.
		tickArmedPoll := poll]
!
tickSetIdle: aBoolean
	<c: 'void tick_set_idle(bool idle)'>
	tickIdle := aBoolean.
	self tickUpdate
!
requestPeriodicPoll: intervalUs
	"While Smalltalk runs, check interrupts (and so poll the platform) at least every intervalUs; 0 = only on request."
	<c: 'void request_periodic_poll(int64_t interval_us)'>
	<export>
	tickPollUs := intervalUs > 0 ifTrue: [intervalUs] ifFalse: [0].
	self tickUpdate
!
init
	<c: 'void sched_init(void)'>
	startUs := self rawNowUs.
	lastPreempted := memory nilOop.
	allocSampleClass := memory nilOop.
	lastSwitchUs := self threadCpuUs.
	self tickerStart
! !

!Scheduler methodsFor: 'linked lists'!
addLastLink: link to: list
	<c: 'void add_last_link(oop list, oop link)'>
	self storeRef: link at: PROC_NEXT put: memory nilOop.
	(self loadRef: list at: LL_FIRST) = memory nilOop
		ifTrue: [self storeRef: list at: LL_FIRST put: link]
		ifFalse: [self storeRef: (self loadRef: list at: LL_LAST) at: PROC_NEXT put: link].
	self storeRef: list at: LL_LAST put: link.
	self storeRef: link at: PROC_MYLIST put: list
!
removeFirstLink: list
	<c: 'oop remove_first_link(oop list)'>
	| first next |
	first := self loadRef: list at: LL_FIRST.
	first = memory nilOop ifTrue: [^memory nilOop].
	next := self loadRef: first at: PROC_NEXT.
	self storeRef: list at: LL_FIRST put: next.
	next = memory nilOop ifTrue: [self storeRef: list at: LL_LAST put: memory nilOop].
	self storeRef: first at: PROC_NEXT put: memory nilOop.
	self storeRef: first at: PROC_MYLIST put: memory nilOop.
	^first
!
addFirstLink: link to: list
	<c: 'void add_first_link(oop list, oop link)'>
	self storeRef: link at: PROC_NEXT put: (self loadRef: list at: LL_FIRST).
	(self loadRef: list at: LL_FIRST) = memory nilOop ifTrue: [self storeRef: list at: LL_LAST put: link].
	self storeRef: list at: LL_FIRST put: link.
	self storeRef: link at: PROC_MYLIST put: list
!
removeLink: link from: list
	<c: 'bool remove_link(oop list, oop link)'>
	| prev cur next |
	prev := memory nilOop.
	cur := self loadRef: list at: LL_FIRST.
	[cur ~= memory nilOop and: [cur ~= link]] whileTrue: [
		prev := cur.
		cur := self loadRef: cur at: PROC_NEXT].
	cur = memory nilOop ifTrue: [^false].
	next := self loadRef: link at: PROC_NEXT.
	prev = memory nilOop
		ifTrue: [self storeRef: list at: LL_FIRST put: next]
		ifFalse: [self storeRef: prev at: PROC_NEXT put: next].
	(self loadRef: list at: LL_LAST) = link ifTrue: [self storeRef: list at: LL_LAST put: prev].
	self storeRef: link at: PROC_NEXT put: memory nilOop.
	self storeRef: link at: PROC_MYLIST put: memory nilOop.
	^true
! !

!Scheduler methodsFor: 'scheduling'!
processor
	^memory special: SO_PROCESSOR
!
activeProcess
	<c: 'oop active_process(void)'>
	^self loadRef: self processor at: SCHED_ACTIVE
!
priorityOf: p
	<c: 'int64_t priority_of(oop p)'>
	| v pr |
	v := self loadRef: p at: PROC_PRIORITY.
	pr := (self isInt: v) ifTrue: [self intVal: v] ifFalse: [1].
	^pr < 1 ifTrue: [1] ifFalse: [pr > 80 ifTrue: [80] ifFalse: [pr]]
!
runList: pri
	^self loadRef: (self loadRef: self processor at: SCHED_LISTS) at: pri - 1
!
transferTo: aProcess
	"Save the active context into the outgoing process and switch to aProcess."
	<c: 'void transfer_to(oop proc)'>
	| proc old now ct ctx |
	proc := self local: 'oop'.
	proc value: aProcess.
	memory pushRoot: proc.
	interpreter materializeAll.
	memory popRoot.
	old := self activeProcess.
	now := self threadCpuUs.
	ct := self loadRef: old at: PROC_CPUTIME.
	self storeRef: old at: PROC_CPUTIME put: (self intOop: ((self isInt: ct) ifTrue: [self intVal: ct] ifFalse: [0]) + now - lastSwitchUs).
	lastSwitchUs := now.
	self storeRef: old at: PROC_SUSPENDED put: interpreter activeCtx.
	self storeRef: self processor at: SCHED_ACTIVE put: proc value.
	ctx := self loadRef: proc value at: PROC_SUSPENDED.
	((self isPtr: ctx) not or: [ctx = memory nilOop]) ifTrue: [self fatal: 'resuming a process without a context'].
	self storeRef: proc value at: PROC_SUSPENDED put: memory nilOop.
	interpreter activeCtx: ctx.
	gc rememberIfOld: ctx.
	statProcessSwitches := statProcessSwitches + 1
!
idleWait
	<c: 'void idle_wait(void)'>
	| now wait |
	inIdle := true.
	(pendingExtN = 0 and: [allocSamplePending not]) ifTrue: [
		now := self nowUs.
		wait := 16r7FFFFFFFFFFFFFFF.
		timerMs >= 0 ifTrue: [wait := (timerMs * 1000) - now].
		(samplerIntervalUs > 0 and: [samplerNextUs - now < wait]) ifTrue: [wait := samplerNextUs - now].
		self tickSetIdle: true.
		wait = 16r7FFFFFFFFFFFFFFF
			ifTrue: [platform wait: -1]
			ifFalse: [wait > 0 ifTrue: [platform wait: wait]].
		self tickSetIdle: false].
	self handleInterrupts.
	lastSwitchUs := self threadCpuUs.
	inIdle := false
!
transferToHighest
	<c: 'void transfer_to_highest(void)'>
	| lists l |
	[lists := self loadRef: self processor at: SCHED_LISTS.
	 (self numSlots: lists) asInt64 - 1 to: 0 by: -1 do: [:i |
		l := self loadRef: lists at: i.
		(self loadRef: l at: LL_FIRST) ~= memory nilOop ifTrue: [
			self transferTo: (self removeFirstLink: l).
			^self]].
	 self idleWait] repeat
!
resumeProcess: proc
	<c: 'void resume_process(oop proc)'>
	| active |
	active := self activeProcess.
	(inIdle not and: [(self priorityOf: proc) > (self priorityOf: active)])
		ifTrue: [
			"Profiler wakeups must not reorder the run queue: they would act as a 1 ms time slicer and bias the samples."
			preemptToFront
				ifTrue: [self addFirstLink: active to: (self runList: (self priorityOf: active))]
				ifFalse: [self addLastLink: active to: (self runList: (self priorityOf: active))].
			lastPreempted := active.
			self transferTo: proc]
		ifFalse: [self addLastLink: proc to: (self runList: (self priorityOf: proc))]
!
suspendActive
	<c: 'void suspend_active(void)'>
	self transferToHighest
!
semaphoreSignal: sem
	<c: 'void signal_semaphore(oop sem)'>
	| ex |
	(self loadRef: sem at: LL_FIRST) = memory nilOop
		ifTrue: [
			ex := self loadRef: sem at: SEM_EXCESS.
			self storeRef: sem at: SEM_EXCESS put: (self intOop: ((self isInt: ex) ifTrue: [self intVal: ex] ifFalse: [0]) + 1)]
		ifFalse: [self resumeProcess: (self removeFirstLink: sem)]
!
semaphoreWait: sem
	<c: 'void wait_semaphore(oop sem)'>
	| ex |
	ex := self loadRef: sem at: SEM_EXCESS.
	((self isInt: ex) and: [(self intVal: ex) > 0]) ifTrue: [
		self storeRef: sem at: SEM_EXCESS put: (self intOop: (self intVal: ex) - 1).
		^self].
	self addLastLink: self activeProcess to: sem.
	self transferToHighest
!
processorYield
	<c: 'void processor_yield(void)'>
	| active l |
	active := self activeProcess.
	l := self runList: (self priorityOf: active).
	(self loadRef: l at: LL_FIRST) = memory nilOop ifTrue: [^self].
	self addLastLink: active to: l.
	self transferTo: (self removeFirstLink: l)
! !

!Scheduler methodsFor: 'interrupt handling'!
isSemaphore: s
	^(self isPtr: s) and: [s ~= memory nilOop and: [(self fmtHasPointers: (self formatOf: s)) and: [(self numSlots: s) > SEM_EXCESS]]]
!
signalIndex: index
	<c: 'void signal_index(int index)'>
	| ext s |
	ext := memory special: SO_EXTERNAL_OBJECTS.
	(index < 1 or: [(self isPtr: ext) not or: [ext = memory nilOop or: [index asUInt32 > (self numSlots: ext)]]]) ifTrue: [^self].
	s := self loadRef: ext at: index - 1.
	(self isSemaphore: s) ifTrue: [self semaphoreSignal: s]
!
handleInterrupts
	<c: 'void handle_interrupts(void)'>
	| now s |
	self atomicStore: #interruptPending value: 0.
	platform poll.
	now := self nowUs.
	(timerMs >= 0 and: [(now quo: 1000) >= timerMs]) ifTrue: [
		timerMs := -1.
		s := memory special: SO_TIMER_SEMAPHORE.
		(self isSemaphore: s) ifTrue: [self semaphoreSignal: s]].
	preemptToFront := true.
	(samplerIntervalUs > 0 and: [now >= samplerNextUs]) ifTrue: [
		"keep the phase, so the mean interval is exact even if interrupt checks come late"
		samplerNextUs := samplerNextUs + samplerIntervalUs.
		samplerNextUs <= now ifTrue: [samplerNextUs := now + samplerIntervalUs].
		samplerTickUnread := true.
		self signalIndex: samplerSema].
	allocSamplePending ifTrue: [
		allocSamplePending := false.
		self signalIndex: allocSampleSema].
	preemptToFront := false.
	gc finalizationPending ifTrue: [
		gc finalizationPending: false.
		s := memory special: SO_FINALIZATION_SEMAPHORE.
		(self isSemaphore: s) ifTrue: [self semaphoreSignal: s]].
	0 to: pendingExtN - 1 do: [:i | self signalIndex: (pendingExt at: i)].
	pendingExtN := 0.
	self tickUpdate
!
setTimer: ms
	<c: 'void set_timer(int64_t ms)'>
	timerMs := ms.
	self tickUpdate
!
processCpuTimeUs: proc
	"cpuTime, including the running slice if active."
	<c: 'int64_t process_cpu_time_us(oop proc)'>
	| ct t |
	ct := self loadRef: proc at: PROC_CPUTIME.
	t := (self isInt: ct) ifTrue: [self intVal: ct] ifFalse: [0].
	(proc = self activeProcess and: [inIdle not]) ifTrue: [t := t + self threadCpuUs - lastSwitchUs].
	^t
!
setSampler: intervalUs semaphore: sema
	<c: 'void set_sampler(int64_t interval_us, int sema)'>
	samplerIntervalUs := intervalUs.
	samplerSema := sema.
	samplerNextUs := self nowUs + intervalUs.
	self tickUpdate
!
allocSampleHit: aClass bytes: bytes
	<c: 'void alloc_sample_hit(oop cls, size_t bytes)'>
	allocSampleClass := aClass.
	allocSampleSize := bytes asInt64.
	allocSamplePending := true.
	allocSampleUnread := true.
	self requestInterruptCheck
!
relinquish: microseconds
	<c: 'void relinquish(int64_t us)'>
	| us now |
	(pendingExtN ~= 0 or: [allocSamplePending]) ifTrue: [^self].
	us := microseconds.
	now := self nowUs.
	(timerMs >= 0 and: [(timerMs * 1000) - now < us]) ifTrue: [us := (timerMs * 1000) - now].
	(samplerIntervalUs > 0 and: [samplerNextUs - now < us]) ifTrue: [us := samplerNextUs - now].
	us > 0 ifTrue: [
		self tickSetIdle: true.
		platform wait: us.
		self tickSetIdle: false].
	self requestInterruptCheck
! !
