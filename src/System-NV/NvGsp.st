Object subclass: #NvGsp
	instanceVariableNames: ''
	classVariableNames: 'Layouts'
	package: 'System-NV'!

NvGsp comment: 'I hold what booting and driving GSP-RM on the GB10 takes in memory (docs/nv-gsp.md, sections 2 and 3), as driver 580.178.04 lays it out: the C declarations of the boot and RPC structures (layouts: NvLayouts by their C names), their constants, and builders that fill them the way nvidia.ko does: the SEC2 chain-of-trust message (cotPayload..., sec2Message:), the GSP-FMC boot parameters, GspFwWprMeta, the LIBOS init arguments, GSP_ARGUMENTS_CACHED, the radix-3 page tables of the GSP-RM image, and the RPC messages (rpc headers, GSP_RM_ALLOC, GSP_RM_CONTROL, FREE) with the message-queue checksum. NvGspQueues puts the messages in the queues, NvGspTransport makes NvDevice''s RM calls of them.

The declarations are mine, from reading the headers; NvGspLayoutTest compares every size, offset and constant with what the C compiler says from the headers themselves (NvGspLayouts, tools/nv-gsp-layouts.sh).

	(NvGsp struct: ''GspFwWprMeta'') size		"256"
	NvGsp radix3Counts: 74985472				"#(1 1 36 18307)"'!

