VMPlatformModule subclass: #PlatformPrimitives
	instanceVariableNames: 'bad'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformPrimitives comment: 'The platform primitives (400-699): argument checking and conversion around the platform layer''s internals.

The receiver is ignored; arguments are positional. Handles are SmallIntegers. Byte buffers are ByteArray/ByteString (or Bitmap); start is 1-based. Booleans are true/false. A primitive fails on bad arguments or platform errors; platformLastError answers the reason. intArg: and its siblings set bad for an argument of the wrong kind.

Events: nextEvent:/injectEvent: use 8-slot Arrays
	[type, timeMs, x, y, buttonOrKey, modifiers, textOrDelta, windowId]
x, y: Floats in points (mouse position; for windowResized the new size; for displayScaleChanged x = new scale). modifiers: shift 1, ctrl 2, alt 4, cmd 8.
	type	buttonOrKey	textOrDelta
	1 mouseMove	buttons held (1 L 2 M 4 R)	nil
	2 mouseDown	button (1 L, 2 M, 3 R)	click count
	3 mouseUp	button	click count
	4 wheel	0	Point dx@dy (Floats; +y = scroll up, honouring the system scroll direction)
	5 keyDown	keycode	repeat (Boolean)
	6 keyUp	keycode	repeat (Boolean)
	7 textInput	0	String (UTF-8 decoded)
	8 windowResized	0	nil
	9 windowCloseRequest, 10 quit, 11 focusGained, 12 focusLost, 13 displayScaleChanged, 14 mouseLeave, 15 windowExposed
timeMs: platform monotonic ms (nil when injecting = now). windowId: window handle or nil.

Keycodes (SDL): printable keys are their lowercase character code (''a'' = 97 ... ''z'' = 122, ''0'' = 48, space = 32), return 13, escape 27, backspace 8, tab 9, delete 127, right 16r4000004F, left 16r40000050, down 16r40000051, up 16r40000052, home 16r4000004A, end 16r4000004D, pageUp 16r4000004B, pageDown 16r4000004E, insert 16r40000049, F1 16r4000003A ... F12 16r40000045, keypad enter 16r40000058, lshift 16r400000E1, lctrl 16r400000E0, lalt 16r400000E2, lcmd 16r400000E3.'!

!PlatformPrimitives class methodsFor: 'declaring'!
declarations
	^#((bad bool))
! !

!PlatformPrimitives methodsFor: 'arguments'!
args: n
	"Start a primitive of n arguments: answer whether it has them."
	bad := false.
	^self argCount = n
!
intArg: i
	<c: 'int64_t int_arg(int i)'>
	| v |
	v := self local: 'int64_t'.
	(memory int64Of: (self arg: i) into: v) ifFalse: [bad := true].
	^v value
!
floatArg: i
	<c: 'double float_arg(int i)'>
	| o |
	o := self arg: i.
	(self isInt: o) ifTrue: [^(self intVal: o) asFloat].
	(memory isFloat: o) ifTrue: [^memory floatVal: o].
	bad := true.
	^0.0
!
boolArg: i
	<c: 'bool bool_arg(int i)'>
	| o |
	o := self arg: i.
	o = memory trueOop ifTrue: [^true].
	o ~= memory falseOop ifTrue: [bad := true].
	^false
!
isText: o
	<c: 'bool is_text(oop o)'>
	| f |
	(self isPtr: o) ifFalse: [^false].
	f := self formatOf: o.
	^f >= F_BYTES or: [f = 10 or: [f = 11]]
!
stringArg: i
	"The malloc'd UTF-8 of a String argument (NULL, and bad set, otherwise)."
	<c: 'char *string_arg(int i)'>
	| o s |
	o := self arg: i.
	s := (self isText: o) ifTrue: [memory utf8Of: o] ifFalse: [self null].
	s isNull ifTrue: [bad := true].
	^s
!
bytesOf: o size: n writable: writable
	"The raw bytes of a byte object or Bitmap, their count in n; NULL if o is none (or immutable and writable is wanted)."
	<c: 'uint8_t *bytes_view(oop o, size_t *n, bool writable)'>
	| f |
	(self isPtr: o) ifFalse: [^self null].
	(writable and: [self isImmutable: o]) ifTrue: [^self null].
	f := self formatOf: o.
	f >= F_BYTES ifTrue: [
		n value: (memory byteSize: o).
		^self bytesOf: o].
	(f = 10 or: [f = 11]) ifTrue: [
		n value: (memory word32Size: o) * 4.
		^self cCoerce: (self words32Of: o) to: 'uint8_t *'].
	^self null
!
rangeArgs: writable handle: h count: count
	"(handle, buffer, start, count) with 1-based start: the bytes of the range; NULL if the arguments are bad."
	<c: 'uint8_t *range_args(bool writable, int64_t *h, int64_t *count)'>
	| start len p |
	self argCount ~= 4 ifTrue: [^self null].
	bad := false.
	h value: (self intArg: 0).
	start := self intArg: 2.
	count value: (self intArg: 3).
	len := self local: 'size_t'.
	p := self bytesOf: (self arg: 1) size: len writable: writable.
	(bad or: [p isNull or: [start < 1 or: [count value < 0 or: [(start - 1 + count value) asUInt64 > len value]]]]) ifTrue: [^self null].
	^p + (start - 1)
!
numberOf: o into: d
	<c: 'bool num_of(oop o, double *d)'>
	(self isInt: o) ifTrue: [
		d value: (self intVal: o) asFloat.
		^true].
	(memory isFloat: o) ifTrue: [
		d value: (memory floatVal: o).
		^true].
	^false
!
rect: r into: out
	"{x. y. w. h} of SmallIntegers."
	<c: 'bool rect_of(oop r, int *out)'>
	| v |
	((self isPtr: r) and: [(self formatOf: r) = F_VAR and: [(self numSlots: r) = 4]]) ifFalse: [^false].
	0 to: 3 do: [:i |
		v := self loadRef: r at: i.
		(self isInt: v) ifFalse: [^false].
		out at: i put: (self intVal: v) asInt32].
	^true
