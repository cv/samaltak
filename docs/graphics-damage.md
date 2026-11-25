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

## Point 1 as built: before and after

Point 1 is built (12dadfa, 3633337, be98070, 75fe3cf). The sections after this one describe and measure the composition
before it ("today" there means then); this one says what changed and measures the same nine scenarios again.

| Stage | Now |
| --- | --- |
| Damage | A `DamageRegion` (System-Devices): device-pixel rectangles clipped to the target, merged when they overlap or lie within 16 px and their union wastes at most a quarter of itself (a typed word joins, a dragged window keeps its old and new rectangle), at most 8 (the cheapest pair merges), full past half the target. |
| Where damage comes from | From the display lists, not from `View>>invalidate`: `DisplayListDiff` compares a new list with the one drawn (byte ranges compared in place by the `bytesMismatch` primitives, see Refinements; equal prefix and suffix skipped; equal counts compared place by place) and damages the old and new bounds of the quads that differ, with their batch's move and clip. A `Form` changed in place damages its image and glyph quads (`Form>>contentVersion`); a `Surface` in a content list always damages its quads. Every vertex byte is now written (solid, pattern and line quads left some), so equal drawings in a reused buffer compare equal. About 55 µs for a 1,500-quad list with one change at first, 12–17 µs since the refinements. |
| Layer render | The surface is kept; a changed layer fills only the damage with its clear color and draws its lists scissored to it (`Renderer>>render:into:clear:commandBuffer:within:`, `fill:color:into:commandBuffer:`), pixel-identical to drawing everything. Whole after `markNeedsRender` (new pipeline), at a new size, on a new surface, with a clear color that is not opaque, or past half. `Layer>>lastDamage` says what it changed. |
| Composite | The compositor notes each item it draws (desk, every window with its shadow and decorations, top bar, overlays, toasts, tooltip, curtain, pointer) and diffs it with the same item of the previous frame; a layer rendered in part adds its damage where it lands (1:1, a pixel around), else the window's bounds; items whose order changed damage both bounds. The composite list goes into two buffers in turn, so the previous frame's stays to compare. |
| When to present | Only frames with damage (`Compositor>>presentedCount`; `frameCount` counts every frame composed, for `World>>waitForFrames:`). `World presentsContinuously: true` presents every tick again (measurements). The top bar's readout and sparkline refresh at most twice a second and only when their text changed, riding along with frames presented for something else: alone they make one frame, three seconds after the last frame counted, to show the settled numbers (not counted in them), so an idle World presents nothing. A request (`Compositor>>sync:`: an RFB viewer reading the frame tap, a screenshot) runs at the next tick but is no change: the readout does not ride along with it, nor is its frame counted. |
| DisplayWindow>>show:clear:damage: | The surface keeps the last frame; the damage is filled and rendered scissored. SDL_GPU's swapchain does not keep its images: the whole surface is blitted (on the GPU). A software GPU's back buffer does (`GPUSwapchain>>keepsContents`): only the rectangles are blitted and `GPUCommandBuffer>>presentDamage:` hands them to the present. |
| NV | Composite and blit only the damage (raster kernels); `HostFramePresenter` uploads only the rectangles into the texture that holds the last frame. |
| UEFI | SoftwareGPU renders and blits only the damage; `FirmwareScreen>>present:width:height:rects:` copies only the rectangles into the shadow copy and Blts each (at most four since the refinements). |
| Vertex buffer | The Renderer's vertex buffer is a ring (4 MB): uploads into ranges a submitted command buffer still reads raced on the GB10's Vulkan (whole frames hid it; kept pixels do not). |

**Correctness.** `DamageCheck start` (UI-Windows) renders every frame drawn in part whole into a scratch surface and
compares the pixels, likewise every layer rendered in part, and the presents: HostFramePresenter's texture and
FirmwareScreen's shadow copy against the whole frame. `DamageCheck forcesFull: true` turns damage off (debugging).
DamageCompositionTest (streamed text, dragging and raising, menus, toasts, closing) passes with no mismatch on SDL_GPU,
`--gpu software` and `--gpu nv` (29–43 partial frames, as many presents, per test); the UEFI World (virtio-gpu, KVM)
typing, dragging and printing: 126 frames, 45 layer renders, 126 presents, no mismatch. On the GB10's Vulkan driver
under Xvfb the first readback of a texture can show what it held before the frame; DamageCheck reads a difference again
before it counts it (`staleReadbacks`).

