VMPlatformModule subclass: #PlatformPrimitives
	instanceVariableNames: 'bad nic builtins'
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
	16 textEditing	0	String: the input method''s composition (x = its cursor, y = the length of its selected part, in characters; -1 if not set)
timeMs: platform monotonic ms (nil when injecting = now). windowId: window handle or nil.

Keycodes (SDL): printable keys are their lowercase character code (''a'' = 97 ... ''z'' = 122, ''0'' = 48, space = 32), return 13, escape 27, backspace 8, tab 9, delete 127, right 16r4000004F, left 16r40000050, down 16r40000051, up 16r40000052, home 16r4000004A, end 16r4000004D, pageUp 16r4000004B, pageDown 16r4000004E, insert 16r40000049, F1 16r4000003A ... F12 16r40000045, keypad enter 16r40000058, lshift 16r400000E1, lctrl 16r400000E0, lalt 16r400000E2, lcmd 16r400000E3.'!

!PlatformPrimitives class methodsFor: 'declaring'!
declarations
	^#((bad bool) (nic PlatformNic) (builtins Builtins))
! !

!PlatformPrimitives class methodsFor: 'adapter declarations'!
initialize
	PlatformPrimitiveAdapter install: self adapterGroups in: self
!
adapterGroups
	"See PlatformPrimitiveAdapter for the row format and expansion."
	^#(
		('window and input' (
			(401 windowClose windows close: ok ((w int32)))
			(404 windowDisplayScale windows displayScale: nonNegative ((w int32)) 'win -> Float')
			(419 windowSetTextInputArea windows setTextInputArea:x:y:width:height:cursor: ok ((w int32) (x int32) (y int32) (wd int32) (h int32) (c int32)) 'win x y w h cursor (points; cursor: x of the caret within the rectangle)')
			(406 windowShow windows show:visible: ok ((w int32) (true literal)))
			(407 windowHide windows show:visible: ok ((w int32) (false literal)))
			(408 windowRefreshRate windows refreshRate: nonNegative ((w int32)) 'win -> Float Hz (0 unknown)')
			(409 setCursor windows setCursor: ok ((k int32)) 'kind (see PlatformWindows>>setCursor:)')
			(414 inputSemaphore events setSemaphore: receiver ((i int32)) 'external semaphore index (0 = none)')
			(416 vsyncSemaphore vsync semaphore: ok ((i int32)) 'external semaphore index signaled per display refresh (0 = stop)')
		))
		('raw network interface' (
			(583 nicSemaphore nic frameSemaphore: ok ((i int32)) 'index: signaled once when a frame is waiting, re-armed by a nicReceive that finds none; 0 = none')
		))
		('pseudo-terminals' (
			(566 ptyClose ptys close: ok ((h int32)) 'pty (hangs up the child unless it ended)')
		))
		('machine' (
			(476 machineFree libc free: receiver ((a address)) 'address (of machineAllocate)')
		))
	)
! !

!PlatformPrimitives methodsFor: 'arguments'!
args: n
	"Start a primitive of n arguments: answer whether it has them."
	bad := false.
	^self argCount = n
!
intArg: i
	<function>
	| v |
	v := self local: 'int64_t'.
	(memory int64Of: (self arg: i) into: v) ifFalse: [bad := true].
	^v value
!
bytesOf: o size: n writable: writable
	"The raw bytes of a byte object or Bitmap, their count in n; NULL if o is none (or immutable and writable is wanted)."
	<function>
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
numberOf: o into: d
	<function>
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
	<function>
	| v |
	((self isPtr: r) and: [(self formatOf: r) = F_VAR and: [(self numSlots: r) = 4]]) ifFalse: [^false].
	0 to: 3 do: [:i |
		v := self loadRef: r at: i.
		(self isInt: v) ifFalse: [^false].
		out at: i put: (self intVal: v) asInt32].
	^true
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
arrayOf: v count: n
	"An Array of n SmallIntegers."
	<function>
	| a |
	a := memory allocSlots: memory clsArray count: n asUInt32.
	0 to: n - 1 do: [:i | self storeRef: a at: i put: (self intOop: (v at: i))].
	^a
! !

!PlatformPrimitives methodsFor: 'windows'!
primWindowSetPosition
	"win x y (points)"
	<vmPrimitive: 422 name: 'windowSetPosition'>
	| w x y |
	(self args: 3) ifFalse: [^self fail].
	w := self intArg: 0.
	x := self intArg: 1.
	y := self intArg: 2.
	bad ifTrue: [^self fail].
	self answerOk: (windows setPosition: w asInt32 x: x asInt32 y: y asInt32)
