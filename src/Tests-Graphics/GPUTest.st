GraphicsTestCase subclass: #GPUTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GPUTest comment: 'I check the Graphics-GPU wrappers: texture transfers, render pass clears, fences, errors carrying the platform message, and re-creation of handles in a new session (as after an image restart).'!

!GPUTest methodsFor: 'tests'!
testInjectedEventRoundTrip
	| buffer event |
	buffer := Array new: 8.
	[(DisplayWindow nextEventInto: buffer) notNil] whileTrue.
	DisplayWindow injectEvent: {7. nil. 1.5. 2. 0. 8. 'hello'. nil}.
	event := DisplayWindow nextEventInto: buffer.
	self assert: (event at: 1) equals: 7.
	self assert: (event at: 6) equals: 8.
	self assert: (event at: 7) equals: 'hello'.
	self assert: (DisplayWindow nextEventInto: buffer) isNil
!
testTextureRoundTrip
	| tex bytes back |
	tex := GPUDevice default textureWidth: 8 height: 4 format: #r8 usage: #(#sampler #colorTarget).
	bytes := (1 to: 32) asArray asByteArray.
	tex upload: bytes.
	GPUDevice default commandBuffer submitWithFence wait.
	back := tex download.
	self assert: back equals: bytes.
	tex release
!
testClearPass
	| tex cmd fence px |
	tex := GPUDevice default textureWidth: 4 height: 4 format: #rgba8 usage: #(#colorTarget).
	cmd := GPUDevice default commandBuffer.
	(cmd beginPassOn: tex clear: #(1 0 0.5 1)) end.
	fence := cmd submitWithFence.
	fence wait.
	self assert: fence isDone.
	px := tex download.
	self assert: (px copyFrom: 1 to: 4) asArray equals: #(255 0 128 255).
	tex release
!
testShaderErrorCarriesPlatformMessage
	| shader |
	shader := GPUDevice default shaderSource: 'this is not metal' entry: 'vmain' stage: #vertex samplers: 0 uniformBuffers: 0.
	self should: [shader handle] raise: GPUError withExceptionDo: [:e |
		"GLSL fails compiling to SPIR-V (GPUShader keeps the SPIR-V), MSL when the device makes the shader"
		self assert: e operation equals: (GPUDevice default shaderLanguage == #glsl ifTrue: ['gpuCompileShader'] ifFalse: ['gpuCreateShader']).
		self assert: e platformLastError notEmpty.
		self assert: (e messageText includesSubstring: e platformLastError)]
!
testBadArgumentsSignalGPUError
	self should: [(GPUDevice default textureWidth: 0 height: 0 format: #rgba8 usage: #(#sampler)) generation] raise: GPUError
!
testWindowDescriptors
	| window |
	window := GPUPrimitives openWindow: 400 height: 300 title: 'descriptor window' flags: 5.
	[
		self assert: (GPUPrimitives windowSize: window) equals: #(400 300).
		self assert: (GPUPrimitives windowDisplayScale: window) > 0.0.
		self assert: (GPUPrimitives windowRefreshRate: window) >= 0.0.
		self assert: (GPUPrimitives showWindow: window) identicalTo: GPUPrimitives.
		self assert: (GPUPrimitives hideWindow: window) identicalTo: GPUPrimitives
	] ensure: [self assert: (GPUPrimitives closeWindow: window) identicalTo: GPUPrimitives].
	self should: [GPUPrimitives windowDisplayScale: window] raise: GPUError withExceptionDo: [:e |
		self assert: e operation equals: 'windowDisplayScale'.
		self assert: (e platformLastError includesSubstring: 'bad window handle')].
	self should: [GPUPrimitives window: window textInputAreaX: 0 y: 0 width: 1 height: 1 cursor: 0]
		raise: GPUError withExceptionDo: [:e |
			self assert: e operation equals: 'windowSetTextInputArea']
!
testNewSessionRecreatesHandles
	"After an image restart every handle is stale: objects re-create themselves on first use, textures report a new generation, and Forms and atlas pages upload their contents again."
	| tex generation form result |
	tex := GPUDevice default textureWidth: 2 height: 2 format: #rgba8 usage: #(#sampler).
	generation := tex generation.
	form := Form width: 2 height: 2.
	form fill: Color blue.
	self render: [:c | c image: form in: (0 @ 0 extent: 1 @ 1)] extent: 1 @ 1.
	GPUDevice startUp: true.
	self deny: tex isAlive.
	self assert: tex generation equals: generation + 1.
	self assert: tex isAlive.
	result := self render: [:c |
		c image: form in: (0 @ 0 extent: 1 @ 1).
		c drawString: 'x' at: 0 @ 0 font: Font code color: Color black] extent: 10 @ 10.
	self assertPixel: 0 @ 0 in: result is: #(0 0 255 255).
	tex release
! !
