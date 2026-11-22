Object subclass: #NvRm
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-NV'!

NvRm comment: 'I am the vocabulary of the NVIDIA open kernel module''s resource manager (RM) API, driver 580.178.04 (open-gpu-kernel-modules at that tag): ioctl request numbers, escape codes, RM classes, control commands and flags, and the parameter blocks as NvStructs (layouts in docs/nv-rm.md, checked against the C headers on arm64 and x86-64, which agree). I only build and read bytes; NvDevice makes the calls.

	NvRm request: NvRm escRmAlloc size: 32          "the ioctl request of NV_ESC_RM_ALLOC"
	NvRm allocRoot: 0 parent: 0 handle: 0 class: NvRm classRootClient params: 0 size: 0
	NvRm statusName: 16r1F                           "''NV_ERR_INVALID_ARGUMENT''"

Pointers inside parameter blocks (NvP64) are Machine addresses. Status fields: the RM call''s NV_STATUS, 0 when it worked.'!

!NvRm class methodsFor: 'ioctl'!
request: escape size: n
	"_IOWR(''F'', escape, n): the ioctl request number of a driver escape whose argument is n bytes."
	^((3 bitShift: 30) bitOr: ((n bitAnd: 16r3FFF) bitShift: 16)) bitOr: ((70 bitShift: 8) bitOr: escape)
!
escCardInfo
	^200
!
escRegisterFd
	^201
!
escRmAllocMemory
	^16r27
!
escRmFree
	^16r29
!
escRmControl
	^16r2A
!
escRmAlloc
	^16r2B
!
escRmMapMemory
	^16r4E
!
escRmUnmapMemory
	^16r4F
!
escRmMapMemoryDma
	^16r57
!
escRmUnmapMemoryDma
	^16r58
! !

!NvRm class methodsFor: 'classes'!
classRootClient
	^16r41
!
classDevice
	^16r80
!
classSubdevice
	^16r2080
!
classMemorySystem
	"NV01_MEMORY_SYSTEM: system memory; on an integrated GPU all its memory is."
	^16r3E
!
classMemoryVirtual
	^16r70
!
classVaSpace
	"FERMI_VASPACE_A"
	^16r90F1
!
classChannelGroup
	"KEPLER_CHANNEL_GROUP_A"
	^16rA06C
!
classContextShare
	"FERMI_CONTEXT_SHARE_A"
	^16r9067
!
usermodeClasses
	"The usermode (doorbell) classes, newest first."
	^#(16rC761 16rC661 16rC561 16rC461)
!
gpfifoClasses
	"Channel GPFIFO classes: BLACKWELL B and A, HOPPER, AMPERE."
	^#(16rCA6F 16rC96F 16rC86F 16rC56F)
!
computeClasses
	"Compute classes: BLACKWELL_COMPUTE_B and A, HOPPER, ADA, AMPERE B."
	^#(16rCEC0 16rCDC0 16rCBC0 16rC9C0 16rC7C0)
!
blackwellComputeA
	^16rCDC0
! !

!NvRm class methodsFor: 'commands'!
cmdSystemGetBuildVersionV2
	^16r13E
!
cmdGpuGetIdInfoV2
	^16r205
!
cmdDeviceGetClassList
	^16r800201
!
cmdGrGetInfo
	^16r20801201
!
cmdChannelGroupSchedule
	^16rA06C0101
!
cmdGpfifoGetWorkSubmitToken
	^16rC36F0108
!
grInfoSmVersion
	^16r0C
!
grInfoMaxWarpsPerSm
	^16r0D
!
grInfoNumGpcs
	^16r14
!
grInfoNumTpcPerGpc
	^16r17
!
grInfoNumSmPerTpc
	^16r20
! !

!NvRm class methodsFor: 'flags'!
vaSpaceFlagsNone
	^0
!
memoryAttrNoncontiguousPci
	"NVOS32 attr: physicality allow-noncontiguous (3 << 27), location PCI (1 << 25), page size 4 KB (1 << 23)."
	^((3 bitShift: 27) bitOr: (1 bitShift: 25)) bitOr: (1 bitShift: 23)
!
memoryAttr2Uncached
	"NVOS32 attr2: GPU cacheable no (2 << 2), prefer no ZBC (1)."
	^(2 bitShift: 2) bitOr: 1
!
memoryAllocFlags
	"NVOS32 alloc flags: map not required, alignment force, ignore bank placement."
	^(16r8000 bitOr: 16r100) bitOr: 1
!
mapDmaFlags
	"NVOS46 flags: read-write, page size 4 KB (1 << 8), cache snoop (1 << 4); RM picks the GPU address."
	^(1 bitShift: 8) bitOr: (1 bitShift: 4)
