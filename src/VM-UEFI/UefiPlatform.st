PlatformInterface subclass: #UefiPlatform
	instanceVariableNames: 'events windows vsync gpu input virtio nic initDone'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiPlatform comment: 'The platform on UEFI (in place of SDLPlatform and HeadlessPlatform): the firmware''s keyboard and pointer pumped at interrupt checks (at most once a millisecond) and while waiting, the refresh clock (UefiVsync), the software GPU (UefiGpu). Waiting waits for a key, the pointer or the timeout, whichever comes first (at most 10 ms with a virtio pointer or the network, which are polled; while frames come and go, the NIC is polled without pause instead: UefiSnp>>spin:).'!

!UefiPlatform class methodsFor: 'declaring'!
declarations
	^#((events UefiEvents) (windows UefiWindows) (vsync UefiVsync) (gpu PlatformGPU) (input UefiInput) (virtio UefiVirtioInput) (nic UefiSnp) (initDone bool))
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiPlatform methodsFor: 'platform'!
init
	<export>
	initDone ifTrue: [^self].
	initDone := true.
	input start.
	virtio start.
	gpu init
!
poll
	<export>
	(initDone and: [windows videoInited and: [events sinceLastPumpNs >= 1000000]]) ifTrue: [events pump].
	nic poll.
	events signalReady
!
wait: timeoutUs
	"Headless (no init) too: then a timer is all there is to wait for, but the NIC."
	<export>
	| us next |
	us := timeoutUs.
	initDone ifTrue: [
		events pump.
		(events pending or: [vsync pending]) ifTrue: [us := 0].
		next := vsync microsecondsToNext.
		(next >= 0 and: [us < 0 or: [next < us]]) ifTrue: [us := next]].
	"the NIC and a virtio device signal nothing the firmware waits for: poll them every 10 ms; a busy NIC without pause"
	((nic wantsPolling or: [virtio isPresent]) and: [us < 0 or: [us > 10000]]) ifTrue: [us := 10000].
	us ~= 0 ifTrue: [us := nic spin: us].
	us ~= 0 ifTrue: [
		initDone
			ifTrue: [input wait: us]
			ifFalse: [
				us < 0 ifTrue: [self fatal: 'deadlock: no runnable process and no pending timer'].
				posix usleep: (us > 1000000 ifTrue: [1000000] ifFalse: [us]) asUInt32]].
	initDone ifTrue: [events pump].
	nic poll.
	events signalReady
!
shutdown
	<export>
	initDone ifTrue: [gpu shutdown]
! !

VMPlatformModule subclass: #UefiWindows
	instanceVariableNames: 'screen open clipboard cursorKind'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiWindows comment: 'Windows on UEFI (in place of PlatformWindows): one, the whole screen (UefiScreen) at one pixel a point, handle 1. Opening it a second time answers it again. The clipboard is a string in memory.'!

!UefiWindows class methodsFor: 'declaring'!
declarations
	^#((screen UefiScreen) (open bool) (clipboard 'char *') (cursorKind int32_t))
!
targetOS
	^#uefi
!
replaces
	^PlatformWindows
!
isSimulated
	^false
! !

!UefiWindows methodsFor: 'windows'!
videoInited
	<function>
	<returns: 'bool'>
	^open
!
open: w height: h title: title flags: flags
	"The screen; 0 (the error set) if there is none."
	<function>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #title type: 'char *'>
	<var: #flags type: 'int32_t'>
	<returns: 'int32_t'>
	(screen start: w height: h) ifFalse: [
		common setError: 'no graphics output with a framebuffer'.
		^0].
	open ifFalse: [
		open := true.
		events updatePollInterval].
	^1
!
isWindow: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'bool'>
	(open and: [win = 1]) ifTrue: [^true].
	common setError: 'no such window'.
	^false
!
close: win
	"The screen stays; its back buffer goes (UefiGpu)."
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'bool'>
	(self isWindow: win) ifFalse: [^false].
	gpu windowClosing: win.
	^true
!
size: win width: w height: h
	"Points: one a pixel."
	<function>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<returns: 'bool'>
	^self pixelSize: win width: w height: h
!
pixelSize: win width: w height: h
	<function>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<returns: 'bool'>
	(self isWindow: win) ifFalse: [^false].
	w value: screen width.
	h value: screen height.
	^true