**How measured.** The nine scenarios again (samaltak-ctl, session functions: Workspace and System Browser opened as
before, hover over the browser's first 16 method items, the Agent's 150 deltas 30 ms apart from a ScriptedProvider);
hosted on a private Xvfb, 1920x1080. *Before*, hosted: the image of origin/main 6002297 on the same VM. *Before*, UEFI:
the same build with `DamageCheck forcesFull: true` (whole composite and present each frame, the same presenting
policy), because the multi-CPU raster (2104b1d) changed the UEFI times since the tables below. Columns: frames presented
and compositor ticks; µs of `DisplayWindow>>show:` a frame (composite, blit, present; on Xvfb mostly its present);
present ms per second; KB a frame rendered into the composite, blitted, uploaded or Blt; µs a frame of `layer.render`.

(a) Hosted, SDL_GPU:

| scenario | frames/ticks | show µs/frame | present ms/s | composite KB/frame | blit KB/frame | layer.render µs/frame |
| --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 185/185 → 53/186 | 3067 → 2937 | 183 → 50 | 8100 → 185 | 8100 → 8100 | 12 → 115 |
| typing | 287/287 → 103/285 | 2511 → 2572 | 150 → 56 | 8100 → 143 | 8100 → 8100 | 35 → 206 |
| idle-after | 65/65 → 11/66 | 2326 → 3440 | 137 → 34 | 8100 → 115 | 8100 → 8100 | 11 → 191 |
| scroll-list | 64/64 → 29/76 | 2764 → 2763 | 161 → 62 | 8100 → 696 | 8100 → 8100 | 43 → 626 |
| hover | 93/93 → 29/100 | 2927 → 2746 | 181 → 47 | 8100 → 343 | 8100 → 8100 | 36 → 442 |
| drag-window | 84/84 → 88/91 | 2200 → 2707 | 132 → 159 | 8100 → 1328 | 8100 → 8100 | 18 → 84 |
| agent-open | 100/100 → 22/104 | 2849 → 3482 | 168 → 45 | 8100 → 1162 | 8100 → 8100 | 26 → 327 |
| agent-stream | 397/397 → 210/399 | 2555 → 4099 | 154 → 128 | 8100 → 170 | 8100 → 8100 | 32 → 265 |
| idle-end | 126/126 → 18/128 | 2389 → 2759 | 143 → 24 | 8100 → 406 | 8100 → 8100 | 22 → 152 |

(b) Hosted, `--gpu nv`:

| scenario | frames/ticks | show µs/frame | present ms/s | composite KB/frame | blit KB/frame | host.upload KB/frame | layer.render µs/frame |
| --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 186/186 → 48/184 | 4066 → 2884 | 244 → 45 | 8100 → 154 | 8100 → 154 | 8100 → 154 | 33 → 187 |
| typing | 286/286 → 95/283 | 4040 → 3083 | 241 → 62 | 8100 → 182 | 8100 → 182 | 8100 → 182 | 115 → 473 |
| idle-after | 65/65 → 11/65 | 3714 → 3821 | 219 → 38 | 8100 → 113 | 8100 → 113 | 8100 → 113 | 28 → 217 |
| scroll-list | 63/63 → 28/57 | 3845 → 3403 | 220 → 95 | 8100 → 227 | 8100 → 227 | 8100 → 227 | 136 → 694 |
| hover | 91/91 → 30/92 | 4234 → 2993 | 257 → 60 | 8100 → 331 | 8100 → 331 | 8100 → 331 | 86 → 519 |
| drag-window | 88/88 → 86/88 | 3816 → 3442 | 224 → 197 | 8100 → 1240 | 8100 → 1240 | 8100 → 1240 | 35 → 53 |
| agent-open | 101/101 → 23/101 | 3966 → 3638 | 236 → 49 | 8100 → 957 | 8100 → 957 | 8100 → 957 | 87 → 380 |
| agent-stream | 392/392 → 204/391 | 3958 → 3535 | 239 → 111 | 8100 → 163 | 8100 → 163 | 8100 → 163 | 147 → 332 |
| idle-end | 125/125 → 17/124 | 4432 → 3036 | 264 → 25 | 8100 → 4 | 8100 → 4 | 8100 → 4 | 32 → 341 |

