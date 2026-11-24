GraphicsTestCase subclass: #GPUFFIRegressionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GPUFFIRegressionTest comment: 'I exercise the public platform FFI on SDL GPU. Run only in display CI, never on the local headless host.'!

!GPUFFIRegressionTest methodsFor: 'tests'!
testScalarPassStateAndConsumption
	| gpu dev tex cmd pass bytes |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
	[
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu beginPass: cmd target: tex clear: #(1 0 0.5 1).
		self assert: (gpu setViewport: pass x: 0 y: 1.0e-300 width: 4 height: 4.0) identicalTo: gpu.
		self assert: (gpu setScissor: pass x: 0 y: 0 width: 4 height: 4) identicalTo: gpu.
		self assert: (gpu endPass: pass) identicalTo: gpu.
		self should: [gpu endPass: pass] raise: GPUError withExceptionDo: [:e |
			self assert: e operation equals: 'gpuEndPass'.
			self assert: (e platformLastError includesSubstring: 'bad render pass handle')].
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: tex x: 0 y: 0 width: 4 height: 4 into: (ByteArray new: 64).
		self assert: (bytes copyFrom: 1 to: 4) asArray equals: #(255 0 128 255)
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		gpu release: tex]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testSubmitAndFenceStatuses
	| gpu dev cmd fence done elapsed |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	[
		cmd := gpu acquireCommandBuffer: dev.
		self assert: (gpu submit: cmd fence: false) isNil.
		self should: [gpu submit: cmd fence: true] raise: GPUError withExceptionDo: [:e |
			self assert: (e platformLastError includesSubstring: 'bad command buffer handle')].
		cmd := nil.
		cmd := gpu acquireCommandBuffer: dev.
		fence := gpu submit: cmd fence: true.
		cmd := nil.
		done := gpu fenceDone: fence.
		self assert: (done == true or: [done == false]).
		self assert: (gpu waitFence: fence) identicalTo: gpu.
		self assert: (gpu fenceDone: fence).
		elapsed := gpu fenceElapsed: fence.
		self assert: (elapsed isNil or: [elapsed >= 0]).
		gpu release: fence.
		fence := nil.
		self should: [gpu fenceDone: -1] raise: GPUError.
		self should: [gpu fenceElapsed: -1] raise: GPUError
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		fence ifNotNil: [gpu release: fence]]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testBoundedTransfers
	| gpu dev tex buffer bytes bitmap |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	tex := gpu createTexture: dev width: 3 height: 2 format: 1 usage: 1.
	[
		buffer := gpu createBuffer: dev usage: 1 size: 16.
		self assert: (gpu uploadBuffer: buffer bytes: #[1 2 3 4 5 6] count: 4 offset: 12) identicalTo: gpu.
		self should: [gpu uploadBuffer: buffer bytes: #[1 2 3 4 5 6] count: 5 offset: 12]
			raise: GPUError withExceptionDo: [:e | self assert: (e platformLastError includesSubstring: 'out of buffer bounds')].
		self assert: (gpu uploadTexture: tex bytes: #[1 2 3 255 4 5 6] x: 0 y: 0 width: 3 height: 2 bytesPerRow: 4)
			identicalTo: gpu.
		self should: [gpu uploadTexture: tex bytes: #[1 2 3] x: 0 y: 0 width: 3 height: 2 bytesPerRow: 4]
			raise: GPUError.
		bytes := ByteArray new: 8.
		bytes at: 7 put: 42; at: 8 put: 43.
		self assert: (gpu download: tex x: 0 y: 0 width: 3 height: 2 into: bytes) identicalTo: bytes.
		self assert: bytes equals: #[1 2 3 4 5 6 42 43].
		bitmap := Bitmap new: 2.
		bitmap at: 2 put: 16r2B2A0000.
		self assert: (gpu download: tex x: 0 y: 0 width: 3 height: 2 into: bitmap) identicalTo: bitmap.
		self assert: (bitmap at: 1) equals: 16r04030201.
		self assert: (bitmap at: 2) equals: 16r2B2A0605.
		self should: [gpu download: tex x: 0 y: 0 width: 3 height: 2 into: (ByteArray new: 5)]
			raise: GPUError
	] ensure: [
		gpu waitIdle: dev.
		buffer ifNotNil: [gpu release: buffer].
		gpu release: tex]
!
testBeginClearAndLoad
	| gpu dev tex cmd pass bytes |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
	[
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu beginPass: cmd target: tex clear: #(0 1.0 1.0e-300 1).
		gpu endPass: pass.
		pass := gpu beginPass: cmd target: tex clear: nil.
		gpu endPass: pass.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: tex x: 0 y: 0 width: 4 height: 4 into: (ByteArray new: 64).
		self assert: (bytes copyFrom: 1 to: 4) equals: #[0 255 0 255]
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		gpu release: tex]
!
testSwapchainAbsentAndDrawable
	| gpu dev window cmd result pass deadline |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	window := gpu openWindow: 32 height: 32 title: 'hidden GPU fixture' flags: 1.
	[
		self assert: (gpu claim: dev window: window) identicalTo: gpu.
		self assert: (#(1 2 3) includes: (gpu swapchainFormat: dev window: window)).
		cmd := gpu acquireCommandBuffer: dev.
		self assert: (gpu acquireSwapchain: cmd window: window) isNil.
		gpu showWindow: window.
		deadline := Time millisecondClockValue + 3000.
		[result := gpu acquireSwapchain: cmd window: window.
		 result isNil and: [Time millisecondClockValue < deadline]] whileTrue: [
			(Delay forMilliseconds: 10) wait].
		self assert: result notNil.
		self assert: result size equals: 3.
		self assert: (result allSatisfy: [:n | n > 0]).
		pass := gpu beginPass: cmd target: result first clear: #(0 0 0 1).
		gpu endPass: pass.
		gpu submit: cmd fence: false.
		cmd := nil.
		gpu waitIdle: dev
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		gpu closeWindow: window]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testOwnedCompilerOutputAndDiagnostics
	| gpu language source result again |
	gpu := GPUPrimitives.
	language := gpu shaderLanguage: GPUDevice default handle.
	source := Renderer glslShaderSource.
	language = 'glsl'
		ifTrue: [
			result := gpu compileShader: source stage: 0.
			"SPIR-V magic and header, plus a fresh byte object on the next call."
			self assert: result size > 20.
			self assert: (result copyFrom: 1 to: 4) equals: #[3 2 35 7].
			again := gpu compileShader: source stage: 0.
			self assert: result equals: again.
			self deny: result == again.
			self should: [gpu compileShader: 'invalid GLSL source' stage: 0]
				raise: GPUError withExceptionDo: [:e | self assert: e platformLastError notEmpty]]
		ifFalse: [
			self should: [gpu compileShader: source stage: 0]
				raise: GPUError withExceptionDo: [:e |
					self assert: (e platformLastError includesSubstring: 'on Metal shaders are MSL')]]
!
testBlitTwoCheckedRects
	| gpu dev src dst cmd bytes |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	src := gpu createTexture: dev width: 2 height: 2 format: 2 usage: 1.
	[
		dst := gpu createTexture: dev width: 2 height: 2 format: 2 usage: 2.
		gpu uploadTexture: src bytes: #[255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255]
			x: 0 y: 0 width: 2 height: 2 bytesPerRow: 8.
		cmd := gpu acquireCommandBuffer: dev.
		self should: [gpu blit: cmd source: src rect: #(0 0 3 2) destination: dst rect: #(0 0 2 2) linear: false]
			raise: GPUError.
		self assert: (gpu blit: cmd source: src rect: #(0 0 2 2) destination: dst rect: #(0 0 2 2) linear: false)
			identicalTo: gpu.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: dst x: 0 y: 0 width: 2 height: 2 into: (ByteArray new: 16).
		self assert: bytes equals: #[255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255]
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		dst ifNotNil: [gpu release: dst].
		gpu release: src]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testShaderPipelineAndTypedResources
	| gpu dev lang source entry vs fs pipeline tex sample buffer sampler cmd pass |
	gpu := GPUPrimitives.
	[
		dev := gpu createDevice: false.
		lang := gpu shaderLanguage: dev.
		self assert: (#('msl' 'glsl') includes: lang).
		source := Renderer shaderSourceFor: lang asSymbol.
		entry := lang = 'glsl' ifTrue: ['main'] ifFalse: ['vmain'].
		vs := gpu createShader: dev source: source entry: entry stage: 0
			samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
		entry := lang = 'glsl' ifTrue: ['main'] ifFalse: ['fmain'].
		lang = 'glsl' ifTrue: [source := gpu compileShader: source stage: 1].
		fs := gpu createShader: dev source: source entry: entry stage: 1
			samplers: 1 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
		self should: [
			gpu createPipeline: dev vertex: fs fragment: vs stride: 40 attributes: #()
				primitive: 0 blend: 2 format: 2] raise: GPUError.
		pipeline := gpu createPipeline: dev vertex: vs fragment: fs stride: 40
			attributes: #(4 0 7 16 7 20 5 24 7 28 2 32) primitive: 0 blend: 2 format: 2.
		tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
		sample := gpu createTexture: dev width: 1 height: 1 format: 2 usage: 1.
		sampler := gpu createSampler: dev linear: false repeat: false.
		buffer := gpu createBuffer: dev usage: 1 size: 120.
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu beginPass: cmd target: tex clear: #(0 0 0 1).
		self assert: (gpu bindPipeline: pass pipeline: pipeline) identicalTo: gpu.
		self assert: (gpu bindVertexBuffer: pass slot: 0 buffer: buffer offset: 0) identicalTo: gpu.
		self assert: (gpu bindTexture: pass slot: 0 texture: sample sampler: sampler) identicalTo: gpu.
		self assert: (gpu pushUniforms: pass stage: 0 slot: 0 bytes: (ByteArray new: 16)) identicalTo: gpu.
		gpu endPass: pass.
		gpu submit: cmd fence: false.
		cmd := nil.
		self assert: (gpu waitIdle: dev) identicalTo: gpu.
		self assert: (gpu release: dev) identicalTo: gpu.
		dev := nil
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		dev ifNotNil: [gpu release: dev]]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testCheckedProceduralDraw
	| gpu dev lang source vertex fragment vs fs tex cmd pass pipe bytes check draw |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	lang := gpu shaderLanguage: dev.
	lang = 'glsl'
		ifTrue: [
			source := '#version 450
#ifdef SAMALTAK_VERTEX
const vec2 corners[3] = vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));
void main(){ gl_Position = vec4(corners[gl_VertexIndex],0,1); }
#else
layout(location=0) out vec4 color;
void main(){ color = vec4(0,1,0,1); }
#endif'.
			vertex := fragment := 'main']
		ifFalse: [
			source := '#include <metal_stdlib>
using namespace metal;
vertex float4 vmain(uint id [[vertex_id]]) {
    const float2 corners[] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
    return float4(corners[id],0,1);
}
fragment float4 fmain() { return float4(0,1,0,1); }'.
			vertex := 'vmain'.
			fragment := 'fmain'].
	check := PlatformFFI bind: #(call 'platform' 'platform_gpu_draw_eligibility' (i32 i32 i32) i32).
	draw := PlatformFFI bind: #(call 'platform' 'platform_gpu_draw' (i32 u32 u32) i32).
	self assert: check notNil.
	self assert: draw notNil.
	[
		vs := gpu createShader: dev source: source entry: vertex stage: 0 samplers: 0
			uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
		fs := gpu createShader: dev source: source entry: fragment stage: 1 samplers: 0
			uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
		pipe := gpu createPipeline: dev vertex: vs fragment: fs stride: 0 attributes: #()
			primitive: 0 blend: 0 format: 2.
		tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu beginPass: cmd target: tex clear: #(1 0 0 1).
		self assert: (check tryInvoke3: pass with: 3 with: 0) equals: -1.
		self assert: (draw tryInvoke3: pass with: 3 with: 0) equals: 0.
		gpu bindPipeline: pass pipeline: pipe.
		self assert: (gpu draw: pass count: 3 first: 0) identicalTo: gpu.
		gpu release: pipe.
		pipe := nil.
		self assert: (check tryInvoke3: pass with: 3 with: 0) equals: 0.
		self assert: (gpu draw: pass count: 3 first: 0) identicalTo: gpu.
		gpu endPass: pass.
		self assert: (check tryInvoke3: pass with: 3 with: 0) equals: -1.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: tex x: 0 y: 0 width: 4 height: 4 into: (ByteArray new: 64).
		self assert: (bytes copyFrom: 1 to: 4) equals: #[0 255 0 255]
	] ensure: [
		{cmd. pipe. vs. fs. tex} do: [:handle | handle ifNotNil: [gpu release: handle]]]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testDrawWithVertexAttributes
	| gpu dev lang source vertex fragment vs fs tex cmd pass pipe verts buffer check bytes |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	lang := gpu shaderLanguage: dev.
	lang = 'glsl'
		ifTrue: [
			source := '#version 450
#ifdef SAMALTAK_VERTEX
layout(location=0) in vec2 position;
void main(){ gl_Position = vec4(position,0,1); }
#else
layout(location=0) out vec4 color;
void main(){ color = vec4(0,1,0,1); }
#endif'.
			vertex := fragment := 'main']
		ifFalse: [
			source := '#include <metal_stdlib>
using namespace metal;
struct Position { float2 xy [[attribute(0)]]; };
vertex float4 vmain(Position p [[stage_in]]) { return float4(p.xy,0,1); }
fragment float4 fmain() { return float4(0,1,0,1); }'.
			vertex := 'vmain'.
			fragment := 'fmain'].
	check := PlatformFFI bind: #(call 'platform' 'platform_gpu_draw_eligibility' (i32 i32 i32) i32).
	[
		vs := gpu createShader: dev source: source entry: vertex stage: 0 samplers: 0
			uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
		fs := gpu createShader: dev source: source entry: fragment stage: 1 samplers: 0
			uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
		"PF_VA_FLOAT2 (2), at byte offset 0, supplies both position components."
		pipe := gpu createPipeline: dev vertex: vs fragment: fs stride: 8 attributes: #(2 0)
			primitive: 0 blend: 0 format: 2.
		tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
		buffer := gpu createBuffer: dev usage: 1 size: 24.
		verts := Bitmap new: 6.
		#(16rBF800000 16rBF800000 16r40400000 16rBF800000 16rBF800000 16r40400000)
			doWithIndex: [:word :i | verts at: i put: word].
		gpu uploadBuffer: buffer bytes: verts count: 24 offset: 0.
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu beginPass: cmd target: tex clear: #(1 0 0 1).
		gpu bindPipeline: pass pipeline: pipe.
		gpu bindVertexBuffer: pass slot: 0 buffer: buffer offset: 0.
		self assert: (check tryInvoke3: pass with: 3 with: 0) equals: 0.
		gpu draw: pass count: 3 first: 0.
		gpu endPass: pass.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: tex x: 0 y: 0 width: 4 height: 4 into: (ByteArray new: 64).
		self assert: (bytes copyFrom: 1 to: 4) equals: #[0 255 0 255]
	] ensure: [
		{cmd. pipe. vs. fs. tex. buffer} do: [:handle | handle ifNotNil: [gpu release: handle]]]
! !
