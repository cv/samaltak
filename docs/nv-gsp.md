# GSP on GB10: how nvidia.ko boots and drives GSP-RM

Step 0 of cv/samaltak#20 (drive the DGX Spark's GB10 from the UEFI image, without Linux): what the open kernel module
does on this Spark to boot the GPU's RISC-V core (GSP) with NVIDIA's resource manager (GSP-RM) and to talk to it, as
facts with source references, plus this Spark's hardware facts, what nova-core covers, the development loop and the plan
for steps 1-6. docs/nv.md ("Phase B") has the overview this document details and corrects; docs/nv-rm.md is the hosted
client (Phase A) whose RM calls become RPCs; ~/samaltak-nv-brief.md holds the questions for NVIDIA (section 7 says which
are now answered).

Sources: open-gpu-kernel-modules at tag `580.178.04` (the installed driver), the firmware files and package on this
Spark (DGX OS, kernel 6.17 nvidia), Linux 7.4-rc4 (`b6a9fa3`) for nova-core, tinygrad `f0b8003`. Everything was read
only: no module, register or configuration space was written.

Tags: **[src]** verified in the source at the given file:line; **[obs]** observed on this Spark; **[inf]** inferred,
with the reasoning. Path abbreviations (all in open-gpu-kernel-modules): `gsp/` = `src/nvidia/src/kernel/gpu/gsp/`,
`sec2/` = `src/nvidia/src/kernel/gpu/sec2/`, `gen/` = `src/nvidia/generated/`, `ref/` =
`src/common/inc/swref/published/`, `gh100.c` = `gsp/arch/hopper/kernel_gsp_gh100.c`, `gb10b.c` =
`gsp/arch/blackwell/kernel_gsp_gb10b.c`, `sec2_gb10b.c` = `sec2/arch/blackwell/kernel_sec2_gb10b.c`, `kgsp.c` =
`gsp/kernel_gsp.c`.

## In short

- GB10 (PCI `10de:2e12`, chip GB10B) has **no VBIOS/FWSEC step, no booter and no FRTS**: GSP-RM is started by a chain of
  trust through **SEC2**, which already runs its own firmware when the driver comes: the driver puts the signed GSP-FMC
  and its descriptors in system memory and sends SEC2 one 868-byte message (MCTP/NVDM "COT") through SEC2's EMEM queue;
  SEC2 starts the FMC on the GSP, the FMC (with ACR) sets up WPR2 in system memory, verifies and starts GSP-RM.
- The driver then waits for the GSP to be released (`HWCFG2` stops reading as a PRI error; the RISC-V lockdown bit
  clears), writes one register (`NV_PFALCON_FALCON_OS`), checks the RISC-V core is active and polls the status queue
  for `GSP_INIT_DONE`, answering `RUN_CPU_SEQUENCER` requests meanwhile. **The register writes of the whole boot are
  about ten**, all listed in section 2.
- The images: `gsp_ga10x.bin` (75 MB, the GSP-RM ELF, from the `nvidia-firmware-580` package) and, compiled into
  `nvidia.ko` as MIT-licensed C arrays, the GB10B GSP-FMC (195,912 B + hash, signature, public key) and the GSP-RM boot
  loader (196,608 B + an 84-byte descriptor).
- RPCs: two 256 KB ring buffers of 4 KB elements in one shared system-memory region, each element a 48-byte queue
  header (checksum, sequence number) plus an `rpc_message_header_v03_00` (`VRPC`) and the payload; `GSP_RM_ALLOC` (103),
  `GSP_RM_CONTROL` (76) and `FREE` (10) carry the same parameter blocks NvRm builds today.
- New against docs/nv.md: on GB10B the MCTP transport header SEC2 gets is the constant **1**, not SOM | EOM (2.4); GB10B's
  GMMU format is Hopper's version 3 with 5 directory levels (57-bit VA) (3.5); the platform pre-initialises the WPR
  region (`PDB_PROP_GPU_PREINITIALIZED_WPR_REGION`) (2.2); the IORT keeps three identity-mapped ranges (RMR) for the GPU's
  stream ids, so the boot firmware's GPU DMA (the GOP's scanout) bypasses translation (4.3).
- nova-core boots GH100/GB100/GB102 through FSP and has a complete command queue, sequencer and radix-3 builder, but no
  GB10B, no SEC2 chain of trust and r570 (not 580) structures: a reference for the transport, not for the boot.
- Recommended loop: a **dedicated** Spark, the GSP driver developed hosted on it over VFIO (Debugger, FLR between
  attempts), each milestone then run bare metal from USB; not this shared Spark, and not QEMU passthrough.

## 1. Firmware

### 1.1 The files nvidia.ko loads on this Spark

| What | Where | Size | sha256 / notes |
|---|---|---|---|
| GSP-RM (LIBOS ELF) | `/lib/firmware/nvidia/580.178.04/gsp_ga10x.bin` | 75,028,464 B | `3b89a63f2e7a0b496113d6e727564e902456fd81017b21d35d3eaba76b24dab2` **[obs]** |
| (Turing GSP-RM, not used on GB10) | `/lib/firmware/nvidia/580.178.04/gsp_tu10x.bin` | 30,483,544 B | **[obs]** |
| GSP-FMC, production signed | `nvidia.ko`: `gen/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB10B.c` (`g_gsp_gb10b_dyn_prd_gfw_image.bin`) | 195,912 B image, 48 B hash (SHA-384), 384 B signature, 384 B public key | uncompressed C array, lines 31-38, 12291-12405 **[src]** |
| GSP-FMC, debug signed | `gen/g_bindata_kgspGetBinArchiveGspRmFmcGfwDebugSigned_GB10B.c` | same sizes | **[src]** |
| GSP-RM boot loader (RISC-V) | `gen/g_bindata_kgspGetBinArchiveGspRmBoot_GB10B.c`: `UCODE_IMAGE_PROD`/`_DBG` + `UCODE_DESC_PROD`/`_DBG` | 196,608 B + 84 B (`RM_RISCV_UCODE_DESC`) | images uncompressed, descriptors raw deflate (section 11); lines 31-38, 12352-12391, 24706-24711 **[src]** |
| log decoder `gsp_log_ga10x.bin` | not installed | - | DGX OS's package does not ship it (brief F1) **[obs]** |

Both `.bin` files come from the package `nvidia-firmware-580-580.178.04` **[obs]**. Nothing else is loaded for the GPU:

- no VBIOS/FWSEC: `kgspExtractVbiosFromRom` is `_395e98` (`NV_ERR_NOT_SUPPORTED`) for GB10B, so the VBIOS/FWSEC block of
  `kgspInitRm_IMPL` is skipped (`kgsp.c` 4020-4063) and `kgspExecuteFwsec` is a stub (`_5baef9`) **[src]**. (The
  `/proc/driver/nvidia` VBIOS version `9a.0b.2d.00.00` **[obs]** is what GSP-RM reports, not an image the driver reads.)
- no booter (booter_load/unload) and no SEC2 ucode: GB10B has `bPartitionedFmc` = TRUE (`gen/g_kernel_gsp_nvoc.c` 451),
  which skips the booter (`kgsp.c` 4076), and `ksec2ResetHw` is a stub (`_5baef9`) **[src]**; SEC2 must therefore already
  run its own boot-ROM-loaded firmware when the driver starts **[inf]**.
- no FRTS: `kgspGetFrtsSize` is `_4a4dee` (returns 0) **[src]**.

### 1.2 How the driver picks them

- Chip family: `nv-firmware-chip-family-select.h` 60 maps GB10B to `NV_FIRMWARE_CHIP_FAMILY_GB10Y` (= 11,
  `src/nvidia/arch/nvalloc/common/inc/nv-firmware.h` 49; its name "gb10y", line 60); every family from GA10x on falls
  through to `gsp_ga10x` (lines 93-99, declared 143-144), loaded with `request_firmware` from
  `nvidia/580.178.04/gsp_ga10x.bin` **[src]**.
- Signature: the ELF holds one 4 KB signature section per family: `.fwsignature_{ga10x, ad10x, gh100, cc_gh100, gb10x,
  cc_gb10x, gb10y, gb20x, cc_gb20x, gb20y}` **[obs]** (readelf). RM builds the name from
  `kgspGetSignatureSectionNamePrefix_GB100` and the family name **[src]**, so GB10B uses `.fwsignature_gb10y` (the `cc_`
  variants are for confidential computing) **[inf]**.
- `.fwversion` (11 bytes, "580.178.04") must equal the driver's version (`kgsp.c` 4731-4775, docs/nv.md) **[src]**.
- `.fwimage` (0x4783000 = 74,985,472 B at file offset 0x40) is the GSP-RM image proper: copied to system memory and
  described to GSP by a radix-3 page table (`_kgspPrepareGspRmBinaryImage`, `kgsp.c` 4843-4909) **[src]**.
- FMC: production or debug by fuse: `_ksec2GetGspUcodeArchive` (`sec2_gb10b.c` 215-237) calls `kgspIsDebugModeEnabled`,
  GB10B's being `_GA100` (`gsp/arch/ampere/kernel_gsp_ga100.c` 46-48): debug if `NV_FUSE_OPT_SECURE_GSP_DEBUG_DIS`
  (0x0082074C in `ref/hopper/gh100/dev_fuse.h` 27; GB10B has no published `dev_fuse.h`) reads `DATA_NO` **[src]**. A retail
  Spark is almost certainly production fused **[inf]**; the UEFI driver can read the fuse in step 1 and choose the same way.

### 1.3 Where a UEFI image gets them, and licensing

- `gsp_ga10x.bin`: the package's `copyright` file (`/usr/share/doc/nvidia-firmware-580-580.178.04/copyright`) puts all
  files under the "NVIDIA-graphics-drivers" licence, non-free, with "No modifications of the included binaries are
  permitted" **[obs]**; whether it may be redistributed on a third-party boot disk is not settled by that notice (brief
  B1). The simplest route that ships nothing: the UEFI image reads the file from the Spark's own DGX OS root file system
  (ext4 on the NVMe, `/lib/firmware/nvidia/580.178.04/`) or from a volume the user fills (`FirmwareVolumes`) **[inf]**.
