SoftwareGPUTest subclass: #NvComputeGPUTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

NvComputeGPUTest comment: 'Every test of SoftwareGPUTest on an NvComputeGPU: the same device protocol, handles and errors, and the same pixels from the raster kernels on the NVIDIA GPU as from the raster primitives. Needs the GPU, so it does not run by default (runsByDefault): make test-nv runs it, and it fails, saying so, where there is none. tearDown closes the GPU.'!

!NvComputeGPUTest methodsFor: 'running'!
gpuOn: aDisplay
	NvComputeGPU isAvailable ifFalse: [^self error: 'no NVIDIA GPU here (no /dev/nvidiactl, or no devices on this platform): NvComputeGPUTest needs one'].
	^NvComputeGPU on: aDisplay
!
shaderLanguage
	^'raster'
!
tearDown
	gpu isNil ifTrue: [^self].
	[super tearDown] ensure: [gpu close]
!
timeLimitMilliseconds
	^60000
! !

!NvComputeGPUTest class methodsFor: 'testing'!
runsByDefault
	^false
! !
