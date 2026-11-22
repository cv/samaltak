GPUResource subclass: #GPUShader
	instanceVariableNames: 'source entry stage samplers uniformBuffers'
	classVariableNames: 'Compiled'
	package: 'Graphics-GPU'!

GPUShader comment: 'I am a vertex or fragment shader compiled from source in my device''s shaderLanguage: MSL (SDL_GPU on Metal), whose entry names the function, or GLSL (SDL_GPU on Vulkan), whose entry point is always main (see docs/platform.md for the binding rules). Compile errors signal a GPUError whose platformLastError holds the compiler''s log.

GLSL is compiled to SPIR-V once per source and stage and the SPIR-V kept in the image (Compiled; stage 2 compiles the Renderer''s), so an image that starts with the shaders it was built with runs no shader compiler: glslang''s symbol tables and pools, about 70 MB, stay for the life of a process that compiled once.

	GPUShader spirvFor: aGLSLString stage: #fragment     "compiled now, or kept"'!

!GPUShader methodsFor: 'private'!
setDevice: aDevice source: mslString entry: entryName stage: aSymbol samplers: samplerCount uniformBuffers: uniformCount
	self setDevice: aDevice.
	source := mslString.
	entry := entryName.
	stage := aSymbol.
	samplers := samplerCount.
	uniformBuffers := uniformCount
!
createHandle
	"GLSL goes to the device as the SPIR-V it compiles to (kept: spirvFor:stage:); MSL as source."
	^GPUPlatform createShader: device handle
		source: (device shaderLanguage == #glsl ifTrue: [self class spirvFor: source stage: stage] ifFalse: [source])
		entry: (device shaderLanguage == #glsl ifTrue: ['main'] ifFalse: [entry])
		stage: (self class stageNumber: stage)
		samplers: samplers uniformBuffers: uniformBuffers storageBuffers: 0 storageTextures: 0
! !

!GPUShader class methodsFor: 'SPIR-V'!
spirvFor: aGLSLString stage: aSymbol
	"The SPIR-V (a ByteArray) aGLSLString compiles to for stage #vertex or #fragment: kept from an earlier compile, else compiled now and kept. A compile error signals a GPUError."
	| key |
	Compiled isNil ifTrue: [Compiled := Dictionary new].
	key := Array with: aSymbol with: aGLSLString.
	^Compiled at: key ifAbsent: [
		| spirv |
		spirv := GPUPlatform compileShader: aGLSLString stage: (self stageNumber: aSymbol).
		spirv isNil ifTrue: [GPUError signal: 'gpuCompileShader'].
		Compiled at: key put: spirv]
!
precompile: aGLSLString
	"Compile both stages of aGLSLString and keep them; answer whether it could (not on macOS, where GLSL is not compiled)."
	^[#(#vertex #fragment) do: [:each | self spirvFor: aGLSLString stage: each]. true]
		on: Error do: [:e | e return: false]
!
forgetCompiled
	Compiled := nil
!
compiledCount
	^Compiled isNil ifTrue: [0] ifFalse: [Compiled size]
!
stageNumber: aSymbol
	^aSymbol == #vertex ifTrue: [0] ifFalse: [1]
! !

!GPUShader methodsFor: 'accessing'!
source
	^source
!
entry
	^entry
!
stage
	^stage
! !
