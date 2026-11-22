/** Merge pull requests (the in-image agent's agent/* PRs) the gated way: check combines them on origin/main in a scratch worktree (conflicts per PR, files) and can leave the combination on a branch to gate; merge rebase-merges them on GitHub in order, rebasing a conflicting PR's branch with the gated combination's resolution (force-with-lease), and verifies main ends up with the gated files; dryRun available. */
async function mergePRs(
  { shell: { exec } },
  input: {
    numbers?: number[];
    action?: "check" | "merge";
    repo?: string;
    branch?: string;
    combined?: string;
    skipGateReason?: string;
    dryRun?: boolean;
  } = {},
) {
  // check (default): the PRs' state, files and GitHub mergeability, then a trial: their commits cherry-picked (-x) in
  // order onto origin/main in a scratch worktree ($TMPDIR/samaltak-prs-*, removed after); a PR that conflicts is
  // reported with its files and left out. branch: if every PR applied, also make that local branch at the combination
  // (git switch to it, samaltak.build/suite, samaltak.gate). When PRs conflict with each other, combine them by hand on a
  // branch from origin/main (git fetch origin pull/N/head; git cherry-pick -x; resolve) and gate that instead.
  // merge: combined (default the branch, else HEAD) must be origin/main plus exactly these PRs with a passed samaltak.gate
  // run of its tree (build/gate-runs here), or give skipGateReason. Then for each PR in order: gh pr merge --rebase when
  // GitHub can; when the PR conflicts with main (an earlier PR touched the same file), its commits are cherry-picked
  // onto the new origin/main, each conflicted file taken from the combination, the PR's branch force-pushed with lease,
  // and merged. Refuses PRs from other repositories and PRs whose files main changed since the combination's base.
  // Finally origin/main's version of every PR file must equal the combination's (verified). dryRun: checks and plan only.
  // numbers default: the open PRs whose branch starts with agent/. repo default: origin's (not gh's default, which is
  // upstream in this clone).
  const action = input.action ?? "check";
  const sh = async (c: string, timeoutMs = 120000) => {
    const r = await exec(c, { timeoutMs });
    return { code: r.code, out: (r.stdout + r.stderr).trim() };
  };
  const q = (s: string) => "'" + s.replace(/'/g, "'\\''") + "'";
  const lines = (s: string) => s.split("\n").filter(Boolean);
  const repo =
    input.repo ??
    (await sh("git remote get-url origin")).out.match(
      /github\.com[:/]([^/\s]+\/[^/\s]+?)(\.git)?$/,
    )?.[1] ??
    "";
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo))
    throw new Error(`mergePRs: bad repo "${repo}" (give repo: owner/name)`);
  if (input.branch && !/^[A-Za-z0-9_.\/-]+$/.test(input.branch))
    throw new Error("mergePRs: bad branch");
  let numbers = input.numbers ?? [];
  if (!numbers.length) {
    const l = await sh(
      `gh pr list -R ${repo} --state open --limit 50 --json number,headRefName -q '.[] | select(.headRefName | startswith("agent/")) | .number'`,
    );
    numbers = lines(l.out)
      .map(Number)
      .filter((n) => n > 0)
      .sort((a, b) => a - b);
    if (!numbers.length) return { ok: true, repo, prs: [], note: "no open agent/ pull requests" };
  }
  if (numbers.some((n) => !Number.isInteger(n) || n <= 0))
    throw new Error("mergePRs: bad PR number");
  const fields =
    "number,state,title,headRefName,headRefOid,isCrossRepository,mergeable,mergeStateStatus,files";
  const view = async (n: number) => {
    for (let i = 0; i < 6; i++) {
      const v = await sh(`gh pr view ${n} -R ${repo} --json ${fields}`);
      if (v.code !== 0) throw new Error(`mergePRs: gh pr view ${n}: ${v.out.slice(-300)}`);
      const p = JSON.parse(v.out);
      if (p.mergeable !== "UNKNOWN" || p.state !== "OPEN") return p;
      await sh("sleep 3");
    }
    return JSON.parse((await sh(`gh pr view ${n} -R ${repo} --json ${fields}`)).out);
  };
  await sh("git fetch -q origin");
  const prs: any[] = [];
  for (const n of numbers) {
    const p = await view(n);
    const f = await sh(`git fetch -q origin pull/${n}/head && git rev-parse FETCH_HEAD`);
    if (f.code !== 0)
      throw new Error(`mergePRs: cannot fetch pull/${n}/head: ${f.out.slice(-300)}`);
    const sha = lines(f.out).pop()!;
    const commits = lines((await sh(`git rev-list --reverse --no-merges origin/main..${sha}`)).out);
    prs.push({
      number: n,
      title: p.title,
      state: p.state,
      branch: p.headRefName,
      cross: p.isCrossRepository,
      mergeable: `${p.mergeable}/${p.mergeStateStatus}`,
      files: (p.files ?? []).map((x: any) => x.path),
      sha,
      commits,
    });
  }
  const notOpen = prs.filter((p) => p.state !== "OPEN");
  const summary = prs.map((p) => ({
    number: p.number,
    title: p.title.slice(0, 120),
    state: p.state,
    branch: p.branch,
    mergeable: p.mergeable,
    commits: p.commits.length,
    files: p.files.slice(0, 15),
  }));
  // a scratch worktree at a ref; the callback works in it; always removed
  const scratch = async <T>(ref: string, fn: (w: string) => Promise<T>): Promise<T> => {
    const w = (await sh(`mktemp -d "\${TMPDIR:-/tmp}/samaltak-prs-XXXXXX"`)).out;
    const a = await sh(`git worktree add -q --detach ${q(w)} ${ref}`);
    if (a.code !== 0) throw new Error(`mergePRs: worktree: ${a.out.slice(-300)}`);
    try {
      return await fn(w);
    } finally {
      await sh(
        `git -C ${q(w)} cherry-pick --abort >/dev/null 2>&1; git worktree remove --force ${q(w)}; git worktree prune`,
      );
    }
  };
  // check: combine on origin/main
  const trial = await scratch("origin/main", async (w) => {
    const res: Array<{ number: number; applied: boolean; conflicts?: string[] }> = [];
    for (const p of prs.filter((x) => x.state === "OPEN")) {
      const before = (await sh(`git -C ${q(w)} rev-parse HEAD`)).out;
      const c = await sh(`git -C ${q(w)} cherry-pick -x ${p.commits.join(" ")}`);
      if (c.code === 0) res.push({ number: p.number, applied: true });
      else {
        const files = lines((await sh(`git -C ${q(w)} diff --name-only --diff-filter=U`)).out);
        await sh(`git -C ${q(w)} cherry-pick --abort; git -C ${q(w)} reset -q --hard ${before}`);
        res.push({ number: p.number, applied: false, conflicts: files });
      }
    }
    const head = (await sh(`git -C ${q(w)} rev-parse HEAD`)).out;
    return { res, head };
  });
  const allApplied = trial.res.every((r) => r.applied) && !notOpen.length;
  if (action === "check") {
    let branch: string | undefined;
    if (input.branch && allApplied && !input.dryRun) {
      const b = await sh(`git branch -f ${input.branch} ${trial.head}`);
      if (b.code !== 0) throw new Error(`mergePRs: branch: ${b.out}`);
      branch = input.branch;
    }
    return {
      ok: allApplied,
      repo,
      prs: summary,
      trial: trial.res,
      branch,
      next: allApplied
        ? branch
          ? [
              `git switch ${branch}; samaltak.build(); samaltak.suite({ tests: [...] }); samaltak.gate({ action: "start", targets: ["auto"] })`,
              `then mergePRs({ numbers: ${JSON.stringify(numbers)}, action: "merge", combined: "${branch}" })`,
            ]
          : ['check again with branch: "prs/combined" to keep the combination for the gate']
        : [
            "combine by hand on a branch from origin/main (git fetch origin pull/N/head; git cherry-pick -x FETCH_HEAD; resolve), gate it, then merge with combined: <that branch>",
          ],
    };
  }
  // merge
  const combined = input.combined ?? input.branch ?? "HEAD";
  if (!/^[A-Za-z0-9_.\/^~-]+$/.test(combined)) throw new Error("mergePRs: bad combined");
  if (notOpen.length)
    return {
      ok: false,
      reason: `not open: ${notOpen.map((p) => `#${p.number} ${p.state}`).join(", ")}`,
      prs: summary,
    };
  const cross = prs.filter((p) => p.cross);
  if (cross.length)
    return {
      ok: false,
      reason: `from other repositories (cannot rebase their branches): ${cross.map((p) => "#" + p.number).join(", ")}`,
    };
  const cTree = (await sh(`git rev-parse ${q(combined + "^{tree}")}`)).out;
  const cBase = (await sh(`git merge-base ${q(combined)} origin/main`)).out;
  const prFiles = [...new Set(prs.flatMap((p) => p.files as string[]))];
  // the combination is its base plus these PRs: its changes from the base are the PRs' files only
  const cFiles = lines((await sh(`git diff --name-only ${cBase} ${q(combined)}`)).out);
  const extra = cFiles.filter((x) => !prFiles.includes(x));
  if (extra.length)
    return {
      ok: false,
      reason: `${combined} changes files no PR changes`,
      extra: extra.slice(0, 20),
    };
  const moved = lines((await sh(`git diff --name-only ${cBase} origin/main`)).out).filter((x) =>
    prFiles.includes(x),
  );
  if (moved.length)
    return {
      ok: false,
      reason: "origin/main changed PR files since the combination's base: combine and gate again",
      files: moved.slice(0, 20),
    };
  const gated = (
    await sh(
      `for f in $(ls -t build/gate-runs/*.json 2>/dev/null | head -40); do b=\${f%.json}; [ "$(cat $b.exit 2>/dev/null)" = 0 ] && cat $f; done`,
    )
  ).out;
  const run = lines(gated)
    .map((l) => JSON.parse(l))
    .find((r) => r.tree === cTree);
  if (!run && !input.skipGateReason)
    return {
      ok: false,
      needsGate: true,
      reason: `no passed samaltak.gate run of ${combined}'s tree here: gate it (git switch to it; samaltak.gate) or give skipGateReason`,
    };
  const plan = prs.map(
    (p) =>
      `#${p.number} ${p.mergeable.startsWith("MERGEABLE") ? "gh pr merge --rebase" : "rebase its branch with the combination's resolution, force-with-lease, then merge"}`,
  );
  if (input.dryRun)
    return {
      ok: true,
      dryRun: true,
      gate: run ? run.id : `skipped: ${input.skipGateReason}`,
      plan,
      prs: summary,
    };
  const done: string[] = [];
  for (const p of prs) {
    await sh("git fetch -q origin");
    let v = await view(p.number);
    if (v.state === "MERGED") {
      done.push(`#${p.number} already merged`);
      continue;
    }
    if (v.mergeable !== "MERGEABLE") {
      const r = await scratch("origin/main", async (w) => {
        const c = await sh(`git -C ${q(w)} cherry-pick ${p.commits.join(" ")}`);
        for (let i = 0; c.code !== 0 && i < 50; i++) {
          const files = lines((await sh(`git -C ${q(w)} diff --name-only --diff-filter=U`)).out);
          if (!files.length) {
            const e = await sh(`git -C ${q(w)} -c core.editor=true cherry-pick --continue`);
            if (e.code === 0) break;
            return { ok: false, out: e.out.slice(-400) };
          }
          await sh(
            `cd ${q(w)} && git checkout ${q(combined)} -- ${files.map(q).join(" ")} && git add -- ${files.map(q).join(" ")}`,
          );
          const e = await sh(`git -C ${q(w)} -c core.editor=true cherry-pick --continue`);
          if (e.code === 0 && !lines((await sh(`git -C ${q(w)} status --porcelain`)).out).length)
            break;
        }
        const push = await sh(
          `git -C ${q(w)} push -q --force-with-lease=${q(`${p.branch}:${p.sha}`)} origin ${q(`HEAD:refs/heads/${p.branch}`)}`,
        );
        return { ok: push.code === 0, out: push.out.slice(-400) };
      });
      if (!r.ok)
        return { ok: false, reason: `could not rebase #${p.number}'s branch`, detail: r.out, done };
      done.push(`#${p.number} branch rebased onto origin/main (combination's resolution)`);
      v = await view(p.number);
    }
    const m = await sh(`gh pr merge ${p.number} -R ${repo} --rebase`, 180000);
    const after = await view(p.number);
    if (after.state !== "MERGED")
      return { ok: false, reason: `#${p.number} did not merge`, detail: m.out.slice(-400), done };
    done.push(`#${p.number} merged`);
  }
  await sh("git fetch -q origin");
  const diff = (
    await sh(`git diff --stat ${q(combined)} origin/main -- ${prFiles.map(q).join(" ")}`)
  ).out;
  return {
    ok: !diff,
    done,
    verified: !diff
      ? "origin/main has the gated combination's version of every PR file"
      : undefined,
    differs: diff ? diff.split("\n").slice(-10) : undefined,
    gate: run ? run.id : `skipped: ${input.skipGateReason}`,
  };
}
