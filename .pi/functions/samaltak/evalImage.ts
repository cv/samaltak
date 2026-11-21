/** Evaluate a Smalltalk expression in this directory's image headlessly with stdin closed and a timeout (after rebuilding the image if asked); errors come back as text (class, message, three contexts) instead of hanging the VM. */
async function evalImage(
  { shell: { execFile }, samaltak: { build: make } },
  input: {
    expr: string;
    image?: string;
    build?: boolean;
    out?: string;
    vmArgs?: string[];
    timeoutS?: number;
    maxLines?: number;
    catchErrors?: boolean;
  },
) {
  // Evaluates a Smalltalk expression in a Samaltak image headlessly, in the current directory (a worktree's own build).
  // Stdin is closed and a hard timeout applies. With catchErrors (default), the expression runs inside
  // [ ... ] on: Error do: and an error comes back as 'ERROR <class>: <message> in <context> < <sender> < ...'
  // instead of leaving the VM waiting (an uncaught error in a headless --eval does not exit).
  // timeoutS defaults to 25 s so a call fits the typescript tool's default 30 s; for longer runs raise both.
  // build: first make the image (samaltak.build, incremental) and stop if that fails; out: the build directory (OUT,
  // default "build"), image defaults to its samaltak.image.
  if (!input?.expr?.trim()) throw new Error("expr is required");
  const out = input.out ?? "build";
  const image = input.image ?? `${out}/samaltak.image`;
  const built = input.build ? await make({ target: "all", out }) : undefined;
  if (built && !built.ok)
    return {
      build: built,
      code: built.code,
      timedOut: built.timedOut,
      error: "build failed: nothing evaluated",
      stdout: "",
      stderr: built.errors.join("\n"),
      truncated: false,
    };
  const timeoutS = Math.min(Math.max(input.timeoutS ?? 25, 1), 280);
  const maxLines = Math.min(Math.max(input.maxLines ?? 40, 1), 400);
  const expr =
    (input.catchErrors ?? true)
      ? `[${input.expr}] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText printString, ' in ', e signalerContext printString, ' < ', e signalerContext sender printString, ' < ', e signalerContext sender sender printString]`
      : input.expr;
  const args = [
    "-k",
    "5",
    String(timeoutS),
    "vm/build/samaltak",
    image,
    "--headless",
    ...(input.vmArgs ?? []),
    "--eval",
    expr,
  ];
  const r = await execFile("sh", ["-c", 'exec timeout "$@" </dev/null', "sh", ...args], {
    timeoutMs: (timeoutS + 10) * 1000,
    maxLines,
    truncate: "tail",
  });
  const stdout = r.stdout.trimEnd();
  return {
    build: built && { seconds: built.seconds, warnings: built.warnings },
    code: r.code,
    timedOut: r.code === 124 || r.code === 137,
    error: /^'ERROR /.test(stdout.split("\n").pop() ?? "") ? stdout.split("\n").pop() : undefined,
    stdout,
    stderr: r.stderr.trimEnd().split("\n").slice(-maxLines).join("\n"),
    truncated: r.truncated,
  };
}
