# How much of a frame changes: damage on the World's four presentation paths

Graphics plan, point 1 (damage-limited composition and presentation: redraw and present only what changed), step one:
measure before building. What share of frames are full redraws and what share small changes, where the bytes and the
time go, on (a) hosted Linux with SDL_GPU, (b) hosted `--gpu nv` (NvComputeGPU, HostFramePresenter), (c) the UEFI World
under QEMU/KVM at 1920x1080 on virtio-gpu (FirmwareScreen's shadow copy and the firmware's Blt) and (d) what QEMU's VNC
server sends. Measured on the DGX Spark (GB10), November 2026.

## Headline

- **Almost every frame changes almost nothing.** Over 4,100 presented frames of nine scripted interactions (idle with a
  blinking caret, typing in a Workspace, scrolling a browser list, hovering it, dragging a window, opening the Agent
  window, the Agent streaming 150 text deltas) 89–100 % of the frames of every scenario but two damage less than 1 % of
  the 1920x1080 screen (median 2.5–3.8 k pixels in 16-pixel tiles); the damaged share of all the pixels composited is
  0.15–0.5 %. The exceptions: dragging a window (14–17 % of the screen per frame, the old and new window rectangles; their
  bounding box 34–47 %) and opening a window (2.4–9 %, its fade-in).
- **Every presented frame is composited and presented whole**: 8.1 MB rendered into the composite surface and 8.1 MB
  blitted to the swapchain (plus, on NV, an 8.1 MB upload; on UEFI an 8.1 MB shadow copy and an 8.1 MB Blt).
- **Hosted, the compositor presents every tick (60 Hz) whether anything changed or not**, and the top bar's ms/fps
  readout changes on nearly every one. 82–97 % of the hosted frames of the idle, hover and scroll scenarios render no
  window at all: their only damage is the readout (≈ 2.5–18 k pixels). On UEFI the compositor presents only on change
  (3–5 fps idle) but while anything moves the readout keeps it at the tick rate too (typing: 40 fps for 16 keys a second).
