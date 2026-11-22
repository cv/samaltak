Object subclass: #NvDevice
	instanceVariableNames: 'ctlFd devFd root device subdevice vaSpace virtualMemory gpuId minor deviceInstance classes grInfo usermode doorbell memories channels'
	classVariableNames: ''
	package: 'System-NV'!

NvDevice comment: 'I am an NVIDIA GPU driven from Smalltalk through the open kernel module''s resource manager (RM) API: ioctls on /dev/nvidiactl and /dev/nvidiaN (PosixDevice), with parameter blocks NvRm builds (docs/nv.md). Hosted Linux only: without devices (UEFI, macOS) or a GPU, open signals an error.

	NvDevice during: [:gpu | | m |
		m := gpu allocate: 4096.            "an NvMemory: system memory the GPU and the CPU both reach"
		m uint32At: 0 put: 42.
		gpu smVersion]                       "16rA04 on the GB10"

Opening makes the RM object tree a compute channel needs: a root client, the device and its subdevice, a VA space RM manages (no UVM: RM picks GPU addresses and writes the page tables), a virtual memory object to map memory into it, and the usermode (doorbell) page mapped for the CPU. Then allocate: gives memory, newChannel an NvChannel, newCompute an NvCompute. RM calls: alloc:parent:params:, control:object:params:, free:parent:; a status other than NV_OK signals an NvError.

close frees everything I made, newest first (channels, memories, the doorbell mapping, then the root client, which takes the rest of the RM objects with it) and closes the files; during: closes even when its block fails. Never leave a device open: an open one holds GPU memory and channels.'!

!NvDevice methodsFor: 'accessing'!
root
	^root
!
device
	^device
!
subdevice
	^subdevice
!
vaSpace
	^vaSpace
!
virtualMemory
	^virtualMemory
!
ctlFd
	^ctlFd
!
classes
	"The RM classes the GPU has (NV0080_CTRL_CMD_GPU_GET_CLASSLIST)."
	^classes
!
gpuId
	^gpuId
!
smVersion
	"The SM version as RM reports it (NV2080_CTRL_GR_INFO_INDEX_SM_VERSION: 16rA04 on the GB10)."
	^grInfo at: NvRm grInfoSmVersion
!
sassVersion
	"The SASS version a QMD names: 16rA4 for SM version 16rA04."
	^((self smVersion bitShift: -4) bitAnd: 16rF0) bitOr: (self smVersion bitAnd: 16rF)
!
grInfo: index
	^grInfo at: index
!
gpcCount
	^grInfo at: NvRm grInfoNumGpcs
!
tpcsPerGpc
	^grInfo at: NvRm grInfoNumTpcPerGpc
!
smsPerTpc
	^grInfo at: NvRm grInfoNumSmPerTpc
!
smCount
	^self gpcCount * self tpcsPerGpc * self smsPerTpc
!
maxWarpsPerSm
	^grInfo at: NvRm grInfoMaxWarpsPerSm
!
classFrom: candidates
	"The first of candidates (RM class numbers) the GPU has; error if none."
	^candidates detect: [:c | classes includes: c] ifNone: [self error: 'the GPU has none of the classes ', candidates printString]
!
doorbell
	"The CPU address of the usermode page; a channel rings at 16r90 with its work submit token."
	^doorbell
!
isOpen
	^ctlFd notNil
!
memories
	^memories
!
channels
	^channels
! !