! !

!PlatformPrimitives methodsFor: 'GPU'!
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
! !

!PlatformPrimitives methodsFor: 'raw network interface'!
primNicOpen
	"bytes (at least 6) -> bytes, the interface's MAC address in the first 6"
	<vmPrimitive: 580 name: 'nicOpen'>
	| buf len p |
	(self args: 1) ifFalse: [^self fail].
	buf := self arg: 0.
	len := self local: 'size_t'.
	p := self bytesOf: buf size: len writable: true.
	(p isNull or: [len value < 6 or: [(nic open: p) not]]) ifTrue: [^self fail].
	self answer: buf
!
primNicSend
	"bytes count -> true, or false if the frame could not go (the transmit queue full)"
	<vmPrimitive: 581 name: 'nicSend'>
	| buf n len p |
	(self args: 2) ifFalse: [^self fail].
	buf := self arg: 0.
	n := self intArg: 1.
	len := self local: 'size_t'.
	p := self bytesOf: buf size: len writable: false.
	(bad or: [p isNull or: [n < 14 or: [n asUInt64 > len value]]]) ifTrue: [^self fail].
	self answer: ((nic send: p length: n) ifTrue: [memory trueOop] ifFalse: [memory falseOop])
!
primNicReceive
	"bytes -> the length of the next frame received into them, nil if none (arms the semaphore)"
	<vmPrimitive: 582 name: 'nicReceive'>
	| buf len p r |
	(self args: 1) ifFalse: [^self fail].
	buf := self arg: 0.
	len := self local: 'size_t'.
	p := self bytesOf: buf size: len writable: true.
	p isNull ifTrue: [^self fail].
	r := nic receive: p max: len value asInt64.
	r = 0 ifTrue: [^self answer: memory nilOop].
	self answerSize: r
!
primNicStatus
	"-> {frames received. sent. sends that failed (the transmit queue full). frames waiting}"
	<vmPrimitive: 584 name: 'nicStatus'>
	| v |
	(self args: 0) ifFalse: [^self fail].
	v := self local: 'int64_t[4]'.
	(nic counters: v) ifFalse: [^self fail].
	self answer: (self arrayOf: v count: 4)
! !

!PlatformPrimitives methodsFor: 'pseudo-terminals'!
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
! !

!PlatformPrimitives methodsFor: 'machine'!
wordOf: o into: w
	"A word of an Integer (two's complement if negative, at most 64 bits), nil (0) or a Boolean (1, 0)."
	<function>
	<var: #w type: 'uint64_t *'>
	<returns: 'bool'>
	| i |
	o = memory nilOop ifTrue: [
		w value: 0.
		^true].
	(o = memory trueOop or: [o = memory falseOop]) ifTrue: [
		w value: (o = memory trueOop ifTrue: [1] ifFalse: [0]).
		^true].
	(memory u64Of: o into: w) ifTrue: [^true].
	i := self local: 'int64_t'.
	(memory int64Of: o into: i) ifFalse: [^false].
	w value: i value asUInt64.
	^true
!
answerWord: w
	"w as a non-negative Integer."
	<function>
	<var: #w type: 'uint64_t'>
	w <= VM_INT_MAX asUInt64 ifTrue: [^self answer: (self intOop: w asInt64)].
	self answer: (memory largeIntFrom: w negative: false)
!
addressArg: i
	"The address of an Integer argument (not 0); NULL, and bad set, otherwise."
	<function>
	<returns: 'uint8_t *'>
	| w |
	w := self local: 'uint64_t'.
	((memory u64Of: (self arg: i) into: w) and: [w value ~= 0]) ifFalse: [
		bad := true.
		^self null].
	^self cCoerce: w value to: 'uint8_t *'
!
memoryArg: i offset: offset length: n writable: writable
	"Memory argument i: an Integer (an address) or a byte object or Bitmap (writable: not immutable), of which n bytes from offset are used (checked for an object); NULL, and bad set, if it is none or too small."
	<function>
	<var: #offset type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #writable type: 'bool'>
	<returns: 'uint8_t *'>
	| o len p |
	o := self arg: i.
	((self isInt: o) or: [(self isPtr: o) and: [(memory classOf: o) = (memory special: SO_LARGEPOS)]]) ifTrue: [
		p := self addressArg: i.
		^p isNull ifTrue: [p] ifFalse: [p + offset]].
	len := self local: 'size_t'.
	p := self bytesOf: o size: len writable: writable.
	(p isNull or: [offset < 0 or: [n < 0 or: [(offset + n) asUInt64 > len value]]]) ifTrue: [
		bad := true.
		^self null].
	^p + offset
