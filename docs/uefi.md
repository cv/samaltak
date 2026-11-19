# The VM on UEFI

The headless VM runs as a UEFI application on x86-64: no operating system, no C library, no hand-written C, no file system. It is translated from the same Lowtalk as `vm/gen`, with the `VM-UEFI` package in place of the C library and the OS. The image is everything there is (sources, fonts) and lives on a raw partition.

    make uefi                                       # $(OUT)/uefi/esp: a boot volume; $(OUT)/uefi/image.disk: the image
    make uefi-run UEFI_ARGS="--headless --eval '3 + 4'"   # boot it in QEMU with OVMF; fails unless the VM exits 0
    make test-uefi                                  # the tests that need no platform layer, there

Needs clang, ld.lld, qemu-system-x86_64 and OVMF (`.agents/setup` installs them). QEMU uses KVM when `/dev/kvm` is there; without it (TCG) the VM still boots in about 5 s.

## How

- **Translation.** `VMTranslator generateVMInto: dir os: #uefi arch: #x86_64` translates the core's modules for every OS and `VM-UEFI`'s (docs/lowtalk.md, An OS without a C library): `UefiLibC`, `UefiLibM` and `UefiPosix` implement `LibC`, `LibM` and `Posix`; `UefiTicker` and `UefiJitPlatform` the core's `Ticker` and `JitPlatform`; `HeadlessPlatform` is the platform. Not checked in: `make uefi` translates into `$(OUT)/uefi/gen`.
- **Compiling.** `vm/uefi.mk`: clang for `x86_64-unknown-none-elf`, freestanding, with the System V ABI the JIT assumes; the firmware's functions are called through `ms_abi` function types (`UefiModule>>efi:with:...`), and `efi_main` and the timer's notification function are `ms_abi` (`<abi: 'ms_abi'>`). `ld.lld` links a static PIE; `UefiImageWriter` (Smalltalk) turns it into a PE32+ EFI application: one read-write-execute section (the JIT's code cache is the zero-fill array the VM reserves for it) and base relocations.
- **Boot volume.** FAT, as the firmware requires: `EFI/BOOT/BOOTX64.EFI` and `samaltak.args`, the command line, one argument a line (without it: `disk: --headless`).
- **The image on disk.** `UefiImageStore`: a raw partition or disk that starts with its superblock (found among the firmware's block devices), two slots of image. The image path `disk:` reads the newest slot; a snapshot writes the other, flushes, then writes that slot's header with the next sequence number, so a crash while saving leaves the last good image. `UefiImageDisk` (Smalltalk) writes a store with the image in slot 0; `make uefi` extends it to `UEFI_DISK_MB` (512). Slots are half of what follows the first megabyte: the partition must be at least twice the image plus 1 MB.
- **Firmware services.** `UefiFirmware` (`efi_main`): turns off the boot manager's watchdog, opens the volume, runs `VMMain`, and powers off with the exit status (`samaltak: exit N` on the console). Console output goes to `ConOut` (QEMU with `-nographic`: the serial port). Memory: `malloc` is the firmware's pool, `mmap` its pages (zeroed). Time: the cycle counter, calibrated against `Stall`; the wall clock is `GetTime` at start plus that. Timers: timer events whose notification calls `Scheduler>>tickFired:` (OVMF's timer ticks every 10 ms). Idle: `WaitForEvent` on a timer, which halts the CPU.

## Limits

- Headless only: no platform layer (window, GPU, files from Smalltalk, sockets, processes).
- Memory is physical: the heap's reservations (twice `--max-heap` plus the young space) are allocated and zeroed at start. `make uefi-run` passes `--max-heap 256` (`UEFI_HEAP_MB`) and gives QEMU 2 GB.
- One CPU, the firmware's timer resolution, its block device drivers.
- x86-64 only. arm64 needs the cycle counter (`cntvct_el0`), instruction cache maintenance in `UefiJitPlatform`, and `-target aarch64-unknown-none-elf`; `UefiImageWriter` already writes arm64 images.

## Real hardware

On a USB stick: a FAT32 partition with the contents of `$(OUT)/uefi/esp`, and a second partition of at least twice the image plus 1 MB with `image.disk` written to its start (`dd`). Boot it on a UEFI PC with Secure Boot off; the output is on the firmware's console.
