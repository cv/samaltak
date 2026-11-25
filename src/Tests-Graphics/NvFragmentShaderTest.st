TestCase subclass: #NvFragmentShaderTest
	instanceVariableNames: 'gpu old device errors handler'
	classVariableNames: ''
	package: 'Tests-Graphics'!

NvFragmentShaderTest comment: 'Tests FragmentShaders on an NvComputeGPU: GLSL made a CUDA kernel (NvShaderCompiler: precompiled, or by NVRTC) and run over the target on the GB10, its pixels, uniforms, derivatives and discards; a live edit compiling in the background while the old pipeline draws, and a broken one reported with the old kept; the shipped shaders precompiled and current; Claude''s Robot rendered. Needs the GPU (and NVRTC for the edits), so it does not run by default (runsByDefault): make test-nv runs it.'!

!NvFragmentShaderTest methodsFor: 'running'!
setUp
	NvComputeGPU isAvailable ifFalse: [^self error: 'no NVIDIA GPU with CUDA here (libcuda, the CUDA runtime, a device): NvFragmentShaderTest needs one'].
	gpu := NvComputeGPU on: SoftwareGPUTestDisplay new.
	old := GPUPlatform display: gpu display device: gpu.
	device := GPUDevice new.
	errors := OrderedCollection new.
	handler := Renderer shaderErrorHandler.
	Renderer shaderErrorHandler: [:e | errors add: e]
!
tearDown
	Renderer shaderErrorHandler: handler.
	old isNil ifFalse: [GPUPlatform display: old first device: old last].
	gpu isNil ifFalse: [gpu close]
!
timeLimitMilliseconds
	^120000
! !

!NvFragmentShaderTest methodsFor: 'support'!
pixelsOf: aSource extent: aPoint uniforms: aByteArray with: aShader
	^(aShader textureFor: (aShader imageExtent: aPoint source: aSource uniforms: aByteArray)) download asArray
!
pixelsOf: aSource extent: aPoint
	^self pixelsOf: aSource extent: aPoint uniforms: (ByteArray new: 16) with: (FragmentShader on: device)
!
unorm: x
	^(x * 255) rounded
!
fresh: aString
	"aString with a constant no other source has, so that NVRTC compiles it (its cache knows none like it)."
	^'const float fresh', Time utcMicroseconds printString, ' = 1.0;
', aString
! !

!NvFragmentShaderTest methodsFor: 'tests'!
testTheDeviceRunsFragmentShaders
	self deny: device buildsShaders.
	self assert: device runsFragmentShaders.
	self assert: device fragmentShaderLanguage equals: #glsl
!
testPixelCentresAndTheUvs
	| px expected |
	px := self pixelsOf: 'void main() { fragColor = vec4(uv, gl_FragCoord.x / 8.0, 1.0); }' extent: 4 @ 2.
	expected := OrderedCollection new.
	0 to: 1 do: [:y | 0 to: 3 do: [:x |
		expected add: (self unorm: x + 0.5 / 4); add: (self unorm: y + 0.5 / 2); add: (self unorm: x + 0.5 / 8); add: 255]].
	self assert: px equals: expected asArray.
	self assert: errors isEmpty
!
testUniforms
	| u px |
	u := ByteArray new: 48.
	#(0.25 0.5 0.75 1.0 0.125 0 0 0 0.375 0.625 0 0) doWithIndex: [:f :i | u float32At: i * 4 - 3 put: f asFloat].
	px := self pixelsOf: 'layout(set = 3, binding = 0) uniform U { vec4 tint; float k; vec2 p[1]; } u;
void main() { fragColor = vec4(u.tint.xyz * u.k * 8.0, u.p[0].y); }' extent: 2 @ 1 uniforms: u with: (FragmentShader on: device).
	self assert: (px first: 4) asArray equals: (Array with: (self unorm: 0.25) with: (self unorm: 0.5) with: (self unorm: 0.75) with: (self unorm: 0.625)).
	self assert: errors isEmpty