!
displayScale: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'double'>
	^(self isWindow: win) ifTrue: [1.0] ifFalse: [-1.0]
!
refreshRate: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'double'>
	^(self isWindow: win) ifTrue: [60.0] ifFalse: [-1.0]
!
setTitle: win title: title
	<function>
	<var: #win type: 'int32_t'>
	<var: #title type: 'char *'>
	<returns: 'bool'>
	^self isWindow: win
!
setTextInputArea: win x: x y: y width: w height: h cursor: c
	<function>
	<var: #win type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #c type: 'int32_t'>
	<returns: 'bool'>
	^self isWindow: win
!
show: win visible: visible
	<function>
	<var: #win type: 'int32_t'>
	<var: #visible type: 'bool'>
	<returns: 'bool'>
	^self isWindow: win
!
handleCount
	<function>
	<returns: 'int32_t'>
	^open ifTrue: [1] ifFalse: [0]
!
present: win pixels: p width: w height: h
	"A frame of the window (BGRA8 rows, from UefiGpu's swapchain) onto the screen."
	<function>
	<var: #win type: 'int32_t'>
	<var: #p type: 'const uint8_t *'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	(self isWindow: win) ifTrue: [screen present: p width: w height: h]
!
pointerAt: x y: y
	"The pointer moved (UefiEvents)."
	<function>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	open ifTrue: [screen moveCursorTo: x y: y]
! !

!UefiWindows methodsFor: 'cursor and clipboard'!
setCursor: kind
	"The arrow whatever the kind."
	<function>
	<var: #kind type: 'int32_t'>
	<returns: 'bool'>
	cursorKind := kind.
	^true
!
clipboardGet
	"malloc'd."
	<function>
	<returns: 'char *'>
	^libc strdup: (clipboard notNull ifTrue: [clipboard] ifFalse: [''])
!
clipboardSet: s
	<function>
	<var: #s type: 'char *'>
	<returns: 'bool'>
	libc free: clipboard.
	clipboard := libc strdup: s.
	^clipboard notNull
!
clipboardData: mime size: size
	"No data but text."
	<function>
	<var: #mime type: 'char *'>
	<var: #size type: 'size_t *'>
	<returns: 'void *'>
	^self null
!
freeClipboardData: data
	<function>
	<var: #data type: 'void *'>
	libc free: data
! !

VMPlatformModule subclass: #UefiEvents
	instanceVariableNames: 'input virtio nic q qHead qLen qCap qDropped inputSem inputArmed lastPumpNs mouseX mouseY buttons lastZ downButton downMs downX downY clicks'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiEvents comment: 'The event queue on UEFI (in place of PlatformEvents): the same FIFO and semaphore, filled from the firmware''s keyboard and pointer (UefiInput). A key stroke is a keyDown, its textInput (a character without ctrl or cmd) and a keyUp: the firmware reports no releases. Modifiers as on Linux: Alt is cmd, the logo key alt. The pointer is in screen pixels, starting at the centre; an absolute pointer (a tablet, a touch screen) if one reports, else a relative one (a mouse); clicks within 400 ms and 4 pixels count up.'!

!UefiEvents class methodsFor: 'declaring'!
declarations
	^#((input UefiInput) (virtio UefiVirtioInput) (nic UefiSnp) (q 'pf_event *') (qHead int32_t) (qLen int32_t) (qCap int32_t) (qDropped int64_t) (inputSem int32_t) (inputArmed bool true)
		(lastPumpNs int64_t) (mouseX double) (mouseY double) (buttons int32_t) (lastZ int64_t) (downButton int32_t) (downMs int64_t)
		(downX double) (downY double) (clicks int32_t))
!
targetOS
	^#uefi
!
replaces
	^PlatformEvents
!
isSimulated
	^false
! !

