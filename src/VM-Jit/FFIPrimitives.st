VMPrimitiveModule subclass: #FFIPrimitives
	instanceVariableNames: 'ffiStubs runtimeNative mathNames mathSignatures platformNames platformSignatures bindingSession bindingCount bindingOwners bindingEntries bindingArities'
	classVariableNames: 'FFI_MEMCMP FFI_PLATFORM_BASE FFI_DYNAMIC FFI_BINDING_LIMIT FFI_BOUND_REJECTED'
	package: 'VM-Jit'!

FFIPrimitives comment: 'Prepare resolves an approved symbol and exact signature to a process-local wrapper. A bound send uses a session-tagged index checked against a VM-managed weak receiver reference. Saved images rebind from the symbolic descriptor. Native code must not reenter the VM or retain borrowed memory.'!

!FFIPrimitives class methodsFor: 'declaring'!
declarations
	"Name/signature rows are in stable ID order; never repurpose an ID. Signature nibbles are the argument tags, then the result tag."
	^#((ffiStubs FFIStubCompiler) (runtimeNative RuntimeNativeLoader)
		(bindingSession uint64_t) (bindingCount int32_t)
		(bindingOwners 'oop[FFI_BINDING_LIMIT]') (bindingEntries 'uint64_t[FFI_BINDING_LIMIT]')
		(bindingArities 'uint8_t[FFI_BINDING_LIMIT]')
		(mathNames 'const char *[10]' #('sin' 'cos' 'log' 'exp' 'atan' 'sqrt' 'fabs' 'trunc' 'ldexp' 'ilogb'))
		(mathSignatures 'uint32_t[10]' #(16r66 16r66 16r66 16r66 16r66 16r66 16r66 16r66 16r616 16r61))
		(platformNames 'const char *[9]' #('platform_windows_close' 'platform_windows_display_scale' 'platform_windows_refresh_rate'
			'platform_windows_show' 'platform_windows_set_cursor' 'platform_windows_set_text_input_area'
			'pty_resize' 'pty_close' 'pty_foreground'))
		(platformSignatures 'uint32_t[9]' #(16r31 16r36 16r36 16r311 16r31 16r3333331 16r3331 16r31 16r31)))
!
initialize
	FFI_MEMCMP := 11.
	FFI_PLATFORM_BASE := 32.
	FFI_DYNAMIC := 65536.
	FFI_BINDING_LIMIT := 4096.
	FFI_BOUND_REJECTED := 1
! !

!FFIPrimitives methodsFor: 'bound primitives'!
primFFIPrepare
	<vmPrimitive: 263 name: 'ffiPrepare'>
	| owner arity entry slot |
	self argCount = 0 ifFalse: [^self fail].
	owner := self receiver.
	arity := self local: 'int32_t'.
	entry := self boundEntry: owner into: arity.
	entry = FFI_BOUND_REJECTED ifTrue: [^self fail].
	entry ~= 0 ifTrue: [^self answerBool: true].
	ffiStubs canPublishCode ifFalse: [^self fail].
	entry := self prepareEntry: (self loadRef: owner at: 0) into: arity.
	entry = 0 ifTrue: [^self fail].
	self ensureBindingSession ifFalse: [^self fail].
	slot := self bindingSlotFor: owner.
	slot < 0 ifTrue: [
		"Make dead owners reusable if the table is full."
		gc fullGC.
		owner := self receiver.
		slot := self bindingSlotFor: owner.
		slot < 0 ifTrue: [^self fail]].
	bindingOwners at: slot put: owner.
	bindingEntries at: slot put: entry.
	bindingArities at: slot put: arity value asUInt8.
	self storeRef: owner at: 1 put: (self intOop: ((bindingSession bitOr: slot asUInt64) asInt64)).
	self answerBool: true
!
primFFIBoundInvoke
	<vmPrimitive: 264 name: 'ffiBoundInvoke'>
	| arity entry |
	arity := self local: 'int32_t'.
	entry := self boundEntry: self receiver into: arity.
	entry = 0 ifTrue: [^self fail].
	entry = FFI_BOUND_REJECTED ifTrue: [^self answerBool: false].
	self argCount = arity value ifFalse: [^self answerBool: false].
	self callBound: entry args: interpreter primStackBase + 1
!
primFFIBoundInvokeArray
	<vmPrimitive: 265 name: 'ffiBoundInvokeArray'>
	self argCount = 1 ifFalse: [^self fail].
	self invokeBoundArray: self arg0
!
invokeBoundArray: args
	<function>
	<var: #args type: 'oop'>
	| arity entry |
	arity := self local: 'int32_t'.
	entry := self boundEntry: self receiver into: arity.
	entry = 0 ifTrue: [^self fail].
	entry = FFI_BOUND_REJECTED ifTrue: [^self answerBool: false].
	(self isArray: args count: arity value asUInt32) ifFalse: [^self answerBool: false].
	self callBound: entry args: (self slotsOf: args)
!
callBound: entry args: args
	"The launcher consumes args before entering native code. Result boxing may GC; args is never read again."
	<function>
	<var: #entry type: 'uint64_t'>
	<var: #args type: 'const oop *'>
	| answer |
	answer := (self cCoerce: entry to: 'oop (*)(const oop *)') call: args.
	self answer: (answer = 0 ifTrue: [memory falseOop] ifFalse: [answer])
! !

!FFIPrimitives methodsFor: 'binding slots'!
isBindingShape: owner
	<var: #owner type: 'oop'>
	^(owner ~= 0 and: [self isPtr: owner]) and: [
		(self formatOf: owner) = F_FIXED and: [(self numSlots: owner) = 2 and: [self isImmutable: owner]]]
!
boundEntry: owner into: arity
	"Zero permits cold preparation for a missing or stale token. A malformed token or wrong owner in this session is a nonretryable rejection."
	<function>
	<var: #owner type: 'oop'>
	<var: #arity type: 'int32_t *'>
	<returns: 'uint64_t'>
	| token value session slot |
	(self isBindingShape: owner) ifFalse: [^FFI_BOUND_REJECTED].
	token := self loadRef: owner at: 1.
	(self isInt: token) ifFalse: [
		^token = memory nilOop ifTrue: [0] ifFalse: [FFI_BOUND_REJECTED]].
	(self intVal: token) < FFI_BINDING_LIMIT ifTrue: [^FFI_BOUND_REJECTED].
	value := (self intVal: token) asUInt64.
	session := value bitClear: (FFI_BINDING_LIMIT - 1) asUInt64.
	session = bindingSession ifFalse: [^0].
	slot := (value bitAnd: (FFI_BINDING_LIMIT - 1) asUInt64) asInt32.
	(slot >= bindingCount or: [(bindingOwners at: slot) ~= owner]) ifTrue: [^FFI_BOUND_REJECTED].
	arity value: (bindingArities at: slot) asInt32.
	^bindingEntries at: slot
!
ensureBindingSession
	<function>
	| nonce |
	bindingSession ~= 0 ifTrue: [^true].
	nonce := self local: 'uint64_t'.
	(posix getEntropy: nonce size: 8) ~= 0 ifTrue: [^false].
	bindingSession := (nonce value bitAnd: VM_INT_MAX asUInt64) bitClear: (FFI_BINDING_LIMIT - 1) asUInt64.
	bindingSession = 0 ifTrue: [^false].
	gc registerWeakOwners: (self functionPointer: #updateBindingOwners:) invalidate: (self functionPointer: #invalidateBindings).
	^true
!
bindingSlotFor: owner
	<function>
	<var: #owner type: 'oop'>
	<returns: 'int32_t'>
	<var: #free type: 'int32_t'>
	| free other |
	free := -1.
	0 to: bindingCount - 1 do: [:i |
		other := bindingOwners at: i.
		other = owner ifTrue: [^i asInt32].
		(free < 0 and: [other = 0]) ifTrue: [free := i asInt32]].
	free >= 0 ifTrue: [^free].
	bindingCount = FFI_BINDING_LIMIT ifTrue: [^ -1].
	free := bindingCount.
	bindingCount := bindingCount + 1.
	^free
!
updateBindingOwners: isDead
	"Called after strong tracing, before from-space is reclaimed. These weak oops never keep bindings alive."
	<function>
	<var: #isDead type: 'bool (*)(oop *)'>
	0 to: bindingCount - 1 do: [:i |
		((bindingOwners at: i) ~= 0 and: [isDead call: bindingOwners + i]) ifTrue: [
			bindingOwners at: i put: 0]]
!
invalidateBindings
	"Require a fresh symbolic bind after forwarding or reopening an immutable object."
	<function>
	0 to: bindingCount - 1 do: [:i | bindingOwners at: i put: 0].
	bindingCount := 0.
	bindingSession := 0
!
prepareEntry: descriptor into: arity
	<function>
	<var: #descriptor type: 'oop'>
	<var: #arity type: 'int32_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<var: #slots type: 'int32_t'>
	<returns: 'uint64_t'>
	| library symbol libraryOop symbolOop libLen symLen tags tagOop count n slots resultOop result target id operation |
	((self isArray: descriptor count: 4) and: [self isImmutable: descriptor]) ifFalse: [^0].
	libraryOop := self loadRef: descriptor at: 0.
	symbolOop := self loadRef: descriptor at: 1.
	tagOop := self loadRef: descriptor at: 2.
	resultOop := self loadRef: descriptor at: 3.
	((self isPtr: libraryOop) and: [(self isPtr: symbolOop) and: [
		(self isByteArray: tagOop) and: [self isInt: resultOop]]]) ifFalse: [^0].
	((self isImmutable: libraryOop) and: [(self isImmutable: symbolOop) and: [
		self isImmutable: tagOop]]) ifFalse: [^0].
	count := self byteCount: tagOop.
	count > 6 ifTrue: [^0].
	n := count asInt32.
	((self intVal: resultOop) < 1 or: [(self intVal: resultOop) > 7 or: [(self intVal: resultOop) = 5]]) ifTrue: [^0].
	result := (self intVal: resultOop) asInt32.
	library := self local: 'uint8_t[128]'.
	symbol := self local: 'uint8_t[128]'.
	libLen := self copyName: libraryOop into: library.
	symLen := self copyName: symbolOop into: symbol.
	(libLen = 0 or: [symLen = 0]) ifTrue: [^0].
	tags := self local: 'uint8_t[6]'.
	libc memcpy: tags from: (self bytesOf: tagOop) size: count.
	slots := n.
	0 to: n - 1 do: [:i | (tags at: i) = 8 ifTrue: [slots := slots + 1]].
	slots > 6 ifTrue: [^0].
	target := self local: 'uint64_t'.
	id := self resolve: library length: libLen symbol: symbol length: symLen types: tags count: n result: result into: target.
	id = 0 ifTrue: [^0].
	operation := id = FFI_MEMCMP ifTrue: [1] ifFalse: [0].
	arity value: n.
	^ffiStubs entryFor: target value argumentTags: tags count: n returnTag: result operation: operation
! !

!FFIPrimitives methodsFor: 'primitives'!
primFFIBind
	<vmPrimitive: 250 name: 'ffiBind'>
	self bindOrInvoke: false
!
primFFIInvoke
	<vmPrimitive: 251 name: 'ffiInvoke'>
	self bindOrInvoke: true
!
bindOrInvoke: invoke
	<function>
	<var: #invoke type: 'bool'>
	<var: #first type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<var: #slots type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #tag type: 'uint8_t'>
	| first library symbol libLen symLen tagObject tagBytes tags n resultOop result id target argArray abiTags words entry bits slots slot tag |
	first := invoke ifTrue: [1] ifFalse: [0].
	self argCount = (invoke ifTrue: [6] ifFalse: [4]) ifFalse: [^self fail].
	ffiStubs canPublishCode ifFalse: [^self fail].
	library := self local: 'uint8_t[128]'.
	symbol := self local: 'uint8_t[128]'.
	libLen := self copyName: (self arg: first) into: library.
	symLen := self copyName: (self arg: first + 1) into: symbol.
	(libLen = 0 or: [symLen = 0]) ifTrue: [^self fail].
	tagObject := self arg: first + 2.
	(self isByteArray: tagObject) ifFalse: [^self fail].
	tagBytes := self byteCount: tagObject.
	tagBytes > 6 ifTrue: [^self fail].
	n := tagBytes asInt32.
	tags := self local: 'uint8_t[6]'.
	libc memcpy: tags from: (self bytesOf: tagObject) size: tagBytes.
	"Tag 8 is logical; its C ABI uses two slots."
	slots := n.
	0 to: n - 1 do: [:i | (tags at: i) = 8 ifTrue: [slots := slots + 1]].
	slots > 6 ifTrue: [^self fail].
	resultOop := self arg: first + 3.
	(self isInt: resultOop) ifFalse: [^self fail].
	((self intVal: resultOop) < 1 or: [(self intVal: resultOop) > 7 or: [(self intVal: resultOop) = 5]]) ifTrue: [^self fail].
	result := (self intVal: resultOop) asInt32.
	target := self local: 'uint64_t'.
	id := self resolve: library length: libLen symbol: symbol length: symLen types: tags count: n result: result into: target.
	id = 0 ifTrue: [^self fail].
	invoke ifFalse: [^self answerInt: id].
	(self arg: 0) = (self intOop: id) ifFalse: [^self fail].
	argArray := self arg: 5.
	(self isArray: argArray count: n asUInt32) ifFalse: [^self fail].
	words := self local: 'uint64_t[6]'.
	abiTags := self local: 'uint8_t[6]'.
	id = FFI_MEMCMP
		ifTrue: [
			(self marshalCompare: argArray into: words) ifFalse: [^self fail].
			libc memcpy: abiTags from: tags size: tagBytes]
		ifFalse: [
			slot := 0.
			0 to: n - 1 do: [:i |
				tag := tags at: i.
				tag = 8 ifTrue: [
					(self borrow: (self loadRef: argArray at: i) into: words + slot length: words + (slot + 1)) ifFalse: [^self fail].
					abiTags at: slot put: 5.
					slot := slot + 1.
					tag := 4]
				ifFalse: [
					(self marshal: (self loadRef: argArray at: i) tag: tag into: words + slot) ifFalse: [^self fail]].
				abiTags at: slot put: tag.
				slot := slot + 1]].
	"From the first borrow to the return of the call: no VM allocation, GC or reentry. Stubs contain only native targets and are cached by the compiler, never by the image."
	entry := ffiStubs downcall: target value types: abiTags count: slots result: result.
	entry = 0 ifTrue: [^self fail].
	bits := (self cCoerce: entry to: 'uint64_t (*)(uint64_t *)') call: words.
	self answer: (self box: bits tag: result)
! !

!FFIPrimitives methodsFor: 'resolution'!
copyName: name into: buf
	"Counted ASCII name on success (also NUL-terminated for the fixed table); zero on rejection."
	<function>
	<var: #name type: 'oop'>
	<var: #buf type: 'uint8_t *'>
	<returns: 'size_t'>
	| f n c |
	(memory isKindOfString: name) ifFalse: [^0].
	f := self formatOf: name.
	n := f >= F_BYTES
		ifTrue: [self byteCount: name]
		ifFalse: [
			(f = F_W32 or: [f = (F_W32 + 1)]) ifFalse: [^0].
			2 * (self numSlots: name) asUInt64 - (f - F_W32) asUInt64].
	(n = 0 or: [n > 127]) ifTrue: [^0].
	0 to: n asInt64 - 1 do: [:i |
		c := memory stringCharAt: name index: i asUInt64.
		(c = 0 or: [c > 127]) ifTrue: [^0].
		buf at: i put: c asUInt8].
	buf at: n put: 0.
	^n
!
resolve: library length: libLen symbol: symbol length: symLen types: tags count: n result: result into: target
	<function>
	<var: #library type: 'const uint8_t *'>
	<var: #libLen type: 'size_t'>
	<var: #symbol type: 'const uint8_t *'>
	<var: #symLen type: 'size_t'>
	<var: #tags type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<var: #target type: 'uint64_t *'>
	<returns: 'int32_t'>
	| name lib sig hasPointer t id |
	name := self cCoerce: symbol to: 'const char *'.
	lib := self cCoerce: library to: 'const char *'.
	sig := 0 asUInt32.
	hasPointer := false.
	0 to: n - 1 do: [:i |
		t := tags at: i.
		(t < 1 or: [t > 6 and: [t ~= 8]]) ifTrue: [^0].
		t = 5 ifTrue: [hasPointer := true].
		sig := ((sig asUInt64 << 4) bitOr: t asUInt64) asUInt32].
	sig := ((sig asUInt64 << 4) bitOr: result asUInt64) asUInt32.
	(libc strcmp: lib with: 'libm') = 0 ifTrue: [
		0 to: 9 do: [:i |
			(sig = (mathSignatures at: i) and: [(libc strcmp: name with: (mathNames at: i)) = 0]) ifTrue: [
				id := (i + 1) asInt32.
				target value: (self mathTarget: id).
				^id]].
		^0].
	(libc strcmp: lib with: 'libc') = 0 ifTrue: [
		(sig = 16r5541 and: [(libc strcmp: name with: 'memcmp') = 0]) ifFalse: [^0].
		target value: (self cCoerce: (self functionPointer: #nativeCompare:with:count:) to: 'uint64_t').
		^FFI_MEMCMP].
	hasPointer ifTrue: [^0].
	(libc strcmp: lib with: 'platform') = 0 ifTrue: [
		0 to: 8 do: [:i |
			(sig = (platformSignatures at: i) and: [(libc strcmp: name with: (platformNames at: i)) = 0]) ifTrue: [
				id := (FFI_PLATFORM_BASE + i) asInt32.
				target value: (platform ffiTarget: id).
				^target value = 0 ifTrue: [0] ifFalse: [id]]].
		^0].
	target value: (self cCoerce: (runtimeNative lookupLibrary: library length: libLen symbol: symbol length: symLen types: tags count: n result: result) to: 'uint64_t').
	^target value = 0 ifTrue: [0] ifFalse: [FFI_DYNAMIC]
! !

!FFIPrimitives methodsFor: 'marshalling'!
isArray: o count: n
	<var: #o type: 'oop'>
	<var: #n type: 'uint32_t'>
	^(o ~= 0 and: [self isPtr: o]) and: [(self rawClass: o) = memory clsArray and: [(self formatOf: o) = F_VAR and: [(self numSlots: o) = n]]]
!
isByteArray: o
	<var: #o type: 'oop'>
	^(self isPtr: o) and: [(self rawClass: o) = memory clsBytearray and: [(self formatOf: o) >= F_BYTES]]
!
byteCount: o
	<var: #o type: 'oop'>
	<returns: 'size_t'>
	^(8 * (self numSlots: o) asUInt64) - ((self formatOf: o) - F_BYTES) asUInt64
!
marshalCompare: array into: words
	<function>
	<var: #array type: 'oop'>
	<var: #words type: 'uint64_t *'>
	<returns: 'bool'>
	| count length |
	(self marshal: (self loadRef: array at: 2) tag: 4 into: words + 2) ifFalse: [^false].
	count := words at: 2.
	length := self local: 'uint64_t'.
	0 to: 1 do: [:i |
		(self borrow: (self loadRef: array at: i) into: words + i length: length) ifFalse: [^false].
		count > length value ifTrue: [^false]].
	^true
!
borrow: slice into: out length: length
	<function>
	<var: #slice type: 'oop'>
	<var: #out type: 'uint64_t *'>
	<var: #length type: 'uint64_t *'>
	<returns: 'bool'>
	| bytes offsetOop lengthOop start len size |
	(self isArray: slice count: 3) ifFalse: [^false].
	bytes := self loadRef: slice at: 0.
	(self isByteArray: bytes) ifFalse: [^false].
	offsetOop := self loadRef: slice at: 1.
	lengthOop := self loadRef: slice at: 2.
	((self isInt: offsetOop) and: [self isInt: lengthOop]) ifFalse: [^false].
	start := self intVal: offsetOop.
	len := self intVal: lengthOop.
	(start < 1 or: [len < 0]) ifTrue: [^false].
	start := start - 1.
	size := self byteCount: bytes.
	(start asUInt64 > size or: [len asUInt64 > (size - start asUInt64)]) ifTrue: [^false].
	out value: (self cCoerce: (self bytesOf: bytes) + start to: 'uint64_t').
	length value: len asUInt64.
	^true
!
marshal: o tag: tag into: out
	<function>
	<var: #o type: 'oop'>
	<var: #tag type: 'int32_t'>
	<var: #out type: 'uint64_t *'>
	<returns: 'bool'>
	| s |
	tag = 6 ifTrue: [
		(memory isFloat: o) ifFalse: [^false].
		out value: (self bitsOfDouble: (memory floatVal: o)).
		^true].
	(tag = 1 or: [tag = 3]) ifTrue: [
		s := self local: 'int64_t'.
		(memory int64Of: o into: s) ifFalse: [^false].
		(tag = 1 and: [s value < -16r80000000 or: [s value > 16r7FFFFFFF]]) ifTrue: [^false].
		out value: s value asUInt64.
		^true].
	(tag = 2 or: [tag = 4]) ifTrue: [
		(memory u64Of: o into: out) ifFalse: [^false].
		^tag = 4 or: [out value <= 16rFFFFFFFF]].
	^false
!
box: bits tag: tag
	<function>
	<var: #bits type: 'uint64_t'>
	<var: #tag type: 'int32_t'>
	<returns: 'oop'>
	tag = 6 ifTrue: [^memory floatOop: (self doubleFromBits: bits)].
	tag = 7 ifTrue: [^memory nilOop].
	tag = 1 ifTrue: [^self intOop: bits asInt32 asInt64].
	tag = 2 ifTrue: [^self intOop: bits asUInt32 asInt64].
	tag = 3 ifTrue: [
		bits = 16r8000000000000000 ifTrue: [^memory largeIntFrom: bits negative: true].
		^memory int64Oop: bits asInt64].
	bits <= VM_INT_MAX asUInt64 ifTrue: [^self intOop: bits asInt64].
	^memory largeIntFrom: bits negative: false
! !

!FFIPrimitives methodsFor: 'fixed native targets'!
mathTarget: id
	<var: #id type: 'int32_t'>
	<returns: 'uint64_t'>
	^id caseOf: {
		[1] -> [self cCoerce: (self functionPointer: #nativeSin:) to: 'uint64_t'].
		[2] -> [self cCoerce: (self functionPointer: #nativeCos:) to: 'uint64_t'].
		[3] -> [self cCoerce: (self functionPointer: #nativeLog:) to: 'uint64_t'].
		[4] -> [self cCoerce: (self functionPointer: #nativeExp:) to: 'uint64_t'].
		[5] -> [self cCoerce: (self functionPointer: #nativeAtan:) to: 'uint64_t'].
		[6] -> [self cCoerce: (self functionPointer: #nativeSqrt:) to: 'uint64_t'].
		[7] -> [self cCoerce: (self functionPointer: #nativeFabs:) to: 'uint64_t'].
		[8] -> [self cCoerce: (self functionPointer: #nativeTrunc:) to: 'uint64_t'].
		[9] -> [self cCoerce: (self functionPointer: #nativeLdexp:exponent:) to: 'uint64_t'].
		[10] -> [self cCoerce: (self functionPointer: #nativeIlogb:) to: 'uint64_t']}
		otherwise: [0 asUInt64]
!
nativeSin: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm sin: x
!
nativeCos: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm cos: x
!
nativeLog: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm log: x
!
nativeExp: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm exp: x
!
nativeAtan: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm atan: x
!
nativeSqrt: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm sqrt: x
!
nativeFabs: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm fabs: x
!
nativeTrunc: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^libm trunc: x
!
nativeLdexp: x exponent: n
	<function>
	<var: #x type: 'double'>
	<var: #n type: 'int32_t'>
	<returns: 'double'>
	^libm ldexp: x exponent: n
!
nativeIlogb: x
	<function>
	<var: #x type: 'double'>
	<returns: 'int32_t'>
	^libm ilogb: x
!
nativeCompare: a with: b count: count
	<function>
	<var: #a type: 'const void *'>
	<var: #b type: 'const void *'>
	<var: #count type: 'uint64_t'>
	<returns: 'int32_t'>
	count = 0 ifTrue: [^0].
	^libc memcmp: a with: b size: count
! !
