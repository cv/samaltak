Object subclass: #NvTransport
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-NV'!

NvTransport comment: 'I am how an NvDevice reaches the NVIDIA resource manager (RM): everything RM-specific NvDevice does goes through me, so the same NvDevice (and NvMemory, NvChannel, NvCompute above it) runs on the open kernel module''s ioctls (NvIoctlTransport, hosted Linux) and, in the tests, on a fake that logs the calls without a GPU (NvFakeTransport, NvTransportTest). Parameter blocks are NvStructs as NvRm builds them; a status other than NV_OK signals an NvError.

	open				before anything else
	attachGpu: index			the index-th GPU''s id (after the root client exists)
	alloc: class client: hClient parent: hParent params: anNvStructOrNil		a new object''s handle
	control: command client: hClient object: hObject params: anNvStruct		anNvStruct as RM left it
	free: hObject client: hClient parent: hParent
	mapMemory: / mapUsermode: hMemory client: device: size:		a CPU address of an object''s pages
	unmapCpu: address size:
	mapToGpu: hMemory client: device: dma: size: flags:		a GPU address in the dma object''s VA space
	unmapFromGpu: hMemory client: device: dma: gpuAddress:
	close'!

!NvTransport methodsFor: 'opening'!
open
	self subclassResponsibility
!
attachGpu: index
	"The id (gpuId) of the index-th GPU (0-based); after the root client was allocated."
	^self subclassResponsibility
!
isOpen
	^self subclassResponsibility
!
close
	self subclassResponsibility
! !

!NvTransport methodsFor: 'resource manager'!
alloc: rmClass client: hClient parent: hParent params: anNvStructOrNil
	"A new RM object of rmClass under hParent of the client hClient (0 for a new root client); answer its handle."
	^self subclassResponsibility
!
control: command client: hClient object: hObject params: anNvStruct
	"RM control command on hObject; answer anNvStruct with what RM wrote into it."
	^self subclassResponsibility
!
free: hObject client: hClient parent: hParent
	self subclassResponsibility
! !

!NvTransport methodsFor: 'mapping'!
mapMemory: hMemory client: hClient device: hDevice size: size
	"The CPU address of size bytes of the memory object hMemory."
	^self subclassResponsibility
!
mapUsermode: hUsermode client: hClient device: hDevice size: size
	"The CPU address of the usermode (doorbell) page hUsermode."
	^self subclassResponsibility
!
unmapCpu: address size: size
	self subclassResponsibility
!
mapToGpu: hMemory client: hClient device: hDevice dma: hDma size: size flags: flags
	"The GPU address the memory hMemory is mapped at in the VA space of the virtual memory object hDma."
	^self subclassResponsibility
!
unmapFromGpu: hMemory client: hClient device: hDevice dma: hDma gpuAddress: gpuAddress
	self subclassResponsibility
! !