!
primMachineSystemTable
	"-> the address of the firmware's system table; fails without a firmware"
	<vmPrimitive: 470 name: 'machineSystemTable'>
	| t |
	(self args: 0) ifFalse: [^self fail].
	t := machine firmwareSystemTable.
	t = 0 ifTrue: [^self fail].
	self answerWord: t
!
primMachineCall
	"fn [arg ...] (up to 10 words: Integers, nil 0, Booleans 1 and 0) -> the word the firmware function at the address fn answers, called in the firmware's convention (ms_abi on x86-64); fails without a firmware"
	<vmPrimitive: 471 name: 'machineCall'>
	| n fn args ok r |
	n := self argCount - 1.
	(n < 0 or: [n > 10]) ifTrue: [^self fail].
	fn := self local: 'uint64_t'.
	args := self local: 'uint64_t[10]'.
	(self wordOf: (self arg: 0) into: fn) ifFalse: [^self fail].
	fn value = 0 ifTrue: [^self fail].
	1 to: n do: [:i | (self wordOf: (self arg: i) into: args + (i - 1)) ifFalse: [^self fail]].
	ok := self local: 'bool'.
	r := machine callFirmware: fn value arguments: args count: n asInt32 ok: ok.
	ok value ifFalse: [^self fail].
	self answerWord: r
!
primMachineRead
	"address size (1, 2, 4 or 8) -> the unsigned Integer there"
	<vmPrimitive: 472 name: 'machineRead'>
	| a n |
	(self args: 2) ifFalse: [^self fail].
	a := self addressArg: 0.
	n := self intArg: 1.
	bad ifTrue: [^self fail].
	n = 1 ifTrue: [^self answerWord: (self uint8At: a) asUInt64].
	n = 2 ifTrue: [^self answerWord: (self uint16At: a) asUInt64].
	n = 4 ifTrue: [^self answerWord: (self uint32At: a) asUInt64].
	n = 8 ifTrue: [^self answerWord: (self uint64At: a)].
	self fail
!
primMachineWrite
	"address size (1, 2, 4 or 8) value (an Integer: its low size bytes)"
	<vmPrimitive: 473 name: 'machineWrite'>
	| a n w |
	(self args: 3) ifFalse: [^self fail].
	a := self addressArg: 0.
	n := self intArg: 1.
	w := self local: 'uint64_t'.
	(bad or: [(self wordOf: (self arg: 2) into: w) not]) ifTrue: [^self fail].
	n = 1 ifTrue: [
		self uint8At: a put: w value asUInt8.
		^self answerSelf].
	n = 2 ifTrue: [
		self uint16At: a put: w value asUInt16.
		^self answerSelf].
	n = 4 ifTrue: [
		self uint32At: a put: w value asUInt32.
		^self answerSelf].
	n = 8 ifTrue: [
		self uint64At: a put: w value.
		^self answerSelf].
	self fail
!
primMachineCopy
	"count src srcOffset dst dstOffset: count bytes (they may overlap); src and dst are addresses or byte objects (Bitmaps), the offsets 0-based"
	<vmPrimitive: 474 name: 'machineCopy'>
	| n s d |
	(self args: 5) ifFalse: [^self fail].
	n := self intArg: 0.
	(bad or: [n < 0]) ifTrue: [^self fail].
	s := self memoryArg: 1 offset: (self intArg: 2) length: n writable: false.
	d := self memoryArg: 3 offset: (self intArg: 4) length: n writable: true.
	bad ifTrue: [^self fail].
	n > 0 ifTrue: [libc memmove: d from: s size: n asUInt64].
	self answerSelf
!
primMachineAllocate
	"size -> the address of size zeroed bytes outside the object heap, which never move (on UEFI the firmware's pool: physical memory, which a device reads at that address); free them with machineFree"
	<vmPrimitive: 475 name: 'machineAllocate'>
	| n p |
	(self args: 1) ifFalse: [^self fail].
	n := self intArg: 0.
	(bad or: [n <= 0 or: [n > 16r1000000000]]) ifTrue: [^self fail].
	p := libc calloc: n asUInt64 size: 1.
	p isNull ifTrue: [^self fail].
	self answerWord: (self cCoerce: p to: 'uint64_t')
