Object subclass: #WindowFFIProof
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'WindowFFIProof'!

!WindowFFIProof class methodsFor: 'helpers'!
require: ok because: message
	ok ifFalse: [self error: message]
!
poison: sources on: behavior during: aBlock
	| originals |
	originals := sources collect: [:source | | method |
		method := Compiler compileMethod: source in: behavior classified: nil.
		{method. behavior compiledMethodAt: method selector}].
	^[
		originals do: [:pair | behavior addSelector: pair first selector withMethod: pair first].
		aBlock value
	] ensure: [
		originals do: [:pair | behavior addSelector: pair second selector withMethod: pair second]]
! !

!WindowFFIProof class methodsFor: 'headless'!
headless
	"The workload does not open files, windows, clipboard or video devices."
	| g vm drops counts err sample out values event |
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
	self poison: #(
		'primDroppedEvents self error: ''legacy dropped counter entered'''
		'primPlatformHandleCounts self error: ''legacy handle counts entered''')
		on: VirtualMachine during: [
		self poison: #(
			'injectEvent: obj self error: ''legacy inject entered'''
			'nextEvent: obj self error: ''legacy dequeue entered'''
			'lastError self error: ''legacy last error entered''')
			on: g class during: [
			self require: vm ffiCandidatePrimDroppedEvents = drops because: 'counter baseline'.
			self require: vm ffiCandidatePrimPlatformHandleCounts = counts because: 'handle counts'.
			self require: g ffiCandidateLastError = err because: 'initial last error'.
			self require: (g ffiCandidateNextEvent: out) isNil because: 'empty event queue'.
			self require: (out at: 9) = #untouched because: 'empty read mutated output'.
			values := {nil. -123. true. false. ''. 'éλ', (String with: (Character value: 16rDCFF)). {1. -2.25}. (2.25 @ -3)}.
			values do: [:extra |
				event := sample copy.
				event at: 7 put: extra.
				self require: (g ffiCandidateInjectEvent: event) == g because: 'inject receiver'.
				event at: 1 put: 99].
			1 to: values size do: [:i |
				| want |
				want := values at: i.
				want class == Array ifTrue: [want := want first @ want second].
				self require: (g ffiCandidateNextEvent: out) == out because: 'dequeue array identity'.
				self require: (out copyFrom: 1 to: 6) = (sample copyFrom: 1 to: 6) because: 'event scalar fields or FIFO'.
				self require: ((out at: 3) isFloat and: [(out at: 4) isFloat]) because: 'coordinates are not floats'.
				self require: (out at: 7) = want because: 'event extra'.
				self require: (out at: 8) = 42 because: 'event window association'.
				self require: (out at: 9) = #untouched because: 'event overwrote trailing slot'].
			self require: (g ffiCandidateNextEvent: out) isNil because: 'unexpected duplicate event'.
			event := {1. nil. 0. 0. #key. nil. nil. nil}.
			g ffiCandidateInjectEvent: event.
			g ffiCandidateNextEvent: out.
			self require: ((out at: 2) class == SmallInteger and: [(out at: 2) >= 0]) because: 'default timestamp'.
			self require: ((out at: 5) = 0 and: [(out at: 6) = 0 and: [(out at: 8) isNil]]) because: 'default event fields'.
			4097 timesRepeat: [g ffiCandidateInjectEvent: sample].
			self require: vm ffiCandidatePrimDroppedEvents = (drops + 1) because: 'overflow not counted exactly once'].
		4096 timesRepeat: [self require: (g nextEvent: out) == out because: 'overflow consumed a queued event'].
		self require: (g nextEvent: out) isNil because: 'overflow enqueued one extra event'.
		self require: vm ffiCandidatePrimDroppedEvents = (drops + 1) because: 'read reset cumulative dropped counter'].
	^true
! !

!WindowFFIProof class methodsFor: 'display CI'!
legacyClipboardData: mime
	<primitive: 'clipboardData'>
	self error: 'legacy clipboard data primitive failed'
!
display
	| g vm w oldClipboard before title mime unadvertisedMime textBytes unadvertisedBytes emptyBytes actual pixels limit |
	g := GPUPrimitives.
	vm := Smalltalk vm.
	w := nil.
	before := vm primPlatformHandleCounts third.
	oldClipboard := g clipboardGet.
	title := 'FFI café λ'.
	mime := 'text/plain;charset=utf-8'.
	unadvertisedMime := 'application/x-window-ffi-unavailable'.
	[
		g clipboardSet: title.
		textBytes := self legacyClipboardData: mime.
		self require: textBytes = title utf8Encoded because: 'legacy clipboard MIME bytes'.
		"X11 can pass an unadvertised target to the local selection callback,
		which can return text bytes even for a non-text MIME type."
		unadvertisedBytes := self legacyClipboardData: unadvertisedMime.
		g clipboardSet: ''.
		emptyBytes := self legacyClipboardData: mime.
		self require: emptyBytes isNil because: 'legacy cleared clipboard MIME must answer nil'.
		vm stderrWrite: 'legacy clipboard MIME: unadvertised ', unadvertisedBytes printString,
			'; cleared ', emptyBytes printString, (String with: Character lf).
		self poison: #(
			'openWindow: w height: h title: t flags: f self error: ''legacy open entered'''
			'windowSize: w self error: ''legacy size entered'''
			'windowPixelSize: w self error: ''legacy pixel size entered'''
			'window: w title: t self error: ''legacy title entered'''
			'window: w width: x height: y self error: ''legacy resize entered'''
			'clipboardGet self error: ''legacy clipboard get entered'''
			'clipboardSet: text self error: ''legacy clipboard set entered'''
			'clipboardData: text self error: ''legacy clipboard data entered''')
			on: g class during: [
			w := g ffiCandidateOpenWindow: 128 height: 96 title: title flags: 3.
			self require: (w class == SmallInteger and: [w > 0]) because: 'window creation'.
			self require: vm ffiCandidatePrimPlatformHandleCounts third = (before + 1) because: 'window handle accounting'.
			self require: (g ffiCandidateWindowSize: w) = #(128 96) because: 'point size'.
			pixels := g ffiCandidateWindowPixelSize: w.
			self require: (pixels class == Array and: [pixels size = 2 and: [pixels allSatisfy: [:n | n > 0]]]) because: 'pixel size'.
			self require: (g ffiCandidateWindow: w title: title, ' renamed') == g because: 'title operation'.
			self require: (g ffiCandidateWindow: w width: 0 height: 120) == false because: 'invalid resize status'.
			self require: (g ffiCandidateWindow: w width: 160 height: 120) == g because: 'window resize operation'.
			limit := Time millisecondClockValue + 3000.
			[(actual := g ffiCandidateWindowSize: w) = #(160 120) or: [Time millisecondClockValue >= limit]]
				whileFalse: [(Delay forMilliseconds: 10) wait].
			self require: actual = #(160 120) because: 'window did not resize'.
			pixels := g ffiCandidateWindowPixelSize: w.
			self require: (pixels class == Array and: [pixels size = 2 and: [pixels allSatisfy: [:n | n > 0]]]) because: 'resized pixel size'.
			self require: (g ffiCandidateClipboardSet: title) == g because: 'clipboard set'.
			self require: g ffiCandidateClipboardGet = title because: 'clipboard text roundtrip'.
			self require: (g ffiCandidateClipboardData: mime) = textBytes because: 'clipboard MIME bytes differ from legacy'.
			self require: (g ffiCandidateClipboardData: unadvertisedMime) = unadvertisedBytes
				because: 'unadvertised clipboard MIME differs from legacy'.
			self require: (g ffiCandidateClipboardSet: '') == g because: 'clear clipboard'.
			self require: g ffiCandidateClipboardGet = '' because: 'empty clipboard text'.
			self require: (g ffiCandidateClipboardData: mime) = emptyBytes because: 'cleared clipboard MIME differs from legacy'.
			self require: ([g ffiCandidateWindowSize: -1. false] on: GPUError do: [:e | e operation = 'windowSize'])
				because: 'completed invalid handle did not signal correct GPUError'.
			self require: (g ffiCandidateLastError includesSubstring: 'bad window handle') because: 'last error after native window error'].
		self require: (g windowSize: w) = (g ffiCandidateWindowSize: w) because: 'legacy point size comparison'.
		self require: (g windowPixelSize: w) = (g ffiCandidateWindowPixelSize: w) because: 'legacy pixel size comparison'.
		self require: ([(g ffiCandidateWindow: w title: (String with: (Character value: 0))). false] on: GPUError do: [:e | e operation = 'windowSetTitle'])
			because: 'embedded NUL must fail'
	] ensure: [
		[w ifNotNil: [g closeWindow: w]] ensure: [g clipboardSet: oldClipboard]].
	self require: vm primPlatformHandleCounts third = before because: 'window leaked'.
	^true
! !