Over the whole run: host.upload 529 → 35 ms, nv.wait 646 → 43 ms, host.blit (SDL acquire, blit, present to Xvfb)
4,255 → 1,550 ms.

(c) UEFI World, QEMU/KVM, virtio-gpu 1920x1080 (whole frames → damage, same build):

| scenario | frames/ticks | show µs/frame | present ms/s | composite KB/frame | blit KB/frame | screen.blt KB/frame | layer.render µs/frame |
| --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 39/186 → 39/187 | 3219 → 524 | 40 → 7 | 8100 → 74 | 8100 → 74 | 8100 → 74 | 169 → 154 |
| typing | 330/429 → 115/406 | 3111 → 640 | 145 → 11 | 8100 → 122 | 8100 → 122 | 8100 → 122 | 73 → 255 |
| idle-after | 11/66 → 11/65 | 3339 → 544 | 33 → 5 | 8100 → 237 | 8100 → 237 | 8100 → 237 | 246 → 189 |
| scroll-list | 478/1741 → 318/1966 | 3240 → 640 | 53 → 6 | 8100 → 184 | 8100 → 184 | 8100 → 184 | 143 → 222 |
| hover | 257/1310 → 270/1656 | 3731 → 587 | 44 → 6 | 8100 → 180 | 8100 → 180 | 8100 → 180 | 217 → 209 |
| drag-window | 122/253 → 116/258 | 3271 → 945 | 95 → 25 | 8100 → 946 | 8100 → 946 | 8100 → 946 | 74 → 72 |
| agent-open | 24/101 → 23/103 | 3687 → 1172 | 52 → 16 | 8100 → 861 | 8100 → 861 | 8100 → 861 | 271 → 257 |
| agent-stream | 262/627 → 243/627 | 3316 → 480 | 84 → 11 | 8100 → 162 | 8100 → 162 | 8100 → 162 | 230 → 195 |
| idle-end | 21/126 → 18/125 | 3284 → 577 | 33 → 5 | 8100 → 279 | 8100 → 279 | 8100 → 279 | 311 → 194 |

Over the whole run: composite.render 1,962 → 173 ms, composite.blit 616 → 42 ms, screen.shadow 545 → 20 ms, screen.blt
1,725 → 466 ms. A damaged frame's Blts (up to 8 rectangles at ≈ 44 µs a call) are now most of its present.

(d) QEMU's VNC server during (c), whole frames → damage (QEMU's CPU includes its vCPUs, now more than one):

