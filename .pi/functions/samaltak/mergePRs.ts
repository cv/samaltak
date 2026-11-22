/** Merge pull requests (the in-image agent's agent/* PRs) the gated way: check combines them on origin/<base> in a scratch worktree (conflicts per PR) and can keep the combination, one resolved segment of commits per PR, on a branch to gate; merge pushes each PR's own resolved commits, rebased onto the base as the previous PR's merge left it, to its branch (force-with-lease), rebase-merges it, and verifies the base against the gated combination after each PR and at the end; base (default main) and dryRun available. */
async function mergePRs(
  { shell: { exec } },
  input: {
    numbers?: number[];
    action?: "check" | "merge";
    repo?: string;
    base?: string;
    branch?: string;
    combined?: string;
    skipGateReason?: string;
    dryRun?: boolean;
  } = {},
) {
  // base: the branch the PRs target (default main; a scratch branch such as scratch/mergeprs-test to try this out).
  // check (default): the PRs' state, files and GitHub mergeability, then a trial: their commits cherry-picked (-x) in
  // order onto origin/<base> in a scratch worktree (removed after); a PR that conflicts is reported with its files and
  // left out. branch: also make that local branch at the combination when every PR applied, or else at the PRs before
  // the first conflicting one, with the commands that add the rest by hand (cherry-pick -x, resolve, continue).
  // The combination is origin/<base> plus, per PR in order, a segment of commits that belong to it: a commit belongs to
  // PR N by its "(cherry picked from commit X)" line naming one of N's commits, or by a line "PR: #N" (a fix-up of
  // N's resolution). Everything a resolution needs, also beyond the conflict hunks (a docs fix), goes into its PR's
  // segment: that is what lands with that PR.
  // merge: combined (default the branch, else HEAD) must be such a combination of exactly these PRs, with a passed
  // samaltak.gate run of its tree (build/gate-runs here), or give skipGateReason. Then for each PR in order: fetch;
  // origin/<base> must still have the combination's state, up to the previous PR, in every file the combination
  // changes (commits that landed meanwhile may change other files only); the PR's segment is cherry-picked onto
  // origin/<base> (its "cherry picked from" lines naming the PR's own commits dropped) and, unless the PR's branch
  // already is exactly that, force-pushed to the branch with lease on the PR's head; gh pr merge --rebase
  // --match-head-commit; then origin/<base> must have the combination's state up to this PR in those files (the
  // whole tree when nothing else landed). Finally the same against the whole combination: the tree equals the gated
  // tree unless other commits landed (then only their files differ). The PRs' original commits are recorded in
  // build/merge-prs/<combination>.json, so a run that stopped half way can be run again: PRs already merged at the
  // front are checked and skipped. Refuses PRs from other repositories or targeting another base. dryRun: every check
  // and the whole chain of resolved commits built in a scratch worktree, nothing pushed or merged.
  // numbers default: the open PRs on base whose branch starts with agent/. repo default: origin's (not gh's default,
  // which is upstream in this clone).
  const action = input.action ?? "check";
  const sh = async (c: string, timeoutMs = 120000) => {
    const r = await exec(c, { timeoutMs });
    return { code: r.code, out: (r.stdout + r.stderr).trim() };
  };
  const q = (s: string) => "'" + s.replace(/'/g, "'\\''") + "'";
  const lines = (s: string) => s.split("\n").filter(Boolean);
  const okRef = (s: string) => /^[A-Za-z0-9_.\/-]+$/.test(s) && !s.startsWith("-") && !s.includes("..");
  const base = input.base ?? "main";
  if (!okRef(base)) throw new Error(`mergePRs: bad base "${base}"`);
  const ob = `origin/${base}`;
  const repo =
    input.repo ??
    (await sh("git remote get-url origin")).out.match(
      /github\.com[:/]([^/\s]+\/[^/\s]+?)(\.git)?$/,
    )?.[1] ??
    "";
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo))
    throw new Error(`mergePRs: bad repo "${repo}" (give repo: owner/name)`);
  if (input.branch && !okRef(input.branch)) throw new Error("mergePRs: bad branch");
  const f0 = await sh(`git fetch -q origin && git rev-parse --verify -q ${q(ob)}`);
  if (f0.code !== 0) throw new Error(`mergePRs: no ${ob}: ${f0.out.slice(-300)}`);
  let numbers = input.numbers ?? [];
  if (!numbers.length) {
    const l = await sh(
      `gh pr list -R ${repo} --state open --base ${q(base)} --limit 50 --json number,headRefName -q '.[] | select(.headRefName | startswith("agent/")) | .number'`,
    );
    numbers = lines(l.out)
      .map(Number)
      .filter((n) => n > 0)
      .sort((a, b) => a - b);
    if (!numbers.length)
      return { ok: true, repo, base, prs: [], note: `no open agent/ pull requests on ${base}` };
  }
  if (numbers.some((n) => !Number.isInteger(n) || n <= 0))
    throw new Error("mergePRs: bad PR number");
  const fields =
    "number,state,title,baseRefName,headRefName,headRefOid,isCrossRepository,mergeable,mergeStateStatus,files";
  // a PR's view; while it is open, wait (up to a minute) for GitHub to know its mergeability and, if given, its head
  const view = async (n: number, head?: string) => {
    for (let i = 0; i < 20; i++) {
      const v = await sh(`gh pr view ${n} -R ${repo} --json ${fields}`);
      if (v.code !== 0) throw new Error(`mergePRs: gh pr view ${n}: ${v.out.slice(-300)}`);
      const p = JSON.parse(v.out);
      if (p.state !== "OPEN" || (p.mergeable !== "UNKNOWN" && (!head || p.headRefOid === head)))
        return p;
      await sh("sleep 3");
    }
    return JSON.parse((await sh(`gh pr view ${n} -R ${repo} --json ${fields}`)).out);
  };
  const prs: any[] = [];
  for (const n of numbers) {
    const p = await view(n);
    const f = await sh(`git fetch -q origin pull/${n}/head && git rev-parse FETCH_HEAD`);
    if (f.code !== 0)
      throw new Error(`mergePRs: cannot fetch pull/${n}/head: ${f.out.slice(-300)}`);
    const sha = lines(f.out).pop()!;
    const commits = lines((await sh(`git rev-list --reverse --no-merges ${q(ob)}..${sha}`)).out);
    prs.push({
      number: n,
      title: p.title,
      state: p.state,
      base: p.baseRefName,
      branch: p.headRefName,
      cross: p.isCrossRepository,
      mergeable: `${p.mergeable}/${p.mergeStateStatus}`,
      files: (p.files ?? []).map((x: any) => x.path),
      sha,
      commits,
    });
  }
  const summary = prs.map((p) => ({
    number: p.number,
    title: p.title.slice(0, 120),
    state: p.state,
    base: p.base,
    branch: p.branch,
    mergeable: p.mergeable,
    commits: p.commits.length,
    files: p.files.slice(0, 15),
  }));
  // a scratch worktree at a ref; the callback works in it; always removed
  const scratch = async <T>(ref: string, fn: (w: string) => Promise<T>): Promise<T> => {
    const w = (await sh(`mktemp -d "\${TMPDIR:-/tmp}/samaltak-prs-XXXXXX"`)).out;
    const a = await sh(`git worktree add -q --detach ${q(w)} ${q(ref)}`);
    if (a.code !== 0) throw new Error(`mergePRs: worktree: ${a.out.slice(-300)}`);
    try {
      return await fn(w);
    } finally {
      await sh(
        `git -C ${q(w)} cherry-pick --abort >/dev/null 2>&1; git worktree remove --force ${q(w)}; git worktree prune`,
      );
    }
  };
  const wrongBase = prs.filter((p) => p.base !== base);
  if (action === "check") {
    const open = prs.filter((x) => x.state === "OPEN" && x.base === base);
    const trial = await scratch(ob, async (w) => {
      const res: Array<{ number: number; applied: boolean; conflicts?: string[] }> = [];
      let prefix: string | null = null;
      let firstConflict = -1;
      for (const [i, p] of open.entries()) {
        const before = (await sh(`git -C ${q(w)} rev-parse HEAD`)).out;
        const c = await sh(`git -C ${q(w)} cherry-pick -x ${p.commits.join(" ")}`);
        if (c.code === 0) res.push({ number: p.number, applied: true });
        else {
          const files = lines((await sh(`git -C ${q(w)} diff --name-only --diff-filter=U`)).out);
          await sh(`git -C ${q(w)} cherry-pick --abort; git -C ${q(w)} reset -q --hard ${before}`);
          res.push({ number: p.number, applied: false, conflicts: files });
          if (prefix === null) {
            prefix = before;
            firstConflict = i;
          }
        }
      }
      const head = (await sh(`git -C ${q(w)} rev-parse HEAD`)).out;
      return { res, head, prefix, firstConflict };
    });
    const allApplied =
      trial.res.every((r) => r.applied) && open.length === prs.length;
    let branch: string | undefined;
    const at = allApplied ? trial.head : trial.prefix;
    if (input.branch && at && !input.dryRun) {
      const b = await sh(`git branch -f ${q(input.branch)} ${at}`);
      if (b.code !== 0) throw new Error(`mergePRs: branch: ${b.out}`);
      branch = input.branch;
    }
    const rest = trial.firstConflict >= 0 ? open.slice(trial.firstConflict) : [];
    const merge = `then mergePRs({ numbers: ${JSON.stringify(numbers)}, action: "merge", combined: "${branch ?? "<branch>"}"${base !== "main" ? `, base: "${base}"` : ""} })`;
    return {
      ok: allApplied,
      repo,
      base,
      prs: summary,
      wrongBase: wrongBase.length ? wrongBase.map((p) => `#${p.number} targets ${p.base}`) : undefined,
      trial: trial.res,
      branch,
      next: allApplied
        ? branch
          ? [
              `git switch ${branch}; samaltak.build(); samaltak.suite({ tests: [...] }); samaltak.gate({ action: "start", targets: ["auto"] })`,
              merge,
            ]
          : ['check again with branch: "prs/combined" to keep the combination for the gate']
        : branch
          ? [
              `git switch ${branch} (it has the PRs before #${rest[0]?.number}); then for each of the rest, in order:`,
              ...rest.map(
                (p) =>
                  `git fetch -q origin pull/${p.number}/head && git cherry-pick -x ${p.commits.join(" ")}`,
              ),
              "on a conflict: resolve, with every edit the PR needs (also beyond the hunks, e.g. docs), git add, git cherry-pick --continue; later fixes for PR N: git commit --amend while it is the last, else a commit whose message has a line 'PR: #N' right after N's commits",
              'then samaltak.gate({ action: "start", targets: ["auto"] }) on it',
              merge,
            ]
          : ['check again with branch: "prs/combined" to get the conflict-free part on a branch and the commands for the rest'],
    };
  }
  // merge
  const combined = input.combined ?? input.branch ?? "HEAD";
  if (!/^[A-Za-z0-9_.\/^~-]+$/.test(combined) || combined.startsWith("-"))
    throw new Error("mergePRs: bad combined");
  const fail = (reason: string, extra: Record<string, unknown> = {}) => ({
    ok: false,
    reason,
    ...extra,
  });
  const bad = prs.filter((p) => p.state === "CLOSED");
  if (bad.length) return fail(`closed: ${bad.map((p) => "#" + p.number).join(", ")}`, { prs: summary });
  if (wrongBase.length)
    return fail(`not on ${base}: ${wrongBase.map((p) => `#${p.number} (${p.base})`).join(", ")}`);
  const cross = prs.filter((p) => p.cross);
  if (cross.length)
    return fail(
      `from other repositories (cannot push their branches): ${cross.map((p) => "#" + p.number).join(", ")}`,
    );
  // PRs already merged must come first (a run that stopped half way)
  const j = prs.findIndex((p) => p.state !== "MERGED");
  const merged = j < 0 ? prs.length : j;
  if (prs.slice(merged).some((p) => p.state === "MERGED"))
    return fail("a later PR is merged before an earlier one: give numbers in merge order", {
      prs: summary,
    });
  const rp = async (r: string) => (await sh(`git rev-parse --verify -q ${q(r)}`)).out;
  const tree = (r: string) => rp(r + "^{tree}");
  const names = async (a: string, b: string) =>
    lines((await sh(`git diff --name-only ${q(a)} ${q(b)}`)).out);
  const cHead = await rp(combined + "^{commit}");
  if (!/^[0-9a-f]{40}$/.test(cHead)) return fail(`no commit ${combined}`);
  const cTree = await tree(cHead);
  const cBase = (await sh(`git merge-base ${cHead} ${q(ob)}`)).out;
  if (lines((await sh(`git rev-list --merges ${cBase}..${cHead}`)).out).length)
    return fail(`${combined} has merge commits since ${ob}: make it a line of commits`);
  // the PRs' original commits, recorded on the first run for this combination
  const recFile = `build/merge-prs/${cHead}.json`;
  let rec: Record<string, { commits: string[]; heads: string[] }> = {};
  try {
    rec = JSON.parse((await sh(`cat ${recFile} 2>/dev/null`)).out || "{}");
  } catch {}
  const changed: string[] = [];
  for (const p of prs) {
    const r = rec[p.number];
    if (!r) rec[p.number] = { commits: p.commits, heads: [p.sha] };
    else if (p.state === "OPEN" && !r.heads.includes(p.sha)) changed.push(`#${p.number}`);
    p.orig = rec[p.number].commits;
  }
  if (changed.length)
    return fail(
      `changed since the first merge run of ${combined} (new commits on their branches): combine and gate again`,
      { prs: changed },
    );
  const saveRec = () =>
    sh(`mkdir -p build/merge-prs && printf '%s\\n' ${q(JSON.stringify(rec))} > ${recFile}`);
  // the combination's commits, each attributed to its PR
  const log = (await sh(`git log --reverse --format='%H%x1f%B%x1e' ${cBase}..${cHead}`, 60000)).out;
  const entries = log
    .split("\x1e")
    .map((s) => s.replace(/^\s+/, ""))
    .filter((s) => s.includes("\x1f"))
    .map((s) => {
      const [h, msg] = s.split("\x1f");
      return { h: h.trim(), msg };
    });
  const seg: Record<number, string[]> = {};
  const refs: Record<number, string[]> = {};
  const unattributed: string[] = [];
  const order: number[] = [];
  for (const e of entries) {
    const picked = [...e.msg.matchAll(/^\(cherry picked from commit ([0-9a-f]{7,40})\)$/gm)].map(
      (m) => m[1],
    );
    let p = prs.find((x) => x.orig.some((s: string) => picked.some((y) => s.startsWith(y))));
    const t = e.msg.match(/^PR:\s*#?(\d+)\s*$/m);
    if (!p && t) p = prs.find((x) => x.number === Number(t[1]));
    if (!p) {
      unattributed.push(`${e.h.slice(0, 12)} ${e.msg.split("\n")[0].slice(0, 80)}`);
      continue;
    }
    (seg[p.number] ??= []).push(e.h);
    (refs[p.number] ??= []).push(...picked);
    order.push(prs.indexOf(p));
  }
  if (unattributed.length)
    return fail(
      `${combined} has commits of no given PR (no "cherry picked from" line naming a PR's commit, no "PR: #N" line)`,
      { commits: unattributed.slice(0, 10) },
    );
  if (order.some((v, i) => i > 0 && v < order[i - 1]))
    return fail(`${combined}'s commits are not in the PRs' order (${numbers.join(", ")}): one segment per PR`);
  const missing = prs.filter((p) => !seg[p.number]);
  if (missing.length)
    return fail(`${combined} has no commits of ${missing.map((p) => "#" + p.number).join(", ")}`);
  const left = prs.filter(
    (p) => refs[p.number].length && p.orig.some((s: string) => !refs[p.number].some((y) => s.startsWith(y))),
  );
  if (left.length)
    return fail(
      `${combined} lacks commits of ${left.map((p) => "#" + p.number).join(", ")} (pushed after it was combined?): combine and gate again`,
    );
  // C[k]: the combination up to PR k; F: the files it changes
  const C = prs.map((p) => seg[p.number][seg[p.number].length - 1]);
  const upTo = (k: number) => (k < 0 ? cBase : C[k]);
  const F = new Set(await names(cBase, cHead));
  const inF = (xs: string[]) => xs.filter((x) => F.has(x));
  const segFiles: string[][] = [];
  for (const [k] of prs.entries()) segFiles.push(await names(upTo(k - 1), C[k]));
  // the base must have the combination's state, up to the PRs merged, in F
  const moved = inF(await names(upTo(merged - 1), ob));
  if (moved.length)
    return fail(
      `${ob} changed files of the combination since ${merged ? `#${prs[merged - 1].number}'s state in it` : "its base"}: combine and gate again`,
      { files: moved.slice(0, 20) },
    );
  const gated = (
    await sh(
      `for f in $(ls -t build/gate-runs/*.json 2>/dev/null | head -40); do b=\${f%.json}; [ "$(cat $b.exit 2>/dev/null)" = 0 ] && cat $f; done`,
    )
  ).out;
  const run = lines(gated)
    .map((l) => {
      try {
        return JSON.parse(l);
      } catch {
        return {};
      }
    })
    .find((r) => r.tree === cTree);
  if (!run && !input.skipGateReason)
    return fail(
      `no passed samaltak.gate run of ${combined}'s tree here: gate it (git switch to it; samaltak.gate) or give skipGateReason`,
      { needsGate: true },
    );
  const gate = run ? run.id : `skipped: ${input.skipGateReason}`;
  if (!input.dryRun) await saveRec();
  const steps: any[] = prs
    .slice(0, merged)
    .map((p) => ({ number: p.number, done: "already merged (its state checked)" }));
  const res = await scratch(ob, async (w) => {
    let pre = await rp(ob);
    for (let k = merged; k < prs.length; k++) {
      const p = prs[k];
      const step: any = { number: p.number, commits: seg[p.number].length };
      steps.push(step);
      if (!input.dryRun) {
        await sh("git fetch -q origin");
        pre = await rp(ob);
        const v = await view(p.number);
        if (v.state !== "OPEN") return fail(`#${p.number} is ${v.state} now`);
        if (v.headRefOid !== p.sha)
          return fail(`#${p.number}'s head moved to ${v.headRefOid} since this run started`);
        const m = inF(await names(upTo(k - 1), pre));
        if (m.length)
          return fail(`${ob} changed files of the combination meanwhile: combine and gate again`, {
            files: m.slice(0, 20),
          });
      }
      // the PR's resolved commits onto the base as it is (or as the previous PR left it, in a dry run)
      await sh(`git -C ${q(w)} reset -q --hard ${pre}`);
      const own = new Set(p.orig as string[]);
      for (const c of seg[p.number]) {
        const cp = await sh(
          `git -C ${q(w)} cherry-pick --allow-empty --keep-redundant-commits ${c}`,
        );
        if (cp.code !== 0) {
          await sh(`git -C ${q(w)} cherry-pick --abort`);
          return fail(`#${p.number}'s resolved commit ${c.slice(0, 12)} does not apply to ${ob}`, {
            detail: cp.out.slice(-400),
          });
        }
        const msg = (await sh(`git -C ${q(w)} log -1 --format=%B`)).out;
        const kept = msg
          .split("\n")
          .filter((l) => {
            const m = l.match(/^\(cherry picked from commit ([0-9a-f]{7,40})\)$/);
            return !m || ![...own].some((s) => s.startsWith(m[1]));
          })
          .join("\n")
          .trim();
        if (kept !== msg.trim())
          await sh(
            `printf '%s\\n' ${q(kept)} | git -C ${q(w)} commit -q --amend --allow-empty --no-verify -F -`,
          );
      }
      const tip = (await sh(`git -C ${q(w)} rev-parse HEAD`)).out;
      const off = inF(await names(tip, C[k]));
      if (off.length)
        return fail(`#${p.number}'s resolved commits on ${ob} differ from the combination`, {
          files: off.slice(0, 20),
        });
      const n = seg[p.number].length;
      const same =
        (await rp(`${p.sha}~${n}`)) === pre && (await tree(p.sha)) === (await tree(tip));
      step.extraFiles = segFiles[k].filter((x) => !p.files.includes(x)).slice(0, 15);
      if (!step.extraFiles.length) delete step.extraFiles;
      if (same) step.push = "none: its branch already is its resolved commits on the base";
      else {
        step.push = `force-with-lease ${p.branch} to ${tip.slice(0, 12)}`;
        step.differsFromPR = inF(await names(p.sha, tip)).slice(0, 15);
      }
      if (input.dryRun) {
        step.merge = "gh pr merge --rebase";
        pre = tip;
        continue;
      }
      const head = same ? p.sha : tip;
      if (!same) {
        const push = await sh(
          `git -C ${q(w)} push -q --force-with-lease=${q(`refs/heads/${p.branch}:${p.sha}`)} origin ${q(`HEAD:refs/heads/${p.branch}`)}`,
        );
        if (push.code !== 0)
          return fail(`could not push #${p.number}'s branch`, { detail: push.out.slice(-400) });
        rec[p.number].heads.push(tip);
        await saveRec();
        step.pushed = tip;
      }
      await view(p.number, head);
      const m = await sh(
        `gh pr merge ${p.number} -R ${repo} --rebase --match-head-commit ${head}`,
        180000,
      );
      const after = await view(p.number);
      if (after.state !== "MERGED")
        return fail(`#${p.number} did not merge`, { detail: m.out.slice(-400) });
      await sh("git fetch -q origin");
      const post = await rp(ob);
      const offAfter = inF(await names(C[k], post));
      const others = (await rp(`${post}~${n}`)) !== pre;
      step.merged = post;
      step.verified = offAfter.length
        ? undefined
        : (await tree(post)) === (await tree(C[k]))
          ? `${ob}'s tree is the combination's up to #${p.number}`
          : `${ob} has the combination's state up to #${p.number} in its files; other files differ by commits that landed meanwhile`;
      if (others) step.landedMeanwhile = true;
      if (offAfter.length)
        return fail(`${ob} after merging #${p.number} differs from the combination`, {
          files: offAfter.slice(0, 20),
        });
      pre = post;
    }
    return { ok: true };
  });
  if (!res.ok) return { ...res, base, gate, steps };
  if (input.dryRun) return { ok: true, dryRun: true, base, combined: cHead, gate, steps };
  await sh("git fetch -q origin");
  const end = await rp(ob);
  const diff = await names(cHead, end);
  const offEnd = inF(diff);
  return {
    ok: !offEnd.length,
    base,
    gate,
    steps,
    verified: offEnd.length
      ? undefined
      : diff.length
        ? `${ob} has the gated combination's state in every file it changes; ${diff.length} other files differ by commits that landed since its base`
        : `${ob}'s tree is the gated tree`,
    differs: offEnd.length ? offEnd.slice(0, 20) : undefined,
    landed: !offEnd.length && diff.length ? diff.slice(0, 20) : undefined,
  };
}