!
testDerivativesAndDiscards
	| px |
	px := self pixelsOf: 'void main() {
	if (gl_FragCoord.y > 4.0) discard;
	fragColor = vec4(dFdx(gl_FragCoord.x * 0.5), dFdy(gl_FragCoord.y * 0.25), fwidth(uv.x) * 8.0, 1.0);
}' extent: 8 @ 8.
	1 to: 4 * 8 * 4 by: 4 do: [:i | self assert: (px copyFrom: i to: i + 3) equals: #(128 64 255 255)].
	(4 * 8 * 4 + 1) to: px size do: [:i | self assert: (px at: i) equals: 0].
	self assert: errors isEmpty
!
testSinesOfLargeArguments
	"sinf's argument reduction for large arguments reads libdevice's table: global data the kernel finds through constant bank 4."
	| px |
	px := self pixelsOf: 'void main() { fragColor = vec4(fract(sin(gl_FragCoord.x * 100000.0)), 0.0, 0.0, 1.0); }' extent: 8 @ 1.
	1 to: 8 do: [:x | | v |
		v := ((x - 0.5) * 100000.0) sin.
		v := v - v floor.
		self assert: ((px at: x * 4 - 3) - (self unorm: v)) abs <= 1]
!
testALiveEditCompilesWhileTheOldShaderDraws
	"A FragmentShader given a new source keeps drawing with its old pipeline while NVRTC compiles the new one in the background, then draws the new; a source with an error is reported (at its line) and the old pipeline stays."
	| fs red green px frames t0 |
	NvRtc isAvailable ifFalse: [^self].
	fs := FragmentShader on: device.
	red := 'void main() { fragColor = vec4(1.0, 0.0, 0.0, 1.0); }'.
	green := self fresh: 'void main() { fragColor = vec4(0.0, 1.0, 0.0, 1.0); }'.
	self assert: ((self pixelsOf: red extent: 2 @ 2 uniforms: (ByteArray new: 16) with: fs) first: 4) equals: #(255 0 0 255).
	frames := 0.
	t0 := Time millisecondClockValue.
	[px := self pixelsOf: green extent: 2 @ 2 uniforms: (ByteArray new: 16) with: fs.
	(px first: 4) = #(0 255 0 255)] whileFalse: [
		self assert: (px first: 4) equals: #(255 0 0 255).
		frames := frames + 1.
		(Delay forMilliseconds: 10) wait.
		self assert: Time millisecondClockValue - t0 < 60000 description: 'the new shader did not come in a minute'].
	self assert: frames > 0 description: 'the edit did not compile in the background'.
	px := self pixelsOf: 'void main() {
	fragColor = vec4(0.0, 0.0, 1.0, 1.0)
}' extent: 2 @ 2 uniforms: (ByteArray new: 16) with: fs.
	self assert: (px first: 4) equals: #(0 255 0 255).
	self assert: errors size equals: 1.
	self assert: errors first line equals: 3
!
testReleasingThePipelineFreesTheKernel
	| fs shaders |
	fs := FragmentShader on: device.
	shaders := [(gpu compute programs keys select: [:k | k name = 'gl_fragment']) size].
	self pixelsOf: 'void main() { fragColor = vec4(0.5); }' extent: 2 @ 2 uniforms: (ByteArray new: 16) with: fs.
	self assert: shaders value equals: 1.
	fs release.
	self assert: shaders value equals: 0
!
testTheShippedShadersArePrecompiled
	"Every ShaderView's shader is in NvPrecompiledShaders under its current key; else make nv-shaders."
	NvShaderCompiler shippedSources do: [:each |
		self assert: (NvShaderCompiler precompiled includesKey: (NvShaderCompiler keyFor: each value))
			description: each key, '''s shader is not precompiled as it is now: make nv-shaders']
!
testTheRobotRenders
	"Claude's Robot's stage, raymarched: hundreds of colours, no error."
	| stage juggler px seen |
	juggler := (Smalltalk at: #ShannonJuggler) new.
	30 timesRepeat: [juggler step].
	stage := (Smalltalk at: #JugglerStage) new juggler: juggler; yourself.
	px := self pixelsOf: stage glslShaderSource extent: 160 @ 120 uniforms: stage packedUniforms with: (FragmentShader on: device).
	seen := Set new.
	1 to: px size by: 4 do: [:i | seen add: (px copyFrom: i to: i + 2)].
	self assert: seen size > 200.
	self assert: errors isEmpty
! !

!NvFragmentShaderTest class methodsFor: 'testing'!
runsByDefault
	^false
! !
