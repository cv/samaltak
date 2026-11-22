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
isSynchronous
	^false
!
tearDown
	gpu isNil ifTrue: [^self].
	[super tearDown] ensure: [gpu close]
!
timeLimitMilliseconds
	^60000
! !

!NvComputeGPUTest methodsFor: 'tests'!
testFenceElapsedIsTheGPUsTime
	"The GPU's clock around the command buffer's work: more than nothing for ten clears of 1920 x 1080, at most the wall time; nothing for a command buffer without GPU work."
	| tex cmd f t0 wall |
	tex := gpu createTexture: dev width: 1920 height: 1080 format: 2 usage: 3.
	cmd := gpu acquireCommandBuffer: dev.
	t0 := Time microsecondClockValue.
	10 timesRepeat: [gpu endPass: (gpu beginPass: cmd target: tex clear: #(1.0 0.0 0.0 1.0))].
	f := gpu submit: cmd fence: true.
	gpu waitFence: f.
	wall := Time microsecondClockValue - t0.
	self assert: (gpu fenceDone: f).
	self assert: (gpu fenceElapsed: f) > 0.
	self assert: (gpu fenceElapsed: f) <= wall.
	cmd := gpu acquireCommandBuffer: dev.
	f := gpu submit: cmd fence: true.
	gpu waitFence: f.
	self assert: (gpu fenceElapsed: f) equals: 0
! !

!NvComputeGPUTest class methodsFor: 'testing'!
runsByDefault
	^false
! !
