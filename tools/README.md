# samaltak-ctl

Drives a running Samaltak image through its control service (`ControlServer`, `src/System-Remote/`). Node ≥ 18, no deps. Session: `--session` / `$SAMALTAK_SESSION`, default `samaltak`; session info lives in `$TMPDIR/samaltak-ctl/<session>.json`, the image's output in `<session>.log`.

    open [--headless] [--hidden] [--image path] [--theme t] [--port n] [--window-size WxH] [--source-dir d]
    snapshot [ref] [--depth n] [--bounds]       find <text>
    click|dblclick|rightclick <ref|x,y> [--mods Shift+Meta]
    type <ref> <text> [--end|--start|--replace] [--delay ms]   (the image types one character every ms, default 45)
    key <combo> [ref]   (Meta+p, Escape, Meta+.; Meta = platform modifier)
    drag <ref> <dx> <dy> | drag <ref> <ref>      resize <ref> <w> <h>      scroll <ref> [dy]
    select <ref> <text|all|end|from-to|line:n>  (editor selection, or list item by label)
    eval <smalltalk> [--timeout ms]    wait <json|@ref|idle|text|ms> [timeout]    bounds <ref>    state
    screenshot [ref] <path> [--scale 1|2] [--pointer]     close
    record start <out.mp4> [--size WxH] [--fps n]    record stop

Input commands (click, type, key, drag, select, scroll, resize) wait until the image has settled — no user Process runnable, the UI idle — for at most 2 s; `--settle ms` changes that limit (`--settle 0`: return at once; useful while a window computes for a long time, as nothing settles then). A target in an inactive window gets focus through a click on that window's title bar, so the caret and the selection stay where they are.

`open` starts `vm/build/samaltak <image> --control --control-port <n> --control-port-file <tmp>` (default image `build/samaltak.image`, default port: a free one) and waits until it listens. Commands the image has not registered (without a UI only ping, commands, eval, wait, state and quit exist) fail with a clear message. Exit codes: 1 error, 2 not found / wait timed out, 3 Smalltalk error (the error JSON, with stack, on stdout).

    export SAMALTAK_SESSION=remote
    samaltak-ctl open --headless
    samaltak-ctl eval '3 + 4'                    # 7
    samaltak-ctl eval '[300 factorial] fork' && samaltak-ctl wait idle
    samaltak-ctl snapshot --depth 1
    samaltak-ctl close

## Protocol

JSON lines over TCP on 127.0.0.1. Request `{"id": 1, "cmd": "eval", "source": "3+4"}`, response `{"id": 1, "ok": true, "printString": "7", "className": "SmallInteger"}` or `{"id": 1, "ok": false, "error": "…", "code": 2}`. One connection may carry many requests; they are answered in order. Commands and their arguments:

| cmd | arguments | answer |
|---|---|---|
| `ping`, `commands` | | `pong`, `commands` |
| `eval` | `source`, `timeout` | `printString`, `className`; errors: code 3, `errorClass`, `stack` |
| `wait` | `idle`, `ms`, `text`, `ref`, `gone`, … , `timeout` (10000) | `ms` |
| `state` | | `processes`, `windows`, `theme`, `idle`, … |
| `quit` | `code` | |
| `snapshot` | `ref`, `depth`, `bounds`, `maxItems` | `text` |
| `find` | `text` | `matches` [{ref, role, label}] |
| `click` | `target`, `button` (left/middle/right), `count`, `mods`, `settle` (ms, all input commands) | `at`, `settled` |
| `type` | `target`, `text`, `at` (end/start), `replace`, `delay` (ms between characters) | `typed` |
| `key` | `combo` (String or Array), `target` | |
| `drag` | `target`, `to` or `dx`/`dy`, `mods` | `from`, `to` |
| `resize` | `target`, `w`, `h` | `bounds` |
| `select` | `target`, `spec` | |
| `scroll` | `target`, `dx`, `dy` | |
| `bounds` | `target` | `x`, `y`, `w`, `h` |
| `screenshot` | `target`, `path`, `scale` (default: display scale), `pointer`, `now` | `path`, `w`, `h` |
| `record` | `action` (start/stop), `path` (FIFO or file), `w`, `h`, `fps` | `recording` / `frames` |

`record start` makes a FIFO, starts `ffmpeg -f rawvideo -pix_fmt rgba -s WxH -r FPS -i <fifo> … out.mp4` and has the image write the composited screen (downsampled on the GPU, remote pointer included) into it; `record stop` ends both. Screenshots leave the remote pointer out unless `--pointer`.

Targets are refs (`@w6.packages.kernel-numbers`, `@w6.packages#3` = 4th child) or points (`{"x":10,"y":20}` or `"10,20"`). The image side (registration API, snapshot contract, input planning) is documented in the class comments of `RemoteControl`, `RemoteSnapshot`, `RemoteInputPlanner` and `RemoteInputDevice`.

Tests: `vm/build/samaltak <image> --headless --test Tests-Remote`, `tests/remote/cli_test.sh [image]`.

## Walkthrough video

    make video     # = the three steps below, then copies the result to docs/media/walkthrough.mp4

    node tools/narrate.mjs <dir>        # ElevenLabs narration per step (eleven_v4, voice Roger; ELEVENLABS_API_KEY in .env), cached
    node tools/walkthrough.mjs <dir>    # drives a visible image through samaltak-ctl, records <dir>/raw.mp4 + captions.json
    python3 tools/compose-video.py <dir>   # caption band + narration → <dir>/walkthrough.mp4

`<dir>` defaults to `.context/video-real`. Steps, captions and spoken text: `narration.json`; each step lasts at least as long as its clip. The recording is the compositor's own output (`record start`), 1440×900 at 30 fps.
