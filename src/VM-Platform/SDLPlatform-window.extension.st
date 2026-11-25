!SDLPlatform methodsFor: '*VM-Platform-window'!
ffiWindowOpen: w height: h title: bytes size: n flags: flags
	<function>
	<approvedFFI: 400 symbol: 'platform_windows_open' arguments: #(3 3 8 3) result: 1>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #flags type: 'int64_t'>
	<returns: 'int32_t'>
	| title result |
	title := nativeCountedText copyTerminated: bytes size: n.
	title isNull ifTrue: [^0].
	result := windows open: w asInt32 height: h asInt32 title: title flags: flags asInt32.
	libc free: title.
	^result
!
ffiWindowSize: win into: bytes capacity: cap
	<function>
	<approvedFFI: 402 symbol: 'platform_windows_size' arguments: #(3 9) result: 1>
	<var: #win type: 'int64_t'>
	<var: #bytes type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| w h |
	cap ~= 8 ifTrue: [^0].
	w := self local: 'int'.
	h := self local: 'int'.
	(windows size: win asInt32 width: w height: h) ifFalse: [^0].
	self windowWire: bytes at: 0 put: w value asUInt32 count: 4.
	self windowWire: bytes at: 4 put: h value asUInt32 count: 4.
	^1
!
ffiWindowPixelSize: win into: bytes capacity: cap
	<function>
	<approvedFFI: 403 symbol: 'platform_windows_pixel_size' arguments: #(3 9) result: 1>
	<var: #win type: 'int64_t'>
	<var: #bytes type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| w h |
	cap ~= 8 ifTrue: [^0].
	w := self local: 'int'.
	h := self local: 'int'.
	(windows pixelSize: win asInt32 width: w height: h) ifFalse: [^0].
	self windowWire: bytes at: 0 put: w value asUInt32 count: 4.
	self windowWire: bytes at: 4 put: h value asUInt32 count: 4.
	^1
!
ffiWindow: win title: bytes size: n
	<function>
	<approvedFFI: 405 symbol: 'platform_windows_set_title' arguments: #(3 8) result: 1>
	<var: #win type: 'int64_t'>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| title ok |
	title := nativeCountedText copyTerminated: bytes size: n.
	title isNull ifTrue: [^0].
	ok := windows setTitle: win asInt32 title: title.
	libc free: title.
	^ok ifTrue: [1] ifFalse: [0]
!
ffiClipboardGet: receipt capacity: cap
	<function>
	<approvedFFI: 410 symbol: 'platform_windows_clipboard_get' arguments: #(9) result: 1>
	<var: #receipt type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| row s |
	row := pagedOutput roomFor: receipt capacity: cap.
	row isNull ifTrue: [^-1].
	s := windows clipboardGet.
	s isNull ifTrue: [^-1].
	(pagedOutput adopt: row bytes: (self cCoerce: s to: 'uint8_t *')
		count: (libc strlen: s) receipt: receipt) ifTrue: [^1].
	libc free: s.
	^-1
!
ffiClipboardSet: bytes size: n
	<function>
	<approvedFFI: 411 symbol: 'platform_windows_clipboard_set' arguments: #(8) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| s ok |
	s := nativeCountedText copyTerminated: bytes size: n.
	s isNull ifTrue: [^0].
	ok := windows clipboardSet: s.
	libc free: s.
	^ok ifTrue: [1] ifFalse: [0]
!
ffiPlatformLastError: bytes capacity: cap
	<function>
	<approvedFFI: 415 symbol: 'platform_last_error' arguments: #(9) result: 1>
	<var: #bytes type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| s n |
	s := common lastErrorString.
	n := libc strlen: s.
	n > cap ifTrue: [^-1].
	n ~= 0 ifTrue: [libc memcpy: bytes from: s size: n].
	^n asInt32
!
ffiPlatformHandleCounts: bytes capacity: cap
	<function>
	<approvedFFI: 417 symbol: 'platform_handle_counts' arguments: #(9) result: 1>
	<var: #bytes type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| counts |
	cap ~= 88 ifTrue: [^0].
	counts := self local: 'int64_t[11]'.
	common handleCounts: counts.
	0 to: 10 do: [:i | self windowWire: bytes at: i * 8 put: (counts at: i) asUInt64 count: 8].
	^1
!
ffiDroppedEvents
	<function>
	<approvedFFI: 418 symbol: 'platform_events_dropped' arguments: #() result: 3>
	<returns: 'int64_t'>
	^events dropped