!UefiEvents methodsFor: 'queue'!
push: e
	"Copies the text; drops the event if the queue is full."
	<function>
	<var: #e type: 'pf_event *'>
	<var: #text type: 'char *'>
	| cap n text d |
	qLen = qCap ifTrue: [
		cap := qCap ~= 0 ifTrue: [qCap * 2] ifFalse: [256].
		cap > PF_EVENT_QUEUE_MAX ifTrue: [
			qDropped := qDropped + 1.
			^self].
		n := self cCoerce: (libc malloc: (self sizeof: 'pf_event') * cap asUInt64) to: 'pf_event *'.
		n isNull ifTrue: [
			qDropped := qDropped + 1.
			^self].
		0 to: qLen - 1 do: [:i | (n + i) copyStructFrom: q + ((qHead + i) rem: qCap)].
		libc free: q.
		q := n.
		qCap := cap.
		qHead := 0].
	text := self null.
	e xkind = PF_X_TEXT ifTrue: [
		text := libc strdup: (e text notNull ifTrue: [e text] ifFalse: ['']).
		text isNull ifTrue: [
			qDropped := qDropped + 1.
			^self]].
	d := q + ((qHead + qLen) rem: qCap).
	qLen := qLen + 1.
	d copyStructFrom: e.
	d text: text
!
dropped
	<function>
	<returns: 'int64_t'>
	^qDropped
!
next: out
	"The caller frees out text."
	<function>
	<var: #out type: 'pf_event *'>
	<returns: 'bool'>
	inputArmed := true.
	qLen = 0 ifTrue: [^false].
	out copyStructFrom: q + qHead.
	qHead := (qHead + 1) rem: qCap.
	qLen := qLen - 1.
	^true
!
setSemaphore: index
	<function>
	<var: #index type: 'int32_t'>
	inputSem := index.
	inputArmed := true
!
pending
	<function>
	<returns: 'bool'>
	^qLen ~= 0
!
signalReady
	"Signal the vsync semaphore if a refresh is due, and the input semaphore if events are pending."
	<function>
	vsync poll.
	(qLen ~= 0 and: [inputSem ~= 0 and: [inputArmed]]) ifTrue: [
		inputArmed := false.
		scheduler signalExternalSemaphore: inputSem]
!
updatePollInterval
	"After the window opens or the NIC's semaphore changes: polls every PF_POLL_US while either wants them."
	<function>
	scheduler requestPeriodicPoll: ((windows videoInited or: [nic wantsPolling]) ifTrue: [PF_POLL_US] ifFalse: [0])
!
sinceLastPumpNs
	<function>
	<returns: 'int64_t'>
	^(common nowMs * 1000000) - lastPumpNs
! !

!UefiEvents methodsFor: 'firmware input'!
pump
	"Queue what the keyboard and the pointer did since the last pump."
	<function>
	| key |
	lastPumpNs := common nowMs * 1000000.
	key := self local: 'EfiKeyData'.
	[input readKey: key] whileTrue: [self translateKey: key].
	self pumpPointer
!
newEvent: type
	| e |
	e := self local: 'pf_event'.
	e type: type.
	e timeMs: common nowMs.
	e x: mouseX.
	e y: mouseY.
	e window: 1.
	^e
!
modsOf: shiftState
	"EFI_SHIFT_STATE_VALID, then right and left shift, control, alt, logo."
	<function>
	<var: #shiftState type: 'uint32_t'>
	<returns: 'int32_t'>
	| m |
	(shiftState bitAnd: 16r80000000) = 0 ifTrue: [^0].
	m := 0.
	(shiftState bitAnd: 3) ~= 0 ifTrue: [m := m bitOr: PF_MOD_SHIFT].
	(shiftState bitAnd: 16rC) ~= 0 ifTrue: [m := m bitOr: PF_MOD_CTRL].
	(shiftState bitAnd: 16r30) ~= 0 ifTrue: [m := m bitOr: PF_MOD_CMD].
	(shiftState bitAnd: 16rC0) ~= 0 ifTrue: [m := m bitOr: PF_MOD_ALT].
	^m asInt32
!
keycodeOfScan: scan
	"The SDL keycode of an EFI scan code; 0 if none."
	<function>
	<var: #scan type: 'int32_t'>
	<returns: 'int64_t'>
	scan = 1 ifTrue: [^16r40000052].
	scan = 2 ifTrue: [^16r40000051].
	scan = 3 ifTrue: [^16r4000004F].
	scan = 4 ifTrue: [^16r40000050].
	scan = 5 ifTrue: [^16r4000004A].
	scan = 6 ifTrue: [^16r4000004D].
	scan = 7 ifTrue: [^16r40000049].
	scan = 8 ifTrue: [^127].
	scan = 9 ifTrue: [^16r4000004B].
	scan = 10 ifTrue: [^16r4000004E].
	(scan >= 11 and: [scan <= 22]) ifTrue: [^16r4000003A + scan - 11].
	scan = 23 ifTrue: [^27].
	^0
