/** Boot the image in QEMU (make uefi-run) with an expression or VM args and return the console and the VM's exit status; refuses if this directory's QEMU is already running, kills the QEMU it started on timeout. */
async function uefiEval(
  { shell: { execFile } },
  input: {
    expr?: string;
    args?: string;
    timeoutS?: number;
    lines?: number;
    out?: string;
    catchErrors?: boolean;
    vars?: Record<string, string>;
  } = {},
) {
  // Boots the image in QEMU with its UEFI firmware (make uefi-run, rebuilding the EFI VM and disk if the image is newer)
  // in the current directory and returns the console: expr runs as --headless --eval, or args gives the VM's
  // arguments after the image verbatim (shell words, e.g. "--headless --test FileTest"). With catchErrors (default) an
  // expr runs inside [ ... ] on: Error do: and an error comes back as error ('ERROR <class>: ...'), since an uncaught
  // error leaves the VM waiting until the timeout.
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
    if (!/^[A-Z][A-Z0-9_]*$/.test(k) || ["OUT", "UEFI_ARGS"].includes(k))
      throw new Error(`bad make variable ${k}`);
    return `${k}=${v}`;
  });
  // $1 UEFI_ARGS, $2 timeout, $3 OUT, then more make variables
  const script = `A=$1; T=$2; O=$3; shift 3
arch=$(uname -m); case $arch in x86_64|amd64) arch=x86_64;; *) arch=arm64;; esac
for v in "$@"; do case $v in UEFI_ARCH=*) arch=\${v#UEFI_ARCH=};; esac; done
dir="$O/uefi-$arch"; log=$(mktemp)
mine() { for p in $(pgrep -f "fat:rw:$dir/esp" 2>/dev/null); do case "$(cat /proc/$p/comm 2>/dev/null)" in qemu-system*) [ "$(readlink /proc/$p/cwd)" = "$PWD" ] && echo $p;; esac; done; }
before=$(mine)
if [ -n "$before" ]; then echo "@@busy $before"; exit 0; fi
rm -f "$dir/console.log"
timeout -k 5 "$T" make uefi-run OUT="$O" "UEFI_ARGS=$A" "$@" >"$log" 2>&1; code=$?
for p in $(mine); do kill "$p" && echo "killed qemu $p" >&2; done
echo "@@make=$code"; grep -a -E "\\*\\*\\*|: (fatal )?error:|^Error |undefined reference|^qemu-system[^ ]*: " "$log" | tail -8
echo "@@console"; [ -f "$dir/console.log" ] && sed -e 's/\\x1b\\[[0-9;=?]*[A-Za-z]//g' -e 's/\\r//g' "$dir/console.log" | grep -a -v '^[[:space:]]*$' | tail -n ${lines}
rm -f "$log"`;
  const r = await execFile(
    "sh",
    ["-c", script, "sh", args, String(timeoutS), out, ...vars],
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
    makeErrors: makePart
      .split("\n")
      .slice(1)
      .filter(Boolean)
      .map((l) => l.slice(0, 300)),
    console: console_.map((l) => l.slice(0, 400)),
    note: r.stderr.trim().slice(-300) || undefined,
  };
}
