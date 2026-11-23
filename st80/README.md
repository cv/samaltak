# Smalltalk-80 guest

In the host image, open **World › VM Simulator › Smalltalk-80**. The tool
builds this guest from the linked Kernel and Compiler packages and
[ST80-UI](ST80-UI/). The 640 × 400 desktop has a Workspace, Transcript and
bouncing ball. Click the `3 + 4` line in the Workspace and press Cmd-P: the
guest compiler evaluates it and the Workspace selects the printed `7`.
Drag a title tab to move its window. **Run** boots the text-only mini
kernel instead.

[DisplayScreen](ST80-UI/DisplayScreen.st) owns the bitmap;
[DisplayBitmap](ST80-UI/DisplayBitmap.st) clips, fills, copies overlapping
rectangles and blits bits. [DisplayFont](ST80-UI/DisplayFont.st) supplies
the X11 misc-fixed 7 × 14 glyphs in 7 × 16 cells. The host
[GuestScreen](../src/Tools/GuestScreen.st) unpacks complete frames for
presentation at an integer scale and queues pointer and keyboard input.
The desktop, its windows and their drawing all belong to the guest.

## Image protocol (v1)

An attached [VMGuestSimulation](../src/VM-ImageBuilder/VMGuestSimulation.st)
sets the guest's predeclared `GuestDisplayMailbox` global to `true`
before bootstrap. `DisplayScreen>>open:` replaces that marker (or a v1
mailbox on reopen) with a fresh Array containing the first, white frame.
Without an attachment the stock guest reports that it needs the simulator
and exits; running it in the native VM does not open a pane.

| Slot (1-based) | Field | Writer |
| ---: | --- | --- |
| 1 | Protocol version, `1` | Guest at open |
| 2–3 | Width, height in pixels | Guest at open |
| 4 | Published packed framebuffer, a ByteArray | Guest |
| 5 | Frame serial: `0` while publishing, positive when complete | Guest |
| 6 | Flat input Array, 160 slots (32 records × five integers) | Host writes records |
| 7 | Read index, initially `0` | Guest |
| 8 | Write index, initially `0` | Host |
| 9 | Guest processing time in µs, or `nil` | Guest |

- **Frames:** Row-major, `(width + 7) // 8` bytes per row, high bit
  leftmost, `1` black, `0` white. Right padding bits are zero. Each axis
  is 1–4096 pixels, with at most 4,194,304 pixels in all. On a dirty flush
  the guest snapshots the drawing buffer, clears the serial to zero,
  writes the bytes and timing, then publishes the next positive serial.
  Timing starts at the first input poll or draw since the previous flush.
  The mailbox holds the latest frame, not a queue of frames.
- **Input:** Each record is `{type. x. y. key. modifiers}`; types 1–4
  are pointer down, up, move and key. Coordinates are guest pixels with
  origin at the top left. The key field carries a mouse button or key
  code. The indices are zero-based modulo 32; equal means empty, and one
  slot stays free, so the ring holds at most 31 pending events. The
  simulator advances the write index after storing the record; the guest
  advances the read index after copying it into its reusable event Array.
  A full ring leaves remaining events in the endpoint's queue.
- **Exchange:** [GuestImageMailbox](../src/VM-ImageBuilder/GuestImageMailbox.st)
  runs on the simulation process at the scheduler's platform poll, with
  an 8 ms poll interval and an idle wait capped at 8 ms when attached. It
  resolves the global again each poll and keeps no guest object addresses
  across polls. It validates the frame extent and byte length before
  copying a new completed frame to the endpoint via
  `displayFrame:extent:time:`, then takes input via `nextEvent`. The
  guest desk drains input on its own timer. The pane's reported input
  latency is an estimate from queue arrival to the next presented frame
  after dequeue, not an acknowledgement from the guest.

The mailbox exchanges ordinary image objects; it needs no display
primitive, FFI export or native trap.