- The FMC and boot loader are byte arrays in MIT-licensed source files (each `g_bindata_*.c` carries the MIT header;
  `COPYING` "Except where noted otherwise ... MIT") **[src]**; a build step can extract them from the 580.178.04 tag (the
  data sections between `BINDATA_INCLUDE_DATA` markers). They are signed: they must stay byte-identical.
- Version coupling: the three must come from the same driver version (580.178.04) and the RPC structures we build must
  be that version's (`g_rpc-structures.h`, `v03_00`).

## 2. The GB10 boot path in nvidia.ko 580.178.04

### 2.1 HALs

GB10B is an iGPU HAL of its own, mixing Hopper, Blackwell (GB100) and Ampere functions (`gen/g_kernel_gsp_nvoc.c`,
`gen/g_kernel_sec2_nvoc.c`, `gen/g_kernel_falcon_nvoc.c`) **[src]**:

| Function | GB10B binds | Effect |
|---|---|---|
| `kgspPrepareForBootstrap`, `kgspBootstrap`, `kgspSetupGspFmcArgs`, `kgspIsWpr2Up`, `kgspTeardown`, `kgspIssueNotifyOp` | `_GH100` | Hopper's FMC boot |
| `kgspPopulateWprMeta`, `kgspGetBinArchiveGspRmBoot`, `...FmcGfw{Debug,Prod}Signed` | `_GB10B` | GB10B images and WPR metadata |
| `kgspResetHw`, `kgspGetGspRmBootUcodeStorage`, `kgspGetSignatureSectionNamePrefix` | `_GB100` | |
| `kgspIsDebugModeEnabled` | `_GA100` | fuse read (1.2) |
| `kgspSetCmdQueueHead`, `kgspHealthCheck`, `kgspService`, `kgspReadEmem` | `_TU102` | queue doorbell, interrupts |
| `kgspExecuteFwsec`, `kgspWaitForGfwBootOk`, `kgspGetFrtsSize`, `kgspExtractVbiosFromRom` | stubs | no FWSEC, no GFW-boot wait, FRTS 0, no VBIOS |
| `kgspConfigureFalcon` | `_GA102` | GSP falcon at `NV_PGSP` (0x110000), RISC-V at `NV_FALCON2_GSP_BASE` (0x111000) (`gsp/arch/ampere/kernel_gsp_ga102.c` 57-59) |
| `kflcnReset` / `IsRiscvActive` / `RiscvProgramBcr` / `WaitForResetToFinish` | `_TU102` / `_GA102` / `_GA102` / `_GA102` | |
| SEC2: `ksec2*BootCommands`, `SetupGspImages`, `SendPacket`, `CreateNvdmHeader`, `WaitForGspTargetMaskReleased` | `_GB10B` (`sec2_gb10b.c`) | the chain of trust |
| `ksec2CreateMctpHeader` | `_539ab4` (returns 1) | see 2.4 |

Properties: `PDB_PROP_KSEC2_BOOT_GSPFMC` (`gen/g_kernel_sec2_nvoc.c` 450), `cotPayloadVersion` = 1 (481), signature and
public key 384 B (473, 476), the GSP heap base size `fwHeapParamBaseSize` 14 MB (`gen/g_kernel_gsp_nvoc.c` 478), EMEM
port 6 (501), `PDB_PROP_GPU_ZERO_FB` (no video memory; `gen/g_gpu_nvoc.c` 214-218),
`PDB_PROP_GPU_PREINITIALIZED_WPR_REGION` (191-196), `PDB_PROP_GPU_ATS_SUPPORTED` (GB10B, GB20B, GB20C; 155-161) **[src]**.

### 2.2 What the CPU prepares (all in system memory)

`kgspInitRm_IMPL` (`kgsp.c` 3984-4300), in order **[src]**:

1. VBIOS/FWSEC: skipped (4020-4063, 1.1). Partitioned FMC: no booter (4076).
2. GSP-RM boot loader: from `kgspGetBinArchiveGspRmBoot_GB10B` into a 4 KB-aligned cached buffer, with its
   `RM_RISCV_UCODE_DESC` (code/data/manifest offsets, `appVersion`) (`kgspPrepareBootBinaryImage`, 4109 → 4583-4652).
3. GSP-RM: `.fwimage` into system memory plus its radix-3 page table; version and signature sections checked/copied
   (`_kgspPrepareGspRmBinaryImage`, 4117 → 4843-4909).
4. LIBOS log buffers (4125) and `LibosMemoryRegionInitArgument`s: the LOGINIT/LOGINTR/LOGRM regions and RMARGS
   (`kgspSetupLibosInitArgs`, 4156 → 5179-5219).
