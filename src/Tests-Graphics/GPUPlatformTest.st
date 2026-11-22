TestCase subclass: #GPUPlatformTest
	instanceVariableNames: 'stderr'
	classVariableNames: ''
	package: 'Tests-Graphics'!

GPUPlatformTest comment: 'GPUPlatform''s choice of a GPU other than the default (--gpu, SAMALTAK_GPU): software is a SoftwareGPU on the display given; nv the NVIDIA device class''s, where it is there, available and opens; anything else, or nv where it cannot be made, the default (nil), said on stderr. The NVIDIA class is a stand-in here (GPUPlatformTestNv): no GPU needed.'!

!GPUPlatformTest methodsFor: 'tests'!
testNoNameIsTheDefault
	self assert: (GPUPlatform device: nil on: SoftwareGPUTestDisplay new nv: GPUPlatformTestNv new) isNil.
	self assert: (GPUPlatform device: '' on: SoftwareGPUTestDisplay new nv: GPUPlatformTestNv new) isNil
!
testSoftware
	| d gpu |
	d := SoftwareGPUTestDisplay new.
	gpu := GPUPlatform device: 'software' on: d nv: nil.
	self assert: gpu class equals: SoftwareGPU.
	self assert: gpu display == d
!
testNv
	| d nv |
	d := SoftwareGPUTestDisplay new.
	nv := GPUPlatformTestNv new.
	self assert: (GPUPlatform device: 'nv' on: d nv: nv) equals: {#nv. d}
!
testNvFallsBackToTheDefault
	"Without Graphics-NV, without an NVIDIA GPU, when it does not open; an unknown name."
	| d |
	d := SoftwareGPUTestDisplay new.
	self assert: (GPUPlatform device: 'nv' on: d nv: nil) isNil.
	self assert: (GPUPlatform device: 'nv' on: d nv: (GPUPlatformTestNv new available: false)) isNil.
	self assert: (GPUPlatform device: 'nv' on: d nv: (GPUPlatformTestNv new fails: true)) isNil.
	self assert: (GPUPlatform device: 'vulkan' on: d nv: GPUPlatformTestNv new) isNil
!
testTheNvClassIsInTheImage
	self assert: (Smalltalk at: #NvComputeGPU ifAbsent: [nil]) notNil.
	self assert: ((Smalltalk at: #NvComputeGPU) inheritsFrom: SoftwareGPU)
! !

Object subclass: #GPUPlatformTestNv
	instanceVariableNames: 'available fails'
	classVariableNames: ''
	package: 'Tests-Graphics'!

GPUPlatformTestNv comment: 'A stand-in for NvComputeGPU''s class in GPUPlatformTest: isAvailable, and on: answers {#nv. aDisplay} or signals an Error.'!

!GPUPlatformTestNv methodsFor: 'accessing'!
available: aBoolean
	available := aBoolean
!
fails: aBoolean
	fails := aBoolean
!
isAvailable
	^available ~~ false
!
on: aDisplay
	fails == true ifTrue: [^self error: 'no GPU after all'].
	^{#nv. aDisplay}
! !
