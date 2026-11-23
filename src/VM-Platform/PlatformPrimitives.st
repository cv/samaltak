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
			(402 windowSize windows size:width:height: pair ((win int32) (w outInt) (h outInt)) 'win -> {w. h} in points')
			(403 windowPixelSize windows pixelSize:width:height: pair ((win int32) (w outInt) (h outInt)) 'win -> {w. h} in pixels')
			(404 windowDisplayScale windows displayScale: nonNegative ((w int32)) 'win -> Float')
			(405 windowSetTitle windows setTitle:title: ok ((w int32) (t string)) 'win title')
			(419 windowSetTextInputArea windows setTextInputArea:x:y:width:height:cursor: ok ((w int32) (x int32) (y int32) (wd int32) (h int32) (c int32)) 'win x y w h cursor (points; cursor: x of the caret within the rectangle)')
			(406 windowShow windows show:visible: ok ((w int32) (true literal)))
			(407 windowHide windows show:visible: ok ((w int32) (false literal)))
			(408 windowRefreshRate windows refreshRate: nonNegative ((w int32)) 'win -> Float Hz (0 unknown)')
			(409 setCursor windows setCursor: ok ((k int32)) 'kind (see PlatformWindows>>setCursor:)')
			(410 clipboardGet windows clipboardGet string () '-> String')
			(411 clipboardSet windows clipboardSet: ok ((s string)) 'string')
			(414 inputSemaphore events setSemaphore: receiver ((i int32)) 'external semaphore index (0 = none)')
			(416 vsyncSemaphore vsync semaphore: ok ((i int32)) 'external semaphore index signaled per display refresh (0 = stop)')
			(418 droppedEvents events dropped int64 () '-> events dropped because the event queue was full (since startup)')
		))
		('GPU' (
			(430 gpuCreateDevice gpu createDevice: handle ((d bool)) 'debug (Boolean) -> dev')
			(431 gpuClaimWindow gpu claimWindow:window: ok ((d int32) (w int32)) 'dev win')
			(432 gpuSwapchainFormat gpu swapchainFormat:window: handle ((d int32) (w int32)) 'dev win -> format')
			(435 gpuCreateTexture gpu createTexture:width:height:format:usage: handle ((d int32) (w int32) (h int32) (f int32) (u int32)) 'dev w h format usage -> tex')
			(436 gpuCreateSampler gpu createSampler:linear:repeat: handle ((d int32) (linear bool) (repeat bool)) 'dev linear (Boolean) repeat (Boolean) -> sampler')
			(438 gpuRelease gpu releaseHandle: ok ((h int32)) 'handle')
			(441 gpuAcquireCommandBuffer gpu acquireCommandBuffer: handle ((d int32)) 'dev -> cmd')
			(444 gpuSetViewport gpu setViewport:x:y:width:height: ok ((p int32) (x float) (y float) (w float) (h float)) 'pass x y w h')
			(445 gpuSetScissor gpu setScissor:x:y:width:height: ok ((p int32) (x int32) (y int32) (w int32) (h int32)) 'pass x y w h')
			(446 gpuBindPipeline gpu bindPipeline:pipeline: ok ((p int32) (q int32)) 'pass pipeline')
			(447 gpuBindVertexBuffer gpu bindVertexBuffer:slot:buffer:offset: ok ((p int32) (s int32) (b int32) (off uint32)) 'pass slot buf offset')
			(448 gpuBindTexture gpu bindTexture:slot:texture:sampler: ok ((p int32) (s int32) (t int32) (sm int32)) 'pass slot tex sampler')
			(450 gpuDraw gpu draw:vertices:first: ok ((p int32) (n int32) (f int32)) 'pass vertexCount firstVertex')
			(451 gpuEndPass gpu endPass: ok ((p int32)) 'pass')
			(454 gpuWaitFence gpu waitFence: ok ((f int32)) 'fence')
			(455 gpuFenceDone gpu fenceDone: bool ((f int32)) 'fence -> Boolean')
			(458 gpuWaitIdle gpu waitIdle: ok ((d int32)) 'dev')
		))
		('files and processes' (
			(500 fileOpen files open:mode: handle ((p string) (m int32)) 'path mode (0 read 1 readWrite 2 append 3 createTruncate) -> file')
			(501 fileClose files close: ok ((f int32)) 'file')
			(502 fileRead files read:into:count: readSize () 'file bytes start count -> count (0 = EOF)')
			(503 fileWrite files write:bytes:count: writeSize () 'file bytes start count -> count')
			(504 fileSize files size: nonNegativeInt64 ((f int32)) 'file -> Integer')
			(505 filePosition files position: nonNegativeInt64 ((f int32)) 'file -> Integer (0-based)')
			(507 fileFlush files flush: ok ((f int32)) 'file')
			(508 fileDelete files delete: path () 'path')
			(509 fileRename files rename:to: ok ((a string) (b string)) 'from to')
			(512 dirCreate files dirCreate: path () 'path')
			(513 cwd files cwd string () '-> String')
			(514 mkfifo files mkfifo: path () 'path')
			(516 processWait files processWait:block:status:done: wait ((pid int64) (block bool) (st outInt) (done outBool)) 'pid block (Boolean) -> exit status or nil (running)')
		))
		('sockets' (
			(540 socketListen sockets listen:port:backlog: handle ((host string) (port int32) (backlog int32)) 'host port backlog -> socket')
			(541 socketConnect sockets connect:port: handle ((host string) (port int32)) 'numeric address port -> socket (connecting: see socketConnected)')
			(543 socketRecv sockets recv:into:count: readCount () 'socket bytes start count -> count, 0 at EOF, nil would block')
			(544 socketSend sockets send:bytes:count: writeCount () 'socket bytes start count -> count or nil')
			(545 socketClose sockets close: ok ((s int32)) 'socket')
			(546 socketSemaphore sockets semaphores:read:write: ok ((s int32) (r int32) (w optionalInt32)) 'socket readIndex [writeIndex]')
			(547 socketLocalPort sockets localPort: handle ((s int32)) 'socket -> port')
			(548 socketResolve sockets lookup: handle ((name string)) 'host name -> socket reading as its numeric addresses, a line each, or one line of !! and the error')
			(549 socketConnected sockets connected: ready ((s int32)) 'socket -> true once connected, nil while connecting (arms the write semaphore)')
		))
		('raw network interface' (
			(583 nicSemaphore nic frameSemaphore: ok ((i int32)) 'index: signaled once when a frame is waiting, re-armed by a nicReceive that finds none; 0 = none')
		))
		('TLS' (
			(550 tlsStart tls start:host: handle ((s int32) (host string)) 'connected socket, host name -> connection (the same handle, no longer a socket; see tlsHandshake)')
			(551 tlsRecv tls recv:into:count: readCount () 'connection bytes start count -> count, 0 at EOF, nil would block')
			(552 tlsSend tls send:bytes:count: writeCount () 'connection bytes start count -> count or nil')
			(553 tlsClose tls close: ok ((h int32)) 'connection')
			(554 tlsSemaphore tls semaphores:read:write: ok ((h int32) (r int32) (w optionalInt32)) 'connection readIndex [writeIndex]')
			(555 tlsHandshake tls handshake: ready ((h int32)) 'connection -> true once the handshake is done (the certificate verified for the host), nil while it waits (arms the semaphore it waits for)')
		))
		('pseudo-terminals' (
			(561 ptyRead sockets ptyRead:into:count: readCount () 'pty bytes start count -> count, 0 at EOF, nil would block')
			(562 ptyWrite sockets ptyWrite:bytes:count: writeCount () 'pty bytes start count -> count or nil')
			(564 ptySemaphore sockets ptySemaphores:read:write: ok ((h int32) (r int32) (w optionalInt32)) 'pty readIndex [writeIndex]')
			(565 ptyWait ptys wait:block:status:done: wait ((h int32) (block bool) (st outInt) (done outBool)) 'pty block (Boolean) -> the child''s exit status or nil (running)')
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
floatArg: i
	<function>
	| o |
	o := self arg: i.
	(self isInt: o) ifTrue: [^(self intVal: o) asFloat].
	(memory isFloat: o) ifTrue: [^memory floatVal: o].
	bad := true.
	^0.0
!
boolArg: i
	<function>
	| o |
	o := self arg: i.
	o = memory trueOop ifTrue: [^true].
	o ~= memory falseOop ifTrue: [bad := true].
	^false
!
isText: o
	<function>
	| f |
	(self isPtr: o) ifFalse: [^false].
	f := self formatOf: o.
	^f >= F_BYTES or: [f = 10 or: [f = 11]]
!
stringArg: i
	"The malloc'd UTF-8 of a String argument (NULL, and bad set, otherwise)."
	<function>
	| o s |
	o := self arg: i.
	s := (self isText: o) ifTrue: [memory utf8Of: o] ifFalse: [self null].
	s isNull ifTrue: [bad := true].
	^s
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
rangeArgs: writable handle: h count: count
	"(handle, buffer, start, count) with 1-based start: the bytes of the range; NULL if the arguments are bad."
	<function>
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
!
stringVector: a nonEmpty: nonEmpty
	"Malloc'd NULL-terminated C strings of an Array of Strings (NULL: not one, or empty when nonEmpty)."
	<function>
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
	<function>
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
	<function>
	| r |
	s isNull ifTrue: [^self fail].
	r := memory stringFromUtf8: s size: (libc strlen: s).
	libc free: s.
	self answer: r
!
arrayOf: v count: n
	"An Array of n SmallIntegers."
	<function>
	| a |
	a := memory allocSlots: memory clsArray count: n asUInt32.
	0 to: n - 1 do: [:i | self storeRef: a at: i put: (self intOop: (v at: i))].
	^a
!
answerPair: ok first: a second: b
	<function>
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
primWindowSetSize
	"win width height (points)"
	<vmPrimitive: 421 name: 'windowSetSize'>
	| w wd h |
	(self args: 3) ifFalse: [^self fail].
	w := self intArg: 0.
	wd := self intArg: 1.
	h := self intArg: 2.
	(bad or: [wd < 1 or: [h < 1]]) ifTrue: [^self fail].
	self answerOk: (windows setSize: w asInt32 width: wd asInt32 height: h asInt32)
!
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
	<function>
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
primPlatformLastError
	"-> String"
	<vmPrimitive: 415 name: 'platformLastError'>
	| e |
	(self args: 0) ifFalse: [^self fail].
	e := common lastErrorString.
	self answer: (memory stringFromUtf8: e size: (libc strlen: e))
!
primPlatformHandleCounts
	"-> live handles {files. sockets. windows. gpuDevices. shaders. pipelines. textures. samplers. buffers. fences. ptys}"
	<vmPrimitive: 417 name: 'platformHandleCounts'>
	| v |
	v := self local: 'int64_t[PF_HANDLE_COUNTS]'.
	common handleCounts: v.
	self answer: (self arrayOf: v count: PF_HANDLE_COUNTS)
! !

!PlatformPrimitives methodsFor: 'GPU'!
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
	"dev source entry stage samplers uniformBuffers storageBuffers storageTextures -> shader. source is a String in the device's shaderLanguage, or a ByteArray of SPIR-V (gpuCompileShader) for a device that takes it."
	<vmPrimitive: 433 name: 'gpuCreateShader'>
	| d stage ns nu nsb nst o code len src entry h |
	(self args: 8) ifFalse: [^self fail].
	d := self intArg: 0.
	stage := self intArg: 3.
	ns := self intArg: 4.
	nu := self intArg: 5.
	nsb := self intArg: 6.
	nst := self intArg: 7.
	o := self arg: 1.
	code := self null.
	src := self null.
	len := self local: 'size_t'.
	((self isPtr: o) and: [(memory classOf: o) = memory clsBytearray])
		ifTrue: [
			code := self bytesOf: o size: len writable: false.
			code isNull ifTrue: [bad := true]]
		ifFalse: [src := self stringArg: 1].
	entry := self stringArg: 2.
	h := bad
		ifTrue: [0]
		ifFalse: [code isNull
			ifTrue: [gpu createShader: d asInt32 source: src entry: entry stage: stage asInt32 samplers: ns asInt32
				uniformBuffers: nu asInt32 storageBuffers: nsb asInt32 storageTextures: nst asInt32]
			ifFalse: [gpu createShader: d asInt32 spirv: code size: len value entry: entry stage: stage asInt32 samplers: ns asInt32
				uniformBuffers: nu asInt32 storageBuffers: nsb asInt32 storageTextures: nst asInt32]].
	libc free: src.
	libc free: entry.
	bad ifTrue: [^self fail].
	self answerHandle: h
!
primGpuCompileShader
	"GLSL source, stage -> the SPIR-V it compiles to (a ByteArray), for gpuCreateShader: an image keeps it, so it compiles no shaders when it starts. Fails with the compiler's log, or where GLSL is not compiled (macOS)."
	<vmPrimitive: 461 name: 'gpuCompileShader'>
	| src stage size spirv result |
	(self args: 2) ifFalse: [^self fail].
	src := self stringArg: 0.
	stage := self intArg: 1.
	bad ifTrue: [
		libc free: src.
		^self fail].
	size := self local: 'size_t'.
	size value: 0.
	spirv := gpu compileShader: src stage: stage asInt32 size: size.
	libc free: src.
	spirv isNull ifTrue: [^self fail].
	result := memory allocBytes: memory clsBytearray count: size value.
	libc memcpy: (self bytesOf: result) from: spirv size: size value.
	libc free: spirv.
	self answer: result
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
! !

!PlatformPrimitives methodsFor: 'sockets'!
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

!PlatformPrimitives methodsFor: 'clipboard'!
primClipboardData
	"MIME type -> bytes, or nil when unavailable."
	<vmPrimitive: 420 name: 'clipboardData'>
	| mime size data result |
	(self args: 1) ifFalse: [^self fail].
	mime := self stringArg: 0.
	bad ifTrue: [^self fail].
	size := self local: 'size_t'.
	size value: 0.
	data := windows clipboardData: mime size: size.
	libc free: mime.
	data isNull ifTrue: [^self answer: memory nilOop].
	(size value = 0 or: [size value > 20971520]) ifTrue: [
		windows freeClipboardData: data.
		^self answer: memory nilOop].
	result := memory allocBytes: memory clsBytearray count: size value.
	libc memcpy: (self bytesOf: result) from: data size: size value.
	windows freeClipboardData: data.
	self answer: result
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