!NvDevice methodsFor: 'opening'!
open: index
	"Open the index-th GPU (0-based) and make the objects a channel needs."
	| cards info |
	memories := OrderedCollection new.
	channels := OrderedCollection new.
	ctlFd := PosixDevice open: '/dev/nvidiactl' flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC).
	root := self alloc: NvRm classRootClient parent: 0 params: nil.
	cards := NvStruct new: 64 * NvRm cardInfoSize.
	self ioctl: ctlFd escape: NvRm escCardInfo struct: cards.
	info := (0 to: 63) select: [:i | (cards u8At: i * NvRm cardInfoSize) ~= 0].
	index < info size ifFalse: [^self error: 'no NVIDIA GPU number ', index printString, ' (', info size printString, ' found)'].
	gpuId := cards u32At: (info at: index + 1) * NvRm cardInfoSize + 16.
	minor := cards u32At: (info at: index + 1) * NvRm cardInfoSize + 56.
	devFd := self openGpuFile.
	deviceInstance := (self control: NvRm cmdGpuGetIdInfoV2 object: root params: (NvRm idInfoParams: gpuId)) u32At: 8.
	device := self alloc: NvRm classDevice parent: root params: (NvRm deviceParams: deviceInstance client: root).
	subdevice := self alloc: NvRm classSubdevice parent: device params: (NvRm subdeviceParams: 0).
	self readClasses.
	self readGrInfo.
	vaSpace := self alloc: NvRm classVaSpace parent: device params: (NvRm vaSpaceParams: NvRm vaSpaceFlagsNone).
	virtualMemory := self alloc: NvRm classMemoryVirtual parent: device params: (NvRm memoryVirtualParams: 0 vaSpace: vaSpace).
	usermode := self alloc: (self classFrom: NvRm usermodeClasses) parent: subdevice params: nil.
	doorbell := self mapToCpu: usermode size: 16r10000 file: '/dev/nvidia', minor printString
!
openGpuFile
	"A new file descriptor of /dev/nvidiaN tied to my control file (NV_ESC_REGISTER_FD)."
	| fd |
	fd := PosixDevice open: '/dev/nvidia', minor printString flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC).
	[self ioctl: fd escape: NvRm escRegisterFd struct: (NvRm registerFd: ctlFd)]
		ifCurtailed: [PosixDevice close: fd].
	^fd
!
readClasses
	| count list |
	count := (self control: NvRm cmdDeviceGetClassList object: device params: (NvRm classListParams: 0 list: 0)) u32At: 0.
	list := Machine allocate: count * 4.
	[self control: NvRm cmdDeviceGetClassList object: device params: (NvRm classListParams: count list: list).
	classes := ((0 to: count - 1) collect: [:i | Machine uint32At: list + (i * 4)]) asSet]
		ensure: [Machine free: list]
!
readGrInfo
	| indexes list |
	indexes := Array with: NvRm grInfoSmVersion with: NvRm grInfoNumGpcs with: NvRm grInfoNumTpcPerGpc with: NvRm grInfoNumSmPerTpc with: NvRm grInfoMaxWarpsPerSm.
	list := Machine allocate: indexes size * 8.
	[indexes doWithIndex: [:index :i | Machine uint32At: list + (i * 8) - 8 put: index].
	self control: NvRm cmdGrGetInfo object: subdevice params: (NvRm grInfoParams: indexes size list: list).
	grInfo := Dictionary new.
	indexes doWithIndex: [:index :i | grInfo at: index put: (Machine uint32At: list + (i * 8) - 4)]]
		ensure: [Machine free: list]
! !

!NvDevice methodsFor: 'resource manager'!
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
alloc: rmClass parent: hParent params: anNvStructOrNil
	"A new RM object of rmClass under hParent (RM picks its handle); its allocation parameters anNvStructOrNil."
	| call |
	self withParams: anNvStructOrNil do: [:address :size |
		call := NvRm allocRoot: (hParent = 0 ifTrue: [0] ifFalse: [root]) parent: hParent handle: 0 class: rmClass params: address size: size.
		self ioctl: ctlFd escape: NvRm escRmAlloc struct: call].
	(call u32At: 28) = 0 ifFalse: [^NvError signal: 'RM alloc of class 16r', (rmClass printString: 16) status: (call u32At: 28)].
	^call u32At: 8
!
control: command object: hObject params: anNvStruct
	"RM control command on hObject; answers anNvStruct with what RM wrote into it."
	| call |
	self withParams: anNvStruct do: [:address :size |
		call := NvRm controlClient: root object: hObject command: command params: address size: size.
		self ioctl: ctlFd escape: NvRm escRmControl struct: call].
	(call u32At: 28) = 0 ifFalse: [^NvError signal: 'RM control 16r', (command printString: 16) status: (call u32At: 28)].
	^anNvStruct
!
free: hObject parent: hParent
	| call |
	call := self ioctl: ctlFd escape: NvRm escRmFree struct: (NvRm freeRoot: root parent: hParent handle: hObject).
	(call u32At: 12) = 0 ifFalse: [^NvError signal: 'RM free' status: (call u32At: 12)]
