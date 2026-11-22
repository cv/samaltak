/** Build with make in this directory (default target all: VM, seed, image; or image, vm, uefi, or translate: the VM's Lowtalk into vm/gen, then the VM) into OUT, within a timeout, and return ok, seconds, the image builder's warnings (undeclared variables, layering), the errors, and for translate whether vm/gen changed. */
async function build(
  { shell: { execFile } },
  input: {
    target?: "all" | "image" | "vm" | "uefi" | "translate";
    out?: string;
    timeoutS?: number;
  } = {},
) {
  // make is incremental: an up-to-date tree takes a second, an image after src/ changes ~10 s, the VM from scratch
  // a few minutes. out (OUT, default "build") keeps builds apart: a dev build in "build/dev" leaves a running gate's
  // or another agent's image alone (samaltak.suite/evalImage take the same out). Stdin is closed; on the timeout make
  // and its children are stopped (timeout -k), so no half-built image keeps building behind your back.
  // translate (make translate: the image, VMTranslator generateVM into vm/gen, then the VM; ~1-4 min) after changing
  // src/VM-* or after a rebase or merge that touched them: vm/gen is checked in and generated, so conflicts in it are
  // resolved by translating again, never by hand. Its result adds translation ('ok' or the translator's error) and
  // gen: the vm/gen files that now differ from HEAD (commit them with the sources; test-core's gen_test fails otherwise).
  const target = input.target ?? "all";
  if (!["all", "image", "vm", "uefi", "translate"].includes(target))
    throw new Error(`build: bad target ${target}`);
  const out = input.out ?? "build";
  if (!/^[A-Za-z0-9_.\/-]+$/.test(out) || out.split("/").includes(".."))
    throw new Error(`build: bad out ${out}`);
  const timeoutS = Math.min(Math.max(input.timeoutS ?? 280, 10), 290);
  const t0 = Date.now();
  const r = await execFile(
    "sh",
    [
      "-c",
      'exec timeout -k 5 "$1" make "$2" "OUT=$3" </dev/null 2>&1',
      "sh",
      String(timeoutS),
      target,
      out,
    ],
    { timeoutMs: (timeoutS + 10) * 1000, maxLines: 4000, truncate: "tail" },
  );
  const lines = r.stdout.split("\n");
  const cWarning = /^\S+\.[ch]:\d+:\d+: warning:/;
  const uniq = (xs: string[]) => [...new Set(xs)];
  const warnings = uniq(
    lines.filter(
      (l) =>
        /warning|undeclared|layering/i.test(l) &&
        !cWarning.test(l) &&
        !/^(cc|clang|gcc) |^\s|^\d+ warnings? generated\.?$/.test(l),
    ),
  );
  const errors = uniq(
    lines.filter((l) =>
      /\*\*\*|: (fatal )?error:|^Error |undefined reference|image builder: error|^stage 2: .*(error|failed)|Error class>>|^[A-Z][A-Za-z]*Error: /.test(
        l,
      ),
    ),
  );
  const timedOut = r.code === 124 || r.code === 137;
  let translation: string | undefined;
  let gen: string[] | undefined;
  if (target === "translate") {
    // the line after the translator's eval: 'ok', or the error's messageText
    const i = lines.findIndex((l) => l.includes("VMTranslator generateVM"));
    translation =
      i >= 0 ? (lines.slice(i + 1).find((l) => l.trim()) ?? "").slice(0, 400) : undefined;
    const g = await execFile("git", ["status", "--porcelain", "--", "vm/gen"]);
    gen = g.stdout.split("\n").filter(Boolean).slice(0, 60);
  }
  return {
    ok: r.code === 0 && (target !== "translate" || translation === "'ok'"),
    code: r.code,
    timedOut,
    target: target as any,
    image: `${out}/samaltak.image`,
    seconds: Math.round((Date.now() - t0) / 100) / 10,
    translation,
    gen,
    warnings: warnings.slice(0, 30).map((l) => l.slice(0, 300)),
    cWarnings: lines.filter((l) => cWarning.test(l)).length,
    errors: errors.slice(0, 20).map((l) => l.slice(0, 400)),
    tail:
      r.code === 0
        ? []
        : lines
            .filter((l) => l.trim())
            .slice(-15)
            .map((l) => l.slice(0, 300)),
    hint: timedOut
      ? "make did not finish: call build again (it resumes where it stopped) with a longer call timeoutMs"
      : target === "translate" && translation !== undefined && translation !== "'ok'"
        ? "the translator failed: fix the Lowtalk source it names, then translate again"
        : undefined,
  };
}
