#!/bin/sh
# Generates src/Tests-NV/NvGspLayouts.st: the layouts (size, and every field's offset and size) of the GSP boot and RPC
# structures and the constants NvGsp builds them with, as the C compiler sees them in NVIDIA's open-gpu-kernel-modules
# at the driver's version (docs/nv-gsp.md). NvGspLayoutTest compares NvGsp's own layouts with them, byte for byte.
#   tools/nv-gsp-layouts.sh [open-gpu-kernel-modules checkout] (default ~/src/github.com/NVIDIA/open-gpu-kernel-modules)
# The checkout must be at tag 580.178.04 (the Spark's driver). Needs cc. Regenerate only when the driver version moves.
set -eu
OGK=${1:-$HOME/src/github.com/NVIDIA/open-gpu-kernel-modules}
VERSION=580.178.04
OUT=$(cd "$(dirname "$0")/.." && pwd)/src/Tests-NV/NvGspLayouts.st
tag=$(git -C "$OGK" describe --tags --exact-match 2>/dev/null || echo none)
[ "$tag" = "$VERSION" ] || { echo "nv-gsp-layouts: $OGK is at $tag, not $VERSION" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# GSP_MSG_QUEUE_ELEMENT's header drags in RM's port library: compile the struct's own text, cut from the header.
awk '/^typedef struct GSP_MSG_QUEUE_ELEMENT/{p=1} p{print} p&&/^} GSP_MSG_QUEUE_ELEMENT;/{p=0} /^#define GSP_MSG_QUEUE_ELEMENT_SIZE_M(IN|AX)/{print}' \
    "$OGK/src/nvidia/inc/kernel/gpu/gsp/message_queue_priv.h" > "$T/element.h"
grep -q 'define GSP_MSG_QUEUE_ELEMENT_SIZE_MAX' "$T/element.h"
# The registry table's structs sit in a generated header of RM's OS layer: their text too.
awk '/^typedef struct PACKED_REGISTRY_ENTRY/{p=1} p{print} p&&/^} PACKED_REGISTRY_TABLE;/{exit}' \
    "$OGK/src/nvidia/generated/g_os_nvoc.h" > "$T/registry.h"
grep -q 'PACKED_REGISTRY_TABLE;' "$T/registry.h"
grep -q 'GSP_MSG_QUEUE_ELEMENT;' "$T/element.h"
cat > "$T/layouts.c" <<'EOF'
#include <stdio.h>
#include <stddef.h>
#include "nvport/nvport.h"
#include "gpu/gsp/gsp_static_config.h"
#include "nvtypes.h"
#include "nvmisc.h"
#include "gpu/fsp/kern_fsp_cot_payload.h"
#include "gsp/gspifpub.h"
#include "gsp/gsp_fw_wpr_meta.h"
#include "libos_init_args.h"
#include "rmRiscvUcode.h"
#include "msgq/msgq_priv.h"
#include "msgq/msgq.h"
#include "gpu/gsp/gsp_init_args.h"
#include "class/cl0000.h"
#include "sec2/sec2_mctp_format.h"
#include "sec2/sec2_nvdm_format.h"
#define RPC_MESSAGE_STRUCTURES
#define RPC_STRUCTURES
#define RPC_GENERIC_UNION
#define RPC_MESSAGE_GENERIC_UNION
#include "vgpu/rpc_headers.h"
#include "g_rpc-structures.h"
#include "g_rpc-message-header.h"
#include "element.h"
#include "registry.h"
#include "rmgspseq.h"
#include "alloc/alloc_channel.h"
#include "ctrl/ctrl0080/ctrl0080gpu.h"
#include "ctrl/ctrl0080/ctrl0080gr.h"
#include "ctrl/ctrl0080/ctrl0080dma.h"
#include "ctrl/ctrl2080/ctrl2080gr.h"
#include "class/cl84a0.h"
#include "class/clc361.h"
#include "published/hopper/gh100/dev_mmu.h"
#include "published/maxwell/gm107/dev_ram.h"
#include "published/blackwell/gb100/dev_vm.h"

#define S(t) printf("\t\t#('%s' %zu #(\n", #t, sizeof(t));
#define F(t, f) printf("\t\t\t#('%s' %zu %zu)\n", #f, offsetof(t, f), sizeof(((t *)0)->f));
#define A(t, f) printf("\t\t\t#('%s' %zu 0)\n", #f, offsetof(t, f)); /* a flexible array: offset only */
#define E printf("\t\t))\n");
#define C(n) printf("\t\t#('%s' %llu)\n", #n, (unsigned long long)(n));
/* a register field hi:lo (dev_*.h): its low and high bit */
#define B(n) printf("\t\t#('%s.low' %u)\n\t\t#('%s.high' %u)\n", #n, (unsigned)(0?n), #n, (unsigned)(1?n));

int main(void)
{
    printf("!NvGspLayouts class methodsFor: 'layouts'!\nlayouts\n\t\"{name. sizeof. {{field. offset. size}...}} (size 0: a flexible array).\"\n\t^#(\n");
    S(NVDM_PAYLOAD_COT) F(NVDM_PAYLOAD_COT, version) F(NVDM_PAYLOAD_COT, size) F(NVDM_PAYLOAD_COT, gspFmcSysmemOffset)
        F(NVDM_PAYLOAD_COT, frtsSysmemOffset) F(NVDM_PAYLOAD_COT, frtsSysmemSize) F(NVDM_PAYLOAD_COT, frtsVidmemOffset)
        F(NVDM_PAYLOAD_COT, frtsVidmemSize) F(NVDM_PAYLOAD_COT, hash384) F(NVDM_PAYLOAD_COT, publicKey)
        F(NVDM_PAYLOAD_COT, signature) F(NVDM_PAYLOAD_COT, gspBootArgsSysmemOffset) E
    S(GSP_FMC_BOOT_PARAMS) F(GSP_FMC_BOOT_PARAMS, initParams.regkeys)
        F(GSP_FMC_BOOT_PARAMS, bootGspRmParams.target) F(GSP_FMC_BOOT_PARAMS, bootGspRmParams.gspRmDescSize)
        F(GSP_FMC_BOOT_PARAMS, bootGspRmParams.gspRmDescOffset) F(GSP_FMC_BOOT_PARAMS, bootGspRmParams.wprCarveoutOffset)
        F(GSP_FMC_BOOT_PARAMS, bootGspRmParams.wprCarveoutSize) F(GSP_FMC_BOOT_PARAMS, bootGspRmParams.bIsGspRmBoot)
        F(GSP_FMC_BOOT_PARAMS, gspRmParams.target) F(GSP_FMC_BOOT_PARAMS, gspRmParams.bootArgsOffset)
        F(GSP_FMC_BOOT_PARAMS, gspSpdmParams.target) F(GSP_FMC_BOOT_PARAMS, gspSpdmParams.payloadBufferOffset)
        F(GSP_FMC_BOOT_PARAMS, gspSpdmParams.payloadBufferSize) F(GSP_FMC_BOOT_PARAMS, gspRmMemParams.flushSysmemAddrValLo)
        F(GSP_FMC_BOOT_PARAMS, gspRmMemParams.flushSysmemAddrValHi) E
    S(GspFwWprMeta) F(GspFwWprMeta, magic) F(GspFwWprMeta, revision) F(GspFwWprMeta, sysmemAddrOfRadix3Elf)
        F(GspFwWprMeta, sizeOfRadix3Elf) F(GspFwWprMeta, sysmemAddrOfBootloader) F(GspFwWprMeta, sizeOfBootloader)
        F(GspFwWprMeta, bootloaderCodeOffset) F(GspFwWprMeta, bootloaderDataOffset) F(GspFwWprMeta, bootloaderManifestOffset)
        F(GspFwWprMeta, sysmemAddrOfSignature) F(GspFwWprMeta, sizeOfSignature) F(GspFwWprMeta, gspFwRsvdStart)
        F(GspFwWprMeta, nonWprHeapOffset) F(GspFwWprMeta, nonWprHeapSize) F(GspFwWprMeta, gspFwWprStart)
        F(GspFwWprMeta, gspFwHeapOffset) F(GspFwWprMeta, gspFwHeapSize) F(GspFwWprMeta, gspFwOffset)
        F(GspFwWprMeta, bootBinOffset) F(GspFwWprMeta, frtsOffset) F(GspFwWprMeta, frtsSize) F(GspFwWprMeta, gspFwWprEnd)
        F(GspFwWprMeta, fbSize) F(GspFwWprMeta, vgaWorkspaceOffset) F(GspFwWprMeta, vgaWorkspaceSize) F(GspFwWprMeta, bootCount)
        F(GspFwWprMeta, sysmemAddrOfCrashReportQueue) F(GspFwWprMeta, sizeOfCrashReportQueue)
        F(GspFwWprMeta, gspFwHeapVfPartitionCount) F(GspFwWprMeta, flags) F(GspFwWprMeta, pmuReservedSize)
        F(GspFwWprMeta, verified) E
    S(LibosMemoryRegionInitArgument) F(LibosMemoryRegionInitArgument, id8) F(LibosMemoryRegionInitArgument, pa)
        F(LibosMemoryRegionInitArgument, size) F(LibosMemoryRegionInitArgument, kind) F(LibosMemoryRegionInitArgument, loc) E
    S(GSP_ARGUMENTS_CACHED) F(GSP_ARGUMENTS_CACHED, messageQueueInitArguments.sharedMemPhysAddr)
        F(GSP_ARGUMENTS_CACHED, messageQueueInitArguments.pageTableEntryCount)
        F(GSP_ARGUMENTS_CACHED, messageQueueInitArguments.cmdQueueOffset)
        F(GSP_ARGUMENTS_CACHED, messageQueueInitArguments.statQueueOffset) F(GSP_ARGUMENTS_CACHED, srInitArguments.oldLevel)
        F(GSP_ARGUMENTS_CACHED, srInitArguments.flags) F(GSP_ARGUMENTS_CACHED, srInitArguments.bInPMTransition)
        F(GSP_ARGUMENTS_CACHED, gpuInstance) F(GSP_ARGUMENTS_CACHED, bDmemStack) F(GSP_ARGUMENTS_CACHED, profilerArgs.pa)
        F(GSP_ARGUMENTS_CACHED, profilerArgs.size) F(GSP_ARGUMENTS_CACHED, sysmemHeapArgs.pa)
        F(GSP_ARGUMENTS_CACHED, sysmemHeapArgs.size) E
    S(RM_RISCV_UCODE_DESC) F(RM_RISCV_UCODE_DESC, version) F(RM_RISCV_UCODE_DESC, bootloaderOffset)
        F(RM_RISCV_UCODE_DESC, bootloaderSize) F(RM_RISCV_UCODE_DESC, bootloaderParamOffset)
        F(RM_RISCV_UCODE_DESC, bootloaderParamSize) F(RM_RISCV_UCODE_DESC, riscvElfOffset) F(RM_RISCV_UCODE_DESC, riscvElfSize)
        F(RM_RISCV_UCODE_DESC, appVersion) F(RM_RISCV_UCODE_DESC, manifestOffset) F(RM_RISCV_UCODE_DESC, manifestSize)
        F(RM_RISCV_UCODE_DESC, monitorDataOffset) F(RM_RISCV_UCODE_DESC, monitorDataSize)
        F(RM_RISCV_UCODE_DESC, monitorCodeOffset) F(RM_RISCV_UCODE_DESC, monitorCodeSize)
        F(RM_RISCV_UCODE_DESC, bIsMonitorEnabled) F(RM_RISCV_UCODE_DESC, swbromCodeOffset)
        F(RM_RISCV_UCODE_DESC, swbromCodeSize) F(RM_RISCV_UCODE_DESC, swbromDataOffset) F(RM_RISCV_UCODE_DESC, swbromDataSize)
        F(RM_RISCV_UCODE_DESC, fbReservedSize) F(RM_RISCV_UCODE_DESC, bSignedAsCode) E
    S(msgqTxHeader) F(msgqTxHeader, version) F(msgqTxHeader, size) F(msgqTxHeader, msgSize) F(msgqTxHeader, msgCount)
        F(msgqTxHeader, writePtr) F(msgqTxHeader, flags) F(msgqTxHeader, rxHdrOff) F(msgqTxHeader, entryOff) E
    S(msgqRxHeader) F(msgqRxHeader, readPtr) E
    S(GSP_MSG_QUEUE_ELEMENT) F(GSP_MSG_QUEUE_ELEMENT, authTagBuffer) F(GSP_MSG_QUEUE_ELEMENT, aadBuffer)
        F(GSP_MSG_QUEUE_ELEMENT, checkSum) F(GSP_MSG_QUEUE_ELEMENT, seqNum) F(GSP_MSG_QUEUE_ELEMENT, elemCount)
        F(GSP_MSG_QUEUE_ELEMENT, rpc) E
    S(rpc_message_header_v03_00) F(rpc_message_header_v03_00, header_version) F(rpc_message_header_v03_00, signature)
        F(rpc_message_header_v03_00, length) F(rpc_message_header_v03_00, function) F(rpc_message_header_v03_00, rpc_result)
        F(rpc_message_header_v03_00, rpc_result_private) F(rpc_message_header_v03_00, sequence)
        F(rpc_message_header_v03_00, u) A(rpc_message_header_v03_00, rpc_message_data) E
    S(rpc_gsp_rm_alloc_v03_00) F(rpc_gsp_rm_alloc_v03_00, hClient) F(rpc_gsp_rm_alloc_v03_00, hParent)
        F(rpc_gsp_rm_alloc_v03_00, hObject) F(rpc_gsp_rm_alloc_v03_00, hClass) F(rpc_gsp_rm_alloc_v03_00, status)
        F(rpc_gsp_rm_alloc_v03_00, paramsSize) F(rpc_gsp_rm_alloc_v03_00, flags) F(rpc_gsp_rm_alloc_v03_00, reserved)
        A(rpc_gsp_rm_alloc_v03_00, params) E
    S(rpc_gsp_rm_control_v03_00) F(rpc_gsp_rm_control_v03_00, hClient) F(rpc_gsp_rm_control_v03_00, hObject)
        F(rpc_gsp_rm_control_v03_00, cmd) F(rpc_gsp_rm_control_v03_00, status) F(rpc_gsp_rm_control_v03_00, paramsSize)
        F(rpc_gsp_rm_control_v03_00, rmapiRpcFlags) F(rpc_gsp_rm_control_v03_00, rmctrlFlags)
        F(rpc_gsp_rm_control_v03_00, rmctrlAccessRight) F(rpc_gsp_rm_control_v03_00, reserved0)
        A(rpc_gsp_rm_control_v03_00, params) E
    S(rpc_free_v03_00) F(rpc_free_v03_00, params.hRoot) F(rpc_free_v03_00, params.hObjectParent)
        F(rpc_free_v03_00, params.hObjectOld) F(rpc_free_v03_00, params.status) E
    S(NV0000_ALLOC_PARAMETERS) F(NV0000_ALLOC_PARAMETERS, hClient) F(NV0000_ALLOC_PARAMETERS, processID)
        F(NV0000_ALLOC_PARAMETERS, processName) F(NV0000_ALLOC_PARAMETERS, pOsPidInfo) E
    S(GspSystemInfo) F(GspSystemInfo, gpuPhysAddr) F(GspSystemInfo, gpuPhysFbAddr) F(GspSystemInfo, gpuPhysInstAddr)
        F(GspSystemInfo, gpuPhysIoAddr) F(GspSystemInfo, nvDomainBusDeviceFunc) F(GspSystemInfo, simAccessBufPhysAddr)
        F(GspSystemInfo, notifyOpSharedSurfacePhysAddr) F(GspSystemInfo, pcieAtomicsOpMask) F(GspSystemInfo, consoleMemSize)
        F(GspSystemInfo, maxUserVa) F(GspSystemInfo, pciConfigMirrorBase) F(GspSystemInfo, pciConfigMirrorSize)
        F(GspSystemInfo, PCIDeviceID) F(GspSystemInfo, PCISubDeviceID) F(GspSystemInfo, PCIRevisionID)
        F(GspSystemInfo, pcieAtomicsCplDeviceCapMask) F(GspSystemInfo, oorArch) F(GspSystemInfo, clPdbProperties)
        F(GspSystemInfo, Chipset) F(GspSystemInfo, bGpuBehindBridge) F(GspSystemInfo, bFlrSupported)
        F(GspSystemInfo, b64bBar0Supported) F(GspSystemInfo, bMnocAvailable) F(GspSystemInfo, chipsetL1ssEnable)
        F(GspSystemInfo, bUpstreamL0sUnsupported) F(GspSystemInfo, bUpstreamL1Unsupported) F(GspSystemInfo, bUpstreamL1PorSupported)
        F(GspSystemInfo, bUpstreamL1PorMobileOnly) F(GspSystemInfo, bSystemHasMux) F(GspSystemInfo, upstreamAddressValid)
        F(GspSystemInfo, FHBBusInfo) F(GspSystemInfo, chipsetIDInfo) F(GspSystemInfo, acpiMethodData)
        F(GspSystemInfo, hypervisorType) F(GspSystemInfo, virtualConfigBits) F(GspSystemInfo, bIsPassthru)
        F(GspSystemInfo, sysTimerOffsetNs) F(GspSystemInfo, gspVFInfo) F(GspSystemInfo, bIsPrimary)
        F(GspSystemInfo, bIsUnixHdmiFrlComplianceEnabled) F(GspSystemInfo, isGridBuild) F(GspSystemInfo, pcieConfigReg)
        F(GspSystemInfo, gridBuildCsp) F(GspSystemInfo, bPreserveVideoMemoryAllocations) F(GspSystemInfo, bTdrEventSupported)
        F(GspSystemInfo, bFeatureStretchVblankCapable) F(GspSystemInfo, bEnableDynamicGranularityPageArrays)
        F(GspSystemInfo, bClockBoostSupported) F(GspSystemInfo, hostPageSize) F(GspSystemInfo, bIsCmcBasedHws)
        F(GspSystemInfo, bGspNocatEnabled) F(GspSystemInfo, bS0ixSupport) F(GspSystemInfo, bWindowChannelAlwaysMapped) E
    S(PACKED_REGISTRY_ENTRY) F(PACKED_REGISTRY_ENTRY, nameOffset) F(PACKED_REGISTRY_ENTRY, type)
        F(PACKED_REGISTRY_ENTRY, data) F(PACKED_REGISTRY_ENTRY, length) E
    S(PACKED_REGISTRY_TABLE) F(PACKED_REGISTRY_TABLE, size) F(PACKED_REGISTRY_TABLE, numEntries) A(PACKED_REGISTRY_TABLE, entries) E
    S(rpc_run_cpu_sequencer_v17_00) F(rpc_run_cpu_sequencer_v17_00, bufferSizeDWord) F(rpc_run_cpu_sequencer_v17_00, cmdIndex)
        F(rpc_run_cpu_sequencer_v17_00, regSaveArea) A(rpc_run_cpu_sequencer_v17_00, commandBuffer) E
    S(rpc_alloc_memory_v13_01) F(rpc_alloc_memory_v13_01, hClient) F(rpc_alloc_memory_v13_01, hDevice)
        F(rpc_alloc_memory_v13_01, hMemory) F(rpc_alloc_memory_v13_01, hClass) F(rpc_alloc_memory_v13_01, flags)
        F(rpc_alloc_memory_v13_01, pteAdjust) F(rpc_alloc_memory_v13_01, format) F(rpc_alloc_memory_v13_01, length)
        F(rpc_alloc_memory_v13_01, pageCount) F(rpc_alloc_memory_v13_01, pteDesc) A(rpc_alloc_memory_v13_01, pteDesc.pte_pde) E
    S(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS) F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, physAddress)
        F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, numEntries) F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, flags)
        F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, hVASpace) F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, chId)
        F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, subDeviceId) F(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS, pasid) E
    S(NV_MEMORY_DESC_PARAMS) F(NV_MEMORY_DESC_PARAMS, base) F(NV_MEMORY_DESC_PARAMS, size)
        F(NV_MEMORY_DESC_PARAMS, addressSpace) F(NV_MEMORY_DESC_PARAMS, cacheAttrib) E
    S(NV_CHANNEL_ALLOC_PARAMS) F(NV_CHANNEL_ALLOC_PARAMS, hObjectError) F(NV_CHANNEL_ALLOC_PARAMS, hObjectBuffer)
        F(NV_CHANNEL_ALLOC_PARAMS, gpFifoOffset) F(NV_CHANNEL_ALLOC_PARAMS, gpFifoEntries) F(NV_CHANNEL_ALLOC_PARAMS, flags)
        F(NV_CHANNEL_ALLOC_PARAMS, hContextShare) F(NV_CHANNEL_ALLOC_PARAMS, hVASpace) F(NV_CHANNEL_ALLOC_PARAMS, hUserdMemory)
        F(NV_CHANNEL_ALLOC_PARAMS, userdOffset) F(NV_CHANNEL_ALLOC_PARAMS, engineType) F(NV_CHANNEL_ALLOC_PARAMS, cid)
        F(NV_CHANNEL_ALLOC_PARAMS, subDeviceId) F(NV_CHANNEL_ALLOC_PARAMS, hObjectEccError)
        F(NV_CHANNEL_ALLOC_PARAMS, instanceMem.base) F(NV_CHANNEL_ALLOC_PARAMS, instanceMem.size)
        F(NV_CHANNEL_ALLOC_PARAMS, instanceMem.addressSpace) F(NV_CHANNEL_ALLOC_PARAMS, instanceMem.cacheAttrib)
        F(NV_CHANNEL_ALLOC_PARAMS, userdMem.base) F(NV_CHANNEL_ALLOC_PARAMS, userdMem.size)
        F(NV_CHANNEL_ALLOC_PARAMS, userdMem.addressSpace) F(NV_CHANNEL_ALLOC_PARAMS, userdMem.cacheAttrib)
        F(NV_CHANNEL_ALLOC_PARAMS, ramfcMem.base) F(NV_CHANNEL_ALLOC_PARAMS, ramfcMem.size)
        F(NV_CHANNEL_ALLOC_PARAMS, ramfcMem.addressSpace) F(NV_CHANNEL_ALLOC_PARAMS, ramfcMem.cacheAttrib)
        F(NV_CHANNEL_ALLOC_PARAMS, mthdbufMem.base) F(NV_CHANNEL_ALLOC_PARAMS, mthdbufMem.size)
        F(NV_CHANNEL_ALLOC_PARAMS, mthdbufMem.addressSpace) F(NV_CHANNEL_ALLOC_PARAMS, mthdbufMem.cacheAttrib)
        F(NV_CHANNEL_ALLOC_PARAMS, hPhysChannelGroup) F(NV_CHANNEL_ALLOC_PARAMS, internalFlags)
        F(NV_CHANNEL_ALLOC_PARAMS, errorNotifierMem.base) F(NV_CHANNEL_ALLOC_PARAMS, errorNotifierMem.size)
        F(NV_CHANNEL_ALLOC_PARAMS, errorNotifierMem.addressSpace) F(NV_CHANNEL_ALLOC_PARAMS, errorNotifierMem.cacheAttrib)
        F(NV_CHANNEL_ALLOC_PARAMS, eccErrorNotifierMem.base) F(NV_CHANNEL_ALLOC_PARAMS, eccErrorNotifierMem.size)
        F(NV_CHANNEL_ALLOC_PARAMS, eccErrorNotifierMem.addressSpace) F(NV_CHANNEL_ALLOC_PARAMS, eccErrorNotifierMem.cacheAttrib)
        F(NV_CHANNEL_ALLOC_PARAMS, ProcessID) F(NV_CHANNEL_ALLOC_PARAMS, SubProcessID) F(NV_CHANNEL_ALLOC_PARAMS, encryptIv)
        F(NV_CHANNEL_ALLOC_PARAMS, decryptIv) F(NV_CHANNEL_ALLOC_PARAMS, hmacNonce) F(NV_CHANNEL_ALLOC_PARAMS, tpcConfigID) E
    S(NV0080_CTRL_GPU_GET_CLASSLIST_V2_PARAMS) F(NV0080_CTRL_GPU_GET_CLASSLIST_V2_PARAMS, numClasses)
        F(NV0080_CTRL_GPU_GET_CLASSLIST_V2_PARAMS, classList) E
    S(NV0080_CTRL_GR_GET_INFO_V2_PARAMS) F(NV0080_CTRL_GR_GET_INFO_V2_PARAMS, grInfoListSize)
        F(NV0080_CTRL_GR_GET_INFO_V2_PARAMS, grInfoList) F(NV0080_CTRL_GR_GET_INFO_V2_PARAMS, grRouteInfo.flags)
        F(NV0080_CTRL_GR_GET_INFO_V2_PARAMS, grRouteInfo.route) E
    printf("\t)\n!\nconstants\n\t\"{name. value}: the constants NvGsp uses, from the same headers.\"\n\t^#(\n");
    C(NV_VGPU_MSG_SIGNATURE_VALID) C(NV_VGPU_MSG_HEADER_VERSION_MAJOR_TOT) C(NV_VGPU_MSG_HEADER_VERSION_MINOR_TOT)
    C(NV_VGPU_MSG_RESULT_RPC_PENDING) C(NV_VGPU_MSG_UNION_INIT)
    C(NV_VGPU_MSG_FUNCTION_NOP) C(NV_VGPU_MSG_FUNCTION_SET_GUEST_SYSTEM_INFO) C(NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY)
    C(NV_VGPU_MSG_FUNCTION_FREE) C(NV_VGPU_MSG_FUNCTION_MAP_MEMORY_DMA) C(NV_VGPU_MSG_FUNCTION_GET_GSP_STATIC_INFO)
    C(NV_VGPU_MSG_FUNCTION_GSP_SET_SYSTEM_INFO) C(NV_VGPU_MSG_FUNCTION_SET_REGISTRY) C(NV_VGPU_MSG_FUNCTION_GSP_RM_CONTROL)
    C(NV_VGPU_MSG_FUNCTION_GSP_RM_ALLOC) C(NV_VGPU_MSG_FUNCTION_CONTINUATION_RECORD)
    C(NV_VGPU_MSG_EVENT_GSP_INIT_DONE) C(NV_VGPU_MSG_EVENT_GSP_RUN_CPU_SEQUENCER) C(NV_VGPU_MSG_EVENT_POST_EVENT)
    C(NV_VGPU_MSG_EVENT_RC_TRIGGERED) C(NV_VGPU_MSG_EVENT_OS_ERROR_LOG) C(NV_VGPU_MSG_EVENT_UCODE_LIBOS_PRINT)
    C(NV_VGPU_MSG_EVENT_GSP_LOCKDOWN_NOTICE)
    C(MSGQ_VERSION) C(MSGQ_FLAGS_SWAP_RX) C(GSP_MSG_QUEUE_ELEMENT_SIZE_MIN) C(GSP_MSG_QUEUE_ELEMENT_SIZE_MAX)
    C(GSP_FW_WPR_META_MAGIC) C(GSP_FW_WPR_META_REVISION) C(GSP_DMA_TARGET_COHERENT_SYSTEM)
    C(LIBOS_MEMORY_REGION_CONTIGUOUS) C(LIBOS_MEMORY_REGION_RADIX3) C(LIBOS_MEMORY_REGION_LOC_SYSMEM)
    C(GSP_SEQ_BUF_OPCODE_REG_WRITE) C(GSP_SEQ_BUF_OPCODE_REG_MODIFY) C(GSP_SEQ_BUF_OPCODE_REG_POLL) C(GSP_SEQ_BUF_OPCODE_DELAY_US)
    C(GSP_SEQ_BUF_OPCODE_REG_STORE) C(GSP_SEQ_BUF_OPCODE_CORE_RESET) C(GSP_SEQ_BUF_OPCODE_CORE_START)
    C(GSP_SEQ_BUF_OPCODE_CORE_WAIT_FOR_HALT) C(GSP_SEQ_BUF_OPCODE_CORE_RESUME) C(GSP_SEQ_BUF_REG_SAVE_SIZE)
    C(LIBOS_MEMORY_REGION_RADIX_PAGE_SIZE) C(NVDM_TYPE_COT) C(MCTP_MSG_HEADER_TYPE_VENDOR_PCI) C(MCTP_MSG_HEADER_VENDOR_ID_NV)
    C(NV01_MEMORY_LIST_SYSTEM) C(NV_VGPU_PTEDESC_IDR_NONE) C(NV_VGPU_PTE_64_SIZE)
    C(NVOS02_FLAGS_PHYSICALITY_CONTIGUOUS) C(NVOS02_FLAGS_LOCATION_PCI) C(NVOS02_FLAGS_COHERENCY_CACHED) C(NVOS02_FLAGS_MAPPING_NO_MAP)
    B(NVOS02_FLAGS_PHYSICALITY) B(NVOS02_FLAGS_LOCATION) B(NVOS02_FLAGS_COHERENCY) B(NVOS02_FLAGS_MAPPING)
    C(NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY) C(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_FLAGS_APERTURE_SYSMEM_COH)
    B(NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_FLAGS_APERTURE)
    C(NV0080_CTRL_CMD_GPU_GET_CLASSLIST_V2) C(NV0080_CTRL_GPU_CLASSLIST_MAX_SIZE)
    C(NV2080_CTRL_CMD_GR_GET_INFO_V2) C(NV0080_CTRL_GR_INFO_MAX_SIZE)
    B(NV_MMU_VER3_PDE_IS_PTE) B(NV_MMU_VER3_PDE_APERTURE) B(NV_MMU_VER3_PDE_PCF) B(NV_MMU_VER3_PDE_ADDRESS)
    C(NV_MMU_VER3_PDE_APERTURE_SYSTEM_COHERENT_MEMORY) C(NV_MMU_VER3_PDE_PCF_VALID_UNCACHED_ATS_NOT_ALLOWED) C(NV_MMU_VER3_PDE__SIZE)
    B(NV_MMU_VER3_DUAL_PDE_IS_PTE) B(NV_MMU_VER3_DUAL_PDE_APERTURE_BIG) B(NV_MMU_VER3_DUAL_PDE_ADDRESS_BIG)
    B(NV_MMU_VER3_DUAL_PDE_APERTURE_SMALL) B(NV_MMU_VER3_DUAL_PDE_PCF_SMALL) B(NV_MMU_VER3_DUAL_PDE_ADDRESS_SMALL) C(NV_MMU_VER3_DUAL_PDE__SIZE)
    B(NV_MMU_VER3_PTE_VALID) B(NV_MMU_VER3_PTE_APERTURE) B(NV_MMU_VER3_PTE_PCF) B(NV_MMU_VER3_PTE_KIND) B(NV_MMU_VER3_PTE_ADDRESS)
    C(NV_MMU_VER3_PTE_APERTURE_SYSTEM_COHERENT_MEMORY) C(NV_MMU_VER3_PTE_PCF_REGULAR_RW_ATOMIC_UNCACHED_ACE) C(NV_MMU_VER3_PTE__SIZE)
    C(NV_RAMIN_ALLOC_SIZE) C(NV_RAMUSERD_CHAN_SIZE) B(NV_VIRTUAL_FUNCTION_FULL_PHYS_OFFSET) C(NVC361_NOTIFY_CHANNEL_PENDING)
    printf("\t)\n! !\n");
    return 0;
}
EOF
I=""
for d in src/common/sdk/nvidia/inc src/nvidia/arch/nvalloc/common/inc src/common/uproc/os/common/include \
         src/common/shared/msgq/inc src/nvidia/inc/kernel src/nvidia/generated src/nvidia/inc src/common/inc \
         src/nvidia/interface src/nvidia/inc/libraries src/nvidia/arch/nvalloc/unix/include \
         src/common/nvlink/inband/interface src/common/inc/swref; do
    I="$I -I$OGK/$d"
