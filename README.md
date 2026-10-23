# Samaltak

A Smalltalk-80 system with a tiny C core, green threads, and a GPU-composited UI (SDL3 + SDL_GPU on Metal). Everything above the core — compiler, class library, fonts, renderer, window system, browser, debugger, profiler, remote control — is Smalltalk, built from the text sources in `src/`.

![Walkthrough](docs/media/walkthrough.mp4)

## Build and run (macOS, Homebrew `sdl3`)

    make            # VM, seed image (boot/bootstrap.py), stage 2 → build/samaltak.image
    vm/build/samaltak build/samaltak.image

## Test

    make test       # everything: VM suite, all Smalltalk tests, GC-verified pass, platform tests, samaltak-ctl scenarios

## Remote control and the video

`tools/samaltak-ctl` drives the running image (snapshot, click, type, key, eval, screenshot, record). `make video` replays `tools/walkthrough.mjs` against the real system, records the compositor's frames, and adds captions and ElevenLabs narration (`ELEVENLABS_API_KEY` in `.env`) → `docs/media/walkthrough.mp4`.

## Docs

- `docs/design.md` — decisions and why
- `docs/implementation.md` — object format, bytecodes, image format, primitives
- `docs/ui.md` — the layers from GPU to tools
- `prototypes/` — the HTML prototypes the UI started from
