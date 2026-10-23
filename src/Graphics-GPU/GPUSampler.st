GPUResource subclass: #GPUSampler
	instanceVariableNames: 'linear repeat'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUSampler comment: 'I am a texture sampler: nearest or linear filtering, clamped or repeating addressing.'!

!GPUSampler methodsFor: 'private'!
setDevice: aDevice linear: linearBoolean repeat: repeatBoolean
	self setDevice: aDevice.
	linear := linearBoolean.
	repeat := repeatBoolean
!
createHandle
	^GPUPlatform createSampler: device handle linear: linear repeat: repeat
! !

!GPUSampler methodsFor: 'testing'!
isLinear
	^linear
! !
