GPUResource subclass: #GPUShader
	instanceVariableNames: 'source entry stage samplers uniformBuffers'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUShader comment: 'I am a vertex or fragment shader compiled from MSL source (SDL_GPU on Metal; see vm/platform/README.md for the binding rules). Compile errors signal a GPUError whose platformLastError holds the Metal log.'!

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
	^GPUPlatform createShader: device handle source: source entry: entry
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