!
mapToCpu: hMemory size: size file: path
	"The CPU address of size bytes of the memory hMemory: RM prepares a mapping on a new file of path, mmap makes it."
	| fd call |
	fd := path = '/dev/nvidiactl'
		ifTrue: [PosixDevice open: path flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC)]
		ifFalse: [self openGpuFile].
	^[call := self ioctl: ctlFd escape: NvRm escRmMapMemory struct: (NvRm mapMemoryClient: root device: device memory: hMemory offset: 0 length: size flags: 0 fd: fd).
	(call u32At: 40) = 0 ifFalse: [^NvError signal: 'RM map memory' status: (call u32At: 40)].
	PosixDevice mmap: size protection: (PosixDevice PROT_READ bitOr: PosixDevice PROT_WRITE) flags: PosixDevice MAP_SHARED fd: fd offset: 0]
		ensure: [PosixDevice close: fd]
!
mapToGpu: hMemory size: size
	"The GPU address (in my VA space) RM maps the memory hMemory at."
	| call |
	call := self ioctl: ctlFd escape: NvRm escRmMapMemoryDma struct: (NvRm mapDmaClient: root device: device dma: virtualMemory memory: hMemory length: size flags: NvRm mapDmaFlags).
	(call u32At: 56) = 0 ifFalse: [^NvError signal: 'RM map memory DMA' status: (call u32At: 56)].
	^call u64At: 48
!
unmapFromGpu: hMemory address: gpuAddress
	| call |
	call := self ioctl: ctlFd escape: NvRm escRmUnmapMemoryDma struct: (NvRm unmapDmaClient: root device: device dma: virtualMemory memory: hMemory gpuAddress: gpuAddress).
	(call u32At: 40) = 0 ifFalse: [^NvError signal: 'RM unmap memory DMA' status: (call u32At: 40)]
! !

!NvDevice methodsFor: 'memory'!
allocate: size
	"size bytes (rounded up to 4 KB) of zeroed memory the GPU and the CPU reach (an NvMemory); mine until freed or I close."
	| m |
	^self allocate: size gpuCached: false
!
allocate: size gpuCached: aBoolean
	"allocate:, or memory the GPU caches in its L2 (aBoolean): faster for kernels, not coherent with the CPU (NvMemory)."
	| m |
	m := NvMemory new device: self size: size gpuCached: aBoolean.
	memories add: m.
	^m
!
forget: anNvMemory
	memories remove: anNvMemory ifAbsent: []
!
forgetChannel: anNvChannel
	channels remove: anNvChannel ifAbsent: []
! !

!NvDevice methodsFor: 'channels'!
newChannel
	"A new GPFIFO channel in its own channel group, with the compute class bound (an NvChannel)."
	| c |
	c := NvChannel new device: self.
	channels add: c.
	^c
!
newCompute
	"A new NvCompute on a new channel."
	^NvCompute new channel: self newChannel
! !

!NvDevice methodsFor: 'closing'!
close
	"Free everything I made, newest first, and close my files. Safe to call twice."
	ctlFd isNil ifTrue: [^self].
	[channels reverse do: [:c | [c close] on: Error do: [:e | ]].
	memories reverse do: [:m | [m free] on: Error do: [:e | ]].
	doorbell notNil ifTrue: [[PosixDevice munmap: doorbell length: 16r10000] on: Error do: [:e | ]. doorbell := nil].
	root notNil ifTrue: [[self free: root parent: 0] on: Error do: [:e | ]. root := nil]]
		ensure: [
			devFd notNil ifTrue: [PosixDevice close: devFd. devFd := nil].
			PosixDevice close: ctlFd.
			ctlFd := nil]
! !

!NvDevice class methodsFor: 'instance creation'!
open
	"The first NVIDIA GPU, opened; close it when done (or use during:)."
	^self open: 0
!
open: index
	| d |
	d := self new.
	[d open: index] ifCurtailed: [d close].
	^d
!
during: aBlock
	"aBlock's value with the first GPU, open; closed after, whatever happens."
	| d |
	d := self open.
	^[aBlock value: d] ensure: [d close]
!
isAvailable
	"Is there an NVIDIA driver to talk to here (hosted, /dev/nvidiactl present)?"
	^PosixDevice isAvailable and: [File exists: '/dev/nvidiactl']
! !
