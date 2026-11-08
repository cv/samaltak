GPUResource subclass: #GPUShader
	instanceVariableNames: 'source entry stage samplers uniformBuffers'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUShader comment: 'I am a vertex or fragment shader compiled from source in my device''s shaderLanguage: MSL (SDL_GPU on Metal), whose entry names the function, or GLSL (SDL_GPU on Vulkan), whose entry point is always main (see docs/platform.md for the binding rules). Compile errors signal a GPUError whose platformLastError holds the compiler''s log.'!

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
	^GPUPlatform createShader: device handle source: source entry: (device shaderLanguage == #glsl ifTrue: ['main'] ifFalse: [entry])
		stage: (stage == #vertex ifTrue: [0] ifFalse: [1])
		samplers: samplers uniformBuffers: uniformBuffers storageBuffers: 0 storageTextures: 0
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
