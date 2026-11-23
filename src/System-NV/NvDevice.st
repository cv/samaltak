Object subclass: #NvDevice
	instanceVariableNames: 'transport root device subdevice vaSpace virtualMemory gpuId deviceInstance classes grInfo usermode doorbell memories channels'
	classVariableNames: ''
	package: 'System-NV'!

NvDevice comment: 'I am an NVIDIA GPU driven from Smalltalk through the resource manager (RM) API, with parameter blocks NvRm builds (docs/nv.md), over an NvTransport: by default NvIoctlTransport, the open kernel module''s ioctls on /dev/nvidiactl and /dev/nvidiaN (PosixDevice; hosted Linux: without devices (UEFI, macOS) or a GPU, open signals an error); NvGspTransport is GSP-RM over its message queues (docs/nv-gsp.md).

	NvDevice during: [:gpu | | m |
		m := gpu allocate: 4096.            "an NvMemory: system memory the GPU and the CPU both reach"
		m uint32At: 0 put: 42.
		gpu smVersion]                       "16rA04 on the GB10"

Opening makes the RM object tree a compute channel needs: a root client, the device and its subdevice, a VA space RM manages (no UVM: RM picks GPU addresses and writes the page tables), a virtual memory object to map memory into it, and the usermode (doorbell) page mapped for the CPU. Then allocate: gives memory, newChannel an NvChannel, newCompute an NvCompute. RM calls: alloc:parent:params:, control:object:params:, free:parent:, and the maps (mapToCpu:size:, mapToGpu:size: and their unmaps), all through my transport; a status other than NV_OK signals an NvError.

close frees everything I made, newest first (channels, memories, the doorbell mapping, then the root client, which takes the rest of the RM objects with it) and closes the transport; during: closes even when its block fails. Never leave a device open: an open one holds GPU memory and channels.'!

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
transport
	^transport
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
	^transport notNil and: [transport isOpen]
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
	self open: index over: NvIoctlTransport new
!
open: index over: anNvTransport
	"Open the index-th GPU through anNvTransport and make the objects a channel needs."
	memories := OrderedCollection new.
	channels := OrderedCollection new.
	transport := anNvTransport.
	transport open.
	root := self alloc: NvRm classRootClient parent: 0 params: nil.
	gpuId := transport attachGpu: index.
	deviceInstance := (self control: NvRm cmdGpuGetIdInfoV2 object: root params: (NvRm idInfoParams: gpuId)) u32At: 8.
	device := self alloc: NvRm classDevice parent: root params: (NvRm deviceParams: deviceInstance client: root).
	subdevice := self alloc: NvRm classSubdevice parent: device params: (NvRm subdeviceParams: 0).
	self readClasses.
	self readGrInfo.
	vaSpace := self alloc: NvRm classVaSpace parent: device params: (NvRm vaSpaceParams: NvRm vaSpaceFlagsNone).
	virtualMemory := self alloc: NvRm classMemoryVirtual parent: device params: (NvRm memoryVirtualParams: 0 vaSpace: vaSpace).
	usermode := self alloc: (self classFrom: NvRm usermodeClasses) parent: subdevice params: nil.
	doorbell := transport mapUsermode: usermode client: root device: device size: 16r10000
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
alloc: rmClass parent: hParent params: anNvStructOrNil
	"A new RM object of rmClass under hParent (RM picks its handle); its allocation parameters anNvStructOrNil."
	^transport alloc: rmClass client: (root ifNil: [0]) parent: hParent params: anNvStructOrNil
!
control: command object: hObject params: anNvStruct
	"RM control command on hObject; answers anNvStruct with what RM wrote into it."
	^transport control: command client: root object: hObject params: anNvStruct
!
free: hObject parent: hParent
	^transport free: hObject client: root parent: hParent
!
mapToCpu: hMemory size: size
	"The CPU address of size bytes of the system memory hMemory."
	^transport mapMemory: hMemory client: root device: device size: size
!
unmapFromCpu: address size: size
	transport unmapCpu: address size: size
!
mapToGpu: hMemory size: size
	"The GPU address (in my VA space) RM maps the memory hMemory at."
	^transport mapToGpu: hMemory client: root device: device dma: virtualMemory size: size flags: NvRm mapDmaFlags
!
unmapFromGpu: hMemory address: gpuAddress
	transport unmapFromGpu: hMemory client: root device: device dma: virtualMemory gpuAddress: gpuAddress
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
	"Free everything I made, newest first, and close my transport. Safe to call twice."
	self isOpen ifFalse: [^self].
	[channels reverse do: [:c | [c close] on: Error do: [:e | ]].
	memories reverse do: [:m | [m free] on: Error do: [:e | ]].
	doorbell notNil ifTrue: [[transport unmapCpu: doorbell size: 16r10000] on: Error do: [:e | ]. doorbell := nil].
	root notNil ifTrue: [[self free: root parent: 0] on: Error do: [:e | ]. root := nil]]
		ensure: [transport close]
! !

!NvDevice class methodsFor: 'instance creation'!
open
	"The first NVIDIA GPU, opened; close it when done (or use during:)."
	^self open: 0
!
open: index
	^self open: index over: NvIoctlTransport new
!
open: index over: anNvTransport
	"The index-th GPU, opened through anNvTransport (NvIoctlTransport, NvGspTransport)."
	| d |
	d := self new.
	[d open: index over: anNvTransport] ifCurtailed: [d close].
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
	^NvIoctlTransport isAvailable
! !