!
mapCachingWriteCombined
	"NVOS33 flags: caching type write-combined (2 << 23)."
	^2 bitShift: 23
!
mapCachingDefault
	"NVOS33 flags: the memory's own caching (6 << 23)."
	^6 bitShift: 23
!
typeNotifier
	^13
!
typeImage
	^0
! !

!NvRm class methodsFor: 'status'!
statusNames
	"NV_ERR_ names without the prefix, at their codes 1..16r8B."
	^#(
		BROKEN_FB BUFFER_TOO_SMALL BUSY_RETRY CALLBACK_NOT_SCHEDULED CARD_NOT_PRESENT CYCLE_DETECTED
		DMA_IN_USE DMA_MEM_NOT_LOCKED DMA_MEM_NOT_UNLOCKED DUAL_LINK_INUSE ECC_ERROR FIFO_BAD_ACCESS
		FREQ_NOT_SUPPORTED GPU_DMA_NOT_INITIALIZED GPU_IS_LOST GPU_IN_FULLCHIP_RESET GPU_NOT_FULL_POWER GPU_UUID_NOT_FOUND
		HOT_SWITCH I2C_ERROR I2C_SPEED_TOO_HIGH ILLEGAL_ACTION IN_USE INFLATE_COMPRESSED_DATA_FAILED
		INSERT_DUPLICATE_NAME INSUFFICIENT_RESOURCES INSUFFICIENT_PERMISSIONS INSUFFICIENT_POWER INVALID_ACCESS_TYPE INVALID_ADDRESS
		INVALID_ARGUMENT INVALID_BASE INVALID_CHANNEL INVALID_CLASS INVALID_CLIENT INVALID_COMMAND
		INVALID_DATA INVALID_DEVICE INVALID_DMA_SPECIFIER INVALID_EVENT INVALID_FLAGS INVALID_FUNCTION
		INVALID_HEAP INVALID_INDEX INVALID_IRQ_LEVEL INVALID_LIMIT INVALID_LOCK_STATE INVALID_METHOD
		INVALID_OBJECT INVALID_OBJECT_BUFFER INVALID_OBJECT_HANDLE INVALID_OBJECT_NEW INVALID_OBJECT_OLD INVALID_OBJECT_PARENT
		INVALID_OFFSET INVALID_OPERATION INVALID_OWNER INVALID_PARAM_STRUCT INVALID_PARAMETER INVALID_PATH
		INVALID_POINTER INVALID_REGISTRY_KEY INVALID_REQUEST INVALID_STATE INVALID_STRING_LENGTH INVALID_READ
		INVALID_WRITE INVALID_XLATE IRQ_NOT_FIRING IRQ_EDGE_TRIGGERED MEMORY_TRAINING_FAILED MISMATCHED_SLAVE
		MISMATCHED_TARGET MISSING_TABLE_ENTRY MODULE_LOAD_FAILED MORE_DATA_AVAILABLE MORE_PROCESSING_REQUIRED MULTIPLE_MEMORY_TYPES
		NO_FREE_FIFOS NO_INTR_PENDING NO_MEMORY NO_SUCH_DOMAIN NO_VALID_PATH NOT_COMPATIBLE
		NOT_READY NOT_SUPPORTED OBJECT_NOT_FOUND OBJECT_TYPE_MISMATCH OPERATING_SYSTEM OTHER_DEVICE_FOUND
		OUT_OF_RANGE OVERLAPPING_UVM_COMMIT PAGE_TABLE_NOT_AVAIL PID_NOT_FOUND PROTECTION_FAULT RC_ERROR
		REJECTED_VBIOS RESET_REQUIRED STATE_IN_USE SIGNAL_PENDING TIMEOUT TIMEOUT_RETRY
		TOO_MANY_PRIMARIES UVM_ADDRESS_IN_USE MAX_SESSION_LIMIT_REACHED LIB_RM_VERSION_MISMATCH PRIV_SEC_VIOLATION GPU_IN_DEBUG_MODE
		FEATURE_NOT_ENABLED RESOURCE_LOST PMU_NOT_READY FLCN_ERROR FATAL_ERROR MEMORY_ERROR
		INVALID_LICENSE NVLINK_INIT_ERROR NVLINK_MINION_ERROR NVLINK_CLOCK_ERROR NVLINK_TRAINING_ERROR NVLINK_CONFIGURATION_ERROR
		RISCV_ERROR FABRIC_MANAGER_NOT_PRESENT ALREADY_SIGNALLED QUEUE_TASK_SLOT_NOT_AVAILABLE KEY_ROTATION_IN_PROGRESS TEST_ONLY_CODE_NOT_ENABLED
		SECURE_BOOT_FAILED INSUFFICIENT_ZBC_ENTRY NVLINK_FABRIC_NOT_READY NVLINK_FABRIC_FAILURE GPU_MEMORY_ONLINING_FAILURE REDUCTION_MANAGER_NOT_AVAILABLE
		THRESHOLD_CROSSED RESOURCE_RETIREMENT_ERROR FABRIC_STATE_OUT_OF_SYNC BUFFER_FULL BUFFER_EMPTY MC_FLA_OFFSET_TABLE_FULL
		DMA_XFER_FAILED)