!
stringVector: a nonEmpty: nonEmpty
	"Malloc'd NULL-terminated C strings of an Array of Strings (NULL: not one, or empty when nonEmpty)."
	<c: 'char **string_vector(oop a, bool non_empty)'>
	| n v s |
	((self isPtr: a) and: [(self formatOf: a) = F_VAR and: [nonEmpty not or: [(self numSlots: a) ~= 0]]]) ifFalse: [^self null].
	n := self numSlots: a.
	v := self cCoerce: (libc calloc: n asUInt64 + 1 size: (self sizeof: 'char *')) to: 'char **'.
	v isNull ifTrue: [^self null].
	0 to: n asInt64 - 1 do: [:i |
		s := self loadRef: a at: i.
		(self isText: s) ifTrue: [v at: i put: (memory utf8Of: s)].
		((self isText: s) not or: [(v at: i) isNull]) ifTrue: [
			0 to: i - 1 do: [:k | libc free: (v at: k)].
			libc free: v.
			^self null]].
	^v
!
freeVector: v
	<c: 'void free_vector(char **v)'>
	| p |
	v isNull ifTrue: [^self].
	p := v.
	[p value notNull] whileTrue: [
		libc free: p value.
		p := p + 1].
	libc free: v
! !

!PlatformPrimitives methodsFor: 'results'!
answerSelf
	self answer: self receiver
!
answerOk: aBoolean
	aBoolean ifTrue: [self answerSelf] ifFalse: [self fail]
!
answerHandle: h
	h > 0 ifTrue: [self answer: (self intOop: h)] ifFalse: [self fail]
!
answerCount: r
	"A count; nil for -1 (would block); fail for other negative results."
	r = -1 ifTrue: [^self answer: memory nilOop].
	r < 0 ifTrue: [^self fail].
	self answer: (self intOop: r)
!
answerSize: r
	"A count; fail if negative."
	r < 0 ifTrue: [^self fail].
	self answer: (self intOop: r)
!
answerNonNegative: d
	d < 0.0 ifTrue: [self fail] ifFalse: [self answer: (memory floatOop: d)]
!
answerString: s
	"s is malloc'd (NULL: fail); freed here."
	<c: 'void answer_string(char *s)'>
	| r |
	s isNull ifTrue: [^self fail].
	r := memory stringFromUtf8: s size: (libc strlen: s).
	libc free: s.
	self answer: r
!
arrayOf: v count: n
	"An Array of n SmallIntegers."
	<c: 'oop array_of_ints(int64_t *v, int n)'>
	| a |
	a := memory allocSlots: memory clsArray count: n asUInt32.
	0 to: n - 1 do: [:i | self storeRef: a at: i put: (self intOop: (v at: i))].
	^a
!
answerPair: ok first: a second: b
	<c: 'void answer_pair(bool ok, int a, int b)'>
	| v |
	ok ifFalse: [^self fail].
	v := self local: 'int64_t[2]'.
	v at: 0 put: a.
	v at: 1 put: b.
	self answer: (self arrayOf: v count: 2)
! !

!PlatformPrimitives methodsFor: 'window and input'!
primWindowOpen
	"w h (points) title flags (1 hidden 2 resizable 4 highDensity) -> win"
	<vmPrimitive: 400 name: 'windowOpen'>
	| w h flags t r |
	(self args: 4) ifFalse: [^self fail].
	w := self intArg: 0.
	h := self intArg: 1.
	flags := self intArg: 3.
	t := self stringArg: 2.
	bad ifTrue: [
		libc free: t.
		^self fail].
	r := windows open: w asInt32 height: h asInt32 title: t flags: flags asInt32.
	libc free: t.
	self answerHandle: r
!
primWindowClose
	<vmPrimitive: 401 name: 'windowClose'>
	| w |
	(self args: 1) ifFalse: [^self fail].
	w := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (windows close: w asInt32)
!
primWindowSize
	"win -> {w. h} in points"
	<vmPrimitive: 402 name: 'windowSize'>
	| win w h ok |
	(self args: 1) ifFalse: [^self fail].
	win := self intArg: 0.
	bad ifTrue: [^self fail].
	w := self local: 'int'.
	h := self local: 'int'.
	ok := windows size: win asInt32 width: w height: h.
	self answerPair: ok first: w value second: h value
!
primWindowPixelSize
	"win -> {w. h} in pixels"
	<vmPrimitive: 403 name: 'windowPixelSize'>
	| win w h ok |
	(self args: 1) ifFalse: [^self fail].
	win := self intArg: 0.
	bad ifTrue: [^self fail].
	w := self local: 'int'.
	h := self local: 'int'.
	ok := windows pixelSize: win asInt32 width: w height: h.
	self answerPair: ok first: w value second: h value
!
primWindowDisplayScale
	"win -> Float"
	<vmPrimitive: 404 name: 'windowDisplayScale'>
	| w |
	(self args: 1) ifFalse: [^self fail].
	w := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerNonNegative: (windows displayScale: w asInt32)
!
primWindowSetTitle
	"win title"
	<vmPrimitive: 405 name: 'windowSetTitle'>
	| w t ok |
	(self args: 2) ifFalse: [^self fail].
	w := self intArg: 0.
	t := self stringArg: 1.
	ok := bad not and: [windows setTitle: w asInt32 title: t].
	libc free: t.
	self answerOk: ok
!
primWindowShow
	<vmPrimitive: 406 name: 'windowShow'>
	| w |
	(self args: 1) ifFalse: [^self fail].
	w := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (windows show: w asInt32 visible: true)
!
primWindowHide
	<vmPrimitive: 407 name: 'windowHide'>
	| w |
	(self args: 1) ifFalse: [^self fail].
	w := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (windows show: w asInt32 visible: false)
!
primWindowRefreshRate
	"win -> Float Hz (0 unknown)"
	<vmPrimitive: 408 name: 'windowRefreshRate'>
	| w |
	(self args: 1) ifFalse: [^self fail].
	w := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerNonNegative: (windows refreshRate: w asInt32)
!
primSetCursor
	"kind (see PlatformWindows>>setCursor:)"
	<vmPrimitive: 409 name: 'setCursor'>
	| k |
	(self args: 1) ifFalse: [^self fail].
	k := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (windows setCursor: k asInt32)
!
primClipboardGet
	"-> String"
	<vmPrimitive: 410 name: 'clipboardGet'>
	(self args: 0) ifFalse: [^self fail].
	self answerString: windows clipboardGet
!
primClipboardSet
	"string"
	<vmPrimitive: 411 name: 'clipboardSet'>
	| s ok |
	(self args: 1) ifFalse: [^self fail].
	s := self stringArg: 0.
	ok := bad not and: [windows clipboardSet: s].
	libc free: s.
	self answerOk: ok
