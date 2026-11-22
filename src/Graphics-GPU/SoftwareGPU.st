Object subclass: #SoftwareGPU
	instanceVariableNames: 'display objects free claims'
	classVariableNames: 'RendererAttributes'
	package: 'Graphics-GPU'!

SoftwareGPU comment: 'I am a GPU in software: GPUPlatform''s device where the VM has no GPU (UEFI), with the gpu primitives'' protocol, handles and errors (docs/platform.md). I keep the objects; the pixel work is SoftwareRaster''s (the raster primitives). I run the Renderer''s uber-shader and nothing else: a pipeline of another vertex layout fails (user FragmentShaders show their error); shaders are not compiled (shaderLanguage: ''software'').

Everything executes when it is called: uploads, clears, draws, blits and downloads; a command buffer only groups them (its vertex uniforms, the swapchain textures it acquired, the time its work took); fences are done when they are made (fenceElapsed: that time, µs). Textures and buffers are memory outside the heap (Machine allocate:), freed when released: R8, RGBA8 or BGRA8 rows, tightly packed. A claimed window has a back buffer (BGRA8, the window''s pixel size), the swapchain texture acquireSwapchain:window: answers; submitting the command buffer that acquired it presents it on my display (presentWindow:pixels:width:height:).'!

!SoftwareGPU methodsFor: 'initialization'!
setDisplay: aDisplay
	display := aDisplay.
	objects := OrderedCollection new.
	free := OrderedCollection new.
	claims := Dictionary new
! !

!SoftwareGPU methodsFor: 'private'!
fail: operation because: aString
	^GPUError new operation: operation; platformLastError: aString; signal
!
add: anObject
	"A handle for anObject."
	| h |
	free isEmpty
		ifTrue: [
			objects addLast: anObject.
			h := objects size]
		ifFalse: [
			h := free removeFirst.
			objects at: h put: anObject].
	^h
!
at: h
	"The object of handle h, nil if there is none."
	^(h isInteger and: [h between: 1 and: objects size]) ifTrue: [objects at: h] ifFalse: [nil]
!
at: h kind: aSymbol for: operation
	"The object of handle h, which must be of kind aSymbol."
	| o |
	o := self at: h.
	(o notNil and: [o kind == aSymbol]) ifFalse: [^self fail: operation because: 'bad ' , aSymbol , ' handle ' , h printString].
	^o
!
device: h for: operation
	^self at: h kind: #device for: operation