!
statusName: anInteger
	anInteger = 0 ifTrue: [^'NV_OK'].
	anInteger = 16rFFFF ifTrue: [^'NV_ERR_GENERIC'].
	(anInteger between: 1 and: self statusNames size) ifTrue: [^'NV_ERR_', (self statusNames at: anInteger)].
	^'NV status 16r', (anInteger printString: 16)
! !

!NvRm class methodsFor: 'ioctl parameters'!
allocRoot: hRoot parent: hParent handle: hNew class: hClass params: address size: n
	"NVOS21_PARAMETERS (NV_ESC_RM_ALLOC), 32 bytes; RM writes hObjectNew at 8 and the status at 28."
	^(NvStruct new: 32)
		u32At: 0 put: hRoot; u32At: 4 put: hParent; u32At: 8 put: hNew; u32At: 12 put: hClass;
		u64At: 16 put: address; u32At: 24 put: n; yourself
!
controlClient: hClient object: hObject command: cmd params: address size: n
	"NVOS54_PARAMETERS (NV_ESC_RM_CONTROL), 32 bytes; status at 28."
	^(NvStruct new: 32)
		u32At: 0 put: hClient; u32At: 4 put: hObject; u32At: 8 put: cmd;
		u64At: 16 put: address; u32At: 24 put: n; yourself
!
freeRoot: hRoot parent: hParent handle: hOld
	"NVOS00_PARAMETERS (NV_ESC_RM_FREE), 16 bytes; status at 12."
	^(NvStruct new: 16) u32At: 0 put: hRoot; u32At: 4 put: hParent; u32At: 8 put: hOld; yourself
!
mapMemoryClient: hClient device: hDevice memory: hMemory offset: offset length: length flags: flags fd: fd
	"nv_ioctl_nvos33_parameters_with_fd (NV_ESC_RM_MAP_MEMORY), 56 bytes: NVOS33_PARAMETERS then the fd to mmap
	afterwards. RM writes the mmap offset (pLinearAddress) at 32 and the status at 40."
	^(NvStruct new: 56)
		u32At: 0 put: hClient; u32At: 4 put: hDevice; u32At: 8 put: hMemory;
		u64At: 16 put: offset; u64At: 24 put: length; u32At: 44 put: flags; u32At: 48 put: fd; yourself
!
unmapMemoryClient: hClient device: hDevice memory: hMemory address: linearAddress
	"NVOS34_PARAMETERS (NV_ESC_RM_UNMAP_MEMORY), 32 bytes; status at 24."
	^(NvStruct new: 32)
		u32At: 0 put: hClient; u32At: 4 put: hDevice; u32At: 8 put: hMemory; u64At: 16 put: linearAddress; yourself
!
mapDmaClient: hClient device: hDevice dma: hDma memory: hMemory length: length flags: flags
	"NVOS46_PARAMETERS (NV_ESC_RM_MAP_MEMORY_DMA), 64 bytes; RM writes the GPU address (dmaOffset) at 48, the status
	at 56."
	^(NvStruct new: 64)
		u32At: 0 put: hClient; u32At: 4 put: hDevice; u32At: 8 put: hDma; u32At: 12 put: hMemory;
		u64At: 24 put: length; u32At: 32 put: flags; yourself
!
unmapDmaClient: hClient device: hDevice dma: hDma memory: hMemory gpuAddress: dmaOffset
	"NVOS47_PARAMETERS (NV_ESC_RM_UNMAP_MEMORY_DMA), 48 bytes; status at 40."
	^(NvStruct new: 48)
		u32At: 0 put: hClient; u32At: 4 put: hDevice; u32At: 8 put: hDma; u32At: 12 put: hMemory;
		u64At: 24 put: dmaOffset; yourself
!
registerFd: ctlFd
	"nv_ioctl_register_fd_t (NV_ESC_REGISTER_FD on /dev/nvidiaN), 4 bytes."
	^(NvStruct new: 4) u32At: 0 put: ctlFd; yourself
!
cardInfoSize
	"nv_ioctl_card_info_t: valid at 0 (byte), gpu_id at 16, minor_number at 56; NV_ESC_CARD_INFO fills an array."
	^72
