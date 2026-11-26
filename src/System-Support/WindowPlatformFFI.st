Object subclass: #WindowPlatformFFI
	instanceVariableNames: ''
	classVariableNames: 'OpenCall SizeCall PixelSizeCall TitleCall SetSizeCall OpacityCall FillRectsCall IconCall DesktopAreaCall ClipboardGetCall ClipboardSetCall ClipboardDataCall NextEventCall InjectEventCall LastErrorCall HandleCountsCall DroppedCall'
	package: 'System-Support'!

WindowPlatformFFI comment: 'Prepared private window/input bindings and their little-endian event codec. Only the hosted platform uses these bindings.'!

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
opacityCall
	^OpacityCall ifNil: [OpacityCall := PlatformFFI bind: #(call 'platform' 'platform_windows_set_opacity' (i64 i64) i32)]
!
fillRectsCall
	^FillRectsCall ifNil: [FillRectsCall := PlatformFFI bind: #(call 'platform' 'platform_windows_fill_rects' (i64 bytesWithLength) i32)]
!
iconCall
	^IconCall ifNil: [IconCall := PlatformFFI bind: #(call 'platform' 'platform_windows_set_icon' (i64 bytesWithLength i64) i32)]
!
desktopAreaCall
	^DesktopAreaCall ifNil: [DesktopAreaCall := PlatformFFI bind: #(call 'platform' 'platform_windows_desktop_area' (writableBytesWithLength) i32)]
!
clipboardGetCall
	^ClipboardGetCall ifNil: [ClipboardGetCall := PlatformFFI bind: #(call 'platform' 'platform_windows_clipboard_get' (writableBytesWithLength) i32)]
!
clipboardSetCall
	^ClipboardSetCall ifNil: [ClipboardSetCall := PlatformFFI bind: #(call 'platform' 'platform_windows_clipboard_set' (bytesWithLength) i32)]
!
clipboardDataCall
	^ClipboardDataCall ifNil: [ClipboardDataCall := PlatformFFI bind: #(call 'platform' 'platform_windows_clipboard_data' (bytesWithLength u64) i32)]
!
nextEventCall
	^NextEventCall ifNil: [NextEventCall := PlatformFFI bind: #(call 'platform' 'platform_events_next' (writableBytesWithLength writableBytesWithLength) i32)]
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

!WindowPlatformFFI class methodsFor: 'diagnostics'!
lastError
	| binding bytes count |
	binding := self lastErrorCall.
	binding isNil ifTrue: [^nil].
	bytes := ByteArray new: 1024.
	count := binding tryInvoke1: {bytes. 1. bytes size}.
	(count == false or: [count < 0]) ifTrue: [^nil].
	count = 0 ifTrue: [^''].
	^PlatformFFI textFromBytes: (bytes copyFrom: 1 to: count)
! !

!WindowPlatformFFI class methodsFor: 'counted text'!
cTextBytes: anObject
	"Accept String/Symbol, exact UTF-8 ByteArray, and stored byte or word code points."
	| class bytes |
	class := anObject class.
	(class == ByteArray or: [class == ByteString or: [
		class == WideString or: [class == ByteSymbol or: [class == WideSymbol]]]])
		ifTrue: [^PlatformFFI cTextBytes: anObject].
	((class isBytes or: [class isWords]) and: [
		class ~~ CompiledMethod and: [(class inheritsFrom: CompiledMethod) not]]) ifFalse: [^nil].
	bytes := ByteArray new: anObject basicSize streamContents: [:out |
		1 to: anObject basicSize do: [:i | PlatformFFI putTextCodePoint: (anObject basicAt: i) on: out]].
	^(bytes includes: 0) ifTrue: [nil] ifFalse: [bytes]
! !

!WindowPlatformFFI class methodsFor: 'event injection'!
tryInjectEvent: event
	"True after one successful native enqueue (the FIFO may drop a full queue).
	False for unsupported or invalid input. No retry after native entry."
	| binding bytes |
	binding := self injectEventCall.
	binding isNil ifTrue: [^false].
	bytes := self encodeEvent: event.
	bytes isNil ifTrue: [^false].
	^(binding tryInvoke1: {bytes. 1. bytes size}) = 1
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
	"An 80-byte header plus optional counted text."
	| type time x y extra kind val dx dy text b |
	(a class instSpec = VMConstants fVar and: [a basicSize >= 8]) ifFalse: [^nil].
	type := a basicAt: 1.
	(type class == SmallInteger and: [type > 0]) ifFalse: [^nil].
	time := a basicAt: 2.
	x := self eventNumber: (a basicAt: 3).
	y := self eventNumber: (a basicAt: 4).
	(x isNil or: [y isNil]) ifTrue: [^nil].
	extra := a basicAt: 7.
	kind := 0.
	val := 0.
	extra isNil ifFalse: [
		extra class == SmallInteger
			ifTrue: [kind := 1. val := extra]
			ifFalse: [
				(extra == true or: [extra == false])
					ifTrue: [kind := 2. val := extra ifTrue: [1] ifFalse: [0]]
					ifFalse: [
						(extra class == Point or: [extra class instSpec = VMConstants fVar and: [extra basicSize = 2]])
							ifTrue: [
								kind := 4.
								extra class == Point
									ifTrue: [dx := extra x. dy := extra y]
									ifFalse: [dx := extra basicAt: 1. dy := extra basicAt: 2].
								dx := self eventNumber: dx.
								dy := self eventNumber: dy.
								(dx isNil or: [dy isNil]) ifTrue: [^nil]]
							ifFalse: [
								kind := 3.
								text := self cTextBytes: extra.
								text isNil ifTrue: [^nil]]]]].
	b := ByteArray new: 80 + (text isNil ifTrue: [0] ifFalse: [text size]).
	self signed64: type at: 1 in: b.
	time class == SmallInteger ifTrue: [
		self signed64: time at: 9 in: b.
		b uint32At: 77 put: 1].
	b float64At: 17 put: x.
	b float64At: 25 put: y.
	self signed64: (self eventSmallInteger: (a basicAt: 5)) at: 33 in: b.
	b uint32At: 41 put: ((self eventSmallInteger: (a basicAt: 6)) bitAnd: 16rFFFFFFFF).
	b uint32At: 45 put: kind.
	self signed64: val at: 49 in: b.
	kind = 4 ifTrue: [b float64At: 57 put: dx; float64At: 65 put: dy].
	b uint32At: 73 put: ((self eventSmallInteger: (a basicAt: 8)) bitAnd: 16rFFFFFFFF).
	(text notNil and: [text notEmpty]) ifTrue: [b replaceFrom: 81 to: b size with: text startingAt: 1].
	^b
!
decodeEvent: b text: text into: a
	| kind extra window |
	kind := b uint32At: 45.
	"No caseOf: here: it is VM-Lowtalk's, which an application's runtime image does not have."
	extra := nil.
	kind = 1 ifTrue: [extra := self signed64At: 49 in: b].
	kind = 2 ifTrue: [extra := (self signed64At: 49 in: b) ~= 0].
	kind = 3 ifTrue: [extra := PlatformFFI textFromBytes: text].
	kind = 4 ifTrue: [extra := (b float64At: 57) @ (b float64At: 65)].
	(kind between: 0 and: 4) ifFalse: [^self error: 'unknown event payload kind ', kind printString].
	window := self signed32At: 73 in: b.
	a basicAt: 1 put: (self signed64At: 1 in: b);
		basicAt: 2 put: (self signed64At: 9 in: b);
		basicAt: 3 put: (b float64At: 17);
		basicAt: 4 put: (b float64At: 25);
		basicAt: 5 put: (self signed64At: 33 in: b);
		basicAt: 6 put: (self signed32At: 41 in: b);
		basicAt: 7 put: extra;
		basicAt: 8 put: (window = 0 ifTrue: [nil] ifFalse: [window]).
	^a
! !
