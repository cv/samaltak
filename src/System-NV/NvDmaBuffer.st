Object subclass: #NvDmaBuffer
	instanceVariableNames: 'cpuAddress deviceAddress size'
	classVariableNames: ''
	package: 'System-NV'!

NvDmaBuffer comment: 'I am memory the CPU and the GPU both reach (an NvDmaMemory allocated me): whole pages, contiguous for the device, at cpuAddress for the CPU (Machine) and deviceAddress for the GPU. Offsets are 0-based bytes.'!

!NvDmaBuffer class methodsFor: 'instance creation'!
cpu: cpuAddress device: aDeviceAddress size: n
	^self new setCpu: cpuAddress device: aDeviceAddress size: n
! !

!NvDmaBuffer methodsFor: 'initialization'!
setCpu: cpuAddress0 device: aDeviceAddress size: n
	cpuAddress := cpuAddress0.
	deviceAddress := aDeviceAddress.
	size := n
! !

!NvDmaBuffer methodsFor: 'accessing'!
cpuAddress
	^cpuAddress
!
deviceAddress
	^deviceAddress
!
size
	^size
!
bytesAt: offset put: aByteArray
	offset + aByteArray size > size ifTrue: [^self error: 'DMA buffer of ', size printString, ' bytes: no room for ', aByteArray size printString, ' at ', offset printString].
	Machine bytesAt: cpuAddress + offset put: aByteArray.
	^aByteArray
!
bytesAt: offset count: n
	^Machine bytesAt: cpuAddress + offset count: n
!
u64At: offset put: anInteger
	^Machine uint64At: cpuAddress + offset put: anInteger
!
u64At: offset
	^Machine uint64At: cpuAddress + offset
! !