done
# GSP_MSG_QUEUE_ELEMENT_SIZE_MIN is RM_PAGE_SIZE (4 KB), which RM's own headers define.
# GspSystemInfo's header (gsp_static_config.h) needs RM's port library configured as the kernel driver builds it.
PORT="-DNVRM -DPORT_IS_KERNEL_BUILD=1 -DPORT_IS_CHECKED_BUILD=0 -DPORT_COVERAGE_PUSH_OFF()= -DPORT_COVERAGE_POP()="
for m in memory util atomic sync string debug safe thread core; do PORT="$PORT -DPORT_MODULE_$m=1"; done
cc -std=gnu11 -DRM_PAGE_SIZE=4096 $PORT -I"$T" $I "$T/layouts.c" -o "$T/layouts"
{
    cat <<EOF
Object subclass: #NvGspLayouts
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspLayouts comment: 'I am generated by tools/nv-gsp-layouts.sh from NVIDIA''s open-gpu-kernel-modules at $VERSION (the C compiler''s sizeof and offsetof of the GSP boot and RPC structures, and the constants NvGsp uses); do not edit me, regenerate me. NvGspLayoutTest compares NvGsp''s layouts and constants with mine.'!

EOF
    "$T/layouts"
} > "$OUT"
echo "nv-gsp-layouts: wrote $OUT"
