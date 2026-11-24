VMPlatformModule subclass: #FFIExternalNotificationAdapter
	instanceVariableNames: 'ffiStubs ffiPrimitives runtimeNative pending marker entry unregister session generation moveX64'
	classVariableNames: ''
	package: 'VM-Platform'!

FFIExternalNotificationAdapter comment: 'One launcher-authorized registration at a time. The C registrar takes (void (*entry)(void), void *context), returns int32_t (0 for success), and may notify synchronously. After success, void unregister(void *context) must wait for all callbacks and discard both arguments before returning. After failure the registrar must already be quiescent and retain neither argument. Both functions run on the VM thread without VM reentry. The immutable callback packet routes the configured integer register to a native atomic latch. The opaque context points only to a process-lifetime native marker.'!

!FFIExternalNotificationAdapter class methodsFor: 'declaring'!
declarations
	"Four-byte x64 sequences: mov rdi, argument register; first byte of the following jump."
	^#((ffiStubs FFIStubCompiler) (ffiPrimitives FFIPrimitives) (runtimeNative RuntimeNativeLoader)
		(pending atomic_int) (marker 'uint8_t[1]') (entry uint64_t) (unregister uint64_t)
		(session int64_t) (generation int64_t)
		(moveX64 'const uint32_t[6]' #(16rFFFF8948 16rFFF78948 16rFFD78948 16rFFCF8948 16rFFC7894C 16rFFCF894C)))
!
isSimulated
	^false
! !

!FFIExternalNotificationAdapter methodsFor: 'callback'!
latch: context
	"No VM calls and no dereference of the argument. For void callbacks the caller ignores the result register."
	<function>
	<var: #context type: 'void *'>
	<returns: 'int32_t'>
	context = (self cCoerce: marker to: 'void *') ifTrue: [self atomicStore: #pending value: 1].
	^0
!
entryFor: index
	"One layout can match the process grant. Only the VM thread publishes."
	<function>
	<var: #index type: 'int32_t'>
	<returns: 'uint64_t'>
	| bytes address target |
	entry ~= 0 ifTrue: [^entry].
	bytes := self local: 'uint32_t[6]'.
	address := self cCoerce: bytes to: 'uint64_t'.
	target := self cCoerce: (self functionPointer: #latch:) to: 'uint64_t'.
	jit isX64
		ifTrue: [
			"endbr64; mov rdi, arg; jmp [rip+3]; aligned literal at +16"
			self uint32At: address put: 16rFA1E0FF3.
			self uint32At: address + 4 put: (moveX64 at: index).
			self uint32At: address + 8 put: 16r00000325.
			self uint32At: address + 12 put: 0]
		ifFalse: [
			"bti c; mov x0, xArg; ldr x16, pc+8; br x16"
			self uint32At: address put: 16rD503245F.
			self uint32At: address + 4 put: ((16rAA0003E0 bitOr: (index asUInt64 << 16)) asUInt32).
			self uint32At: address + 8 put: 16r58000050.
			self uint32At: address + 12 put: 16rD61F0200].
	self uint32At: address + 16 put: target asUInt32.
	self uint32At: address + 20 put: (target >> 32) asUInt32.
	entry := ffiStubs publishCode: (self cCoerce: bytes to: 'const uint8_t *') size: 24.
	^entry
! !

!FFIExternalNotificationAdapter methodsFor: 'subscription'!
ensureSession
	<function>
	<returns: 'bool'>
	| nonce |
	session ~= 0 ifTrue: [^true].
	nonce := self local: 'uint64_t'.
	(posixIO getEntropy: nonce size: 8) = 0 ifFalse: [^false].
	session := (nonce value bitAnd: VM_INT_MAX asUInt64) asInt64.
	^session ~= 0
!
matchesToken
	<function>
	| s g |
	(self argCount = 2 and: [unregister ~= 0]) ifFalse: [^false].
	s := self arg: 0.
	g := self arg: 1.
	^((self isInt: s) and: [(self intVal: s) = session]) and: [
		(self isInt: g) and: [(self intVal: g) = generation]]
! !

!FFIExternalNotificationAdapter methodsFor: 'primitives'!
primBind
	<vmPrimitive: 260 name: 'ffiExternalNotificationBind'>
	<var: #contextIndex type: 'int32_t'>
	<var: #resultTag type: 'int32_t'>
	| library symbol libLen symLen object count tags result resultTag contextIndex tag registrar cancel abi args packet start stop token |
	(self argCount = 4 and: [unregister = 0 and: [generation < VM_INT_MAX]]) ifFalse: [^self fail].
	ffiStubs canPublishCode ifFalse: [^self fail].
	library := self local: 'uint8_t[128]'.
	symbol := self local: 'uint8_t[128]'.
	libLen := ffiPrimitives copyName: (self arg: 0) into: library.
	symLen := ffiPrimitives copyName: (self arg: 1) into: symbol.
	(libLen = 0 or: [symLen = 0]) ifTrue: [^self fail].
	object := self arg: 2.
	(ffiPrimitives isByteArray: object) ifFalse: [^self fail].
	count := ffiPrimitives byteCount: object.
	(count = 0 or: [count > 6]) ifTrue: [^self fail].
	tags := self local: 'uint8_t[6]'.
	libc memcpy: tags from: (self bytesOf: object) size: count.
	result := self arg: 3.
	result = (self intOop: 1)
		ifTrue: [resultTag := 250]
		ifFalse: [
			result = (self intOop: 7) ifFalse: [^self fail].
			resultTag := 251].
	contextIndex := -1.
	0 to: count asInt32 - 1 do: [:i |
		tag := tags at: i.
		tag = 250
			ifTrue: [
				contextIndex >= 0 ifTrue: [^self fail].
				contextIndex := i asInt32]
			ifFalse: [(tag < 1 or: [tag > 4]) ifTrue: [^self fail]]].
	contextIndex < 0 ifTrue: [^self fail].
	registrar := runtimeNative lookupLibrary: library length: libLen symbol: symbol length: symLen types: tags count: count asInt32 result: resultTag.
	registrar isNull ifTrue: [^self fail].
	cancel := runtimeNative notificationUnregister.
	cancel isNull ifTrue: [^self fail].
	self ensureSession ifFalse: [^self fail].
	"All publication must succeed before entering the registrar."
	abi := self local: 'uint8_t[2]'.
	abi at: 0 put: 5; at: 1 put: 5.
	start := ffiStubs downcall: (self cCoerce: registrar to: 'uint64_t') types: abi count: 2 result: 1.
	stop := ffiStubs downcall: (self cCoerce: cancel to: 'uint64_t') types: abi count: 1 result: 7.
	(start = 0 or: [stop = 0]) ifTrue: [^self fail].
	packet := self entryFor: contextIndex.
	packet = 0 ifTrue: [^self fail].
	args := self local: 'uint64_t[2]'.
	args at: 0 put: packet; at: 1 put: (self cCoerce: marker to: 'uint64_t').
	self atomicStore: #pending value: 0.
	((self cCoerce: start to: 'uint64_t (*)(uint64_t *)') call: args) ~= 0 ifTrue: [
		self atomicStore: #pending value: 0.
		^self fail].
	unregister := stop.
	generation := generation + 1.
	token := memory allocObj: memory clsArray format: F_VAR slots: 2.
	self storeRef: token at: 0 put: (self intOop: session).
	self storeRef: token at: 1 put: (self intOop: generation).
	self answer: token
!
primPoll
	<vmPrimitive: 261 name: 'ffiExternalNotificationPoll'>
	self matchesToken ifFalse: [^self fail].
	self answerBool: (self atomicExchange: #pending value: 0) ~= 0
!
primClose
	<vmPrimitive: 262 name: 'ffiExternalNotificationClose'>
	| args |
	self matchesToken ifFalse: [^self fail].
	args := self local: 'uint64_t[1]'.
	args at: 0 put: (self cCoerce: marker to: 'uint64_t').
	"No lock held while unregister waits for workers to quiesce."
	(self cCoerce: unregister to: 'uint64_t (*)(uint64_t *)') call: args.
	unregister := 0.
	self atomicStore: #pending value: 0.
	self answerBool: true
! !
