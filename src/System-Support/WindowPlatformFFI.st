Object subclass: #WindowPlatformFFI
	instanceVariableNames: ''
	classVariableNames: 'OpenCall SizeCall PixelSizeCall TitleCall SetSizeCall ClipboardGetCall ClipboardSetCall ClipboardDataCall NextEventCall InjectEventCall LastErrorCall HandleCountsCall DroppedCall'
	package: 'System-Support'!

WindowPlatformFFI comment: 'Prepared private window/input bindings and their little-endian event codec. Candidates are explicit; old images and firmware still use the original primitive when a call cannot enter.'!

!WindowPlatformFFI class methodsFor: 'bindings'!
openCall
	^OpenCall ifNil: [OpenCall := PlatformFFI bind: #(call 'platform' 'platform_windows_open' (i64 i64 bytesWithLength i64) i32)]
!
sizeCall
	^SizeCall ifNil: [SizeCall := PlatformFFI bind: #(call 'platform' 'platform_windows_size' (i64 writableBytesWithLength) i32)]
!
pixelSizeCall
	^PixelSizeCall ifNil: [PixelSizeCall := PlatformFFI bind: #(call 'platform' 'platform_windows_pixel_size' (i64 writableBytesWithLength) i32)]
!
titleCall
	^TitleCall ifNil: [TitleCall := PlatformFFI bind: #(call 'platform' 'platform_windows_set_title' (i64 bytesWithLength) i32)]
!
setSizeCall
	^SetSizeCall ifNil: [SetSizeCall := PlatformFFI bind: #(call 'platform' 'platform_windows_set_size' (i64 i64 i64) i32)]
!
clipboardGetCall
	^ClipboardGetCall ifNil: [ClipboardGetCall := PlatformFFI bind: #(call 'platform' 'platform_windows_clipboard_get' (u64) i32)]
!
clipboardSetCall
	^ClipboardSetCall ifNil: [ClipboardSetCall := PlatformFFI bind: #(call 'platform' 'platform_windows_clipboard_set' (bytesWithLength) i32)]
!
clipboardDataCall
	^ClipboardDataCall ifNil: [ClipboardDataCall := PlatformFFI bind: #(call 'platform' 'platform_windows_clipboard_data' (bytesWithLength u64) i32)]
!
nextEventCall
	^NextEventCall ifNil: [NextEventCall := PlatformFFI bind: #(call 'platform' 'platform_events_next' (u64) i32)]
!
injectEventCall
	^InjectEventCall ifNil: [InjectEventCall := PlatformFFI bind: #(call 'platform' 'platform_events_inject' (bytesWithLength) i32)]
!
lastErrorCall
	^LastErrorCall ifNil: [LastErrorCall := PlatformFFI bind: #(call 'platform' 'platform_last_error' (writableBytesWithLength) i32)]
!
handleCountsCall
	^HandleCountsCall ifNil: [HandleCountsCall := PlatformFFI bind: #(call 'platform' 'platform_handle_counts' (writableBytesWithLength) i32)]
!
droppedCall
	^DroppedCall ifNil: [DroppedCall := PlatformFFI bind: #(call 'platform' 'platform_events_dropped' () i64)]
! !

!WindowPlatformFFI class methodsFor: 'wire codec'!
signed32At: i in: bytes
	| n |
	n := bytes uint32At: i.
	^n < 16r80000000 ifTrue: [n] ifFalse: [n - 16r100000000]
!
signed64At: i in: bytes
	^(bytes uint32At: i) + ((self signed32At: i + 4 in: bytes) bitShift: 32)
!
signed64: n at: i in: bytes
	bytes uint32At: i put: (n bitAnd: 16rFFFFFFFF).
	bytes uint32At: i + 4 put: ((n bitShift: -32) bitAnd: 16rFFFFFFFF)
!
eventNumber: n
	n class == SmallInteger ifTrue: [^n asFloat].
	(n class == SmallFloat64 or: [n class == BoxedFloat64]) ifTrue: [^n].
	^nil
!
eventSmallInteger: n
	^n class == SmallInteger ifTrue: [n] ifFalse: [0]
!
encodeEvent: a
	"An 80-byte header plus optional counted text. Exact ordinary Array and Point are the fast-path shapes; unusual F_VAR objects stay with the primitive."
	| type time x y extra kind val dx dy text b |
	(a class == Array and: [a size >= 8]) ifFalse: [^nil].
	type := a first.
	(type class == SmallInteger and: [type > 0]) ifFalse: [^nil].
	time := a at: 2.
	x := self eventNumber: (a at: 3).
	y := self eventNumber: (a at: 4).
	(x isNil or: [y isNil]) ifTrue: [^nil].
	extra := a at: 7.
	kind := 0.
	val := 0.
	extra isNil ifFalse: [
		extra class == SmallInteger
			ifTrue: [kind := 1. val := extra]
			ifFalse: [
				(extra == true or: [extra == false])
					ifTrue: [kind := 2. val := extra ifTrue: [1] ifFalse: [0]]
					ifFalse: [
						(extra class == Point or: [extra class == Array and: [extra size = 2]])
							ifTrue: [
								kind := 4.
								extra class == Point
									ifTrue: [dx := extra x. dy := extra y]
									ifFalse: [dx := extra first. dy := extra second].
								dx := self eventNumber: dx.
								dy := self eventNumber: dy.
								(dx isNil or: [dy isNil]) ifTrue: [^nil]]
							ifFalse: [
								kind := 3.
								text := PlatformFFI cTextBytes: extra.
								text isNil ifTrue: [^nil]]]]].
	b := ByteArray new: 80 + (text isNil ifTrue: [0] ifFalse: [text size]).
	self signed64: type at: 1 in: b.
	time class == SmallInteger ifTrue: [
		self signed64: time at: 9 in: b.
		b uint32At: 77 put: 1].
	b float64At: 17 put: x.
	b float64At: 25 put: y.
	self signed64: (self eventSmallInteger: (a at: 5)) at: 33 in: b.
	b uint32At: 41 put: ((self eventSmallInteger: (a at: 6)) bitAnd: 16rFFFFFFFF).
	b uint32At: 45 put: kind.
	self signed64: val at: 49 in: b.
	kind = 4 ifTrue: [b float64At: 57 put: dx; float64At: 65 put: dy].
	b uint32At: 73 put: ((self eventSmallInteger: (a at: 8)) bitAnd: 16rFFFFFFFF).
	(text notNil and: [text notEmpty]) ifTrue: [b replaceFrom: 81 to: b size with: text startingAt: 1].
	^b
!
decodeEvent: b into: a
	| kind extra window |
	kind := b uint32At: 45.
	extra := kind caseOf: {
		[0] -> [nil].
		[1] -> [self signed64At: 49 in: b].
		[2] -> [(self signed64At: 49 in: b) ~= 0].
		[3] -> [PlatformFFI textFromBytes: (b size = 80 ifTrue: [ByteArray new: 0] ifFalse: [b copyFrom: 81 to: b size])].
		[4] -> [(b float64At: 57) @ (b float64At: 65)]}.
	window := self signed32At: 73 in: b.
	a at: 1 put: (self signed64At: 1 in: b);
		at: 2 put: (self signed64At: 9 in: b);
		at: 3 put: (b float64At: 17);
		at: 4 put: (b float64At: 25);
		at: 5 put: (self signed64At: 33 in: b);
		at: 6 put: (self signed32At: 41 in: b);
		at: 7 put: extra;
		at: 8 put: (window = 0 ifTrue: [nil] ifFalse: [window]).
	^a
! !
