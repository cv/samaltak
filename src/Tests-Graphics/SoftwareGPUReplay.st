Object subclass: #SoftwareGPUReplay
	instanceVariableNames: 'gpu dev handles swapchains claimed pipelines samplers cmd windowSize frame passes frames mismatches microseconds'
	classVariableNames: ''
	package: 'Tests-Graphics'!

SoftwareGPUReplay comment: 'I replay a SoftwareGPURecorder''s record (its comment has the format) on a device of the gpu primitives'' protocol that presents on a display, a SoftwareGPU or a subclass (NvComputeGPU), and compare: each pass''s target when it ends (downloaded) and each frame presented with the recorded pixels, byte for byte. After a difference I carry on from the recorded pixels. I am the device''s display: the record''s window, at the size its swapchain records say.

	r := SoftwareGPUReplay replay: ''build/nv/world.nvrec'' on: NvComputeGPU.
	r mismatches        "an empty collection when every pass and frame was the record''s"
	r summary

tests/nv/run.sh (make test-nv) replays the World''s recorded frames on an NvComputeGPU and on a SoftwareGPU.'!

!SoftwareGPUReplay methodsFor: 'initialization'!
setDeviceClass: aClass
	handles := Dictionary new.
	swapchains := Set new.
	claimed := Set new.
	samplers := Dictionary new.
	passes := frames := microseconds := 0.
	mismatches := OrderedCollection new.
	windowSize := #(1 1).
	gpu := aClass on: self.
	dev := gpu createDevice: false.
	pipelines := (0 to: 2) collect: [:blend | | vs fs |
		vs := gpu createShader: dev source: 'vertex' entry: 'vmain' stage: 0 samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
		fs := gpu createShader: dev source: 'fragment' entry: 'fmain' stage: 1 samplers: 1 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
		gpu createPipeline: dev vertex: vs fragment: fs stride: 40 attributes: #(4 0 7 16 7 20 5 24 7 28 2 32) primitive: 0 blend: blend format: 2]
! !

!SoftwareGPUReplay methodsFor: 'accessing'!
gpu
	^gpu
!
passes
	"Pass ends compared."
	^passes
!
frames
	"Presented frames compared."
	^frames
!
mismatches
	"What differed: a String each."
	^mismatches
!
microseconds
	"The time the replay took, reading the record included."
	^microseconds
!
summary
	^gpu class name, ': ', passes printString, ' passes and ', frames printString, ' frames compared, ',
		mismatches size printString, ' differed, in ', (microseconds // 1000) printString, ' ms'
!
release
	"Release my device and everything made on it (an NvComputeGPU: close its GPU)."
	[dev isNil ifFalse: [gpu release: dev]] ensure: [
		dev := nil.
		(gpu respondsTo: #close) ifTrue: [gpu close]]
! !

!SoftwareGPUReplay methodsFor: 'display'!
windowPixelSize: window
	^windowSize
!
presentWindow: window pixels: address width: w height: h
	frame := Machine bytesAt: address count: w * h * 4
! !

!SoftwareGPUReplay methodsFor: 'replaying'!
replay: aPath
	| s t0 |
	t0 := Time microsecondClockValue.
	s := FileStream readOnlyFileNamed: aPath.
	[s binary.
	(s next: 8) asString = 'SAMNVRC1' ifFalse: [^self error: aPath, ' is not a SoftwareGPURecorder record'].
	[s atEnd] whileFalse: [self step: s]]
		ensure: [s close].
	microseconds := Time microsecondClockValue - t0
!
step: aStream
	| header n b words bytes pad |
	header := aStream next: 16.
	n := header uint32At: 5.
	b := header uint32At: 9.
	words := n = 0 ifTrue: [ByteArray new] ifFalse: [aStream next: n * 8].
	bytes := b = 0 ifTrue: [ByteArray new] ifFalse: [aStream next: b].
	pad := 8 - (b \\ 8) \\ 8.
	pad > 0 ifTrue: [aStream next: pad].
	self op: (header uint32At: 1) words: words bytes: bytes
!
op: op words: w bytes: bytes
	| i |
	i := [:k | self int: w at: k].
	op = 1 ifTrue: [^handles at: (i value: 1) put: (gpu createTexture: dev width: (i value: 2) height: (i value: 3) format: (i value: 4) usage: 3)].
	op = 2 ifTrue: [^handles at: (i value: 1) put: (gpu createBuffer: dev usage: 1 size: (i value: 2))].
	op = 3 ifTrue: [^self forget: (i value: 1)].
	op = 4 ifTrue: [^self uploadTexture: (i value: 1) x: (i value: 2) y: (i value: 3) width: (i value: 4) height: (i value: 5) bytes: bytes].
	op = 5 ifTrue: [^gpu uploadBuffer: (handles at: (i value: 1)) bytes: bytes count: (i value: 3) offset: (i value: 2)].
	op = 6 ifTrue: [^self swapchain: (i value: 1) window: (i value: 2) width: (i value: 3) height: (i value: 4)].
	op = 7 ifTrue: [^self clear: (i value: 1) value: (i value: 2)].
	op = 8 ifTrue: [^self draw: w].
	op = 9 ifTrue: [
		^gpu blit: self command source: (handles at: (i value: 1)) rect: ((2 to: 5) collect: [:k | i value: k])
			destination: (handles at: (i value: 6)) rect: ((7 to: 10) collect: [:k | i value: k]) linear: (i value: 11) ~= 0].
	op = 10 ifTrue: [^self passEnd: (i value: 1) bytes: bytes].
	op = 11 ifTrue: [^self present: bytes].
	op = 12 ifTrue: [
		frame := nil.
		gpu submit: self command fence: false.
		^cmd := nil].
	^self error: 'unknown record op ', op printString
! !

!SoftwareGPUReplay methodsFor: 'private'!
int: words at: k
	"The k-th word, a signed 64-bit integer."
	| lo hi |
	lo := words uint32At: k * 8 - 7.
	hi := words uint32At: k * 8 - 3.
	hi >= 16r80000000 ifTrue: [hi := hi - 16r100000000].
	^(hi bitShift: 32) + lo
!
float: words at: k
	^words float64At: k * 8 - 7
!
command
	^cmd ifNil: [cmd := gpu acquireCommandBuffer: dev]
!
forget: h
	"A released texture or buffer; a swapchain texture ends with its command buffer."
	| mine |
	mine := handles removeKey: h ifAbsent: [^self].
	(swapchains includes: mine)
		ifTrue: [swapchains remove: mine]
		ifFalse: [gpu release: mine]
!
uploadTexture: h x: x y: y width: w height: hh bytes: bytes
	| t |
	t := handles at: h.
	gpu uploadTexture: t bytes: bytes x: x y: y width: w height: hh bytesPerRow: bytes size // hh
!
swapchain: h window: window width: w height: hh
	| r |
	windowSize := {w. hh}.
	(claimed includes: window) ifFalse: [
		gpu claim: dev window: window.
		claimed add: window].
	r := gpu acquireSwapchain: self command window: window.
	handles at: h put: r first.
	swapchains add: r first
!
clear: h value: v
	"The clear color whose unorm8 channels give the recorded pixel value."
	| t format c |
	t := handles at: h.
	format := (gpu textureSize: t) last.
	c := format = 1
		ifTrue: [{(v bitAnd: 255) / 255.0. 0.0. 0.0. 0.0}]
		ifFalse: [(0 to: 3) collect: [:k | ((v bitShift: k * -8) bitAnd: 255) / 255.0]].
	format = 3 ifTrue: [c := {c at: 3. c at: 2. c at: 1. c at: 4}].
	gpu endPass: (gpu beginPass: self command target: t clear: c)
!
draw: w
	"target blend scissor(4) viewport(4) viewSize(2) translate(2) texture linear repeat buffer offset first count"
	| i uniforms pass tex |
	i := [:k | self int: w at: k].
	uniforms := ByteArray new: 16.
	1 to: 4 do: [:k | uniforms float32At: k * 4 - 3 put: (self float: w at: k + 10)].
	gpu pushUniforms: self command stage: 0 slot: 0 bytes: uniforms.
	pass := gpu beginPass: cmd target: (handles at: (i value: 1)) clear: nil.
	gpu bindPipeline: pass pipeline: (pipelines at: (i value: 2) + 1).
	gpu bindVertexBuffer: pass slot: 0 buffer: (handles at: (i value: 18)) offset: (i value: 19).
	gpu setScissor: pass x: (i value: 3) y: (i value: 4) width: (i value: 5) height: (i value: 6).
	gpu setViewport: pass x: (self float: w at: 7) y: (self float: w at: 8) width: (self float: w at: 9) height: (self float: w at: 10).
	tex := i value: 15.
	tex = 0 ifFalse: [
		gpu bindTexture: pass slot: 0 texture: (handles at: tex)
			sampler: (self samplerLinear: (i value: 16) ~= 0 repeat: (i value: 17) ~= 0)].
	gpu draw: pass count: (i value: 21) first: (i value: 20).
	gpu endPass: pass
!
samplerLinear: linear repeat: repeat
	^samplers at: {linear. repeat} ifAbsentPut: [gpu createSampler: dev linear: linear repeat: repeat]
!
passEnd: h bytes: recorded
	"Compare a texture's pixels (not a swapchain's: its frame is compared when presented)."
	| t size format mine expected |
	t := handles at: h.
	(swapchains includes: t) ifTrue: [^self].
	size := gpu textureSize: t.
	format := size last.
	mine := gpu download: t x: 0 y: 0 width: size first height: (size at: 2) into: (ByteArray new: recorded size).
	expected := format = 3 ifTrue: [self swapRedAndBlue: recorded] ifFalse: [recorded].
	passes := passes + 1.
	mine = expected ifTrue: [^self].
	mismatches add: 'pass end ', passes printString, ' (texture ', h printString, ', ', size printString, '): ',
		(self differences: mine with: expected bytesPerPixel: (format = 1 ifTrue: [1] ifFalse: [4])) printString, ' pixels differ'.
	gpu uploadTexture: t bytes: recorded x: 0 y: 0 width: size first height: (size at: 2) bytesPerRow: recorded size // (size at: 2)
!
present: recorded
	frames := frames + 1.
	frame = recorded ifTrue: [^self].
	mismatches add: 'frame ', frames printString, ': ',
		(frame isNil
			ifTrue: ['not presented']
			ifFalse: [(self differences: frame with: recorded bytesPerPixel: 4) printString, ' pixels differ'])
!
swapRedAndBlue: bytes
	| b |
	b := bytes copy.
	1 to: b size by: 4 do: [:k | b at: k put: (bytes at: k + 2); at: k + 2 put: (bytes at: k)].
	^b
!
differences: a with: b bytesPerPixel: bpp
	a size = b size ifFalse: [^a size max: b size].
	^(1 to: a size by: bpp) count: [:k | (a copyFrom: k to: k + bpp - 1) ~= (b copyFrom: k to: k + bpp - 1)]
! !

!SoftwareGPUReplay class methodsFor: 'replaying'!
replay: aPath on: aDeviceClass
	"Replay the record at aPath on a new aDeviceClass (SoftwareGPU or a subclass) with me as its display; answer me, done."
	| r |
	r := self new setDeviceClass: aDeviceClass.
	[r replay: aPath] ensure: [r release].
	^r
! !