!
isEventArray: a
	^(self isPtr: a) and: [(self formatOf: a) = F_VAR and: [(self numSlots: a) >= 8 and: [(self isImmutable: a) not]]]
!
primNextEvent
	"8-slot Array -> it, filled, or nil"
	<vmPrimitive: 412 name: 'nextEvent'>
	| e a v p |
	(self args: 1) ifFalse: [^self fail].
	(self isEventArray: (self arg: 0)) ifFalse: [^self fail].
	e := self local: 'pf_event'.
	(events next: e) ifFalse: [^self answer: memory nilOop].
	a := self local: 'oop'.
	a value: (self arg: 0).
	memory pushRoot: a.
	self storeRef: a value at: 0 put: (self intOop: e type).
	self storeRef: a value at: 1 put: (self intOop: e timeMs).
	v := memory floatOop: e x.
	self storeRef: a value at: 2 put: v.
	v := memory floatOop: e y.
	self storeRef: a value at: 3 put: v.
	self storeRef: a value at: 4 put: (self intOop: e key).
	self storeRef: a value at: 5 put: (self intOop: e mods).
	v := memory nilOop.
	e xkind = PF_X_INT ifTrue: [v := self intOop: e ival].
	e xkind = PF_X_BOOL ifTrue: [v := self bool: e ival ~= 0].
	e xkind = PF_X_TEXT ifTrue: [v := memory stringFromUtf8: e text size: (libc strlen: e text)].
	e xkind = PF_X_POINT ifTrue: [
		p := self local: 'oop'.
		p value: (memory allocSlots: (memory special: SO_POINT) count: 0).
		memory pushRoot: p.
		v := memory floatOop: e dx.
		self storeRef: p value at: 0 put: v.
		v := memory floatOop: e dy.
		self storeRef: p value at: 1 put: v.
		memory popRoot.
		v := p value].
	self storeRef: a value at: 6 put: v.
	self storeRef: a value at: 7 put: (e window ~= 0 ifTrue: [self intOop: e window] ifFalse: [memory nilOop]).
	memory popRoot.
	libc free: e text.
	self answer: a value