!
translateKey: k
	<function>
	<var: #k type: 'EfiKeyData *'>
	| mods ch code e text |
	mods := self modsOf: k keyShiftState.
	ch := k unicodeChar asInt64.
	code := self keycodeOfScan: k scanCode asInt32.
	code = 0 ifTrue: [
		(ch >= 1 and: [ch <= 26 and: [ch ~= 8 and: [ch ~= 9 and: [ch ~= 13]]]]) ifTrue: [
			ch := ch + 96.
			mods := mods bitOr: PF_MOD_CTRL].
		(ch >= $A value and: [ch <= $Z value]) ifTrue: [
			mods := mods bitOr: PF_MOD_SHIFT.
			code := ch + 32].
		code = 0 ifTrue: [code := ch]].
	code = 0 ifTrue: [^self].
	e := self newEvent: PF_EV_KEY_DOWN.
	e key: code.
	e mods: mods.
	e xkind: PF_X_BOOL.
	e ival: 0.
	self push: e.
	(ch >= 32 and: [ch ~= 127 and: [(mods bitAnd: (PF_MOD_CTRL bitOr: PF_MOD_CMD)) = 0 and: [k scanCode = 0]]]) ifTrue: [
		text := self local: 'char[4]'.
		ch < 16r80
			ifTrue: [text at: 0 put: ch]
			ifFalse: [
				ch < 16r800
					ifTrue: [
						text at: 0 put: (16rC0 bitOr: ch >> 6).
						text at: 1 put: (16r80 bitOr: (ch bitAnd: 63))]
					ifFalse: [
						text at: 0 put: (16rE0 bitOr: ch >> 12).
						text at: 1 put: (16r80 bitOr: ((ch >> 6) bitAnd: 63)).
						text at: 2 put: (16r80 bitOr: (ch bitAnd: 63))]].
		e := self newEvent: PF_EV_TEXT_INPUT.
		e mods: mods.
		e xkind: PF_X_TEXT.
		e text: text.
		self push: e].
	e := self newEvent: PF_EV_KEY_UP.
	e key: code.
	e mods: mods.
	e xkind: PF_X_BOOL.
	e ival: 0.
	self push: e
!
pumpPointer
	"A virtio input device if there is one (UefiVirtioInput), else the firmware's absolute pointer if it reports, else its relative one: a move, then the buttons that changed, then the wheel."
	<function>
	| abs rel mode x y z now b w h dz ps |
	w := self local: 'int'.
	h := self local: 'int'.
	(windows pixelSize: 1 width: w height: h) ifFalse: [^self].
	abs := self local: 'EfiAbsolutePointerState'.
	rel := self local: 'EfiSimplePointerState'.
	(mouseX = 0.0 and: [mouseY = 0.0]) ifTrue: [
		mouseX := (w value quo: 2) asFloat.
		mouseY := (h value quo: 2) asFloat].
	x := mouseX.
	y := mouseY.
	b := buttons.
	dz := 0.
	ps := self local: 'UefiPointerState'.
	virtio isPresent
		ifTrue: [
			virtio poll.
			virtio state: ps.
			ps x >= 0.0 ifTrue: [x := ps x * w value asFloat].
			ps y >= 0.0 ifTrue: [y := ps y * h value asFloat].
			x := x + ps dx asFloat.
			y := y + ps dy asFloat.
			dz := ps wheel.
			b := ps buttons]
		ifFalse: [(input absoluteState: abs)
		ifTrue: [
			mode := input absoluteMode.
			mode maxX > mode minX ifTrue: [x := ((abs currentX - mode minX) asInt64 * w value asInt64) asFloat / (mode maxX - mode minX + 1) asInt64 asFloat].
			mode maxY > mode minY ifTrue: [y := ((abs currentY - mode minY) asInt64 * h value asInt64) asFloat / (mode maxY - mode minY + 1) asInt64 asFloat].
			z := abs currentZ asInt64.
			dz := z - lastZ.
			lastZ := z.
			b := (((abs activeButtons bitAnd: 1) ~= 0 ifTrue: [1] ifFalse: [0]) bitOr: ((abs activeButtons bitAnd: 2) ~= 0 ifTrue: [4] ifFalse: [0])) asInt32]
		ifFalse: [
			(input relativeState: rel) ifFalse: [^self].
			x := x + rel relativeX asFloat.
			y := y + rel relativeY asFloat.
			dz := rel relativeZ asInt64.
			b := ((rel leftButton ~= 0 ifTrue: [1] ifFalse: [0]) bitOr: (rel rightButton ~= 0 ifTrue: [4] ifFalse: [0])) asInt32]].
	x < 0.0 ifTrue: [x := 0.0].
	y < 0.0 ifTrue: [y := 0.0].
	x > (w value - 1) asFloat ifTrue: [x := (w value - 1) asFloat].
	y > (h value - 1) asFloat ifTrue: [y := (h value - 1) asFloat].
	(x ~= mouseX or: [y ~= mouseY]) ifTrue: [
		mouseX := x.
		mouseY := y.
		windows pointerAt: (self cCoerce: x to: 'int32_t') y: (self cCoerce: y to: 'int32_t').
		self pushMove].
	self button: 1 mask: 1 held: b.
	self button: 3 mask: 4 held: b.
	buttons := b.
	dz ~= 0 ifTrue: [
		now := self newEvent: PF_EV_WHEEL.
		now key: 0.
		now xkind: PF_X_POINT.
		now dx: 0.0.
		now dy: dz asFloat.
		self push: now]