!
ffiClipboardData: bytes size: n ticket: ticket
	<function>
	<approvedFFI: 420 symbol: 'platform_windows_clipboard_data' arguments: #(8 4) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	| mime size data ok |
	(ownedFFI ownedCanProduce: ticket) ifFalse: [^-1].
	mime := nativeCountedText copyTerminated: bytes size: n.
	mime isNull ifTrue: [^-1].
	size := self local: 'size_t'.
	size value: 0.
	data := windows clipboardData: mime size: size.
	libc free: mime.
	data isNull ifTrue: [^0].
	(size value = 0 or: [size value > 20971520]) ifTrue: [
		windows freeClipboardData: data.
		^0].
	ok := ownedFFI ownedPublish: ticket from: (self cCoerce: data to: 'const uint8_t *') size: size value.
	windows freeClipboardData: data.
	^ok ifTrue: [1] ifFalse: [-1]
!
ffiWindow: win width: w height: h
	<function>
	<approvedFFI: 421 symbol: 'platform_windows_set_size' arguments: #(3 3 3) result: 1>
	<var: #win type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	(w < 1 or: [w > 16r7FFFFFFF or: [h < 1 or: [h > 16r7FFFFFFF]]]) ifTrue: [^0].
	^(windows setSize: win asInt32 width: w asInt32 height: h asInt32) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: '*VM-Platform-window-events'!
ffiEventsNext: bytes capacity: headerCap receipt: receipt capacity: cap
	<function>
	<approvedFFI: 412 symbol: 'platform_events_next' arguments: #(9 9) result: 1>
	<var: #bytes type: 'uint8_t *'>
	<var: #headerCap type: 'uint64_t'>
	<var: #receipt type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| e row headerStart receiptStart |
	(headerCap ~= 80 or: [cap ~= 16]) ifTrue: [
		common setError: 'wrong event output buffer size'.
		^-1].
	headerStart := self cCoerce: bytes to: 'uintptr_t'.
	receiptStart := self cCoerce: receipt to: 'uintptr_t'.
	(headerStart < (receiptStart + cap) and: [receiptStart < (headerStart + headerCap)]) ifTrue: [
		common setError: 'event header and receipt overlap'.
		^-1].
	0 to: 15 do: [:i | (receipt at: i) ~= 0 ifTrue: [
		common setError: 'event output requires a fresh receipt'.
		^-1]].
	e := self local: 'pf_event'.
	(events peekForFFI: e) ifFalse: [
		"Even an empty read rearms the input semaphore."
		events next: e.
		^0].
	e text notNull ifTrue: [
		row := pagedOutput roomFor: receipt capacity: cap.
		row isNull ifTrue: [^-1].
		(pagedOutput adopt: row bytes: (self cCoerce: e text to: 'uint8_t *')
			count: (libc strlen: e text) receipt: receipt) ifFalse: [^-1]].
	self windowWire: bytes at: 0 put: e type asInt64 asUInt64 count: 8.
	self windowWire: bytes at: 8 put: e timeMs asUInt64 count: 8.
	self windowWire: bytes at: 16 put: (self bitsOfDouble: e x) count: 8.
	self windowWire: bytes at: 24 put: (self bitsOfDouble: e y) count: 8.
	self windowWire: bytes at: 32 put: e key asUInt64 count: 8.
	self windowWire: bytes at: 40 put: e mods asUInt32 count: 4.
	self windowWire: bytes at: 44 put: e xkind asUInt32 count: 4.
	self windowWire: bytes at: 48 put: e ival asUInt64 count: 8.
	self windowWire: bytes at: 56 put: (self bitsOfDouble: e dx) count: 8.
	self windowWire: bytes at: 64 put: (self bitsOfDouble: e dy) count: 8.
	self windowWire: bytes at: 72 put: e window asUInt32 count: 4.
	self windowWire: bytes at: 76 put: 0 count: 4.
	"Only the VM thread touches the FIFO. Transfer its text ownership to the lease."
	events next: e.
	^1
