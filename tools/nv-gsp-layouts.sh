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
grep -q 'GSP_MSG_QUEUE_ELEMENT;' "$T/element.h"
cat > "$T/layouts.c" <<'EOF'
#include <stdio.h>
#include <stddef.h>
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

#define S(t) printf("\t\t#('%s' %zu #(\n", #t, sizeof(t));
#define F(t, f) printf("\t\t\t#('%s' %zu %zu)\n", #f, offsetof(t, f), sizeof(((t *)0)->f));
#define A(t, f) printf("\t\t\t#('%s' %zu 0)\n", #f, offsetof(t, f)); /* a flexible array: offset only */
#define E printf("\t\t))\n");
#define C(n) printf("\t\t#('%s' %llu)\n", #n, (unsigned long long)(n));

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
    C(LIBOS_MEMORY_REGION_RADIX_PAGE_SIZE) C(NVDM_TYPE_COT) C(MCTP_MSG_HEADER_TYPE_VENDOR_PCI) C(MCTP_MSG_HEADER_VENDOR_ID_NV)
    printf("\t)\n! !\n");
    return 0;
}
EOF
I=""
for d in src/common/sdk/nvidia/inc src/nvidia/arch/nvalloc/common/inc src/common/uproc/os/common/include \
         src/common/shared/msgq/inc src/nvidia/inc/kernel src/nvidia/generated src/nvidia/inc src/common/inc \
         src/nvidia/interface src/nvidia/inc/libraries src/nvidia/arch/nvalloc/unix/include; do
    I="$I -I$OGK/$d"
done
# GSP_MSG_QUEUE_ELEMENT_SIZE_MIN is RM_PAGE_SIZE (4 KB), which RM's own headers define.
cc -std=gnu11 -DRM_PAGE_SIZE=4096 -I"$T" $I "$T/layouts.c" -o "$T/layouts"
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
