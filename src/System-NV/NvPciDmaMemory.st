NvDmaMemory subclass: #NvPciDmaMemory
	instanceVariableNames: 'device'
	classVariableNames: ''
	package: 'System-NV'!

NvPciDmaMemory comment: 'I give out DMA memory of a PciDevice (the firmware''s AllocateBuffer and Map: contiguous pages, below 4 GB, at the device address the IOMMU or the firmware gives). release gives it all back with the device''s own release.'!

!NvPciDmaMemory class methodsFor: 'instance creation'!
on: aPciDevice
	^self new setDevice: aPciDevice
! !

!NvPciDmaMemory methodsFor: 'initialization'!
setDevice: aPciDevice
	device := aPciDevice
! !

!NvPciDmaMemory methodsFor: 'allocating'!
allocate: bytes
	| n host |
	n := bytes + 4095 // 4096 * 4096.
	host := device allocate: n.
	host isNil ifTrue: [^self error: 'no DMA memory for ', n printString, ' bytes (the firmware allocates below 4 GB)'].
	^NvDmaBuffer cpu: host device: (device deviceAddress: host) size: n
!
release
	device release
! !