| scenario | s | updates/s | rects/update | changed px/update (% of screen) | KB/update | KB/s | QEMU CPU, % of a core |
| --- | --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 3.1 → 3.1 | 9.5 → 8.4 | 1.8 → 1.8 | 434 → 434 (0.02 %) | 0.2 → 0.1 | 1 → 1 | 158 → 57 |
| typing | 7.2 → 6.8 | 13.6 → 12.3 | 1.2 → 0.9 | 513 → 469 (0.02 %) | 0.1 → 0.1 | 2 → 1 | 270 → 53 |
| idle-after | 1.1 → 1.1 | 6.2 → 6.4 | 0.3 → 1.1 | 91 → 505 (0.02 %) | 0.0 → 0.0 | 0 → 0 | 156 → 30 |
| scroll-list | 24.6 → 26.2 | 8.1 → 7.4 | 1.1 → 0.5 | 429 → 208 (0.01 %) | 0.0 → 0.0 | 0 → 0 | 162 → 38 |
| hover | 22.5 → 24.0 | 7.6 → 7.4 | 0.7 → 0.4 | 277 → 147 (0.01 %) | 0.0 → 0.0 | 0 → 0 | 138 → 28 |
| drag-window | 4.2 → 6.4 | 13.9 → 11.8 | 34.6 → 21.4 | 238,003 → 185,923 (9 %) | 8.1 → 5.7 | 113 → 67 | 223 → 84 |
| agent-open | 1.7 → 1.9 | 9.7 → 4.8 | 1.8 → 2.4 | 121,457 → 115,788 (5.6 %) | 3.5 → 4.5 | 34 → 21 | 166 → 26 |
| agent-stream | 9.5 → 10.6 | 16.8 → 15.2 | 4.2 → 4.0 | 1,023 → 978 (0.05 %) | 0.5 → 0.5 | 8 → 7 | 249 → 43 |
| idle-end | 2.1 → 2.1 | 8.0 → 4.7 | 0.5 → 0.4 | 139 → 115 (0.01 %) | 0.0 → 0.0 | 0 → 0 | 160 → 19 |

**In short.** Hosted, 45–86 % fewer frames are presented in every scenario but dragging, and each renders 0.1–1.3 MB
instead of 8.1 MB; the present path's CPU per second drops 2.5–6x (SDL_GPU) and 2–10x (NV, whose uploads shrink from
8.1 MB to the damage). On UEFI a frame's present path costs 0.5–0.6 ms instead of 3.1–3.7 (drag 0.95, a window opening
1.2), and QEMU's CPU drops 3–8x; the bytes on the wire hardly change (QEMU already sent only what changed). The price is
CPU in `layer.render` hosted: 85–690 µs a frame instead of 10–150, the display list diffs in Smalltalk and drawing in
pieces, where the GPU would have drawn the whole layer for less; on UEFI the two balance.

**Left.** Done since (next section): comparing byte ranges in place, fewer and larger Blts on UEFI, subtracting
opaque windows above a damaged item, culling batches outside a damage rectangle on the CPU. Still left: damage from the
views themselves (see the next section's end); SDL_GPU offers no partial present (VK_KHR_incremental_present), so its
blit stays whole.

## Refinements: diffs in place, fewer Blts, occlusion, culling

| Change | What |
| --- | --- |
| Diffs in place | Two VM primitives, `bytesMismatch` and `bytesLastMismatch` (since typed FFI exports, `core_bytes_mismatch` and `core_bytes_last_mismatch`: [ffi-fork.md](ffi-fork.md)) (`ByteArray>>indexOfMismatchAt:with:at:size:`, `lastIndexOfMismatchAt:with:at:size:`): where two ranges of byte or word objects first or last differ, 16 bytes at a time through ByteSearch's NEON/SSE2 blocks (`mismatchOf:with:from:size:`, and `lastMismatchOf:with:size:`, new, with `lastOf:` on the blocks). `DisplayListDiff` finds the first or last differing quad of a whole run with one call instead of copying 64-quad chunks into scratch ByteArrays and halving. It also joins the bounds of quads damaged one after another while their union wastes little (DamageRegion's rule) before they reach the region (whose `insert:` was a third of the diff), finds a run's batches by halves (a composite item is a few of the list's many batches) and hands the batches it already knows to the quads it damages. |
| Stage times | `layer.diff` (inside `layer.render`) and `composite.diff` (`Compositor>>damageOf:items:rendered:`). |
| UEFI Blts | `FirmwareScreen class>>mergeBlts:`: a frame's rectangles go as at most four Blts; two whose union adds fewer than 40,000 pixels (≈ the 44 µs a call costs, at 0.6 ns a pixel and the shadow copy) always go as one, beyond four the pair that wastes least merges. Exact: the back buffer holds the whole frame. |
| Occlusion | `Compositor>>occludersIn:old:`: windows drawn 1:1 at opacity 1 whose surface is cleared with an opaque color (premultiplied blending keeps it opaque), present in the last frame too, inset by a pixel. An item's damage (its diff and its layer's damage) is collected apart and loses what the occluders above it in every frame it is in cover (`damageInto:using:below:old:occluders:during:`): such a pixel shows that window before and after, and what changes in it is that window's own damage. |
| Culling | `DisplayList>>boundsOfBatch:` (kept per list) from a third primitive, `rasterQuadBounds` (PlatformRaster: 3 µs for 1,300 quads, 150 µs in Smalltalk); `Renderer>>render:into:clear:commandBuffer:within:` draws a batch for a damage rectangle only if its quads reach it, with its clip cut to them, on every GPU (NvComputeGPU and SoftwareGPU skip the draws, the kernels and rasterizers see smaller clips). |

