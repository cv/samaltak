/** A/B benchmarks for performance work (AGENTS.md): Are We Fast Yet / micro / workload benchmarks (vm/tests/bench/awfy.sh) of this tree against origin/main (or another ref, built once in a cached worktree), interleaved, pinned to one big core, CPU time; per benchmark the steady-state medians, the change and whether it is a regression beyond the threshold. */
async function bench(
  { shell: { exec }, samaltak: { build: make } },
  input: {
    benchmarks: string[];
    vmArgs?: string;
    init?: string;
    against?: string | null;
    iterations?: number;
    rounds?: number;
    cpu?: string;
    cpuTime?: boolean;
    build?: boolean;
    threshold?: number;
    timeoutS?: number;
  },
) {
  // benchmarks: awfy.sh names (Bounce, CD, DeltaBlue, Havlak, Json, List, Mandelbrot, NBody, Permute, Queens,
  // Richards, Sieve, Storage, Towers; MicroFib ... MicroFactorial; Recompile, TextRendering; the realworld and Adv*
  // ones; name:inner sets the inner iterations), vmArgs e.g. "--jit opt". against (default "origin/main"; null: this
  // tree only) is checked out once per commit in $TMPDIR/samaltak-bench/<sha> and built there (make; the first build of
  // a VM takes minutes: if it does not finish, the result says building, call again); this tree is built first unless
  // build: false. Each round runs every benchmark once per tree, one VM process each (awfy.sh -n iterations, default 10),
  // the trees' order alternating, pinned with taskset to cpu (default: the highest-numbered core of the highest maximum
  // frequency, a Cortex-X925 on the DGX Spark; an unpinned VM lands on an A725 at half the speed; "none" to not pin),
  // measuring the Smalltalk thread's CPU time (cpuTime, default true; awfy.sh --cpu). Steady state: the median of an
  // invocation's second half of laps; per tree the median over rounds (default 3). change = new/base - 1; regression
  // when change > threshold % (default 5, AGENTS.md's bar) and above the rounds' spread: rerun those before believing
  // it. Stops starting runs at timeoutS (default 250) and reports what it measured (complete: false). init: Smalltalk
  // each run evaluates before the benchmark (awfy.sh --init, e.g. "Profiler default stop"); with it both trees run
  // this tree's awfy.sh and benchmark sources (the base's may predate --init).
  const t0 = Date.now();
  const timeoutS = Math.min(Math.max(input.timeoutS ?? 250, 20), 285);
  const deadline = t0 + timeoutS * 1000;
  const names = input.benchmarks ?? [];
  if (!names.length || names.some((b) => !/^[A-Za-z][A-Za-z0-9]*(:\d+)?$/.test(b)))
    throw new Error("bench: benchmarks: awfy.sh names such as Bounce, MicroFib or Json:5");
  const vmArgs = input.vmArgs ?? "";
  if (!/^[A-Za-z0-9 =_.,-]*$/.test(vmArgs)) throw new Error("bench: bad vmArgs");
  const init = input.init ?? "";
  if (/[\n']/.test(init)) throw new Error("bench: init: one line, no single quotes (use #symbols)");
  const iterations = Math.min(Math.max(input.iterations ?? 10, 2), 100);
  const rounds = Math.min(Math.max(input.rounds ?? 3, 1), 10);
  const threshold = input.threshold ?? 5;
  const q = (s: string) => "'" + s.replace(/'/g, "'\\''") + "'";
  const sh = async (c: string, timeoutMs = 60000) => {
    const r = await exec(c, { timeoutMs });
    return { code: r.code, out: (r.stdout + r.stderr).trim() };
  };
  // the core to pin to
  let cpu = input.cpu ?? "";
  if (!cpu) {
    const f = await sh(
      "grep -H . /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq 2>/dev/null",
    );
    const cores = f.out
      .split("\n")
      .map((l) => l.match(/cpu(\d+)\/cpufreq\/cpuinfo_max_freq:(\d+)/))
      .filter((m): m is RegExpMatchArray => !!m)
      .map((m) => ({ n: Number(m[1]), f: Number(m[2]) }));
    const top = Math.max(...cores.map((c) => c.f));
    cpu = cores.length
      ? String(Math.max(...cores.filter((c) => c.f === top).map((c) => c.n)))
      : "none";
  }
  if (cpu !== "none" && !/^[0-9,-]+$/.test(cpu))
    throw new Error("bench: cpu is a taskset list such as 17, or none");
  const here = (await sh("pwd")).out;
  const trees: Array<{ label: string; dir: string }> = [{ label: "new", dir: here }];
  let built: Record<string, string> = {};
  if (input.build ?? true) {
    const b = await make({
      target: "all",
      timeoutS: Math.max(20, Math.min(280, Math.floor((deadline - Date.now()) / 1000) - 10)),
    });
    if (!b.ok)
      return {
        ok: false,
        state: b.timedOut ? "building" : "build failed",
        tree: "new",
        errors: b.errors,
        tail: b.tail,
      };
    built.new = `${b.seconds} s`;
  }
  let againstSha: string | undefined;
  if (input.against !== null) {
    const ref = input.against ?? "origin/main";
    if (!/^[A-Za-z0-9_.\/^~-]+$/.test(ref)) throw new Error("bench: bad against");
    if (ref.startsWith("origin/")) await sh("git fetch -q origin");
    againstSha = (await sh(`git rev-parse --verify ${q(ref + "^{commit}")}`)).out;
    if (!/^[0-9a-f]{40}$/.test(againstSha)) throw new Error(`bench: unknown ref ${ref}`);
    const dir = (await sh(`printf %s "\${TMPDIR:-/tmp}/samaltak-bench/${againstSha.slice(0, 12)}"`))
      .out;
    if ((await sh(`test -d ${q(dir)}`)).code !== 0) {
      const w = await sh(
        `mkdir -p "$(dirname ${q(dir)})" && git worktree add -q --detach ${q(dir)} ${againstSha}`,
      );
      if (w.code !== 0) throw new Error(`bench: worktree for ${ref}: ${w.out.slice(-300)}`);
    }
    const left = Math.floor((deadline - Date.now()) / 1000) - 10;
    const b = await exec(
      `cd ${q(dir)} && exec timeout -k 5 ${Math.max(10, left)} make all </dev/null 2>&1`,
      {
        timeoutMs: (Math.max(10, left) + 15) * 1000,
        maxLines: 30,
        truncate: "tail",
      },
    );
    if (b.code !== 0)
      return {
        ok: false,
        state: b.code === 124 || b.code === 137 ? "building" : "build failed",
        tree: `${ref} (${againstSha.slice(0, 9)}) in ${dir}`,
        tail: b.stdout
          .split("\n")
          .filter(Boolean)
          .slice(-8)
          .map((l) => l.slice(0, 300)),
        hint:
          b.code === 124 || b.code === 137
            ? "the baseline is still building: call bench again (make resumes)"
            : undefined,
      };
    built.base = "ok";
    trees.push({ label: "base", dir });
  }
  const load = (await sh("cut -d' ' -f1-3 /proc/loadavg")).out;
  const steady: Record<string, Record<string, number[]>> = {};
  const errors: string[] = [];
  let complete = true;
  const median = (a: number[]) => {
    const s = [...a].sort((x, y) => x - y);
    const n = s.length;
    return n ? (n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2) : NaN;
  };
  outer: for (let r = 0; r < rounds; r++)
    for (const b of names)
      for (const t of r % 2 ? [...trees].reverse() : trees) {
        if (Date.now() > deadline - 15000) {
          complete = false;
          break outer;
        }
        const left = Math.floor((deadline - Date.now()) / 1000);
        const cmd = `${cpu === "none" ? "" : `taskset -c ${cpu} `}sh ${q((init ? here : t.dir) + "/vm/tests/bench/awfy.sh")}${init ? ` --init ${q(init)}` : ""} --vm ${q(t.dir + "/vm/build/samaltak")} --image ${q(t.dir + "/build/samaltak.image")}${vmArgs ? ` --vm-args ${q(vmArgs)}` : ""}${(input.cpuTime ?? true) ? " --cpu" : ""} -n ${iterations} ${b} </dev/null 2>&1`;
        const o = await exec(`timeout -k 5 ${left} ${cmd}`, {
          timeoutMs: (left + 10) * 1000,
          maxLines: 400,
        });
        const laps = o.stdout
          .split("\n")
          .map((l) => l.match(/^([A-Za-z0-9]+),(\d+),(-?\d+)$/))
          .filter((m): m is RegExpMatchArray => !!m)
          .map((m) => Number(m[3]));
        const name = b.split(":")[0];
        if (laps.length < 2) {
          errors.push(
            `${t.label} ${b}: ${o.stdout.split("\n").filter(Boolean).slice(-2).join(" | ").slice(0, 300)}`,
          );
          continue;
        }
        ((steady[name] ??= {})[t.label] ??= []).push(
          median(laps.slice(Math.floor(laps.length / 2))) / 1000,
        );
      }
  const rows = Object.entries(steady).map(([name, by]) => {
    const n = by.new ?? [];
    const base = by.base ?? [];
    const mn = median(n);
    const mb = median(base);
    const spread = (a: number[]) =>
      a.length > 1 ? Math.round((Math.max(...a) / Math.min(...a) - 1) * 1000) / 10 : 0;
    const change = base.length && n.length ? Math.round((mn / mb - 1) * 1000) / 10 : null;
    return {
      benchmark: name,
      newMs: Math.round(mn * 100) / 100,
      baseMs: base.length ? Math.round(mb * 100) / 100 : undefined,
      changePct: change,
      spreadPct: { new: spread(n), base: base.length ? spread(base) : undefined },
      runs: { new: n.length, base: base.length },
      regression:
        change !== null && change > threshold && change > Math.max(spread(n), spread(base)),
      improvement:
        change !== null && change < -threshold && -change > Math.max(spread(n), spread(base)),
    };
  });
  return {
    ok: errors.length === 0,
    complete,
    against: againstSha ? `${input.against ?? "origin/main"} ${againstSha.slice(0, 9)}` : null,
    cpu,
    vmArgs,
    init: init || undefined,
    iterations,
    rounds,
    loadBefore: load,
    seconds: Math.round((Date.now() - t0) / 1000),
    built,
    results: rows,
    regressions: rows.filter((r) => r.regression).map((r) => r.benchmark),
    errors: errors.slice(0, 10),
    hint: complete
      ? undefined
      : "stopped at timeoutS: fewer rounds or benchmarks per call, or call again and combine",
  };
}
