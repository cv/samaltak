Object subclass: #GPUPlatform
	instanceVariableNames: ''
	classVariableNames: 'Device Display'
	package: 'Graphics-GPU'!

GPUPlatform comment: 'I am the private gateway of Graphics-GPU to the platform''s GPU and windows (docs/platform.md): every method forwards to a backend, the VM''s primitives (GPUPrimitives: SDL3, SDL_GPU) where it has them, else, where the image drives the machine itself (UEFI), the firmware''s display (FirmwareDisplay: windows and events) and a SoftwareGPU on it; so too on Linux without a window system where SAMALTAK_SCREEN=kms asks for it (KmsDisplay, FirmwareDisplay current there: KMS and evdev). They are chosen on first use after the image starts (reset). Failures signal a GPUError carrying the platform''s explanation. Only the classes of Graphics-GPU use me.

Another GPU is opt-in: --gpu NAME on the command line, else the environment''s SAMALTAK_GPU. nv is an NvComputeGPU (Graphics-NV: the raster kernels on an NVIDIA GPU, docs/nv-gpu.md), software a SoftwareGPU; hosted they present through a HostFramePresenter in the VM''s windows, on UEFI on the firmware''s display. Where it cannot be made (no Graphics-NV, no CUDA userspace, it does not open) the default is used, with a line on stderr saying why: hosted the default GPU, on the firmware''s or the KMS screen software rendering.'!

!GPUPlatform class methodsFor: 'backends'!
display
	"The windows and events."
	Display isNil ifTrue: [self chooseBackends].
	^Display
!
device
	"The GPU."
	Device isNil ifTrue: [self chooseBackends].
	^Device
