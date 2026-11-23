VMPlatformModule subclass: #FFISDLLogAdapter
	instanceVariableNames: 'ffiStubs logLock installed previousLog previousData shaderCapture shaderError entry entries session generation capacity head queued drops categories priorities lengths payloads'
	classVariableNames: 'MAX_RECORDS MAX_BYTES MAX_STORAGE SHADER_ERROR_SIZE MAX_DROPS'
	package: 'VM-Platform'!

FFISDLLogAdapter comment: 'One process-lifetime SDL log router, shared with GPU error capture. The VM thread installs it once. SDL owns the message and serializes its callbacks; logLock protects the shader buffer and queue against the VM consumer and disarm. The callback never invokes the image, retains no message pointer, and forwards the original arguments to the previous callback after releasing logLock.'!

!FFISDLLogAdapter class methodsFor: 'declaring'!
declarations
	^#((ffiStubs FFIStubCompiler) (logLock 'pthread_mutex_t[1]' #(PTHREAD_MUTEX_INITIALIZER)) (installed bool)
		(previousLog 'SDL_LogOutputFunction[1]') (previousData 'void *[1]')
		(shaderCapture bool) (shaderError 'char[SHADER_ERROR_SIZE]')
		(entry SDL_LogOutputFunction) (entries 'uint64_t[MAX_BYTES]') (session int64_t) (generation int64_t)
		(capacity int32_t) (head int32_t) (queued int32_t) (drops int32_t)
		(categories 'int[MAX_RECORDS]') (priorities 'int[MAX_RECORDS]') (lengths 'int[MAX_RECORDS]')
		(payloads 'uint8_t[MAX_STORAGE]'))
!
initialize
	MAX_RECORDS := 64.
	MAX_BYTES := 240.
	MAX_STORAGE := MAX_RECORDS * MAX_BYTES.
	SHADER_ERROR_SIZE := 2048.
	MAX_DROPS := 2147483647
!
isSimulated
	^false
! !

