/** Run tests/st_suite.sh on packages or test classes (optional VM/JIT args), after rebuilding the image if asked (build, out), and return ok, the summary line, FAIL/ERROR lines and a short tail. */
async function suite(
  { shell: { execFile }, samaltak: { build: make } },
  input: {
    tests?: string[];
    vmArgs?: string[];
    image?: string;
    build?: boolean;
    out?: string;
    timeoutS?: number;
    maxFailures?: number;
  } = {},
) {
  // Runs tests/st_suite.sh (the image's Smalltalk tests, headless) on packages or test classes in the current directory,
  // e.g. { tests: ["Tests-Crypto", "TLSSocketTest"] }; all tests when none are given. vmArgs go before the image
  // (e.g. ["--jit", "opt", "--jit-threshold", "0"]). Returns ok, the summary line, FAIL/ERROR lines, and the tail.
  // build: first make the image (samaltak.build: VM, seed, image; incremental) and stop there if it fails; out: the build
  // directory (OUT, default "build"; e.g. "build/dev" so a running gate's build is left alone), image defaults to its
  // samaltak.image. Make the tool call's timeoutMs longer than timeoutS (plus the build).
  const out = input.out ?? "build";
  const image = input.image ?? `${out}/samaltak.image`;
  const built = input.build ? await make({ target: "all", out }) : undefined;
  if (built && !built.ok)
    return {
      build: built,
      ok: false,
      code: built.code,
      timedOut: built.timedOut,
      summary: null,
      verdict: ["build failed: no tests run"],
      failures: built.errors,
      moreFailures: 0,
      tail: built.tail,
    };
  const timeoutS = Math.min(Math.max(input.timeoutS ?? 280, 10), 290);
  const max = Math.min(Math.max(input.maxFailures ?? 30, 1), 200);
  const r = await execFile(
    "tests/st_suite.sh",
    [image, ...(input.vmArgs ?? []), "--", ...(input.tests ?? [])],
    {
      timeoutMs: timeoutS * 1000,
      maxLines: 20000,
      truncate: "tail",
    },
  );
  const lines = (r.stdout + "\n" + r.stderr).split("\n");
  const summary = lines.filter((l) => /^\d+ run, /.test(l)).pop() ?? null;
  const failures = lines.filter((l) => /^(FAIL |ERROR )/.test(l));
  const verdict = lines.filter((l) => /^st_suite: /.test(l));
  return {
    build: built && { seconds: built.seconds, warnings: built.warnings },
    ok: r.code === 0,
    code: r.code,
    timedOut: r.code === null || r.code === 124,
    summary,
    verdict,
    failures: failures.slice(0, max).map((l) => l.slice(0, 400)),
    moreFailures: Math.max(0, failures.length - max),
    tail: lines
      .filter((l) => l.trim())
      .slice(-12)
      .map((l) => l.slice(0, 300)),
  };
}
