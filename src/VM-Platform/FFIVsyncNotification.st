VMPlatformModule subclass: #FFIVsyncNotification
	instanceVariableNames: 'ffiStubs asm entropy notifyLock lockInitialized active pendingSignals subscriptions entries session serial tick nBound'
	classVariableNames: 'MAX_VSYNC_BINDINGS'
	package: 'VM-Platform'!

FFIVsyncNotification comment: 'The native refresh source calls a fixed dispatcher. Each live slot supplies its own native context (a pending word) to generated code with the signature void(uint64_t tick, uint32_t *pending); neither an oop nor a host pointer crosses the image API. The mutex protects publication, generated calls, polling and revocation. Published code embeds only a tick mask, never a slot address, and is reused after close.'!

!FFIVsyncNotification class methodsFor: 'declaring'!
declarations
	^#((ffiStubs FFIStubCompiler) (asm JitAssembler) (entropy FFIVsyncEntropy)
		(notifyLock 'pthread_mutex_t[1]') (lockInitialized bool) (active atomic_bool) (pendingSignals bool)
		(subscriptions 'ffi_vsync_subscription[MAX_VSYNC_BINDINGS]') (entries 'uint64_t[8]')
		(session uint64_t) (serial uint64_t) (tick uint64_t) (nBound int32_t))
!
initialize
	MAX_VSYNC_BINDINGS := 16
!
isSimulated
	^false
! !

!FFIVsyncNotification methodsFor: 'code generation'!
entryFor: index
	"index determines the tick mask 2**index - 1. Both supported ABIs pass tick and the word pointer in argument registers 0 and 1. No calls or instruction references outside this packet."
	<function>
	<var: #index type: 'int32_t'>
	<returns: 'uint64_t'>
	| bytes a mask entry |
	entry := entries at: index.
	entry ~= 0 ifTrue: [^entry].
	bytes := self local: 'uint32_t[8]'.
	a := self cCoerce: bytes to: 'uint64_t'.
	mask := (1 << index) - 1.
	asm isX64
		ifTrue: [
			"endbr64; test dil, mask; jnz ret; mov dword ptr [rsi], 1; ret"
			self uint32At: a put: 16rFA1E0FF3.
			self uint32At: a + 4 put: (((mask asUInt64 << 24) bitOr: 16rC7F640) asUInt32).
			self uint32At: a + 8 put: 16r06C70675.
			self uint32At: a + 12 put: 1.
			self uint8At: a + 16 put: 16rC3.
			entry := ffiStubs publishCode: (self cCoerce: bytes to: 'const uint8_t *') size: 17]
		ifFalse: [
			"bti c; movz x2, mask; tst x0, x2; b.ne ret; mov w2, #1; str w2, [x1]; ret"
			self uint32At: a put: 16rD503245F.
			self uint32At: a + 4 put: ((16rD2800002 asUInt64 bitOr: (mask asUInt64 << 5)) asUInt32).
			self uint32At: a + 8 put: 16rEA02001F.
			self uint32At: a + 12 put: 16r54000061.
			self uint32At: a + 16 put: 16r52800022.
			self uint32At: a + 20 put: 16rB9000022.
			self uint32At: a + 24 put: 16rD65F03C0.
			entry := ffiStubs publishCode: (self cCoerce: bytes to: 'const uint8_t *') size: 28].
	entries at: index put: entry.
	^entry
! !

!FFIVsyncNotification methodsFor: 'registration'!
prepare
	"On the VM thread, before starting the host refresh source."
	<export>
	lockInitialized ifFalse: [
		lockInitialized := (posixThreads mutexInit: notifyLock attributes: self null) = 0].
	^lockInitialized
!
ensureSession
	<function>
	| value |
	session ~= 0 ifTrue: [^true].
	value := self local: 'uint64_t'.
	(entropy getEntropy: value size: 8) ~= 0 ifTrue: [^false].
	session := value value bitAnd: VM_INT_MAX asUInt64.
	^session ~= 0