!
chooseBackends
	| firmware |
	firmware := FirmwareDisplay current.
	Display := firmware ifNil: [GPUPrimitives].
	Device := self device: self requestedGPU on: (firmware ifNil: [HostFramePresenter new]) nv: (Smalltalk at: #NvComputeGPU ifAbsent: [nil]).
	Device isNil ifTrue: [Device := firmware isNil ifTrue: [GPUPrimitives] ifFalse: [SoftwareGPU on: firmware]]
!
requestedGPU
	"What --gpu NAME, else the environment's SAMALTAK_GPU, asks for ('nv', 'software'), or nil: the default."
	^(Smalltalk argumentAfter: '--gpu') ifNil: [Smalltalk vm getenv: 'SAMALTAK_GPU']
!
device: aName on: aDisplay nv: nvClass
	"The device aName asks for, presenting on aDisplay; nil for the default (no name, an unknown one, or one that cannot be made here). nvClass: NvComputeGPU, or nil without Graphics-NV."
	(aName isNil or: [aName isEmpty]) ifTrue: [^nil].
	aName = 'software' ifTrue: [^SoftwareGPU on: aDisplay].
	aName = 'nv' ifFalse: [^self note: 'unknown GPU ', aName printString on: aDisplay].
	nvClass isNil ifTrue: [^self note: 'nv: no Graphics-NV in this image' on: aDisplay].
	nvClass isAvailable ifFalse: [
		^self note: 'nv: ', ((nvClass respondsTo: #unavailableReason) ifTrue: [nvClass unavailableReason] ifFalse: ['no NVIDIA GPU here']) on: aDisplay].
	^[nvClass on: aDisplay] on: Error do: [:e | e return: (self note: 'nv: the NVIDIA GPU did not open (', e messageText asString, ')' on: aDisplay)]
!
note: aString on: aDisplay
	"Say on stderr why the default is used, and what it is: hosted (aDisplay a HostFramePresenter) the default GPU, else software rendering (a SoftwareGPU on the firmware's or the KMS screen); answer nil."
	Smalltalk vm stderrWrite: 'Samaltak: --gpu: ', aString, ': ', ((aDisplay isKindOf: HostFramePresenter) ifTrue: ['the default GPU'] ifFalse: ['software rendering']), ' instead', (String with: Character lf).
	^nil
!
display: aDisplay device: aDevice
	"Use other backends (tests); answer the ones in use, {display. device}."
	| old |
	old := {Display. Device}.
	Display := aDisplay.
	Device := aDevice.
	^old
!
reset
	"Choose again on next use (a new VM process)."
	Display := Device := nil
! !

!GPUPlatform class methodsFor: 'device'!
createDevice: debug
	^self device createDevice: debug
!
shaderLanguage: dev
	"'msl' or 'glsl': the source gpuCreateShader takes on device."
	^self device shaderLanguage: dev
!
runsFragmentShaders: dev
	"Whether a device that builds no shaders runs FragmentShaders still (an NvComputeGPU's kernels)."
	^(self device respondsTo: #runsFragmentShaders:) and: [self device runsFragmentShaders: dev]
!
canBuildFragmentShader: dev source: aString
	^(self device respondsTo: #canBuildFragmentShader:source:) and: [self device canBuildFragmentShader: dev source: aString]
!
fragmentShaderReady: dev source: aString
	"Whether a pipeline of the fragment shader aString would be built at once (an NvComputeGPU may compile it in the background first)."
	^(self device respondsTo: #fragmentShaderReady:source:) not or: [self device fragmentShaderReady: dev source: aString]
!
claim: dev window: window
	^self device claim: dev window: window
!
swapchainFormat: dev window: window
	^self device swapchainFormat: dev window: window
!
swapchainKeepsContents: dev window: window
	"Whether the window's swapchain texture keeps the last frame (GPUSwapchain>>keepsContents)."
	(self device respondsTo: #swapchainKeepsContents:window:) ifFalse: [^false].
	^self device swapchainKeepsContents: dev window: window
!
waitIdle: dev
	^self device waitIdle: dev
!
release: aHandle
	^self device release: aHandle
! !

!GPUPlatform class methodsFor: 'resources'!
createShader: dev source: msl entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	^self device createShader: dev source: msl entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
!
compileShader: glsl stage: stage
	^self device compileShader: glsl stage: stage
!
createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
	^self device createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
!
createTexture: dev width: w height: h format: format usage: usage
	^self device createTexture: dev width: w height: h format: format usage: usage
!
createSampler: dev linear: linear repeat: repeat
	^self device createSampler: dev linear: linear repeat: repeat
!
createBuffer: dev usage: usage size: size
	^self device createBuffer: dev usage: usage size: size
!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	^self device uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	^self device uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
!
download: texture x: x y: y width: w height: h into: bytes
	^self device download: texture x: x y: y width: w height: h into: bytes
!
textureSize: texture
	^self device textureSize: texture
! !

!GPUPlatform class methodsFor: 'commands'!
acquireCommandBuffer: dev
	^self device acquireCommandBuffer: dev
!
acquireSwapchain: commandBuffer window: window
	"Answer {texture. width. height}, or nil when the window cannot be drawn now."
	^self device acquireSwapchain: commandBuffer window: window
!
beginPass: commandBuffer target: texture clear: rgbaOrNil
	^self device beginPass: commandBuffer target: texture clear: rgbaOrNil
!
setViewport: pass x: x y: y width: w height: h
	^self device setViewport: pass x: x y: y width: w height: h
!
setScissor: pass x: x y: y width: w height: h
	^self device setScissor: pass x: x y: y width: w height: h
!
bindPipeline: pass pipeline: pipeline
	^self device bindPipeline: pass pipeline: pipeline
!
bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
	^self device bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
!
bindTexture: pass slot: slot texture: texture sampler: sampler
	^self device bindTexture: pass slot: slot texture: texture sampler: sampler
!
pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
	^self device pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
!
draw: pass count: vertexCount first: firstVertex
	^self device draw: pass count: vertexCount first: firstVertex
!
endPass: pass
	^self device endPass: pass
!
blit: commandBuffer source: src rect: srcRect destination: dst rect: dstRect linear: linear
	^self device blit: commandBuffer source: src rect: srcRect destination: dst rect: dstRect linear: linear
!
submit: commandBuffer fence: wantFence
	^self device submit: commandBuffer fence: wantFence
!
presentDamage: commandBuffer rects: anArray
	"Only these rectangles of the swapchain texture commandBuffer acquired changed (GPUCommandBuffer>>presentDamage:); a device that cannot use that presents all of it."
	(self device respondsTo: #presentDamage:rects:) ifFalse: [^nil].
	^self device presentDamage: commandBuffer rects: anArray
!
waitFence: fence
	^self device waitFence: fence
!
fenceDone: fence
	^self device fenceDone: fence
!
fenceElapsed: fence
	^self device fenceElapsed: fence
! !

!GPUPlatform class methodsFor: 'windows'!
openWindow: w height: h title: title flags: flags
	^self display openWindow: w height: h title: title flags: flags
!
closeWindow: window
	"The device lets go of the window, unless the display keeps it open: the firmware's screen is every window (a UI test's in a live World), and the World still draws on it."
	self display closeWindow: window.
	(self display keepsWindowOpen: window) ifFalse: [self device windowClosed: window]
!
windowSize: window
	^self display windowSize: window
!
windowPixelSize: window
	^self display windowPixelSize: window
!
windowDisplayScale: window
	^self display windowDisplayScale: window
!
windowRefreshRate: window
	^self display windowRefreshRate: window
!
window: window title: aString
	^self display window: window title: aString
!
window: window width: w height: h
	^self display window: window width: w height: h
!
window: window x: x y: y
	^self display window: window x: x y: y
!
window: window opacity: permille
	^self display window: window opacity: permille
!
window: window fillRects: anArray
	^self display window: window fillRects: anArray
!
window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
	^self display window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
!
showWindow: window
	^self display showWindow: window
!
hideWindow: window
	^self display hideWindow: window
!
nextEvent: anArray
	"Fill anArray (8 slots) with the next platform event and answer it, or answer nil."
	^self display nextEvent: anArray
!
injectEvent: anArray
	^self display injectEvent: anArray
!
inputSemaphore: externalIndex
	^self display inputSemaphore: externalIndex
!
vsyncSemaphore: externalIndex
	^self display vsyncSemaphore: externalIndex
!
setCursor: kind
	^self display setCursor: kind
!
clipboardGet
	^self display clipboardGet
!
clipboardSet: aString
	^self display clipboardSet: aString
! !

!GPUPlatform class methodsFor: 'clipboard'!
clipboardData: mime
	^self display clipboardData: mime
! !