!
pushMove
	<function>
	| e |
	e := self newEvent: PF_EV_MOUSE_MOVE.
	e key: buttons.
	e xkind: PF_X_NIL.
	self push: e
!
button: button mask: mask held: b
	"A down or up event if button (1 left, 3 right) changed."
	<function>
	<var: #button type: 'int32_t'>
	<var: #mask type: 'int32_t'>
	<var: #b type: 'int32_t'>
	| e down now |
	(b bitAnd: mask) = (buttons bitAnd: mask) ifTrue: [^self].
	down := (b bitAnd: mask) ~= 0.
	now := common nowMs.
	down ifTrue: [
		clicks := (button = downButton and: [now - downMs <= 400 and: [(mouseX - downX) <= 4.0 and: [(downX - mouseX) <= 4.0 and: [(mouseY - downY) <= 4.0 and: [(downY - mouseY) <= 4.0]]]]])
			ifTrue: [clicks + 1]
			ifFalse: [1].
		downButton := button.
		downMs := now.
		downX := mouseX.
		downY := mouseY].
	e := self newEvent: (down ifTrue: [PF_EV_MOUSE_DOWN] ifFalse: [PF_EV_MOUSE_UP]).
	e key: button.
	e xkind: PF_X_INT.
	e ival: clicks.
	self push: e
! !

VMPlatformModule subclass: #UefiVsync
	instanceVariableNames: 'vsyncSem nextNs'
	classVariableNames: 'UEFI_REFRESH_NS'
	package: 'VM-UEFI'!

UefiVsync comment: 'The refresh semaphore on UEFI (in place of PlatformVsync): there is no display refresh to follow, so a 60 Hz clock signals it, at most once per poll; behind by more than a period, it starts again from now.'!

!UefiVsync class methodsFor: 'declaring'!
declarations
	^#((vsyncSem int32_t) (nextNs int64_t))
!
targetOS
	^#uefi
!
replaces
	^PlatformVsync
!
isSimulated
	^false
!
initialize
	UEFI_REFRESH_NS := 16666667
! !

!UefiVsync methodsFor: 'refresh'!
semaphore: index
	"0 = stop."
	<function>
	<var: #index type: 'int32_t'>
	<returns: 'bool'>
	vsyncSem := index.
	nextNs := (common nowMs * 1000000) + UEFI_REFRESH_NS.
	^true
!
pending
	<function>
	<returns: 'bool'>
	^vsyncSem ~= 0 and: [(common nowMs * 1000000) >= nextNs]
!
microsecondsToNext
	"Until the next refresh; -1 if none is wanted."
	<function>
	<returns: 'int64_t'>
	| d |
	vsyncSem = 0 ifTrue: [^-1].
	d := nextNs - (common nowMs * 1000000).
	^d < 0 ifTrue: [0] ifFalse: [d quo: 1000]
!
poll
	<function>
	| now |
	self pending ifFalse: [^self].
	now := common nowMs * 1000000.
	nextNs := nextNs + UEFI_REFRESH_NS.
	nextNs <= now ifTrue: [nextNs := now + UEFI_REFRESH_NS].
	scheduler signalExternalSemaphore: vsyncSem
! !