!
target: h for: operation
	"A texture or a swapchain texture."
	| o |
	o := self at: h.
	(o notNil and: [o kind == #texture or: [o kind == #swapchain]]) ifFalse: [^self fail: operation because: 'bad texture handle ' , h printString].
	^o
!
drop: h
	"Remove handle h, freeing the memory it owns."
	| o |
	o := objects at: h.
	((o kind == #texture or: [o kind == #buffer]) and: [o address notNil]) ifTrue: [Machine free: o address].
	objects at: h put: nil.
	free addLast: h
!
dropPassesOf: cmd
	"The passes and swapchain textures of command buffer cmd."
	(self at: cmd) owned do: [:each | (objects at: each key) == each value ifTrue: [self drop: each key]]
!
add: anObject ownedBy: cmd
	"A handle for anObject (a pass or a swapchain texture), which ends with command buffer cmd."
	| h |
	h := self add: anObject.
	(self at: cmd) owned add: h -> anObject.
	^h
!
charge: cmd since: t0
	"The time since t0 (µs) to the work of command buffer cmd."
	(self at: cmd) ifNotNil: [:c | c size: c size + (Time microsecondClockValue - t0)]
!
bytesPerPixel: format
	^format = 1 ifTrue: [1] ifFalse: [4]
!
byteSizeOf: bytes
	^(bytes isKindOf: Bitmap) ifTrue: [bytes size * 4] ifFalse: [bytes size]
!
unorm8: x
	"A float channel as unorm8: round(clamp(x, 0, 1) * 255)."
	x > 0 ifFalse: [^0].
	x >= 1 ifTrue: [^255].
	^(x asFloat * 255.0 + 0.5) floor
! !

!SoftwareGPU methodsFor: 'device'!
createDevice: debug
	^self add: (SoftwareGPUObject kind: #device)
!
shaderLanguage: dev
	"What createShader: takes: 'software' (the source is ignored)."
	self device: dev for: 'gpuShaderLanguage'.
	^'software'
!
claim: dev window: window
	| c |
	self device: dev for: 'gpuClaimWindow'.
	display windowPixelSize: window.
	c := claims at: window ifAbsent: [nil].
	c notNil ifTrue: [
		c device = dev ifTrue: [^self].
		^self fail: 'gpuClaimWindow' because: 'the window is claimed by another device'].
	claims at: window put: ((SoftwareGPUObject kind: #claim) device: dev; yourself)
!
swapchainFormat: dev window: window
	"BGRA8, the firmware's framebuffer order."
	self device: dev for: 'gpuSwapchainFormat'.
	display windowPixelSize: window.
	^3
!
waitIdle: dev
	self device: dev for: 'gpuWaitIdle'
!
windowClosed: window
	"Release window from the device that claimed it, and its back buffer."
	(claims removeKey: window ifAbsent: [nil]) ifNotNil: [:c | self unclaim: c]
!
unclaim: aClaim
	aClaim address isNil ifTrue: [^self].
	objects doWithIndex: [:o :h | (o notNil and: [o kind == #swapchain and: [o address = aClaim address]]) ifTrue: [self drop: h]].
	Machine free: aClaim address.
	aClaim address: nil
!
release: h
	"A device releases everything created on it; passes and swapchain textures end with their command buffer."
	| o |
	o := self at: h.
	o isNil ifTrue: [^self fail: 'gpuRelease' because: 'bad GPU handle ' , h printString].
	(o kind == #pass or: [o kind == #swapchain]) ifTrue: [^self fail: 'gpuRelease' because: 'pass/swapchain handles end with their command buffer'].
	o kind == #device ifTrue: [^self releaseDevice: h].
	o kind == #commandBuffer ifTrue: [self dropPassesOf: h].
	self drop: h
!
releaseDevice: dev
	objects doWithIndex: [:o :h | (o notNil and: [o kind == #commandBuffer and: [o device = dev]]) ifTrue: [self release: h]].
	objects doWithIndex: [:o :h | (o notNil and: [h ~= dev and: [o device = dev]]) ifTrue: [self drop: h]].
	(claims keys select: [:w | (claims at: w) device = dev]) do: [:w | self windowClosed: w].
	self drop: dev
! !

!SoftwareGPU methodsFor: 'resources'!
compileShader: glsl stage: stage
	"No shaders are compiled here (shaderLanguage: 'software')."
	^GPUError new operation: 'gpuCompileShader'; platformLastError: 'the software GPU compiles no shaders'; signal
!
createShader: dev source: source entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	"The source is not compiled: a shader is its stage."
	self device: dev for: 'gpuCreateShader'.
	^self add: ((SoftwareGPUObject kind: #shader) device: dev; format: stage; yourself)
!
createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
	"Only the Renderer's pipeline (any blend, an RGBA8 or BGRA8 target)."
	| v f |
	self device: dev for: 'gpuCreatePipeline'.
	v := self at: vs kind: #shader for: 'gpuCreatePipeline'.
	f := self at: fs kind: #shader for: 'gpuCreatePipeline'.
	(attributes size even and: [attributes size <= 32]) ifFalse: [^self fail: 'gpuCreatePipeline' because: 'bad attribute count'].
	(targetFormat between: 1 and: 3) ifFalse: [^self fail: 'gpuCreatePipeline' because: 'bad target format ' , targetFormat printString].
	(primitiveType between: 0 and: 4) ifFalse: [^self fail: 'gpuCreatePipeline' because: 'bad primitive type ' , primitiveType printString].
	(blend between: 0 and: 2) ifFalse: [^self fail: 'gpuCreatePipeline' because: 'bad blend mode ' , blend printString].
	(stride = 40 and: [attributes asArray = RendererAttributes and: [primitiveType = 0 and: [v format = 0 and: [f format = 1 and: [targetFormat ~= 1]]]]])
		ifFalse: [^self fail: 'gpuCreatePipeline' because: 'the software GPU runs the Renderer''s shader only'].
	^self add: ((SoftwareGPUObject kind: #pipeline) device: dev; format: targetFormat; extra: blend; yourself)
!
createTexture: dev width: w height: h format: format usage: usage
	"The pixels start out zero."
	self device: dev for: 'gpuCreateTexture'.
	((w between: 1 and: 16384) and: [(h between: 1 and: 16384) and: [(format between: 1 and: 3) and: [(usage bitAnd: 3) ~= 0]]])
		ifFalse: [^self fail: 'gpuCreateTexture' because: 'bad texture parameters'].
	^self add: ((SoftwareGPUObject kind: #texture) device: dev; width: w; height: h; format: format;
		address: (Machine allocate: w * h * (self bytesPerPixel: format)); yourself)
!
createSampler: dev linear: linear repeat: repeat
	self device: dev for: 'gpuCreateSampler'.
	^self add: ((SoftwareGPUObject kind: #sampler) device: dev; extra: {linear. repeat}; yourself)
!
createBuffer: dev usage: usage size: size
	self device: dev for: 'gpuCreateBuffer'.
	(usage = 1 and: [size > 0]) ifFalse: [^self fail: 'gpuCreateBuffer' because: 'bad buffer parameters'].
	^self add: ((SoftwareGPUObject kind: #buffer) device: dev; size: size; address: (Machine allocate: size); yourself)
!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	| b |
	b := self at: buffer kind: #buffer for: 'gpuUploadBuffer'.
	(byteCount between: 0 and: (self byteSizeOf: bytes)) ifFalse: [^self fail: 'gpuUploadBuffer' because: 'bad byte count'].
	byteCount = 0 ifTrue: [^self].
	(dstOffset >= 0 and: [dstOffset + byteCount <= b size]) ifFalse: [^self fail: 'gpuUploadBuffer' because: 'upload out of buffer bounds'].
	Machine copy: byteCount from: bytes at: 0 to: b address at: dstOffset
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	| t bpp |
	t := self at: texture kind: #texture for: 'gpuUploadTexture'.
	bpp := self bytesPerPixel: t format.
	(x >= 0 and: [y >= 0 and: [w > 0 and: [h > 0 and: [x + w <= t width and: [y + h <= t height
		and: [bytesPerRow >= (w * bpp) and: [(self byteSizeOf: bytes) >= ((h - 1) * bytesPerRow + (w * bpp))]]]]]]])
			ifFalse: [^self fail: 'gpuUploadTexture' because: 'bad texture upload region'].
	SoftwareRaster copy: t address + ((y * t width + x) * bpp) stride: t width * bpp from: bytes stride: bytesPerRow
		width: w height: h bytesPerPixel: bpp mode: 0
!
download: texture x: x y: y width: w height: h into: bytes
	"Synchronous; BGRA8 is converted to RGBA8."
	| t bpp |
	t := self at: texture kind: #texture for: 'gpuDownload'.
	bpp := self bytesPerPixel: t format.
	(x >= 0 and: [y >= 0 and: [w > 0 and: [h > 0 and: [x + w <= t width and: [y + h <= t height and: [(self byteSizeOf: bytes) >= (w * h * bpp)]]]]]])
		ifFalse: [^self fail: 'gpuDownload' because: 'bad download region'].
	SoftwareRaster copy: bytes stride: w * bpp from: t address + ((y * t width + x) * bpp) stride: t width * bpp
		width: w height: h bytesPerPixel: bpp mode: (t format = 3 ifTrue: [1] ifFalse: [0]).
	^bytes
!
textureSize: texture
	| t |
	t := self target: texture for: 'gpuTextureSize'.
	^{t width. t height. t format}
! !

!SoftwareGPU methodsFor: 'commands'!
acquireCommandBuffer: dev
	"Its vertex uniforms and the µs its work took (size)."
	self device: dev for: 'gpuAcquireCommandBuffer'.
	^self add: ((SoftwareGPUObject kind: #commandBuffer) device: dev; size: 0; extra: {0.0. 0.0. 0.0. 0.0}; owned: OrderedCollection new; yourself)
!
acquireSwapchain: cmd window: window
	"The back buffer of window (BGRA8, its pixel size), presented when cmd is submitted: {texture. width. height}, or nil if the window has no pixels."
	| c claim size w h |
	c := self at: cmd kind: #commandBuffer for: 'gpuAcquireSwapchain'.
	claim := claims at: window ifAbsent: [^self fail: 'gpuAcquireSwapchain' because: 'the window is not claimed'].
	size := display windowPixelSize: window.
	w := size first.
	h := size last.
	(w > 0 and: [h > 0]) ifFalse: [^nil].
	(claim address isNil or: [claim width ~= w or: [claim height ~= h]]) ifTrue: [
		self unclaim: claim.
		claim address: (Machine allocate: w * h * 4); width: w; height: h].
	^{self add: ((SoftwareGPUObject kind: #swapchain) device: c device; address: claim address; width: w; height: h; format: 3; command: cmd; extra: window; yourself) ownedBy: cmd.
		w. h}
!
beginPass: cmd target: texture clear: rgbaOrNil
	"rgbaOrNil: {r. g. b. a} floats, nil = load. Clears now."
	| c t pass bpp v t0 |
	c := self at: cmd kind: #commandBuffer for: 'gpuBeginPass'.
	t := self target: texture for: 'gpuBeginPass'.
	pass := SoftwarePass command: cmd target: t handle: texture.
	rgbaOrNil isNil ifFalse: [
		(rgbaOrNil isArray and: [rgbaOrNil size = 4 and: [rgbaOrNil allSatisfy: [:e | e isNumber]]]) ifFalse: [^self fail: 'gpuBeginPass' because: 'bad clear color'].
		bpp := self bytesPerPixel: t format.
		v := rgbaOrNil collect: [:e | self unorm8: e].
		v := t format = 1
			ifTrue: [v first]
			ifFalse: [
				t format = 3
					ifTrue: [(v at: 3) + ((v at: 2) << 8) + ((v at: 1) << 16) + ((v at: 4) << 24)]
					ifFalse: [(v at: 1) + ((v at: 2) << 8) + ((v at: 3) << 16) + ((v at: 4) << 24)]].
		t0 := Time microsecondClockValue.
		SoftwareRaster fill: t address count: t width * t height bytesPerPixel: bpp value: v.
		self charge: cmd since: t0].
	^self add: pass ownedBy: cmd
!
setViewport: pass x: x y: y width: w height: h
	(self at: pass kind: #pass for: 'gpuSetViewport') viewportX: x y: y width: w height: h
!
setScissor: pass x: x y: y width: w height: h
	(self at: pass kind: #pass for: 'gpuSetScissor') scissorX: x y: y width: w height: h
!
bindPipeline: pass pipeline: pipeline
	| p |
	p := self at: pass kind: #pass for: 'gpuBindPipeline'.
	p pipeline: (self at: pipeline kind: #pipeline for: 'gpuBindPipeline')
!
bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
	"The pipeline reads slot 0 only."
	| p b |
	p := self at: pass kind: #pass for: 'gpuBindVertexBuffer'.
	b := self at: buffer kind: #buffer for: 'gpuBindVertexBuffer'.
	slot = 0 ifTrue: [p buffer: b handle: buffer offset: offset]
!
bindTexture: pass slot: slot texture: texture sampler: sampler
	"The shader samples slot 0 only."
	| p t s |
	p := self at: pass kind: #pass for: 'gpuBindTexture'.
	t := self at: texture kind: #texture for: 'gpuBindTexture'.
	s := self at: sampler kind: #sampler for: 'gpuBindTexture'.
	slot = 0 ifTrue: [p texture: t handle: texture sampler: s extra]
!
pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
	"The shader reads vertex slot 0 only (viewport size, translation: four floats)."
	| o c |
	o := self at: commandBufferOrPass.
	c := (o notNil and: [o kind == #pass]) ifTrue: [self at: o command] ifFalse: [o].
	(c notNil and: [c kind == #commandBuffer]) ifFalse: [^self fail: 'gpuPushUniforms' because: 'bad command buffer handle ' , commandBufferOrPass printString].
	(stage = 0 and: [slot = 0]) ifTrue: [
		1 to: (bytes size // 4 min: 4) do: [:i | c extra at: i put: (bytes float32At: i * 4 - 3)]]
!
draw: pass count: vertexCount first: firstVertex
	"Run the pipeline on the vertices now: triangles, in order; six equal vertices from an index divisible by six (without bit 31 of mode) as one quad."
	| p b t0 |
	p := self at: pass kind: #pass for: 'gpuDraw'.
	p pipeline isNil ifTrue: [^self fail: 'gpuDraw' because: 'no pipeline bound'].
	(vertexCount < 0 or: [firstVertex < 0]) ifTrue: [^self fail: 'gpuDraw' because: 'bad vertex range'].
	vertexCount < 3 ifTrue: [^self].
	b := p buffer.
	(b isNil or: [(self at: p bufferHandle) ~~ b]) ifTrue: [^self fail: 'gpuDraw' because: 'bad vertex buffer handle'].
	p offset + (firstVertex + vertexCount * 40) > b size ifTrue: [^self fail: 'gpuDraw' because: 'the draw reads beyond the vertex buffer'].
	(self at: p targetHandle) == p target ifFalse: [^self].
	t0 := Time microsecondClockValue.
	SoftwareRaster
		draw: (p stateWith: (self at: p command) extra texture: (p texture notNil and: [(self at: p textureHandle) == p texture]))
		vertices: b address + p offset first: firstVertex count: vertexCount.
	self charge: p command since: t0
!
endPass: pass
	self at: pass kind: #pass for: 'gpuEndPass'.
	self drop: pass
!
blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: aBoolean
	"Now, like SDL_BlitGPUTexture: each destination pixel samples the source at its centre mapped into srcRect, converted to the destination's format."
	| s d t0 |
	self at: cmd kind: #commandBuffer for: 'gpuBlit'.
	s := self at: src kind: #texture for: 'gpuBlit'.
	d := self target: dst for: 'gpuBlit'.
	t0 := Time microsecondClockValue.
	SoftwareRaster blit: s surface rect: srcRect asArray to: d surface rect: dstRect asArray linear: aBoolean.
	self charge: cmd since: t0
!
submit: cmd fence: wantFence
	"Present the swapchain textures cmd acquired; a fence (done already: the µs cmd's work took), or nil."
	| c busy |
	c := self at: cmd kind: #commandBuffer for: 'gpuSubmit'.
	busy := c size.
	c owned do: [:each | | o |
		o := each value.
		((objects at: each key) == o and: [o kind == #swapchain]) ifTrue: [
			(claims at: o extra ifAbsent: [nil]) ifNotNil: [:claim |
				claim address = o address ifTrue: [display presentWindow: o extra pixels: o address width: o width height: o height]]]].
	self dropPassesOf: cmd.
	self drop: cmd.
	wantFence ifFalse: [^nil].
	^self add: ((SoftwareGPUObject kind: #fence) device: c device; size: busy; yourself)
!
waitFence: fence
	self at: fence kind: #fence for: 'gpuWaitFence'
!
fenceDone: fence
	self at: fence kind: #fence for: 'gpuFenceDone'.
	^true
!
fenceElapsed: fence
	"µs of work of the fence's command buffer."
	^(self at: fence kind: #fence for: 'gpuFenceElapsed') size
! !

!SoftwareGPU methodsFor: 'accessing'!
liveObjects
	"How many objects of each kind live (a Bag of kinds)."
	^(objects reject: [:o | o isNil]) asBag collect: [:o | o kind]
! !

!SoftwareGPU class methodsFor: 'class initialization'!
initialize
	"The Renderer's vertex layout: float4 at 0, uint at 16 and 20, ubyte4norm at 24, uint at 28, float2 at 32."
	RendererAttributes := #(4 0 7 16 7 20 5 24 7 28 2 32)
! !

!SoftwareGPU class methodsFor: 'instance creation'!
on: aDisplay
	"A GPU presenting on aDisplay (presentWindow:pixels:width:height:, windowPixelSize:)."
	^self new setDisplay: aDisplay
! !