!FFISDLLogAdapter methodsFor: 'SDL routing'!
ensureHook
	"VM thread only. Do not hold logLock across any SDL logging API, which can take SDL's log mutex."
	<function>
	installed ifTrue: [^self].
	sdl getLogOutputFunction: previousLog userdata: previousData.
	sdl setLogOutputFunction: (self functionPointer: #route:category:priority:message:) userdata: self null.
	installed := true
!
route: userdata category: category priority: priority message: message
	<function>
	<var: #userdata type: 'void *'>
	<var: #category type: 'int'>
	<var: #priority type: 'SDL_LogPriority'>
	<var: #message type: 'const char *'>
	posixThreads mutexLock: logLock.
	(shaderCapture and: [priority >= sdl SDL_LOG_PRIORITY_ERROR]) ifTrue: [
		sdl strlcpy: shaderError from: message size: SHADER_ERROR_SIZE].
	capacity > 0 ifTrue: [entry call: userdata with: category with: priority with: message].
	posixThreads mutexUnlock: logLock.
	(previousLog at: 0) isNull ifFalse: [
		(previousLog at: 0) call: (previousData at: 0) with: category with: priority with: message]
!
enqueue: userdata category: category priority: priority message: message limit: limit
	"Called through a descriptor-specialized adapter with logLock held and a nonzero capacity."
	<function>
	<var: #userdata type: 'void *'>
	<var: #category type: 'int'>
	<var: #priority type: 'SDL_LogPriority'>
	<var: #message type: 'const char *'>
	<var: #limit type: 'int32_t'>
	| tail n |
	queued = capacity ifTrue: [
		drops < MAX_DROPS ifTrue: [drops := drops + 1].
		^self].
	tail := (head + queued) rem: capacity.
	n := 0.
	[n < limit and: [(message at: n) ~= 0]] whileTrue: [n := n + 1].
	categories at: tail put: category.
	priorities at: tail put: priority asInt32.
	lengths at: tail put: n.
	libc memcpy: payloads + (tail * MAX_BYTES) from: message size: n asUInt64.
	queued := queued + 1
!
entryForByteLimit: limit
	"Pass the verified copy limit in argument register 5, then tail-jump. Preserve all four SDL arguments and the caller's stack. One immutable packet per limit, regardless of queue capacity or number of binds."
	<function>
	<var: #limit type: 'int32_t'>
	<returns: 'uint64_t'>
	| index address code addr target |
	index := limit - 1.
	address := entries at: index.
	address ~= 0 ifTrue: [^address].
	code := self local: 'uint64_t[3]'.
	addr := self cCoerce: code to: 'uint64_t'.
	target := self cCoerce: (self functionPointer: #enqueue:category:priority:message:limit:) to: 'uint64_t'.
	jit isX64
		ifTrue: [
			"endbr64; mov r8d, limit; jmp [rip]; target at +16"
			self uint32At: addr put: 16rFA1E0FF3.
			self uint32At: addr + 4 put: ((16rB841 bitOr: (limit asUInt64 << 16)) asUInt32).
			self uint32At: addr + 8 put: 16r25FF0000.
			self uint32At: addr + 12 put: 0]
		ifFalse: [
			"bti c; movz w4, limit; ldr x16, pc+8; br x16; target at +16"
			self uint32At: addr put: 16rD503245F.
			self uint32At: addr + 4 put: ((16r52800004 bitOr: (limit asUInt64 << 5)) asUInt32).
			self uint32At: addr + 8 put: 16r58000050.
			self uint32At: addr + 12 put: 16rD61F0200].
	self uint64At: addr + 16 put: target.
	address := ffiStubs publishCode: (self cCoerce: code to: 'const uint8_t *') size: 24.
	entries at: index put: address.
	^address
! !

!FFISDLLogAdapter methodsFor: 'GPU error capture'!
enableShaderCapture
	<export>
	self ensureHook.
	posixThreads mutexLock: logLock.
	shaderCapture := true.
	posixThreads mutexUnlock: logLock
!
clearShaderError
	<export>
	posixThreads mutexLock: logLock.
	shaderError at: 0 put: 0.
	posixThreads mutexUnlock: logLock
!
copyShaderError: dst size: size
	<export>
	<var: #dst type: 'char *'>
	<var: #size type: 'size_t'>
	posixThreads mutexLock: logLock.
	sdl strlcpy: dst from: shaderError size: size.
	posixThreads mutexUnlock: logLock
! !

!FFISDLLogAdapter methodsFor: 'primitive support'!
matchesHandle
	"Only on the VM thread. session, generation and capacity are changed only by VM primitives."
	<function>
	| s g |
	(self argCount = 2 and: [capacity > 0]) ifFalse: [^false].
	s := self arg: 0.
	g := self arg: 1.
	^((self isInt: s) and: [(self intVal: s) = session]) and:
		[(self isInt: g) and: [(self intVal: g) = generation]]
! !

!FFISDLLogAdapter methodsFor: 'notification primitives'!
primBind
	<vmPrimitive: 255 name: 'ffiSDLLogBind'>
	| c b cap limit nonce address result |
	(self argCount = 2 and: [capacity = 0 and: [generation < VM_INT_MAX]]) ifFalse: [^self fail].
	c := self arg: 0.
	b := self arg: 1.
	((self isInt: c) and: [self isInt: b]) ifFalse: [^self fail].
	cap := self intVal: c.
	limit := self intVal: b.
	(cap < 1 or: [cap > MAX_RECORDS or: [limit < 1 or: [limit > MAX_BYTES]]]) ifTrue: [^self fail].
	session = 0 ifTrue: [
		nonce := self local: 'uint64_t'.
		(posixIO getEntropy: nonce size: 8) = 0 ifFalse: [^self fail].
		session := ((nonce value bitAnd: 16r1FFFFFFFFFFFFFFF) + 1) asInt64].
	address := self entryForByteLimit: limit asInt32.
	address = 0 ifTrue: [^self fail].
	self ensureHook.
	result := memory allocObj: memory clsArray format: F_VAR slots: 2.
	posixThreads mutexLock: logLock.
	generation := generation + 1.
	capacity := cap asInt32.
	entry := self cCoerce: address to: 'SDL_LogOutputFunction'.
	head := 0.
	queued := 0.
	drops := 0.
	posixThreads mutexUnlock: logLock.
	self storeRef: result at: 0 put: (self intOop: session).
	self storeRef: result at: 1 put: (self intOop: generation).
	self answer: result
!
primPoll
	<vmPrimitive: 256 name: 'ffiSDLLogPoll'>
	| copy n category priority data result |
	self matchesHandle ifFalse: [^self fail].
	copy := self local: 'uint8_t[MAX_BYTES]'.
	posixThreads mutexLock: logLock.
	queued = 0 ifTrue: [
		posixThreads mutexUnlock: logLock.
		^self answer: memory nilOop].
	n := lengths at: head.
	category := categories at: head.
	priority := priorities at: head.
	libc memcpy: copy from: payloads + (head * MAX_BYTES) size: n asUInt64.
	posixThreads mutexUnlock: logLock.
	"Allocate outside the lock. The producer never removes or overwrites the head."
	data := self local: 'oop'.
	data value: (memory allocBytes: memory clsBytearray count: n asUInt64).
	libc memcpy: (self bytesOf: data value) from: copy size: n asUInt64.
	memory pushRoot: data.
	result := memory allocObj: memory clsArray format: F_VAR slots: 3.
	memory popRoot.
	self storeRef: result at: 0 put: (self intOop: category).
	self storeRef: result at: 1 put: (self intOop: priority).
	self storeRef: result at: 2 put: data value.
	posixThreads mutexLock: logLock.
	head := (head + 1) rem: capacity.
	queued := queued - 1.
	posixThreads mutexUnlock: logLock.
	self answer: result
!
primDropped
	<vmPrimitive: 257 name: 'ffiSDLLogDropped'>
	| count |
	self matchesHandle ifFalse: [^self fail].
	posixThreads mutexLock: logLock.
	count := drops.
	posixThreads mutexUnlock: logLock.
	self answerInt: count
!
primClose
	<vmPrimitive: 258 name: 'ffiSDLLogClose'>
	self matchesHandle ifFalse: [^self fail].
	posixThreads mutexLock: logLock.
	capacity := 0.
	entry := self null.
	queued := 0.
	posixThreads mutexUnlock: logLock.
	self answerBool: true
!
primProbe
	"Fixed, video-independent source to test the actual SDL log registration."
	<vmPrimitive: 259 name: 'ffiSDLLogProbe'>
	| o n |
	self argCount = 1 ifFalse: [^self fail].
	o := self arg: 0.
	(self isInt: o) ifFalse: [^self fail].
	n := self intVal: o.
	(n < 0 or: [n > 9]) ifTrue: [^self fail].
	sdl logWarn: sdl SDL_LOG_CATEGORY_APPLICATION format: 'samaltak FFI SDL log probe %d (100%% ready)' with: (n asInt32).
	self answerBool: true
! !
