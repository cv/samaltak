Widget subclass: #ShaderView
	instanceVariableNames: 'shader'
	classVariableNames: ''
	package: 'UI-Widgets'!

ShaderView comment: 'I show a picture computed on the GPU by a fragment shader (FragmentShader: the source after its prelude, a function fmain), at device resolution, in my bounds. Subclasses answer shaderSource (MSL) and glslShaderSource (GLSL, for Vulkan; see FragmentShader) and uniforms, an Array of rows, each one float4 of the shader''s uniform struct: up to four Numbers, Points (two) and Colors (r g b a, premultiplied by the shader if it wants). Each drawing renders a new frame from them (at renderScale); invalidate when they change (every frame, for an animation). A changed shaderSource takes effect at the next drawing. An NvComputeGPU runs the GLSL as a CUDA kernel (precompiled for the shipped views, else compiled by NVRTC where the CUDA toolkit is). Where the device runs no fragment shaders (GPUDevice>>runsFragmentShader: false: a SoftwareGPU, on UEFI and the appliance without an NVIDIA GPU, or an NvComputeGPU without NVRTC for a shader not precompiled) I draw drawWithoutShaderOn: instead, which subclasses override with a plain picture.'!

!ShaderView methodsFor: 'shader'!
shaderSource
	"MSL."
	^self subclassResponsibility
!
glslShaderSource
	"GLSL: shaderSource for Vulkan."
	^self subclassResponsibility
!
shaderSourceFor: aLanguage
	^aLanguage == #glsl ifTrue: [self glslShaderSource] ifFalse: [self shaderSource]
!
uniforms
	^#()
!
renderScale
	"The fraction of device pixels I render: less is cheaper, scaled up when drawn."
	^1
! !

!ShaderView methodsFor: 'drawing'!
shader: aFragmentShader
	"Draw with aFragmentShader (tests: one on another device) instead of my own."
	(shader notNil and: [shader ~~ aFragmentShader]) ifTrue: [shader release].
	shader := aFragmentShader.
	self invalidate
!
drawSelfOn: aCanvas
	| s src |
	s := aCanvas scale * self renderScale.
	(self width * s) rounded < 1 | ((self height * s) rounded < 1) ifTrue: [^self].
	shader isNil ifTrue: [shader := FragmentShader new].
	src := self shaderSourceFor: shader device fragmentShaderLanguage.
	(shader runs: src) ifFalse: [^self drawWithoutShaderOn: aCanvas].
	aCanvas
		image: (shader
			imageExtent: (self width * s) rounded @ (self height * s) rounded
			source: src
			uniforms: self packedUniforms)
		in: self localBounds
!
packedUniforms
	| rows bytes |
	rows := self uniforms.
	bytes := ByteArray new: (rows size max: 1) * 16.
	rows doWithIndex: [:row :i |
		| at |
		at := i * 16 - 15.
		(row isArray ifTrue: [row] ifFalse: [Array with: row]) do: [:each |
			(each isNumber ifTrue: [Array with: each] ifFalse: [
				each isPoint ifTrue: [Array with: each x with: each y] ifFalse: [each asArray]]) do: [:f |
					bytes float32At: at put: f asFloat.
					at := at + 4]]].
	^bytes
!
drawWithoutShaderOn: aCanvas
	"Where no fragment shader runs (a SoftwareGPU; an NvComputeGPU for a shader it cannot compile); subclasses draw a plain picture instead."
	aCanvas fillRect: self localBounds color: (Color gray: 0.2).
	aCanvas drawString: 'This view needs a GPU' in: self localBounds font: Font ui color: Color white align: #center
! !
