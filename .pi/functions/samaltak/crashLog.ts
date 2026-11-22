/** Triage a VM's death from a samaltak-ctl session log (TMPDIR/samaltak-ctl/<session>.log) or any console log: whether the session's VM still runs, the fatal line and exit status, the Smalltalk stack around it with repeated frames collapsed, the last test errors, and the tail. */
async function crashLog(
  { shell: { exec } },
  input: { session?: string; file?: string; contextLines?: number; tailLines?: number } = {},
) {
  // For "the VM is gone": a samaltak-ctl session (session, default "samaltak"; ctlSession and vncWorld name theirs) logs
  // the VM's (or QEMU's console's) output to $TMPDIR/samaltak-ctl/<session>.log, overwritten when the session opens again,
  // so read it (or copy it aside) before reopening. file: any log instead (a copied crash log, OUT/uefi-<arch>/console.log,
  // a gate log). Returns alive (the session's recorded pid still runs; null for a file), fatal (lines such as
  // "samaltak: fatal: out of memory (256 MB live, limit 256 MB)", a C or QEMU error), exit (the VM's "samaltak: exit N"),
  // the lines before the first fatal line (contextLines, default 25) and the stack after it with consecutive repeats
  // collapsed ("StackOverflowTest>>depth: (x192418)"), the last ERROR/FAIL lines of tests, and the collapsed tail.
  // Escape sequences and carriage returns are stripped; the last 4 MB of a longer log are read. Nothing is sent anywhere.
  const session = input.session ?? "samaltak";
  if (!/^[A-Za-z0-9_-]+$/.test(session)) throw new Error("crashLog: bad session name");
  const ctx = Math.min(Math.max(input.contextLines ?? 25, 0), 200);
  const tailN = Math.min(Math.max(input.tailLines ?? 25, 0), 200);
  const dir = (await exec('printf %s "${TMPDIR:-/tmp}/samaltak-ctl"')).stdout;
  const file = input.file ?? `${dir}/${session}.log`;
  const q = (s: string) => "'" + s.replace(/'/g, "'\\''") + "'";
  const st = await exec(`test -f ${q(file)} && wc -c < ${q(file)}`);
  if (st.code !== 0)
    throw new Error(
      `crashLog: no log ${file}${input.file ? "" : ` (no samaltak-ctl session "${session}" here)`}`,
    );
  let alive: boolean | null = null;
  let meta: { pid?: number; port?: number; uefi?: boolean; started?: string } | undefined;
  if (!input.file) {
    const j = await exec(`cat ${q(`${dir}/${session}.json`)} 2>/dev/null`);
    if (j.stdout.trim()) {
      try {
        const m = JSON.parse(j.stdout);
        meta = { pid: m.pid, port: m.port, uefi: m.uefi, started: m.started };
        alive = typeof m.pid === "number" && (await exec(`kill -0 ${m.pid}`)).code === 0;
      } catch {
        meta = undefined;
      }
    } else alive = false;
  }
  const r = await exec(
    `tail -c 3900000 ${q(file)} | sed -e 's/\\x1b\\[[0-9;=?]*[A-Za-z]//g' | tr -d '\\r'`,
    { maxBytes: 4000000, truncate: "tail", timeoutMs: 30000 },
  );
  const lines = r.stdout.split("\n");
  const collapse = (xs: string[]) => {
    const outL: string[] = [];
    for (let i = 0; i < xs.length;) {
      let j = i + 1;
      while (j < xs.length && xs[j] === xs[i]) j++;
      if (xs[i].trim() || j - i === 1) outL.push(j - i > 1 ? `${xs[i]} (x${j - i})` : xs[i]);
      i = j;
    }
    return outL.map((l) => l.slice(0, 300));
  };
  const fatalRe =
    /samaltak: fatal|^fatal:|panic|Segmentation fault|SIGSEGV|SIGBUS|Aborted|core dumped|^qemu-system[^ ]*: |Synchronous Exception|out of memory \(/i;
  const fatalIdx = lines.findIndex((l) => fatalRe.test(l));
  const exitLine = lines.filter((l) => /samaltak: exit -?\d+/.test(l)).pop();
  const around =
    fatalIdx >= 0
      ? {
          before: collapse(lines.slice(Math.max(0, fatalIdx - ctx), fatalIdx)),
          after: collapse(lines.slice(fatalIdx + 1, fatalIdx + 4000)).slice(0, 60),
        }
      : undefined;
  const testErrors = lines.filter((l) => /^(ERROR|FAIL) /.test(l));
  return {
    file,
    bytes: Number(st.stdout.trim()),
    session: input.file ? undefined : session,
    alive,
    meta,
    fatal: [...new Set(lines.filter((l) => fatalRe.test(l)))]
      .slice(0, 10)
      .map((l) => l.slice(0, 300)),
    exit: exitLine ? Number(exitLine.replace(/.*samaltak: exit /, "")) : null,
    around,
    testErrors: testErrors.slice(-10).map((l) => l.slice(0, 300)),
    moreTestErrors: Math.max(0, testErrors.length - 10),
    tail: collapse(lines.slice(-Math.max(tailN * 20, 200)))
      .filter((l) => l.trim())
      .slice(-tailN),
    hint:
      alive === true
        ? "the session's VM still runs: this is its log so far"
        : fatalIdx < 0 && !exitLine
          ? "no fatal line and no exit status: the VM may have been killed from outside (kernel OOM: sudo dmesg), or the log was overwritten by a later open"
          : undefined,
  };
}
