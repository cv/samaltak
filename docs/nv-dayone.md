# Day one on the dedicated DGX Spark: GSP from the hosted image, then bare metal

The runbook for cv/samaltak#20 on a Spark nobody else uses. Everything before this was built and tested against fakes
(docs/nv-gsp.md 10-14). Each step here is the first contact with the real GB10. Its order goes from read-only to
writing: probe, dry run, boot, then the RM objects, memory and channels of steps 4-6. First hosted (Linux on the
Spark, the GPU handed to VFIO, the Debugger at hand), then the same milestones bare metal from a USB stick.
Write down every line the steps print: they are what the issue's next comments report.

## 0. Before you start

- A **dedicated** Spark. None of this runs on the shared one, whose GPU serves the display and other users
  (`tools/nv-vfio.sh` refuses `bind` without `NV_VFIO_DEDICATED=yes`).
- This repository built on it (`make`), and the firmware in a directory: `tools/nv-gsp-firmware.sh ~/nv-firmware`
  (gsp_ga10x.bin from the installed 580.178.04 driver plus the GB10B FMC and boot loader cut from the open driver's
  sources). Check `SHA256SUMS` against docs/nv-gsp.md 11.
- A serial console (section 3), a USB stick for the bare-metal part, and a second machine to watch from.
- `make test-nv` passing on it with nvidia.ko bound: the GPU and the driver are healthy before anything is changed.

## 1. Safety

- **Never write the SPI flash or the VBIOS.** Nothing in Samaltak can: no code opens `/dev/mtd*`, runs a flasher or
  writes a ROM BAR. Do not add any.
- **Register writes** go through `NvBar0`. It writes only the boot's six registers: SEC2 `EMEMC(0)` 0x840AC0,
  `EMEMD(0)` 0x840AC4, `QUEUE_TAIL(0)` 0x840C04, `QUEUE_HEAD(0)` 0x840C00, GSP `FALCON_OS` 0x110080, and the doorbell
  `NV_PGSP_QUEUE_HEAD(0)` 0x110C00. Any other write is refused before it happens.
  - The exception is the writes GSP-RM asks for itself through `GSP_RUN_CPU_SEQUENCER` (`sequencerWrite32:value:`).
    They are recorded in `writes`; read them after every boot.
  - `NvBar0 on: d dryRun: true` records without writing. Always run the dry run first.
- **Other writes**:
  - Configuration space gets one write, the command register's memory and bus-master bits (`d enable`).
  - Steps 5-6 write page tables, instance blocks and pushbuffers in **system** memory (DMA buffers).
  - Step 6 writes the usermode doorbell in BAR0 (0xB80090), which is not in NvBar0's list: it is NvChannel's store,
    as on Linux.
- **Resets** happen only when you call them: `VfioPciDevice reset` (FLR). Nothing resets on its own.
- **One attempt at a time.** Before retrying, read the mailboxes (the error says them) and the LIBOS put pointers.

## 2. Handing the GPU to VFIO

