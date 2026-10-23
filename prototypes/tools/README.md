# samaltak-ctl

Drives the classic prototype through its control service (`window.SamaltakCtl`, `1-classic/remote.js`) via `agent-browser`. Input is synthesized as real DOM events at the target's on-screen point. Node ≥ 18, no deps. Session: `--session` / `$SAMALTAK_SESSION`, default `samaltak`.

    open [--theme t] [--type y] [--headed]      snapshot [ref] [--depth n] [--bounds]     find <text>
    click|dblclick|rightclick <ref|x,y>         type <ref> <text> [--end|--start|--replace]
    key <combo> [ref]   (Meta+p, Escape, Meta+.; Meta = platform modifier)
    drag <ref> <dx> <dy> | drag <ref> <ref>      resize <ref> <w> <h>      scroll <ref> [dy]
    select <ref> <text|all|end|from-to|line:n>  (editor selection, or list item by label)
    eval <smalltalk>    wait <json|@ref|idle|text|ms> [timeout]    bounds <ref>    state
    screenshot [ref] <path>                     close

Refs (`@w1.packages.kernel-numbers`) are stable per widget; `@list#3` picks the 4th item. Widgets with `data-role` / `data-label` appear automatically. Exit codes: 1 error, 2 not found / wait timed out, 3 Smalltalk error.

    export SAMALTAK_SESSION=remote
    samaltak-ctl open
    samaltak-ctl snapshot --depth 1
    samaltak-ctl select @w6.packages Kernel-Numbers
    samaltak-ctl type @w1.text '3 + 4' --end && samaltak-ctl key Meta+p
    samaltak-ctl snapshot @w1        # editor … sel=… / selection "7"
    samaltak-ctl click @desktop && samaltak-ctl click @menu.transcript
    samaltak-ctl eval "[1 to: 50 do: [:i | 300 factorial]] fork" && samaltak-ctl wait idle
    samaltak-ctl screenshot @w6 /tmp/browser.png

## Walkthrough video

    node walkthrough.mjs <dir>       # drives the Debugger/Profiler demo, records <dir>/raw.webm + captions.json
    node narrate.mjs <dir>           # ElevenLabs narration per step (ELEVENLABS_API_KEY in .env), cached
    python3 compose-video.py <dir>   # caption band + narration → <dir>/walkthrough.mp4

Run `narrate.mjs` before `walkthrough.mjs` so each step lasts as long as its narration. Steps and spoken text: `narration.json`. Result: `docs/media/prototype-walkthrough.mp4`.
