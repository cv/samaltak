Object subclass: #SoftwareGPURecorderDisplay
	instanceVariableNames: 'width height recorder'
	classVariableNames: ''
	package: 'Tests-Graphics'!

SoftwareGPURecorderDisplay comment: 'The display of a SoftwareGPURecorder: one window, handle 1, of width x height pixels at one pixel a point (every open answers it), no input, the World''s refresh on the Compositor''s own timeout; each frame presented goes to the recorder.'!

!SoftwareGPURecorderDisplay methodsFor: 'initialization'!
setWidth: w height: h recorder: aRecorder
	width := w.
	height := h.
	recorder := aRecorder
! !

!SoftwareGPURecorderDisplay methodsFor: 'windows'!
openWindow: w height: h title: aString flags: flags
	^1
!
closeWindow: window
!
keepsWindowOpen: window
	^true
!
windowSize: window
	^{width. height}
!
windowPixelSize: window
	^{width. height}
!
windowDisplayScale: window
	^1.0
!
windowRefreshRate: window
	^60.0
!
window: window title: aString
!
window: window icon: aByteArray width: w
	^false
!
window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
!
showWindow: window
!
hideWindow: window
!
windowClosed: window
!
presentWindow: window pixels: address width: w height: h
	recorder present: window pixels: address width: w height: h
!
setCursor: kind
!
clipboardGet
	^''
!
clipboardSet: aString
!
clipboardData: mime
	^nil
! !

!SoftwareGPURecorderDisplay methodsFor: 'events'!
nextEvent: anArray
	^nil
!
injectEvent: anArray
	^nil
!
inputSemaphore: anInteger
!
vsyncSemaphore: anInteger
!
droppedEvents
	^0
! !

SoftwareGPU subclass: #SoftwareGPURecorder
	instanceVariableNames: 'stream frames maxFrames snapshots'
	classVariableNames: ''
	package: 'Tests-Graphics'!

SoftwareGPURecorder comment: 'I am a SoftwareGPU that records what I am given and the pixels I produced, so that they can be replayed elsewhere: tests/nv replays a record on the CUDA raster kernels (gpu/nv, docs/nv-kernels.md) and compares.

	(SoftwareGPURecorder width: 1920 height: 1080 path: ''build/nv/world.nvrec'') maxFrames: 4; install.
	World openExtent: 1920 @ 1080 hidden: false.

install makes me and my display (SoftwareGPURecorderDisplay) GPUPlatform''s backends, before anything made a GPU object. I record from my creation (textures and buffers, their uploads and releases, the swapchain, clears, draws, blits, submits), with each pass''s target pixels when it ends (snapshots: true, the default) and each frame presented; after maxFrames presented frames, or at stop, the file is closed and I go on unrecorded.

The record (all little-endian): the 8 bytes SAMNVRC1, then records: uint32 op, uint32 n, uint32 byte count b, uint32 0, n 64-bit words (integers, two''s complement; floats as IEEE doubles; booleans 0 or 1), b bytes, zeros to a multiple of 8. Handles are mine (reused after a release). The ops and their words:
	1 texture: handle width height format (its pixels zero)
	2 buffer: handle size
	3 release: handle (a texture, buffer or swapchain texture)
	4 upload texture: handle x y width height; bytes: the rows, tightly packed
	5 upload buffer: handle offset count; bytes
	6 swapchain: handle window width height (the window''s back buffer, BGRA8, kept between frames)
	7 clear: handle value (the pixel value every pixel got: a byte for R8)
	8 draw: target blend scissorX scissorY scissorW scissorH viewportX viewportY viewportW viewportH viewSizeX viewSizeY translateX translateY texture (0: none) linear repeat buffer offset first count
	9 blit: source sx sy sw sh destination dx dy dw dh linear
	10 pass end: target width height format; bytes: its pixels
	11 present: window width height; bytes: the BGRA8 frame
	12 submit: command buffer'!

