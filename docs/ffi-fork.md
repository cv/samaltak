# The FFI and the fork's performance primitives

Upstream's descriptor FFI ([ffi.md](ffi.md)) retired 102 numbered primitives that were thin adapters over a platform
call (files, sockets, TLS, ptys, windows, the GPU, the core's clocks, environment and bignum operations) in favour of
approved typed exports: `<approvedFFI: key symbol: ... arguments: ... result: ...>` on `FFIPrimitives` (`vm:core`)
or `SDLPlatform` (`platform`), called through a generated wrapper, and in `--jit opt` straight from a guarded send
([jit.md, Bound FFI sites](jit.md#bound-ffi-sites)). This note says what that means for the fork's own kernels and
for the plan in the primitives-vs-JIT review (crypto 640–647, PNG 207, deflate 208–211, rawBytesReplace 212,
PixelPack 213, ZRLE 214, PixelDiff 215, the byte-range compares 119/122, the devices 590–597, the NV work).

## What merged as what

- The fork's numbered primitives keep their numbers: none collides with upstream's (its new ones are 250–265; the
  retired numbers stay reserved, and the fork's 207–215 sit after the reserved guest display 200–206).
  `tests/vm/ffi_cutover.py check` passes with them in the table.
- Where upstream moved a facade the fork had changed, the fork's change follows upstream's FFI version: `File`'s
  handle operations send a handle that is a mounted volume's file (a `VolumeFile`, `FirmwareFile`) the operation before the FFI call (mounted volumes, UEFI's FAT and ext4), `TLSSocket`
  falls back to the VM's TLS engine (mbedTLS; the Smalltalk TLS before it) when `platform_tls_start` is unavailable (UEFI has no platform exports).
- The one fork change that the FFI cannot carry is uploading a texture from an address outside the heap
  (`HostFramePresenter`, `NvComputeGPU`'s back buffer): the image passes no raw pointers through the FFI, so it is
  a primitive of its own, `gpuUploadTextureAddress` (462), and `GPUPrimitives uploadTexture:bytes:...` sends an
  Integer there and a byte object to `platform_gpu_upload_texture`. Its sibling `windowPresentAddress` (463) copies a
  rectangle of such a frame into the window's SDL surface, for `HostFramePresenter` where no SDL_GPU device can be
  made (no Vulkan driver that shows on the display: lavapipe on KMS/DRM, docs/linux-appliance.md).

## Which kernels could be FFI-bound C functions

What a typed export can take: at most six native slots; scalars; read-only slices `{aByteArray. start. count}`
(two slots) of an *exact* ByteArray; writable slices for approved built-ins only; no Bitmaps or other word objects,
no Strings except as copied text, no addresses. On UEFI there is no wrapper generation: each `vm:core` export it
answers is a hand-written static wrapper (`UefiFFIStubMemory>>staticCoreEntry:signature:`), and `platform` exports
are not there at all.

| Kernel | Shape | As an export |
| --- | --- | --- |
| CRC-32, CRC-32C, Adler-32 | `(u32 crc, bytes) -> u32` | fits: 3 slots |
| cryptoFeatures | `() -> i64` | fits |
| GHASH, AES block | state/key + in + out slices | fits in 6 slots, if the state is an exact ByteArray |
| SHA-256/512 compress | word state + blocks | only with the state as a ByteArray |
| AES-CTR | key + in + out + counter | 8 slots: no, unless the counter rides in a buffer |
| ByteSearch, compare/case, bytesMismatch | Strings and ByteArrays, short calls | no: Strings are not slices, a slice Array per call costs more than the work, and baseline code compares Strings inline |
| PNG filter, PixelPack, ZRLE, PixelDiff, deflate, rawBytesReplace | Bitmaps, word tables, several outputs | no: word objects are not slices, and most take more than six slots |
| devices (open/ioctl/mmap/pread/pwrite), NV, machine | descriptors and addresses | no: addresses (upstream keeps its machine primitives 470–478 for the same reason) |

So the candidates are the checksums, `cryptoFeatures` and, with a ByteArray state, GHASH, AES block and SHA. Upstream
did the same with its bignum operations (20–31 became `integerMagnitude` exports), so moving them would follow its
structure. It is not worth doing now: each would need a static UEFI wrapper (the Smalltalk TLS runs on UEFI and is the
crypto's main user there), interpreter and baseline callers would pay the slice Arrays and the bound invocation
(upstream measured typed calls at 1.07× the numbered ones in the interpreter, 1.03× in baseline, 0.97× in opt on a
4 KB file operation), and the kernels' callers are fork-only anyway.

## Do optimized FFI calls change keep or retire?

No. An FFI-bound C function is still C in the VM: binding a kernel through the FFI changes how it is called, not
whether it is native, so it is neither a way to retire a primitive nor a reason to keep one. The review's split
stands: keep what needs hardware instructions or SIMD (crypto and CRC, ByteSearch and the string kernels, the
byte-range compares, PixelPack, PNG, rawBytesReplace, PixelRows), and retire the scalar loops (Adler-32, the token
counts, PixelDiff, then ZRLE and the matcher) only when the opt tier's loop work makes their Smalltalk fast enough,
each behind its benchmark. The optimized site removes the send and primitive dispatch (a few ns), which matters for
small calls; the fork's kernels run on kilobytes to megabytes, where it is noise.

What the FFI does change is the policy for *new* native code: a kernel with a slice-shaped signature that only opt
code calls in bulk can be a `vm:core` export instead of a numbered primitive (no number to collide, a typed C
prototype), as long as it need not run on UEFI or gets a static wrapper there.
