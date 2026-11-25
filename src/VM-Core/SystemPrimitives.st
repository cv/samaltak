VMPrimitiveModule subclass: #SystemPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

SystemPrimitives comment: 'Time and system primitives: clocks, quit, snapshot, GC, statistics, the method cache, the command line, standard output, the environment, the VM''s banner.

vmStats answers an Array of SmallIntegers: 1 scavenges, 2 full GCs, 3 scavenge µs, 4 full GC µs, 5 old bytes used, 6 old budget, 7 eden bytes, 8 bytes allocated, 9 remembered set size, 10 process switches, 11 bytes tenured, 12 weak slots cleared, 13 frames flushed into Contexts, 14 flushes; the JIT''s: 15 methods compiled, 16 bytecodes compiled, 17 compile µs (CPU time, charged to no Process), 18 code bytes, 19 code cache flushes, 20 entries into machine code, 21 exits to the interpreter, 22 resumptions (machine code continued after a return, a send the interpreter made or a process switch), 23 on-stack replacements, 24 methods the JIT could not compile; baseline code''s: 25 inline cache misses, 26 sites linked, 27 polymorphic caches, 28 megamorphic sites, 29 block cache misses, 30 C primitive calls, 31 frame walks; the optimizing tier''s: 32 methods optimized, 33 their bytecodes, 34 µs optimizing, 35 optimized code bytes, 36 deoptimizations, 37 on-stack replacements into optimized code, 38 optimized methods invalidated, 39 methods it could not optimize, 40 sends through the runtime; 41 the GC''s TENURE_AGE; 42 reconciles of the Processes'' CPU time (reads of the thread clock that charge them, Scheduler>>reconcile); 43 timer arms (the Ticker''s timers set or cleared, Scheduler>>tickUpdate).'!

!SystemPrimitives methodsFor: 'time'!
primMillisecondClock
	<vmPrimitive: 150 name: 'millisecondClock'>
	self answer: (self intOop: scheduler nowMs)
!
primMicrosecondClock
	<vmPrimitive: 151 name: 'microsecondClock'>
	self answer: (self intOop: scheduler nowUs)
!
primWorkClockStart
	"(fps, semaphore index) The work clock starts: answer its time in µs."
	<vmPrimitive: 567 name: 'workClockStart'>
	((self isInt: (self arg: 0)) and: [self isInt: (self arg: 1)]) ifFalse: [^self fail].
	self answer: (self intOop: (scheduler workClockStart: (self intVal: (self arg: 0)) semaphore: (self intVal: (self arg: 1)) asInt32))
!
primWorkClockStop
	<vmPrimitive: 568 name: 'workClockStop'>
	scheduler workClockStop.
	self answer: self receiver
!
primWorkClockRunning
	<vmPrimitive: 569 name: 'workClockRunning'>
	scheduler workClockRunning: self arg0 = memory trueOop.
	self answer: self receiver
!
primWorkClockPaced
	<vmPrimitive: 570 name: 'workClockPaced'>
	scheduler workClockPaced: self arg0 = memory trueOop.
	self answer: self receiver
!
primWorkClockQuerying
	<vmPrimitive: 577 name: 'workClockQuerying'>
	scheduler workClockQuerying: self arg0 = memory trueOop.
	self answer: self receiver
!
primWorkClockHold
	<vmPrimitive: 573 name: 'workClockHold'>
	scheduler workClockHold.
	self answer: self receiver
!
primWorkClockRelease
	<vmPrimitive: 574 name: 'workClockRelease'>
	self answer: (self intOop: scheduler workClockRelease)
!
primWorkClockSkipRealTime
	<vmPrimitive: 578 name: 'workClockSkipRealTime'>
	scheduler workClockSkipRealTime.
	self answer: self receiver
!
primWorkClockHeldMicros
	<vmPrimitive: 575 name: 'workClockHeldMicros'>
	self answer: (self intOop: scheduler workClockHeldUs)
!
primWorkClockCharge
	<vmPrimitive: 576 name: 'workClockCharge'>
	(self isInt: self arg0) ifFalse: [^self fail].
	scheduler workClockCharge: (self intVal: self arg0).
	self answer: self receiver
!
primWorkClockNextFrame
	"µs of the next frame of the work clock, nil while it is off"
	<vmPrimitive: 572 name: 'workClockNextFrame'>
	| us |
	us := scheduler workClockNextFrame.
	self answer: (us < 0 ifTrue: [memory nilOop] ifFalse: [self intOop: us])