!
primInjectEvent
	"8-slot Array"
	<vmPrimitive: 413 name: 'injectEvent'>
	| a e o ok |
	(self args: 1) ifFalse: [^self fail].
	a := self arg: 0.
	((self isPtr: a) and: [(self formatOf: a) = F_VAR and: [(self numSlots: a) >= 8]]) ifFalse: [^self fail].
	e := self local: 'pf_event'.
	o := self loadRef: a at: 0.
	ok := (self isInt: o) and: [(self intVal: o) > 0].
	ok ifTrue: [e type: (self intVal: o) asInt32].
	o := self loadRef: a at: 1.
	e timeMs: ((self isInt: o) ifTrue: [self intVal: o] ifFalse: [common nowMs]).
	ok := ok and: [(self numberOf: (self loadRef: a at: 2) into: (e fieldAddress: #x))
		and: [self numberOf: (self loadRef: a at: 3) into: (e fieldAddress: #y)]].
	o := self loadRef: a at: 4.
	e key: ((self isInt: o) ifTrue: [self intVal: o] ifFalse: [0]).
	o := self loadRef: a at: 5.
	e mods: ((self isInt: o) ifTrue: [(self intVal: o) asInt32] ifFalse: [0]).
	o := self loadRef: a at: 7.
	e window: ((self isInt: o) ifTrue: [(self intVal: o) asInt32] ifFalse: [0]).
	ok := ok and: [self textOrDelta: (self loadRef: a at: 6) into: e].
	ok ifTrue: [events push: e].
	libc free: e text.
	ok ifFalse: [^self fail].
	scheduler requestInterruptCheck.
	self answerSelf
!
textOrDelta: o into: e
	"Set the textOrDelta of e from o: nil, a SmallInteger, a Boolean, a Point (or a pair) of numbers, or a String (malloc'd UTF-8); answer whether o is one."
	<c: 'bool text_or_delta(oop o, pf_event *e)'>
	o = memory nilOop ifTrue: [
		e xkind: PF_X_NIL.
		^true].
	(self isInt: o) ifTrue: [
		e xkind: PF_X_INT.
		e ival: (self intVal: o).
		^true].
	(o = memory trueOop or: [o = memory falseOop]) ifTrue: [
		e xkind: PF_X_BOOL.
		e ival: (o = memory trueOop ifTrue: [1] ifFalse: [0]).
		^true].
	((self isPtr: o) and: [((memory classOf: o) = (memory special: SO_POINT) and: [(self numSlots: o) >= 2])
			or: [(self formatOf: o) = F_VAR and: [(self numSlots: o) = 2]]]) ifTrue: [
		e xkind: PF_X_POINT.
		^(self numberOf: (self loadRef: o at: 0) into: (e fieldAddress: #dx))
			and: [self numberOf: (self loadRef: o at: 1) into: (e fieldAddress: #dy)]].
	(self isText: o) ifTrue: [
		e xkind: PF_X_TEXT.
		^(e text: (memory utf8Of: o)) notNull].
	^false
!
primInputSemaphore
	"external semaphore index (0 = none)"
	<vmPrimitive: 414 name: 'inputSemaphore'>
	| i |
	(self args: 1) ifFalse: [^self fail].
	i := self intArg: 0.
	bad ifTrue: [^self fail].
	events setSemaphore: i asInt32.
	self answerSelf
!
primPlatformLastError
	"-> String"
	<vmPrimitive: 415 name: 'platformLastError'>
	| e |
	(self args: 0) ifFalse: [^self fail].
	e := common lastErrorString.
	self answer: (memory stringFromUtf8: e size: (libc strlen: e))
!
primVsyncSemaphore
	"external semaphore index signaled per display refresh (0 = stop)"
	<vmPrimitive: 416 name: 'vsyncSemaphore'>
	| i |
	(self args: 1) ifFalse: [^self fail].
	i := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (vsync semaphore: i asInt32)
!
primPlatformHandleCounts
	"-> live handles {files. sockets. windows. gpuDevices. shaders. pipelines. textures. samplers. buffers. fences. ptys}"
	<vmPrimitive: 417 name: 'platformHandleCounts'>
	| v |
	v := self local: 'int64_t[PF_HANDLE_COUNTS]'.
	common handleCounts: v.
	self answer: (self arrayOf: v count: PF_HANDLE_COUNTS)
!
primDroppedEvents
	"-> events dropped because the event queue was full (since startup)"
	<vmPrimitive: 418 name: 'droppedEvents'>
	(self args: 0) ifFalse: [^self fail].
	self answer: (memory int64Oop: events dropped)
! !

!PlatformPrimitives methodsFor: 'GPU'!
primGpuCreateDevice
	"debug (Boolean) -> dev"
	<vmPrimitive: 430 name: 'gpuCreateDevice'>
	| d |
	(self args: 1) ifFalse: [^self fail].
	d := self boolArg: 0.
	bad ifTrue: [^self fail].
	self answerHandle: (gpu createDevice: d)
!
primGpuClaimWindow
	"dev win"
	<vmPrimitive: 431 name: 'gpuClaimWindow'>
	| d w |
	(self args: 2) ifFalse: [^self fail].
	d := self intArg: 0.
	w := self intArg: 1.
	bad ifTrue: [^self fail].
	self answerOk: (gpu claimWindow: d asInt32 window: w asInt32)
!
primGpuSwapchainFormat
	"dev win -> format"
	<vmPrimitive: 432 name: 'gpuSwapchainFormat'>
	| d w |
	(self args: 2) ifFalse: [^self fail].
	d := self intArg: 0.
	w := self intArg: 1.
	bad ifTrue: [^self fail].
	self answerHandle: (gpu swapchainFormat: d asInt32 window: w asInt32)
!
primGpuShaderLanguage
	"dev -> 'msl' or 'glsl': what gpuCreateShader takes"
	<vmPrimitive: 460 name: 'gpuShaderLanguage'>
	| d l |
	(self args: 1) ifFalse: [^self fail].
	d := self intArg: 0.
	bad ifTrue: [^self fail].
	l := gpu shaderLanguage: d asInt32.
	l isNull ifTrue: [^self fail].
	self answer: (memory stringFromUtf8: l size: (libc strlen: l))
!
primGpuCreateShader
	"dev source (in the device's shaderLanguage) entry stage samplers uniformBuffers storageBuffers storageTextures -> shader"
	<vmPrimitive: 433 name: 'gpuCreateShader'>
	| d stage ns nu nsb nst src entry h |
	(self args: 8) ifFalse: [^self fail].
	d := self intArg: 0.
	stage := self intArg: 3.
	ns := self intArg: 4.
	nu := self intArg: 5.
	nsb := self intArg: 6.
	nst := self intArg: 7.
	src := self stringArg: 1.
	entry := self stringArg: 2.
	h := bad
		ifTrue: [0]
		ifFalse: [gpu createShader: d asInt32 source: src entry: entry stage: stage asInt32 samplers: ns asInt32
			uniformBuffers: nu asInt32 storageBuffers: nsb asInt32 storageTextures: nst asInt32].
	libc free: src.
	libc free: entry.
	bad ifTrue: [^self fail].
	self answerHandle: h
!
primGpuCreatePipeline
	"dev vs fs stride attrs {fmt. off. ...} primitive blend targetFormat -> pipeline"
	<vmPrimitive: 434 name: 'gpuCreatePipeline'>
	| d vs fs stride prim blend fmt attrs va n f off |
	(self args: 8) ifFalse: [^self fail].
	d := self intArg: 0.
	vs := self intArg: 1.
	fs := self intArg: 2.
	stride := self intArg: 3.
	prim := self intArg: 5.
	blend := self intArg: 6.
	fmt := self intArg: 7.
	attrs := self arg: 4.
	bad ifTrue: [^self fail].
	((self isPtr: attrs) and: [(self formatOf: attrs) = F_VAR and: [((self numSlots: attrs) bitAnd: 1) = 0 and: [(self numSlots: attrs) <= 32]]]) ifFalse: [^self fail].
	va := self local: 'pf_vattr[16]'.
	n := ((self numSlots: attrs) quo: 2) asInt32.
	0 to: n - 1 do: [:i |
		f := self loadRef: attrs at: 2 * i.
		off := self loadRef: attrs at: (2 * i) + 1.
		((self isInt: f) and: [self isInt: off]) ifFalse: [^self fail].
		(va at: i) format: (self intVal: f) asInt32.
		(va at: i) offset: (self intVal: off) asInt32].
	self answerHandle: (gpu createPipeline: d asInt32 vertexShader: vs asInt32 fragmentShader: fs asInt32 stride: stride asInt32
		attributes: va count: n primitive: prim asInt32 blend: blend asInt32 targetFormat: fmt asInt32)
!
primGpuCreateTexture
	"dev w h format usage -> tex"
	<vmPrimitive: 435 name: 'gpuCreateTexture'>
	| d w h f u |
	(self args: 5) ifFalse: [^self fail].
	d := self intArg: 0.
	w := self intArg: 1.
	h := self intArg: 2.
	f := self intArg: 3.
	u := self intArg: 4.
	bad ifTrue: [^self fail].
	self answerHandle: (gpu createTexture: d asInt32 width: w asInt32 height: h asInt32 format: f asInt32 usage: u asInt32)
!
primGpuCreateSampler
	"dev linear (Boolean) repeat (Boolean) -> sampler"
	<vmPrimitive: 436 name: 'gpuCreateSampler'>
	| d linear repeat |
	(self args: 3) ifFalse: [^self fail].
	d := self intArg: 0.
	linear := self boolArg: 1.
	repeat := self boolArg: 2.
	bad ifTrue: [^self fail].
	self answerHandle: (gpu createSampler: d asInt32 linear: linear repeat: repeat)
!
primGpuCreateBuffer
	"dev usage (1 vertex) size -> buf"
	<vmPrimitive: 437 name: 'gpuCreateBuffer'>
	| d u n |
	(self args: 3) ifFalse: [^self fail].
	d := self intArg: 0.
	u := self intArg: 1.
	n := self intArg: 2.
	bad ifTrue: [^self fail].
	(n <= 0 or: [n > 16rFFFFFFFF]) ifTrue: [^self fail].
	self answerHandle: (gpu createBuffer: d asInt32 usage: u asInt32 size: n asUInt32)
!
primGpuRelease
	"handle"
	<vmPrimitive: 438 name: 'gpuRelease'>
	| h |
	(self args: 1) ifFalse: [^self fail].
	h := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (gpu releaseHandle: h asInt32)
!
primGpuUploadBuffer
	"buf bytes byteCount dstOffset"
	<vmPrimitive: 439 name: 'gpuUploadBuffer'>
	| b n off len p |
	(self args: 4) ifFalse: [^self fail].
	b := self intArg: 0.
	n := self intArg: 2.
	off := self intArg: 3.
	bad ifTrue: [^self fail].
	len := self local: 'size_t'.
	p := self bytesOf: (self arg: 1) size: len writable: false.
	(p isNull or: [n < 0 or: [n asUInt64 > len value or: [off < 0 or: [off > 16rFFFFFFFF]]]]) ifTrue: [^self fail].
	self answerOk: (gpu uploadBuffer: b asInt32 data: p count: n asUInt32 offset: off asUInt32)
!
primGpuUploadTexture
	"tex bytes x y w h bytesPerRow"
	<vmPrimitive: 440 name: 'gpuUploadTexture'>
	| t x y w h bpr len p |
	(self args: 7) ifFalse: [^self fail].
	t := self intArg: 0.
	x := self intArg: 2.
	y := self intArg: 3.
	w := self intArg: 4.
	h := self intArg: 5.
	bpr := self intArg: 6.
	bad ifTrue: [^self fail].
	len := self local: 'size_t'.
	p := self bytesOf: (self arg: 1) size: len writable: false.
	p isNull ifTrue: [^self fail].
	self answerOk: (gpu uploadTexture: t asInt32 data: p length: len value x: x asInt32 y: y asInt32 width: w asInt32 height: h asInt32 bytesPerRow: bpr asInt32)
!
primGpuAcquireCommandBuffer
	"dev -> cmd"
	<vmPrimitive: 441 name: 'gpuAcquireCommandBuffer'>
	| d |
	(self args: 1) ifFalse: [^self fail].
	d := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerHandle: (gpu acquireCommandBuffer: d asInt32)
!
primGpuAcquireSwapchain
	"cmd win -> {tex. w. h} or nil"
	<vmPrimitive: 442 name: 'gpuAcquireSwapchain'>
	| c win w h t v |
	(self args: 2) ifFalse: [^self fail].
	c := self intArg: 0.
	win := self intArg: 1.
	bad ifTrue: [^self fail].
	w := self local: 'int'.
	h := self local: 'int'.
	t := gpu acquireSwapchain: c asInt32 window: win asInt32 width: w height: h.
	t = 0 ifTrue: [
		^(common lastErrorString at: 0) ~= 0
			ifTrue: [self fail]
			ifFalse: [self answer: memory nilOop]].
	v := self local: 'int64_t[3]'.
	v at: 0 put: t.
	v at: 1 put: w value.
	v at: 2 put: h value.
	self answer: (self arrayOf: v count: 3)
!
primGpuBeginPass
	"cmd tex clear ({r. g. b. a} or nil = load) -> pass"
	<vmPrimitive: 443 name: 'gpuBeginPass'>
	| c t cl rgba d |
	(self args: 3) ifFalse: [^self fail].
	c := self intArg: 0.
	t := self intArg: 1.
	cl := self arg: 2.
	bad ifTrue: [^self fail].
	rgba := self local: 'float[4]'.
	d := self local: 'double'.
	cl ~= memory nilOop ifTrue: [
		((self isPtr: cl) and: [(self formatOf: cl) = F_VAR and: [(self numSlots: cl) = 4]]) ifFalse: [^self fail].
		0 to: 3 do: [:i |
			(self numberOf: (self loadRef: cl at: i) into: d) ifFalse: [^self fail].
			rgba at: i put: d value]].
	self answerHandle: (gpu beginPass: c asInt32 target: t asInt32 clear: (cl = memory nilOop ifTrue: [self null] ifFalse: [rgba]))
!
primGpuSetViewport
	"pass x y w h"
	<vmPrimitive: 444 name: 'gpuSetViewport'>
	| p x y w h |
	(self args: 5) ifFalse: [^self fail].
	p := self intArg: 0.
	x := self floatArg: 1.
	y := self floatArg: 2.
	w := self floatArg: 3.
	h := self floatArg: 4.
	bad ifTrue: [^self fail].
	self answerOk: (gpu setViewport: p asInt32 x: x y: y width: w height: h)
!
primGpuSetScissor
	"pass x y w h"
	<vmPrimitive: 445 name: 'gpuSetScissor'>
	| p x y w h |
	(self args: 5) ifFalse: [^self fail].
	p := self intArg: 0.
	x := self intArg: 1.
	y := self intArg: 2.
	w := self intArg: 3.
	h := self intArg: 4.
	bad ifTrue: [^self fail].
	self answerOk: (gpu setScissor: p asInt32 x: x asInt32 y: y asInt32 width: w asInt32 height: h asInt32)
!
primGpuBindPipeline
	"pass pipeline"
	<vmPrimitive: 446 name: 'gpuBindPipeline'>
	| p q |
	(self args: 2) ifFalse: [^self fail].
	p := self intArg: 0.
	q := self intArg: 1.
	bad ifTrue: [^self fail].
	self answerOk: (gpu bindPipeline: p asInt32 pipeline: q asInt32)
!
primGpuBindVertexBuffer
	"pass slot buf offset"
	<vmPrimitive: 447 name: 'gpuBindVertexBuffer'>
	| p s b off |
	(self args: 4) ifFalse: [^self fail].
	p := self intArg: 0.
	s := self intArg: 1.
	b := self intArg: 2.
	off := self intArg: 3.
	bad ifTrue: [^self fail].
	self answerOk: (gpu bindVertexBuffer: p asInt32 slot: s asInt32 buffer: b asInt32 offset: off asUInt32)
!
primGpuBindTexture
	"pass slot tex sampler"
	<vmPrimitive: 448 name: 'gpuBindTexture'>
	| p s t sm |
	(self args: 4) ifFalse: [^self fail].
	p := self intArg: 0.
	s := self intArg: 1.
	t := self intArg: 2.
	sm := self intArg: 3.
	bad ifTrue: [^self fail].
	self answerOk: (gpu bindTexture: p asInt32 slot: s asInt32 texture: t asInt32 sampler: sm asInt32)
!
primGpuPushUniforms
	"cmdOrPass stage slot bytes"
	<vmPrimitive: 449 name: 'gpuPushUniforms'>
	| c st sl len p |
	(self args: 4) ifFalse: [^self fail].
	c := self intArg: 0.
	st := self intArg: 1.
	sl := self intArg: 2.
	bad ifTrue: [^self fail].
	len := self local: 'size_t'.
	p := self bytesOf: (self arg: 3) size: len writable: false.
	p isNull ifTrue: [^self fail].
	self answerOk: (gpu pushUniforms: c asInt32 stage: st asInt32 slot: sl asInt32 data: p count: len value asUInt32)
!
primGpuDraw
	"pass vertexCount firstVertex"
	<vmPrimitive: 450 name: 'gpuDraw'>
	| p n f |
	(self args: 3) ifFalse: [^self fail].
	p := self intArg: 0.
	n := self intArg: 1.
	f := self intArg: 2.
	bad ifTrue: [^self fail].
	self answerOk: (gpu draw: p asInt32 vertices: n asInt32 first: f asInt32)
!
primGpuEndPass
	"pass"
	<vmPrimitive: 451 name: 'gpuEndPass'>
	| p |
	(self args: 1) ifFalse: [^self fail].
	p := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (gpu endPass: p asInt32)
!
primGpuBlit
	"cmd src {x. y. w. h} dst {x. y. w. h} linear"
	<vmPrimitive: 452 name: 'gpuBlit'>
	| c s d linear sr dr |
	(self args: 6) ifFalse: [^self fail].
	c := self intArg: 0.
	s := self intArg: 1.
	d := self intArg: 3.
	linear := self boolArg: 5.
	sr := self local: 'int[4]'.
	dr := self local: 'int[4]'.
	(bad or: [(self rect: (self arg: 2) into: sr) not or: [(self rect: (self arg: 4) into: dr) not]]) ifTrue: [^self fail].
	self answerOk: (gpu blit: c asInt32 source: s asInt32 rect: sr destination: d asInt32 rect: dr linear: linear)
!
primGpuSubmit
	"cmd wantFence -> fence or nil"
	<vmPrimitive: 453 name: 'gpuSubmit'>
	| c want ok f |
	(self args: 2) ifFalse: [^self fail].
	c := self intArg: 0.
	want := self boolArg: 1.
	bad ifTrue: [^self fail].
	ok := self local: 'bool'.
	f := gpu submit: c asInt32 fence: want ok: ok.
	ok value ifFalse: [^self fail].
	self answer: (f ~= 0 ifTrue: [self intOop: f] ifFalse: [memory nilOop])
!
primGpuWaitFence
	"fence"
	<vmPrimitive: 454 name: 'gpuWaitFence'>
	| f |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (gpu waitFence: f asInt32)
!
primGpuFenceDone
	"fence -> Boolean"
	<vmPrimitive: 455 name: 'gpuFenceDone'>
	| f r |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	r := gpu fenceDone: f asInt32.
	r < 0 ifTrue: [^self fail].
	self answerBool: r ~= 0
!
primGpuDownload
	"tex x y w h bytes -> bytes"
	<vmPrimitive: 456 name: 'gpuDownload'>
	| t x y w h buf len p |
	(self args: 6) ifFalse: [^self fail].
	t := self intArg: 0.
	x := self intArg: 1.
	y := self intArg: 2.
	w := self intArg: 3.
	h := self intArg: 4.
	bad ifTrue: [^self fail].
	buf := self arg: 5.
	len := self local: 'size_t'.
	p := self bytesOf: buf size: len writable: true.
	(p isNull or: [(gpu download: t asInt32 x: x asInt32 y: y asInt32 width: w asInt32 height: h asInt32 into: p length: len value) not]) ifTrue: [^self fail].
	self answer: buf
!
primGpuTextureSize
	"tex -> {w. h. format}"
	<vmPrimitive: 457 name: 'gpuTextureSize'>
	| t w h f v |
	(self args: 1) ifFalse: [^self fail].
	t := self intArg: 0.
	bad ifTrue: [^self fail].
	w := self local: 'int'.
	h := self local: 'int'.
	f := self local: 'int'.
	(gpu textureSize: t asInt32 width: w height: h format: f) ifFalse: [^self fail].
	v := self local: 'int64_t[3]'.
	v at: 0 put: w value.
	v at: 1 put: h value.
	v at: 2 put: f value.
	self answer: (self arrayOf: v count: 3)
!
primGpuWaitIdle
	"dev"
	<vmPrimitive: 458 name: 'gpuWaitIdle'>
	| d |
	(self args: 1) ifFalse: [^self fail].
	d := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (gpu waitIdle: d asInt32)
!
primGpuFenceElapsed
	"fence -> µs from submit to completion, or nil while pending"
	<vmPrimitive: 459 name: 'gpuFenceElapsed'>
	| f r |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	r := gpu fenceElapsed: f asInt32.
	r = -2 ifTrue: [^self fail].
	self answer: (r < 0 ifTrue: [memory nilOop] ifFalse: [self intOop: r])
! !

!PlatformPrimitives methodsFor: 'files and processes'!
pathOp: aBlock
	"A primitive of one path argument: aBlock answers whether the operation on the path (a C string) succeeded."
	| p ok |
	(self args: 1) ifFalse: [^self fail].
	p := self stringArg: 0.
	ok := bad not and: [aBlock value: p].
	libc free: p.
	self answerOk: ok
!
primFileOpen
	"path mode (0 read 1 readWrite 2 append 3 createTruncate) -> file"
	<vmPrimitive: 500 name: 'fileOpen'>
	| p m h |
	(self args: 2) ifFalse: [^self fail].
	p := self stringArg: 0.
	m := self intArg: 1.
	h := bad ifTrue: [0] ifFalse: [files open: p mode: m asInt32].
	libc free: p.
	self answerHandle: h
!
primFileClose
	"file"
	<vmPrimitive: 501 name: 'fileClose'>
	| f |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (files close: f asInt32)
!
primFileRead
	"file bytes start count -> count (0 = EOF)"
	<vmPrimitive: 502 name: 'fileRead'>
	| h n p |
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	p := self rangeArgs: true handle: h count: n.
	self answerSize: (p notNull ifTrue: [files read: h value asInt32 into: p count: n value asUInt64] ifFalse: [-1])
!
primFileWrite
	"file bytes start count -> count"
	<vmPrimitive: 503 name: 'fileWrite'>
	| h n p |
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	p := self rangeArgs: false handle: h count: n.
	self answerSize: (p notNull ifTrue: [files write: h value asInt32 bytes: p count: n value asUInt64] ifFalse: [-1])
!
primFileSize
	"file -> Integer"
	<vmPrimitive: 504 name: 'fileSize'>
	| f r |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	r := files size: f asInt32.
	r < 0 ifTrue: [^self fail].
	self answer: (memory int64Oop: r)
!
primFilePosition
	"file -> Integer (0-based)"
	<vmPrimitive: 505 name: 'filePosition'>
	| f r |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	r := files position: f asInt32.
	r < 0 ifTrue: [^self fail].
	self answer: (memory int64Oop: r)
!
primFileSeek
	"file position (0-based)"
	<vmPrimitive: 506 name: 'fileSeek'>
	| f pos |
	(self args: 2) ifFalse: [^self fail].
	f := self intArg: 0.
	pos := self intArg: 1.
	bad ifTrue: [^self fail].
	self answerOk: (pos >= 0 and: [files seek: f asInt32 to: pos])
!
primFileFlush
	"file"
	<vmPrimitive: 507 name: 'fileFlush'>
	| f |
	(self args: 1) ifFalse: [^self fail].
	f := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (files flush: f asInt32)
!
primFileDelete
	"path"
	<vmPrimitive: 508 name: 'fileDelete'>
	self pathOp: [:p | files delete: p]
!
primFileRename
	"from to"
	<vmPrimitive: 509 name: 'fileRename'>
	| a b ok |
	(self args: 2) ifFalse: [^self fail].
	a := self stringArg: 0.
	b := self stringArg: 1.
	ok := bad not and: [files rename: a to: b].
	libc free: a.
	libc free: b.
	self answerOk: ok
!
primFileStat
	"path -> {exists. isDirectory. size. mtimeMicroseconds}"
	<vmPrimitive: 510 name: 'fileStat'>
	| p st ok a v |
	(self args: 1) ifFalse: [^self fail].
	p := self stringArg: 0.
	st := self local: 'pf_stat'.
	ok := bad not and: [files stat: p into: st].
	libc free: p.
	ok ifFalse: [^self fail].
	a := self local: 'oop'.
	a value: (memory allocSlots: memory clsArray count: 4).
	memory pushRoot: a.
	self storeRef: a value at: 0 put: (self bool: st exists).
	self storeRef: a value at: 1 put: (self bool: st isDir).
	v := memory int64Oop: st fileSize.
	self storeRef: a value at: 2 put: v.
	v := memory int64Oop: st mtimeUs.
	self storeRef: a value at: 3 put: v.
	memory popRoot.
	self answer: a value
!
primDirEntries
	"path -> Array of Strings"
	<vmPrimitive: 511 name: 'dirEntries'>
	| p n v a s |
	(self args: 1) ifFalse: [^self fail].
	p := self stringArg: 0.
	n := self local: 'int'.
	v := bad ifTrue: [self cCoerce: self null to: 'char **'] ifFalse: [files dirEntries: p count: n].
	libc free: p.
	v isNull ifTrue: [^self fail].
	a := self local: 'oop'.
	a value: (memory allocSlots: memory clsArray count: n value asUInt32).
	memory pushRoot: a.
	0 to: n value - 1 do: [:i |
		s := memory stringFromUtf8: (v at: i) size: (libc strlen: (v at: i)).
		self storeRef: a value at: i put: s.
		libc free: (v at: i)].
	memory popRoot.
	libc free: v.
	self answer: a value
!
primDirCreate
	"path"
	<vmPrimitive: 512 name: 'dirCreate'>
	self pathOp: [:p | files dirCreate: p]
!
primCwd
	"-> String"
	<vmPrimitive: 513 name: 'cwd'>
	(self args: 0) ifFalse: [^self fail].
	self answerString: files cwd
!
primMkfifo
	"path"
	<vmPrimitive: 514 name: 'mkfifo'>
	self pathOp: [:p | files mkfifo: p]
!
primSpawnProcess
	"argv (Array of Strings, PATH lookup) -> pid"
	<vmPrimitive: 515 name: 'spawnProcess'>
	| argv pid |
	(self args: 1) ifFalse: [^self fail].
	argv := self stringVector: (self arg: 0) nonEmpty: true.
	argv isNull ifTrue: [^self fail].
	pid := files spawn: argv.
	self freeVector: argv.
	pid < 0 ifTrue: [^self fail].
	self answer: (self intOop: pid)
!
primExecProcess
	"argv (Array of Strings, PATH lookup): the VM's process runs argv instead; fails if it cannot"
	<vmPrimitive: 518 name: 'execProcess'>
	<notTryable>
	| argv |
	(self args: 1) ifFalse: [^self fail].
	argv := self stringVector: (self arg: 0) nonEmpty: true.
	argv isNull ifTrue: [^self fail].
	files exec: argv.
	self freeVector: argv.
	self fail
!
primProcessWait
	"pid block (Boolean) -> exit status or nil (running)"
	<vmPrimitive: 516 name: 'processWait'>
	| pid block st done |
	(self args: 2) ifFalse: [^self fail].
	pid := self intArg: 0.
	block := self boolArg: 1.
	bad ifTrue: [^self fail].
	st := self local: 'int'.
	done := self local: 'bool'.
	(files processWait: pid block: block status: st done: done) ifFalse: [^self fail].
	self answer: (done value ifTrue: [self intOop: st value] ifFalse: [memory nilOop])
! !

!PlatformPrimitives methodsFor: 'sockets'!
primSocketListen
	"host port backlog -> socket"
	<vmPrimitive: 540 name: 'socketListen'>
	| host port backlog h |
	(self args: 3) ifFalse: [^self fail].
	host := self stringArg: 0.
	port := self intArg: 1.
	backlog := self intArg: 2.
	h := bad ifTrue: [0] ifFalse: [sockets listen: host port: port asInt32 backlog: backlog asInt32].
	libc free: host.
	self answerHandle: h
!
primSocketConnect
	"host port -> socket"
	<vmPrimitive: 541 name: 'socketConnect'>
	| host port h |
	(self args: 2) ifFalse: [^self fail].
	host := self stringArg: 0.
	port := self intArg: 1.
	h := bad ifTrue: [0] ifFalse: [sockets connect: host port: port asInt32].
	libc free: host.
	self answerHandle: h
!
primSocketAccept
	"socket -> socket or nil"
	<vmPrimitive: 542 name: 'socketAccept'>
	| s wb h |
	(self args: 1) ifFalse: [^self fail].
	s := self intArg: 0.
	bad ifTrue: [^self fail].
	wb := self local: 'bool'.
	h := sockets accept: s asInt32 wouldBlock: wb.
	h ~= 0 ifTrue: [^self answer: (self intOop: h)].
	wb value ifTrue: [^self answer: memory nilOop].
	self fail
!
primSocketRecv
	"socket bytes start count -> count, 0 at EOF, nil would block"
	<vmPrimitive: 543 name: 'socketRecv'>
	| h n p |
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	p := self rangeArgs: true handle: h count: n.
	self answerCount: (p notNull ifTrue: [sockets recv: h value asInt32 into: p count: n value asUInt64] ifFalse: [-2])
!
primSocketSend
	"socket bytes start count -> count or nil"
	<vmPrimitive: 544 name: 'socketSend'>
	| h n p |
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	p := self rangeArgs: false handle: h count: n.
	self answerCount: (p notNull ifTrue: [sockets send: h value asInt32 bytes: p count: n value asUInt64] ifFalse: [-2])
!
primSocketClose
	"socket"
	<vmPrimitive: 545 name: 'socketClose'>
	| s |
	(self args: 1) ifFalse: [^self fail].
	s := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (sockets close: s asInt32)
!
primSocketSemaphore
	"socket readIndex [writeIndex]"
	<vmPrimitive: 546 name: 'socketSemaphore'>
	| s r w |
	bad := false.
	(self argCount = 2 or: [self argCount = 3]) ifFalse: [^self fail].
	s := self intArg: 0.
	r := self intArg: 1.
	w := self argCount = 3 ifTrue: [self intArg: 2] ifFalse: [0].
	bad ifTrue: [^self fail].
	self answerOk: (sockets semaphores: s asInt32 read: r asInt32 write: w asInt32)
!
primSocketLocalPort
	"socket -> port"
	<vmPrimitive: 547 name: 'socketLocalPort'>
	| s |
	(self args: 1) ifFalse: [^self fail].
	s := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerHandle: (sockets localPort: s asInt32)
! !

!PlatformPrimitives methodsFor: 'pseudo-terminals'!
primPtySpawn
	"argv (Array of Strings, PATH lookup) env (Array of 'K=V' or nil = inherit) cwd (or nil) rows cols -> {pty. pid}"
	<vmPrimitive: 560 name: 'ptySpawn'>
	<var: #envp type: 'char **'>
	<var: #cwd type: 'char *'>
	| argv envp cwd rows cols pid h v |
	(self args: 5) ifFalse: [^self fail].
	argv := self stringVector: (self arg: 0) nonEmpty: true.
	envp := self null.
	(self arg: 1) ~= memory nilOop ifTrue: [envp := self stringVector: (self arg: 1) nonEmpty: false].
	cwd := self null.
	(self arg: 2) ~= memory nilOop ifTrue: [cwd := self stringArg: 2].
	rows := self intArg: 3.
	cols := self intArg: 4.
	pid := self local: 'int64_t'.
	h := 0.
	(bad not and: [argv notNull and: [(envp notNull or: [(self arg: 1) = memory nilOop])
		and: [rows > 0 and: [cols > 0 and: [rows < 65536 and: [cols < 65536]]]]]]) ifTrue: [
			h := ptys spawn: argv environment: envp directory: cwd rows: rows asInt32 columns: cols asInt32 pid: pid].
	self freeVector: argv.
	self freeVector: envp.
	libc free: cwd.
	h <= 0 ifTrue: [^self fail].
	v := self local: 'int64_t[2]'.
	v at: 0 put: h.
	v at: 1 put: pid value.
	self answer: (self arrayOf: v count: 2)
!
primPtyRead
	"pty bytes start count -> count, 0 at EOF, nil would block"
	<vmPrimitive: 561 name: 'ptyRead'>
	| h n p |
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	p := self rangeArgs: true handle: h count: n.
	self answerCount: (p notNull ifTrue: [sockets ptyRead: h value asInt32 into: p count: n value asUInt64] ifFalse: [-2])
!
primPtyWrite
	"pty bytes start count -> count or nil"
	<vmPrimitive: 562 name: 'ptyWrite'>
	| h n p |
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	p := self rangeArgs: false handle: h count: n.
	self answerCount: (p notNull ifTrue: [sockets ptyWrite: h value asInt32 bytes: p count: n value asUInt64] ifFalse: [-2])
!
primPtyResize
	"pty rows cols"
	<vmPrimitive: 563 name: 'ptyResize'>
	| h rows cols |
	(self args: 3) ifFalse: [^self fail].
	h := self intArg: 0.
	rows := self intArg: 1.
	cols := self intArg: 2.
	bad ifTrue: [^self fail].
	self answerOk: (rows > 0 and: [cols > 0 and: [rows < 65536 and: [cols < 65536 and: [ptys resize: h asInt32 rows: rows asInt32 columns: cols asInt32]]]])
!
primPtySemaphore
	"pty readIndex [writeIndex]"
	<vmPrimitive: 564 name: 'ptySemaphore'>
	| h r w |
	bad := false.
	(self argCount = 2 or: [self argCount = 3]) ifFalse: [^self fail].
	h := self intArg: 0.
	r := self intArg: 1.
	w := self argCount = 3 ifTrue: [self intArg: 2] ifFalse: [0].
	bad ifTrue: [^self fail].
	self answerOk: (sockets ptySemaphores: h asInt32 read: r asInt32 write: w asInt32)
!
primPtyWait
	"pty block (Boolean) -> the child's exit status or nil (running)"
	<vmPrimitive: 565 name: 'ptyWait'>
	| h block st done |
	(self args: 2) ifFalse: [^self fail].
	h := self intArg: 0.
	block := self boolArg: 1.
	bad ifTrue: [^self fail].
	st := self local: 'int'.
	done := self local: 'bool'.
	(ptys wait: h asInt32 block: block status: st done: done) ifFalse: [^self fail].
	self answer: (done value ifTrue: [self intOop: st value] ifFalse: [memory nilOop])
!
primPtyForeground
	"pty -> its foreground process group"
	<vmPrimitive: 571 name: 'ptyForeground'>
	| h group |
	(self args: 1) ifFalse: [^self fail].
	h := self intArg: 0.
	bad ifTrue: [^self fail].
	group := ptys foreground: h asInt32.
	group < 0 ifTrue: [^self fail].
	self answer: (self intOop: group asInt64)
!
primPtyClose
	"pty (hangs up the child unless it ended)"
	<vmPrimitive: 566 name: 'ptyClose'>
	| h |
	(self args: 1) ifFalse: [^self fail].
	h := self intArg: 0.
	bad ifTrue: [^self fail].
	self answerOk: (ptys close: h asInt32)
! !
