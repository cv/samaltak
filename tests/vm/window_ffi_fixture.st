Object subclass: #WindowFFIProof
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'WindowFFIProof'!

!WindowFFIProof class methodsFor: 'helpers'!
require: ok because: message
	ok ifFalse: [self error: message]
! !

!WindowFFIProof class methodsFor: 'headless'!
headless
	"The workload does not open files, windows, clipboard or video devices."
	| g vm drops counts err sample out values event raw |
	g := GPUPrimitives.
	vm := Smalltalk vm.
	drops := vm primDroppedEvents.
	counts := vm primPlatformHandleCounts.
	self require: (counts class == Array and: [counts size = 11 and: [counts third = 0]]) because: 'not a fresh hosted platform'.
	err := g lastError.
	out := Array new: 9.
	out at: 9 put: #untouched.
	sample := #(17 123 2.5 -8 97 -2 nil 42).
	self require: (g nextEvent: out) isNil because: 'unexpected initial input'.
	self require: err isString because: 'last error text'.
	self require: (g nextEvent: out) isNil because: 'empty event queue'.
	self require: (out at: 9) = #untouched because: 'empty read mutated output'.
	values := {nil. -123. true. false. ''. 'éλ', (String with: (Character value: 16rDCFF)). {1. -2.25}. (2.25 @ -3)}.
	values do: [:extra |
		event := sample copy.
		event at: 7 put: extra.
		self require: (g injectEvent: event) == g because: 'inject receiver'.
		event at: 1 put: 99].
	1 to: values size do: [:i |
		| want |
		want := values at: i.
		want class == Array ifTrue: [want := want first @ want second].
		self require: (g nextEvent: out) == out because: 'dequeue array identity'.
		self require: (out copyFrom: 1 to: 6) = (sample copyFrom: 1 to: 6) because: 'event scalar fields or FIFO'.
		self require: ((out at: 3) isFloat and: [(out at: 4) isFloat]) because: 'coordinates are not floats'.
		self require: (out at: 7) = want because: 'event extra'.
		self require: (out at: 8) = 42 because: 'event window association'.
		self require: (out at: 9) = #untouched because: 'event overwrote trailing slot'].
	self require: (g nextEvent: out) isNil because: 'unexpected duplicate event'.
	g injectEvent: sample.
	raw := ByteArray new: 96.
	self require: (WindowPlatformFFI nextEventCall tryInvoke2: {raw. 1. 80} with: {raw. 80. 16}) = -1
		because: 'overlapping header and receipt accepted'.
	self require: (g nextEvent: out) == out because: 'failed output preflight dequeued the event'.
	event := {1. nil. 0. 0. #key. nil. nil. nil}.
	g injectEvent: event.
	g nextEvent: out.
	self require: ((out at: 2) class == SmallInteger and: [(out at: 2) >= 0]) because: 'default timestamp'.
	self require: ((out at: 5) = 0 and: [(out at: 6) = 0 and: [(out at: 8) isNil]]) because: 'default event fields'.
	4097 timesRepeat: [g injectEvent: sample].
	self require: vm primDroppedEvents = (drops + 1) because: 'overflow not counted exactly once'.
	4096 timesRepeat: [self require: (g nextEvent: out) == out because: 'overflow consumed a queued event'].
	self require: (g nextEvent: out) isNil because: 'overflow enqueued one extra event'.
	self require: vm primDroppedEvents = (drops + 1) because: 'read reset cumulative dropped counter'.
	^true
! !

!WindowFFIProof class methodsFor: 'large headless output'!
largeEvent
	| count payload out text |
	count := 67108868.
	payload := ByteArray new: count withAll: 65.
	payload at: count put: 90.
	out := Array new: 8.
	GPUPrimitives injectEvent: {7. nil. 0. 0. nil. nil. payload. nil}.
	payload := nil.
	self require: (GPUPrimitives nextEvent: out) == out because: 'large event was not dequeued'.
	text := out at: 7.
	self require: (text size = count and: [text first = $A and: [text last = $Z]])
		because: 'large event text truncated or damaged'.
	self require: (GPUPrimitives nextEvent: out) isNil because: 'large event was dequeued twice'.
	^true
! !

!WindowFFIProof class methodsFor: 'display CI'!
display
	| g vm w oldClipboard before title mime unadvertisedMime unadvertisedBytes actual pixels limit |
	g := GPUPrimitives.
	vm := Smalltalk vm.
	w := nil.
	before := vm primPlatformHandleCounts third.
	oldClipboard := g clipboardGet.
	title := 'FFI café λ'.
	mime := 'text/plain;charset=utf-8'.
	unadvertisedMime := 'application/x-window-ffi-unavailable'.
	[
		w := g openWindow: 128 height: 96 title: title flags: 3.
		self require: (w class == SmallInteger and: [w > 0]) because: 'window creation'.
		self require: vm primPlatformHandleCounts third = (before + 1) because: 'window handle accounting'.
		self require: (g windowSize: w) = #(128 96) because: 'point size'.
		pixels := g windowPixelSize: w.
		self require: (pixels class == Array and: [pixels size = 2 and: [pixels allSatisfy: [:n | n > 0]]]) because: 'pixel size'.
		self require: (g window: w title: title, ' renamed') == g because: 'title operation'.
		self require: (g window: w width: 0 height: 120) == false because: 'invalid resize status'.
		self require: (g window: w width: 160 height: 120) == g because: 'window resize operation'.
		limit := Time millisecondClockValue + 3000.
		[(actual := g windowSize: w) = #(160 120) or: [Time millisecondClockValue >= limit]]
			whileFalse: [(Delay forMilliseconds: 10) wait].
		self require: actual = #(160 120) because: 'window did not resize'.
		pixels := g windowPixelSize: w.
		self require: (pixels class == Array and: [pixels size = 2 and: [pixels allSatisfy: [:n | n > 0]]]) because: 'resized pixel size'.
		self require: (g clipboardSet: title) == g because: 'clipboard set'.
		self require: g clipboardGet = title because: 'clipboard text roundtrip'.
		self require: (g clipboardData: mime) = title utf8Encoded because: 'advertised clipboard MIME bytes'.
		"X11 can route an unadvertised MIME to its local clipboard callback."
		unadvertisedBytes := g clipboardData: unadvertisedMime.
		self require: (unadvertisedBytes isNil or: [unadvertisedBytes = title utf8Encoded])
			because: 'unexpected clipboard bytes for unadvertised MIME'.
		self require: (g clipboardSet: '') == g because: 'clear clipboard'.
		self require: g clipboardGet = '' because: 'empty clipboard text'.
		self require: (g clipboardData: mime) isNil because: 'cleared clipboard MIME must be absent'.
		self require: ([g windowSize: -1. false] on: GPUError do: [:e | e operation = 'windowSize'])
			because: 'completed invalid handle did not signal correct GPUError'.
		self require: (g lastError includesSubstring: 'bad window handle') because: 'last error after native window error'.
		self require: ([(g window: w title: (String with: (Character value: 0))). false] on: GPUError do: [:e | e operation = 'windowSetTitle'])
			because: 'embedded NUL must fail'
	] ensure: [
		[w ifNotNil: [g closeWindow: w]] ensure: [g clipboardSet: oldClipboard]].
	self require: vm primPlatformHandleCounts third = before because: 'window leaked'.
	^true
! !