**Correctness.** DisplayListDiffTest, DamageRegionTest and DamageCompositionTest (with a new test: lines streamed under
an opaque window present nothing; it fails with occlusion switched off) pass with no mismatch on SDL_GPU,
`--gpu software` and `--gpu nv`; the UEFI World at 1920x1080 on virtio-gpu (typing, scrolling, dragging, an Agent
window streaming over the others, typing under it) checked by DamageCheck: 490 frames, 301 layer renders, 490 presents,
no mismatch. Known flakes on the GB10 hosted, the same before these changes: the NV host texture or a Surface read
back stale once in a few runs (DamageCompositionTest's presents, DisplayListDiffTest's whole-render comparison), and
CompositorTest>>testFocusedTitleBarHasStripesAndTab, testFrameRecordsAreRecorded, SlowMotionTest under load (they pass
on lavapipe). `make test-nv` links its C reference again (it had not since the multi-CPU raster).

**The diff's CPU.** The scenarios' wall-clock stage times move by more than the diff's cost from run to run on the
shared machine (load 4–38), so the diffs were also replayed: the layer list pairs the compositor diffed during the
scenarios, recorded (Layer>>damageFor: patched in the running image) and diffed again 20 times each in the same image,
before (origin/main e95b8a4 with the two stage counters) and after:

| phase | diffs | quads (new list) | µs a diff before → after |
| --- | --- | --- | --- |
| idle-caret | 16 | 425 | 29.6 → 11.7 |
| typing | 107–109 | 180 | 15.4 → 5.5 |
| scroll-list | 25–27 | 790 | 135.6 → 75.7 |
| hover | 32 | 733 | 102.1 → 63.3 |
| agent-open | 15 | 431 | 12.0 → 6.1 |
| agent-stream | 203–205 | 574 | 15.3 → 10.5 |

A 1,297-quad list of 36 text rows: equal 27 → 12 µs, one glyph changed 24 → 17, text appended 21 → 10, six rows
recolored (270 glyphs damaged) 192 → 76. What is left in scrolling and hovering is the damaged quads themselves (most
of the list's quads move). The scenarios, hosted SDL_GPU, both images at once on the same machine, µs a presented frame
(wall clock, indicative):

| scenario | frames/ticks | layer.diff µs | layer.render µs | composite.diff µs |
| --- | --- | --- | --- | --- |
| idle-caret | 48/188 → 50/185 | 76 → 54 | 131 → 115 | 141 → 124 |
| typing | 99/284 → 100/286 | 58 → 72 | 191 → 245 | 174 → 144 |
| idle-after | 12/68 → 11/67 | 57 → 38 | 138 → 100 | 162 → 224 |
| scroll-list | 32/72 → 33/83 | 204 → 205 | 314 → 348 | 148 → 156 |
| hover | 34/113 → 34/111 | 223 → 179 | 357 → 288 | 139 → 97 |
| drag-window | 86/90 → 88/90 | 11 → 7 | 26 → 19 | 163 → 111 |
| agent-open | 24/105 → 23/103 | 60 → 72 | 243 → 217 | 131 → 156 |
| agent-stream | 200/394 → 199/389 | 63 → 53 | 155 → 133 | 73 → 55 |
| idle-end | 18/126 → 19/127 | 71 → 62 | 158 → 165 | 110 → 103 |

**Occlusion, Blts and culling, A/B.** The same build, each feature switched off for A by recompiling
`occludersIn:old:`, `FirmwareScreen class>>mergeBlts:` and `DisplayList>>boundsOfBatch:` in the running image (B: as
built); hosted A and B ran at once. The hosted World has six windows besides the scenario's (Transcript, Process
Browser, Mandelbrot, an Inspector, a second browser), some updating under the scenario's windows: that is what occlusion
removes. µs and KB a presented frame.

