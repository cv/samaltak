# Samaltak

A Smalltalk-80 system with green threads and a GPU-composited UI (SDL3 + SDL_GPU on Metal), written entirely in Smalltalk and built from the text sources in `src/`: the compiler, class library, fonts, renderer, window system, browser, debugger, profiler and remote control, and the VM itself. The VM and its platform layer are written in Lowtalk, a subset of Smalltalk (docs/lowtalk.md): run as Smalltalk it is a simulator you can debug in the image; translated to C (`vm/gen/`) it is the VM.

![Walkthrough](docs/media/walkthrough.mp4)

## Build and run (macOS, Homebrew `sdl3`)

    make            # VM (from vm/gen), seed image (ImageBuilder in boot/seed.image), stage 2 → build/samaltak.image
    vm/build/samaltak build/samaltak.image
    make translate  # after changing the VM's Lowtalk sources (src/VM-Core, src/VM-Platform): regenerate vm/gen

## Test

    make test       # everything: VM suite, all Smalltalk tests, GC-verified pass, platform tests, samaltak-ctl scenarios

## Remote control and the video

`tools/samaltak-ctl` drives the running image (snapshot, click, type, key, eval, screenshot, record). `make video` replays `tools/walkthrough.mjs` against the real system, records the compositor's frames, and adds captions and ElevenLabs narration (`ELEVENLABS_API_KEY` in `.env`) → `docs/media/walkthrough.mp4`.

## Docs

- `docs/design.md` — decisions and why
- `docs/implementation.md` — object format, bytecodes, image format, primitives
- `docs/lowtalk.md` — the Smalltalk subset the VM is written in, its translation to C and its simulation
- `docs/ui.md` — the layers from GPU to tools
- `docs/platform.md` — the platform layer and its primitives
- `prototypes/` — the HTML prototypes the UI started from