!SoftwareGPURecorder methodsFor: 'recording'!
setPath: aPath
	stream := FileStream forceNewFileNamed: aPath.
	stream binary.
	stream nextPutAll: 'SAMNVRC1' asByteArray.
	frames := 0.
	maxFrames := SmallInteger maxVal.
	snapshots := true
!
maxFrames: anInteger
	maxFrames := anInteger
!
snapshots: aBoolean
	"Whether a pass's target pixels are recorded when it ends."
	snapshots := aBoolean
!
frames
	"Frames presented while recording."
	^frames
!
isRecording
	^stream notNil
!
install
	"Make my display and me GPUPlatform's backends; answer the previous ones, {display. device}."
	^GPUPlatform display: display device: self
!
stop
	stream isNil ifTrue: [^self].
	stream close.
	stream := nil
!
record: op words: anArray bytes: aByteArrayOrNil
	| n header pad |
	stream isNil ifTrue: [^self].
	n := aByteArrayOrNil isNil ifTrue: [0] ifFalse: [aByteArrayOrNil size].
	header := ByteArray new: 16 + (anArray size * 8).
	header uint32At: 1 put: op; uint32At: 5 put: anArray size; uint32At: 9 put: n; uint32At: 13 put: 0.
	anArray doWithIndex: [:x :i |
		| o v |
		o := 9 + (i * 8).
		x isFloat
			ifTrue: [header float64At: o put: x]
			ifFalse: [
				v := x == true ifTrue: [1] ifFalse: [x == false ifTrue: [0] ifFalse: [x ifNil: [0]]].
				header uint32At: o put: (v bitAnd: 16rFFFFFFFF); uint32At: o + 4 put: ((v bitShift: -32) bitAnd: 16rFFFFFFFF)]].
	stream nextPutAll: header.
	n > 0 ifTrue: [stream nextPutAll: aByteArrayOrNil].
	pad := 8 - (n \\ 8) \\ 8.
	pad > 0 ifTrue: [stream nextPutAll: (ByteArray new: pad)]
!
present: window pixels: address width: w height: h
	"A frame my display presents."
	stream isNil ifTrue: [^self].
	self record: 11 words: {window. w. h} bytes: (Machine bytesAt: address count: w * h * 4).
	frames := frames + 1.
	frames >= maxFrames ifTrue: [self stop]
! !