(a) SDL_GPU (composite.render is encoding; its KB the pixels drawn):

| scenario | frames/ticks | composite.diff µs | composite.render µs | composite.render KB |
| --- | --- | --- | --- | --- |
| idle-caret | 52/187 → 50/186 | 142 → 213 | 100 → 182 | 168 → 31 |
| typing | 99/287 → 101/286 | 227 → 311 | 122 → 137 | 124 → 27 |
| idle-after | 12/66 → 12/67 | 234 → 174 | 124 → 101 | 205 → 29 |
| scroll-list | 33/81 → 38/90 | 298 → 216 | 229 → 95 | 182 → 84 |
| hover | 34/110 → 34/110 | 107 → 159 | 85 → 90 | 285 → 142 |
| drag-window | 90/94 → 92/96 | 118 → 148 | 117 → 115 | 1212 → 1153 |
| agent-open | 21/108 → 23/106 | 131 → 196 | 86 → 188 | 1045 → 826 |
| agent-stream | 204/394 → 206/394 | 84 → 87 | 76 → 63 | 169 → 115 |
| idle-end | 17/128 → 19/129 | 118 → 137 | 82 → 101 | 75 → 3 |

Over the run: composite KB a frame 375 → 287, composite.render 104 → 105 µs a frame, composite.diff 94 → 113 µs a call.

(b) NV:

| scenario | frames/ticks | composite.diff µs | composite.render µs | nv.wait µs | host.upload µs | host.upload KB |
| --- | --- | --- | --- | --- | --- | --- |
| idle-caret | 53/188 → 52/188 | 156 → 176 | 349 → 327 | 65 → 39 | 52 → 42 | 148 → 30 |
| typing | 96/284 → 100/284 | 188 → 321 | 200 → 287 | 81 → 56 | 53 → 43 | 155 → 25 |
| idle-after | 11/68 → 11/70 | 187 → 369 | 468 → 285 | 67 → 48 | 53 → 42 | 226 → 31 |
| scroll-list | 31/102 → 35/86 | 235 → 232 | 262 → 471 | 78 → 49 | 67 → 54 | 232 → 82 |
| hover | 32/129 → 33/125 | 128 → 169 | 239 → 218 | 69 → 50 | 101 → 75 | 333 → 128 |
| drag-window | 95/99 → 95/99 | 167 → 176 | 423 → 407 | 123 → 119 | 201 → 190 | 1186 → 1120 |
| agent-open | 22/107 → 23/109 | 249 → 146 | 290 → 337 | 122 → 106 | 185 → 148 | 1053 → 811 |
| agent-stream | 207/394 → 205/397 | 97 → 118 | 214 → 208 | 53 → 45 | 63 → 55 | 165 → 122 |
| idle-end | 18/129 → 18/128 | 162 → 134 | 229 → 236 | 67 → 50 | 62 → 50 | 138 → 39 |

Over the run: composite and upload KB a frame 390 → 290, nv.wait 76 → 62 µs, host.upload 90 → 78 µs, composite.render
(encoding the draws) 272 → 291 µs, composite.diff 96 → 126 µs a call.

(c) UEFI, virtio-gpu 1920x1080, KVM (A and B one after the other):

