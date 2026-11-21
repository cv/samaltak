/** Run the push gate (default test-core; add test-uefi / test-jit-*) under Xvfb + lavapipe in the background, on a snapshot of HEAD in its own worktree, recording HEAD, tree and base in build/gate-runs; start, wait (resumable), status or stop. */
async function gate(
  { shell: { exec, execFile } },
  input: {
    action?: "start" | "wait" | "status" | "stop";
    targets?: string[];
    id?: string;
    waitS?: number;
    out?: string;
    isolate?: boolean;
  } = {},
) {
  // The push gate (AGENTS.md) as CI runs it: Xvfb + software Vulkan (lavapipe), in the background, for the current
  // directory's HEAD. start: begin a run of targets (default ["test-core"]; add "test-uefi", "test-jit-baseline",
  // "test-jit-opt" as AGENTS.md requires; test-core takes ~6.5 min, with test-uefi ~7.5 min, plus ~30 s to build) and
  // record HEAD, its tree and its base on origin/main in build/gate-runs/<id>.json; samaltak.push accepts a passed run
  // of the tree it pushes. isolate (default true) runs it in a detached worktree of HEAD under $TMPDIR/samaltak-gate
  // with its own build/ and TMPDIR (samaltak-ctl sessions): you can keep editing and building here, uncommitted and
  // untracked files are not tested, and a QEMU run here (uefiEval, ctlSession) or another worktree's test-uefi does
  // not collide with it. Its worktree is removed when the run passes, kept for a look when it fails (until the next
  // start). isolate: false runs in place and needs a clean worktree. One run at a time per directory: start (or wait
  // with no run of HEAD's tree) returns the running run instead of starting a second. wait (default): wait up to waitS
  // (<= 280) for run id (default: the latest run of HEAD's tree that covers targets, else one is started); call again
  // while state is "running". A run whose processes are gone without an exit status is "died". stop: end run id
  // (default: the running one) through its recorded process group, nothing else. status: the latest runs.
  const action = input.action ?? "wait";
  const dir = "build/gate-runs";
  const isolate = input.isolate ?? true;
  const q = (s: string) => "'" + s.replace(/'/g, "'\\''") + "'";
  const readRuns = async () => {
    const r = await exec(
      `mkdir -p ${dir}; for f in $(ls -t ${dir}/*.json 2>/dev/null | head -12); do b=\${f%.json}; e=$(cat $b.exit 2>/dev/null || echo); a=; p=$(cat $b.pid 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && a=1; printf '%s\\t%s\\t%s\\n' "$e" "$a" "$(cat "$f")"; done`,
    );
    return r.stdout
      .split("\n")
      .filter(Boolean)
      .map((l) => {
        const [exit, alive, json] = l.split("\t");
        const rec = JSON.parse(json);
        // runs recorded before pid files existed count as running until their exit file appears (for 2 hours)
        const old = !rec.pidFile && Date.now() / 1000 - rec.started < 7200;
        const state =
          exit !== ""
            ? ["passed", "stopped", "failed"][Number(exit) === 0 ? 0 : Number(exit) === 143 ? 1 : 2]
            : alive || old
              ? "running"
              : "died";
        return { ...rec, exit: exit === "" ? null : Number(exit), state };
      });
  };
  const summarize = async (rec: any) => {
    const log = `${dir}/${rec.id}.log`;
    const s = await exec(
      `grep -a -E '^[0-9]+ run, |^st_suite: |^(FAIL |ERROR )|: all passed|passed, [0-9]+ failed|make(\\[[0-9]+\\])?: \\*\\*\\*|^make test: FAILED|^test-uefi: |^qemu-system[^ ]*: ' ${log} 2>/dev/null | tail -25; echo "@@"; tail -n 4 ${log} 2>/dev/null`,
    );
    const [hits, tail] = s.stdout.split("@@\n");
    const targets: string[] = rec.targets.split(" ");
    const expectedS =
      30 +
      (targets.includes("test-core") ? 390 : 0) +
      (targets.includes("test-uefi") ? 90 : 0) +
      targets.filter((t) => t.startsWith("test-jit-")).length * 240;
    return {
      ...rec,
      elapsedS: Math.round((rec.finished ?? Date.now() / 1000) - rec.started),
      expectedS,
      log,
      results: hits
        .split("\n")
        .filter(Boolean)
        .map((l) => l.slice(0, 300)),
      tail: (tail ?? "")
        .split("\n")
        .filter(Boolean)
        .map((l) => l.slice(0, 300)),
      hint:
        rec.state === "failed"
          ? "a failure blocks only if the test passes on origin/main: rerun it alone (samaltak.suite) here and on origin/main" +
            (rec.workdir ? `; the run's tree stays at ${rec.workdir} until the next start` : "")
          : rec.state === "died"
            ? "the run's processes are gone without an exit status: start it again"
            : undefined,
    };
  };
  const covers = (r: any, want: string[]) => want.every((t) => r.targets.split(" ").includes(t));
  const start = async (): Promise<{ id: string; note?: string }> => {
    const targets = input.targets?.length ? input.targets : ["test-core"];
    for (const t of targets) if (!/^[A-Za-z0-9_.=\/-]+$/.test(t)) throw new Error(`gate: bad target ${t}`);
    if (input.out && !/^[A-Za-z0-9_.\/-]+$/.test(input.out)) throw new Error(`gate: bad out ${input.out}`);
    const runs = await readRuns();
    const running = runs.find((r) => r.state === "running");
    if (running)
      return {
        id: running.id,
        note: `a gate run (${running.targets}) is already running here: not starting a second one; wait for it, or stop it`,
      };
    const dirty = (await exec("git status --porcelain --untracked-files=no")).stdout.trim();
    if (dirty && !isolate)
      throw new Error("gate: commit first; the worktree has uncommitted changes:\n" + dirty.slice(0, 800));
    // worktrees of earlier isolated runs (already reported) go now
    for (const r of runs)
      if (r.workdir) await exec(`[ -d ${q(r.workdir)} ] && git worktree remove --force ${q(r.workdir)}; true`);
    await exec("git worktree prune");
    // runner: $1 runs dir, $2 id, $3 runtime dir, $4 private TMPDIR, $5 tree to test, $6 this directory, then make args
    const runner = `D=$1; I=$2; R=$3; T=$4; W=$5; O=$6; shift 6
echo $$ > "$D/$I.pid"
cd "$W" || exit 1
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json SDL_VIDEODRIVER=x11 SDL_VIDEO_X11_SCALING_FACTOR=2 XDG_RUNTIME_DIR="$R" TMPDIR="$T" xvfb-run -a -s "-screen 0 1280x1024x24" make "$@" > "$D/$I.log" 2>&1
e=$?
echo $e > "$D/$I.exit.tmp"; mv "$D/$I.exit.tmp" "$D/$I.exit"
rm -rf "$T"
if [ $e = 0 ] && [ "$W" != "$O" ]; then git -C "$O" worktree remove --force "$W" >/dev/null 2>&1; fi`;
    // starter: $1 runner, $2 isolate (1/0), $3 OUT or "", then the targets
    const starter = `set -e
runner=$1; iso=$2; out=$3; shift 3
git fetch -q origin || true
id=$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)
orig=$PWD; d=$orig/${dir}; mkdir -p "$d"
work=$orig
if [ "$iso" = 1 ]; then
  work=\${TMPDIR:-/tmp}/samaltak-gate/$(basename "$orig")-$id
  mkdir -p "$(dirname "$work")"
  git worktree add -q --detach "$work" HEAD
fi
printf '{"id":"%s","head":"%s","tree":"%s","base":"%s","targets":"%s","cwd":"%s","workdir":"%s","pidFile":true,"started":%s}\\n' "$id" "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "$(git merge-base HEAD origin/main)" "$*" "$orig" "$([ "$iso" = 1 ] && echo "$work")" "$(date +%s)" > "$d/$id.json"
rt=/tmp/samaltak-runtime-$(id -u); mkdir -p "$rt"; chmod 700 "$rt"
tmp=$d/$id.tmp; mkdir -p "$tmp"
[ -n "$out" ] && set -- "$@" "OUT=$out"
setsid sh -c "$runner" sh "$d" "$id" "$rt" "$tmp" "$work" "$orig" "$@" </dev/null >/dev/null 2>&1 &
for i in $(seq 1 100); do [ -s "$d/$id.pid" ] && break; sleep 0.1; done
echo "$id"`;
    const r = await execFile("sh", ["-c", starter, "sh", runner, isolate ? "1" : "0", input.out ?? "", ...targets], {
      timeoutMs: 120000,
    });
    if (r.code !== 0) throw new Error("gate: could not start: " + (r.stderr || r.stdout).slice(-600));
    const id = r.stdout.trim().split("\n").pop()!;
    const uncommitted = isolate
      ? (await exec("git status --porcelain")).stdout.split("\n").filter(Boolean)
      : [];
    return {
      id,
      note: uncommitted.length
        ? `not in the gated tree (uncommitted here): ${uncommitted.slice(0, 12).join(", ")}${uncommitted.length > 12 ? ", ..." : ""}`
        : undefined,
    };
  };
  if (action === "status")
    return {
      runs: (await readRuns()).slice(0, 6).map((r) => ({
        id: r.id,
        state: r.state,
        targets: r.targets,
        head: r.head?.slice(0, 9),
        workdir: r.workdir || undefined,
      })),
    };
  if (action === "stop") {
    const runs = await readRuns();
    const rec = input.id ? runs.find((r) => r.id === input.id) : runs.find((r) => r.state === "running");
    if (!rec) return { stopped: false, reason: input.id ? `no run ${input.id}` : "no gate run is running here" };
    if (rec.state !== "running") return { stopped: false, reason: `run ${rec.id} is ${rec.state}` };
    const k = await exec(
      `p=$(cat ${dir}/${rec.id}.pid 2>/dev/null); [ -n "$p" ] || exit 3; kill -TERM -- -$p 2>/dev/null; sleep 3; kill -KILL -- -$p 2>/dev/null; [ -f ${dir}/${rec.id}.exit ] || echo 143 > ${dir}/${rec.id}.exit; echo $p`,
      { timeoutMs: 30000 },
    );
    if (k.code !== 0) return { stopped: false, reason: `run ${rec.id} has no pid file (started by an older gate): stop it by hand` };
    // what the run started in its own group (a samaltak-ctl --uefi session's make and QEMU) works in its tree: by PID
    if (rec.workdir)
      await exec(
        `for c in /proc/[0-9]*/cwd; do case "$(readlink $c 2>/dev/null)" in ${q(rec.workdir)}|${q(rec.workdir)}/*) p=\${c#/proc/}; kill -KILL \${p%/cwd} 2>/dev/null;; esac; done; git worktree remove --force ${q(rec.workdir)}; git worktree prune`,
      );
    return { stopped: true, id: rec.id, processGroup: Number(k.stdout.trim()) };
  }
  let id = input.id;
  let note: string | undefined;
  if (action === "start") ({ id, note } = await start());
  if (!id) {
    const tree = (await exec("git rev-parse 'HEAD^{tree}'")).stdout.trim();
    const want = input.targets ?? [];
    const existing = (await readRuns()).find(
      (r) => r.tree === tree && covers(r, want) && (r.state === "running" || r.state === "passed"),
    );
    if (existing) id = existing.id;
    else ({ id, note } = await start());
  }
  const waitS = action === "start" ? 0 : Math.min(Math.max(input.waitS ?? 270, 0), 280);
  if (waitS > 0)
    await exec(
      `for i in $(seq 1 ${Math.ceil(waitS / 5)}); do [ -f ${dir}/${id}.exit ] && break; p=$(cat ${dir}/${id}.pid 2>/dev/null); [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null && break; sleep 5; done`,
      { timeoutMs: (waitS + 15) * 1000 },
    );
  const rec = (await readRuns()).find((r) => r.id === id);
  if (!rec) throw new Error(`gate: no run ${id} in ${dir}`);
  if (rec.state === "passed" || rec.state === "failed")
    rec.finished = Number((await exec(`stat -c %Y ${dir}/${id}.exit`)).stdout.trim());
  return { ...(await summarize(rec)), note };
}