! !

!NvRm class methodsFor: 'alloc parameters'!
deviceParams: deviceId client: hClient
	"NV0080_ALLOC_PARAMETERS, 56 bytes; vaMode 0 (optional multiple VA spaces)."
	^(NvStruct new: 56) u32At: 0 put: deviceId; u32At: 4 put: hClient; yourself
!
subdeviceParams: subDeviceId
	"NV2080_ALLOC_PARAMETERS, 4 bytes."
	^(NvStruct new: 4) u32At: 0 put: subDeviceId; yourself
!
vaSpaceParams: flags
	"NV_VASPACE_ALLOCATION_PARAMETERS, 56 bytes: RM''s default range, RM manages the page tables."
	^(NvStruct new: 56) u32At: 4 put: flags; yourself
!
memoryVirtualParams: limit vaSpace: hVASpace
	"NV_MEMORY_VIRTUAL_ALLOCATION_PARAMS, 24 bytes."
	^(NvStruct new: 24) u64At: 8 put: limit; u32At: 16 put: hVASpace; yourself
!
memoryParams: size owner: hOwner type: type alignment: alignment
	"NV_MEMORY_ALLOCATION_PARAMS for NV01_MEMORY_SYSTEM, 128 bytes: size bytes of noncontiguous system memory the GPU
	does not cache. RM writes the size it allocated at 64."
	^(NvStruct new: 128)
		u32At: 0 put: hOwner; u32At: 4 put: type; u32At: 8 put: self memoryAllocFlags;
		u32At: 24 put: self memoryAttrNoncontiguousPci; u32At: 28 put: self memoryAttr2Uncached; u32At: 32 put: 6;
		u64At: 64 put: size; u64At: 72 put: alignment; u64At: 88 put: size - 1; yourself
!
channelGroupParams: engineType
	"NV_CHANNEL_GROUP_ALLOCATION_PARAMETERS, 20 bytes (engine 1: graphics, which runs compute)."
	^(NvStruct new: 20) u32At: 12 put: engineType; yourself
!
contextShareParams: hVASpace
	"NV_CTXSHARE_ALLOCATION_PARAMETERS, 12 bytes; subcontext async."
	^(NvStruct new: 12) u32At: 0 put: hVASpace; u32At: 4 put: 1; yourself
!
gpfifoParams: entries ringAddress: gpuAddress ringMemory: hBuffer userdMemory: hUserd userdOffset: userdOffset errorNotifier: hError contextShare: hContextShare
	"NV_CHANNELGPFIFO_ALLOCATION_PARAMETERS, 368 bytes: the ring of entries 8-byte GPFIFO entries at gpuAddress (in
	the memory hBuffer), the channel''s USERD at userdOffset in hUserd, errors noted in hError."
	^(NvStruct new: 368)
		u32At: 0 put: hError; u32At: 4 put: hBuffer; u64At: 8 put: gpuAddress; u32At: 16 put: entries;
		u32At: 24 put: hContextShare; u32At: 32 put: hUserd; u64At: 64 put: userdOffset; yourself
! !

!NvRm class methodsFor: 'control parameters'!
buildVersionParams
	"NV0000_CTRL_SYSTEM_GET_BUILD_VERSION_V2_PARAMS, 1032 bytes: driverVersionBuffer (a C string) at 0."
	^NvStruct new: 1032
!
idInfoParams: gpuId
	"NV0000_CTRL_GPU_GET_ID_INFO_V2_PARAMS, 32 bytes: deviceInstance comes back at 8."
	^(NvStruct new: 32) u32At: 0 put: gpuId; yourself
!
classListParams: count list: address
	"NV0080_CTRL_GPU_GET_CLASSLIST_PARAMS, 16 bytes: with count 0 RM answers the count at 0, else fills count u32s at address."
	^(NvStruct new: 16) u32At: 0 put: count; u64At: 8 put: address; yourself
!
grInfoParams: count list: address
	"NV2080_CTRL_GR_GET_INFO_PARAMS, 32 bytes: a list of count (index, data) u32 pairs at address."
	^(NvStruct new: 32) u32At: 0 put: count; u64At: 8 put: address; yourself
!
scheduleParams: enable
	"NVA06C_CTRL_GPFIFO_SCHEDULE_PARAMS, 3 bytes."
	^(NvStruct new: 3) u8At: 0 put: (enable ifTrue: [1] ifFalse: [0]); yourself
!
workSubmitTokenParams
	"NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN_PARAMS, 4 bytes: the token comes back at 0."
	^(NvStruct new: 4) u32At: 0 put: -1; yourself
! !