!
primMachineBarrier
	"A full memory barrier (the compiler's and the CPU's): a device sees the stores before it before those after it."
	<vmPrimitive: 477 name: 'machineBarrier'>
	builtins memoryBarrier.
	self answerSelf
!
primMachineWatch
	"event index: signal external semaphore index whenever the firmware event at the address event is signaled (the VM's wait wakes for it); index 0 stops; fails without a firmware"
	<vmPrimitive: 478 name: 'machineWatch'>
	| e i |
	(self args: 2) ifFalse: [^self fail].
	e := self local: 'uint64_t'.
	i := self intArg: 1.
	(bad or: [(memory u64Of: (self arg: 0) into: e) not or: [e value = 0 or: [i < 0 or: [i > 16r7FFFFFFF]]]]) ifTrue: [^self fail].
	self answerOk: (machine watchEvent: e value semaphore: i asInt32)
! !

!PlatformPrimitives methodsFor: 'raster'!
slot: a at: i
	"SmallInteger slot i of a (bad set if it is none)."
	<function>
	| o |
	o := self loadRef: a at: i.
	(self isInt: o) ifFalse: [
		bad := true.
		^0].
	^self intVal: o
!
floatSlot: a at: i
	<function>
	<returns: 'double'>
	| d |
	d := self local: 'double'.
	(self numberOf: (self loadRef: a at: i) into: d) ifFalse: [bad := true].
	^d value
!
pointerSlot: a at: i
	"An address slot (an Integer; 0 is NULL)."
	<function>
	<returns: 'uint8_t *'>
	| w |
	w := self local: 'uint64_t'.
	(memory u64Of: (self loadRef: a at: i) into: w) ifFalse: [bad := true].
	^self cCoerce: w value to: 'uint8_t *'
!
isFormat: f
	^f >= PF_TEX_R8 and: [f <= PF_TEX_BGRA8]
!
isSide: n
	^n > 0 and: [n <= 65536]
!
surface: a into: s
	"{address. width. height. format ...} into the target fields of s."
	<function>
	<var: #s type: 'RasterState *'>
	<returns: 'bool'>
	((self isPtr: a) and: [(self formatOf: a) = F_VAR and: [(self numSlots: a) >= 4]]) ifFalse: [^false].
	s pixels: (self pointerSlot: a at: 0).
	s width: (self slot: a at: 1).
	s height: (self slot: a at: 2).
	s format: (self slot: a at: 3) asInt32.
	^bad not and: [s pixels notNull and: [(self isSide: s width) and: [(self isSide: s height) and: [self isFormat: s format]]]]
!
primRasterDraw
	"state vertices first count: the Renderer's vertices first .. first + count - 1 (40 bytes each) at the address vertices, drawn by its uber-shader. state: {target. width. height. format. blend. scissorX. scissorY. scissorW. scissorH. viewportX. viewportY. viewportW. viewportH. viewSizeX. viewSizeY. translateX. translateY. texture (0: none). textureWidth. textureHeight. textureFormat. linear. repeat}, addresses, pixels and codes as the gpu primitives take them (RasterState)"
	<vmPrimitive: 480 name: 'rasterDraw'>
	| a st v first n |
	(self args: 4) ifFalse: [^self fail].
	a := self arg: 0.
	((self isPtr: a) and: [(self formatOf: a) = F_VAR and: [(self numSlots: a) = 23]]) ifFalse: [^self fail].
	st := self local: 'RasterState'.
	(self surface: a into: st) ifFalse: [^self fail].
	st blend: (self slot: a at: 4) asInt32.
	st scissorX: (self slot: a at: 5).
	st scissorY: (self slot: a at: 6).
	st scissorW: (self slot: a at: 7).
	st scissorH: (self slot: a at: 8).
	st viewportX: (self floatSlot: a at: 9).
	st viewportY: (self floatSlot: a at: 10).
	st viewportW: (self floatSlot: a at: 11).
	st viewportH: (self floatSlot: a at: 12).
	st viewSizeX: (self floatSlot: a at: 13).
	st viewSizeY: (self floatSlot: a at: 14).
	st translateX: (self floatSlot: a at: 15).
	st translateY: (self floatSlot: a at: 16).
	st texture: (self pointerSlot: a at: 17).
	st textureWidth: (self slot: a at: 18).
	st textureHeight: (self slot: a at: 19).
	st textureFormat: (self slot: a at: 20) asInt32.
	st linear: (self loadRef: a at: 21) = memory trueOop.
	st wrap: (self loadRef: a at: 22) = memory trueOop.
	v := self addressArg: 1.
	first := self intArg: 2.
	n := self intArg: 3.
	(bad or: [st blend < PF_BLEND_NONE or: [st blend > PF_BLEND_PREMULTIPLIED or: [first < 0 or: [n < 0]]]]) ifTrue: [^self fail].
	(st texture notNull and: [(self isSide: st textureWidth) not or: [(self isSide: st textureHeight) not or: [(self isFormat: st textureFormat) not]]]) ifTrue: [^self fail].
	raster rasterize: st vertices: v first: first count: n.
	self answerSelf
