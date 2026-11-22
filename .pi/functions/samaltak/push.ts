/** Push commits to origin/main safely: clean tree (or autostash), rebase (abort on conflict), no conflict markers/whitespace errors, a passed gate of the same change with no overlapping incoming commits, push with retries; dryRun available. */
async function push(
  { shell: { exec } },
  input: { dryRun?: boolean; skipGateReason?: string; maxAttempts?: number; autostash?: boolean } = {},
) {
  // Pushes this worktree's commits to origin/main by the repo's protocol (AGENTS.md): clean worktree; fetch and rebase
  // onto origin/main (aborted and reported on a conflict); no conflict markers or whitespace errors in the pushed
  // files; a passed samaltak.gate run of the same change (HEAD's tree, or the same diff against the base it ran on)
  // where the commits that landed since that base touch none of the pushed files (else needsGate with the overlap);
  // then git push origin HEAD:main, retrying (fetch, rebase, checks) if someone pushed in between. skipGateReason
  // pushes without a matching gate run (say why). autostash: keep uncommitted work out of the way during the rebase
  // (git rebase --autostash) instead of refusing; it is never pushed, and comes back afterwards (a conflict leaves it
  // in git stash, reported). HEAD already on top of origin/main is pushed as it is (no rebase, so merge commits such
  // as an upstream sync stay merges); otherwise the rebase keeps merges (--rebase-merges).
  const sh = async (c: string) => {
    const r = await exec(c, { timeoutMs: 120000 });
    return { code: r.code, out: (r.stdout + r.stderr).trim() };
  };
  const fail = (reason: string, extra: Record<string, unknown> = {}) => ({
    ok: false,
    pushed: false,
    reason,
    ...extra,
  });
  const patchId = async (a: string, b: string) =>
    (await sh(`git diff ${a} ${b} | git patch-id --stable | cut -d' ' -f1`)).out;
  const dirty = await sh("git status --porcelain --untracked-files=no");
  if (dirty.out && !input.autostash)
    return fail("uncommitted changes: commit them, or push with autostash: true", {
      files: dirty.out.split("\n").slice(0, 20),
    });
  const runs = (
    await sh(
      `for f in $(ls -t build/gate-runs/*.json 2>/dev/null | head -30); do b=\${f%.json}; [ "$(cat $b.exit 2>/dev/null)" = 0 ] && cat $f; done`,
    )
  ).out
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l));
  const attempts = Math.min(Math.max(input.maxAttempts ?? 3, 1), 5);
  for (let attempt = 1; attempt <= attempts; attempt++) {
    await sh("git fetch -q origin");
    const ahead = Number((await sh("git rev-list --count origin/main..HEAD")).out);
    if (!ahead)
      return { ok: true, pushed: false, reason: "nothing to push: HEAD is on origin/main" };
    const onTop = (await sh("git merge-base --is-ancestor origin/main HEAD")).code === 0;
    const rb = onTop
      ? { code: 0, out: "" }
      : await sh(`git rebase -q --rebase-merges${input.autostash ? " --autostash" : ""} origin/main`);
    if (rb.code !== 0) {
      const files = (await sh("git diff --name-only --diff-filter=U")).out;
      await sh("git rebase --abort");
      return fail(
        "rebase onto origin/main conflicts; resolve by hand (keep both sides of shared lists), then gate again",
        { conflicts: files.split("\n").filter(Boolean), detail: rb.out.slice(-800) },
      );
    }
    const stashNote = /autostash.*conflict/i.test(rb.out)
      ? "your uncommitted changes conflicted with the rebased tree: they are in git stash (git stash pop)"
      : undefined;
    const head = (await sh("git rev-parse HEAD")).out;
    const tree = (await sh("git rev-parse 'HEAD^{tree}'")).out;
    const ours = (await sh("git diff --name-only origin/main HEAD")).out
      .split("\n")
      .filter(Boolean);
    const check = await sh("git diff --check origin/main HEAD");
    const markers = ours.length
      ? await sh(
          `git grep -n -E '^(<<<<<<<|>>>>>>>)( |$)' HEAD -- ${ours.map((f) => `'${f.replace(/'/g, "'\\''")}'`).join(" ")}`,
        )
      : { code: 1, out: "" };
    if (check.out || markers.code === 0)
      return fail("conflict markers or whitespace errors in the pushed range", {
        diffCheck: check.out.slice(0, 1500),
        markers: markers.code === 0 ? markers.out.slice(0, 1500) : "",
      });
    let gateNote = "";
    const exact = runs.find((r) => r.tree === tree);
    if (exact) gateNote = `gate ${exact.id} passed on this tree`;
    else {
      const mine = await patchId("origin/main", "HEAD");
      let overlapSeen: string[] = [];
      for (const r of runs) {
        if ((await sh(`git cat-file -e ${r.head} && git cat-file -e ${r.base}`)).code !== 0)
          continue;
        if ((await patchId(r.base, r.head)) !== mine) continue;
        const incoming = (await sh(`git diff --name-only ${r.base} origin/main`)).out
          .split("\n")
          .filter(Boolean);
        const overlap = ours.filter((f) => incoming.includes(f));
        if (!overlap.length) {
          gateNote = `gate ${r.id} passed on the same change; commits landed since touch none of the pushed files`;
          break;
        }
        overlapSeen = overlap;
      }
      if (!gateNote && input.skipGateReason)
        gateNote = `no matching gate run: ${input.skipGateReason}`;
      if (!gateNote && overlapSeen.length)
        return fail(
          "commits landed since your gate run change files you push: run samaltak.gate on the rebased HEAD",
          { needsGate: true, overlap: overlapSeen.slice(0, 30), head },
        );
      if (!gateNote)
        return fail("no passed samaltak.gate run of this change: run samaltak.gate first", {
          needsGate: true,
          head,
        });
    }
    const commits = (await sh("git log --format='%h %s' origin/main..HEAD")).out
      .split("\n")
      .filter(Boolean);
    if (input.dryRun) return { ok: true, pushed: false, dryRun: true, gate: gateNote, commits, stashNote };
    const p = await sh("git push -q origin HEAD:main");
    if (p.code === 0)
      return { ok: true, pushed: true, attempt, gate: gateNote, commits, head: head.slice(0, 9), stashNote };
    if (!/non-fast-forward|fetch first|rejected/.test(p.out))
      return fail("git push failed", { detail: p.out.slice(-800) });
  }
  return fail(`origin/main kept moving: gave up after ${attempts} attempts`);
}
