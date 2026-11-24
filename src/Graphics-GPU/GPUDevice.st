Object subclass: #GPUDevice
	instanceVariableNames: 'handle session debug language'
	classVariableNames: 'Default Session'
	package: 'Graphics-GPU'!

GPUDevice comment: 'I am a GPU device (SDL_GPU on Metal or Vulkan, or a SoftwareGPU on UEFI) and the factory for every other GPU object. "GPUDevice default" is created lazily. Platform handles die with the VM process: on image startup a new session begins, and I and every object I created re-create our handles from the parameters we keep, on first use. Textures lose their contents then; their owners notice through GPUTexture>>generation.'!

!GPUDevice methodsFor: 'initialization'!
setDebug: aBoolean
	debug := aBoolean
! !

!GPUDevice methodsFor: 'accessing'!
handle
	"Answer my platform handle, creating the device in this session if needed."
	(handle notNil and: [session == Session]) ifTrue: [^handle].
	Session isNil ifTrue: [Session := Object new].
	handle := GPUPlatform createDevice: debug == true.
	session := Session.
	language := nil.
	^handle
!
isSoftware
	"Whether the CPU renders (SoftwareGPU, on UEFI): every frame costs the CPU the VM runs on."
	^self shaderLanguage == #software
!
buildsShaders
	"Whether I build pipelines from shader source (SDL_GPU: #msl, #glsl). A SoftwareGPU or an NvComputeGPU runs the Renderer's shader natively and refuses every other pipeline: the Renderer does not rebuild on them, and FragmentShaders and ShaderViews draw without one."
	^#(#msl #glsl) includes: self shaderLanguage
!
runsFragmentShaders
	"Whether FragmentShaders run on me (their source in fragmentShaderLanguage): where I build shaders (SDL_GPU), and on an NvComputeGPU that has their compiler (NVRTC) or precompiled kernels; not on a SoftwareGPU."
	self buildsShaders ifTrue: [^true].
	^GPUPlatform runsFragmentShaders: self handle
!
runsFragmentShader: aString
	"Whether the fragment shader aString (in fragmentShaderLanguage, its prelude included) can run on me: on an NvComputeGPU without NVRTC only a precompiled one can."
	self buildsShaders ifTrue: [^true].
	^GPUPlatform canBuildFragmentShader: self handle source: aString
!
fragmentShaderReady: aString
	"Whether a pipeline of the fragment shader aString (its prelude included) is built at once; if not (an NvComputeGPU compiling it in the background), FragmentShader keeps drawing with its old one meanwhile."
	self buildsShaders ifTrue: [^true].
	^GPUPlatform fragmentShaderReady: self handle source: aString
!
fragmentShaderLanguage
	"The language of FragmentShaders' sources: my shaderLanguage, but GLSL on an NvComputeGPU (#raster), which compiles GLSL fragment shaders to kernels."
	^self shaderLanguage == #raster ifTrue: [#glsl] ifFalse: [self shaderLanguage]
!
shaderLanguage
	"#msl (Metal, macOS), #glsl (Vulkan, Linux: GLSL 450 compiled to SPIR-V with SAMALTAK_VERTEX or SAMALTAK_FRAGMENT defined, so that one source can hold both stages; the entry point is main), #software (SoftwareGPU: the CPU runs the Renderer's shader, and no other) or #raster (NvComputeGPU: the Renderer's shader on the GPU's raster kernels, and no other; buildsShaders). Shader sources are in this language."
	| h |
	h := self handle.
	language isNil ifTrue: [language := (GPUPlatform shaderLanguage: h) asSymbol].
	^language
!
session
	"Answer the token of the session my current handle belongs to; objects I made compare against it."
	self handle.
	^session
!
isDebug
	^debug == true
! !

!GPUDevice methodsFor: 'creating resources'!
shaderSource: mslString entry: entryName stage: aSymbol samplers: samplerCount uniformBuffers: uniformCount
	"aSymbol is #vertex or #fragment."
	^GPUShader new setDevice: self source: mslString entry: entryName stage: aSymbol samplers: samplerCount uniformBuffers: uniformCount
!
pipelineVertex: vertexShader fragment: fragmentShader stride: stride attributes: attributes primitive: primitiveSymbol blend: blendSymbol format: formatSymbol
	"attributes: Array of {formatSymbol. byteOffset} pairs (#float #float2 #float3 #float4 #ubyte4norm #ubyte4 #uint #int); primitiveSymbol: #triangles #triangleStrip #lines #lineStrip #points; blendSymbol: #none #alpha #premultiplied; formatSymbol: a texture format."
	^GPUPipeline new setDevice: self vertex: vertexShader fragment: fragmentShader stride: stride attributes: attributes primitive: primitiveSymbol blend: blendSymbol format: formatSymbol
!
textureWidth: w height: h format: formatSymbol usage: usageSymbols
	"formatSymbol: #r8 #rgba8 #bgra8; usageSymbols: a collection of #sampler and #colorTarget."
	^GPUTexture new setDevice: self width: w height: h format: formatSymbol usage: usageSymbols
!
samplerLinear: linearBoolean repeat: repeatBoolean
	^GPUSampler new setDevice: self linear: linearBoolean repeat: repeatBoolean
!
vertexBufferSize: byteSize
	^GPUBuffer new setDevice: self size: byteSize
!
swapchainFor: aHostWindow
	^GPUSwapchain new setDevice: self window: aHostWindow
! !

!GPUDevice methodsFor: 'commands'!
commandBuffer
	"Answer a fresh command buffer for this frame."
	^GPUCommandBuffer new setDevice: self handle: (GPUPlatform acquireCommandBuffer: self handle)
!
waitIdle
	GPUPlatform waitIdle: self handle
!
flushUploads
	"Submit the uploads the platform holds back for the next submit now, without waiting: an empty command buffer's submit does (Renderer>>render:on:clear:)."
	self commandBuffer submit
! !

!GPUDevice methodsFor: 'releasing'!
release
	(handle notNil and: [session == Session]) ifTrue: [GPUPlatform release: handle].
	handle := nil
! !

!GPUDevice class methodsFor: 'instance creation'!
new
	^super new setDebug: false
!
debug
	^super new setDebug: true
! !

!GPUDevice class methodsFor: 'accessing'!
default
	^Default ifNil: [Default := self new]
!
currentSession
	^Session ifNil: [Session := Object new]
! !

!GPUDevice class methodsFor: 'formats'!
textureFormatCode: aSymbol
	aSymbol == #r8 ifTrue: [^1].
	aSymbol == #rgba8 ifTrue: [^2].
	aSymbol == #bgra8 ifTrue: [^3].
	^self error: 'Unknown texture format ', aSymbol printString
!
textureFormatFromCode: anInteger
	^#(#r8 #rgba8 #bgra8) at: anInteger
!
bytesPerPixel: aSymbol
	^aSymbol == #r8 ifTrue: [1] ifFalse: [4]
! !

!GPUDevice class methodsFor: 'system startup'!
initialize
	Smalltalk addToStartUpList: self
!
startUp: resuming
	"Handles of the previous VM process are gone: begin a new session, on the backends of this machine."
	resuming ifTrue: [
		Session := Object new.
		GPUPlatform reset]
! !