!
refreshed
	"Host refresh thread: no image work, no arbitrary pointer or callback. A late invocation after revocation either sees no slot or sees only the current registration."
	<export>
	| slot wasPending wake |
	(self atomicLoad: #active) ifFalse: [^self].
	posixThreads mutexLock: notifyLock.
	wake := false.
	tick := tick + 1.
	0 to: MAX_VSYNC_BINDINGS - 1 do: [:i |
		slot := subscriptions + i.
		slot generation ~= 0 ifTrue: [
			wasPending := slot pending ~= 0.
			(self cCoerce: slot entry to: 'void (*)(uint64_t, uint32_t *)')
				call: tick with: (slot fieldAddress: #pending).
			(wasPending not and: [slot pending ~= 0 and: [slot semaphoreIndex ~= 0]]) ifTrue: [
				slot needsSignal: true.
				wake := wake or: [pendingSignals not].
				pendingSignals := true]]].
	posixThreads mutexUnlock: notifyLock.
	wake ifTrue: [
		scheduler requestInterruptCheck.
		sdlPlatform wake]
!
pendingSignals
	"Check after platform_wait has announced inWait. The shared lock closes the check/wake race."
	<export>
	| pending |
	(self atomicLoad: #active) ifFalse: [^false].
	posixThreads mutexLock: notifyLock.
	pending := pendingSignals.
	posixThreads mutexUnlock: notifyLock.
	^pending
!
signalReady
	"Only on the VM thread during the scheduler's poll, which drains the queued indices before returning to Smalltalk."
	<export>
	| indices count slot |
	(self atomicLoad: #active) ifFalse: [^self].
	indices := self local: 'int32_t[MAX_VSYNC_BINDINGS]'.
	count := 0.
	posixThreads mutexLock: notifyLock.
	pendingSignals ifTrue: [
		pendingSignals := false.
		0 to: MAX_VSYNC_BINDINGS - 1 do: [:i |
			slot := subscriptions + i.
			slot needsSignal ifTrue: [
				slot needsSignal: false.
				indices at: count put: slot semaphoreIndex.
				count := count + 1]]].
	posixThreads mutexUnlock: notifyLock.
	0 to: count - 1 do: [:i | scheduler signalExternalSemaphore: (indices at: i)]
!
slotFor: epochValue generation: generationValue
	"Called with notifyLock held, on the VM thread only."
	<function>
	<var: #epochValue type: 'oop'>
	<var: #generationValue type: 'oop'>
	<returns: 'ffi_vsync_subscription *'>
	| generation slot |
	((self isInt: epochValue) and: [(self isInt: generationValue) and: [
		(self intVal: epochValue) asUInt64 = session and: [session ~= 0]]]) ifFalse: [^self null].
	generation := self intVal: generationValue.
	generation <= 0 ifTrue: [^self null].
	0 to: MAX_VSYNC_BINDINGS - 1 do: [:i |
		slot := subscriptions + i.
		slot generation = generation asUInt64 ifTrue: [^slot]].
	^self null
! !

!FFIVsyncNotification methodsFor: 'primitives'!
primBind
	<vmPrimitive: 252 name: 'ffiVsyncBind'>
	| step index entry slot token semaphoreIndex ext sem |
	(self argCount = 3 and: [(self arg: 0) = (self intOop: 2) and: [
		(self isInt: (self arg: 1)) and: [self isInt: (self arg: 2)]]]) ifFalse: [^self fail].
	semaphoreIndex := self intVal: (self arg: 2).
	(semaphoreIndex < 0 or: [semaphoreIndex > 2147483647]) ifTrue: [^self fail].
	semaphoreIndex ~= 0 ifTrue: [
		ext := memory special: SO_EXTERNAL_OBJECTS.
		((self isPtr: ext) and: [ext ~= memory nilOop and: [
			(self rawClass: ext) = memory clsArray and: [semaphoreIndex asUInt64 <= (self numSlots: ext)]]])
			ifFalse: [^self fail].
		sem := self loadRef: ext at: semaphoreIndex - 1.
		((self isPtr: sem) and: [(self rawClass: sem) = (memory special: SO_SEMAPHORE)]) ifFalse: [^self fail]].
	step := self intVal: (self arg: 1).
	(step < 1 or: [step > 128 or: [(step bitAnd: step - 1) ~= 0]]) ifTrue: [^self fail].
	(nBound >= MAX_VSYNC_BINDINGS or: [serial >= VM_INT_MAX asUInt64]) ifTrue: [^self fail].
	self ensureSession ifFalse: [^self fail].
	index := 0.
	[step > 1] whileTrue: [index := index + 1. step := step >> 1].
	entry := self entryFor: index asInt32.
	entry = 0 ifTrue: [^self fail].
	nBound = 0 ifTrue: [(vsync notifications: true) ifFalse: [^self fail]].
	posixThreads mutexLock: notifyLock.
	slot := subscriptions.
	[slot generation ~= 0] whileTrue: [slot := slot + 1].
	serial := serial + 1.
	slot pending: 0.
	slot semaphoreIndex: semaphoreIndex asInt32.
	slot needsSignal: false.
	slot entry: entry.
	slot generation: serial.
	nBound := nBound + 1.
	self atomicStore: #active value: true.
	posixThreads mutexUnlock: notifyLock.
	token := memory allocObj: memory clsArray format: F_VAR slots: 2.
	self storeRef: token at: 0 put: (self intOop: session asInt64).
	self storeRef: token at: 1 put: (self intOop: serial asInt64).
	self answer: token
!
primPoll
	<vmPrimitive: 253 name: 'ffiVsyncPoll'>
	| slot wasPending |
	(self argCount = 2 and: [nBound > 0]) ifFalse: [^self fail].
	posixThreads mutexLock: notifyLock.
	slot := self slotFor: (self arg: 0) generation: (self arg: 1).
	slot isNull ifTrue: [
		posixThreads mutexUnlock: notifyLock.
		^self fail].
	wasPending := slot pending ~= 0.
	slot pending: 0.
	slot needsSignal: false.
	posixThreads mutexUnlock: notifyLock.
	self answerBool: wasPending
!
primClose
	<vmPrimitive: 254 name: 'ffiVsyncClose'>
	| slot |
	(self argCount = 2 and: [nBound > 0]) ifFalse: [^self fail].
	posixThreads mutexLock: notifyLock.
	slot := self slotFor: (self arg: 0) generation: (self arg: 1).
	slot isNull ifTrue: [
		posixThreads mutexUnlock: notifyLock.
		^self fail].
	slot generation: 0.
	slot pending: 0.
	slot needsSignal: false.
	slot semaphoreIndex: 0.
	slot entry: 0.
	nBound := nBound - 1.
	nBound = 0 ifTrue: [pendingSignals := false].
	self atomicStore: #active value: nBound ~= 0.
	posixThreads mutexUnlock: notifyLock.
	"Stopping a host source may wait for a callback. Never hold notifyLock here."
	nBound = 0 ifTrue: [vsync notifications: false].
	self answerBool: true
! !

VMStruct subclass: #FFIVsyncSubscription
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!FFIVsyncSubscription class methodsFor: 'declaring'!
cName
	^'ffi_vsync_subscription'
!
fields
	^#((entry uint64_t) (generation uint64_t) (pending uint32_t) (semaphoreIndex int32_t) (needsSignal bool))
! !

CLibrary subclass: #FFIVsyncEntropy
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!FFIVsyncEntropy class methodsFor: 'declaring'!
headers
	^#('<unistd.h>')
! !

!FFIVsyncEntropy methodsFor: 'entropy'!
getEntropy: buffer size: size
	<c: 'int getentropy(void *buffer, size_t size)'>
	^self error: 'not simulated'
! !
