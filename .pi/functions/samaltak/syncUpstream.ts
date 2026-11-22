/** Merge upstream (schani/samaltak) into the fork: fetch, report the new upstream commits, what they touch (VM, overlap with the fork) and a trial merge's conflicts; without dryRun, make the real merge commit (never a rebase or squash) on top of origin/main, leaving conflicts to resolve, and say which gate stages it needs. */
async function syncUpstream(
  { shell: { exec } },
  input: { dryRun?: boolean; remote?: string; branch?: string; message?: string } = {},
) {
  // The fork (origin) follows upstream (remote "upstream", branch main) by merges: its history is published, so upstream's
  // commits come in as they are, through a merge commit, never rebased or squashed. dryRun (default true) only fetches
  // and reports: the upstream commits not yet merged, the files they change, whether they touch the VM (src/VM-*, vm/),
  // the files both sides changed since the merge base, and a trial merge (git merge-tree, nothing written) with its
  // conflicts. dryRun: false, in a clean worktree whose HEAD is origin/main (or behind it, fast-forwarded): git merge
  // --no-ff upstream/main with message (default "Merge upstream/main (<sha>): <subjects>"). Conflicts stay in the worktree
  // for you to resolve keeping both sides' intent (read both commits), except vm/gen: take either side, then
  // samaltak.build({ target: "translate" }) regenerates it; then git add and git commit --no-edit. After the merge:
  // build (translate when the VM changed), samaltak.gate with the stages it lists (or ["auto"]), and samaltak.push, which
  // pushes a merge on top of origin/main as it is. If origin/main moved meanwhile, merge origin/main into it (again a
  // merge, not a rebase) and gate that.
  const remote = input.remote ?? "upstream";
  const branch = input.branch ?? "main";
  if (!/^[A-Za-z0-9_.-]+$/.test(remote) || !/^[A-Za-z0-9_.\/-]+$/.test(branch))
    throw new Error("syncUpstream: bad remote or branch");
  const dryRun = input.dryRun ?? true;
  const sh = async (c: string, timeoutMs = 120000) => {
    const r = await exec(c, { timeoutMs });
    return { code: r.code, out: (r.stdout + r.stderr).trim() };
  };
  const up = `${remote}/${branch}`;
  if ((await sh(`git remote get-url ${remote}`)).code !== 0)
    throw new Error(
      `syncUpstream: no remote ${remote} (git remote add ${remote} https://github.com/schani/samaltak.git)`,
    );
  const f = await sh(`git fetch -q ${remote} && git fetch -q origin`);
  if (f.code !== 0) throw new Error(`syncUpstream: fetch failed: ${f.out.slice(-400)}`);
  const lines = (s: string) => s.split("\n").filter(Boolean);
  const incoming = lines((await sh(`git log --format='%h %s' origin/main..${up}`)).out);
  if (!incoming.length)
    return { ok: true, upToDate: true, note: `${up} is already merged into origin/main` };
  const base = (await sh(`git merge-base origin/main ${up}`)).out;
  const upFiles = lines((await sh(`git diff --name-only ${base} ${up}`)).out);
  const forkFiles = new Set(lines((await sh(`git diff --name-only ${base} origin/main`)).out));
  const overlap = upFiles.filter((x) => forkFiles.has(x));
  const vm = upFiles.filter((x) => /^src\/VM-|^vm\//.test(x) && !x.startsWith("vm/tests/bench/"));
  const trial = await sh(`git merge-tree --write-tree --name-only --messages origin/main ${up}`);
  // exit 0: clean; 1: conflicts (after the tree id, the conflicted files, then the messages)
  const conflicts = trial.code === 1 ? lines(trial.out).filter((l) => /^CONFLICT /.test(l)) : [];
  const stages = [
    "test-core",
    "test-uefi",
    ...(vm.length ? ["test-jit-baseline", "test-jit-opt"] : []),
  ];
  const report = {
    incoming: incoming.slice(0, 40),
    moreIncoming: Math.max(0, incoming.length - 40),
    upstreamFiles: upFiles.length,
    vmTouched: vm.slice(0, 15),
    overlap: overlap.slice(0, 30),
    conflicts: conflicts.slice(0, 30).map((l) => l.slice(0, 200)),
    trialError: trial.code > 1 ? trial.out.slice(-400) : undefined,
    gateTargets: stages,
    translate: vm.length > 0,
  };
  if (dryRun) return { ok: true, dryRun: true, ...report };
  const dirty = (await sh("git status --porcelain --untracked-files=no")).out;
  if (dirty)
    return {
      ok: false,
      reason: "uncommitted changes: commit or stash them first",
      files: lines(dirty).slice(0, 20),
      ...report,
    };
  if ((await sh("git merge-base --is-ancestor HEAD origin/main")).code !== 0)
    return {
      ok: false,
      reason:
        "HEAD has commits not on origin/main: sync from a worktree at origin/main (git switch -C <branch> origin/main)",
      ...report,
    };
  await sh("git merge -q --ff-only origin/main");
  const head = (await sh(`git rev-parse --short ${up}`)).out;
  const subjects = incoming
    .map((l) => l.replace(/^\S+ /, ""))
    .slice(0, 3)
    .join("; ");
  const msg =
    input.message ??
    `Merge ${up} (${head}): ${subjects}${incoming.length > 3 ? `; and ${incoming.length - 3} more` : ""}`;
  const m = await sh(`git merge --no-ff -m '${msg.replace(/'/g, "'\\''")}' ${up}`, 180000);
  const unmerged = lines((await sh("git diff --name-only --diff-filter=U")).out);
  if (m.code !== 0 && unmerged.length)
    return {
      ok: false,
      merging: true,
      unmerged,
      next: [
        'resolve each file keeping both sides\' intent (git show the upstream commits); vm/gen: git checkout --theirs or --ours, then samaltak.build({ target: "translate" })',
        "git add the files; git commit --no-edit (the merge commit)",
        `samaltak.gate({ action: "start", targets: ${JSON.stringify(stages)} }), then samaltak.push()`,
      ],
      ...report,
    };
  if (m.code !== 0)
    return { ok: false, reason: "git merge failed", detail: m.out.slice(-600), ...report };
  return {
    ok: true,
    merged: (await sh("git log --oneline -1")).out,
    next: [
      ...(vm.length
        ? ['samaltak.build({ target: "translate" }): commit vm/gen if it changed (gen)']
        : ["samaltak.build()"]),
      `samaltak.gate({ action: "start", targets: ${JSON.stringify(stages)} }), then samaltak.push()`,
    ],
    ...report,
  };
}