! !

!SystemPrimitives methodsFor: 'system'!
primQuit
	<vmPrimitive: 160 name: 'quit'>
	<notTryable>
	| c |
	c := self arg0.
	jit printBoundSiteTrace.
	libc fflush: libc stdout.
	libc fflush: libc stderr.
	platform shutdown.
	libc exit: ((self isInt: c) ifTrue: [(self intVal: c) asInt32] ifFalse: [0])
!
primSnapshot
	<vmPrimitive: 161 name: 'snapshot'>
	<notTryable>
	| path ok ctx |
	(memory isKindOfString: self arg0) ifFalse: [^self fail].
	path := memory utf8Of: self arg0.
	path isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	interpreter primCommit: memory trueOop.
	interpreter materializeAll.
	self storeRef: scheduler activeProcess at: PROC_SUSPENDED put: interpreter activeCtx.
	ok := imageFile writeSnapshot: path.
	libc free: path.
	self storeRef: scheduler activeProcess at: PROC_SUSPENDED put: memory nilOop.
	ctx := interpreter activeCtx.
	(self slotsOf: ctx) at: CTX_FIXED + (interpreter ctxStackp: ctx) - 1 put: (ok ifTrue: [memory falseOop] ifFalse: [memory nilOop])
!
primGC
	<vmPrimitive: 162 name: 'gc'>
	gc fullGC.
	self answer: (self intOop: (gc oldBudget - (gc oldTop - gc oldLo)) asInt64)
!
primScavenge
	<vmPrimitive: 163 name: 'scavenge'>
	gc scavenge.
	self answer: (self intOop: (gc edenHi - gc edenTop) asInt64)
!
primReleaseMemory
	"Give back to the system the memory an idle program holds only because it was busy before: eden's and the empty survivor space's pages (after a scavenge), and all machine code with its feedback and the JIT's scratch areas (dropped before Smalltalk goes on; what runs again is compiled again). Answers the receiver."
	<vmPrimitive: 174 name: 'releaseMemory'>
	gc releaseFreeMemory.
	jit releaseMemory.
	self answer: self receiver
!
primVMStats
	<vmPrimitive: 164 name: 'vmStats'>
	| v a |
	v := self local: 'int64_t[43]'.
	scheduler vmStatsInto: v.
	a := memory allocObj: memory clsArray format: F_VAR slots: 43.
	0 to: 42 do: [:i | (self slotsOf: a) at: i put: (self intOop: (v at: i))].
	self answer: a
!
primFlushMethodCache
	<vmPrimitive: 165 name: 'flushMethodCache'>
	interpreter flushMethodCache.
	jit methodsChanged.
	jit optMethodsChanged: memory nilOop.
	self answer: self receiver
!
primFlushCacheForSelector
	<vmPrimitive: 166 name: 'flushCacheForSelector'>
	interpreter flushMethodCacheSelector: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]).
	jit methodsChangedFor: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]).
	jit optMethodsChanged: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]).
	self answer: self receiver
!
stringsArray: v count: n
	<function>
	| a root s |
	a := memory allocObj: memory clsArray format: F_VAR slots: n asUInt32.
	root := self local: 'oop'.
	root value: a.
	memory pushRoot: root.
	0 to: n - 1 do: [:i |
		s := memory stringFromUtf8: (v at: i) size: (libc strlen: (v at: i)).
		self storeRef: root value at: i put: s].
	memory popRoot.
	^root value
!
primVMArguments
	<vmPrimitive: 167 name: 'vmArguments'>
	self answer: (self stringsArray: vmMain argv + vmMain argsStart count: vmMain argc - vmMain argsStart)
!
primImagePath
	<vmPrimitive: 168 name: 'imagePath'>
	| p |
	p := imageFile imagePath isNull ifTrue: [self cString: ''] ifFalse: [imageFile imagePath].
	self answer: (memory stringFromUtf8: p size: (libc strlen: p))
!
primPrimitiveNames
	<vmPrimitive: 171 name: 'primitiveNames'>
	self answer: primitives namesArray
!
primVMBanner
	<vmPrimitive: 173 name: 'vmBanner'>
	| b |
	b := vmMain banner.
	self answer: (memory stringFromUtf8: b size: (libc strlen: b))
! !
