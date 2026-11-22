# Samaltak

A Smalltalk-80 system with green threads and a GPU-composited UI (SDL3 + SDL_GPU on Metal or Vulkan), written entirely in Smalltalk and built from the text sources in `src/`: the compiler, class library, fonts, renderer, window system, browser, debugger, profiler and remote control, and the VM itself. The VM and its platform layer are written in Lowtalk, a subset of Smalltalk (docs/lowtalk.md): run as Smalltalk it is a simulator you can debug in the image; translated to C (`vm/gen/`) it is the VM.

![Walkthrough](docs/media/walkthrough.mp4)

## Build and run

macOS on Apple Silicon (Homebrew `sdl3` and `openssl@3`), or Linux on arm64 or x86-64 (`sdl3`, `shaderc` and OpenSSL 3, e.g. `libssl-dev`; e.g. Asahi Linux, Vulkan). The JIT emits arm64 or x86-64 (docs/jit.md).

    make            # VM (from vm/gen), seed image (ImageBuilder in boot/seed.image), stage 2 → build/samaltak.image
    make run        # start it (rebuilds the image first only if src/, boot/ or the VM changed since it was built or saved)
    make translate  # after changing the VM's Lowtalk sources (src/VM-Core, src/VM-Platform): regenerate vm/gen

One `vm/gen` serves all of them: what differs per OS is in modules for one OS (`targetOS`: the ticker, the code cache's memory, `PlatformHost`), which the build picks by `uname -s`; what differs per CPU (the assembler, and the code generators' functions that use it) by `uname -m` (`targetArch`, docs/lowtalk.md). On Linux shaders are GLSL (compiled to SPIR-V with shaderc) where macOS uses MSL, and the Alt key is ⌘ (Super is the window manager's).

## Applications

Samaltak programs can also run as windows of the desktop's window manager, straight from their source (docs/apps.md). The first is the Omarchy weather card:

    bin/samaltak run apps/Weather     # a floating Hyprland window in the Omarchy theme
    bin/samaltak test apps/Weather

## Test

    make test       # everything: VM suite, all Smalltalk tests, GC-verified pass, platform tests, samaltak-ctl scenarios

## Remote control and the video

`tools/samaltak-ctl` drives the running image (snapshot, click, type, key, eval, screenshot, record). `make video` replays `tools/walkthrough.mjs` against the real system, records the compositor's frames, and adds captions and ElevenLabs narration (`ELEVENLABS_API_KEY` in `.env`) → `docs/media/walkthrough.mp4`.

For Zed syntax highlighting, install the [Smalltalk extension](tools/zed-smalltalk/README.md).


## Docs

- `docs/design.md` — decisions and why
- `docs/implementation.md` — object format, bytecodes, image format, primitives
- `docs/lowtalk.md` — the Smalltalk subset the VM is written in, its translation to C and its simulation
- `docs/ui.md` — the layers from GPU to tools
- `docs/graphics-damage.md` — how much of each frame changes on the four presentation paths (SDL_GPU, NV, UEFI, VNC), measured with DamageProbe and StageTimes; the design of damage-limited composition and presentation
- `docs/platform.md` — the platform layer and its primitives
- `docs/apps.md` — applications as Linux windows, run from source (AppWorld, Application, OmarchyTheme, apps/Weather)
- `docs/uefi.md` — the headless VM as a UEFI application (bare metal, QEMU)
- `docs/remote.md` — the control service's token: samaltak-ctl open and connect, a bare-metal machine from another one; the remote display (VNC): starting it, connecting from Screen Sharing and TigerVNC, security
- `docs/nv-gpu.md` — NvComputeGPU (`--gpu nv`): the World rendered on the NVIDIA GB10 by the raster kernels through System-NV, presented through SDL_GPU; tests and frame times
- `docs/nv-kernels.md` — the Renderer's raster work as CUDA kernels for the NVIDIA GB10, their ABI, make test-nv
- `docs/tls.md` — the TLS 1.3 and 1.2 client in Smalltalk (HTTPS on UEFI), and tools/tls-survey against real servers
- `docs/crypto.md` — hashes, MACs, ciphers and randomness in Smalltalk (System-Crypto)
- `docs/agent.md` — the in-image coding agent: conversations, tools, the OpenAI and Anthropic Messages providers, API keys from the host
- `docs/github.md` — source changes as GitHub branches, commits and pull requests through the REST API (GitHubClient, SourceFiler's GitHub store)
- `docs/certificates.md` — DER, X.509 certificates, trust anchors and chain validation in Smalltalk (System-TLS)
- `docs/storage.md` — block devices and the read-only ext2/3/4 reader
- `docs/nv-rm.md` — System-NV: compute kernels on an NVIDIA GPU (the GB10) through the open kernel module's RM ioctls, from Smalltalk
- `docs/files.md` — files on UEFI: the firmware's block devices, ext4 volumes mounted read-only under `/` and `/mnt`
- `docs/nv.md` — the NVIDIA GB10 through the open kernel module's RM ioctls, without NVIDIA's libraries: objects, structs, memory, channels, QMDs, cubins (`tools/nv-probe.py` runs it)
- `prototypes/` — the HTML prototypes the UI started from