!
ffiEventsInject: bytes size: n
	<function>
	<approvedFFI: 413 symbol: 'platform_events_inject' arguments: #(8) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| e t k |
	n < 80 ifTrue: [^0].
	t := (self windowWire: bytes at: 0 count: 8) asInt64.
	t <= 0 ifTrue: [^0].
	k := (self windowWire: bytes at: 44 count: 4) asInt32.
	(k < 0 or: [k > 4 or: [k ~= 3 and: [n ~= 80]]]) ifTrue: [^0].
	e := self local: 'pf_event'.
	e type: t asInt32.
	e timeMs: ((self windowWire: bytes at: 76 count: 4) = 0
		ifTrue: [common nowMs]
		ifFalse: [(self windowWire: bytes at: 8 count: 8) asInt64]).
	e x: (self doubleFromBits: (self windowWire: bytes at: 16 count: 8)).
	e y: (self doubleFromBits: (self windowWire: bytes at: 24 count: 8)).
	e key: (self windowWire: bytes at: 32 count: 8) asInt64.
	e mods: (self windowWire: bytes at: 40 count: 4) asInt32.
	e xkind: k.
	e ival: (self windowWire: bytes at: 48 count: 8) asInt64.
	e dx: (self doubleFromBits: (self windowWire: bytes at: 56 count: 8)).
	e dy: (self doubleFromBits: (self windowWire: bytes at: 64 count: 8)).
	e window: (self windowWire: bytes at: 72 count: 4) asInt32.
	k = 3 ifTrue: [
		e text: (nativeCountedText copyTerminated: bytes + 80 size: n - 80).
		e text isNull ifTrue: [^0]].
	events push: e.
	libc free: e text.
	scheduler requestInterruptCheck.
	^1
!
windowWire: bytes at: offset put: value count: n
	"Encode an unaligned little-endian field, independent of C struct layout."
	<function>
	<var: #bytes type: 'uint8_t *'>
	<var: #offset type: 'int32_t'>
	<var: #value type: 'uint64_t'>
	<var: #n type: 'int32_t'>
	0 to: n - 1 do: [:i | bytes at: offset + i put: (value >> (i * 8)) asUInt8]
!
windowWire: bytes at: offset count: n
	<function>
	<var: #bytes type: 'const uint8_t *'>
	<var: #offset type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<returns: 'uint64_t'>
	| v |
	v := 0 asUInt64.
	0 to: n - 1 do: [:i | v := v bitOr: ((bytes at: offset + i) asUInt64 << (i * 8))].
	^v
! !

!SDLPlatform methodsFor: '*VM-Platform-window-desktop'!
ffiWindow: win opacity: permille
	"Show the window at permille / 1000 opacity: a desktop window through the compositor's alpha modifier, another through SDL."
	<function>
	<approvedFFI: 423 symbol: 'platform_windows_set_opacity' arguments: #(3 3) result: 1>
	<var: #win type: 'int64_t'>
	<var: #permille type: 'int64_t'>
	<returns: 'int32_t'>
	(permille < 0 or: [permille > 1000]) ifTrue: [^0].
	^(windows setOpacity: win asInt32 permille: permille asInt32) ifTrue: [1] ifFalse: [0]
!
ffiWindow: win fillRects: bytes size: n
	"A transparent window (which SDL_GPU does not draw): its own pixels cleared, filled with rectangles and shown. 20 bytes a rectangle, little-endian: x, y, width, height (pixels, int32) and rgba (16rRRGGBBAA, premultiplied, uint32)."
	<function>
	<approvedFFI: 424 symbol: 'platform_windows_fill_rects' arguments: #(3 8) result: 1>
	<var: #win type: 'int64_t'>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| w count o |
	(n rem: 20) = 0 ifFalse: [^0].
	w := win asInt32.
	(windows clearSurface: w) ifFalse: [^0].
	count := (n quo: 20) asInt64.
	0 to: count - 1 do: [:i |
		o := (i * 20) asInt32.
		windows fillSurface: w
			x: (self windowWire: bytes at: o count: 4) asInt32
			y: (self windowWire: bytes at: o + 4 count: 4) asInt32
			width: (self windowWire: bytes at: o + 8 count: 4) asInt32
			height: (self windowWire: bytes at: o + 12 count: 4) asInt32
			rgba: (self windowWire: bytes at: o + 16 count: 4) asUInt32].
	^(windows presentSurface: w) ifTrue: [1] ifFalse: [0]
!
ffiWindow: win icon: bytes size: n width: w
	"Set the window's icon: w pixels wide, 4 bytes each (red, green, blue, alpha; not premultiplied), rows top to bottom."
	<function>
	<approvedFFI: 425 symbol: 'platform_windows_set_icon' arguments: #(3 8 3) result: 1>
	<var: #win type: 'int64_t'>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #w type: 'int64_t'>
	<returns: 'int32_t'>
	| h |
	(w < 1 or: [w > 1024]) ifTrue: [^0].
	(n rem: (w * 4) asUInt64) = 0 ifFalse: [^0].
	h := (n quo: (w * 4) asUInt64) asInt64.
	(h < 1 or: [h > 1024]) ifTrue: [^0].
	^(windows setIcon: win asInt32 pixels: bytes width: w asInt32 height: h asInt32) ifTrue: [1] ifFalse: [0]
! !
