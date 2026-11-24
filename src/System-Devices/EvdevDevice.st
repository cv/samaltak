Object subclass: #EvdevDevice
	instanceVariableNames: 'path fd name keyboard relative absolute touchpad direct minX maxX minY maxY lastX lastY touching'
	classVariableNames: ''
	package: 'System-Devices'!

EvdevDevice comment: 'I am one Linux input device (/dev/input/eventN, linux/input.h) for EvdevInput: opened non-blocking through PosixDevice, my capabilities asked of the kernel (EVIOCGBIT, EVIOCGPROP, EVIOCGABS): a keyboard (letter keys), a relative pointer (a mouse: REL_X and REL_Y), an absolute one (ABS_X and ABS_Y: a tablet such as QEMU''s virtio-tablet, a touch screen, INPUT_PROP_DIRECT, or a touchpad: BTN_TOOL_FINGER without it, whose finger''s motion moves the pointer as a mouse would). read:count: takes the input_events waiting (24 bytes each on a 64-bit kernel: the time, type, code and value) with read(2): evdev refuses pread. Devices that are none of these (a power button, a lid switch) are not opened for long.'!

!EvdevDevice methodsFor: 'opening'!
setPath: aPath
	path := aPath
!
open
	"Open and classify me; answer whether I am a keyboard or a pointer (else I am closed again)."
	fd := [PosixDevice open: path flags: ((PosixDevice O_RDONLY bitOr: PosixDevice O_NONBLOCK) bitOr: PosixDevice O_CLOEXEC)] on: OSError do: [:e | e return: nil].
	fd isNil ifTrue: [^false].
	([self classify] on: OSError do: [:e | e return: false]) ifTrue: [^true].
	self close.
	^false
!
classify
	| types keys rel abs props |
	name := self string: 16r06 size: 128.
	types := self bits: 0 size: 4.
	keys := (self has: 1 in: types) ifTrue: [self bits: 1 size: 96] ifFalse: [ByteArray new: 96].
	rel := (self has: 2 in: types) ifTrue: [self bits: 2 size: 4] ifFalse: [ByteArray new: 4].
	abs := (self has: 3 in: types) ifTrue: [self bits: 3 size: 8] ifFalse: [ByteArray new: 8].
	props := self request: 16r09 size: 4.
	keyboard := (self has: 30 in: keys) and: [(self has: 44 in: keys) and: [self has: 57 in: keys]].
	relative := (self has: 0 in: rel) and: [self has: 1 in: rel].
	absolute := (self has: 0 in: abs) and: [self has: 1 in: abs].
	direct := self has: 1 in: props.
	touchpad := absolute and: [direct not and: [self has: 16r145 in: keys]].
	absolute ifTrue: [| x y |
		x := self absInfo: 0.
		y := self absInfo: 1.
		minX := x first. maxX := x last.
		minY := y first. maxY := y last].
	touching := false.
	^keyboard or: [relative or: [absolute]]
!
close
	fd isNil ifFalse: [[PosixDevice close: fd] on: OSError do: [:e | e return: nil]].
	fd := nil
!
abandon
	"Forget the descriptor: it was the previous VM process's."
	fd := nil
! !

!EvdevDevice methodsFor: 'accessing'!
path
	^path
!
name
	^name
!
isKeyboard
	^keyboard
!
isTouchpad
	^touchpad
!
isAbsolute
	"A tablet or a touch screen: its X and Y are a point of the screen."
	^absolute and: [touchpad not]
!
isDirect
	"A touch screen: a touch is the left button."
	^direct
!
kind
	"What I am, for people: keyboard, mouse, touchpad, tablet, touchscreen (several, comma-separated)."
	| kinds |
	kinds := OrderedCollection new.
	keyboard ifTrue: [kinds add: 'keyboard'].
	relative ifTrue: [kinds add: 'mouse'].
	touchpad ifTrue: [kinds add: 'touchpad'].
	(self isAbsolute and: [direct not]) ifTrue: [kinds add: 'tablet'].
	(self isAbsolute and: [direct]) ifTrue: [kinds add: 'touchscreen'].
	^kinds inject: '' into: [:s :k | s isEmpty ifTrue: [k] ifFalse: [s, ', ', k]]
!
read: address count: n
	"read(2) of up to n bytes of input_events into address; nil when there are none (EAGAIN). An unplugged device signals an OSError (ENODEV)."
	^PosixDevice read: fd into: address count: n
! !

!EvdevDevice methodsFor: 'pointer'!
pointOf: x y: y in: extent
	"The screen point of an absolute device's x and y (nil where an axis has not been reported)."
	| px py |
	px := (x isNil or: [maxX <= minX]) ifTrue: [nil] ifFalse: [(x - minX) * extent x / (maxX - minX + 1)].
	py := (y isNil or: [maxY <= minY]) ifTrue: [nil] ifFalse: [(y - minY) * extent y / (maxY - minY + 1)].
	^{px. py}
!
touchpadMove: axis to: value in: extent
	"A touchpad's finger moved along axis (0: x, 1: y) to value: the pointer's motion (pixels), the pad's width spanning the screen's; 0 for the first report of a touch."
	| last d |
	touching ifFalse: [^0].
	last := axis = 0 ifTrue: [lastX] ifFalse: [lastY].
	axis = 0 ifTrue: [lastX := value] ifFalse: [lastY := value].
	last isNil ifTrue: [^0].
	d := value - last.
	^axis = 0
		ifTrue: [d * extent x / ((maxX - minX) max: 1)]
		ifFalse: [d * extent x / ((maxX - minX) max: 1)]
!
touch: aBoolean
	"The finger is down (BTN_TOUCH) or lifted: a new touch starts from where it lands."
	touching := aBoolean.
	lastX := lastY := nil
! !

!EvdevDevice methodsFor: 'private'!
request: nr size: n
	"The n bytes an _IOC(_IOC_READ, 'E', nr, n) ioctl fills."
	| a |
	a := Machine allocate: n.
	^[PosixDevice ioctl: fd request: ((2 bitShift: 30) bitOr: ((n bitShift: 16) bitOr: (16r4500 bitOr: nr))) argument: a.
	Machine bytesAt: a count: n]
		ensure: [Machine free: a]
!
bits: type size: n
	"EVIOCGBIT(type, n): the codes of type the device has, a bit each (type 0: the types)."
	^self request: 16r20 + type size: n
!
string: nr size: n
	"A string an ioctl fills (EVIOCGNAME: 6), up to its NUL."
	| bytes end |
	bytes := self request: nr size: n.
	end := (bytes indexOf: 0) - 1.
	end < 0 ifTrue: [end := n].
	^(bytes copyFrom: 1 to: end) asString
!
absInfo: axis
	"{minimum. maximum} of an absolute axis (EVIOCGABS: struct input_absinfo, int32s value minimum maximum ...)."
	| a |
	a := Machine allocate: 24.
	^[PosixDevice ioctl: fd request: ((2 bitShift: 30) bitOr: ((24 bitShift: 16) bitOr: (16r4540 + axis))) argument: a.
	{Machine int32At: a + 4. Machine int32At: a + 8}]
		ensure: [Machine free: a]
!
has: bit in: bytes
	"Is bit (0-based) set in the bitmap bytes (longs in the host's order: little-endian here)?"
	| i |
	i := bit // 8 + 1.
	i > bytes size ifTrue: [^false].
	^((bytes at: i) bitAnd: (1 bitShift: bit \\ 8)) ~= 0
! !

!EvdevDevice class methodsFor: 'instance creation'!
path: aPath
	^self new setPath: aPath
! !
