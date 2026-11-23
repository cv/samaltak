NvTransport subclass: #NvIoctlTransport
	instanceVariableNames: 'ctlFd devFd minor'
	classVariableNames: ''
	package: 'System-NV'!

NvIoctlTransport comment: 'I reach RM through the open kernel module: ioctls on /dev/nvidiactl and /dev/nvidiaN (PosixDevice; hosted Linux), the escapes and parameter blocks of docs/nv.md (NvRm). Memory maps to the CPU by an RM map call on a new file then mmap. The kernel module forwards what GSP-RM must do as RPCs and does the rest itself (docs/nv-gsp.md, 3.3).'!

!NvIoctlTransport class methodsFor: 'testing'!
isAvailable
	"Is there an NVIDIA driver to talk to here (hosted, /dev/nvidiactl present)?"
	^PosixDevice isAvailable and: [File exists: '/dev/nvidiactl']
! !

!NvIoctlTransport methodsFor: 'accessing'!
ctlFd
	^ctlFd
!
minor
	^minor
! !

!NvIoctlTransport methodsFor: 'opening'!
open
	ctlFd := PosixDevice open: '/dev/nvidiactl' flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC)
!
isOpen
	^ctlFd notNil
!
attachGpu: index
	"NV_ESC_CARD_INFO for the index-th GPU's id and minor number, then my file of /dev/nvidiaN."
	| cards info gpuId |
	cards := NvStruct new: 64 * NvRm cardInfoSize.
	self ioctl: ctlFd escape: NvRm escCardInfo struct: cards.
	info := (0 to: 63) select: [:i | (cards u8At: i * NvRm cardInfoSize) ~= 0].
	index < info size ifFalse: [^self error: 'no NVIDIA GPU number ', index printString, ' (', info size printString, ' found)'].
	gpuId := cards u32At: (info at: index + 1) * NvRm cardInfoSize + 16.
	minor := cards u32At: (info at: index + 1) * NvRm cardInfoSize + 56.
	devFd := self openGpuFile.
	^gpuId
!
openGpuFile
	"A new file descriptor of /dev/nvidiaN tied to my control file (NV_ESC_REGISTER_FD)."
	| fd |
	fd := PosixDevice open: '/dev/nvidia', minor printString flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC).
	[self ioctl: fd escape: NvRm escRegisterFd struct: (NvRm registerFd: ctlFd)]
		ifCurtailed: [PosixDevice close: fd].
	^fd
!
close
	"Close my files. Safe to call twice."
	ctlFd isNil ifTrue: [^self].
	[devFd notNil ifTrue: [PosixDevice close: devFd. devFd := nil]]
		ensure: [PosixDevice close: ctlFd. ctlFd := nil]
! !

!NvIoctlTransport methodsFor: 'resource manager'!
ioctl: fd escape: escape struct: anNvStruct
	"Call the driver escape on fd with anNvStruct (copied out of the heap and back)."
	| address |
	address := anNvStruct copyToMachine.
	[PosixDevice ioctl: fd request: (NvRm request: escape size: anNvStruct size) argument: address.
	anNvStruct readFrom: address] ensure: [Machine free: address].
	^anNvStruct
!
withParams: anNvStructOrNil do: aBlock
	"aBlock with the address and size of a copy of anNvStructOrNil outside the heap (0 0 for nil); read it back after."
	| address |
	anNvStructOrNil isNil ifTrue: [^aBlock value: 0 value: 0].
	address := anNvStructOrNil copyToMachine.
	^[| r | r := aBlock value: address value: anNvStructOrNil size. anNvStructOrNil readFrom: address. r]
		ensure: [Machine free: address]
!
alloc: rmClass client: hClient parent: hParent params: anNvStructOrNil
	| call |
	self withParams: anNvStructOrNil do: [:address :size |
		call := NvRm allocRoot: hClient parent: hParent handle: 0 class: rmClass params: address size: size.
		self ioctl: ctlFd escape: NvRm escRmAlloc struct: call].
	(call u32At: 28) = 0 ifFalse: [^NvError signal: 'RM alloc of class 16r', (rmClass printString: 16) status: (call u32At: 28)].
	^call u32At: 8
!
control: command client: hClient object: hObject params: anNvStruct
	| call |
	self withParams: anNvStruct do: [:address :size |
		call := NvRm controlClient: hClient object: hObject command: command params: address size: size.
		self ioctl: ctlFd escape: NvRm escRmControl struct: call].
	(call u32At: 28) = 0 ifFalse: [^NvError signal: 'RM control 16r', (command printString: 16) status: (call u32At: 28)].
	^anNvStruct
!
free: hObject client: hClient parent: hParent
	| call |
	call := self ioctl: ctlFd escape: NvRm escRmFree struct: (NvRm freeRoot: hClient parent: hParent handle: hObject).
	(call u32At: 12) = 0 ifFalse: [^NvError signal: 'RM free' status: (call u32At: 12)]
! !

!NvIoctlTransport methodsFor: 'mapping'!
mapMemory: hMemory client: hClient device: hDevice size: size
	"System memory maps through a new file of /dev/nvidiactl."
	^self map: hMemory client: hClient device: hDevice size: size on: (PosixDevice open: '/dev/nvidiactl' flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC))
!
mapUsermode: hUsermode client: hClient device: hDevice size: size
	"The usermode page maps through a new file of /dev/nvidiaN."
	^self map: hUsermode client: hClient device: hDevice size: size on: self openGpuFile
!
map: hMemory client: hClient device: hDevice size: size on: fd
	"RM prepares a mapping of hMemory on fd (NV_ESC_RM_MAP_MEMORY), mmap makes it; fd closes after."
	| call |
	^[call := self ioctl: ctlFd escape: NvRm escRmMapMemory struct: (NvRm mapMemoryClient: hClient device: hDevice memory: hMemory offset: 0 length: size flags: 0 fd: fd).
	(call u32At: 40) = 0 ifFalse: [^NvError signal: 'RM map memory' status: (call u32At: 40)].
	PosixDevice mmap: size protection: (PosixDevice PROT_READ bitOr: PosixDevice PROT_WRITE) flags: PosixDevice MAP_SHARED fd: fd offset: 0]
		ensure: [PosixDevice close: fd]
!
unmapCpu: address size: size
	PosixDevice munmap: address length: size
!
mapToGpu: hMemory client: hClient device: hDevice dma: hDma size: size flags: flags
	| call |
	call := self ioctl: ctlFd escape: NvRm escRmMapMemoryDma struct: (NvRm mapDmaClient: hClient device: hDevice dma: hDma memory: hMemory length: size flags: flags).
	(call u32At: 56) = 0 ifFalse: [^NvError signal: 'RM map memory DMA' status: (call u32At: 56)].
	^call u64At: 48
!
unmapFromGpu: hMemory client: hClient device: hDevice dma: hDma gpuAddress: gpuAddress
	| call |
	call := self ioctl: ctlFd escape: NvRm escRmUnmapMemoryDma struct: (NvRm unmapDmaClient: hClient device: hDevice dma: hDma memory: hMemory gpuAddress: gpuAddress).
	(call u32At: 40) = 0 ifFalse: [^NvError signal: 'RM unmap memory DMA' status: (call u32At: 40)]
! !