!NvGsp class methodsFor: 'declarations'!
declarations
	"C name -> {packed. declaration} (NvLayout), from the 580.178.04 headers named in each."
	| rpcHeader |
	rpcHeader := #(('header_version' #u32) ('signature' #u32) ('length' #u32) ('function' #u32) ('rpc_result' #u32) ('rpc_result_private' #u32) ('sequence' #u32)
		('u' (#union ('spare' #u32) ('cpuRmGfid' #u32))) ('rpc_message_data' (#array #u8 0))).
	^Dictionary new
		"src/nvidia/inc/kernel/gpu/fsp/kern_fsp_cot_payload.h 36-55 (pragma pack 1)"
		at: 'NVDM_PAYLOAD_COT' put: {true. #(('version' #u16) ('size' #u16) ('gspFmcSysmemOffset' #u64) ('frtsSysmemOffset' #u64) ('frtsSysmemSize' #u32)
			('frtsVidmemOffset' #u64) ('frtsVidmemSize' #u32) ('hash384' (#array #u32 12)) ('publicKey' (#array #u32 96)) ('signature' (#array #u32 96)) ('gspBootArgsSysmemOffset' #u64))};
		"src/nvidia/arch/nvalloc/common/inc/gsp/gspifpub.h 43-90"
		at: 'GSP_FMC_BOOT_PARAMS' put: {false. #(('initParams' (#struct (('regkeys' #u32))))
			('bootGspRmParams' (#struct (('target' #enum) ('gspRmDescSize' #u32) ('gspRmDescOffset' #u64) ('wprCarveoutOffset' #u64) ('wprCarveoutSize' #u32) ('bIsGspRmBoot' #bool))))
			('gspRmParams' (#struct (('target' #enum) ('bootArgsOffset' #u64))))
			('gspSpdmParams' (#struct (('target' #enum) ('payloadBufferOffset' #u64) ('payloadBufferSize' #u32))))
			('gspRmMemParams' (#struct (('flushSysmemAddrValLo' #u32) ('flushSysmemAddrValHi' #u32)))))};
		"src/nvidia/arch/nvalloc/common/inc/gsp/gsp_fw_wpr_meta.h 60-208"
		at: 'GspFwWprMeta' put: {false. #(('magic' #u64) ('revision' #u64) ('sysmemAddrOfRadix3Elf' #u64) ('sizeOfRadix3Elf' #u64) ('sysmemAddrOfBootloader' #u64) ('sizeOfBootloader' #u64)
			('bootloaderCodeOffset' #u64) ('bootloaderDataOffset' #u64) ('bootloaderManifestOffset' #u64)
			(nil (#union (nil (#struct (('sysmemAddrOfSignature' #u64) ('sizeOfSignature' #u64)))) (nil (#struct (('gspFwHeapFreeListWprOffset' #u32) ('unused0' #u32) ('unused1' #u64))))))
			('gspFwRsvdStart' #u64) ('nonWprHeapOffset' #u64) ('nonWprHeapSize' #u64) ('gspFwWprStart' #u64) ('gspFwHeapOffset' #u64) ('gspFwHeapSize' #u64) ('gspFwOffset' #u64)
			('bootBinOffset' #u64) ('frtsOffset' #u64) ('frtsSize' #u64) ('gspFwWprEnd' #u64) ('fbSize' #u64) ('vgaWorkspaceOffset' #u64) ('vgaWorkspaceSize' #u64) ('bootCount' #u64)
			(nil (#union
				(nil (#struct (('partitionRpcAddr' #u64) ('partitionRpcRequestOffset' #u16) ('partitionRpcReplyOffset' #u16) ('elfCodeOffset' #u32) ('elfDataOffset' #u32) ('elfCodeSize' #u32) ('elfDataSize' #u32) ('lsUcodeVersion' #u32))))
				(nil (#struct (('partitionRpcPadding' (#array #u32 4)) ('sysmemAddrOfCrashReportQueue' #u64) ('sizeOfCrashReportQueue' #u32) ('lsUcodeVersionPadding' (#array #u32 1)))))))
			('gspFwHeapVfPartitionCount' #u8) ('flags' #u8) ('padding' (#array #u8 2)) ('pmuReservedSize' #u32) ('verified' #u64))};
		"src/common/uproc/os/common/include/libos_init_args.h 49-56"
		at: 'LibosMemoryRegionInitArgument' put: {false. #(('id8' #u64) ('pa' #u64) ('size' #u64) ('kind' #u8) ('loc' #u8))};
		"src/nvidia/inc/kernel/gpu/gsp/gsp_init_args.h 29-64 (NvLength is 64 bits)"
		at: 'GSP_ARGUMENTS_CACHED' put: {false. #(('messageQueueInitArguments' (#struct (('sharedMemPhysAddr' #u64) ('pageTableEntryCount' #u32) ('cmdQueueOffset' #u64) ('statQueueOffset' #u64))))
			('srInitArguments' (#struct (('oldLevel' #u32) ('flags' #u32) ('bInPMTransition' #bool))))
			('gpuInstance' #u32) ('bDmemStack' #bool) ('profilerArgs' (#struct (('pa' #u64) ('size' #u64)))) ('sysmemHeapArgs' (#struct (('pa' #u64) ('size' #u64)))))};
		"src/nvidia/arch/nvalloc/common/inc/rmRiscvUcode.h 36-58"
		at: 'RM_RISCV_UCODE_DESC' put: {false. #(('version' #u32) ('bootloaderOffset' #u32) ('bootloaderSize' #u32) ('bootloaderParamOffset' #u32) ('bootloaderParamSize' #u32)
			('riscvElfOffset' #u32) ('riscvElfSize' #u32) ('appVersion' #u32) ('manifestOffset' #u32) ('manifestSize' #u32) ('monitorDataOffset' #u32) ('monitorDataSize' #u32)
			('monitorCodeOffset' #u32) ('monitorCodeSize' #u32) ('bIsMonitorEnabled' #u32) ('swbromCodeOffset' #u32) ('swbromCodeSize' #u32) ('swbromDataOffset' #u32) ('swbromDataSize' #u32)
			('fbReservedSize' #u32) ('bSignedAsCode' #u32))};
		"src/common/shared/msgq/inc/msgq/msgq_priv.h 40-56"
		at: 'msgqTxHeader' put: {false. #(('version' #u32) ('size' #u32) ('msgSize' #u32) ('msgCount' #u32) ('writePtr' #u32) ('flags' #u32) ('rxHdrOff' #u32) ('entryOff' #u32))};
		at: 'msgqRxHeader' put: {false. #(('readPtr' #u32))};
		"src/nvidia/inc/kernel/gpu/gsp/message_queue_priv.h 38-46"
		at: 'GSP_MSG_QUEUE_ELEMENT' put: {false. {#('authTagBuffer' (#array #u8 16)). #('aadBuffer' (#array #u8 16)). #('checkSum' #u32). #('seqNum' #u32). #('elemCount' #u32).
			{'rpc'. {#aligned. 8. {#struct. rpcHeader}}}}};
		"src/nvidia/generated/g_rpc-message-header.h 37-49"
		at: 'rpc_message_header_v03_00' put: {false. rpcHeader};
		"src/nvidia/generated/g_rpc-structures.h 1489-1518, 159-162; g_sdk-structures.h 259-265"
		at: 'rpc_gsp_rm_alloc_v03_00' put: {false. #(('hClient' #handle) ('hParent' #handle) ('hObject' #handle) ('hClass' #u32) ('status' #u32) ('paramsSize' #u32) ('flags' #u32) ('reserved' (#array #u8 4)) ('params' (#array #u8 0)))};
		at: 'rpc_gsp_rm_control_v03_00' put: {false. #(('hClient' #handle) ('hObject' #handle) ('cmd' #u32) ('status' #u32) ('paramsSize' #u32) ('rmapiRpcFlags' #u32) ('rmctrlFlags' #u32) ('rmctrlAccessRight' #u32)
			('reserved0' (#aligned 8 #u64)) ('params' (#array #u8 0)))};
		at: 'rpc_free_v03_00' put: {false. #(('params' (#struct (('hRoot' #handle) ('hObjectParent' #handle) ('hObjectOld' #handle) ('status' #u32)))))};
		"src/nvidia/inc/kernel/gpu/gsp/gsp_static_config.h 172-227; BUSINFO and ACPI_METHOD_DATA (chipset.h, gpu_acpi_data.h) are left zero, as opaque bytes"
		at: 'GspSystemInfo' put: {false. #(('gpuPhysAddr' #u64) ('gpuPhysFbAddr' #u64) ('gpuPhysInstAddr' #u64) ('gpuPhysIoAddr' #u64) ('nvDomainBusDeviceFunc' #u64)
			('simAccessBufPhysAddr' #u64) ('notifyOpSharedSurfacePhysAddr' #u64) ('pcieAtomicsOpMask' #u64) ('consoleMemSize' #u64) ('maxUserVa' #u64)
			('pciConfigMirrorBase' #u32) ('pciConfigMirrorSize' #u32) ('PCIDeviceID' #u32) ('PCISubDeviceID' #u32) ('PCIRevisionID' #u32) ('pcieAtomicsCplDeviceCapMask' #u32)
			('oorArch' #u8) ('clPdbProperties' #u64) ('Chipset' #u32) ('bGpuBehindBridge' #bool) ('bFlrSupported' #bool) ('b64bBar0Supported' #bool) ('bMnocAvailable' #bool)
			('chipsetL1ssEnable' #u32) ('bUpstreamL0sUnsupported' #bool) ('bUpstreamL1Unsupported' #bool) ('bUpstreamL1PorSupported' #bool) ('bUpstreamL1PorMobileOnly' #bool)
			('bSystemHasMux' #bool) ('upstreamAddressValid' #u8) ('FHBBusInfo' (#aligned 2 (#array #u8 10))) ('chipsetIDInfo' (#aligned 2 (#array #u8 10)))
			('acpiMethodData' (#aligned 4 (#array #u8 676))) ('hypervisorType' #u32) ('virtualConfigBits' #u16) ('bIsPassthru' #bool) ('sysTimerOffsetNs' #u64)
			('gspVFInfo' (#struct (('totalVFs' #u32) ('firstVFOffset' #u32) ('FirstVFBar0Address' #u64) ('FirstVFBar1Address' #u64) ('FirstVFBar2Address' #u64) ('b64bitBar0' #bool) ('b64bitBar1' #bool) ('b64bitBar2' #bool))))
			('bIsPrimary' #bool) ('bIsUnixHdmiFrlComplianceEnabled' #bool) ('isGridBuild' #bool) ('pcieConfigReg' (#struct (('linkCap' #u32)))) ('gridBuildCsp' #u32)
			('bPreserveVideoMemoryAllocations' #bool) ('bTdrEventSupported' #bool) ('bFeatureStretchVblankCapable' #bool) ('bEnableDynamicGranularityPageArrays' #bool)
			('bClockBoostSupported' #bool) ('hostPageSize' #u64) ('bIsCmcBasedHws' #bool) ('bGspNocatEnabled' #bool) ('bS0ixSupport' #bool) ('bWindowChannelAlwaysMapped' #bool))};
		"src/nvidia/generated/g_os_nvoc.h 225-239"
		at: 'PACKED_REGISTRY_ENTRY' put: {false. #(('nameOffset' #u32) ('type' #u8) ('data' #u32) ('length' #u32))};
		at: 'PACKED_REGISTRY_TABLE' put: {false. #(('size' #u32) ('numEntries' #u32) ('entries' (#array (#struct (('nameOffset' #u32) ('type' #u8) ('data' #u32) ('length' #u32))) 0)))};
		"src/nvidia/generated/g_rpc-structures.h 1535-1541"
		at: 'rpc_run_cpu_sequencer_v17_00' put: {false. #(('bufferSizeDWord' #u32) ('cmdIndex' #u32) ('regSaveArea' (#array #u32 8)) ('commandBuffer' (#array #u32 0)))};
		"src/common/sdk/nvidia/inc/class/cl0000.h 47-52 (NV_PROC_NAME_MAX_LENGTH 100; NvP64 aligned 8)"
		at: 'NV0000_ALLOC_PARAMETERS' put: {false. #(('hClient' #handle) ('processID' #u32) ('processName' (#array #u8 100)) ('pOsPidInfo' (#aligned 8 #u64)))};
		yourself
!
layouts
	"C name -> NvLayout."
	Layouts isNil ifTrue: [
		Layouts := Dictionary new.
		self declarations keysAndValuesDo: [:k :v | Layouts at: k put: (NvLayout named: k declaration: v last packed: v first)]].
	^Layouts
!
layout: aName
	^self layouts at: aName ifAbsent: [self error: 'no GSP structure ', aName]
!
struct: aName
	"A zeroed struct of the C type aName (an NvGspStruct)."
	^NvGspStruct layout: (self layout: aName)
! !

!NvGsp class methodsFor: 'constants'!
constants
	"The header constants I use, by their C names (NvGspLayoutTest checks them)."
	^Dictionary new
		at: 'NV_VGPU_MSG_SIGNATURE_VALID' put: 16r43505256;
		at: 'NV_VGPU_MSG_HEADER_VERSION_MAJOR_TOT' put: 3;
		at: 'NV_VGPU_MSG_HEADER_VERSION_MINOR_TOT' put: 0;
		at: 'NV_VGPU_MSG_RESULT_RPC_PENDING' put: 16rFFFFFFFF;
		at: 'NV_VGPU_MSG_UNION_INIT' put: 0;
		at: 'NV_VGPU_MSG_FUNCTION_NOP' put: 0;
		at: 'NV_VGPU_MSG_FUNCTION_SET_GUEST_SYSTEM_INFO' put: 1;
		at: 'NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY' put: 4;
		at: 'NV_VGPU_MSG_FUNCTION_FREE' put: 10;
		at: 'NV_VGPU_MSG_FUNCTION_MAP_MEMORY_DMA' put: 14;
		at: 'NV_VGPU_MSG_FUNCTION_GET_GSP_STATIC_INFO' put: 65;
		at: 'NV_VGPU_MSG_FUNCTION_CONTINUATION_RECORD' put: 71;
		at: 'NV_VGPU_MSG_FUNCTION_GSP_SET_SYSTEM_INFO' put: 72;
		at: 'NV_VGPU_MSG_FUNCTION_SET_REGISTRY' put: 73;
		at: 'NV_VGPU_MSG_FUNCTION_GSP_RM_CONTROL' put: 76;
		at: 'NV_VGPU_MSG_FUNCTION_GSP_RM_ALLOC' put: 103;
		at: 'NV_VGPU_MSG_EVENT_GSP_INIT_DONE' put: 16r1001;
		at: 'NV_VGPU_MSG_EVENT_GSP_RUN_CPU_SEQUENCER' put: 16r1002;
		at: 'NV_VGPU_MSG_EVENT_POST_EVENT' put: 16r1003;
		at: 'NV_VGPU_MSG_EVENT_RC_TRIGGERED' put: 16r1004;
		at: 'NV_VGPU_MSG_EVENT_OS_ERROR_LOG' put: 16r1006;
		at: 'NV_VGPU_MSG_EVENT_UCODE_LIBOS_PRINT' put: 16r100C;
		at: 'NV_VGPU_MSG_EVENT_GSP_LOCKDOWN_NOTICE' put: 16r101C;
		at: 'MSGQ_VERSION' put: 0;
		at: 'MSGQ_FLAGS_SWAP_RX' put: 1;
		at: 'GSP_MSG_QUEUE_ELEMENT_SIZE_MIN' put: 4096;
		at: 'GSP_MSG_QUEUE_ELEMENT_SIZE_MAX' put: 65536;
		at: 'GSP_FW_WPR_META_MAGIC' put: 16rDC3AAE21371A60B3;
		at: 'GSP_FW_WPR_META_REVISION' put: 1;
		at: 'GSP_DMA_TARGET_COHERENT_SYSTEM' put: 1;
		at: 'LIBOS_MEMORY_REGION_CONTIGUOUS' put: 1;
		at: 'LIBOS_MEMORY_REGION_RADIX3' put: 2;
		at: 'LIBOS_MEMORY_REGION_LOC_SYSMEM' put: 1;
		at: 'LIBOS_MEMORY_REGION_RADIX_PAGE_SIZE' put: 4096;
		at: 'NVDM_TYPE_COT' put: 16r14;
		at: 'MCTP_MSG_HEADER_TYPE_VENDOR_PCI' put: 16r7E;
		at: 'MCTP_MSG_HEADER_VENDOR_ID_NV' put: 16r10DE;
		at: 'GSP_SEQ_BUF_OPCODE_REG_WRITE' put: 0;
		at: 'GSP_SEQ_BUF_OPCODE_REG_MODIFY' put: 1;
		at: 'GSP_SEQ_BUF_OPCODE_REG_POLL' put: 2;
		at: 'GSP_SEQ_BUF_OPCODE_DELAY_US' put: 3;
		at: 'GSP_SEQ_BUF_OPCODE_REG_STORE' put: 4;
		at: 'GSP_SEQ_BUF_OPCODE_CORE_RESET' put: 5;
		at: 'GSP_SEQ_BUF_OPCODE_CORE_START' put: 6;
		at: 'GSP_SEQ_BUF_OPCODE_CORE_WAIT_FOR_HALT' put: 7;
		at: 'GSP_SEQ_BUF_OPCODE_CORE_RESUME' put: 8;
		at: 'GSP_SEQ_BUF_REG_SAVE_SIZE' put: 8;
		yourself
!
constant: aName
	^self constants at: aName
!
function: aSymbol
	"An RPC function or event number by its short name: #GSP_RM_ALLOC, #GSP_INIT_DONE, ..."
	^self constants at: 'NV_VGPU_MSG_FUNCTION_', aSymbol ifAbsent: [self constants at: 'NV_VGPU_MSG_EVENT_', aSymbol]
!
headerVersion
	"rpc_message_header_v03_00 header_version: major 31:24, minor 23:16 (rpc_headers.h 56-59)."
	^((self constant: 'NV_VGPU_MSG_HEADER_VERSION_MAJOR_TOT') bitShift: 24) bitOr: ((self constant: 'NV_VGPU_MSG_HEADER_VERSION_MINOR_TOT') bitShift: 16)
!
page
	^4096
!
cotPayloadVersion
	"GB10B's cotPayloadVersion (g_kernel_sec2_nvoc.c 481)."
	^1
!
sec2MctpHeader
	"The MCTP transport header word SEC2 gets on GB10B: ksec2CreateMctpHeader is _539ab4, a stub answering 1 (g_kernel_sec2_nvoc.h 853-855)."
	^1
!
nvdmHeader: nvdmType
	"The MCTP message header word: type vendor-PCI 6:0, vendor id 23:8, NVDM type 31:24 (sec2_mctp_format.h 46-53; ksec2CreateNvdmHeader_GB10B)."
	^((self constant: 'MCTP_MSG_HEADER_TYPE_VENDOR_PCI') bitOr: ((self constant: 'MCTP_MSG_HEADER_VENDOR_ID_NV') bitShift: 8)) bitOr: (nvdmType bitShift: 24)
! !

!NvGsp class methodsFor: 'chain of trust'!
cotPayloadFmc: fmcAddress size: fmcSize hash: hashBytes publicKey: keyBytes signature: signatureBytes bootArgs: fmcParamsAddress
	"NVDM_PAYLOAD_COT as ksec2PrepareBootCommands_GB10B and ksec2SetupGspImages_GB10B fill it (kernel_sec2_gb10b.c 484-532, 561-610): the FMC image's device address, frtsSysmemSize = the image's size, no vidmem, the archive's hash, key and signature, the FMC boot parameters' address."
	| p |
	p := self struct: 'NVDM_PAYLOAD_COT'.
	p at: 'version' put: self cotPayloadVersion;
		at: 'size' put: p size;
		at: 'gspFmcSysmemOffset' put: fmcAddress;
		at: 'frtsSysmemSize' put: fmcSize;
		at: 'hash384' put: hashBytes;
		at: 'publicKey' put: keyBytes;
		at: 'signature' put: signatureBytes;
		at: 'gspBootArgsSysmemOffset' put: fmcParamsAddress.
	^p
!
sec2Message: aPayload
	"The bytes to put in SEC2's EMEM channel: the MCTP header word, the NVDM header word (type COT), the payload, padded to whole words (ksec2SendMessage_IMPL, kernel_sec2.c 282-366)."
	| m |
	m := NvStruct new: 8 + (aPayload size + 3 // 4 * 4).
	m u32At: 0 put: self sec2MctpHeader; u32At: 4 put: (self nvdmHeader: (self constant: 'NVDM_TYPE_COT')); bytesAt: 8 put: aPayload bytes.
	^m
!
sec2QueueTail: aMessage
	"NV_PSEC_QUEUE_TAIL(0) for aMessage: its size, padded to 4, minus 4 (kernel_sec2_gb10b.c 699-733)."
	^(aMessage size + 3 // 4 * 4) - 4
!
fmcBootParamsWprMeta: wprMetaAddress libosArgs: libosArgsAddress
	"GSP_FMC_BOOT_PARAMS as kgspSetupGspFmcArgs_GH100 fills it for a cold boot (kernel_gsp_gh100.c 411-486): GspFwWprMeta for the FMC, the LIBOS init arguments for GSP-RM, both coherent system memory; no regkeys, SPDM or sysmem flush."
	| p |
	p := self struct: 'GSP_FMC_BOOT_PARAMS'.
	p at: 'bootGspRmParams.gspRmDescOffset' put: wprMetaAddress;
		at: 'bootGspRmParams.gspRmDescSize' put: (self layout: 'GspFwWprMeta') size;
		at: 'bootGspRmParams.target' put: (self constant: 'GSP_DMA_TARGET_COHERENT_SYSTEM');
		at: 'bootGspRmParams.bIsGspRmBoot' put: 1;
		at: 'gspRmParams.bootArgsOffset' put: libosArgsAddress;
		at: 'gspRmParams.target' put: (self constant: 'GSP_DMA_TARGET_COHERENT_SYSTEM').
	^p
!
wprMetaBootloader: bootAddress size: bootSize descriptor: aDesc radix3: radix3Address imageSize: imageSize signature: signatureAddress size: signatureSize heapSize: heapSize
	"GspFwWprMeta as kgspPopulateWprMeta_GH100 then _GB10B fill it (kernel_gsp_gh100.c 295-387, kernel_gsp_gb10b.c 61-89): the boot loader and its descriptor's offsets (aDesc an RM_RISCV_UCODE_DESC), the radix-3 image, the signature, the heap; no FRTS, VGA workspace, PMU reservation or non-WPR heap on GB10B; WPR offsets left to ACR."
	| m |
	m := self struct: 'GspFwWprMeta'.
	m at: 'magic' put: (self constant: 'GSP_FW_WPR_META_MAGIC');
		at: 'revision' put: (self constant: 'GSP_FW_WPR_META_REVISION');
		at: 'sizeOfBootloader' put: bootSize;
		at: 'sysmemAddrOfBootloader' put: bootAddress;
		at: 'sizeOfRadix3Elf' put: imageSize;
		at: 'sysmemAddrOfRadix3Elf' put: radix3Address;
		at: 'bootloaderCodeOffset' put: (aDesc at: 'monitorCodeOffset');
		at: 'bootloaderDataOffset' put: (aDesc at: 'monitorDataOffset');
		at: 'bootloaderManifestOffset' put: (aDesc at: 'manifestOffset');
		at: 'sysmemAddrOfSignature' put: signatureAddress;
		at: 'sizeOfSignature' put: signatureSize;
		at: 'gspFwHeapSize' put: heapSize.
	^m
! !

!NvGsp class methodsFor: 'GSP-RM arguments'!
initArgId: aString
	"A LIBOS region's id8: up to 8 characters, the first in the most significant byte used (_kgspGenerateInitArgId, kernel_gsp.c 2657-2675)."
	^(aString first: (aString size min: 8)) inject: 0 into: [:id :c | (id bitShift: 8) bitOr: c value]
!
libosRegion: aName address: pa size: n
	"A LibosMemoryRegionInitArgument: contiguous, in system memory (kgspSetupLibosInitArgs_IMPL, kernel_gsp.c 5179-5219)."
	^(self struct: 'LibosMemoryRegionInitArgument')
		at: 'id8' put: (self initArgId: aName);
		at: 'pa' put: pa;
		at: 'size' put: n;
		at: 'kind' put: (self constant: 'LIBOS_MEMORY_REGION_CONTIGUOUS');
		at: 'loc' put: (self constant: 'LIBOS_MEMORY_REGION_LOC_SYSMEM');
		yourself
!
libosArguments: regions
	"The LIBOS init arguments page: the regions (LibosMemoryRegionInitArgument structs: the log buffers, then RMARGS), zeros after."
	| page |
	page := NvStruct new: self page.
	regions doWithIndex: [:r :i | page bytesAt: (i - 1) * r size put: r bytes].
	^page
!
logBuffers
	"The LIBOS log buffers of a release build on GB10B (LIBOS 3), {name. bytes}, in order (kernel_gsp.c 3152-3240): init, interrupt, RM, MNOC, debugger and root tasks, then the LIBOS kernel's (kgspHasLibosKernelLogging is true for GB10B); the names are the tasks' memory ids (nv-firmware-chip-family-select.h 107-113, 151)."
	^#(#('LOGINIT' 16r10000) #('LOGINTR' 16r10000) #('LOGRM' 16r10000) #('LOGMNOC' 16r10000) #('LOGDBG' 16r10000) #('LOGROOT' 16r1000) #('LOGKRNL' 16r10000))
!
arguments: sharedMemory pageTableEntries: count commandQueue: cmdOffset statusQueue: statOffset heap: heapAddress size: heapSize
	"GSP_ARGUMENTS_CACHED (kgspPopulateGspRmInitArgs_IMPL, kernel_gsp.c 4511-4575): the message queues' shared memory and, as the GB10 has no video memory, GSP-RM's heap in system memory."
	^(self struct: 'GSP_ARGUMENTS_CACHED')
		at: 'messageQueueInitArguments.sharedMemPhysAddr' put: sharedMemory;
		at: 'messageQueueInitArguments.pageTableEntryCount' put: count;
		at: 'messageQueueInitArguments.cmdQueueOffset' put: cmdOffset;
		at: 'messageQueueInitArguments.statQueueOffset' put: statOffset;
		at: 'sysmemHeapArgs.pa' put: heapAddress;
		at: 'sysmemHeapArgs.size' put: heapSize;
		yourself
!
sysmemHeapSize
	"RmGspSysmemHeapSizeMB's default, 512 MB (nvrm_registry.h 2356)."
	^512 * 1048576
! !

!NvGsp class methodsFor: 'init RPCs'!
systemInfoBar0: bar0Address domain: domain bus: bus devfn: devfn deviceVendor: deviceVendor subsystem: subsystem revision: revision
	"GspSystemInfo for GSP_SET_SYSTEM_INFO as rpcGspSetSystemInfo_v17_00 fills it (rpc.c 10493-10657) for a GB10 on bare metal: BAR0's address, the PCI location (gpuEncodeDomainBusDevice: domain 63:32, bus 15:8, device and function 7:0), the configuration space's id words as RM reads them (kern_gpu_gb100.c 950-967: device and vendor, subsystem, revision), the configuration space's mirror in BAR0 (NV_EP_PCFGM 16r92000-16r92FFF: kbifGetPciConfigSpacePriMirror_GH100, which GB10B uses; gh100 dev_xtl_ep_pri.h 26), FLR and a 64-bit BAR0, 4 KB host pages; no frame buffer, instance or I/O BAR, no hypervisor. Fields nvidia.ko takes from Linux (maxUserVa, the chipset's, ACPI's) are left zero here: see docs/nv-gsp.md 12."
	^(self struct: 'GspSystemInfo')
		at: 'gpuPhysAddr' put: bar0Address;
		at: 'nvDomainBusDeviceFunc' put: ((domain bitShift: 32) bitOr: ((bus bitShift: 8) bitOr: devfn));
		at: 'PCIDeviceID' put: deviceVendor;
		at: 'PCISubDeviceID' put: subsystem;
		at: 'PCIRevisionID' put: revision;
		at: 'pciConfigMirrorBase' put: 16r92000;
		at: 'pciConfigMirrorSize' put: 16r1000;
		at: 'bFlrSupported' put: 1;
		at: 'b64bBar0Supported' put: 1;
		at: 'hostPageSize' put: 4096;
		yourself
!
setSystemInfo: aGspSystemInfo
	"GSP_SET_SYSTEM_INFO (72): the header and GspSystemInfo, its length counting it; sent before the boot, no reply (kgspQueueAsyncInitRpcs)."
	^self rpc: (self function: #GSP_SET_SYSTEM_INFO) payload: aGspSystemInfo counted: 0 params: nil sequence: 0
!
registry: pairs
	"A PACKED_REGISTRY_TABLE of DWORD keys, {name. value} pairs, laid out as RmPackageRegistry does (registry.c 628-700): the header, the entries, then each name (NUL-terminated) at its nameOffset from the table's start; DWORD entries have type 1, data the value, length 4."
	| entrySize names table offset |
	entrySize := (self layout: 'PACKED_REGISTRY_ENTRY') size.
	names := pairs collect: [:p | p first asByteArray, #[0]].
	offset := 8 + (entrySize * pairs size).
	table := NvStruct new: offset + (names inject: 0 into: [:sum :n | sum + n size]).
	table u32At: 0 put: table size; u32At: 4 put: pairs size.
	pairs doWithIndex: [:p :i | | e |
		e := 8 + (entrySize * (i - 1)).
		table u32At: e put: offset; u8At: e + 4 put: 1; u32At: e + 8 put: p last; u32At: e + 12 put: 4.
		table bytesAt: offset put: (names at: i).
		offset := offset + (names at: i) size].
	^table
!
setRegistry: aTable
	"SET_REGISTRY (73): the header and the table, its length counting it (rpcSetRegistry: totalSize, rpc.c 10700-10730)."
	^self rpc: (self function: #SET_REGISTRY) payload: aTable counted: 0 params: nil sequence: 0
! !

!NvGsp class methodsFor: 'radix-3'!
radix3Counts: imageSize
	"The pages of each level of a LIBOS radix-3 description of imageSize bytes: {1. level 1. level 2. data} (kgspCreateRadix3_IMPL, kernel_gsp.c 4956-4969: 512 8-byte entries a page)."
	| counts |
	counts := Array new: 4.
	counts at: 4 put: imageSize + self page - 1 // self page.
	3 to: 1 by: -1 do: [:i | counts at: i put: (counts at: i + 1) - 1 // 512 + 1].
	(counts at: 1) = 1 ifFalse: [^self error: 'radix-3: ', imageSize printString, ' bytes are too many'].
	^counts
!
radix3Tables: imageSize pageAddress: aBlock
	"The table pages of a radix-3 allocation for imageSize bytes, laid out as kgspCreateRadix3_IMPL does (kernel_gsp.c 4963-5048): level 0, the level 1 pages, the level 2 pages, then the data, all in one allocation of whole pages; each table holds the device addresses (aBlock value: the page's index in the allocation) of the next level's pages, level 2 those of the data. WprMeta's sysmemAddrOfRadix3Elf is page 0's address."
	| counts first tables |
	counts := self radix3Counts: imageSize.
	first := Array new: 4.
	first at: 1 put: 0.
	2 to: 4 do: [:i | first at: i put: (first at: i - 1) + (counts at: i - 1)].
	tables := NvStruct new: (first at: 4) * self page.
	1 to: 3 do: [:level |
		0 to: (counts at: level + 1) - 1 do: [:k |
			tables u64At: ((first at: level) * self page) + (8 * k) put: (aBlock value: (first at: level + 1) + k)]].
	^tables
! !

!NvGsp class methodsFor: 'rpc'!
rpcFunction: function length: payloadLength sequence: sequence
	"An rpc_message_header_v03_00 as rpcWriteCommonHeader writes it (rpc_common.c 124-185): result and private result pending, length the header and payloadLength; sequence as rpcSendMessage numbers it."
	^(self struct: 'rpc_message_header_v03_00')
		at: 'header_version' put: self headerVersion;
		at: 'signature' put: (self constant: 'NV_VGPU_MSG_SIGNATURE_VALID');
		at: 'length' put: (self layout: 'rpc_message_header_v03_00') size + payloadLength;
		at: 'function' put: function;
		at: 'rpc_result' put: (self constant: 'NV_VGPU_MSG_RESULT_RPC_PENDING');
		at: 'rpc_result_private' put: (self constant: 'NV_VGPU_MSG_RESULT_RPC_PENDING');
		at: 'sequence' put: sequence;
		yourself
!
rpc: function payload: aStruct counted: counted params: aByteArrayOrNil sequence: sequence
	"An RPC message: the header, aStruct, then the parameters; the header's length counts aStruct and counted bytes of the parameters."
	| params m |
	params := aByteArrayOrNil ifNil: [ByteArray new].
	m := NvStruct new: 32 + aStruct size + params size.
	m bytesAt: 0 put: (self rpcFunction: function length: aStruct size + counted sequence: sequence) bytes.
	m bytesAt: 32 put: aStruct bytes.
	params isEmpty ifFalse: [m bytesAt: 32 + aStruct size put: params].
	^m
!
rmAllocClient: hClient parent: hParent object: hObject class: rmClass params: aByteArrayOrNil sequence: sequence
	"GSP_RM_ALLOC (103) as rpcRmApiAlloc_GSP builds it (rpc.c 11138-11230): the parameters follow rpc_gsp_rm_alloc_v03_00 but the header's length counts only the struct (rpcWriteCommonHeader with sizeof(rpc_gsp_rm_alloc_v03_00), 11197)."
	| p |
	p := (self struct: 'rpc_gsp_rm_alloc_v03_00')
		at: 'hClient' put: hClient; at: 'hParent' put: hParent; at: 'hObject' put: hObject; at: 'hClass' put: rmClass;
		at: 'paramsSize' put: (aByteArrayOrNil ifNil: [0] ifNotNil: [:b | b size]);
		yourself.
	^self rpc: (self function: #GSP_RM_ALLOC) payload: p counted: 0 params: aByteArrayOrNil sequence: sequence
!
rmControlClient: hClient object: hObject command: command params: aByteArrayOrNil sequence: sequence
	"GSP_RM_CONTROL (76) as rpcRmApiControl_GSP builds it (rpc.c 10978-10995): the length counts the parameters; no flags."
	| p n |
	n := aByteArrayOrNil ifNil: [0] ifNotNil: [:b | b size].
	p := (self struct: 'rpc_gsp_rm_control_v03_00')
		at: 'hClient' put: hClient; at: 'hObject' put: hObject; at: 'cmd' put: command; at: 'paramsSize' put: n;
		yourself.
	^self rpc: (self function: #GSP_RM_CONTROL) payload: p counted: n params: aByteArrayOrNil sequence: sequence
!
freeClient: hClient parent: hParent object: hObject sequence: sequence
	"FREE (10): rpc_free_v03_00, an NVOS00_PARAMETERS (rpc.c 3341)."
	| p |
	p := (self struct: 'rpc_free_v03_00')
		at: 'params.hRoot' put: hClient; at: 'params.hObjectParent' put: hParent; at: 'params.hObjectOld' put: hObject;
		yourself.
	^self rpc: (self function: #FREE) payload: p counted: 0 params: nil sequence: sequence
!
rootParamsClient: hClient
	"NV0000_ALLOC_PARAMETERS for a new root client (rpcRmApiAlloc_GSP sends it whole for NV01_ROOT, rpc.c 11176-11180)."
	^((self struct: 'NV0000_ALLOC_PARAMETERS') at: 'hClient' put: hClient; yourself) bytes
!
checksum: aByteArray
	"_checkSum32 (message_queue_priv.h 112-124): the XOR of the bytes as little-endian 64-bit words (the size a multiple of 8), its halves XORed."
	| lo hi |
	lo := 0.
	hi := 0.
	0 to: aByteArray size - 1 by: 8 do: [:i |
		lo := lo bitXor: (aByteArray uint32At: i + 1).
		hi := hi bitXor: (aByteArray uint32At: i + 5)].
	^lo bitXor: hi
! !
