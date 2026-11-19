# The VM on UEFI

The headless VM runs as a UEFI application on x86-64 and arm64: no operating system, no C library, no hand-written C, no file system. It is translated from the same Lowtalk as `vm/gen`, with the `VM-UEFI` package in place of the C library and the OS. The image is everything there is (sources, fonts) and lives on a raw partition.

    make uefi                                       # $(OUT)/uefi-$(UEFI_ARCH)/esp: a boot volume; .../image.disk: the image
    make uefi-run UEFI_ARGS="--headless --eval '3 + 4'"   # boot it in QEMU with its UEFI firmware; fails unless the VM exits 0
    make test-uefi                                  # the tests that need no platform layer, there

`UEFI_ARCH` is `x86_64` or `arm64`, this machine's by default. Needs clang, ld.lld, `qemu-system-x86_64` or `qemu-system-aarch64` and the firmware for it, OVMF or AAVMF (`.agents/setup` installs x86-64's; Homebrew's `qemu` has both). For this machine's CPU QEMU runs the VM on it, with KVM where `/dev/kvm` is there, else on macOS with Hypervisor.framework (QEMU 11.0 fails at its start on macOS 26; 11.1 works); for another CPU it emulates (TCG), and the VM still boots in about 5 s.

## How

- **Translation.** `VMTranslator generateVMInto: dir os: #uefi arch: #x86_64` (or `#arm64`) translates the core's modules for every OS and `VM-UEFI`'s (docs/lowtalk.md, An OS without a C library): `UefiLibC`, `UefiLibM` and `UefiPosix` implement `LibC`, `LibM` and `Posix`; `UefiTicker` and `UefiJitPlatform` the core's `Ticker` and `JitPlatform`; `HeadlessPlatform` is the platform. What differs between the CPUs is `UefiCpu`, an arch interface (`UefiX64Cpu`, `UefiArm64Cpu`): the cycle counter, instruction cache maintenance, switching stacks, with the instructions C has no builtin for in their C preambles. Not checked in: `make uefi` translates into `$(OUT)/uefi-$(UEFI_ARCH)/gen`.
- **Compiling.** `vm/uefi.mk`: clang for `x86_64-unknown-none-elf` or `aarch64-unknown-none-elf`, freestanding, with the ABI the JIT assumes (on x86-64 System V); the firmware's functions are called through `ms_abi` function types (`UefiModule>>efi:with:...`), and `efi_main` and the timer's notification function are `ms_abi` (`<abi: 'ms_abi'>`): UEFI's convention on x86-64, nothing on AArch64, where UEFI's is the standard one. `ld.lld` links a static PIE; `UefiImageWriter` (Smalltalk) turns it into a PE32+ EFI application: one read-write-execute section (the JIT's code cache is the zero-fill array the VM reserves for it) and base relocations.
- **Boot volume.** FAT, as the firmware requires: `EFI/BOOT/BOOTX64.EFI` (`BOOTAA64.EFI`) and `samaltak.args`, the command line, one argument a line (without it: `disk: --headless`).
- **The image on disk.** `UefiImageStore`: a raw partition or disk that starts with its superblock (found among the firmware's block devices), two slots of image. The image path `disk:` reads the newest slot; a snapshot writes the other, flushes, then writes that slot's header with the next sequence number, so a crash while saving leaves the last good image. `UefiImageDisk` (Smalltalk) writes a store with the image in slot 0; `make uefi` extends it to `UEFI_DISK_MB` (512). Slots are half of what follows the first megabyte: the partition must be at least twice the image plus 1 MB.
- **Firmware services.** `UefiFirmware` (`efi_main`): first makes its image writable and executable where the firmware protects it by its sections (edk2 on AArch64 maps the one section read-only; `EFI_MEMORY_ATTRIBUTE_PROTOCOL`, which ArmVirtQemu uninstalls, else the CPU architectural protocol's `SetMemoryAttributes`), turns off the boot manager's watchdog, switches to a stack of 8 MB (the firmware's is 128 KB; the JIT's code keeps a native frame per activation), opens the volume, runs `VMMain`, and powers off with the exit status (`samaltak: exit N` on the console). Console output goes to `ConOut` (QEMU with `-nographic`: the serial port). Memory: `malloc` is the firmware's pool, `mmap` its pages (zeroed). Time: the cycle counter (`rdtsc`, `cntvct_el0`), calibrated against `Stall`; the wall clock is `GetTime` at start plus that. Timers: timer events whose notification calls `Scheduler>>tickFired:` (OVMF's timer ticks every 10 ms). Idle: `WaitForEvent` on a timer, which halts the CPU.

## Limits

- Headless only: no platform layer (window, GPU, files from Smalltalk, sockets, processes).
- Memory is physical: the heap's reservations (twice `--max-heap` plus the young space) are allocated and zeroed at start. `make uefi-run` passes `--max-heap 256` (`UEFI_HEAP_MB`) and gives QEMU 2 GB.
- One CPU, the firmware's timer resolution, its block device drivers.

## Real hardware

On a USB stick: a FAT32 partition with the contents of `$(OUT)/uefi-$(UEFI_ARCH)/esp`, and a second partition of at least twice the image plus 1 MB with `image.disk` written to its start (`dd`). Boot it on a UEFI PC (or arm64 machine) with Secure Boot off; the output is on the firmware's console.