!SoftwareGPURecorder methodsFor: 'private'!
drop: h
	| o |
	o := objects at: h.
	(o kind == #texture or: [o kind == #buffer or: [o kind == #swapchain]]) ifTrue: [self record: 3 words: {h} bytes: nil].
	super drop: h
! !

!SoftwareGPURecorder methodsFor: 'resources'!
createTexture: dev width: w height: h format: format usage: usage
	| t |
	t := super createTexture: dev width: w height: h format: format usage: usage.
	self record: 1 words: {t. w. h. format} bytes: nil.
	^t
!
createBuffer: dev usage: usage size: size
	| b |
	b := super createBuffer: dev usage: usage size: size.
	self record: 2 words: {b. size} bytes: nil.
	^b
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	| t bpp rows |
	super uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow.
	stream isNil ifTrue: [^self].
	t := self at: texture.
	bpp := self bytesPerPixel: t format.
	rows := ByteArray new: w * h * bpp.
	0 to: h - 1 do: [:j |
		rows replaceFrom: j * w * bpp + 1 to: j + 1 * w * bpp
			with: (Machine bytesAt: t address + ((y + j * t width + x) * bpp) count: w * bpp) startingAt: 1].
	self record: 4 words: {texture. x. y. w. h} bytes: rows
!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	super uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset.
	(stream isNil or: [byteCount = 0]) ifTrue: [^self].
	self record: 5 words: {buffer. dstOffset. byteCount} bytes: (Machine bytesAt: (self at: buffer) address + dstOffset count: byteCount)
! !

!SoftwareGPURecorder methodsFor: 'commands'!
acquireSwapchain: cmd window: window
	| r |
	r := super acquireSwapchain: cmd window: window.
	r isNil ifFalse: [self record: 6 words: {r first. window. r at: 2. r at: 3} bytes: nil].
	^r
!
beginPass: cmd target: texture clear: rgbaOrNil
	| pass t |
	pass := super beginPass: cmd target: texture clear: rgbaOrNil.
	rgbaOrNil isNil ifFalse: [
		t := self at: texture.
		self record: 7 words: {texture. t format = 1 ifTrue: [Machine uint8At: t address] ifFalse: [Machine uint32At: t address]} bytes: nil].
	^pass
!
draw: pass count: vertexCount first: firstVertex
	| p st tex |
	super draw: pass count: vertexCount first: firstVertex.
	p := self at: pass.
	(stream notNil and: [vertexCount >= 3 and: [(self at: p targetHandle) == p target]]) ifFalse: [^self].
	tex := p texture notNil and: [(self at: p textureHandle) == p texture].
	st := p stateWith: (self at: p command) extra texture: tex.
	self record: 8 words: {p targetHandle. st at: 5. st at: 6. st at: 7. st at: 8. st at: 9.
		st at: 10. st at: 11. st at: 12. st at: 13. st at: 14. st at: 15. st at: 16. st at: 17.
		tex ifTrue: [p textureHandle] ifFalse: [0]. st at: 22. st at: 23.
		p bufferHandle. p offset. firstVertex. vertexCount} bytes: nil
!
endPass: pass
	| p t |
	p := self at: pass kind: #pass for: 'gpuEndPass'.
	(stream notNil and: [snapshots and: [(self at: p targetHandle) == p target]]) ifTrue: [
		t := p target.
		self record: 10 words: {p targetHandle. t width. t height. t format}
			bytes: (Machine bytesAt: t address count: t width * t height * (self bytesPerPixel: t format))].
	super endPass: pass
!
blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: aBoolean
	| s d |
	super blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: aBoolean.
	s := srcRect asArray.
	d := dstRect asArray.
	self record: 9 words: {src. s at: 1. s at: 2. s at: 3. s at: 4. dst. d at: 1. d at: 2. d at: 3. d at: 4. aBoolean} bytes: nil
!
submit: cmd fence: wantFence
	self record: 12 words: {cmd} bytes: nil.
	^super submit: cmd fence: wantFence
! !

!SoftwareGPURecorder class methodsFor: 'instance creation'!
width: w height: h path: aPath
	"A recorder writing to aPath, its display one window of w x h pixels."
	| display gpu |
	display := SoftwareGPURecorderDisplay new.
	gpu := (self on: display) setPath: aPath; yourself.
	display setWidth: w height: h recorder: gpu.
	^gpu
! !

!SoftwareGPURecorder class methodsFor: 'reading'!
recordsIn: bytes
	"The records of a record's bytes: {op. words (integers). bytes}."
	| records i op n b words |
	(bytes copyFrom: 1 to: 8) asString = 'SAMNVRC1' ifFalse: [^self error: 'not a SoftwareGPURecorder record'].
	records := OrderedCollection new.
	i := 9.
	[i <= bytes size] whileTrue: [
		op := bytes uint32At: i.
		n := bytes uint32At: i + 4.
		b := bytes uint32At: i + 8.
		words := (1 to: n) collect: [:k | | o lo hi |
			o := i + 8 + (k * 8).
			lo := bytes uint32At: o.
			hi := bytes uint32At: o + 4.
			hi >= 16r80000000 ifTrue: [hi := hi - 16r100000000].
			(hi bitShift: 32) + lo].
		i := i + 16 + (n * 8).
		records add: {op. words. bytes copyFrom: i to: i + b - 1}.
		i := i + b + (8 - (b \\ 8) \\ 8)].
	^records asArray
! !
