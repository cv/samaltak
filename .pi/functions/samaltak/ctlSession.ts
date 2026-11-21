/** Drive an image with tools/samaltak-ctl: optionally open a session (hosted, windowed on a private Xvfb, or --uefi with env such as OUT and ext4 disks), run steps in order, always close what it opened. */
async function ctlSession(
  { shell: { execFile }, ui: { notify } },
  input: {
    session?: string;
    open?: string[];
    steps: string[][];
    xvfb?: boolean;
    keepOpen?: boolean;
    continueOnError?: boolean;
    stepTimeoutS?: number;
    openTimeoutS?: number;
    env?: Record<string, string>;
    out?: string;
    disks?: Array<
      | string
      | { dir: string; label?: string; sizeMB?: number; device?: "nvme" | "virtio-blk-pci" | "usb-storage" }
    >;
  },
) {
  // Drives a running image with tools/samaltak-ctl (docs: its usage) from the current directory: optionally opens a
  // session (open: its flags, e.g. ["--headless"] or ["--uefi", "--headless"]), runs steps in order (each the
  // arguments of one command, e.g. ["eval", "3 + 4"], ["eval", "--timeout", "200000", "..."], ["agent-config",
  // "--from-pi"], ["screenshot", "/tmp/s.png"]), stops at the first failure unless continueOnError, and closes the
  // session it opened unless keepOpen. xvfb gives a windowed session a private Xvfb display, stopped by its PID
  // afterwards (never by a pattern).
  // env: environment for every command, above all for open --uefi, which runs make uefi-control: e.g. { UEFI_NIC:
  // "e1000e", UEFI_HEAP_MB: "512" }. out sets OUT (the build directory). disks attaches read-only disks to a --uefi
  // session (UEFI_DISKS): "FILE@DEVICE" (nvme, virtio-blk-pci, usb-storage) or { dir, label?, sizeMB?, device? }, an
  // ext4 file system of dir's contents made with mkfs.ext4 -d, at /mnt/<label> on UEFI (label: default dir's name).
  // agent-config --from-pi resolves pi's API key, through 1Password's op when pi's config says so, which may wait for
  // the operator's approval: the operator is notified first, and a failure comes back with a hint. Output that looks
  // like an API key is redacted. In evals, print an AgentItem's text (item text), not its printString (cut short).
  const session = input.session ?? `pit-${Date.now().toString(36)}`;
  if (!/^[A-Za-z0-9_-]+$/.test(session)) throw new Error("bad session name");
  const stepTimeoutS = Math.min(Math.max(input.stepTimeoutS ?? 60, 5), 280);
  const env: Record<string, string> = { ...(input.env ?? {}) };
  for (const k of Object.keys(env)) if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) throw new Error(`bad env name ${k}`);
  if (input.out) env.OUT = input.out;
  const out = env.OUT ?? "build";
  const made: string[] = [];
  if (input.disks?.length) {
    const specs: string[] = [];
    const labels = new Set<string>();
    for (const d of input.disks) {
      if (typeof d === "string") {
        if (!/^[^@\s]+@(nvme|virtio-blk-pci|usb-storage)$/.test(d))
          throw new Error(`bad disk ${d}: FILE@nvme, FILE@virtio-blk-pci or FILE@usb-storage`);
        if ((await execFile("test", ["-f", d.split("@")[0]])).code !== 0)
          throw new Error(`disk file ${d.split("@")[0]} not found`);
        specs.push(d);
        continue;
      }
      const label = (d.label ?? d.dir.replace(/\/+$/, "").split("/").pop() ?? "disk")
        .replace(/[^A-Za-z0-9_-]/g, "-")
        .slice(0, 16);
      if (labels.has(label)) throw new Error(`two disks labeled ${label}: give each a label`);
      labels.add(label);
      const img = `${out}/uefi-disks/${label}.img`;
      const mk = await execFile(
        "sh",
        [
          "-c",
          'set -e; [ -d "$1" ] || { echo "no directory $1" >&2; exit 2; }; mb=$4; [ "$mb" -gt 0 ] || mb=$(( $(du -sm "$1" | cut -f1) * 13 / 10 + 16 )); mkdir -p "$(dirname "$3")"; rm -f "$3"; truncate -s "$mb"M "$3"; PATH=$PATH:/sbin:/usr/sbin mkfs.ext4 -q -F -L "$2" -d "$1" "$3"',
          "sh",
          d.dir,
          label,
          img,
          String(Math.max(0, Math.floor(d.sizeMB ?? 0))),
        ],
        { timeoutMs: 120000 },
      );
      if (mk.code !== 0) throw new Error(`could not make the ext4 disk for ${d.dir}: ${mk.stderr.slice(-400)}`);
      specs.push(`${img}@${d.device ?? "nvme"}`);
      made.push(`${img} (/mnt/${label})`);
    }
    env.UEFI_DISKS = specs.join(" ");
  }
  const redact = (s: string) =>
    s
      .replace(/\b(sk-[A-Za-z0-9_-]{16,}|nvapi-[A-Za-z0-9_-]{16,})/g, "<redacted>")
      .replace(/("?(api[_-]?key|authorization|x-api-key)"?\s*[:=]\s*"?)(Bearer )?[^\s",}]{12,}/gi, "$1<redacted>");
  let display = "";
  let xvfbPid = "";
  const results: Array<{ step: string[]; code: number | null; out: string; hint?: string }> = [];
  const run = async (args: string[], timeoutS: number) => {
    const pairs = Object.entries({ ...env, ...(display ? { DISPLAY: display } : {}) }).map(([k, v]) => `${k}=${v}`);
    const r = await execFile(
      "sh",
      ["-c", 'exec env "$@" </dev/null', "sh", ...pairs, "tools/samaltak-ctl", "--session", session, ...args],
      {
        timeoutMs: timeoutS * 1000,
        maxLines: 400,
        truncate: "tail",
      },
    );
    return {
      code: r.code,
      out: redact((r.stdout + (r.stderr ? "\n" + r.stderr : "")).trim()).slice(-3000),
    };
  };
  let notified = false;
  try {
    if (input.xvfb) {
      const x = await execFile("sh", [
        "-c",
        `for n in $(seq 140 199); do [ -e /tmp/.X11-unix/X$n ] || [ -e /tmp/.X$n-lock ] || { setsid Xvfb :$n -screen 0 1600x1000x24 >/dev/null 2>&1 </dev/null & echo ":$n $!"; exit 0; }; done; exit 1`,
      ]);
      if (x.code !== 0) throw new Error("no free X display");
      [display, xvfbPid] = x.stdout.trim().split(" ");
      await execFile("sleep", ["1"]);
    }
    if (input.open) {
      const o = await run(["open", ...input.open], Math.min(Math.max(input.openTimeoutS ?? 240, 10), 285));
      results.push({ step: ["open", ...input.open], ...o });
      if (o.code !== 0) return { ok: false, session, display: display || undefined, made, results };
    }
    for (const step of input.steps) {
      const fromPi = step.includes("agent-config") && step.includes("--from-pi");
      if (fromPi && !notified) {
        notified = true;
        await notify(
          "samaltak-ctl agent-config --from-pi is resolving pi's API key now: approve 1Password's prompt if it appears.",
          "warning",
        ).catch(() => null);
      }
      const r: { step: string[]; code: number | null; out: string; hint?: string } = {
        step,
        ...(await run(step, fromPi ? Math.max(stepTimeoutS, 150) : stepTimeoutS)),
      };
      if (fromPi && r.code !== 0)
        r.hint =
          "the apiKey command (1Password op) failed, often waiting for the operator's approval (authorization timeout, ssh Permission denied): ask the operator to approve and retry";
      results.push(r);
      if (r.code !== 0 && !input.continueOnError) break;
    }
  } finally {
    if (input.open && !input.keepOpen) results.push({ step: ["close"], ...(await run(["close"], 30)) });
    if (xvfbPid && !input.keepOpen) await execFile("kill", [xvfbPid]);
  }
  const ok = results.every((r) => r.code === 0);
  return { ok, session, display: display || undefined, made: made.length ? made : undefined, results };
}