5. `GSP_ARGUMENTS_CACHED` (`kgspPopulateGspRmInitArgs`, 4159 → 4511-4575): the message-queue init arguments (the shared
   region's address, the command and status queue offsets, section 3) and, because of `ZERO_FB`, `sysmemHeapArgs`: a
   system-memory heap for GSP-RM of `RmGspSysmemHeapSizeMB`, default **512 MB** (`src/nvidia/interface/nvrm_registry.h`
   2355-2356; allocated in `gsp/arch/turing/kernel_gsp_tu102.c` 206-211).
6. The first two RPCs are queued before boot: `GSP_SET_SYSTEM_INFO` (72) and `SET_REGISTRY` (73)
   (`kgspQueueAsyncInitRpcs`, 3792-3815; called 4179).
7. Boot, retried on failure (4192-4235) through `_kgspBootGspRm` (3902-3970): the WPR2-up check (3911) is skipped because
   GB10B has `PREINITIALIZED_WPR_REGION`; `kgspPrepareForBootstrap` (3928) then `kgspBootstrap` (3946).

`kgspPrepareForBootstrap_GH100` (`gh100.c` 775-810) **[src]**:

8. `kgspSetupGspFmcArgs_GH100` (794 → 411-486): the FMC boot parameters `GSP_FMC_BOOT_PARAMS` in a 4 KB cached buffer:
   `bootGspRmParams` = { `gspRmDescOffset` = the WprMeta's GPU address, its size, target coherent system memory,
   `bIsGspRmBoot` = TRUE }, `gspRmParams` = { `bootArgsOffset` = the LIBOS init arguments' address, target }; SPDM only
   when enabled (not on GB10).
9. `GspFwWprMeta` (256 bytes, `kgspPopulateWprMeta_GB10B`, `gb10b.c` 61-89; layout comment 30-60, common part
   `kgspPopulateWprMeta_GH100`): the boot loader's system-memory address and size, the radix-3 root and size, the code,
   data and manifest offsets from the descriptor, the signature, the GSP heap size, `frtsSize` 0, the crash-dump queue,
   revision and magic. WPR2's own offsets are left to ACR (`FW_WPR_OFFSET_SET_BY_ACR`); the driver learns the layout
   after boot (`_kgspSetFwWprLayoutOffset`, `kgsp.c` 4283).
10. SEC2 (802-807): `ksec2PrepareBootCommands_GB10B` (`sec2_gb10b.c` 561-610) allocates `NVDM_PAYLOAD_COT` (860 bytes,
    packed; `src/nvidia/inc/kernel/gpu/fsp/kern_fsp_cot_payload.h` 36-55) and `ksec2SetupGspImages_GB10B` (437-544) fills
    it: the FMC image copied to a 4 KB-aligned cached buffer (`gspFmcSysmemOffset`, its GPU address); `frtsSysmemSize` =
    the FMC image size (508; brief A3 asks whether that is intended); vidmem fields 0; `hash384`, `publicKey`,
    `signature` from the FMC archive; `gspBootArgsSysmemOffset` = the FMC boot parameters' address; `version` 1, `size`
    860.

All addresses handed to the GPU are its DMA addresses (`memdescGetPhysAddr(..., AT_GPU, ...)`; under Linux SMMU IOVAs)
**[src]**. Memory the client provides, roughly: 75 MB GSP-RM copy + radix-3, 512 MB heap, ~200 KB each for FMC and boot
loader, the queues (512 KB + page table), log buffers, three 4 KB argument pages; about 600 MB **[inf]** (the Spark has
128 GB).

### 2.3 Register sequence of `kgspBootstrap_GH100` on GB10B

BAR0 offsets; `GSP` = falcon at 0x110000, `RV` = its RISC-V block at 0x111000, `SEC2` = 0x840000. Register addresses from
`ref/blackwell/gb10b/dev_sec_pri.h` 27-48, `ref/blackwell/gb10b/dev_gsp.h` 27, `ref/hopper/gh100/dev_gsp.h` 26-54,
`ref/hopper/gh100/dev_falcon_v4.h` 27-81, `ref/hopper/gh100/dev_riscv_pri.h` 58-68, `ref/ampere/ga102/dev_gsp.h` 38
**[src]**. Every wait is `gpuTimeoutCondWait` with the default GPU timeout: **4 s** on bare-metal Linux
(`osGetTimeoutParams`, `src/nvidia/arch/nvalloc/unix/src/os.c` ~2004-2036) **[src]**.

| # | Access | Register (BAR0) | Value / condition | Source |
|---|---|---|---|---|
| 0 | - | - | `kflcnSetRiscvMode(TRUE)`: a software flag only (`gen/g_kernel_falcon_nvoc.h` 953-956); no reset of GSP or SEC2 anywhere in the boot path (the only `kflcnReset` is the CPU sequencer's CORE_RESET, `kgsp.c` 5403-5408) | `gh100.c` 850 |
| 1 | poll | SEC2 `QUEUE_HEAD(0)` 0x840C00, `QUEUE_TAIL(0)` 0x840C04 | until HEAD == TAIL (channel idle) | `ksec2CanSendPacket_GB10B` `sec2_gb10b.c` 344-356; poll `sec2/kernel_sec2.c` 605-639 |
| 2 | write | SEC2 `EMEMC(0)` 0x840AC0 | `AINCW` (bit 24) \| offset 0 (OFFS 7:2, BLK 15:8) | `_ksec2ConfigEmemc_GB10B` 118-165 |
| 3 | write ×217 | SEC2 `EMEMD(0)` 0x840AC4 | the 868-byte packet (2.4), word by word | `_ksec2WriteToEmem_GB10B` 166-214 |
| 4 | write | SEC2 `QUEUE_TAIL(0)` 0x840C04 | 864 (bytes, padded to 4, − 4) | `_ksec2UpdateQueueHeadTail_GB10B` 72-93 (82-83) |
| 5 | write | SEC2 `QUEUE_HEAD(0)` 0x840C00 | 0 (last: hands the message to SEC2) | same |
| 6 | poll | SEC2 `MAILBOX0` 0x840040 | until ≠ 0xC001CAFE ("command handling"); no reply is read | `_ksec2WaitForCmdHandling` 285-311, called 612-670 |
| 7 | poll | GSP `HWCFG2` 0x1100F4 | until ≠ 0 and (value & 0xFFFFFF00) ≠ 0xBADF4100 (the PRI "target locked" error): SEC2 has released the GSP to the CPU | `_ksec2IsGspTargetMaskReleased` 264-283, 368-378; `gh100.c` 897-910 |
| 8 | poll | GSP `MAILBOX0` 0x110040, `MAILBOX1` 0x110044, `HWCFG2` 0x1100F4 | still waiting while MAILBOX0/1 hold the FMC parameters' address (lo/hi); done when `HWCFG2.RISCV_BR_PRIV_LOCKDOWN` (bit 13) = 0 (UNLOCK) or MAILBOX0 ≠ 0 | `_kgspLockdownReleasedOrFmcError` `gh100.c` 492-535; wait 926-943 |
| 9 | read | GSP `MAILBOX0` 0x110040 | ≠ 0 → the FMC's error code, boot fails (`NV_ERR_NOT_READY`) | `gh100.c` 944-948 |
| 10 | write | GSP `NV_PFALCON_FALCON_OS` 0x110080 | the boot loader descriptor's `appVersion` | `gh100.c` 955-956 |
| 11 | read | RV `NV_PRISCV_RISCV_CPUCTL` 0x111388 | `ACTIVE_STAT` (bit 7) set, else "Failed to boot GSP" (one read in RM; nova-core polls 10 ms up to 5 s) | `gh100.c` 959-966 |
| 12 | memory | status queue | link GSP's status queue (wait for its TX header, retrying) | `GspStatusQueueInit` `gh100.c` 975-977; `msgqRxLink` `gsp/message_queue_cpu.c` 346-390 |
| 13 | memory + write | status queue; GSP `QUEUE_HEAD(0)` 0x110C00 after each command | poll for `GSP_INIT_DONE`, running `RUN_CPU_SEQUENCER` meanwhile (2.5) | `kgspWaitForRmInitDone` `kgsp.c` 5252-5282; doorbell `kgspSetCmdQueueHead_TU102` `gsp/arch/turing/kernel_gsp_tu102.c` 343-355 |

Who writes the FMC parameters' address into the GSP mailboxes (step 8) is not in the client source: SEC2 or the FMC
**[inf]**. Step 6 only proves SEC2 left the 0xC001CAFE state; if SEC2 never wrote it, the poll passes at once and step 7
is the real wait **[inf]**.

### 2.4 The SEC2 message

`ksec2SendMessage_IMPL` (`sec2/kernel_sec2.c` 282-366) and `ksec2SendPacket_GB10B` (`sec2_gb10b.c` 699-733) **[src]**:

- Two header words (`HEADER_DWORD_MAX` 2, `kernel_sec2.c` 50-52), then the payload; the packet is at most the EMEM
  channel's 1024 bytes (`SEC2_EMEM_CHANNEL_RM_SIZE`, `sec2_gb10b.c` 36-39, 322-332), so the 860-byte COT payload goes as a
  single 868-byte packet.
- Word 0, the MCTP transport header: `ksec2CreateMctpHeader` is bound to `_539ab4` for GB10B, which **returns 1**
  (`gen/g_kernel_sec2_nvoc.h` 853-855, binding `gen/g_kernel_sec2_nvoc.c` 786-790): the word is `0x00000001`, not the
  SOM/EOM/SEID/SEQ bits of the FSP format (`fsp_mctp_format.h` 34-53, tinygrad's FSP code). GB20B has a real function.
- Word 1, the NVDM message header: `ksec2CreateNvdmHeader_GB10B` (390-401) = type 0x7E (vendor PCI) | vendor id 0x10DE <<
  8 | NVDM type COT 0x14 (`fsp_nvdm_format.h` 40) << 24 = **`0x1410DE7E`**.

### 2.5 What GSP sends back during boot

Events on the status queue (`src/nvidia/inc/kernel/vgpu/rpc_global_enums.h`) **[src]**: `GSP_INIT_DONE` 0x1001 (the end of
boot), `GSP_RUN_CPU_SEQUENCER` 0x1002, `POST_EVENT` 0x1003, `RC_TRIGGERED` 0x1004, `OS_ERROR_LOG` 0x1006,
`UCODE_LIBOS_PRINT` 0x100C, `GSP_LOCKDOWN_NOTICE` 0x101C. The CPU sequencer (`kgspExecuteSequencerBuffer_IMPL`, `kgsp.c`
5297; dispatch `_kgspRpcRunCpuSequencer` 433, 1521; opcodes `src/nvidia/arch/nvalloc/common/inc/rmgspseq.h`) runs
REG_WRITE (5331), REG_MODIFY (5341), REG_POLL (5356), DELAY_US (5383), REG_STORE (5392), CORE_RESET (5403),
CORE_START (5412), CORE_WAIT_FOR_HALT (5420) on GSP's behalf. After `GSP_INIT_DONE` the driver sends
`SET_GUEST_SYSTEM_INFO` (`kgsp.c` 4263) and `GET_GSP_STATIC_INFO` (4270), and reads the WPR layout ACR chose (4283).

### 2.6 WPR, FRTS and the heap

- FRTS: none (size 0, 1.1); the COT's vidmem fields are 0 **[src]**.
- WPR2: in system memory, placed by ACR inside a region the platform pre-initialises (`PREINITIALIZED_WPR_REGION`,
  `FW_WPR_OFFSET_SET_BY_ACR`; `gb10b.c` 30-60) **[src]**; its size is the GSP heap (base 14 MB plus a per-chip part; 88-280 MB
  per docs/nv.md) plus the images. Where the platform's region is: not in the client source. Candidate: the third IORT
  RMR range for the GPU, 0xA1600000 + 0x18200000 (386 MB), reserved in `/proc/iomem` (4.3) **[inf]**.
- The 512 MB system heap (2.2 step 5) is ordinary client memory, not WPR **[src]**.

## 3. The RPC transport

### 3.1 Shared memory and queues

One DMA region, described to GSP in the init arguments (`_getMsgQueueParams`, `gsp/message_queue_cpu.c` 60-126)
**[src]**: a page table of the region's own pages (one 8-byte PTE per 4 KB page), then the command queue (CPU → GSP)
and the status queue (GSP → CPU), 0x40000 bytes each (71-72). Each queue starts with a `msgqTxHeader` { `version`,
`size`, `msgSize`, `msgCount`, `writePtr`, `flags`, `rxHdrOff`, `entryOff` } and a `msgqRxHeader` { `readPtr` }
(`src/nvidia/inc/kernel/gpu/gsp/msgq/msgq_priv.h` 48-65), then `msgCount` entries of `msgSize` = 4 KB. Our read pointer
for the status queue lives in the command queue's RX header and vice versa: both queues are made with
`MSGQ_FLAGS_SWAP_RX`, so each side writes its read pointer into its own queue's `msgqRxHeader` (`msgqTxCreate`,
`msgqRxLink`, `src/common/shared/msgq/msgq.c` 188-245, 331-420) **[src]**. Each queue's header page: `msgqTxHeader` at 0,
`msgqRxHeader` at 32 (aligned to 16), entries from 4096; 63 entries of 4 KB in 256 KB; one entry always stays free.

An element (`GSP_MSG_QUEUE_ELEMENT`, `src/nvidia/inc/kernel/gpu/gsp/message_queue_priv.h` 43-51) **[src]**: `authTagBuffer`
[16], `aadBuffer` [16] (confidential computing; zero here), `checkSum`, `seqNum`, `elemCount` (4 KB pages it spans):
0x30 bytes, then the RPC. An element is 4 KB to 64 KB (91-104); larger RPCs continue in `CONTINUATION_RECORD`
messages. Sending (`message_queue_cpu.c` 469-565): fill the element, `seqNum` = the queue's TX counter (481, incremented per
message, 588), the checksum over the element with the field zeroed (483, 515-519; the receiver checks that the sum over
the element, checksum included, is 0, 676-685, and that `seqNum` is the expected one, 693), wait up to 1 s per element
for space (530), advance `writePtr`, then ring GSP's doorbell: `NV_PGSP_QUEUE_HEAD(0)` 0x110C00
(`kgspSetCmdQueueHead_TU102`) **[src]**. Receiving is polling the status queue's
`writePtr` against our `readPtr` (`rpcRecvPoll`); GSP also raises SWGEN0, which polling can ignore (D1) **[src]**.

### 3.2 The RPC header and the calls

`rpc_message_header_v03_00` (`gen/g_rpc-message-header.h` 41-52) **[src]**: `header_version` 0x03000000, `signature`
0x43505256 ("VRPC", `src/nvidia/inc/kernel/vgpu/rpc_headers.h` 58-61), `length` (header + payload), `function`,
`rpc_result`, `rpc_result_private`, `sequence`, a spare/GFID word; payload follows. The reply comes back in the same
shape with `rpc_result` set.

| Function | # | Payload (`gen/g_rpc-structures.h`) | Phase A equivalent |
|---|---|---|---|
| `GSP_RM_ALLOC` | 103 | `rpc_gsp_rm_alloc_v03_00` (1491-1502): hClient, hParent, hObject, hClass, status, paramsSize, flags, reserved, params[] | `NV_ESC_RM_ALLOC` (`alloc:parent:params:`): the same params block |
| `GSP_RM_CONTROL` | 76 | `rpc_gsp_rm_control_v03_00` (1506-1518): hClient, hObject, cmd, status, paramsSize, flags, params[] | `NV_ESC_RM_CONTROL` (`control:object:params:`) |
| `FREE` | 10 | `rpc_free_v03_00` (160-163) = `NVOS00_PARAMETERS_v03_00` { hRoot, hObjectParent, hObjectOld, status } (`gen/g_sdk-structures.h` 261-267) | `NV_ESC_RM_FREE` (`free:parent:`) |
| `ALLOC_MEMORY` | 4 | a memory object's pages (PTE list) | none: done by the kernel module today |
| `GSP_SET_SYSTEM_INFO`, `SET_REGISTRY` | 72, 73 | before boot (2.2) | none |
| `GET_GSP_STATIC_INFO` | 65 | after boot | none |

The header's `length` is the header and the payload struct, for `GSP_RM_CONTROL` also the parameters (rpc.c 10978-10981),
but for `GSP_RM_ALLOC` not: `rpcWriteCommonHeader` gets `sizeof(rpc_gsp_rm_alloc_v03_00)` and the parameters are copied
after it (11197-11217), so they travel in the element's 4 KB entry past the checksummed length **[src]**. A new root client
(`NV01_ROOT`) always carries a whole `NV0000_ALLOC_PARAMETERS` (120 bytes, 11176-11180) **[src]**.

The client side: `rpcRmApiAlloc_GSP` (`src/nvidia/src/kernel/vgpu/rpc.c` 11138), `rpcRmApiControl_GSP` (10853),
`rpcRmApiFree_GSP` (11311) **[src]**. Embedded pointers in parameter blocks (NvRm's `NvP64` fields) cannot cross: the
kernel module flattens or resolves them before forwarding; the calls Phase A makes use flat blocks except where NvRm
already marshals arrays (docs/nv-rm.md) **[inf]**.

### 3.3 What the kernel module does itself (we must, on UEFI)

On a GSP client every RM object exists twice: CPU-RM constructs it and forwards it to GSP-RM (the classes flagged
`RS_FLAGS_ALLOC_RPC_TO_PHYS_RM` in `src/nvidia/src/kernel/rmapi/resource_list.h`; controls flagged
`RMCTRL_FLAGS_ROUTE_TO_PHYSICAL` 0x40, `src/nvidia/inc/kernel/rmapi/control.h` 233) **[src]**. The parts CPU-RM keeps:

- **System memory** (`NV01_MEMORY_SYSTEM`, the only kind on GB10): CPU-RM allocates and pins the pages, then tells GSP with
  `ALLOC_MEMORY` (`src/nvidia/src/kernel/mem_mgr/system_mem.c` 490; also `mem.c` 568, `os_desc_mem.c` 214) **[src]**. On
  UEFI: a `PciDevice` DMA buffer and an `ALLOC_MEMORY` describing it.
- **VA spaces and page tables** (`FERMI_VASPACE_A`): CPU-RM builds the client VA space's GMMU page tables (gvaspace), copies
  the PDEs GSP-RM reserves for itself (`NV90F1_CTRL_CMD_VASPACE_COPY_SERVER_RESERVED_PDES`,
  `src/nvidia/src/kernel/mem_mgr/gpu_vaspace.c` 5180) and gives GSP the root with `NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY`
  (`gpu/mmu/kern_gmmu.c` 2079) **[src]**. Mapping (`NV_ESC_RM_MAP_MEMORY_DMA`) writes PTEs on the CPU side **[inf]**. NvRm
  already uses an RM-owned (not ATS) VA space (docs/nv-rm.md), so it needs exactly this.
- **Channels**: CPU-RM allocates the instance block and USERD and passes their descriptors (`instanceMem`, `userdMem`:
  base, size, address space, cache attribute) in the GPFIFO allocation to GSP (`gpu/fifo/kernel_channel.c` 2450-2490)
  **[src]**.
- **BAR mappings**: GB10 has BAR0 only (4.1) **[obs]**: no BAR1 aperture and no BAR2 page tables to manage; the CPU
  reaches GPU memory directly (it is system memory) and the usermode/doorbell page (`BLACKWELL_USERMODE_A`) is a BAR0
  window **[inf]** (docs/nv.md).

### 3.4 GB10B's GMMU format

`kgmmuFmtInitLevels_GB10X` (`src/nvidia/src/kernel/gpu/mmu/arch/blackwell/kern_gmmu_fmt_gb10x.c` 24-61, bound for GB10B in
`gen/g_kern_gmmu_nvoc.c` 689) is Hopper's version-3 format (`kgmmuFmtInitLevels_GH10X`,
`gpu/mmu/arch/hopper/kern_gmmu_fmt_gh10x.c` 59-120) plus one change **[src]**:

- 57-bit VA: PD4 [56], PD3 [55:47], PD2 [46:38] (may now hold a 256 GB page), PD1 [37:29] (512 MB page), PD0 [28:21]
  (dual PDE, 2 MB page), PT_SMALL [20:12] (4 KB) or PT_BIG [20:16] (64 KB).
- PTE (`ref/hopper/gh100/dev_mmu.h` 131-177): VALID 0, APERTURE 2:1, PCF 7:3, KIND 11:8, ADDRESS 51:12.

This answers docs/nv.md Phase B question 3 and brief C4 (format; UVM agrees, `uvm_blackwell_mmu.c`).

## 4. This Spark's hardware

### 4.1 PCI **[obs]**

- GPU `000f:01:00.0`, `10de:2e12` rev a1, class 030000 (VGA), subsystem `10de:0000`, part 2E12-275-A1; root port
  `000f:00:00.0` (`10de:22d1`). The link is virtual (C2C): LnkCap 2.5 GT/s x16, reported "downgraded" Gen1 x1.
- **BAR0 only**: 64 MB at 0x24000000, 64-bit prefetchable. No BAR1, BAR2 or I/O BAR.
- Capabilities: PM (NoSoftRst+), MSI (16 vectors, disabled), PCIe (FLReset+, MPS 256), vendor-specific, **MSI-X 9 vectors**
  (table BAR0 + 0xB90000, PBA BAR0 + 0xBA0000; Linux uses 8, IRQs 341-348), AER, ARI, L1SS, vendor `[2a4]` ID 1,
  **ATS (enabled)**, **PASID (20 bits, enabled)**, DSN. Reset methods: `flr bus`. The root port has ACS (SrcValid,
  ReqRedir, CmpltRedir, UpstreamFwd).
- nvidia-smi: Addressing ATS, C2C enabled, Display Attached No; `/proc/driver/nvidia`: DMA 41 bits (mask 0x1ffffffffff),
  `EnableGpuFirmware` 18, VBIOS 9a.0b.2d.00.00. `vgaarb` names it the boot VGA device.

### 4.2 IOMMU **[obs]**

IOMMU group 20, type DMA (translated), behind SMMUv3 `0x13000000`; kernel command line `iommu.passthrough=0
pci=pcie_bus_safe`. Three SMMUv3s: 0x13800000 (PCIe segments 0-14), 0x13000000 (segment 15: the GPU and HDA), 0x14900000
(platform devices). Output address size 40 bits.

### 4.3 ACPI: IORT, DSDT **[obs]**

- IORT (rev 6): root complex segment 15 maps RID → stream id 1:1 (the GPU is SID 0x100), with **ATS attribute set** (the
  other segments 0), coherent, memory address limit 40 bits.
- An **RMR** node (flags 0x10: no remap; attribute Normal NC) for SIDs 0..0x100 on SMMU 0x13000000 with three ranges:
  0x3_0000_0000 + 48 MB (the "UEFI" carveout GSP-RM reports), 0x2_8000_0000 + 2 GB (contains DISPLAY_FRM at
  0x2_8020_0000), and 0xA160_0000 + 0x1820_0000 (386 MB; `/proc/iomem` has 0x93400000-0xafffffff and
  0xb9600000-0xb97fffff reserved). RMRs exist so that DMA the firmware started before the OS (here: the GPU's) keeps
  working when the OS enables the SMMU: **the boot firmware has the GB10 display engine scan out of the DISPLAY_FRM
  carveout, and GPU DMA before the OS uses physical addresses** **[inf, strong]**.
- DSDT: `\_SB_.PCIF.RP0_.IGPU` with power domains IGPU, HFRP_IGPU, SMMU_DISP_GPU SYS and DISP_DRV. SSDT4 (NVIDIA NBCI)
  refers to `_SB_.PCI0.RP0.PEGP` (apparently stale). Firmware: AMI 5.36_0ACUM018 (2025-08-06), board P4242.
- No efifb/simpledrm in this boot's log (the console moves to fbcon only with nvidia-drm), so the GOP framebuffer's
  address is not logged; Display Attached is No (headless now).
- System RAM ends at 0x20_7FFF_FFFF (128 GB, below 2^40); `/proc/iomem` reserved 0x2_8000_0000-0x3_237F_FFFF.

So: the GOP is driven by the GB10's display engine **[inf]**; whether the boot firmware also runs (or ran) GSP, SEC2's
chain of trust or a GSP-RM of its own before handing over is not known (brief A2); step 1 can read it (section 7).

## 5. nova-core and other references

nova-core in Linux 7.4-rc4 (`drivers/gpu/nova-core`, ~19,000 lines of Rust) **[src]**:

- Chips: Turing, Ampere, Ada, GH100, GB100/GB102 (its `BlackwellGB10x` is the datacenter GB100, not GB10) and GB20x
  (`gpu.rs` 130-147). **No GB10B or GB20B** (no iGPU, no `ZERO_FB` heap).
- Boot: Turing-Ada through booter and FWSEC (`firmware/booter.rs`, `firmware/fwsec/`); Hopper/Blackwell dGPUs through FSP's
  chain of trust (`fsp.rs`, `mctp.rs`, `gsp/hal/gh100.rs`: lockdown-release wait as `_kgspLockdownReleasedOrFmcError`).
  **No SEC2 chain of trust.** `gsp/boot.rs` (144 lines) is the common sequence: queue SET_SYSTEM_INFO and SET_REGISTRY,
  chip boot, write the OS version, poll RISC-V active (10 ms, 5 s), wait for GSP_INIT_DONE.
- Transport: `gsp/cmdq.rs` (984 lines, plus continuation records), `gsp/sequencer.rs` (379), `firmware/radix3.rs`,
  `GetGspStaticInfo`; `MsgFunction` lists `GspRmControl` and friends but there are no RM alloc/control wrappers.
- ABI: bindings for **r570.144** (`gsp/fw/r570_144.rs`), firmware from `nvidia/<chip>/gsp/` (linux-firmware layout); 580's
  structures and the GB10B images are not used.

Reuse as a reference: the queue element and checksum handling, continuation records, the sequencer, radix-3, the
WprMeta and FMC parameter construction, and the COT payload logic (the payload struct is the same; only the transport to
SEC2's EMEM and the MCTP word differ, 2.4). Struct layouts must come from the 580.178.04 headers.

tinygrad (`f0b8003`, `tinygrad/runtime/support/nv/ip.py`) boots discrete GPUs: SEC2 only as Ampere's booter host (190-222,
684-688), FSP for Blackwell dGPUs; no GB10 path **[src]**.

## 6. Development loop and open questions

### 6.1 Recommendation

1. **Not on this Spark.** It is shared and its GPU serves other users: anything from step 3 on needs the GPU without
   nvidia.ko. Steps 0-2 need no GPU access; step 1 needs a reboot into the UEFI image (operator's call).
2. **A dedicated Spark, hosted over VFIO, as the main loop.** Unbind nvidia.ko, give `000f:01:00.0` to the hosted image
   through `/dev/vfio` and write the GSP driver with the Debugger, inspecting the queues and log buffers live. Reasons: the
   GPU has FLR (4.1), so a failed attempt can often be retried without a power cycle (whether FLR resets SEC2 and the
   GSP lockdown is to be found out; rebinding nvidia.ko is the check); VFIO's IOMMU mapping gives the same "DMA address"
   abstraction `PciDevice` gives on UEFI, so the driver above it is the same code; no console or USB stick per attempt.
   `VfioPciDevice` is that `PciDevice` (section 13); the GPU's firmware RMR ranges may make the kernel refuse VFIO
   (section 13; the day-one runbook is docs/nv-dayone.md).
3. **Each milestone then bare metal by USB** (`make usb-image`), with the serial console (the Spark has a UART at
   0x16A00000, `earlycon`, SPCR/DBG2) for logs. Differences VFIO hides: the SMMU (bypass or RMR identity on UEFI, 4.3), the
   GPU's state after the GOP, interrupts.
4. **QEMU passthrough: not pursued.** It adds a second translation layer and needs the guest to see ATS, the RMRs and C2C
   coherence correctly, with nothing gained over hosted VFIO; it is unknown whether GB10's iGPU can be assigned to a guest
   at all.

Offline work that needs no GPU (do first, any machine): the boot structures (COT payload, FMC parameters, WprMeta, LIBOS
args, radix-3, queue headers, elements, RPC headers) built in Smalltalk and tested byte-for-byte against the 580 headers'
layouts; a fake GSP for the transport.

### 6.2 The issue's open questions

- *Is the GPU a PCI I/O handle on UEFI, powered and out of reset?* Open. The GOP very likely drives it (4.3), so it is
  powered with the display engine running. Step 1 answers it (find the handle, read `NV_PMC_BOOT_0`).
- *Which Falcon/booter steps; VBIOS/FWSEC?* **Answered**: none; SEC2 chain of trust only (1.1, 2).
- *May we ship the firmware?* Partly: FMC and boot loader are MIT-licensed source arrays; `gsp_ga10x.bin`'s notice forbids
  modification and does not settle redistribution (1.3). Avoid the question by reading the file from the Spark's DGX OS
  volume or a user-filled volume.
- *SMMU: do PciDevice addresses work, or ATS/PASID?* Partly: the client gives GSP DMA addresses everywhere (2.2); GB10B
  runs RM-owned page tables fine without ATS (NvRm does it today; 3.4); before the OS the GPU's stream ids are identity
  mapped for the carveouts (4.3). Open: whether UEFI leaves the SMMU in bypass for all GPU DMA (else `PciDevice` must
  program it or use the RMR ranges), and whether SEC2/GSP DMA goes through the same stream id.
- *Interrupts: polling?* Yes for boot and RPCs (`rpcRecvPoll`, 3.1); GSP's SWGEN0 can be ignored **[src]**; channels'
  completion by semaphores, as today.

### 6.3 Biggest unknowns

1. The GPU's state after the GOP: is GSP already booted or locked by the boot firmware (SEC2 may refuse a second COT),
   and is there a reset that brings SEC2 back to "accept a COT" (FLR? `NV_SYSCTRL_SEC_FAULT` cases, `ref/blackwell/gb10b/dev_boot.h`)?
2. Whether SEC2 accepts the COT from a pre-OS agent at all (brief A1), and what MAILBOX0 codes mean (A3).
3. The SMMU's state under UEFI and which addresses GSP accepts (C1).
4. The set of internal RPCs/controls CPU-RM issues between INIT_DONE and a running compute channel (brief A5; the
   Linux driver's own sequence can be logged on the dedicated Spark with the driver's RPC logging (a module parameter,
not to be changed on this shared one)).

## 7. Plan for steps 1-6

| Step | Work | Exit test | Risk | Estimate |
|---|---|---|---|---|
| 1. UEFI probe | Find `10de:2e12` with `PciDevice`, BAR0, capabilities; read only: `NV_PMC_BOOT_0` (0x0), SEC2 `QUEUE_HEAD/TAIL(0)` and `MAILBOX0/1`, GSP `HWCFG2` (lockdown bit, PRI error?), `MAILBOX0/1`, RV `CPUCTL` (active/halted), the debug fuse 0x0082074C; whether the GOP handle is connected | same chip id as Linux; a report of the post-GOP state; nothing written | needs a reboot of a Spark into the image; a read of a locked register returns 0xBADF41xx (harmless) | 2-3 days |
| 2. Transport seam | `NvIoctlTransport` (today's) and `NvGspTransport` behind NvDevice's alloc/control/free; the boot and queue structures as NvStructs with byte-level tests; a fake GSP | Tests-NV unchanged on Linux; seam and layout tests pass everywhere | layouts from the wrong version (pin 580.178.04) | 1 week |
| 3. GSP boot | firmware loading (ext4/ESP), DMA buffers, sections 2.2-2.5, the CPU sequencer, LIBOS log dump (raw) | `GSP_INIT_DONE` and an answered `GET_GSP_STATIC_INFO` | hangs needing a power cycle; unknown SEC2 errors; post-GOP state (6.3) | 2-4 weeks |
| 4. RM objects | SET_SYSTEM_INFO/REGISTRY contents, root/device/subdevice, class list, GR info over RPC | `smVersion` = 16rA04, class list as on Linux | missing internal RPCs CPU-RM sends (6.3 item 4) | 1 week |
| 5. Memory and VA | `ALLOC_MEMORY` for DMA buffers, the VA space, GMMU v3 page tables (3.4), SET_PAGE_DIRECTORY | CPU-written memory read back by a copy engine or a semaphore release | coherence (C5), 40-bit DMA limit (C2) | 1-2 weeks |
| 6. Channel and launch | GPFIFO with instance block and USERD descriptors (3.3), doorbell in BAR0, NvCompute | `NvTestKernels` `fill` = 7, then Tests-NV on UEFI | fault/error handling without interrupts | 1-2 weeks |

Steps 1 and 2 can proceed now; step 3 should wait for a dedicated Spark.

## 8. Step 1: the probe

`NvProbe` (System-NV) looks at an NVIDIA GPU without writing anything, and `FirmwareDiagnostics`' `nvidia` section runs it
on every NVIDIA display function the firmware's PCI I/O protocol has. What it reports:

- where the function is (`segment:bus:device.function`), its device path, whether a firmware driver manages it (opened
  BY_DRIVER or EXCLUSIVE), how many child controllers that driver made, and which GOP is this GPU's (a child, or a device
  path below the GPU's): the answer to "is the GOP driven by the GB10's display engine";
- the configuration space: ids, revision, class, subsystem, the command register (memory decoding, bus mastering), the
  BARs with the sizes the firmware assigned (`GetBarAttributes`, never sized by writing ones), the capabilities (PM, MSI,
  PCIe link and FLR, MSI-X table and PBA) and extended capabilities (ATS, PASID, the serial number, and NVIDIA's VSEC
  with `NV_EP_PCFG_GPU_VSEC_DEBUG_SEC` at 16r2B4: the SEC_FAULT bits RM decodes, `kern_gpu_gb10b.c` 99-176);
- if (and only if) memory decoding is already on, eleven BAR0 registers read through PCI I/O `Mem.Read`: `NV_PMC_BOOT_0`,
  `NV_PMC_BOOT_42` (chip 16r1AB = GB10B, revision), SEC2 `QUEUE_HEAD(0)`/`QUEUE_TAIL(0)`/`MAILBOX0`/`MAILBOX1`, GSP
  `HWCFG2`/`MAILBOX0`/`MAILBOX1`, the GSP RISC-V `CPUCTL` (addresses in 2.3) and `NV_FUSE_OPT_SECURE_GSP_DEBUG_DIS`
  (16r82074C, 1.2: which FMC to use), each decoded (PRI errors 16rBADxxxxx
  included), and a `state:` line saying what they imply.

Run it on the dedicated Spark:

1. `make usb-image USB_DIAG=nv` (on any Linux, the Spark itself included; the stick's command line then runs
   `FirmwareDiagnostics runNvidiaThenWorld`: the firmware, the PCI functions, the NVIDIA section, then the World after a
   key or 30 s), write `build/uefi/usb.img` to a stick (docs/uefi.md, Bare metal), boot the Spark from it.
2. The lines (`diag nvidia ...`) appear on the console and in `samaltak-diag.txt` on the stick's EFI system partition,
   flushed before the registers are read, so a hang leaves the configuration-space part. Under the World, the World menu's
   System › **NVIDIA GPU probe** (on UEFI only) shows the same lines in a Workspace. `USB_DIAG=1` includes the section too, before
   the network.

What to look for:

| Line | Expect | If not |
|---|---|---|
| `nvidia 000f:01:00.0 on ..., driven by the firmware` | the GPU, managed by the firmware's GOP driver | not managed: the GOP is elsewhere, or the firmware leaves the GPU alone |
| `nvidia gop N is this GPU's` | one line: the GOP is the GB10's display engine | none: the scanout is not this PCI function's (another display path) |
| `id 10de:2e12 rev a1`, `bar 0: memory 16r24000000, 64-bit, prefetchable, 64 MB` | as under Linux (4.1) | a different BAR0: the firmware maps the GPU elsewhere before Linux |
| `command ...: memory decoding on` | on (the GOP driver uses BAR0) | off: no register was read; the next step must enable decoding (a write) |
| `sec fault ...: none` | none (Linux reads 0) | a SEC_FAULT already: nothing will boot until a cold reset |
| `reg NV_PMC_BOOT_42 ... chip 16r1ab (GB10B), revision A1` | that | PRI error or all ones: BAR0 not usable from UEFI as is |
| `reg FUSE_OPT_SECURE_GSP_DEBUG_DIS ... production-signed` | production (brief A4) | debug: use the debug-signed FMC |
| `state: SEC2 queue 0 idle` | idle | busy: someone is talking to SEC2 |
| `state: GSP ...` | "not released to the CPU": nobody booted GSP, as nvidia.ko expects before its chain of trust | "running": the firmware booted GSP (GSP-RM or its own); the boot then needs a reset first (FLR? docs 6.3) |

The probe's decoding is tested without a GPU (`NvProbeTest`, with this Spark's configuration space as `sudo lspci -xxxx`
shows it and register values from the headers) on Linux and on UEFI, where the same test also runs the section on QEMU's
firmware (no NVIDIA GPU).

### nv-brief questions now answered

- **C4** (GMMU format): answered (3.4).
- **C2** (address widths): answered by the source as far as it goes (41-bit physical, 40-bit DMA cap; docs/nv.md); RMR
  and IORT limits 40 bits (4.3).
- **A3** (COT and errors): partly: the exact packet, including the GB10B MCTP word 1 (2.4), and the mailbox protocol
  (2.3); the error codes remain.
- **A5** (version coupling, init RPCs): partly: SET_SYSTEM_INFO, SET_REGISTRY, INIT_DONE, SET_GUEST_SYSTEM_INFO,
  GET_GSP_STATIC_INFO (2.2, 2.5); the rest of CPU-RM's post-init sequence remains.
- **A2** (state after UEFI, reset): partly: the driver does no reset and no GFW-boot wait, the WPR region is
  pre-initialised by the platform, FLR exists; the post-GOP state remains (step 1).
- **C1, C3** (DMA addresses, WPR2): partly (4.3: RMR identity ranges; 2.6: candidate WPR carve-out).
- **D1** (polling): yes for boot and RPCs (3.1).
- **A1, A4, B1, B2, C5, E1, F1-F3**: open; A4 can be measured in step 1 (the fuse read), F1 partly by dumping LIBOS log
  buffers raw.

## 9. Step 2: the transport seam and the structures

- **The seam** (System-NV): `NvDevice` and `NvMemory` make every RM call and mapping through an `NvTransport`
  (`alloc:client:parent:params:`, `control:client:object:params:`, `free:client:parent:`, `mapMemory:`/`mapUsermode:`,
  `unmapCpu:size:`, `mapToGpu:`/`unmapFromGpu:`, `attachGpu:`, `open`/`close`). `NvIoctlTransport` is the kernel
  module's ioctls (today's path, unchanged: `make test-nv` passes); `NvDevice open: 0 over: aTransport` takes another.
  `NvTransportTest` runs NvDevice over a fake transport that logs the calls.
- **The structures** (`NvGsp`): the C declarations of `NVDM_PAYLOAD_COT`, `GSP_FMC_BOOT_PARAMS`, `GspFwWprMeta`,
  `LibosMemoryRegionInitArgument`, `GSP_ARGUMENTS_CACHED`, `RM_RISCV_UCODE_DESC`, `msgqTxHeader`/`msgqRxHeader`,
  `GSP_MSG_QUEUE_ELEMENT`, `rpc_message_header_v03_00`, `rpc_gsp_rm_alloc_v03_00`, `rpc_gsp_rm_control_v03_00`,
  `rpc_free_v03_00` and `NV0000_ALLOC_PARAMETERS`, laid out by `NvLayout` with C's rules, and builders that fill them as
  nvidia.ko does (2.2-2.4, 3): the SEC2 message (MCTP word 1, NVDM 16r1410DE7E, the COT payload, `QUEUE_TAIL` 864), the
  FMC parameters, WprMeta for GB10B, LIBOS regions and ids (`'RMARGS'` = 16r524D41524753), the GSP arguments, radix-3
  tables (`radix3Counts: 74985472` = 1, 1, 36, 18307 pages), RPC headers and the three RM messages, the queue checksum.
- **Byte for byte**: `tools/nv-gsp-layouts.sh` compiles a program against open-gpu-kernel-modules at 580.178.04 that
  prints `sizeof` and every member's `offsetof`/size of those structures, and the constants used, into
  `src/Tests-NV/NvGspLayouts.st` (generated; rerun when the driver version moves). `NvGspLayoutTest` requires NvGsp's
  layouts and constants to equal them; `NvGspTest` checks each builder's bytes at those offsets.
- **The queues and the transport**: `NvGspQueues` is the shared region (page table, command and status queues),
  `NvGspEndpoint` one side of it (send: elements with checksum, sequence number and entry count, wrapping the ring;
  receive: checks both), `NvGspTransport` NvDevice's RM calls as RPCs over the CPU endpoint, ringing a doorbell block
  (on the GB10: `NV_PGSP_QUEUE_HEAD(0)` = 0) and polling for the reply, keeping events. It picks handles as a client RM
  does and refuses, saying which step does them, the controls whose parameters point at other memory (class list, GR
  info: FINN serialization, step 4) and the mappings (client-side RM, step 5).
- **The fake GSP** (`NvFakeGsp`, Tests-NV) is GSP-RM's side over the same memory: it makes the status queue as GSP does,
  checks every message, and answers allocs, controls and frees. `NvGspTransportTest` runs the transport against it:
  headers and page table, an RPC's element as it sits in the queue, 150 calls around the 63-entry ring, a two-entry
  message, events before a reply, errors, and `NvDevice open:over:` the GSP transport up to the class list.

All of these tests need no GPU and run in `make test-core` and, in QEMU, `make test-uefi`.

## 10. Step 3 groundwork: the boot, against a fake GB10

`NvGspBoot` (System-NV) is the boot of section 2 as code: `prepare` (all of 2.2 in DMA memory: boot loader, radix-3
image, signature, FMC, the seven LIBOS log buffers of a release build on GB10B, LOGINIT, LOGINTR, LOGRM, LOGMNOC, LOGDBG,
LOGROOT, LOGKRNL, the queues, the system heap, GSP_ARGUMENTS_CACHED, the LIBOS arguments ending in RMARGS, WprMeta with
the 133 MB WPR heap of GB10B, the FMC parameters, the SEC2 message), `check`, `sendChainOfTrust`, `waitForRelease`,
`startRiscv` and `waitForInitDone` (the register sequence of 2.3, each wait with the 4 s default and, when it runs
out, the mailboxes), then an `NvGspTransport` on the queues whose doorbell writes `NV_PGSP_QUEUE_HEAD(0)`. `queue:`
puts RPCs in the command queue before the boot as nvidia.ko does with SET_SYSTEM_INFO and SET_REGISTRY.

New facts from the source on the way **[src]**: the WPR heap (`gspFwHeapSize`) on GB10B is 22 MB (LIBOS 3 bare-metal OS
carveout) + 14 MB + 1 MB (96 KB a GB, 1 GB without video memory) + 96 MB (48 KB × 2048 channels), clamped to 88-280 MB:
133 MB (`_kgspCalculateFwHeapSize`, kernel_gsp.c 5542-5590; gsp_fw_heap.h 32-110); LIBOS 3 logs as listed above with the
kernel's (kgspHasLibosKernelLogging is true for GB10B; kernel_gsp.c 3152-3240), each buffer holding its put pointer and
its pages' addresses (3070-3105); `bDmemStack` is true by default (4539); nvidia.ko reads `EMEMC(0)` back after the words
and checks it advanced by their count (kernel_sec2_gb10b.c 182-210).

Safety, before anything is written: `check` refuses another chip (`NV_PMC_BOOT_42` not 16r1AB) and a GSP that SEC2
does not hold (`HWCFG2` not the PRI error: someone booted it), and the SEC2 queue must be idle. On the GPU the registers
are an `NvBar0` on the PciDevice: it writes only the registers of the boot's write list (EMEMC/EMEMD, SEC2 queue 0, FALCON_OS,
the GSP doorbell) and refuses any other before it happens; `NvBar0 on: gpu dryRun: true` records the writes without
making them, and `NvGspBoot dryRun` goes as far as the chain of trust with it.

Tested against `NvFakeGb10` (Tests-NV): SEC2's EMEM channel and queue, a SEC2 that checks the message, the FMC's SHA-384,
the FMC parameters, WprMeta, the boot loader, the radix-3 image, the LIBOS and GSP arguments and the queues' page table;
the FMC's lockdown with its parameters' address in the mailboxes; GSP-RM (NvFakeGsp) starting when FALCON_OS is written,
reading the queued RPCs and sending GSP_INIT_DONE. `NvGspBootTest`: the 221 writes in order, what the fake saw, RPCs
before and after the boot, the refusals before any write, a bad hash, an FMC error, no GSP_INIT_DONE, the wrong firmware
version, the write list and the dry run.

On the dedicated Spark (once the firmware loads, step 3 next), the first run is the dry run:

	d := PciDevice in: Firmware current detect: [:p | NvProbe isNvidiaGpu: p].
	(NvGspBoot registers: (NvBar0 on: d dryRun: true) memory: (NvPciDmaMemory on: d) firmware: aFirmware) dryRun

It reads registers and allocates DMA memory but writes nothing to the GPU. Open for the real run: `PciDevice allocate:`
takes memory below 4 GB (about 600 MB here: the 512 MB system heap, the 75 MB image), and the GPU must master the bus
(the probe's `command` line shows whether the GOP driver left it on).

## 11. The firmware for the image

`tools/nv-gsp-firmware.sh OUTDIR` puts what a GB10 GSP boot needs in a directory, for a volume the UEFI image mounts (an
ext4 such as the Spark's own DGX OS root, or the ESP): `gsp_ga10x.bin` copied from the installed driver (`GSP_BIN` to
take it from elsewhere; its `.fwversion` must be 580.178.04), and under `gb10b/` the arrays nvidia.ko is built with, cut
from open-gpu-kernel-modules' generated bindata sources at the 580.178.04 tag: `fmc-prod.{image,hash,sig,pkey}`,
`fmc-debug.*`, `boot-prod.{image,desc}`, `boot-debug.*`, and `SHA256SUMS`. It ships nothing: the repository holds the
tool, not the files (section 1.3). On this Spark:

	3b89a63f2e7a0b496113d6e727564e902456fd81017b21d35d3eaba76b24dab2  gsp_ga10x.bin
	8371a29f1c68da89b73bdc87af477c37f0b4e05939c58379d0e3d29efc5575b5  gb10b/boot-debug.desc
	709b88a88fc7ae9bd56b010bcc0a8269d4d40b3c0454aa5b366e8d562d83a404  gb10b/boot-debug.image
	8371a29f1c68da89b73bdc87af477c37f0b4e05939c58379d0e3d29efc5575b5  gb10b/boot-prod.desc
	427a691d8453f02548d395f40ac900eb0d5b8ea864e8f14f958eef890ba400a2  gb10b/boot-prod.image
	155a0cc3d8eb6b2446b09ecf6d7ade4dd20dc14387cbb9574f49f3cfb3781a95  gb10b/fmc-debug.hash
	51a665a76e354a15009ca506958b6092377843ae50a97fb1ccf0612da0d05cf5  gb10b/fmc-debug.image
	7b3d6981aad093ee023a8ceb67b686dbb7c1c72acd97db3107aff59edd2c814c  gb10b/fmc-debug.pkey
	15206650aff639d2c2394348565bc864608d390e82732770c79bd18c50943c57  gb10b/fmc-debug.sig
	f0389f3a9ce3bb6093e80bfc924bbe2a4ece0199b080a37f64bc1fef63f7500c  gb10b/fmc-prod.hash
	b13ead4b9a6b8a0d268f3094cc4f4521d6be8a9a525edbc9a8f3f397c86f1f2e  gb10b/fmc-prod.image
	e9bbc669c27ad8827b5bbc2b2f52fdb47718659a651088869a5f3b11d2df7816  gb10b/fmc-prod.pkey
	9db429257a18e7c5c1a3df185001c671e21bec4e94c719a574d2ce72e2e07272  gb10b/fmc-prod.sig

Found on the way **[src, obs]**: the FMC archives' `UCODE_HASH` is the SHA-384 of their `UCODE_IMAGE` (the tool checks it;
NvFakeGb10's SEC2 checks the same); the images are stored uncompressed, but the boot loader's descriptors are raw deflate
(28 bytes for 84; bindata's `utilGzAllocate`), which the tool inflates; prod and debug boot loaders differ, their
descriptors do not: version 5, manifest 0 + 0xA00, monitor data 0xA00 + 0xA600, monitor code 0xB000 + 0x24D00, monitor
enabled, and `appVersion` 0, so `FALCON_OS` is written 0 on GB10B.

In the image, `NvGspFirmware fromDirectory: '/mnt/nv-firmware' debug: false` loads it (`NvElf` takes `.fwimage`,
`.fwversion` and `.fwsignature_gb10y` from gsp_ga10x.bin; `debug:` as the probe's fuse line says) and `problems` lists
what is wrong with it. Loaded from this Spark's files and booted against NvFakeGb10, the whole path runs: the real FMC
passes the fake SEC2's hash check and the real 75 MB GSP-RM image comes back whole through its radix-3 tables (17
buffers, 74,692 KB with a token heap). `NvGspFirmwareTest` (everywhere) uses a synthetic gsp_ga10x.bin;
`NvGspFirmwareFileTest` (`make test-nv`) the installed one.

## 12. What GSP-RM asks of the CPU during the boot, and the init RPCs

- **The CPU sequencer** (`NvGspSequencer`): GSP_RUN_CPU_SEQUENCER events carry `rpc_run_cpu_sequencer_v17_00`
  (`bufferSizeDWord`, `cmdIndex`, an 8-word save area, the command words; g_rpc-structures.h 1535-1541), run as
  `kgspExecuteSequencerBuffer_IMPL` does (kernel_gsp.c 5297-5438, rmgspseq.h): REG_WRITE, REG_MODIFY (clear mask, or
  value), REG_POLL (timeout in µs, 0 the default; on timeout its error code), DELAY_US, REG_STORE; no reply goes back
  **[src]**. The falcon operations (CORE_RESET, CORE_START, CORE_WAIT_FOR_HALT, CORE_RESUME: `kflcnReset`, `kflcnStartCpu`,
  `kflcnWaitForHalt`) are not done yet and stop the boot with an error that names them; whether a cold boot on GB10 sends
  any is for the dedicated Spark to show (they serve suspend and resume on Hopper) **[inf]**. NvGspBoot runs the sequencer
  for every such event while it waits for GSP_INIT_DONE; its writes go through `NvBar0 sequencerWrite32:value:` (outside
  the boot's write list, as nvidia.ko does them, recorded, not made in a dry run).
- **LIBOS logs**: `logPutPointers` (how many words each of the seven buffers holds) and `logWords:` (the raw records)
  read what GSP-RM wrote; decoding needs `gsp_log_ga10x.bin`'s `.fwlogging` sections, which DGX OS does not ship
  (liblogdecode.c: records start with a metadata address into them) **[src]**.
- **GSP_SET_SYSTEM_INFO** (`NvGsp systemInfoBar0:domain:bus:devfn:deviceVendor:subsystem:revision:`, `setSystemInfo:`):
  `GspSystemInfo` (936 bytes) as `rpcGspSetSystemInfo_v17_00` fills it (rpc.c 10493-10657): BAR0's address,
  `nvDomainBusDeviceFunc` (domain 63:32, bus 15:8, devfn 7:0: `gpuEncodeDomainBusDevice`), the id words as read from
  configuration space (kern_gpu_gb100.c 950-967), the configuration mirror at BAR0 16r92000 + 16r1000
  (`kbifGetPciConfigSpacePriMirror_GH100`, which GB10B uses; gh100 dev_xtl_ep_pri.h 26), FLR, a 64-bit BAR0 and 4 KB pages.
  Left zero, to settle on the dedicated Spark: what nvidia.ko takes from Linux and the platform (`maxUserVa`, the
  chipset's `clPdbProperties`/`Chipset` and bus infos, `acpiMethodData`, `bIsPrimary`, `sysTimerOffsetNs`,
  `pcieConfigReg.linkCap`, `consoleMemSize`) **[inf]**.
- **SET_REGISTRY** (`NvGsp registry:`, `setRegistry:`): a `PACKED_REGISTRY_TABLE` laid out as `RmPackageRegistry` does
  (registry.c 628-700): header, 16-byte entries, then the names; DWORD keys only so far. With no keys `RmPackageRegistry`
  answers NV_WARN_NOTHING_TO_DO; whether nvidia.ko then sends the RPC at all is open **[inf]**.
- `NvGspBoot queueSystemInfo:registry:` queues both before the boot. All layouts (GspSystemInfo, the registry structs,
  the sequencer RPC, the opcodes) are in `NvGspLayouts`, so `NvGspLayoutTest` checks them against the compiler too
  (GspSystemInfo's header needs RM's port library configured: tools/nv-gsp-layouts.sh does it).

## 13. The hosted loop: PciDevice over VFIO

`VfioPciDevice` (System-Devices) is a `PciDevice` whose function Linux gives to user space through VFIO: the reading and
driving protocol the firmware's PCI I/O gives on UEFI (`config:width:`, `barResource:`, `mem32At:bar:`,
`mem32At:bar:put:`, `enable`, `allocate:`, `deviceAddress:`, `release`), so `NvProbe`, `NvBar0`, `NvPciDmaMemory`
and `NvGspBoot` run over it unchanged (section 6.1's main loop). It talks to the kernel through `PosixDevice` (ioctl,
mmap, and pread/pwrite, primitives added for it):

- `open:` (Documentation/driver-api/vfio.rst's order): `/dev/vfio/vfio`, `VFIO_GET_API_VERSION` (0),
  `VFIO_CHECK_EXTENSION` (Type1 v2, else Type1), `/dev/vfio/<group>` (the group from
  `/sys/kernel/iommu_groups/*/devices`), `VFIO_GROUP_GET_STATUS` (viable), `VFIO_GROUP_SET_CONTAINER`,
  `VFIO_SET_IOMMU`, `VFIO_GROUP_GET_DEVICE_FD` ("000f:01:00.0"), `VFIO_DEVICE_GET_INFO`, the configuration region's
  `VFIO_DEVICE_GET_REGION_INFO`.
- Configuration space: pread/pwrite of the configuration region (index 7). BARs: each memory BAR's region mmap'd shared
  on first use, registers read and written there (a barrier before each store, so CPU writes to DMA memory reach the GPU
  before a doorbell); pread/pwrite where the region cannot be mapped.
- DMA: anonymous memory (`mmap` with `MAP_ANONYMOUS`, zeroed) mapped read-write at IOVAs from 4 GB up
  (`VFIO_IOMMU_MAP_DMA`), skipping the group's `reserved_regions` and staying below 2^40; `deviceAddress:` answers the
  IOVA. So the GSP boot's ~600 MB fit, which `PciDevice allocate:` below 4 GB does not promise (section 10).
- `reset`: `VFIO_DEVICE_RESET` (FLR on this GPU), only when called. No interrupts: everything polls.
- `VfioPciDevice availability`: the container's API version and IOMMU types, read only (no group opened).

The structures (`vfio_group_status`, `vfio_device_info`, `vfio_region_info`, `vfio_iommu_type1_info`,
`vfio_iommu_type1_dma_map`, `vfio_iommu_type1_dma_unmap`) and the numbers are checked against the C compiler:
`tools/vfio-layouts.sh` writes `VfioLayouts` from `linux/vfio.h` and `VfioLayoutTest` compares. `VfioFake` (Tests-Devices)
is VFIO without a kernel: `VfioPciDeviceTest` checks the exact ioctl sequence with each structure's bytes, configuration
space, BARs through mmap and through pread/pwrite, IOVAs past reserved regions, release in reverse order, the refusals;
`NvVfioTest` holds this Spark's configuration space and an unbooted GB10B's registers in the fake's BAR0 and runs
`NvProbe` (the same lines as on UEFI), `NvBar0` (writes in the mapping, refusals), `NvPciDmaMemory` and the GSP boot's
dry run (every buffer VFIO-mapped, BAR0 untouched). **All of this is verified against the fake only.**

On this (shared) Spark, read only **[obs]**: `/dev/vfio/vfio` answers API version 0 with Type1, Type1 v2 and no-IOMMU
(kernel 7.0.0-1024-nvidia: the container is iommufd's compatibility one, `CONFIG_VFIO_CONTAINER` unset,
`CONFIG_IOMMUFD_VFIO_CONTAINER=y`, `CONFIG_VFIO_DEVICE_CDEV=y`). The GPU's group 20 has these `reserved_regions`:
`0x08000000-0x080fffff msi`, `0xa1600000-0xb97fffff direct`, `0x280000000-0x302ffffff direct` (the IORT RMRs, 4.3,
not relaxable). **Risk** **[inf, strong]**: Linux refuses to switch a device with non-relaxable direct regions to a
blocking domain ("Firmware has requested this device have a 1:1 IOMMU mapping, rejecting configuring the device without
a 1:1 mapping", iommu.c, since 6.x), and taking a group's DMA ownership for VFIO (`VFIO_GROUP_SET_CONTAINER`, or binding
the cdev to iommufd) does exactly that. So `open:` will most likely fail on the GB10 with EINVAL at
`VFIO_GROUP_SET_CONTAINER`; its error says so, and the kernel log (`dmesg`) has the line above. Checking that is the first thing to do on the dedicated Spark
(docs/nv-dayone.md 2, with `tools/nv-vfio.sh`).

## 14. Steps 4-6 against the fake GSP: the client side of RM

`NvGspTransport`, given `memory:` (an `NvDmaMemory`; `NvGspBoot`'s transport gets the boot's) and `bar0:` (BAR0's CPU
address), does what nvidia.ko's CPU-RM does itself (3.3), so `NvDevice`, `NvMemory`, `NvChannel` and `NvCompute` run
over it unchanged. The routing comes from the NVOC export tables: none of the controls NvDevice and NvChannel make is
`RMCTRL_FLAGS_ROUTE_TO_PHYSICAL` (0x40). GPU_GET_ID_INFO_V2 is 0x109 (`g_client_resource_nvoc.c` 815), GET_CLASSLIST
0x10b (`g_device_nvoc.c` 185), GR_GET_INFO 0x118 (`g_subdevice_nvoc.c` 5208), GET_WORK_SUBMIT_TOKEN 0x10008
(`g_kernel_channel_nvoc.c` 543), GPFIFO_SCHEDULE 0x10008 (`g_kernel_channel_group_api_nvoc.c` 215) and
DMA_SET_PAGE_DIRECTORY 0x14004 (`g_device_nvoc.c` 890). CPU-RM handles each of them and forwards what it needs **[src]**.

- **Step 4, RM objects.** Allocs and frees are GSP_RM_ALLOC/FREE, as CPU-RM forwards them. GPU_GET_ID_INFO_V2 is
  answered locally (one GPU, instance 0). The two pointer controls are sent as their flat forms, GET_CLASSLIST_V2
  (0x800292, 200 classes inline) and GR_GET_INFO_V2 (0x20801228, 58 `{index, data}` pairs inline), and the answers
  are copied into NvDevice's buffers. **[inf]**: CPU-RM answers both from its own data, the class database
  (`device_ctrl.c` 60-95) and GR static info (`NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_GET_INFO`, `kernel_graphics.c`
  1231). Whether GSP-RM answers the V2 forms when they are sent to it directly is the first step-4 question for the
  dedicated Spark.
- **Step 5, memory and VA.** An `NV01_MEMORY_SYSTEM` alloc becomes a DMA buffer plus `ALLOC_MEMORY`
  (`rpc_alloc_memory_v13_01`: class `NV01_MEMORY_LIST_SYSTEM` 0x81, OS02 flags contiguous|PCI|cached 0x1000). Since the
  memdesc is contiguous, a GSP client sends one PTE, the page number (`rpc.c` 3458-3500, `_issuePteDescRpc`
  2252-2310), and the header length counts it **[src]**. A `FERMI_VASPACE_A` is forwarded and gets an `NvGmmu`: GMMU v3
  tables in DMA memory (PD4 at bit 56 with 2 entries, PD3, PD2, PD1, dual PD0, 4 KB PTs; 3.4). Its root goes to GSP-RM
  with `NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY` (0x801813, aperture SYSMEM_COH). `mapToGpu:` writes PTEs at VAs from
  8 GB up. The entries:
  - PDE: aperture 2 (coherent sysmem), PCF 3 (uncached, no ATS), address 51:12.
  - Dual PDE: small half at 66:65, 69:67, 115:76; big half invalid.
  - PTE: valid, aperture 2, PCF 1 (regular RW atomic uncached), kind 0, address 51:12 (`dev_mmu.h` 53-188).
  - The PCF choices are **[inf]**.
- **Step 6, channel and launch.** A GPFIFO alloc gets the descriptors CPU-RM fills on a GSP client (`kernel_channel.c`
  2750-2830): `instanceMem` (a 4 KB block of its own, `NV_RAMIN_ALLOC_SIZE`), `ramfcMem` at the block's start,
  `userdMem` (hUserdMemory[0] + userdOffset[0], `NV_RAMUSERD_CHAN_SIZE` 512) and `errorNotifierMem`, all ADDR_SYSMEM
  (1, `g_mem_desc_nvoc.h` 115). The usermode page is BAR0 + 0xB80000 (`NV_VIRTUAL_FUNCTION_FULL_PHYS_OFFSET`, gb100
  `dev_vm.h` 39; GB10B publishes no `dev_vm.h`, **[inf]**), with the doorbell at 0x90. NvChannel and NvCompute
  then work as on Linux.
- **Byte for byte**: all six new structures (`rpc_alloc_memory_v13_01` 56 B, `NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS`
  32, `NV_MEMORY_DESC_PARAMS` 24, `NV_CHANNEL_ALLOC_PARAMS` 368, `NV0080_CTRL_GPU_GET_CLASSLIST_V2_PARAMS` 804,
  `NV0080_CTRL_GR_GET_INFO_V2_PARAMS` 488) and 70 constants, including every GMMU v3 field's bit positions, are in
  `NvGspLayouts` from `tools/nv-gsp-layouts.sh` and checked by `NvGspLayoutTest`.
- **Tests, verified only against `NvFakeGsp`** (`NvGspClientTest`). They check the PTE and PDE words against
  hand-computed `dev_mmu.h` values, NvGmmu's levels, and ALLOC_MEMORY and SET_PAGE_DIRECTORY bytes. Then NvDevice opens
  over the GSP transport: classes, `smVersion` 16rA04, 48 SMs, the page directory GSP-RM got. The fake then plays the
  GPU through the tables in memory, with its own GMMU walk:
  - NvMemory is reached through the page tables.
  - A channel carries its descriptors, and fences come back as the fake host's semaphore releases.
  - `NvCompute run:` of the cubin's `fill` launches: the fake reads the QMD's constant bank 0 address and the
    parameters at 16r380, and writes what `fill` would.

  None of GSP-RM's or the GPU's real behaviour is checked beyond the headers.

Open for the dedicated Spark (the 580 source names them; none is done):
- `SET_GUEST_SYSTEM_INFO` and `GET_GSP_STATIC_INFO` after GSP_INIT_DONE (`kernel_gsp.c` 4263-4275). The static info
  carries `hInternalClient/Device/Subdevice`, the handles of the internal controls below.
- CPU-RM's internal static queries, sent to GSP-RM on the internal client (the `NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_*`
  family: GET_INFO, GET_CONTEXT_BUFFERS_INFO `kernel_graphics.c` 749, GET_CAPS, GET_GLOBAL_SM_ORDER,
  GET_FLOORSWEEPING_MASKS, GET_PPC_MASKS, GET_ZCULL_INFO, GET_ROP_INFO, GET_FECS_*, GET_PDB_PROPERTIES, the
  SM_ISSUE_* ones; `NV2080_CTRL_CMD_INTERNAL_FIFO_GET_NUM_CHANNELS` `kernel_fifo.c` 1328).
- GR context buffers and their promotion (`NV2080_CTRL_CMD_GPU_PROMOTE_CTX`, `kernel_graphics_context.c` 2174), which
  a compute object needs before its first launch.
- The channel group's method buffers (`mthdbufMem`, left 0).
- The PDEs GSP-RM keeps for itself (`NV90F1_CTRL_CMD_VASPACE_COPY_SERVER_RESERVED_PDES`, `gpu_vaspace.c` 4038-4110),
  and TLB invalidation after unmapping.
- The work submit token: CPU-RM makes it from the channel id and runlist (`kfifoGenerateWorkSubmitTokenHal`). The fake
  answers `16r40000000 + n`.

The order of the day-one experiments, with what to expect from each, is docs/nv-dayone.md 5-6.
