/** Boot the image in QEMU (make uefi-run) with an expression or VM args, optionally with ext4 disks (files, or made from directories), and return the console and the VM's exit status; refuses if this directory's QEMU is already running, kills the QEMU it started on timeout. */
async function uefiEval(
  { shell: { execFile } },
  input: {
    expr?: string;
    args?: string;
    timeoutS?: number;
    lines?: number;
    out?: string;
    catchErrors?: boolean;
    disks?: Array<
      | string
      | { dir: string; label?: string; sizeMB?: number; device?: "nvme" | "virtio-blk-pci" | "usb-storage" }
    >;
    vars?: Record<string, string>;
  } = {},
) {
  // Boots the image in QEMU with its UEFI firmware (make uefi-run, rebuilding the EFI VM and disk if the image is newer)
  // in the current directory and returns the console: expr runs as --headless --eval, or args gives the VM's
  // arguments after the image verbatim (shell words, e.g. "--headless --test FileTest"). With catchErrors (default) an
  // expr runs inside [ ... ] on: Error do: and an error comes back as error ('ERROR <class>: ...'), since an uncaught
  // error leaves the VM waiting until the timeout.
  // disks: more read-only disks (docs/files.md), each "FILE@DEVICE" (DEVICE nvme, virtio-blk-pci or usb-storage) or
  // { dir, label?, sizeMB?, device? (nvme) }: an ext4 file system of dir's contents labeled label (default: dir's
  // name), made with mkfs.ext4 -d into OUT/uefi-disks/<label>.img; on UEFI each shows at /mnt/<label>.
  // vars: more make variables, e.g. { UEFI_HEAP_MB: "512", UEFI_NIC: "e1000e" }. out: the build directory (OUT).
  // One QEMU per OUT: refuses while a QEMU of this directory's OUT/uefi-<arch> runs (a ctlSession --uefi, another
  // uefiEval; samaltak.gate runs in its own worktree); at the timeout it kills only the QEMU it started.
  if (!input.expr && !input.args) throw new Error("expr or args is required");
  const q = (s: string) => `'${s.replace(/'/g, "'\\''")}'`;
  const out = input.out ?? "build";
  if (!/^[A-Za-z0-9_.\/-]+$/.test(out)) throw new Error(`bad out ${out}`);
  const expr =
    input.expr && (input.catchErrors ?? true)
      ? `[${input.expr}] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText printString, ' in ', e signalerContext printString, ' < ', e signalerContext sender printString]`
      : input.expr;
  const args = (input.args ?? `--headless --eval ${q(expr!)}`).replace(/\$/g, "$$$$");
  const timeoutS = Math.min(Math.max(input.timeoutS ?? 240, 10), 285);
  const lines = Math.min(Math.max(input.lines ?? 40, 5), 300);
  const vars = Object.entries(input.vars ?? {}).map(([k, v]) => {
    if (!/^[A-Z][A-Z0-9_]*$/.test(k) || ["OUT", "UEFI_ARGS", "UEFI_DISKS"].includes(k))
      throw new Error(`bad make variable ${k}`);
    return `${k}=${v}`;
  });
  // disks: files as given, directories made into ext4 images
  const diskSpecs: string[] = [];
  const made: string[] = [];
  const labels = new Set<string>();
  for (const d of input.disks ?? []) {
    if (typeof d === "string") {
      if (!/^[^@\s]+@(nvme|virtio-blk-pci|usb-storage)$/.test(d))
        throw new Error(`bad disk ${d}: FILE@nvme, FILE@virtio-blk-pci or FILE@usb-storage`);
      const ck = await execFile("test", ["-f", d.split("@")[0]]);
      if (ck.code !== 0) throw new Error(`disk file ${d.split("@")[0]} not found`);
      diskSpecs.push(d);
      continue;
    }
    const label = (d.label ?? d.dir.replace(/\/+$/, "").split("/").pop() ?? "disk").replace(/[^A-Za-z0-9_-]/g, "-").slice(0, 16);
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
    diskSpecs.push(`${img}@${d.device ?? "nvme"}`);
    made.push(`${img} (/mnt/${label})`);
  }
  // $1 UEFI_ARGS, $2 timeout, $3 OUT, $4 UEFI_DISKS, then more make variables
  const script = `A=$1; T=$2; O=$3; K=$4; shift 4
arch=$(uname -m); case $arch in x86_64|amd64) arch=x86_64;; *) arch=arm64;; esac
dir="$O/uefi-$arch"; log=$(mktemp)
mine() { for p in $(pgrep -f "fat:rw:$dir/esp" 2>/dev/null); do case "$(cat /proc/$p/comm 2>/dev/null)" in qemu-system*) [ "$(readlink /proc/$p/cwd)" = "$PWD" ] && echo $p;; esac; done; }
before=$(mine)
if [ -n "$before" ]; then echo "@@busy $before"; exit 0; fi
rm -f "$dir/console.log"
timeout -k 5 "$T" make uefi-run OUT="$O" "UEFI_ARGS=$A" "UEFI_DISKS=$K" "$@" >"$log" 2>&1; code=$?
for p in $(mine); do kill "$p" && echo "killed qemu $p" >&2; done
echo "@@make=$code"; grep -a -E "\\*\\*\\*|: (fatal )?error:|^Error |undefined reference|^qemu-system[^ ]*: " "$log" | tail -8
echo "@@console"; [ -f "$dir/console.log" ] && sed -e 's/\\x1b\\[[0-9;=?]*[A-Za-z]//g' -e 's/\\r//g' "$dir/console.log" | grep -a -v '^[[:space:]]*$' | tail -n ${lines}
rm -f "$log"`;
  const r = await execFile(
    "sh",
    ["-c", script, "sh", args, String(timeoutS), out, diskSpecs.join(" "), ...vars],
    { timeoutMs: (timeoutS + 20) * 1000, maxLines: 2000 },
  );
  if (r.stdout.startsWith("@@busy"))
    throw new Error(
      `a QEMU of this directory's ${out}/uefi-* is running (pid ${r.stdout.slice(7).trim()}): close its samaltak-ctl session or wait, or use another out`,
    );
  const [, makePart = "", consolePart = ""] = r.stdout.split(/@@make=|@@console\n?/);
  const makeCode = Number(makePart.split("\n")[0]);
  const console_ = consolePart.split("\n").filter(Boolean);
  const exitLine = console_.filter((l) => /samaltak: exit /.test(l)).pop();
  const errLine = console_.filter((l) => /^'ERROR /.test(l)).pop();
  return {
    ok: makeCode === 0,
    timedOut: makeCode === 124 || makeCode === 137,
    vmExit: exitLine ? Number(exitLine.replace(/.*samaltak: exit /, "")) : null,
    error: errLine,
    disks: diskSpecs.length ? diskSpecs : undefined,
    made: made.length ? made : undefined,
    makeErrors: makePart
      .split("\n")
      .slice(1)
      .filter(Boolean)
      .map((l) => l.slice(0, 300)),
    console: console_.map((l) => l.slice(0, 400)),
    note: r.stderr.trim().slice(-300) || undefined,
  };
}
