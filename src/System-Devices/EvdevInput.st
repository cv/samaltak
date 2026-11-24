Object subclass: #EvdevInput
	instanceVariableNames: 'display queue devices buffer process keymap held caps point buttons wheel moved polls'
	classVariableNames: 'Keycodes UsKeymap'
	package: 'System-Devices'!

EvdevInput comment: 'I am the keyboards and pointers of a KmsDisplay: Linux''s evdev devices (/dev/input/event*, EvdevDevice), every one that is a keyboard or a pointer, read by my Process every 8 ms (non-blocking read(2)s; the nodes looked for again every 2 s, so a device plugged in later is found: devtmpfs makes its node, no udev needed; one unplugged goes). Keys (EV_KEY below BTN_MISC) become the image''s key events (InputQueue: keyDown with repeats, keyUp, text) with SDL keycodes and the modifiers as SDL has them on Linux: Shift 1, Ctrl 2, the Alt keys cmd 8, the logo (Meta) keys alt 4; text for a key typed without ctrl or cmd, by the keymap: the kernel''s (its plain, shift and AltGr tables, KDGKBENT on /dev/tty0: loadkmap''s layout), the US one where it has none; Caps Lock shifts letters; Right Alt is AltGr where the keymap''s AltGr table types something. The pointer (one, whatever moves it): mice by their motion, tablets and touch screens by their point, touchpads by the finger''s motion; buttons left, right, middle (a touch screen''s touch is left); wheels; reported to the display at each EV_SYN, which moves the arrow. counts: the devices, their kinds, and the polls.'!

!EvdevInput methodsFor: 'initialization'!
setDisplay: aDisplay
	display := aDisplay.
	queue := aDisplay queue.
	devices := OrderedCollection new.
	held := Set new.
	caps := false.
	buttons := 0.
	wheel := 0 @ 0.
	moved := false.
	polls := 0.
	keymap := UsKeymap
! !

!EvdevInput methodsFor: 'running'!
start
	"Open the devices there are now and start polling (also with none yet: they may come)."
	PosixDevice isAvailable ifFalse: [^false].
	keymap := self class kernelKeymap ifNil: [UsKeymap].
	buffer := Machine allocate: 64 * 24.
	self scan.
	process := [[(Delay forMilliseconds: 8) wait. self poll] repeat] forkAt: Processor highIOPriority + 5 named: 'evdev input'.
	^true
!
stop
	self abandon.
	devices do: [:d | d close].
	devices := OrderedCollection new.
	buffer isNil ifFalse: [Machine free: buffer].
	buffer := nil
!
abandon
	"Stop without the devices (the previous VM's)."
	process isNil ifFalse: [process terminate].
	process := nil.
	devices do: [:d | d abandon]
