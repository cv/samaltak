Object subclass: #NvGspQueues
	instanceVariableNames: 'address deviceAddress'
	classVariableNames: ''
	package: 'System-NV'!

NvGspQueues comment: 'I am the shared memory GSP-RM and the CPU talk through (docs/nv-gsp.md 3.1; message_queue_cpu.c 60-126, kernel_gsp.c 4524-4527): one region of whole pages, contiguous for the device, in this order: a page table of the region''s own pages (one 8-byte device address a page; 129 entries in one page), the command queue (CPU to GSP, 256 KB) and the status queue (GSP to CPU, 256 KB). Each queue is a msgq ring: a msgqTxHeader and a msgqRxHeader in its first page, then 63 entries of 4 KB. The CPU makes the page table and the command queue''s header; GSP makes the status queue''s header when it boots (GSP_ARGUMENTS_CACHED tells it where all this is: arguments).

address is where the CPU reaches me (Machine memory), deviceAddress where the GPU does (a PciDevice DMA buffer''s device address on UEFI). cpuEndpoint sends on the command queue and receives on the status queue; gspEndpoint is the other side, for a fake GSP in tests.'!

!NvGspQueues class methodsFor: 'sizes'!
commandQueueSize
	^16r40000
!
statusQueueSize
	^16r40000
!
pageTableEntryCount
	"The queues' pages and the page table's own (_getMsgQueueParams: numPtes)."
	| pages |
	pages := self commandQueueSize + self statusQueueSize // NvGsp page.
	^pages + (pages * 8 + NvGsp page - 1 // NvGsp page)
!
pageTableSize
	^self pageTableEntryCount * 8 + NvGsp page - 1 // NvGsp page * NvGsp page
!
size
	^self pageTableSize + self commandQueueSize + self statusQueueSize
! !

!NvGspQueues class methodsFor: 'instance creation'!
at: cpuAddress device: aDeviceAddress
	"The queues in size bytes at cpuAddress (zeroed), the GPU's view of them at aDeviceAddress; prepare writes the CPU's part."
	^self new setAddress: cpuAddress device: aDeviceAddress
! !

!NvGspQueues methodsFor: 'initialization'!
setAddress: cpuAddress device: aDeviceAddress
	address := cpuAddress.
	deviceAddress := aDeviceAddress
!
prepare
	"The page table (the device address of each page of the region, the table's first) and the command queue's header (msgqTxCreate, msgq.c 188-245)."
	0 to: self class pageTableEntryCount - 1 do: [:i | Machine uint64At: address + (8 * i) put: deviceAddress + (NvGsp page * i)].
	self cpuEndpoint initializeTransmit: self class commandQueueSize
! !

!NvGspQueues methodsFor: 'accessing'!
address
	^address
!
deviceAddress
	^deviceAddress
!
commandQueueOffset
	^self class pageTableSize
!
statusQueueOffset
	^self commandQueueOffset + self class commandQueueSize
!
cpuEndpoint
	^NvGspEndpoint transmit: address + self commandQueueOffset receive: address + self statusQueueOffset
!
gspEndpoint
	^NvGspEndpoint transmit: address + self statusQueueOffset receive: address + self commandQueueOffset
!
arguments: heapAddress size: heapSize
	"GSP_ARGUMENTS_CACHED for these queues and GSP-RM's system-memory heap."
	^NvGsp arguments: deviceAddress pageTableEntries: self class pageTableEntryCount commandQueue: self commandQueueOffset statusQueue: self statusQueueOffset heap: heapAddress size: heapSize
! !
