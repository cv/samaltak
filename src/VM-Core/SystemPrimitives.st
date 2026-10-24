VMPrimitiveModule subclass: #SystemPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

SystemPrimitives comment: 'Time and system primitives: clocks, quit, snapshot, GC, statistics, the method cache, the command line, standard output, the environment.

vmStats answers an Array of SmallIntegers: 1 scavenges, 2 full GCs, 3 scavenge µs, 4 full GC µs, 5 old bytes used, 6 old budget, 7 eden bytes, 8 bytes allocated, 9 remembered set size, 10 process switches, 11 bytes tenured, 12 weak slots cleared, 13 frames flushed into Contexts, 14 flushes.'!

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
	v := self local: 'int64_t[14]'.
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
	a := memory allocObj: memory clsArray format: F_VAR slots: 14.
	0 to: 13 do: [:i | (self slotsOf: a) at: i put: (self intOop: (v at: i))].
	self answer: a
!
primFlushMethodCache
	<vmPrimitive: 165 name: 'flushMethodCache'>
	interpreter flushMethodCache.
	self answer: self receiver
!
primFlushCacheForSelector
	<vmPrimitive: 166 name: 'flushCacheForSelector'>
	interpreter flushMethodCacheSelector: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]).
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
! !