!
primRasterFill
	"address count bytesPerPixel (1 or 4) value: count pixels set to value"
	<vmPrimitive: 481 name: 'rasterFill'>
	| p n bpp v |
	(self args: 4) ifFalse: [^self fail].
	p := self addressArg: 0.
	n := self intArg: 1.
	bpp := self intArg: 2.
	v := self intArg: 3.
	(bad or: [n < 0 or: [(bpp = 1 or: [bpp = 4]) not or: [v < 0 or: [v > 16rFFFFFFFF]]]]) ifTrue: [^self fail].
	raster fill: p count: n bytesPerPixel: bpp asInt32 value: v asUInt32.
	self answerSelf
!
primRasterBlit
	"src {x. y. w. h} dst {x. y. w. h} linear: src and dst are {address. width. height. format}; as gpuBlit does"
	<vmPrimitive: 482 name: 'rasterBlit'>
	| s d sr dr r v |
	(self args: 5) ifFalse: [^self fail].
	bad := false.
	s := self local: 'RasterState'.
	d := self local: 'RasterState'.
	sr := self local: 'int64_t[4]'.
	dr := self local: 'int64_t[4]'.
	r := self local: 'int[4]'.
	((self surface: (self arg: 0) into: s) and: [self surface: (self arg: 2) into: d]) ifFalse: [^self fail].
	(self rect: (self arg: 1) into: r) ifFalse: [^self fail].
	0 to: 3 do: [:i | sr at: i put: (r at: i) asInt64].
	(self rect: (self arg: 3) into: r) ifFalse: [^self fail].
	0 to: 3 do: [:i | dr at: i put: (r at: i) asInt64].
	v := self arg: 4.
	(v = memory trueOop or: [v = memory falseOop]) ifFalse: [^self fail].
	raster blitPixels: s pixels width: s width height: s height format: s format rect: sr
		to: d pixels width: d width height: d height format: d format rect: dr linear: v = memory trueOop.
	self answerSelf
!
primRasterCopy
	"dst dstStride src srcStride width height bytesPerPixel mode: rows of pixels of 1 or 4 bytes; dst and src are addresses or byte objects (Bitmaps); mode bit 1 swaps red and blue, bit 2 copies only the pixels whose alpha is not 0 (4-byte pixels)"
	<vmPrimitive: 483 name: 'rasterCopy'>
	| ds ss w h bpp mode d s |
	(self args: 8) ifFalse: [^self fail].
	ds := self intArg: 1.
	ss := self intArg: 3.
	w := self intArg: 4.
	h := self intArg: 5.
	bpp := self intArg: 6.
	mode := self intArg: 7.
	(bad or: [w < 0 or: [h < 0 or: [(bpp = 1 or: [bpp = 4]) not or: [mode < 0 or: [mode > 3 or: [ds < (w * bpp) or: [ss < (w * bpp)]]]]]]]) ifTrue: [^self fail].
	(w = 0 or: [h = 0]) ifTrue: [^self answerSelf].
	d := self memoryArg: 0 offset: 0 length: ((h - 1) * ds) + (w * bpp) writable: true.
	s := self memoryArg: 2 offset: 0 length: ((h - 1) * ss) + (w * bpp) writable: false.
	bad ifTrue: [^self fail].
	raster copy: d stride: ds from: s stride: ss width: w height: h bytesPerPixel: bpp mode: mode.
	self answerSelf
! !
