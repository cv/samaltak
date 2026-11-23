#!/bin/sh
# usage: tests/timeline.sh FILE [all]: the timeline FILE (SAMALTAK_TIMELINE: make recipe lines, st_suite's VMs, slot
# waits; tests/stages.sh writes OUT/stages/timeline) as a report: each stage's span and slot waits, then the steps of
# the build and of the stage that ended last, the critical path (all: of every stage), as a tree of recipe lines of
# 1 s or more (start offset, duration, target, command), a suite's VMs summed up on its line.
f=$1
[ -s "$f" ] || { echo "timeline: no events in $f"; exit 0; }
awk -F '\t' -v all="${2:-}" '
  { split($1, h, " "); n++; s[n] = h[1]; e[n] = h[2]; x[n] = h[3]; st[n] = h[4]; id[n] = h[5]; par[n] = h[6]; w[n] = $2; c[n] = $3
    if (h[5] != "-") idx[h[5]] = n
    if (n == 1 || h[1] < t0) t0 = h[1] }
  function sorted(list,   m, a, k, j, t, out) {
    m = split(list, a, " ")
    for (k = 2; k <= m; k++) { t = a[k]; for (j = k - 1; j >= 1 && s[a[j]] > s[t]; j--) a[j + 1] = a[j]; a[j + 1] = t }
    out = ""; for (k = 1; k <= m; k++) out = out " " a[k]
    return out
  }
  function pr(i, depth,   m, a, k, ind, note) {
    if (e[i] - s[i] < 1) return
    ind = ""; for (k = 0; k < depth; k++) ind = ind "  "
    note = ""
    if (i in vms) note = sprintf(" [%d VMs, longest %.1f s%s]", vms[i], vmmax[i], (i in waits) && waits[i] >= 1 ? sprintf(", slot waits %.0f s", waits[i]) : "")
    else if ((i in waits) && waits[i] >= 1) note = sprintf(" [slot wait %.1f s]", waits[i])
    printf "timeline: %6.1f +%6.1f s %s%s%s: %s%s\n", s[i] - t0, e[i] - s[i], ind, w[i], x[i] == 0 ? "" : " (exit " x[i] ")", substr(c[i], 1, 100 - 2 * depth), note
    m = split(sorted(kids[i]), a, " ")
    for (k = 1; k <= m; k++) pr(a[k], depth + 1)
  }
  END {
    for (i = 1; i <= n; i++) {
      d = e[i] - s[i]
      if (!(st[i] in a0) || s[i] < a0[st[i]]) a0[st[i]] = s[i]
      if (!(st[i] in b0) || e[i] > b0[st[i]]) b0[st[i]] = e[i]
      p = (par[i] in idx) ? idx[par[i]] : 0
      if (w[i] == "slot-wait") { stw[st[i]] += d; if (p) waits[p] += d; continue }
      if (w[i] == "st_suite" && p) { vms[p]++; if (d > vmmax[p]) vmmax[p] = d; continue }
      if (p) kids[p] = kids[p] " " i; else roots[st[i]] = roots[st[i]] " " i
    }
    last = ""; for (k in b0) if (k != "-" && (last == "" || b0[k] > b0[last])) last = k
    for (k in a0) printf "timeline: %-18s %6.1f - %6.1f s (%5.1f s)%s\n", k == "-" ? "build" : k, a0[k] - t0, b0[k] - t0, b0[k] - a0[k], \
      (k in stw) && stw[k] >= 1 ? sprintf(", slot waits %.0f s", stw[k]) : "" | "sort -k3 -n"
    close("sort -k3 -n")
    order = ""
    for (k in a0) if (k == "-") order = k " " order; else if (all != "" || k == last) order = order " " k
    m = split(order, ks, " ")
    for (q = 1; q <= m; q++) {
      k = ks[q]
      printf "timeline: steps of %s%s:\n", k == "-" ? "the build" : k, k == last ? " (critical path)" : ""
      r = split(sorted(roots[k]), a, " ")
      for (j = 1; j <= r; j++) pr(a[j], 0)
    }
  }' "$f"