- **Per presented frame the present path costs** 4.7 ms CPU on UEFI (composite render 2.0 ms, RGBA→BGRA blit 0.5,
  shadow copy 0.7, GOP Blt 1.5), 5.3 ms hosted on NV (GPU wait 0.5, 8 MB upload 0.5, SDL blit and present 4.2) and
  4.6 ms hosted on SDL_GPU (present 4.6 ms: Xvfb's present path, see caveats; GPU ≤ 5.4 ms with queueing).
- **Layers**: unchanged windows are not re-rendered, but a changed window is re-rendered whole: the Agent window streaming
  text re-renders its 720x700 layer on every delta (16 Mpx/s, 1.7 MB a frame) for 0.2 % of the screen changed.
- **VNC is already damage-limited on the wire**: QEMU compares the guest's surface with its own copy and sends only what
  changed (typing: 23 updates/s of 1 k pixels, 11 KB/s; dragging 83 KB/s). The cost of the whole-frame Blt lands in QEMU
  (an 8 MB transfer and an 8 MB compare per frame), not in the bytes.
- **Expected savings of point 1** (details below): UEFI present path 4.7 ms → ≈ 0.2 ms per typing frame (−95 %), and
  ≈ −90 % of the UEFI CPU spent presenting while typing or streaming; hosted, skipping undamaged frames removes 65–97 % of
  the presents in all but the streaming scenario; NV uploads drop from 8.1 MB to a few KB per frame.

## What is damage-limited today, and what is not

Read from UI-Windows (World, Compositor, Layer, Window, View), Graphics-Canvas (Canvas, DisplayList, Renderer,
DisplayWindow), Graphics-GPU (SoftwareGPU, HostFramePresenter), Graphics-NV (NvComputeGPU) and System-Devices
(FirmwareScreen, FirmwareDisplay).

| Stage | Damage-limited? |
| --- | --- |
| A view's drawing (Window>>redraw) | Partly: retained drawing replays the DisplaySegments of views that did not change (View>>drawRetainedOn:, Canvas>>replay:), so recording is incremental; but each redraw publishes a whole new DisplayList, and nothing records *where* it changed. |
| Layer render (Layer>>renderExtent:…) | Per window only: a layer is rendered again when its content or chrome list changed (identity), and then entirely: clear, every quad. Unchanged windows keep their surface. |
| Composite (Compositor>>present:now:) | No. Every presented frame builds the whole screen's DisplayList (desk halftone, every layer, shadows, top bar, overlays, toasts, pointer) and renders it into the DisplayWindow's full-size surface, cleared. |
| When to present | Hosted World: every tick (World>>presentsContinuously, so the top bar's frame times stay live). A software device (UEFI) or an AppWorld: only when something changed (World>>changed, animations, the top bar), resting as long as the frame took. |
| Top bar | Its retained drawing is incremental, but its ms/fps readout changes with almost every frame and asks for the next. |
| DisplayWindow>>show: | No: whole surface → swapchain blit. |
| SDL_GPU (a) | No: full render pass, full blit, present. |
| NV (b) | No: raster kernels render the whole composite and raster_blit it into the BGRA back buffer (uncached system memory); present waits for the GPU (touch:) and HostFramePresenter uploads the whole 8.1 MB frame into an SDL texture (its upload already takes x y w h), then blits it to the swapchain. |
| UEFI (c) | No: SoftwareGPU renders the composite on the CPU, blits it RGBA→BGRA into the back buffer, FirmwareScreen copies the whole frame into its shadow copy and Blts the whole screen (EfiBltBufferToVideo; edk2's VirtioGpuDxe copies into its backing store, TRANSFER_TO_HOST_2D and RESOURCE_FLUSH of the rectangle). **The pointer is**: moving it restores 12x19 pixels from the shadow copy and Blts only them, without a frame. |
| QEMU VNC (d) | Yes on the wire: QEMU compares in 16-pixel-wide blocks per row and sends the changed rectangles. Not in QEMU's CPU: every Blt of the whole screen means a whole transfer and compare. |

Nothing between View>>invalidate and the present keeps a damage rectangle.

## How it was measured

- **StageTimes** (System-Profiling, new): named counters of µs and bytes for the stages below the compositor, off by
  default (`StageTimes current` is nil and each stage only tests that): `layer.render`, `composite.render`,
  `composite.blit`, `present.submit` (DisplayWindow>>show:), `nv.wait` (NvComputeGPU>>present:), `host.upload`,
  `host.blit` (HostFramePresenter), `screen.shadow`, `screen.blt`, `screen.pointer` (FirmwareScreen). On SDL_GPU
  the render and blit stages are encoding times (the GPU's time is the FrameRecord's `gpu`, an upper bound with
  queueing); on a SoftwareGPU they are the work itself.
- **DamageProbe** (UI-Windows, new; `DamageProbe start`, `current mark: 'name'`, `summary`, `csv:`, `stop`): the
  compositor hands it each presented frame. Damage is computed from the display lists, not the pixels: every quad gets a
  key (its position and what its clip leaves of it, mode, color; texels for glyphs, images and lines; the texture for
  glyphs and images), and a quad drawn in one frame and not the other damages its bounds. The whole screen's composite
  list is compared with the previous frame's (windows moving, fading, raised; top bar, toasts, pointer), and the old and
  new content and chrome lists of every layer rendered again, placed where the layer is (windows above it are not
  subtracted, so this overestimates covered windows). Areas are counted in 16x16 tiles (QEMU's VNC granularity); a quad's
  box is coarser than its pixels (glyph boxes), so this overestimates too. Its own cost is 0.6 ms a frame (outside the
  stage times).
- **Scenarios** (samaltak-ctl, in order, each marked): open a Workspace (60,80 760x520) and a System Browser on
  OrderedCollection (880,80 980x600), focus the Workspace; *idle-caret* 3 s; *typing* 77 characters 60 ms apart;
  *idle-after* 1 s; *scroll-list* 8 wheel steps down and 8 up on the methods list; *hover* 16 pointer positions down that
  list; *drag-window* the Workspace by its title bar 4 times (400,150 and back, 300,250 and back); *agent-open* an Agent
  window (720x700) on a ScriptedProvider; *agent-stream* one turn whose 150 text deltas arrive 30 ms apart; *idle-end* 2 s.
- **Setups**: (a) and (b) the hosted VM in a 1920x1080 window (scale 1) on a private Xvfb; SDL_GPU ran on the NVIDIA
  Vulkan driver (libnvidia-glcore; its X11 present to Xvfb goes through the CPU, so `present.submit` ≈ 3–5 ms is that,
  not the GB10's work); (b) with `SAMALTAK_GPU=nv`. (c) `samaltak-ctl open --uefi --window-size 1920x1080` with
  `UEFI_GPU=virtio-gpu-pci`, KVM, one vCPU's Smalltalk. (d) a minimal RFB client during (c) (VNC auth, ZRLE, incremental
  update requests as a viewer sends them) logging rectangles, area and bytes per update, plus QEMU's CPU time.
- The machine was shared (load average 15–19 on 20 cores): times are indicative, the pixel counts are not affected.

## Results

Columns: frames presented and compositor ticks; frames per second presented; damaged share of the composited pixels
(16-px tiles) and of their bounding boxes; share of frames damaging < 1 % of the screen; share of frames that render no
layer (nothing in any window changed); layer pixels rendered per second; mean µs of DisplayWindow>>show: (composite,
blit, present) per frame; present-path ms per second.

### (a) Hosted, SDL_GPU (NVIDIA Vulkan on Xvfb)

| scenario | frames/ticks | s | fps | damaged % | bbox % | frames <1% | no-layer frames | layer Mpx/s | show µs/frame | present ms/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 186/186 | 3.1 | 60 | 0.38 | 2.66 | 92% | 88% | 2.3 | 5929 | 356 |
| typing | 318/318 | 5.3 | 60 | 0.21 | 4.24 | 100% | 65% | 7.8 | 4793 | 288 |
| idle-after | 69/69 | 1.2 | 58 | 0.24 | 0.62 | 100% | 88% | 2.0 | 5574 | 321 |
| scroll-list | 78/78 | 1.3 | 60 | 0.25 | 2.27 | 99% | 85% | 3.3 | 4344 | 261 |
| hover | 175/175 | 2.9 | 60 | 0.17 | 4.28 | 100% | 87% | 2.5 | 3762 | 227 |
| drag-window | 93/93 | 1.5 | 62 | 17.07 | 43.50 | 9% | 86% | 2.6 | 3545 | 220 |
| agent-open | 128/128 | 2.1 | 61 | 2.40 | 7.11 | 90% | 81% | 6.1 | 5047 | 308 |
| agent-stream | 307/307 | 5.1 | 60 | 0.23 | 10.95 | 99% | 45% | 17.1 | 4583 | 276 |
| idle-end | 125/125 | 2.1 | 60 | 0.16 | 1.89 | 99% | 87% | 2.5 | 4712 | 280 |

Mean per frame over all 1,479: draw (chrome and composite lists) 307 µs, layers 51 µs, composite.render 116 µs and
composite.blit 30 µs (encoding), present.submit 4,556 µs, GPU ≤ 5.4 ms; 8.1 MB rendered and 8.1 MB blitted.

### (b) Hosted, --gpu nv (NvComputeGPU, HostFramePresenter)

| scenario | frames/ticks | s | fps | damaged % | bbox % | frames <1% | no-layer frames | layer Mpx/s | show µs/frame | present ms/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 183/183 | 3.1 | 59 | 0.27 | 1.40 | 96% | 97% | 0.8 | 6786 | 401 |
| typing | 316/316 | 5.3 | 60 | 0.18 | 3.83 | 100% | 74% | 6.1 | 5521 | 329 |
| idle-after | 67/67 | 1.1 | 61 | 0.29 | 0.38 | 100% | 97% | 0.7 | 5720 | 348 |
| scroll-list | 92/92 | 1.5 | 61 | 0.51 | 2.20 | 89% | 87% | 4.7 | 5612 | 344 |
| hover | 178/178 | 3.0 | 59 | 0.18 | 1.89 | 100% | 97% | 0.7 | 4925 | 292 |
| drag-window | 89/89 | 1.5 | 59 | 17.25 | 42.45 | 10% | 97% | 0.8 | 4726 | 280 |
| agent-open | 126/126 | 2.1 | 60 | 2.40 | 6.61 | 90% | 90% | 4.4 | 6020 | 361 |
| agent-stream | 305/305 | 5.1 | 60 | 0.28 | 11.14 | 99% | 48% | 15.6 | 5154 | 308 |
| idle-end | 126/126 | 2.1 | 60 | 0.34 | 1.65 | 99% | 97% | 1.0 | 4925 | 296 |

Mean per frame over 1,482: composite.render 148 µs and composite.blit 77 µs (kernel launches), nv.wait 462 µs (the
GPU finishing them), host.upload 534 µs for 8.1 MB (15 GB/s), host.blit 4,222 µs (SDL acquire, blit, present to Xvfb),
layer.render 71 µs.

### (c) UEFI World, QEMU/KVM, virtio-gpu 1920x1080 (SoftwareGPU, FirmwareScreen)

| scenario | frames/ticks | s | fps | damaged % | bbox % | frames <1% | no-layer frames | layer Mpx/s | show µs/frame | present ms/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 34/155 | 3.2 | 11 | 0.30 | 17.81 | 97% | 82% | 0.7 | 5362 | 57 |
| typing | 296/375 | 7.4 | 40 | 0.15 | 2.19 | 100% | 71% | 4.5 | 5265 | 211 |
| idle-after | 4/51 | 1.1 | 4 | 0.24 | 3.37 | 100% | 50% | 0.7 | 4589 | 17 |
| scroll-list | 251/865 | 18.5 | 14 | 0.48 | 2.18 | 91% | 82% | 1.1 | 4494 | 61 |
| hover | 277/862 | 18.9 | 15 | 0.32 | 2.24 | 97% | 87% | 0.8 | 5001 | 73 |
| drag-window | 106/440 | 9.9 | 11 | 13.97 | 34.12 | 21% | 82% | 0.8 | 4733 | 51 |
| agent-open | 30/106 | 2.1 | 14 | 8.78 | 29.78 | 63% | 60% | 3.5 | 4545 | 65 |
| agent-stream | 170/282 | 4.8 | 35 | 0.19 | 18.00 | 99% | 8% | 16.4 | 4608 | 163 |
| idle-end | 10/125 | 2.1 | 5 | 0.19 | 18.92 | 100% | 60% | 1.0 | 3849 | 18 |

Mean per frame over 1,178: composite.render 2,007 µs, composite.blit 516 µs, screen.shadow 669 µs, screen.blt 1,465 µs
(each 8.1 MB), draw 347 µs, layers 111 µs. (The ctl commands are slower on UEFI, so scroll, hover and drag take longer
and present fewer frames per second than hosted.)

Cost against area on this machine (UEFI, 30–40 repetitions):

| | full screen | 960x540 | 400x300 | 64x32 | 8x16 |
| --- | --- | --- | --- | --- | --- |
| GOP Blt (FirmwareScreen>>copyToScreen:) | 1,298 µs | 403 µs | 81 µs | 45 µs | 44 µs |
| composite render clipped to the rectangle (241 quads) | 1,219 µs | 333 µs | 478 µs (covers window images) | 4 µs | |

A Blt costs ≈ 44 µs a call (two virtio round trips) plus ≈ 0.6 ns a pixel: rectangles should be merged into a few.

### (d) What QEMU's VNC server sends (ZRLE) during (c)

| scenario | s | updates/s | rects/update | changed px/update (% of screen) | KB/update | KB/s | QEMU CPU, % of a core |
| --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 3.1 | 6.1 | 6.9 | 1,583 (0.08 %) | 0.6 | 3 | 14 |
| typing | 7.4 | 23.4 | 5.1 | 1,004 (0.05 %) | 0.5 | 11 | 33 |
| idle-after | 1.1 | 1.8 | 8.0 | 1,480 (0.07 %) | 1.0 | 2 | 12 |
| scroll-list | 18.5 | 5.9 | 16.1 | 4,563 (0.22 %) | 2.3 | 14 | 15 |
| hover | 18.9 | 6.7 | 7.1 | 1,875 (0.09 %) | 0.7 | 5 | 16 |
| drag-window | 9.9 | 5.4 | 121.4 | 265,123 (12.8 %) | 15.5 | 83 | 13 |
| agent-open | 2.1 | 6.6 | 26.0 | 186,963 (9.0 %) | 8.1 | 53 | 15 |
| agent-stream | 4.8 | 27.0 | 6.8 | 1,764 (0.09 %) | 1.0 | 26 | 33 |
| idle-end | 2.1 | 4.8 | 6.7 | 1,552 (0.07 %) | 1.1 | 5 | 8 |

QEMU's pixel comparison agrees with the probe's display-list damage: the same small fractions (the probe's are 2–4x
larger: 16x16 tiles and quad boxes against QEMU's exact rows) and the same 13–14 % for dragging. QEMU's CPU includes the
vCPU running the image.

## Design sketch for point 1

Damage is a list of device-pixel rectangles (merged, a handful at most; one full-screen rectangle when the union exceeds
about half the screen), produced by the compositor per presented frame and handed down to the present.

1. **Present only damaged frames, and calm the readout.** The compositor keeps ticking (animations, statistics) but
   renders and presents only when the frame's damage is not empty; the top bar's ms/fps readout changes at most twice a
   second. Hosted this removes the frames that render no layer and damage only the readout: 82–97 % of the frames idle,
   hovering or scrolling, 65–74 % typing, 45–48 % streaming. Each saves the whole present (4.6 ms CPU of Xvfb present
   here, the GPU's composite and blit; on a real display the swapchain flip and the GPU's 16 MB of writes). On UEFI it
   ends the readout's feedback (a frame changes the readout, which asks for a frame): typing would present about 16 frames
   a second instead of 40.
2. **Scene damage in the compositor.** For each thing it draws (each window's quad and shadow with its rectangle,
   opacity, scale, z-order and focus, the decorations, the top bar's segments, toasts, tooltip, curtain, the remote
   pointer) keep last frame's state; what differs damages its old and new bounds. Cheap state keys, not the probe's
   quad hashing (0.6 ms a frame). Windows above a damaged one clip nothing at first; subtracting opaque windows later.
3. **Layer damage from the window.** Window>>redraw knows which views drew anew and which were replayed (and replayed
   segments that moved): it publishes, with the content list, the union of their bounds in window coordinates. The layer
   accumulates it until rendered, renders with its surface kept (clear: nil), fills the damaged rectangles with its clear
   color and draws only the quads that intersect them, scissored. The Agent window streaming text: a few thousand pixels
   per delta instead of 490 k (1.7 MB a frame); typing likewise.
4. **Composite only the damage.** DisplayWindow keeps its surface between frames (it already does, but clears it): render
   the composite list with clear: nil, scissored to each damage rectangle, after culling quads outside them on the CPU
   (the Renderer already sets a scissor per batch; a pass-level scissor is one more argument).
5. **Present only the damage**, a rectangle list on the swapchain's submit (`GPUPlatform` present with damage; SoftwareGPU
   and NvComputeGPU pass it to their display's presentWindow:…rects:):
   - **UEFI**: SoftwareGPU blits only the rectangles into the back buffer; FirmwareScreen copies only them into the shadow
     copy and Blts each (merged to at most ~4–8 calls: 44 µs a call). VirtioGpuDxe then transfers and flushes only them,
     and QEMU's VNC compares only them.
   - **NV**: raster_blit only the rectangles into the back buffer; HostFramePresenter uploads only them into its texture
     (uploadTexture already takes x y w h; the texture persists) and blits the whole texture to the swapchain (GPU-side).
   - **SDL_GPU**: the swapchain's images do not keep their contents, so the surface → swapchain blit stays whole (GPU-side,
     cheap on the GB10); the gains are 1, 3 and 4. SDL_GPU does not expose VK_KHR_incremental_present.

Expected savings, from the numbers above:

| path | per frame today | with damage (typing, streaming, hover: ≤ 0.5 % damaged) | other |
| --- | --- | --- | --- |
| UEFI | 4.7 ms: render 2.0, blit 0.5, shadow 0.7, Blt 1.5 | ≈ 0.2 ms: render ≈ 10–50 µs, blit and shadow ≈ 5 µs, 1–3 Blts ≈ 0.1–0.15 ms | typing: 211 → ≈ 4 ms/s of CPU presenting (16 fps × 0.2 ms after 1); streaming 163 → ≈ 10 ms/s, plus layer renders 1.7 MB → ≈ 10 KB a delta; drag stays ≈ 14 % of a full frame per frame (two window rectangles, not their bounding box: 2.5x less) |
| NV | 5.3 ms: wait 0.5, upload 0.5 (8.1 MB), present 4.2 | upload ≈ 10 µs (a few KB); wait shorter (kernels on the damage only) | the SDL present per frame stays; skipping undamaged frames (1) removes 65–97 % of them |
| SDL_GPU | CPU 4.6 ms (Xvfb present), GPU ≤ 5.4 ms, 16 MB written | GPU composite on the damage only; the blit stays | 1 removes 65–97 % of the presents |
| VNC | bytes already only the change | unchanged | QEMU's 8 MB transfer and 8 MB compare per frame shrink to the rectangles (QEMU 33 % of a core while typing, with the guest) |

Order: 1 (small, the largest hosted win, and the UEFI readout loop), then 2 + 4 + 5 (the UEFI and NV present paths), then
3 (layers, for streaming and typing in large windows).

## Reproducing

```
DamageProbe start.
DamageProbe current mark: 'typing'.     "... interact ..."
DamageProbe current summary.            "a line per scenario"
DamageProbe current csv: 'typing'.      "per frame: ms, damage px, bbox px, rects, layers, layer px, draw, layers, show, gpu, probe µs"
DamageProbe stop
```

The scenario driver was a pit session function over samaltak-ctl (`ctlSession` steps as listed above); the VNC client is
about 60 lines of Python (RFB 3.8, VNC authentication, ZRLE rectangles skipped by their length).

Two observations on the way: solid and pattern quads leave their texel fields unwritten, so in the compositor's reused
vertex buffer they carry the previous frame's bytes (harmless: the shader ignores them; a damage tracker must too); and
the top bar's readout, measuring frames, makes frames.
