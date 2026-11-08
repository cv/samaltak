GraphicsTestCase subclass: #FragmentShaderTest
	instanceVariableNames: 'shader'
	classVariableNames: ''
	package: 'Tests-Graphics'!

FragmentShaderTest comment: 'I test FragmentShader and ShaderImage: a frame drawn with Canvas>>image:in: shows what the shader computed from its uniforms, uv runs from the top-left, a frame is rendered once and again after its texture lost its contents (as after an image restart), new source takes effect, and source that does not compile keeps the old pipeline and reports the error (once).'!

!FragmentShaderTest methodsFor: 'running'!
setUp
	shader := FragmentShader new
!
tearDown
	shader release
! !

!FragmentShaderTest methodsFor: 'support'!
msl: mslString glsl: glslString
	"The source in the device's shader language."
	^shader device shaderLanguage == #glsl ifTrue: [glslString] ifFalse: [mslString]
!
tint
	^self
		msl: 'fragment float4 fmain(ShaderIn in [[stage_in]], constant float4 &tint [[buffer(0)]]) { return tint; }'
		glsl: 'layout(set = 3, binding = 0) uniform U { vec4 tint; }; void main() { fragColor = tint; }'
!
uniforms: anArray
	| bytes |
	bytes := ByteArray new: 16.
	anArray doWithIndex: [:f :i | bytes float32At: i * 4 - 3 put: f asFloat].
	^bytes
!
draw: aShaderImage
	^self render: [:c | c image: aShaderImage in: (2 @ 2 extent: 4 @ 4)] extent: 10 @ 10
! !

!FragmentShaderTest methodsFor: 'tests'!
testUniformsShow
	| form |
	form := self draw: (shader imageExtent: 8 @ 8 source: self tint uniforms: (self uniforms: #(1 0 0 1))).
	self assertPixel: 8 @ 8 in: form is: #(255 0 0 255).
	self assertPixel: 2 @ 2 in: form is: #(255 255 255 255)
!
testUVFromTheTopLeft
	| form |
	form := self draw: (shader imageExtent: 8 @ 8
		source: (self
			msl: 'fragment float4 fmain(ShaderIn in [[stage_in]], constant float4 &u [[buffer(0)]]) { return float4(in.uv, in.size.x / 8.0, 1.0); }'
			glsl: 'layout(set = 3, binding = 0) uniform U { vec4 u; }; void main() { fragColor = vec4(uv, size.x / 8.0, 1.0); }')
		uniforms: (self uniforms: #(0))).
	self assertPixel: 4 @ 4 in: form is: #(16 16 255 255) tolerance: 1.
	self assertPixel: 11 @ 4 in: form is: #(239 16 255 255) tolerance: 1.
	self assertPixel: 4 @ 11 in: form is: #(16 239 255 255) tolerance: 1
!
testRenderedOnceAndAgainWhenTheTextureIsLost
	| image texture generation |
	image := shader imageExtent: 8 @ 8 source: self tint uniforms: (self uniforms: #(0 0 1 1)).
	texture := image textureOn: GPUDevice default.
	generation := texture generation.
	self assert: (image textureOn: GPUDevice default) == texture.
	self assert: texture generation equals: generation.
	texture release.
	self assertPixel: 8 @ 8 in: (self draw: image) is: #(0 0 255 255).
	self assert: texture generation > generation
!
testNewSourceAndCompileErrors
	| errors form handler |
	self assertPixel: 8 @ 8 in: (self draw: (shader imageExtent: 8 @ 8 source: self tint uniforms: (self uniforms: #(1 0 0 1)))) is: #(255 0 0 255).
	form := self draw: (shader imageExtent: 8 @ 8
		source: (self
			msl: 'fragment float4 fmain(ShaderIn in [[stage_in]], constant float4 &tint [[buffer(0)]]) { return tint.gbra; }'
			glsl: 'layout(set = 3, binding = 0) uniform U { vec4 tint; }; void main() { fragColor = tint.gbra; }')
		uniforms: (self uniforms: #(1 0 0 1))).
	self assertPixel: 8 @ 8 in: form is: #(0 0 255 255).
	errors := OrderedCollection new.
	handler := Renderer shaderErrorHandler.
	Renderer shaderErrorHandler: [:e | errors add: e].
	[2 timesRepeat: [form := self draw: (shader imageExtent: 8 @ 8 source: 'fragment float4 fmain(nonsense' uniforms: (self uniforms: #(0 1 0 1)))]]
		ensure: [Renderer shaderErrorHandler: handler].
	self assert: errors size equals: 1.
	self assertPixel: 8 @ 8 in: form is: #(255 0 0 255)
! !