| scenario | frames/ticks | composite.diff µs | composite.render µs | screen.blt µs | screen.blt KB |
| --- | --- | --- | --- | --- | --- |
| idle-caret | 32/189 → 49/188 | 103 → 241 | 107 → 85 | 393 → 646 | 87 → 19 |
| typing | 103/411 → 119/412 | 184 → 191 | 173 → 87 | 574 → 314 | 132 → 15 |
| idle-after | 10/65 → 11/69 | 83 → 101 | 109 → 71 | 423 → 417 | 126 → 24 |
| scroll-list | 285/1733 → 268/1570 | 99 → 137 | 134 → 96 | 452 → 308 | 140 → 49 |
| hover | 301/1921 → 193/1055 | 74 → 110 | 135 → 79 | 432 → 461 | 145 → 58 |
| drag-window | 128/360 → 102/142 | 98 → 117 | 424 → 490 | 520 → 487 | 879 → 1043 |
| agent-open | 22/108 → 22/111 | 81 → 128 | 1021 → 950 | 508 → 1125 | 907 → 757 |
| agent-stream | 245/631 → 248/633 | 61 → 81 | 118 → 79 | 329 → 468 | 162 → 100 |
| idle-end | 17/129 → 19/128 | 83 → 107 | 88 → 79 | 256 → 256 | 73 → 59 |

Over the run: composite KB a frame 244 → 166, composite.render 182 → 144 µs, composite.blit 47 → 43, screen.shadow
26 → 25, composite.diff 65 → 89 µs a call. screen.blt a frame is dominated by the latency of the calls, which varied by
half between runs (B once 316 µs a frame, once 426, against A's 434): Blt bytes fell 244 → 174 KB a frame.

**In short.** A layer's diff costs 1.5–2.8x less CPU (typing 5.5 µs, a streamed delta in the 720x700 Agent window
10.5 µs). Occlusion takes a quarter to a third of the composited pixels away when windows update under others; on UEFI
the composite costs a fifth less, on NV the GPU wait and upload an eighth to a sixth less. The price is in
composite.diff: 20–30 µs a frame of bookkeeping (occluders, the items' damage collected apart). Culling pays on the
software and NV rasterizers only with its primitive (in Smalltalk the bounds cost more than the draws they skip).

**Damage from the views (not done).** After the above, diffing a big window is cheap where little changes (5–11 µs a
typed character or a streamed delta for 180–575 quads) and where much changes the damaged quads are the cost, which
damage from the views would not avoid (a scrolled list's view redraws all its rows). So the layer diff stays.
Damage from the views would need: Window>>redraw to publish, with the list, the union of the bounds of the views drawn
anew and of the replayed segments that moved (Canvas>>replay: knows them), the Layer to accumulate it until rendered,
and care where it is not enough (a Form changed in place, a view drawing outside its bounds, clips that change). What
costs more now is composite.diff, 65–125 µs a frame: the composite list is new each frame and every item is diffed
(runs found and allocated, damage regions per occluded item); keeping the items' runs and comparing only items whose
bytes moved would be the next step.

**The frame tap** (`FrameTap`, System-Devices) passes each presented frame's damage on, for a remote display:
`FrameTap current` is the firmware screen's tap on UEFI (told by `present:width:height:rects:` the rectangles its caller
gave, however the Blts are merged, and `#full` by the whole-frame present; pixels read from the cursor-free BGRA shadow
copy under its lock) and hosted the Compositor's (told after `show:clear:damage:`, `#full` for whole frames; pixels the
surface's RGBA, read back in the compositor's Process). Hosted, the surface is the frame in its own pixels (the composite
list's `pixelExtent`: a 640x400 World at scale 2 is 1280x800 even where X11 reports the window's pixels as 640x400, and
the blit to the swapchain scales), and the remote pointer is not in it: it is a DisplayList of its own, drawn over a
copy of the surface that the window shows, with its own damage. The RFB server reads one update's rectangles in one
request between two frames (1280x800 under lavapipe: about 1.5 ms for the whole frame, 30 µs for a 120x40 rectangle),
at most `--display-rate` (60) updates a second per client, spaced by at least the last one's cost. Each `FrameTapListener` (one per client) gathers up to 32
rectangles until it takes them, full on a whole frame or a new size, and its semaphore is signalled when its damage stops
being empty. FrameTapTest and FrameTapCompositionTest rebuild the screen from the damage and the pixels read.


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