!
scan
	"Open the event nodes not open yet."
	| paths |
	paths := ([Directory entries: '/dev/input'] on: Error do: [:e | e return: #()])
		select: [:n | n beginsWith: 'event'] thenCollect: [:n | '/dev/input/', n].
	paths do: [:p |
		(devices anySatisfy: [:d | d path = p]) ifFalse: [| d |
			d := EvdevDevice path: p.
			d open ifTrue: [devices add: d]]]
!
devices
	^devices
!
counts
	"The devices ({path. name. kind}) and how often I polled."
	^Dictionary new
		at: #devices put: (devices collect: [:d | {d path. d name. d kind}]) asArray;
		at: #polls put: polls;
		at: #keymap put: (keymap == UsKeymap ifTrue: ['us'] ifFalse: ['kernel']);
		yourself
! !

!EvdevInput methodsFor: 'polling'!
poll
	"Take every device's events; look for new devices every 250 polls."
	polls := polls + 1.
	polls \\ 250 = 0 ifTrue: [self scan].
	devices copy do: [:d |
		[self drain: d] on: OSError do: [:e |
			d close.
			devices remove: d ifAbsent: [nil]]]
!
drain: aDevice
	| n |
	[n := aDevice read: buffer count: 64 * 24.
	 n notNil and: [n > 0]] whileTrue: [
		0 to: n // 24 - 1 do: [:i | | e |
			e := buffer + (i * 24).
			self device: aDevice type: (Machine uint16At: e + 16) code: (Machine uint16At: e + 18) value: (Machine int32At: e + 20)]]
!
device: aDevice type: type code: code value: value
	"One input_event: EV_SYN 0, EV_KEY 1, EV_REL 2, EV_ABS 3."
	type = 0 ifTrue: [^code = 0 ifTrue: [self report]].
	type = 1 ifTrue: [^self device: aDevice key: code value: value].
	type = 2 ifTrue: [
		code = 0 ifTrue: [self moveBy: value @ 0].
		code = 1 ifTrue: [self moveBy: 0 @ value].
		code = 6 ifTrue: [wheel := wheel + (value @ 0). moved := true].
		code = 8 ifTrue: [wheel := wheel + (0 @ value). moved := true].
		^self].
	type = 3 ifTrue: [
		(code = 0 or: [code = 1]) ifFalse: [^self].
		aDevice isTouchpad ifTrue: [| d |
			d := aDevice touchpadMove: code to: value in: display extent.
			^self moveBy: (code = 0 ifTrue: [d @ 0] ifFalse: [0 @ d])].
		^self moveTo: (aDevice pointOf: (code = 0 ifTrue: [value]) y: (code = 1 ifTrue: [value]) in: display extent)]
!
device: aDevice key: code value: value
	"A key (below BTN_MISC 16r100) or a button: BTN_LEFT 16r110, RIGHT 16r111, MIDDLE 16r112, BTN_TOUCH 16r14A."
	| mask |
	code < 16r100 ifTrue: [^self key: code value: value].
	code = 16r14A ifTrue: [
		aDevice isTouchpad ifTrue: [^aDevice touch: value ~= 0].
		aDevice isDirect ifFalse: [^self].
		mask := 1].
	mask isNil ifTrue: [mask := code = 16r110 ifTrue: [1] ifFalse: [code = 16r111 ifTrue: [4] ifFalse: [code = 16r112 ifTrue: [2] ifFalse: [0]]]].
	mask = 0 ifTrue: [^self].
	buttons := value ~= 0 ifTrue: [buttons bitOr: mask] ifFalse: [buttons bitClear: mask].
	moved := true
!
moveBy: aPoint
	point := (point ifNil: [display pointerPosition]) + aPoint.
	moved := true
!
moveTo: pair
	"pair: {x or nil. y or nil}, screen pixels."
	| p |
	p := point ifNil: [display pointerPosition].
	point := (pair first ifNil: [p x]) @ (pair last ifNil: [p y]).
	moved := true
!
report
	"The pointer's state since the last EV_SYN to the display."
	| p |
	moved ifFalse: [^self].
	p := point ifNil: [display pointerPosition].
	display pointerAt: p x asFloat @ p y asFloat buttons: buttons wheel: (wheel x = 0 ifTrue: [wheel y] ifFalse: [wheel]).
	point := nil.
	wheel := 0 @ 0.
	moved := false
! !

!EvdevInput methodsFor: 'keys'!
modifiers
	"Shift 1, Ctrl 2, the logo keys alt 4, the Alt keys cmd 8 (Right Alt not while it types as AltGr: see key:value:)."
	| m |
	m := 0.
	((held includes: 42) or: [held includes: 54]) ifTrue: [m := m bitOr: 1].
	((held includes: 29) or: [held includes: 97]) ifTrue: [m := m bitOr: 2].
	((held includes: 125) or: [held includes: 126]) ifTrue: [m := m bitOr: 4].
	((held includes: 56) or: [held includes: 100]) ifTrue: [m := m bitOr: 8].
	^m
!
key: code value: value
	"A key pressed (1), held (2: a repeat) or released (0)."
	| sdl mods text altGr |
	value = 0 ifTrue: [held remove: code ifAbsent: [nil]] ifFalse: [held add: code].
	(code = 58 and: [value = 1]) ifTrue: [caps := caps not].
	sdl := self keycodeOf: code.
	sdl = 0 ifTrue: [^self].
	mods := self modifiers.
	altGr := (held includes: 100) and: [(self character: code table: 3) notNil].
	(altGr and: [(held includes: 56) not]) ifTrue: [mods := mods bitClear: 8].
	value = 0 ifTrue: [^queue keyUp: sdl modifiers: mods].
	queue keyDown: sdl modifiers: mods repeat: value = 2.
	(mods bitAnd: 10) = 0 ifFalse: [^self].
	text := self textOf: code altGr: altGr.
	text isNil ifFalse: [queue text: text modifiers: mods]
!
keycodeOf: code
	"The SDL keycode of a Linux key: a named key's, else the character the key types unshifted; 0 if none."
	(Keycodes at: code ifAbsent: [nil]) ifNotNil: [:k | ^k].
	^(self character: code table: 1) ifNil: [0] ifNotNil: [:c | c asLowercase value]
!
textOf: code altGr: aBoolean
	"The text a key types: by the AltGr table, else the shift one if Shift is held (or, for a letter, Caps Lock on, but not both), else the plain one."
	| shift c |
	aBoolean ifTrue: [^(self character: code table: 3) asString].
	shift := (held includes: 42) or: [held includes: 54].
	(caps and: [(self character: code table: 1) ifNil: [false] ifNotNil: [:p | p isLetter]]) ifTrue: [shift := shift not].
	c := self character: code table: (shift ifTrue: [2] ifFalse: [1]).
	^c ifNotNil: [:ch | ch asString]
!
character: code table: index
	"The printable Character the keymap's table index (1 plain, 2 shift, 3 AltGr) has for code, else nil."
	| table |
	table := keymap at: index.
	(code between: 1 and: table size) ifFalse: [^nil].
	^table at: code
! !

!EvdevInput class methodsFor: 'class initialization'!
initialize
	"Keycodes: Linux key codes (linux/input-event-codes.h) of named keys to SDL keycodes. UsKeymap: the US layout's plain, shift and AltGr tables (Characters by key code, nil where none), with the keypad as Num Lock on."
	| plain shift rows |
	Keycodes := Dictionary new.
	#(1 27 14 8 15 9 28 13 96 13 111 127
	  102 16r4000004A 103 16r40000052 104 16r4000004B 105 16r40000050 106 16r4000004F 107 16r4000004D 108 16r40000051 109 16r4000004E 110 16r40000049
	  87 16r40000044 88 16r40000045 58 16r40000039 127 16r40000065 99 16r40000046 70 16r40000047 119 16r40000048
	  29 16r400000E0 42 16r400000E1 56 16r400000E2 125 16r400000E3 97 16r400000E4 54 16r400000E5 100 16r400000E6 126 16r400000E7)
		pairsDo: [:code :sdl | Keycodes at: code put: sdl].
	0 to: 9 do: [:i | Keycodes at: 59 + i put: 16r4000003A + i].
	plain := Array new: 127.
	shift := Array new: 127.
	rows := #(2 '1234567890-=' '!!@#$%^&*()_+' 16 'qwertyuiop[]' 'QWERTYUIOP{}' 30 'asdfghjkl;''`' 'ASDFGHJKL:"~' 43 '\zxcvbnm,./' '|ZXCVBNM<>?' 57 ' ' ' '
	  71 '789-456+1230.' '789-456+1230.' 55 '*' '*' 98 '/' '/').
	1 to: rows size by: 3 do: [:g |
		1 to: (rows at: g + 1) size do: [:i |
			plain at: (rows at: g) + i - 1 put: ((rows at: g + 1) at: i).
			shift at: (rows at: g) + i - 1 put: ((rows at: g + 2) at: i)]].
	UsKeymap := {plain. shift. Array new: 127}
