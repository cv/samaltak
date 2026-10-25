VMPrimitiveModule subclass: #SystemPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

SystemPrimitives comment: 'Time and system primitives: clocks, quit, snapshot, GC, statistics, the method cache, the command line, standard output, the environment, the VM''s banner.

vmStats answers an Array of SmallIntegers: 1 scavenges, 2 full GCs, 3 scavenge µs, 4 full GC µs, 5 old bytes used, 6 old budget, 7 eden bytes, 8 bytes allocated, 9 remembered set size, 10 process switches, 11 bytes tenured, 12 weak slots cleared, 13 frames flushed into Contexts, 14 flushes; the JIT''s: 15 methods compiled, 16 bytecodes compiled, 17 compile µs, 18 code bytes, 19 code cache flushes, 20 entries into machine code, 21 exits to the interpreter, 22 resumptions (machine code continued after a return or a send the interpreter made), 23 on-stack replacements, 24 methods the JIT could not compile; the optimizing tier''s: 25 methods optimized, 26 their bytecodes, 27 µs optimizing, 28 optimized code bytes, 29 deoptimizations, 30 on-stack replacements into optimized code, 31 optimized methods invalidated, 32 methods it could not optimize.'!

!SystemPrimitives methodsFor: 'time'!
primMillisecondClock
	<vmPrimitive: 150 name: 'millisecondClock'>
	self answer: (self intOop: scheduler nowMs)
!
primMicrosecondClock
	<vmPrimitive: 151 name: 'microsecondClock'>
	self answer: (self intOop: scheduler nowUs)
!
primUtcMicroseconds
	<vmPrimitive: 152 name: 'utcMicroseconds'>
	| tv |
	tv := self local: 'Timeval'.
	posix gettimeofday: tv zone: self null.
	self answer: (self intOop: (tv tv_sec * 1000000) + tv tv_usec)
! !

!SystemPrimitives methodsFor: 'system'!
primQuit
	<vmPrimitive: 160 name: 'quit'>
	<notTryable>
	| c |
	c := self arg0.
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
primVMStats
	<vmPrimitive: 164 name: 'vmStats'>
	| v a |
	v := self local: 'int64_t[32]'.
	v at: 0 put: gc statScavenges asInt64.
	v at: 1 put: gc statFullGcs asInt64.
	v at: 2 put: gc statScavengeUs asInt64.
	v at: 3 put: gc statFullUs asInt64.
	v at: 4 put: (gc oldTop - gc oldLo) asInt64.
	v at: 5 put: gc oldBudget asInt64.
	v at: 6 put: (gc edenHi - gc edenLo) asInt64.
	v at: 7 put: (gc statAllocated + (gc edenTop - gc edenLo)) asInt64.
	v at: 8 put: gc remsetCount asInt64.
	v at: 9 put: scheduler statProcessSwitches asInt64.
	v at: 10 put: gc statTenured asInt64.
	v at: 11 put: gc statWeakCleared asInt64.
	v at: 12 put: interpreter statMaterialized asInt64.
	v at: 13 put: interpreter statFlushes asInt64.
	v at: 14 put: jit statCompiled asInt64.
	v at: 15 put: jit statBytecodes asInt64.
	v at: 16 put: jit statCompileUs asInt64.
	v at: 17 put: jit statCodeBytes asInt64.
	v at: 18 put: jit statCacheFlushes asInt64.
	v at: 19 put: jit statEntries asInt64.
	v at: 20 put: jit statExits asInt64.
	v at: 21 put: jit statResumes asInt64.
	v at: 22 put: jit statOsr asInt64.
	v at: 23 put: jit statFailed asInt64.
	v at: 24 put: (jit optStat: 0).
	v at: 25 put: (jit optStat: 1).
	v at: 26 put: (jit optStat: 2).
	v at: 27 put: (jit optStat: 3).
	v at: 28 put: (jit optStat: 4).
	v at: 29 put: (jit optStat: 5).
	v at: 30 put: (jit optStat: 6).
	v at: 31 put: (jit optStat: 7).
	a := memory allocObj: memory clsArray format: F_VAR slots: 32.
	0 to: 31 do: [:i | (self slotsOf: a) at: i put: (self intOop: (v at: i))].
	self answer: a
!
primFlushMethodCache
	<vmPrimitive: 165 name: 'flushMethodCache'>
	interpreter flushMethodCache.
	jit methodsChanged: memory nilOop.
	self answer: self receiver
!
primFlushCacheForSelector
	<vmPrimitive: 166 name: 'flushCacheForSelector'>
	interpreter flushMethodCacheSelector: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]).
	jit methodsChanged: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]).
	self answer: self receiver
!
stringsArray: v count: n
	<c: 'oop strings_array(char **v, int n)'>
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
writeTo: f
	| s u |
	s := self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver].
	((self isPtr: s) and: [(memory isKindOfString: s) or: [(self rawClass: s) = memory clsBytearray]]) ifFalse: [^self fail].
	u := memory utf8Of: s.
	u isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	libc fputs: u to: f.
	libc fflush: f.
	libc free: u.
	self answer: self receiver
!
primStdoutWrite
	<vmPrimitive: 169 name: 'stdoutWrite'>
	self writeTo: libc stdout
!
primStderrWrite
	<vmPrimitive: 170 name: 'stderrWrite'>
	self writeTo: libc stderr
!
primPrimitiveNames
	<vmPrimitive: 171 name: 'primitiveNames'>
	self answer: primitives namesArray
!
primGetenv
	<vmPrimitive: 172 name: 'getenv'>
	| k v |
	(memory isKindOfString: self arg0) ifFalse: [^self fail].
	k := memory utf8Of: self arg0.
	k isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	v := libc getenv: k.
	libc free: k.
	self answer: (v notNull ifTrue: [memory stringFromUtf8: v size: (libc strlen: v)] ifFalse: [memory nilOop])
!
primVMBanner
	<vmPrimitive: 173 name: 'vmBanner'>
	| b |
	b := vmMain banner.
	self answer: (memory stringFromUtf8: b size: (libc strlen: b))
! !
