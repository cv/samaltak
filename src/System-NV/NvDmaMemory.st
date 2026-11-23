Object subclass: #NvDmaMemory
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-NV'!

NvDmaMemory comment: 'I give out NvDmaBuffers: zeroed memory the CPU and the GPU both reach. NvPciDmaMemory takes them from a PciDevice (UEFI); tests have a fake in Machine memory.'!

!NvDmaMemory methodsFor: 'allocating'!
allocate: bytes
	"A zeroed NvDmaBuffer of bytes rounded up to whole pages."
	^self subclassResponsibility
!
release
	"Give back every buffer."
	self subclassResponsibility
! !