! !

!EvdevInput class methodsFor: 'keymap'!
kernelKeymap
	"The kernel's keymap (the console's: loadkmap sets it), its plain, shift and AltGr tables, with the US keymap where it has no printable character for a key (the keypad is KT_PAD there); nil without a console to ask (KDGKBENT on /dev/tty0)."
	| fd e tables |
	fd := [PosixDevice open: '/dev/tty0' flags: ((PosixDevice O_RDONLY bitOr: PosixDevice O_NOCTTY) bitOr: PosixDevice O_CLOEXEC)] on: OSError do: [:x | x return: nil].
	fd isNil ifTrue: [^nil].
	e := Machine allocate: 4.
	^[[tables := #(0 1 2) collect: [:t | | table |
		table := (UsKeymap at: t + 1) copy.
		1 to: 127 do: [:code | | v |
			Machine uint8At: e put: t; uint8At: e + 1 put: code; uint16At: e + 2 put: 0.
			PosixDevice ioctl: fd request: 16r4B46 argument: e.
			v := Machine uint16At: e + 2.
			"KT_LATIN 0 and KT_LETTER 11: a Latin-1 character."
			(((v bitShift: -8) = 0 or: [(v bitShift: -8) = 11]) and: [(v bitAnd: 255) >= 32 and: [(v bitAnd: 255) ~= 127]])
				ifTrue: [table at: code put: (Character value: (v bitAnd: 255))]].
		table].
	 tables]
		on: OSError do: [:x | x return: nil]]
			ensure: [Machine free: e. PosixDevice close: fd]
! !

!EvdevInput class methodsFor: 'instance creation'!
display: aDisplay
	^self new setDisplay: aDisplay
! !
