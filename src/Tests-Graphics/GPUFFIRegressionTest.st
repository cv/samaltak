GraphicsTestCase subclass: #GPUFFIRegressionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GPUFFIRegressionTest comment: 'I exercise opt-in platform FFI on SDL GPU. Run only in display CI, never on the local headless host.'!

!GPUFFIRegressionTest methodsFor: 'tests'!
testScalarPassStateAndConsumption
	| gpu dev tex cmd pass bytes original selectors |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
	selectors := #(setViewport:x:y:width:height: setScissor:x:y:width:height: endPass:).
	original := selectors collect: [:selector | gpu class compiledMethodAt: selector].
	[
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu beginPass: cmd target: tex clear: #(1 0 0.5 1).
		[
			Compiler compile: 'setViewport: p x: x y: y width: w height: h self error: ''legacy viewport fallback''' in: gpu class.
			Compiler compile: 'setScissor: p x: x y: y width: w height: h self error: ''legacy scissor fallback''' in: gpu class.
			Compiler compile: 'endPass: p self error: ''legacy end-pass fallback''' in: gpu class.
			self assert: (gpu ffiCandidateSetViewport: pass x: 0 y: 1.0e-300 width: 4 height: 4.0) identicalTo: gpu.
			self assert: (gpu ffiCandidateSetScissor: pass x: 0 y: 0 width: 4 height: 4) identicalTo: gpu.
			self assert: (gpu ffiCandidateEndPass: pass) identicalTo: gpu.
			self should: [gpu ffiCandidateEndPass: pass] raise: GPUError withExceptionDo: [:e |
				self assert: e operation equals: 'gpuEndPass'.
				self assert: (e platformLastError includesSubstring: 'bad render pass handle')]
		] ensure: [
			selectors with: original do: [:sel :method | gpu class addSelector: sel withMethod: method]].
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
	| gpu dev cmd fence done elapsed selectors original |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	selectors := #(submit:fence: fenceDone: fenceElapsed: waitFence:).
	original := selectors collect: [:selector | gpu class compiledMethodAt: selector].
	[
		Compiler compile: 'submit: cmd fence: f self error: ''legacy submit fallback''' in: gpu class.
		Compiler compile: 'fenceDone: f self error: ''legacy fence status fallback''' in: gpu class.
		Compiler compile: 'fenceElapsed: f self error: ''legacy fence time fallback''' in: gpu class.
		Compiler compile: 'waitFence: f self error: ''legacy wait fallback''' in: gpu class.
		cmd := gpu acquireCommandBuffer: dev.
		self assert: (gpu ffiCandidateSubmit: cmd fence: false) isNil.
		self should: [gpu ffiCandidateSubmit: cmd fence: true] raise: GPUError withExceptionDo: [:e |
			self assert: (e platformLastError includesSubstring: 'bad command buffer handle')].
		cmd := nil.
		cmd := gpu acquireCommandBuffer: dev.
		fence := gpu ffiCandidateSubmit: cmd fence: true.
		cmd := nil.
		done := gpu ffiCandidateFenceDone: fence.
		self assert: (done == true or: [done == false]).
		self assert: (gpu ffiCandidateWaitFence: fence) identicalTo: gpu.
		self assert: (gpu ffiCandidateFenceDone: fence).
		elapsed := gpu ffiCandidateFenceElapsed: fence.
		self assert: (elapsed isNil or: [elapsed >= 0]).
		gpu release: fence.
		fence := nil.
		self should: [gpu ffiCandidateFenceDone: -1] raise: GPUError.
		self should: [gpu ffiCandidateFenceElapsed: -1] raise: GPUError
	] ensure: [
		selectors with: original do: [:sel :method | gpu class addSelector: sel withMethod: method].
		cmd ifNotNil: [gpu release: cmd].
		fence ifNotNil: [gpu release: fence]]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testBoundedTransfers
	| gpu dev tex buffer bytes selectors original |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	tex := gpu createTexture: dev width: 3 height: 2 format: 1 usage: 1.
	selectors := #(uploadBuffer:bytes:count:offset: uploadTexture:bytes:x:y:width:height:bytesPerRow: download:x:y:width:height:into:).
	original := selectors collect: [:selector | gpu class compiledMethodAt: selector].
	[
		buffer := gpu createBuffer: dev usage: 1 size: 16.
		Compiler compile: 'uploadBuffer: b bytes: s count: n offset: o self error: ''legacy buffer fallback''' in: gpu class.
		Compiler compile: 'uploadTexture: t bytes: s x: x y: y width: w height: h bytesPerRow: r self error: ''legacy texture fallback''' in: gpu class.
		Compiler compile: 'download: t x: x y: y width: w height: h into: d self error: ''legacy download fallback''' in: gpu class.
		self assert: (gpu ffiCandidateUploadBuffer: buffer bytes: #[1 2 3 4 5 6] count: 4 offset: 12) identicalTo: gpu.
		self should: [gpu ffiCandidateUploadBuffer: buffer bytes: #[1 2 3 4 5 6] count: 5 offset: 12]
			raise: GPUError withExceptionDo: [:e | self assert: (e platformLastError includesSubstring: 'out of buffer bounds')].
		self assert: (gpu ffiCandidateUploadTexture: tex bytes: #[1 2 3 255 4 5 6] x: 0 y: 0 width: 3 height: 2 bytesPerRow: 4)
			identicalTo: gpu.
		self should: [gpu ffiCandidateUploadTexture: tex bytes: #[1 2 3] x: 0 y: 0 width: 3 height: 2 bytesPerRow: 4]
			raise: GPUError.
		bytes := ByteArray new: 8.
		bytes at: 7 put: 42; at: 8 put: 43.
		self assert: (gpu ffiCandidateDownload: tex x: 0 y: 0 width: 3 height: 2 into: bytes) identicalTo: bytes.
		self assert: bytes equals: #[1 2 3 4 5 6 42 43].
		self should: [gpu ffiCandidateDownload: tex x: 0 y: 0 width: 3 height: 2 into: (ByteArray new: 5)]
			raise: GPUError
	] ensure: [
		selectors with: original do: [:sel :method | gpu class addSelector: sel withMethod: method].
		gpu waitIdle: dev.
		buffer ifNotNil: [gpu release: buffer].
		gpu release: tex]
!
testBeginClearAndLoad
	| gpu dev tex cmd pass original bytes |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	tex := gpu createTexture: dev width: 4 height: 4 format: 2 usage: 2.
	original := gpu class compiledMethodAt: #beginPass:target:clear:.
	[
		Compiler compile: 'beginPass: cmd target: t clear: c self error: ''legacy begin fallback''' in: gpu class.
		cmd := gpu acquireCommandBuffer: dev.
		pass := gpu ffiCandidateBeginPass: cmd target: tex clear: #(0 1.0 1.0e-300 1).
		gpu endPass: pass.
		pass := gpu ffiCandidateBeginPass: cmd target: tex clear: nil.
		gpu endPass: pass.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: tex x: 0 y: 0 width: 4 height: 4 into: (ByteArray new: 64).
		self assert: (bytes copyFrom: 1 to: 4) equals: #[0 255 0 255]
	] ensure: [
		gpu class addSelector: #beginPass:target:clear: withMethod: original.
		cmd ifNotNil: [gpu release: cmd].
		gpu release: tex]
!
testSwapchainAbsentAndDrawable
	| gpu dev window cmd result pass deadline |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	window := gpu openWindow: 32 height: 32 title: 'hidden GPU fixture' flags: 1.
	[
		self withoutLegacy: #('claim: d window: w' 'swapchainFormat: d window: w' 'acquireSwapchain: c window: w') do: [
			self assert: (gpu ffiCandidateClaim: dev window: window) identicalTo: gpu.
			self assert: (#(1 2 3) includes: (gpu ffiCandidateSwapchainFormat: dev window: window)).
			cmd := gpu acquireCommandBuffer: dev.
			self assert: (gpu ffiCandidateAcquireSwapchain: cmd window: window) isNil.
			gpu showWindow: window.
			deadline := Time millisecondClockValue + 3000.
			[result := gpu ffiCandidateAcquireSwapchain: cmd window: window.
			 result isNil and: [Time millisecondClockValue < deadline]] whileTrue: [
				(Delay forMilliseconds: 10) wait].
			self assert: result notNil.
			self assert: result size equals: 3.
			self assert: (result allSatisfy: [:n | n > 0]).
			pass := gpu beginPass: cmd target: result first clear: #(0 0 0 1).
			gpu endPass: pass.
			gpu submit: cmd fence: false.
			cmd := nil.
			gpu waitIdle: dev]
	] ensure: [
		cmd ifNotNil: [gpu release: cmd].
		gpu closeWindow: window]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testOwnedCompilerOutputAndDiagnostics
	| gpu language source expected result original |
	gpu := GPUPrimitives.
	language := gpu shaderLanguage: GPUDevice default handle.
	source := Renderer glslShaderSource.
	language = 'glsl' ifTrue: [expected := gpu compileShader: source stage: 0].
	original := gpu class compiledMethodAt: #compileShader:stage:.
	[
		Compiler compile: 'compileShader: s stage: n self error: ''legacy shader fallback''' in: gpu class.
		language = 'glsl'
			ifTrue: [
				result := gpu ffiCandidateCompileShader: source stage: 0.
				self assert: result equals: expected.
				self deny: result == expected.
				self should: [gpu ffiCandidateCompileShader: 'invalid GLSL source' stage: 0]
					raise: GPUError withExceptionDo: [:e | self assert: e platformLastError notEmpty]]
			ifFalse: [
				self should: [gpu ffiCandidateCompileShader: source stage: 0]
					raise: GPUError withExceptionDo: [:e |
						self assert: (e platformLastError includesSubstring: 'on Metal shaders are MSL')]]
	] ensure: [gpu class addSelector: #compileShader:stage: withMethod: original]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testBlitTwoCheckedRects
	| gpu dev src dst cmd original bytes |
	gpu := GPUPrimitives.
	dev := GPUDevice default handle.
	src := gpu createTexture: dev width: 2 height: 2 format: 2 usage: 1.
	original := gpu class compiledMethodAt: #blit:source:rect:destination:rect:linear:.
	[
		dst := gpu createTexture: dev width: 2 height: 2 format: 2 usage: 2.
		gpu uploadTexture: src bytes: #[255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255]
			x: 0 y: 0 width: 2 height: 2 bytesPerRow: 8.
		cmd := gpu acquireCommandBuffer: dev.
		Compiler compile: 'blit: c source: s rect: sr destination: d rect: dr linear: b self error: ''legacy blit fallback''' in: gpu class.
		self should: [gpu ffiCandidateBlit: cmd source: src rect: #(0 0 3 2) destination: dst rect: #(0 0 2 2) linear: false]
			raise: GPUError.
		self assert: (gpu ffiCandidateBlit: cmd source: src rect: #(0 0 2 2) destination: dst rect: #(0 0 2 2) linear: false)
			identicalTo: gpu.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: dst x: 0 y: 0 width: 2 height: 2 into: (ByteArray new: 16).
		self assert: bytes equals: #[255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255]
	] ensure: [
		gpu class addSelector: #blit:source:rect:destination:rect:linear: withMethod: original.
		cmd ifNotNil: [gpu release: cmd].
		dst ifNotNil: [gpu release: dst].
		gpu release: src]
! !

!GPUFFIRegressionTest methodsFor: 'fixture support'!
withoutLegacy: methodHeaders do: aBlock
	| behavior replacements originals |
	behavior := GPUPrimitives class.
	replacements := methodHeaders collect: [:header |
		Compiler compileMethod: header, ' self error: ''legacy GPU fallback''' in: behavior classified: 'FFI test'].
	originals := replacements collect: [:method | behavior compiledMethodAt: method selector].
	[
		replacements do: [:method | behavior addSelector: method selector withMethod: method].
		aBlock value
	] ensure: [originals do: [:method | behavior addSelector: method selector withMethod: method]]
! !

!GPUFFIRegressionTest methodsFor: 'tests'!
testShaderPipelineAndTypedResources
	| gpu dev lang source entry vs fs pipeline tex sample buffer sampler cmd pass |
	gpu := GPUPrimitives.
	[
		self withoutLegacy: #(
			'createDevice: b'
			'shaderLanguage: d'
			'createShader: d source: src entry: e stage: st samplers: s uniformBuffers: u storageBuffers: b storageTextures: t'
			'createPipeline: d vertex: v fragment: f stride: s attributes: a primitive: p blend: b format: fmt'
			'createTexture: d width: w height: h format: f usage: u'
			'createSampler: d linear: l repeat: r'
			'createBuffer: d usage: u size: n'
			'acquireCommandBuffer: d'
			'bindPipeline: p pipeline: q'
			'bindVertexBuffer: p slot: s buffer: b offset: o'
			'bindTexture: p slot: s texture: t sampler: a'
			'pushUniforms: p stage: st slot: sl bytes: n'
			'waitIdle: d'
			'release: h') do: [
			dev := gpu ffiCandidateCreateDevice: false.
			lang := gpu ffiCandidateShaderLanguage: dev.
			self assert: (#('msl' 'glsl') includes: lang).
			source := Renderer shaderSourceFor: lang asSymbol.
			entry := lang = 'glsl' ifTrue: ['main'] ifFalse: ['vmain'].
			vs := gpu ffiCandidateCreateShader: dev source: source entry: entry stage: 0
				samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
			entry := lang = 'glsl' ifTrue: ['main'] ifFalse: ['fmain'].
			lang = 'glsl' ifTrue: [source := gpu compileShader: source stage: 1].
			fs := gpu ffiCandidateCreateShader: dev source: source entry: entry stage: 1
				samplers: 1 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
			self should: [
				gpu ffiCandidateCreatePipeline: dev vertex: fs fragment: vs stride: 40 attributes: #()
					primitive: 0 blend: 2 format: 2] raise: GPUError.
			pipeline := gpu ffiCandidateCreatePipeline: dev vertex: vs fragment: fs stride: 40
				attributes: #(4 0 7 16 7 20 5 24 7 28 2 32) primitive: 0 blend: 2 format: 2.
			tex := gpu ffiCandidateCreateTexture: dev width: 4 height: 4 format: 2 usage: 2.
			sample := gpu ffiCandidateCreateTexture: dev width: 1 height: 1 format: 2 usage: 1.
			sampler := gpu ffiCandidateCreateSampler: dev linear: false repeat: false.
			buffer := gpu ffiCandidateCreateBuffer: dev usage: 1 size: 120.
			cmd := gpu ffiCandidateAcquireCommandBuffer: dev.
			pass := gpu beginPass: cmd target: tex clear: #(0 0 0 1).
			self assert: (gpu ffiCandidateBindPipeline: pass pipeline: pipeline) identicalTo: gpu.
			self assert: (gpu ffiCandidateBindVertexBuffer: pass slot: 0 buffer: buffer offset: 0) identicalTo: gpu.
			self assert: (gpu ffiCandidateBindTexture: pass slot: 0 texture: sample sampler: sampler) identicalTo: gpu.
			self assert: (gpu ffiCandidatePushUniforms: pass stage: 0 slot: 0 bytes: (ByteArray new: 16)) identicalTo: gpu.
			gpu endPass: pass.
			gpu submit: cmd fence: false.
			cmd := nil.
			self assert: (gpu ffiCandidateWaitIdle: dev) identicalTo: gpu.
			self assert: (gpu ffiCandidateRelease: dev) identicalTo: gpu.
			dev := nil]
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
	draw := PlatformFFI bind: #(call 'platform' 'platform_gpu_draw' (i32 i32 i32) i32).
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
		self withoutLegacy: #('draw: p count: n first: f') do: [
			self assert: (gpu ffiCandidateDraw: pass count: 3 first: 0) identicalTo: gpu].
		gpu ffiCandidateRelease: pipe.
		pipe := nil.
		self assert: (check tryInvoke3: pass with: 3 with: 0) equals: 0.
		self assert: (draw tryInvoke3: pass with: 3 with: 0) equals: 0.
		gpu endPass: pass.
		self assert: (check tryInvoke3: pass with: 3 with: 0) equals: -1.
		gpu submit: cmd fence: false.
		cmd := nil.
		bytes := gpu download: tex x: 0 y: 0 width: 4 height: 4 into: (ByteArray new: 64).
		self assert: (bytes copyFrom: 1 to: 4) equals: #[0 255 0 255]
	] ensure: [
		{cmd. pipe. vs. fs. tex} do: [:handle | handle ifNotNil: [gpu release: handle]]]
! !