`tools/nv-vfio.sh status` (read only) shows:
- the GPU's driver (nvidia) and its IOMMU group (20 on the shared Spark), and the group's other functions and their
  drivers (all must be vfio-pci's or none);
- the group's reserved regions;
- the VFIO devices, and who has `/dev/nvidia*` open.

`sudo -E NV_VFIO_DEDICATED=yes tools/nv-vfio.sh bind`:
1. stops display-manager, nvidia-persistenced and the DCGM/fabric-manager services that are running (remembered in
   `/run/nv-vfio.stopped`);
2. unloads nvidia_drm, nvidia_modeset and nvidia_uvm, and unbinds nvidia;
3. binds vfio-pci (`driver_override`, `drivers_probe`), checks that the group is viable and gives `/dev/vfio/<group>` to
   you.

`... tools/nv-vfio.sh unbind` reverses it: vfio-pci off, the override cleared, nvidia reprobed and its modules and
services back, then `nvidia-smi -L`.

**The first check, before any experiment: will the kernel give the GPU's DMA to VFIO at all?** On the shared Spark,
group 20 has two non-relaxable `direct` reserved regions, the IORT RMRs (docs/nv-gsp.md 4.3, 13). Linux refuses to
move such a device to a blocking domain, which taking DMA ownership for VFIO does. `status` warns about it. Then:

```smalltalk
d := VfioPciDevice open: '000f:01:00.0'.
```

- **Expect, most likely**: an error at `VFIO_GROUP_SET_CONTAINER` with EINVAL, and in `dmesg`: "Firmware has
  requested this device have a 1:1 IOMMU mapping, rejecting configuring the device without a 1:1 mapping. Contact your
  platform vendor."
- **If so, stop the hosted loop there.** `unbind`, check that `nvidia-smi` is back, and report it on the issue. It is
  a question for NVIDIA / the platform vendor (is there a supported way to assign the GB10 to VFIO?), not something to
  work around. Go on with the bare-metal milestones (section 6), which need no VFIO.
- If `open:` succeeds, `d deviceInfo` (flags 3 = reset and PCI, 9 regions), `d regionInfo: 0` (BAR0: size 64 MB,
  flags with read, write and mmap: 7, or 15 with capabilities) and `d reservedRegions` are the first facts to record.

## 3. Logs

- **Serial console**: the Spark's UART at 0x16A00000 (SPCR and DBG2 name it; Linux uses it as `earlycon`). Read its
  settings from the SPCR on the dedicated Spark (`sudo cat /sys/firmware/acpi/tables/SPCR | xxd`: interface type,
  baud rate) and `dmesg | grep -i -e spcr -e earlycon -e ttyAMA`. Where the port comes out on the board is not
  documented anywhere I found: ask NVIDIA. Under UEFI the image's console goes there (docs/uefi.md, The console), so
  the bare-metal milestones log to it. Capture it on the second machine (`picocom -b <baud> /dev/ttyUSB0 | tee log`).
- **LIBOS logs** after each boot attempt, raw (decoding needs `gsp_log_ga10x.bin`, which DGX OS does not ship):
  `boot logPutPointers` (words written per buffer), and each buffer's words saved:

  ```smalltalk
  boot logPutPointers keysDo: [:name |
      File writeBytes: (ByteArray streamContents: [:s | (boot logWords: name) do: [:w | 0 to: 7 do: [:i | s nextPut: (w bitShift: -8 * i) \\ 256]]])
          to: '/tmp/gsp-', name, '.bin']
  ```
- **The kernel's**: `dmesg -w` in a second terminal through all of it (VFIO, the IOMMU and Xid lines).
- **The boot's own**: `boot log` (one line per step, with the time each wait took), `boot events`, and the
  registers' `writes`.

## 4. Recovery ladder

Take the lowest step that brings the GPU back to a known state, and note which one it took:
1. **FLR**: `d reset` (VFIO_DEVICE_RESET), then the probe again (5.1). Does SEC2 hold the GSP again (`HWCFG2` reads
   16rBADF41xx)? That answers docs/nv-gsp.md 6.3's first unknown: whether FLR brings back "accept a chain of trust".
2. **Give it back to nvidia.ko**: `d release`, `tools/nv-vfio.sh unbind`, then `nvidia-smi`, `dmesg` (Xid, GSP
   errors) and `make test-nv`. If nvidia.ko boots the GPU again, nothing is stuck.
3. **Reboot** the Spark.
4. **Power cycle**: shut down, remove power for 30 s, boot.

If step 4 does not bring `make test-nv` back, stop and report: nothing in this runbook should be able to cause that.

## 5. The experiments, hosted

Each needs the previous one to have passed. `d` is the `VfioPciDevice`, `fw` the firmware:

```smalltalk
fw := NvGspFirmware fromDirectory: '/home/<you>/nv-firmware' debug: false.   "debug: as the probe's fuse line says"
fw problems     "must be empty"
```

1. **Probe** (read only): `(NvProbe on: d) lines`. Expect what docs/nv-gsp.md 8's table expects:
   - `id 10de:2e12 rev a1`, BAR0 64 MB, memory decoding on (vfio-pci enables it);
   - `chip 16r1ab (GB10B)`, production fuse.
   - Then the new fact, the GSP's state after nvidia.ko let go: "running" or "held by SEC2". Then `d reset` and probe
     again, and record both.
2. **Dry run** (reads, allocates DMA memory, writes nothing):

   ```smalltalk
   boot := NvGspBoot registers: (NvBar0 on: d dryRun: true) memory: (NvPciDmaMemory on: d) firmware: fw.
   boot dryRun
   ```

   Expect four lines:
   - `prepared: 17 buffers, about 600000 KB`, with the 512 MB heap;
   - `checked: GB10B (NV_PMC_BOOT_42 16r1ABA1000), GSP held by SEC2`;
   - `idle SEC2 queue 0 (HEAD = TAIL)`;
   - `sent the chain of trust: 217 words, TAIL 864`.

   `boot`'s registers' `writes` holds 220 entries, none of them made. A refusal ("not held by SEC2") means step 4.1
   first.
3. **The real boot, to GSP_INIT_DONE** (the first writes):

   ```smalltalk
   d enable.
   boot := NvGspBoot registers: (NvBar0 on: d) memory: (NvPciDmaMemory on: d) firmware: fw.
   boot queueSystemInfo: (NvGsp systemInfoBar0: 16r24000000 domain: 16rF bus: 1 devfn: 0 deviceVendor: 16r2E1210DE subsystem: 16r10DE revision: 16rA1) registry: #().
   transport := boot boot.
   ```

   Take the BAR0 address and ids from the probe's lines. Expect the log to go through:
   - `end of SEC2's command handling`;
   - `release of the GSP by SEC2`;
   - `release of the RISC-V lockdown by the GSP-FMC`;
   - `GSP RISC-V active`;
   - `status queue from GSP-RM`;
   - `GSP-RM up: n events before GSP_INIT_DONE`.

   Each wait has 4 s. Record each time, `boot events` (functions), the sequencer's writes, and the LIBOS put
   pointers. Each failure names the step and shows the mailboxes:
   - SEC2 never leaving 16rC001CAFE, or HWCFG2 staying 16rBADF41xx: SEC2 refused the chain of trust. Its MAILBOX0/1
     codes are brief A3's question.
   - A non-zero GSP MAILBOX0: an FMC error code.
   - Sequencer core operations (CORE_RESET etc.): the boot stops and names them (docs/nv-gsp.md 12).
4. **GET_GSP_STATIC_INFO**: not built yet (docs/nv-gsp.md 14, open). Build its RPC from `g_rpc-structures.h` (and
   `SET_GUEST_SYSTEM_INFO` before it, `kernel_gsp.c` 4263-4275), with `GspStaticConfigInfo` added to
   tools/nv-gsp-layouts.sh. Expect an answer with rpc_result 0, and the internal client, device and subdevice handles
   (`hInternalClient`, ...), which the internal controls of step 4 need.
5. **Step 4, RM objects**:

   ```smalltalk
   transport bar0: (d bar: 0) first.
   gpu := NvDevice open: 0 over: transport.
   gpu smVersion. gpu smCount. gpu classes
   ```

   Expect 16rA04, 48, and the class list docs/nv-rm.md shows under Linux (with 16rCEC0, 16rC96F, 16rC761). A failure
   at GET_CLASSLIST_V2 or GR_GET_INFO_V2 is the open question of docs/nv-gsp.md 14: CPU-RM answers these itself, from
   its class database and the `NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_*` controls. Then those come next.
6. **Step 5, memory and VA**: `m := gpu allocate: 4096`. Expect ALLOC_MEMORY and SET_PAGE_DIRECTORY to be accepted.
   The exit test is `c := gpu newChannel. c sync`: the GPU reads its GPFIFO and pushbuffer through our page tables,
   and its semaphore release lands in memory the CPU reads (`c completedValue` = 1). A hang shows GPGet/GPPut and the
   error notifier. An MMU fault comes as an event (`transport events`). The known gaps are GSP-RM's reserved PDEs, the
   method buffers and TLB invalidation (docs/nv-gsp.md 14).
7. **Step 6, a launch**:

   ```smalltalk
   gpu newCompute run: (NvTestKernels cubin kernelNamed: 'fill') grid: 1 block: 256 arguments: {m gpuAddress. 7. 1}.
   m uint32At: 0   "7"
   ```

   The expected gap is the GR context buffers and their promotion (`NV2080_CTRL_CMD_GPU_PROMOTE_CTX`) before a compute
   object's first launch. Then Tests-NV's GPU tests over this transport.

After each experiment: `gpu close` (when open), `d release`, and a step of section 4 if the next one needs a fresh
GPU.

## 6. The same milestones bare metal, from USB

The UEFI image drives the GPU through the firmware's `PciDevice` instead of VFIO. The code above is the same, and
`d` is `PciDevice in: Firmware current detect: [:p | NvProbe isNvidiaGpu: p]`. Differences VFIO hid: the SMMU's state
under UEFI and which addresses the GPU's DMA uses (docs/nv-gsp.md 4.3, 6.2), the GPU's state after the GOP, and
`PciDevice allocate:` taking memory below 4 GB (the 512 MB heap may not fit: `sysmemHeapSize:` smaller, and note what
GSP-RM says).

1. **Probe**: `make usb-image USB_DIAG=nv`, write the stick (docs/uefi.md, Real hardware), boot from it with the serial
   console attached. Lines `diag nvidia ...` as docs/nv-gsp.md 8 expects, also in `samaltak-diag.txt` on the stick.
   This is step 1's exit test. The GOP line and the GSP's state after the firmware are the facts.
2. **Firmware on the stick**: `make usb-image USB_FILES=$HOME/nv-firmware USB_FILES_MB=160` puts the directory on an
   ext4 volume of the stick (`/mnt/<name>`: check `File mountTable` in the World). Add `USB_CONTROL=1` to drive it with
   `samaltak-ctl connect` from the second machine (docs/remote.md).
3. **Dry run, boot, steps 4-6**: as in section 5, in a Workspace of the World. Use `d` from `PciDevice in:detect:`,
   `NvPciDmaMemory on: d`, and for `bar0:` the BAR's address (`(d barResource: 0) first`: the firmware maps BARs
   where configuration space says). After each milestone, save the boot's log, events and LIBOS words to the stick's ESP
   (`/mnt/<ESP label>/`) and the serial capture. A hang needs a power cycle (no FLR from here without code for it).

## 7. What to report on the issue

Per experiment: the lines printed, the mailboxes on failure, the wait times, the sequencer's writes, the events, the
LIBOS put pointers, the recovery step it took. And on the first day especially: whether VFIO accepted the GPU (2), the
GSP's state after nvidia.ko and after FLR (5.1), and what GET_GSP_STATIC_INFO answered.

The driver's own RPC sequence on Linux would be the best reference for step 4's internal calls. nvidia.ko can log it,
but only through registry keys found in its source, not documented settings. Ask before using them.
