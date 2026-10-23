// Samaltak — Direction 2: Infinite canvas. Camera, background (grid/regions/edges), input, spotter, startup.
(function (S) {
  'use strict';
  const $ = s => document.querySelector(s);
  const { h, fmt } = S;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  const LAYER_COLORS = ['#cf9b52', '#cd7c5c', '#c27096', '#9587d8', '#65a3d8', '#74b597'];
  const PLAY_COLOR = '#dcc69b';
  const LAYER_NAMES = ['Kernel', 'Graphics-GPU', 'Graphics-Canvas', 'UI-Windows', 'UI-Widgets', 'Tools'];
  const LAYER_TAGS = ['objects · numbers · green threads', '3D · WebGPU-shaped', '2D · vectors & text → DisplayLists', 'Compositor · a Process per Window', 'Morphic-style widgets', 'built from widgets'];
  const LAYER_NOTES = [
    'Root classes, numbers, and Processes. All green threads share one OS thread; switches happen at safepoints.',
    'Thin WebGPU-shaped API over Metal/Vulkan/D3D. Only Graphics-Canvas talks to me.',
    'Vector paths, text, images. Records DisplayLists, rasterized by compute shaders.',
    'Windows and compositing. Each Window owns a Process and a layer texture.',
    'What normal UI code uses. Widgets draw on a Canvas; they never see the GPU.',
    'Development tools, built from UI-Widgets like any other application.',
  ];
  const COL_W = 712, COL_GAP = 110, HEAD_H = 150, PKG_PAD = 20, PKG_LABEL = 30, PKG_GAP = 30, CLS_W = 300, CLS_GAP = 24;
  const MIN_S = 0.05, MAX_S = 2.5;

  S.cards = new Map();
  S.edges = [];
  S.regions = [];
  S.classCards = new Map();
  S.mode = 'detail';

  const viewport = $('#viewport'), bg = $('#bg'), ctx = bg.getContext('2d'), world = S.world = $('#world');
  const mmCanvas = $('#minimap canvas'), mctx = mmCanvas.getContext('2d');
  let vw = innerWidth, vh = innerHeight, dpr = devicePixelRatio || 1;
  const cam = S.cam = { x: 0, y: 0, s: 1 };
  let bgDirty = true, camDirty = true, mmDirty = true, hudDirty = true, procDirty = true;
  let blockAlpha = 0;
  S.dirty = () => { bgDirty = true; mmDirty = true; };

  S.ro = new ResizeObserver(entries => {
    const bands = new Set();
    for (const en of entries) {
      const c = S.cards.get(en.target.dataset.id);
      if (!c) continue;
      const nh = en.target.offsetHeight;
      if (nh && nh !== c.h) { c.h = nh; if (c.pkg) bands.add(c.pkg.band); }
    }
    bands.forEach(relayoutBand);
    S.dirty();
  });

  // ------------------------------------------------------------------ helpers
  const hexA = (hex, a) => { const n = parseInt(hex.slice(1), 16); return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`; };
  function localY(el, card) { let y = 0, n = el; while (n && n !== card.el) { y += n.offsetTop; n = n.offsetParent; } return y; }
  const playRegion = () => S.regions.find(r => r.kind === 'play');
  function regionRect(r) {
    if (r.kind !== 'play') return r;
    let x0 = r.x, y0 = r.y, x1 = r.x + r.w, y1 = r.y + r.h;
    for (const c of S.cards.values()) if (c.zone === 'play' && c.x > -9000) {
      x0 = Math.min(x0, c.x - 50); y0 = Math.min(y0, c.y - 90); x1 = Math.max(x1, c.x + c.w + 50); y1 = Math.max(y1, c.y + c.h + 50);
    }
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }
  const contains = (r, p) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
  const toWorld = (sx, sy) => ({ x: (sx - cam.x) / cam.s, y: (sy - cam.y) / cam.s });
  const isEditable = el => el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT' || el.isContentEditable);

  // ------------------------------------------------------------------ camera
  function applyCam() {
    const r = v => Math.round(v * dpr) / dpr;
    world.style.transform = `translate(${r(cam.x)}px, ${r(cam.y)}px) scale(${cam.s})`;
    const m = cam.s >= 0.55 ? 'detail' : cam.s >= 0.3 ? 'summary' : 'map';
    if (m !== S.mode) { S.mode = m; document.body.dataset.zoom = m; }
    bgDirty = mmDirty = hudDirty = true;
    camDirty = false;
  }
  function setCam(x, y, s) { cam.x = x; cam.y = y; cam.s = s; camDirty = true; }
  function zoomAt(sx, sy, f) {
    const ns = clamp(cam.s * f, MIN_S, MAX_S), wx = (sx - cam.x) / cam.s, wy = (sy - cam.y) / cam.s;
    setCam(sx - wx * ns, sy - wy * ns, ns);
  }
  let anim = null, inertia = null;
  const cancelAnim = () => { anim = null; inertia = null; };
  function flyTo(t, dur, done) {
    inertia = null;
    const s0 = cam.s, c0 = toWorld(vw / 2, vh / 2), m = Math.min(vw, vh);
    const D = Math.hypot(t.cx - c0.x, t.cy - c0.y);
    const sMid = Math.min(s0, t.s, 0.9 * m / (D + m / Math.max(s0, t.s)));
    const bump = Math.max(0, Math.log(Math.sqrt(s0 * t.s)) - Math.log(sMid));
    dur = dur || clamp(420 + 220 * bump + 140 * Math.abs(Math.log2(t.s / s0)), 420, 1150);
    const ae = document.activeElement, refocus = isEditable(ae) && !ae.closest('#spotter') ? ae : null;
    const fin = () => { if (refocus && refocus.isConnected && !isEditable(document.activeElement)) refocus.focus({ preventScroll: true }); done && done(); };
    anim = { t0: performance.now(), dur, s0, s1: t.s, c0, c1: { x: t.cx, y: t.cy }, bump, done: fin };
  }
  function stepAnim(now) {
    const u = Math.min(1, (now - anim.t0) / anim.dur);
    const e = u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
    const s = Math.exp(Math.log(anim.s0) + (Math.log(anim.s1) - Math.log(anim.s0)) * e - anim.bump * Math.sin(Math.PI * e));
    const cx = anim.c0.x + (anim.c1.x - anim.c0.x) * e, cy = anim.c0.y + (anim.c1.y - anim.c0.y) * e;
    setCam(vw / 2 - cx * s, vh / 2 - cy * s, s);
    if (u >= 1) { const d = anim.done; anim = null; d && d(); }
  }
  function fitRect(r, o = {}) {
    const pad = o.pad ?? 70, maxS = o.maxS ?? 1;
    const s = clamp(Math.min((vw - pad * 2) / r.w, (vh - pad * 2 - 50) / r.h), MIN_S, maxS);
    return { cx: r.x + r.w / 2, cy: r.y + r.h / 2 - 22 / s, s };
  }
  function worldBounds() {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    const add = r => { x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y); x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h); };
    S.regions.forEach(r => add(regionRect(r)));
    S.cards.forEach(c => { if (c.x > -9000) add(c.rect()); });
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }
  const fitAll = () => { const b = worldBounds(); b.y -= 60; b.h += 60; flyTo(fitRect(b, { pad: 36 })); };
  const zoomBy = f => { const c = toWorld(vw / 2, vh / 2); flyTo({ cx: c.x, cy: c.y, s: clamp(cam.s * f, MIN_S, MAX_S) }, 280); };
  const zoom100 = () => { const c = toWorld(vw / 2, vh / 2); flyTo({ cx: c.x, cy: c.y, s: 1 }, 380); };
  let lastZoom = null;
  S.zoomToCard = (card, o = {}) => {
    const t = fitRect(card.rect(), { pad: 90, maxS: 1 });
    const here = toWorld(vw / 2, vh / 2);
    if (!o.pulse && lastZoom && lastZoom.card === card && Math.abs(cam.s - lastZoom.s) < 0.01 && Math.hypot(here.x - lastZoom.cx, here.y - lastZoom.cy) < 4) {
      const p = lastZoom.prev; lastZoom = null; flyTo(p); return;
    }
    const prev = { cx: here.x, cy: here.y, s: cam.s };
    flyTo(t, null, () => { lastZoom = { card, prev, cx: t.cx, cy: t.cy, s: t.s }; if (o.edit && card.ed) card.ed.ta.focus({ preventScroll: true }); });
    card.focus();
    if (o.pulse) { card.el.classList.remove('ping'); void card.el.offsetWidth; card.el.classList.add('ping'); }
  };
  function reveal(card) {
    const r = card.rect(), m = 40;
    if (cam.s < 0.55) { flyTo(fitRect(r, { maxS: 0.9 })); return; }
    const sx0 = r.x * cam.s + cam.x, sy0 = r.y * cam.s + cam.y, sx1 = (r.x + r.w) * cam.s + cam.x, sy1 = (r.y + r.h) * cam.s + cam.y;
    let dx = 0, dy = 0;
    if (sx1 > vw - m) dx = vw - m - sx1;
    if (sx0 + dx < m) dx = m - sx0;
    if (sy1 > vh - m) dy = vh - m - sy1;
    if (sy0 + dy < 70) dy = 70 - sy0;
    if (dx || dy) flyTo({ cx: (vw / 2 - cam.x - dx) / cam.s, cy: (vh / 2 - cam.y - dy) / cam.s, s: cam.s }, 560);
  }
  S.flyTo = flyTo; S.fitRect = fitRect;

  // ------------------------------------------------------------------ strata layout
  function layoutStrata() {
    for (let L = 0; L <= 5; L++) {
      const band = { kind: 'band', layer: L, name: LAYER_NAMES[L], tag: LAYER_TAGS[L], note: LAYER_NOTES[L], color: LAYER_COLORS[L], x: L * (COL_W + COL_GAP), y: 0, w: COL_W, h: 400, pkgs: [] };
      S.regions.push(band);
      let y = HEAD_H;
      for (const p of FakeImage.packages.filter(p => p.layer === L)) {
        const pk = { name: p.name, x: band.x + 24, y, w: COL_W - 48, h: 0, band, members: [], count: p.classes.length };
        band.pkgs.push(pk);
        let rowY = y + PKG_LABEL + PKG_PAD, rowH = 0;
        p.classes.forEach((c, i) => {
          const col = i % 2;
          if (i && !col) { rowY += rowH + CLS_GAP; rowH = 0; }
          const cc = new S.ClassCard({ cls: c, pkgName: p.name, layer: L, accent: band.color, x: pk.x + PKG_PAD + col * (CLS_W + CLS_GAP), y: rowY, w: CLS_W });
          cc.el.classList.add('fixed');
          cc.mount();
          cc.pkg = pk; pk.members.push(cc);
          S.classCards.set(c.name, cc);
          rowH = Math.max(rowH, cc.h);
        });
        pk.h = rowY + rowH + PKG_PAD - y;
        y += pk.h + PKG_GAP;
      }
      relayoutBand(band);
    }
    S.regions.push({ kind: 'play', name: 'Playground', tag: 'your exploration trail', note: 'Snippets, live objects, processes. Evaluate, inspect, follow fields — the trail stays on the canvas.', color: PLAY_COLOR, x: 6 * (COL_W + COL_GAP), y: 0, w: 1320, h: 1060 });
  }
  function relayoutBand(band) {
    let cursor = band.y + HEAD_H;
    for (const pk of band.pkgs) {
      const dy = cursor - pk.y;
      if (Math.abs(dy) > 0.5) { pk.members.forEach(m => tweenCard(m, m.x, m.y + dy)); pk.y = cursor; }
      const bottom = Math.max(pk.y + PKG_LABEL + 80, ...pk.members.map(m => (m._tw ? m._tw.y1 : m.y) + m.h));
      pk.h = bottom - pk.y + PKG_PAD;
      cursor = pk.y + pk.h + PKG_GAP;
    }
    band.h = Math.max(cursor - PKG_GAP + 30 - band.y, 600);
    S.dirty();
  }
  S.classCardFor = name => S.classCards.get(String(name).replace(/ class$/, '')) || null;

  const tweens = new Set();
  function tweenCard(c, x, y, dur = 360) {
    if (drag && drag.card === c) return;
    const from = c._tw ? { x: c.x, y: c.y } : { x: c.x, y: c.y };
    c._tw = { x0: from.x, y0: from.y, x1: x, y1: y, t0: performance.now(), dur };
    tweens.add(c);
  }
  function stepTweens(now) {
    for (const c of tweens) {
      const t = c._tw, u = Math.min(1, (now - t.t0) / t.dur), e = 1 - Math.pow(1 - u, 3);
      c.x = t.x0 + (t.x1 - t.x0) * e; c.y = t.y0 + (t.y1 - t.y0) * e; c.place();
      if (u >= 1) { c._tw = null; tweens.delete(c); }
    }
    if (tweens.size) S.dirty();
  }

  // ------------------------------------------------------------------ cards & edges
  function addEdge(from, to, fy, label, kind) { S.edges.push({ from, to, fy, label, kind }); S.dirty(); }
  function findSpot(w, hgt, x0, y0, self) {
    const others = [...S.cards.values()].filter(c => c !== self && c.x > -9000);
    const g = 26;
    const free = (x, y) => others.every(c => x + w + g <= c.x || c.x + c.w + g <= x || y + hgt + g <= c.y || c.y + c.h + g <= y);
    for (let col = 0; col < 8; col++) {
      const x = x0 + col * Math.round(w * 0.55 + 20);
      for (let k = 0; k < 44; k++) {
        const dy = k === 0 ? 0 : (k % 3 === 0 ? -1 : 1) * Math.ceil(k * 2 / 3) * 28;
        if (free(x, y0 + dy)) return { x, y: y0 + dy };
      }
    }
    return { x: x0, y: y0 };
  }
  function spawnNear(card, src, fy, o = {}) {
    card.x = -99999; card.y = -99999;
    card.zone = src ? src.zone : 'play';
    card.mount();
    const pos = src ? findSpot(card.w, card.h, src.x + src.w + 90, src.y + fy - 22, card) : toWorld(vw / 2 - card.w / 2, vh / 3);
    card.moveTo(Math.round(pos.x), Math.round(pos.y));
    if (src) addEdge(src, card, fy, o.label, o.kind);
    card.focus();
    if (o.reveal !== false) reveal(card);
    return card;
  }
  S.removeCard = card => {
    if (card.el.classList.contains('fixed')) return;
    if (card.kind === 'process' && card.fproc.busy) S.sched.terminate(card.fproc);
    S.edges = S.edges.filter(e => e.from !== card && e.to !== card);
    if (card.proc) S.sched.remove(card.proc);
    if (card.kind === 'method' && card.classCard) { const chip = card.classCard.chips.get(card.key); chip && chip.classList.remove('open'); }
    if (card.kind === 'debugger' && card.target && card.target.state === 'suspended') S.sched.resume(card.target);
    S.cards.delete(card.id);
    S.ro.unobserve(card.el);
    card.el.classList.add('leaving');
    setTimeout(() => card.el.remove(), 180);
    if (card.pkg) { card.pkg.members = card.pkg.members.filter(m => m !== card); relayoutBand(card.pkg.band); }
    if (S.focused === card) S.focused = null;
    S.dirty();
  };

  S.spawnObject = (src, res, o) => {
    const oc = new S.ObjectCard({ res, src: o.src, view: o.view });
    return spawnNear(oc, src, o.fy, { label: o.label, kind: 'inspect', reveal: o.reveal });
  };

  S.inspectField = (card, row, rowEl) => {
    const fy = localY(rowEl, card) + rowEl.offsetHeight / 2;
    const dup = S.edges.find(e => e.from === card && e.label === row.name && e.kind !== 'class');
    if (dup) { S.zoomToCard(dup.to, { pulse: true }); return; }
    if (row.name === 'class') {
      const cc = S.classCardFor(row.value);
      if (cc) { S.linkToClass(card, cc, rowEl); return; }
    }
    let res;
    try { res = MiniST.evaluate(row.value); } catch (e) { S.toast(`${row.value} is not in this prototype image`); return; }
    S.sched.blip(card.proc);
    return S.spawnObject(card, res, { fy, label: row.name, src: row.value });
  };
  S.linkToClass = (card, cc, el) => {
    if (!S.edges.find(e => e.from === card && e.to === cc)) addEdge(card, cc, localY(el, card) + el.offsetHeight / 2, 'class', 'class');
    S.zoomToCard(cc, { pulse: true });
  };

  S.openMethod = (cc, proto, key, o = {}) => {
    const existing = [...S.cards.values()].find(c => c.kind === 'method' && c.cls === cc.cls && c.key === key);
    if (existing) { S.zoomToCard(existing, { pulse: true }); return existing; }
    const pk = cc.pkg;
    const mc = new S.MethodCard({ cls: cc.cls, proto, key, source: cc.cls.protocols[proto][key], accent: cc.accent, w: pk.w - 2 * PKG_PAD });
    const bottom = Math.max(...pk.members.map(m => (m._tw ? m._tw.y1 : m.y) + m.h));
    mc.x = pk.x + PKG_PAD; mc.y = bottom + 22;
    mc.classCard = cc;
    mc.mount();
    mc.pkg = pk; pk.members.push(mc);
    const chip = cc.chips.get(key);
    chip.classList.add('open');
    addEdge(cc, mc, localY(chip, cc) + chip.offsetHeight / 2, proto, 'method');
    relayoutBand(pk.band);
    mc.focus();
    S.sched.blip(cc.proc);
    if (o.fly) S.zoomToCard(mc, { edit: true }); else reveal(mc);
    return mc;
  };

  // ------------------------------------------------------------------ evaluation
  const HEAVY = /^\s*\(\s*1\s+to:\s*(\d+)\s*\)\s+count:\s*\[\s*:(\w+)\s*\|\s*\2\s+isPrime\s*\]\s*\.?\s*$/;
  S.transcript = s => { if (S.transcriptCard) S.transcriptCard.write(s); };
  S.evaluate = (card, ed, kind, r, o = {}) => {
    if (card.busyProc) return null;
    const hv = HEAVY.exec(r.src);
    if (hv && Number(hv[1]) > 300000) { runBusy(card, ed, kind, r, Number(hv[1])); return null; }
    let src = r.src;
    if (/\bself\b/.test(src) && card.kind === 'object') {
      if (!o.selfSrc) { ed.showError(r, 'self cannot be re-created for this object in the prototype'); return null; }
      src = src.replace(/\bself\b/g, '(' + o.selfSrc + ')');
    }
    S.sched.blip(card.proc);
    const forks = [];
    let res;
    try {
      res = MiniST.evaluate(src, { workspace: card.workspace || card.id, transcript: S.transcript, forked: (block, name) => forks.push(name) });
    } catch (e) {
      ed.showError(r, e && e.message ? e.message : String(e));
      return null;
    }
    ed.flash(r);
    forks.forEach(name => S.fork(card, ed, r, name, src));
    const fy = localY(ed.el, card) + ed.lineY(r.e);
    let spawned = null;
    if (kind === 'print') ed.insertResult(r, res.printString);
    else if (kind === 'inspect') spawned = S.spawnObject(card, res, { fy, label: 'inspect', src: r.src, reveal: o.reveal });
    return { res, card: spawned };
  };

  function extractBlock(src) {
    const m = /\]\s*(fork|forkNamed:|forkAt:)/.exec(src);
    if (!m) return null;
    let depth = 0;
    for (let i = m.index; i >= 0; i--) {
      if (src[i] === ']') depth++;
      else if (src[i] === '[' && --depth === 0) return src.slice(i + 1, m.index).trim();
    }
    return null;
  }
  S.fork = (card, ed, r, name, src, o = {}) => {
    const nm = typeof name === 'string' ? name : (name && name.name) || 'a Process';
    const body = extractBlock(src);
    const pc = new S.ProcessCard({ name: nm, src: r.src.trim().replace(/\.$/, '') });
    pc.proc.kind = 'fork';
    const hv = body && /^\(\s*1\s+to:\s*(\d+)\s*\)\s*count:\s*\[\s*:\w+\s*\|\s*\w+\s+isPrime\s*\]$/.exec(body);
    const work = hv ? S.sched.primeWork(Number(hv[1]), body)
      : S.sched.thunkWork(() => {
        try { return MiniST.evaluate(body || 'nil', { workspace: card.workspace || card.id, transcript: S.transcript }).printString; }
        catch (e) { return 'Error: ' + e.message; }
      }, 700);
    S.sched.start(pc.proc, work, (w, secs) => {
      pc.finished = typeof w.result === 'number' ? fmt(w.result) : w.result;
      pc.secs = secs;
      pc.update();
      S.transcript(`'${nm}' finished → ${pc.finished} (${secs.toFixed(1)} s)\n`);
    });
    const fy = localY(ed.el, card) + ed.lineY(r.e);
    spawnNear(pc, card, fy, { label: 'fork', kind: 'fork', reveal: o.reveal });
    return pc;
  };

  function runBusy(card, ed, kind, r, N) {
    const p = card.proc;
    const work = S.sched.primeWork(N, r.src.trim().replace(/\.$/, ''));
    const mark = ed.flash(r, 'running');
    card._busyCtx = { mark, r, ed };
    S.sched.start(p, work, (w, secs) => {
      mark && mark.remove();
      card._busyCtx = null;
      card.setBusy(null);
      const ps = String(w.result);
      if (kind === 'print') ed.insertResult(r, ps);
      else if (kind === 'inspect') S.spawnObject(card, MiniST.evaluate(ps), { fy: localY(ed.el, card) + ed.lineY(r.e), label: 'inspect', src: ps });
      S.transcript(`${p.name}: ${fmt(w.result)} primes below ${fmt(N)} in ${secs.toFixed(1)} s\n`);
    });
    card.setBusy(p);
    S.toast(`<b>${S.escH(p.name)}</b> is busy in its own Process — pan, zoom and type elsewhere. <kbd>⌘.</kbd> interrupts.`, 4200);
  }

  S.interrupt = proc => {
    let p = proc;
    const live = q => q && q.busy && q.state !== 'suspended';
    const f = S.focused;
    if (!p && f && live(f.busyProc)) p = f.busyProc;
    if (!p && f && f.kind === 'process' && live(f.fproc)) p = f.fproc;
    if (!p) p = S.sched.busyProcs().filter(live).sort((a, b) => b.t0 - a.t0)[0];
    if (!live(p)) { S.toast('No busy Process to interrupt'); return; }
    S.sched.suspend(p);
    const owner = S.cards.get(p.cardId);
    if (owner) { owner.updateBusy(); owner.update && owner.update(); }
    const dbg = new S.DebuggerCard({ proc: p, ownerCard: owner });
    spawnNear(dbg, owner, 17, { label: 'User Interrupt', kind: 'debug' });
    S.transcript(`User Interrupt in '${p.name}'\n`);
  };
  S.terminate = p => {
    if (!p) return;
    const owner = S.cards.get(p.cardId);
    if (p.kind === 'fork') S.sched.terminate(p);
    else { p.busy = false; p.work = null; p.state = 'waiting'; S.sched.emit(); }
    if (owner && owner.busyProc === p) {
      const bc = owner._busyCtx;
      owner.setBusy(null);
      if (bc) { bc.mark && bc.mark.remove(); bc.ed.showError(bc.r, 'Process terminated — unwound to the event loop'); owner._busyCtx = null; }
    }
    if (owner && owner.update) owner.update();
    [...S.cards.values()].filter(c => c.kind === 'debugger' && c.target === p).forEach(c => S.removeCard(c));
    S.transcript(`'${p.name}' terminated\n`);
  };

  // ------------------------------------------------------------------ drawing
  function resize() {
    vw = innerWidth; vh = innerHeight; dpr = devicePixelRatio || 1;
    bg.width = Math.round(vw * dpr); bg.height = Math.round(vh * dpr);
    const mr = mmCanvas.getBoundingClientRect();
    mmCanvas.width = Math.round(mr.width * dpr); mmCanvas.height = Math.round(mr.height * dpr);
    camDirty = bgDirty = mmDirty = true;
  }
  function rr(c, x, y, w, hh, r) { c.beginPath(); c.roundRect(x, y, w, hh, r); }
  function drawGrid() {
    let sp = 24 * cam.s;
    while (sp < 13) sp *= 4;
    const t = clamp((sp - 13) / 40, 0, 1);
    const dots = (spacing, alpha, size) => {
      if (alpha < 0.01) return;
      const ox = ((cam.x % spacing) + spacing) % spacing, oy = ((cam.y % spacing) + spacing) % spacing;
      ctx.beginPath();
      for (let x = ox; x < vw; x += spacing) for (let y = oy; y < vh; y += spacing) ctx.rect(x - size / 2, y - size / 2, size, size);
      ctx.fillStyle = `rgba(255,232,196,${alpha})`;
      ctx.fill();
    };
    dots(sp, 0.085 * t, 1.3);
    dots(sp * 4, 0.12, 1.8);
  }
  const scr = r => ({ x: r.x * cam.s + cam.x, y: r.y * cam.s + cam.y, w: r.w * cam.s, h: r.h * cam.s });
  const onScreen = s => s.x < vw && s.y < vh && s.x + s.w > 0 && s.y + s.h > 0;
  function drawRegions() {
    for (const r of S.regions) {
      const R = scr(regionRect(r));
      if (!onScreen(R)) continue;
      const rad = clamp(30 * cam.s, 6, 30);
      rr(ctx, R.x, R.y, R.w, R.h, rad);
      ctx.fillStyle = hexA(r.color, r.kind === 'play' ? 0.035 : 0.05);
      ctx.fill();
      ctx.lineWidth = 1;
      ctx.strokeStyle = hexA(r.color, 0.26);
      ctx.stroke();
      if (r.kind !== 'band') continue;
      for (const pk of r.pkgs) {
        const P = scr(pk);
        if (!onScreen(P)) continue;
        rr(ctx, P.x + 0.5, P.y + 0.5, P.w, P.h, clamp(18 * cam.s, 4, 18));
        ctx.fillStyle = hexA(r.color, 0.035);
        ctx.fill();
        ctx.setLineDash([4, 4]);
        ctx.strokeStyle = hexA(r.color, 0.3);
        ctx.stroke();
        ctx.setLineDash([]);
        if (PKG_LABEL * cam.s > 9 && S.mode !== 'map') {
          ctx.font = `600 ${clamp(PKG_LABEL * cam.s * 0.42, 9, 11)}px ui-monospace, "SF Mono", Menlo, monospace`;
          ctx.fillStyle = hexA(r.color, 0.85);
          ctx.textBaseline = 'middle';
          ctx.letterSpacing = '0.8px';
          ctx.fillText(pk.name.toUpperCase(), P.x + 14, P.y + PKG_LABEL * cam.s * 0.55);
          const w = ctx.measureText(pk.name.toUpperCase()).width;
          ctx.letterSpacing = '0px';
          ctx.fillStyle = 'rgba(200,190,170,.45)';
          ctx.fillText(`${pk.count} classes`, P.x + 24 + w, P.y + PKG_LABEL * cam.s * 0.55);
        }
      }
    }
  }
  function drawRegionLabels() {
    for (const r of S.regions) {
      const R = scr(regionRect(r));
      if (!onScreen(R) || R.w < 80) continue;
      const map = S.mode === 'map';
      if (map) { drawMapLabel(r, R); continue; }
      const pad = clamp(26 * cam.s, 10, 26);
      const nameSize0 = map ? clamp(150 * cam.s, 14, 22) : clamp(34 * cam.s, 16, 26);
      ctx.font = `500 ${nameSize0}px "New York", ui-serif, Georgia, serif`;
      const nameNeed = ctx.measureText(r.name).width + 50;
      ctx.font = `12px -apple-system, "SF Pro Text", sans-serif`;
      const fullNeed = nameNeed + 12 + ctx.measureText(r.tag).width;
      let lx = Math.max(R.x + pad, 14), ly = R.y + pad;
      if (r.kind === 'band') ly = Math.max(ly, Math.min(64, R.y + HEAD_H * cam.s - 44));
      const avail = R.x + R.w - pad - lx;
      const showTag = avail >= fullNeed;
      if (avail < nameNeed) lx = R.x + R.w - pad - nameNeed;
      if (ly < -60 || ly > vh) continue;
      const nameSize = map ? clamp(150 * cam.s, 14, 22) : clamp(34 * cam.s, 16, 26);
      ctx.textBaseline = 'alphabetic';
      // layer chip
      const chip = r.kind === 'band' ? `L${r.layer}` : '✦';
      ctx.font = `700 ${map ? 10 : 11}px ui-monospace, "SF Mono", Menlo, monospace`;
      const cw = ctx.measureText(chip).width + 12, chH = map ? 16 : 18;
      rr(ctx, lx, ly, cw, chH, 5);
      ctx.fillStyle = hexA(r.color, 0.2); ctx.fill();
      ctx.fillStyle = r.color;
      ctx.fillText(chip, lx + 6, ly + chH - (map ? 4.5 : 5));
      ctx.font = `500 ${nameSize}px "New York", ui-serif, "Iowan Old Style", Georgia, serif`;
      ctx.fillStyle = '#efe6d5';
      const nx = lx + cw + 10, base = ly + chH - 3;
      ctx.fillText(r.name, nx, base + (nameSize - chH) * 0.35);
      const nw = ctx.measureText(r.name).width;
      ctx.font = `${map ? 11 : 12}px -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif`;
      ctx.fillStyle = hexA(r.color, 0.9);
      if (map) { if (nx + nw + 12 + ctx.measureText(r.tag).width < R.x + R.w - 8) ctx.fillText(r.tag, nx + nw + 12, base + (nameSize - chH) * 0.35); }
      else {
        if (showTag) ctx.fillText(r.tag, nx + nw + 12, base + (nameSize - chH) * 0.35);
        const noteW = Math.min(R.x + R.w - pad - lx, 560);
        if (cam.s > 0.42 && r.note && noteW > 220) {
          ctx.fillStyle = 'rgba(214,204,186,.55)';
          ctx.font = `12px -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif`;
          wrapText(r.note, lx, base + nameSize * 0.5 + 18, noteW, 16, 2);
        }
      }
    }
  }
  const SERIF = '"New York", ui-serif, "Iowan Old Style", Georgia, serif', MONO = 'ui-monospace, "SF Mono", Menlo, monospace', SANS = '-apple-system, "SF Pro Text", "Helvetica Neue", sans-serif';
  function fitStr(t, maxW) {
    if (ctx.measureText(t).width <= maxW) return t;
    while (t.length > 1 && ctx.measureText(t + '…').width > maxW) t = t.slice(0, -1);
    return t + '…';
  }
  function drawMapLabel(r, R) {
    if (R.w < 60 || R.y > vh || R.y < -10) return;
    const chip = r.kind === 'band' ? `L${r.layer}` : '✦';
    ctx.textBaseline = 'alphabetic';
    ctx.font = `700 10px ${MONO}`;
    const cw = ctx.measureText(chip).width + 10;
    let fs = clamp(R.w / 7, 11, 22);
    ctx.font = `500 ${fs}px ${SERIF}`;
    while (fs > 11 && cw + 8 + ctx.measureText(r.name).width > R.w) { fs -= 1; ctx.font = `500 ${fs}px ${SERIF}`; }
    const nb = R.y - 24;
    rr(ctx, R.x, nb - 12, cw, 15, 4);
    ctx.fillStyle = hexA(r.color, 0.22); ctx.fill();
    ctx.fillStyle = r.color; ctx.font = `700 10px ${MONO}`; ctx.fillText(chip, R.x + 5, nb - 1);
    ctx.font = `500 ${fs}px ${SERIF}`; ctx.fillStyle = '#efe6d5';
    ctx.fillText(fitStr(r.name, R.w - cw - 8), R.x + cw + 8, nb);
    ctx.font = `11px ${SANS}`; ctx.fillStyle = hexA(r.color, 0.85);
    ctx.fillText(fitStr(r.tag, R.w), R.x, R.y - 8);
  }
  function wrapText(t, x, y, maxW, lh, maxLines) {
    const words = t.split(' ');
    let line = '', n = 0;
    for (const w of words) {
      const test = line ? line + ' ' + w : w;
      if (ctx.measureText(test).width > maxW && line) { ctx.fillText(line, x, y); y += lh; line = w; if (++n >= maxLines) return; }
      else line = test;
    }
    if (line) ctx.fillText(line, x, y);
  }
  function drawLayerArrows() {
    if (cam.s < 0.08) return;
    const bands = S.regions.filter(r => r.kind === 'band');
    const play = playRegion();
    const pairs = bands.slice(1).map((b, i) => [b, bands[i]]);
    pairs.push([play, bands[5]]);
    for (const [hi, lo] of pairs) {
      const x1 = (hi.x) * cam.s + cam.x - 8, x0 = (lo.x + lo.w) * cam.s + cam.x + 8;
      const y = (hi.y + HEAD_H + 46) * cam.s + cam.y;
      if (x1 < 0 || x0 > vw || y < -20 || y > vh + 20 || x1 - x0 < 24) continue;
      ctx.strokeStyle = hexA(lo.color, 0.55); ctx.fillStyle = hexA(lo.color, 0.75);
      ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.moveTo(x1, y); ctx.lineTo(x0 + 6, y); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x0 + 8, y - 4); ctx.lineTo(x0 + 8, y + 4); ctx.closePath(); ctx.fill();
      if (x1 - x0 > 56) {
        ctx.font = `10px ui-monospace, "SF Mono", Menlo, monospace`;
        ctx.textAlign = 'center'; ctx.fillStyle = 'rgba(214,204,186,.5)';
        ctx.fillText('calls', (x0 + x1) / 2, y - 7);
        ctx.textAlign = 'left';
      }
    }
  }
  const EDGE_COLORS = { inspect: '#86c5b6', fork: '#e8a84c', debug: '#e2725f', method: null, class: '#dcc69b' };
  function edgeGeom(e) {
    const a = e.from, b = e.to;
    const fy = clamp(e.fy ?? 17, 8, a.h - 8);
    let p0, p1, c0, c1;
    if (e.kind === 'method' && a.x - b.x < 40) {
      p0 = { x: a.x, y: a.y + fy }; p1 = { x: b.x, y: b.y + 17 };
      const lx = Math.min(p0.x, p1.x) - 46; c0 = { x: lx, y: p0.y }; c1 = { x: lx, y: p1.y };
    } else if (b.x >= a.x + a.w + 12) {
      p0 = { x: a.x + a.w, y: a.y + fy }; p1 = { x: b.x, y: b.y + 17 };
      const d = Math.max(40, (p1.x - p0.x) * 0.5); c0 = { x: p0.x + d, y: p0.y }; c1 = { x: p1.x - d, y: p1.y };
    } else if (b.x + b.w <= a.x - 12) {
      p0 = { x: a.x, y: a.y + fy }; p1 = { x: b.x + b.w, y: b.y + 17 };
      const d = Math.max(40, (p0.x - p1.x) * 0.5); c0 = { x: p0.x - d, y: p0.y }; c1 = { x: p1.x + d, y: p1.y };
    } else {
      const down = b.y > a.y;
      const cx = (Math.max(a.x, b.x) + Math.min(a.x + a.w, b.x + b.w)) / 2;
      p0 = { x: cx, y: down ? a.y + a.h : a.y }; p1 = { x: cx, y: down ? b.y : b.y + b.h };
      const d = Math.max(30, Math.abs(p1.y - p0.y) * 0.5) * (down ? 1 : -1); c0 = { x: p0.x, y: p0.y + d }; c1 = { x: p1.x, y: p1.y - d };
    }
    return [p0, c0, c1, p1];
  }
  function drawEdges(now) {
    for (const e of S.edges) {
      if (!S.cards.has(e.from.id) || !S.cards.has(e.to.id)) continue;
      const pts = edgeGeom(e).map(p => ({ x: p.x * cam.s + cam.x, y: p.y * cam.s + cam.y }));
      const [p0, c0, c1, p1] = pts;
      const minX = Math.min(p0.x, c0.x, c1.x, p1.x), maxX = Math.max(p0.x, c0.x, c1.x, p1.x), minY = Math.min(p0.y, c0.y, c1.y, p1.y), maxY = Math.max(p0.y, c0.y, c1.y, p1.y);
      if (maxX < 0 || minX > vw || maxY < 0 || minY > vh) continue;
      const col = EDGE_COLORS[e.kind] || e.from.accent;
      const running = e.kind === 'fork' && e.to.fproc && e.to.fproc.busy && e.to.fproc.state !== 'suspended';
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = hexA(col, e.kind === 'class' ? 0.45 : 0.62);
      if (running || e.kind === 'class' || e.kind === 'debug') { ctx.setLineDash(running ? [6, 6] : [3, 5]); ctx.lineDashOffset = running ? -now / 40 : 0; }
      ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.bezierCurveTo(c0.x, c0.y, c1.x, c1.y, p1.x, p1.y); ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = hexA(col, 0.9);
      ctx.beginPath(); ctx.arc(p0.x, p0.y, 3, 0, Math.PI * 2); ctx.fill();
      const ang = Math.atan2(p1.y - c1.y, p1.x - c1.x), L = 7.5;
      ctx.beginPath(); ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p1.x - L * Math.cos(ang - 0.45), p1.y - L * Math.sin(ang - 0.45));
      ctx.lineTo(p1.x - L * Math.cos(ang + 0.45), p1.y - L * Math.sin(ang + 0.45));
      ctx.closePath(); ctx.fill();
      if (e.label && S.mode === 'detail') {
        const t = 0.5, mt = 1 - t;
        const mx = mt * mt * mt * p0.x + 3 * mt * mt * t * c0.x + 3 * mt * t * t * c1.x + t * t * t * p1.x;
        const my = mt * mt * mt * p0.y + 3 * mt * mt * t * c0.y + 3 * mt * t * t * c1.y + t * t * t * p1.y;
        ctx.font = `10.5px ui-monospace, "SF Mono", Menlo, monospace`;
        const tw = ctx.measureText(e.label).width;
        rr(ctx, mx - tw / 2 - 7, my - 9, tw + 14, 18, 9);
        ctx.fillStyle = '#1c1a16'; ctx.fill();
        ctx.strokeStyle = hexA(col, 0.45); ctx.lineWidth = 1; ctx.stroke();
        ctx.fillStyle = hexA(col, 1); ctx.textBaseline = 'middle'; ctx.textAlign = 'center';
        ctx.fillText(e.label, mx, my + 0.5);
        ctx.textAlign = 'left';
      }
    }
  }
  function drawBlocks(alpha) {
    ctx.globalAlpha = alpha;
    ctx.textBaseline = 'middle';
    for (const c of S.cards.values()) {
      const R = scr(c.rect());
      if (!onScreen(R)) continue;
      const rad = clamp(12 * cam.s, 2, 10);
      rr(ctx, R.x, R.y, R.w, R.h, rad);
      ctx.fillStyle = '#2a2722'; ctx.fill();
      ctx.strokeStyle = hexA(c.accent, c.busyProc || (c.fproc && c.fproc.busy) ? 0.95 : 0.35); ctx.lineWidth = 1; ctx.stroke();
      ctx.fillStyle = hexA(c.accent, 0.85);
      ctx.fillRect(R.x + rad, R.y, Math.min(R.w - rad * 2, 22), 2);
      if (R.w > 36 && R.h > 14) {
        const fs = clamp(R.w / 9, 9, 12.5);
        ctx.font = `600 ${fs}px -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif`;
        let t = c.kind === 'method' ? S.selectorOf(c.key) : c.kind === 'object' ? c.res.printString : c.title;
        const maxW = R.w - 12;
        if (ctx.measureText(t).width > maxW) { while (t.length > 1 && ctx.measureText(t + '…').width > maxW) t = t.slice(0, -1); t += '…'; }
        ctx.fillStyle = '#eee5d4';
        ctx.fillText(t, R.x + 6, R.y + Math.min(R.h / 2, 13));
      }
    }
    ctx.globalAlpha = 1;
  }
  function drawBG(now) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#171612';
    ctx.fillRect(0, 0, vw, vh);
    const g = ctx.createRadialGradient(vw * 0.55, vh * 0.35, 0, vw * 0.55, vh * 0.35, Math.max(vw, vh) * 0.8);
    g.addColorStop(0, 'rgba(60,50,36,.28)'); g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, vw, vh);
    drawGrid();
    drawRegions();
    drawLayerArrows();
    drawEdges(now);
    if (blockAlpha > 0.01) drawBlocks(blockAlpha);
    drawRegionLabels();
    bgDirty = false;
  }

  // ------------------------------------------------------------------ minimap
  let mmMap = null;
  function drawMinimap() {
    const W = mmCanvas.width / dpr, H = mmCanvas.height / dpr;
    mctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    mctx.clearRect(0, 0, W, H);
    const b = worldBounds(), pad = 8;
    const k = Math.min((W - pad * 2) / b.w, (H - pad * 2) / b.h);
    const ox = pad + (W - pad * 2 - b.w * k) / 2 - b.x * k, oy = pad + (H - pad * 2 - b.h * k) / 2 - b.y * k;
    mmMap = { k, ox, oy };
    for (const r of S.regions) {
      const R = regionRect(r);
      rr(mctx, R.x * k + ox, R.y * k + oy, R.w * k, R.h * k, 3);
      mctx.fillStyle = hexA(r.color, 0.13); mctx.fill();
      mctx.strokeStyle = hexA(r.color, 0.45); mctx.lineWidth = 1; mctx.stroke();
    }
    for (const c of S.cards.values()) {
      if (c.x < -9000) continue;
      const busy = (c.busyProc && c.busyProc.state !== 'suspended') || (c.fproc && c.fproc.busy && c.fproc.state !== 'suspended');
      mctx.fillStyle = busy ? '#e8a84c' : c.kind === 'debugger' ? '#e2725f' : hexA(c.accent, 0.55);
      mctx.fillRect(c.x * k + ox, c.y * k + oy, Math.max(1.5, c.w * k), Math.max(1.5, c.h * k));
    }
    const v0 = toWorld(0, 0), v1 = toWorld(vw, vh);
    const vx = v0.x * k + ox, vy = v0.y * k + oy, vwid = (v1.x - v0.x) * k, vhei = (v1.y - v0.y) * k;
    mctx.fillStyle = 'rgba(255,240,215,.07)';
    mctx.fillRect(vx, vy, vwid, vhei);
    mctx.strokeStyle = 'rgba(255,240,215,.85)'; mctx.lineWidth = 1.2;
    mctx.strokeRect(Math.round(vx) + 0.5, Math.round(vy) + 0.5, Math.max(3, vwid), Math.max(3, vhei));
    mmDirty = false;
  }
  function mmToWorld(e) { const r = mmCanvas.getBoundingClientRect(); return { x: (e.clientX - r.left - mmMap.ox) / mmMap.k, y: (e.clientY - r.top - mmMap.oy) / mmMap.k }; }
  let mmDrag = false;
  mmCanvas.addEventListener('pointerdown', e => {
    e.stopPropagation(); mmDrag = true; mmCanvas.setPointerCapture(e.pointerId);
    const p = mmToWorld(e); flyTo({ cx: p.x, cy: p.y, s: cam.s }, 380);
  });
  mmCanvas.addEventListener('pointermove', e => { if (!mmDrag || anim) return; const p = mmToWorld(e); setCam(vw / 2 - p.x * cam.s, vh / 2 - p.y * cam.s, cam.s); });
  mmCanvas.addEventListener('pointerup', () => { mmDrag = false; });

  // ------------------------------------------------------------------ HUD
  const crumb = $('#crumb'), zpct = $('#zpct');
  function updateHud() {
    const c = toWorld(vw / 2, vh / 2);
    const reg = S.regions.find(r => contains(regionRect(r), c));
    const pk = reg && reg.pkgs ? reg.pkgs.find(p => contains(p, c)) : null;
    let card = null;
    for (const cd of S.cards.values()) if (contains(cd.rect(), c)) card = cd;
    const parts = [];
    if (reg) parts.push(`<button data-go="region" style="--c:${reg.color}"><i></i>${reg.kind === 'band' ? 'L' + reg.layer + ' · ' : ''}${S.escH(reg.name)}</button>`);
    else parts.push('<span class="dim">open canvas</span>');
    if (pk) parts.push(`<span>${S.escH(pk.name)}</span>`);
    if (card && S.mode !== 'map') parts.push(`<span class="cur">${S.escH(card.kind === 'object' ? card.res.className : card.title)}</span>`);
    const html = parts.join('<b>›</b>') + `<span class="mode">${S.mode}</span>`;
    if (html !== crumb._h) {
      crumb._h = html; crumb.innerHTML = html;
      const b = crumb.querySelector('[data-go=region]');
      if (b) b.addEventListener('click', () => flyTo(fitRect(regionRect(reg), { maxS: 1 })));
    }
    zpct.textContent = Math.round(cam.s * 100) + '%';
    hudDirty = false;
  }

  const statCanvas = $('#stats canvas'), sctx = statCanvas.getContext('2d'), statText = $('#stats .t');
  const frameTimes = [];
  let lastFrame = 0, statT = 0;
  function drawStats(now) {
    const W = 72, H = 18;
    if (statCanvas.width !== W * dpr) { statCanvas.width = W * dpr; statCanvas.height = H * dpr; }
    sctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    sctx.clearRect(0, 0, W, H);
    const n = Math.min(frameTimes.length, 60);
    const yOf = ft => H - 1 - clamp(ft / 40, 0, 1) * (H - 2);
    sctx.fillStyle = 'rgba(255,240,215,.14)'; sctx.fillRect(0, Math.round(yOf(16.7)), W, 1);
    sctx.beginPath();
    for (let i = 0; i < n; i++) { const x = W - (n - 1 - i) * (W / 59), y = yOf(frameTimes[frameTimes.length - n + i]); i ? sctx.lineTo(x, y) : sctx.moveTo(x, y); }
    sctx.strokeStyle = 'rgba(167,199,140,.9)'; sctx.lineWidth = 1.2; sctx.lineJoin = 'round'; sctx.stroke();
    for (let i = 0; i < n; i++) { const ft = frameTimes[frameTimes.length - n + i]; if (ft > 20) { sctx.fillStyle = '#e2725f'; sctx.fillRect(W - (n - 1 - i) * (W / 59) - 1, yOf(ft) - 1, 2, 2); } }
    if (now - statT > 300) {
      statT = now;
      const recent = frameTimes.slice(-30);
      const avg = recent.reduce((a, b) => a + b, 0) / (recent.length || 1);
      const busy = S.sched.procs.filter(p => p.busy && p.state !== 'suspended').length;
      statText.innerHTML = `<div><b>compositor</b> ${avg.toFixed(1)} ms · ${Math.round(1000 / avg)} fps</div><span>${S.sched.procs.length} Processes · ${busy} busy · 1 OS thread</span>`;
    }
  }

  // ------------------------------------------------------------------ main loop
  let procT = 0;
  function frame(now) {
    if (lastFrame) { frameTimes.push(now - lastFrame); if (frameTimes.length > 120) frameTimes.shift(); }
    lastFrame = now;
    const busy = S.sched.tick(now);
    if (anim) stepAnim(now);
    if (inertia) {
      setCam(cam.x + inertia.vx * 16, cam.y + inertia.vy * 16, cam.s);
      inertia.vx *= 0.9; inertia.vy *= 0.9;
      if (Math.hypot(inertia.vx, inertia.vy) < 0.02) inertia = null;
    }
    stepTweens(now);
    if (camDirty) applyCam();
    const target = S.mode === 'map' ? 1 : 0;
    if (Math.abs(blockAlpha - target) > 0.01) { blockAlpha += (target - blockAlpha) * 0.22; bgDirty = true; } else blockAlpha = target;
    if (busy) { bgDirty = true; mmDirty = mmDirty || (now % 500 < 17); }
    if (bgDirty) drawBG(now);
    if (mmDirty) drawMinimap();
    if (hudDirty) updateHud();
    if (now - procT > 110) {
      procT = now;
      for (const c of S.cards.values()) {
        if (c.kind === 'process' && (c.fproc.busy || c._wasBusy)) { c.update(); c._wasBusy = c.fproc.busy; }
        if (c.busyProc) c.updateBusy();
      }
      if (procDirty) {
        procDirty = false;
        for (const c of S.cards.values()) { c.updateProc(); if (c.kind === 'processes') c.render(); }
      }
    }
    drawStats(now);
    requestAnimationFrame(frame);
  }
  S.sched.onChange(() => { procDirty = true; });

  // ------------------------------------------------------------------ input
  let spaceDown = false, drag = null;
  const body = document.body;
  viewport.addEventListener('pointerdown', e => {
    hideMenu();
    const onCard = e.target.closest('.card');
    const pan = e.button === 1 || (e.button === 0 && (spaceDown || !onCard));
    if (!pan) return;
    e.preventDefault();
    if (onCard) e.stopPropagation();
    if (!onCard && isEditable(document.activeElement)) document.activeElement.blur();
    cancelAnim();
    drag = { type: 'pan', id: e.pointerId, lx: e.clientX, ly: e.clientY, sx: e.clientX, sy: e.clientY, t: performance.now(), vx: 0, vy: 0 };
    viewport.setPointerCapture(e.pointerId);
    body.classList.add('dragging');
  }, true);
  S.beginCardDrag = (card, e) => {
    if (e.target.closest('textarea, button, .row, .sel, .tab, .frame, .prow')) return;
    cancelAnim();
    drag = { type: 'card', card, id: e.pointerId, sx: e.clientX, sy: e.clientY, ox: card.x, oy: card.y, moved: false };
    viewport.setPointerCapture(e.pointerId);
    e.preventDefault();
  };
  viewport.addEventListener('pointermove', e => {
    if (!drag || e.pointerId !== drag.id) return;
    if (drag.type === 'pan') {
      const dx = e.clientX - drag.lx, dy = e.clientY - drag.ly, t = performance.now(), dt = Math.max(1, t - drag.t);
      drag.vx = drag.vx * 0.6 + (dx / dt) * 0.4; drag.vy = drag.vy * 0.6 + (dy / dt) * 0.4;
      drag.lx = e.clientX; drag.ly = e.clientY; drag.t = t;
      setCam(cam.x + dx, cam.y + dy, cam.s);
    } else {
      const dx = (e.clientX - drag.sx) / cam.s, dy = (e.clientY - drag.sy) / cam.s;
      if (!drag.moved && Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy) < 4) return;
      if (!drag.moved) { drag.moved = true; drag.card.el.classList.add('lifted'); }
      drag.card.moveTo(drag.ox + dx, drag.oy + dy);
    }
  });
  const endDrag = e => {
    if (!drag || e.pointerId !== drag.id) return;
    body.classList.remove('dragging');
    if (drag.type === 'pan') {
      const moved = Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy);
      if (performance.now() - drag.t < 60 && Math.hypot(drag.vx, drag.vy) > 0.25) inertia = { vx: drag.vx, vy: drag.vy };
      if (moved < 4 && S.mode === 'map') {
        const p = toWorld(e.clientX, e.clientY);
        const hit = [...S.cards.values()].reverse().find(c => contains(c.rect(), p));
        if (hit) S.zoomToCard(hit);
      } else if (moved < 4 && S.focused) { S.focused.el.classList.remove('focused'); S.focused = null; }
    } else {
      drag.card.el.classList.remove('lifted');
      if (!drag.moved && S.mode !== 'detail') S.zoomToCard(drag.card);
    }
    drag = null;
  };
  viewport.addEventListener('scroll', () => { viewport.scrollTop = 0; viewport.scrollLeft = 0; });
  viewport.addEventListener('pointerup', endDrag);
  viewport.addEventListener('pointercancel', endDrag);

  viewport.addEventListener('wheel', e => {
    e.preventDefault();
    cancelAnim();
    let dx = e.deltaX, dy = e.deltaY;
    if (e.deltaMode === 1) { dx *= 16; dy *= 16; }
    if (e.ctrlKey || e.metaKey) zoomAt(e.clientX, e.clientY, Math.exp(-clamp(dy, -60, 60) * 0.0095));
    else { if (e.shiftKey && !dx) { dx = dy; dy = 0; } setCam(cam.x - dx, cam.y - dy, cam.s); }
  }, { passive: false });
  let gScale = 1;
  viewport.addEventListener('gesturestart', e => { e.preventDefault(); gScale = 1; });
  viewport.addEventListener('gesturechange', e => { e.preventDefault(); zoomAt(e.clientX, e.clientY, e.scale / gScale); gScale = e.scale; });

  viewport.addEventListener('dblclick', e => {
    if (e.target.closest('.card')) return;
    const p = toWorld(e.clientX, e.clientY);
    const reg = S.regions.find(r => contains(regionRect(r), p));
    if (reg && cam.s < 0.5) flyTo(fitRect(regionRect(reg), { maxS: 1 }));
    else if (reg) flyTo({ cx: p.x, cy: p.y, s: Math.min(1.2, cam.s * 1.6) });
    else fitAll();
  });
  viewport.addEventListener('contextmenu', e => {
    if (e.target.closest('.card')) return;
    e.preventDefault();
    const p = toWorld(e.clientX, e.clientY);
    S.menu(e.clientX, e.clientY, [
      { label: 'New playground here', key: 'N', action: () => newSnippet(p) },
      { label: 'New note here', action: () => newNote(p) },
      { sep: true },
      { label: 'Zoom to fit everything', key: '0', action: fitAll },
      { label: 'Back to the trail', key: 'H', action: home },
    ]);
  });

  window.addEventListener('keydown', e => {
    const mod = e.metaKey || e.ctrlKey, k = e.key;
    if (mod && k.toLowerCase() === 'k') { e.preventDefault(); e.stopPropagation(); openSpotter(); return; }
    if (mod && k === '.') { e.preventDefault(); e.stopPropagation(); S.interrupt(); return; }
    if (k === 'Escape' && closeOverlays()) { e.preventDefault(); return; }
    if (!$('#spotter').hidden) return;
    if (mod && k === '0') { e.preventDefault(); fitAll(); return; }
    if (mod && (k === '=' || k === '+')) { e.preventDefault(); zoomBy(1.3); return; }
    if (mod && k === '-') { e.preventDefault(); zoomBy(1 / 1.3); return; }
    if (isEditable(document.activeElement) || mod) return;
    if (k === ' ') { e.preventDefault(); if (!spaceDown) { spaceDown = true; body.classList.add('space'); } return; }
    if (k === '?') toggleHelp();
    else if (k === '0') fitAll();
    else if (k === '1') zoom100();
    else if (k === '=' || k === '+') zoomBy(1.3);
    else if (k === '-') zoomBy(1 / 1.3);
    else if (k === 'h' || k === 'H') home();
    else if ((k === 'f' || k === 'F') && S.focused) S.zoomToCard(S.focused);
    else if (k === 'n' || k === 'N') newSnippet(toWorld(vw / 2 - 200, vh / 2 - 120));
    else return;
    e.preventDefault();
  }, true);
  window.addEventListener('keyup', e => { if (e.key === ' ') { spaceDown = false; body.classList.remove('space'); } });
  window.addEventListener('blur', () => { spaceDown = false; body.classList.remove('space'); });
  window.addEventListener('resize', resize);
  window.addEventListener('pointerdown', e => { if (!e.target.closest('#menu')) hideMenu(); });

  function newSnippet(p) {
    const c = new S.SnippetCard({ x: Math.round(p.x), y: Math.round(p.y), w: 420, title: 'Playground', text: '"New playground"\n3 + 4\n' });
    c.zone = contains(regionRect(playRegion()), p) ? 'play' : null;
    c.mount(); c.focus();
    setTimeout(() => { c.ed.ta.focus({ preventScroll: true }); c.ed.ta.setSelectionRange(c.ed.text.length, c.ed.text.length); }, 30);
  }
  function newNote(p) {
    const c = new S.NoteCard({ x: Math.round(p.x), y: Math.round(p.y), title: 'Note', text: 'Write anything. Code like 2 raisedTo: 64 evaluates too — select it, ⌘P.' });
    c.zone = contains(regionRect(playRegion()), p) ? 'play' : null;
    c.mount(); c.focus();
  }

  $('#zoomctl').addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.z === 'in') zoomBy(1.3); else if (b.dataset.z === 'out') zoomBy(1 / 1.3); else if (b.dataset.z === 'fit') fitAll(); else zoom100();
  });
  $('#helpBtn').addEventListener('click', () => toggleHelp());
  $('#spotBtn').addEventListener('click', () => openSpotter());
  $('#homeBtn').addEventListener('click', () => home());

  // ------------------------------------------------------------------ menu / toast / help
  const menuEl = $('#menu');
  S.menu = (x, y, items) => {
    menuEl.innerHTML = '';
    for (const it of items) {
      if (it.sep) { menuEl.appendChild(h('div', 'sep')); continue; }
      const b = h('button', 'mi', `<span>${it.label}</span>${it.key ? `<kbd>${it.key}</kbd>` : ''}`);
      b.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); });
      b.addEventListener('click', () => { hideMenu(); it.action(); });
      menuEl.appendChild(b);
    }
    menuEl.hidden = false;
    const r = menuEl.getBoundingClientRect();
    menuEl.style.left = Math.min(x, vw - r.width - 8) + 'px';
    menuEl.style.top = Math.min(y, vh - r.height - 8) + 'px';
  };
  function hideMenu() { menuEl.hidden = true; }
  const toastEl = $('#toast');
  let toastT = 0;
  S.toast = (msg, ms = 2400) => {
    toastEl.innerHTML = msg; toastEl.classList.add('on');
    clearTimeout(toastT); toastT = setTimeout(() => toastEl.classList.remove('on'), ms);
  };
  function toggleHelp(force) { const el = $('#help'); el.hidden = force != null ? !force : !el.hidden; }
  $('#help').addEventListener('pointerdown', e => { if (e.target.id === 'help' || e.target.closest('.x')) toggleHelp(false); });
  function closeOverlays() {
    if (!menuEl.hidden) { hideMenu(); return true; }
    if (!$('#spotter').hidden) { closeSpotter(); return true; }
    if (!$('#help').hidden) { toggleHelp(false); return true; }
    return false;
  }

  // ------------------------------------------------------------------ spotter
  const spotEl = $('#spotter'), spotIn = $('#spotter input'), spotList = $('#spotter .results');
  let spotItems = [], spotSel = 0;
  function allTargets() {
    const out = [];
    for (const r of S.regions) out.push({ kind: r.kind === 'band' ? 'layer' : 'region', label: r.kind === 'band' ? `L${r.layer} ${r.name}` : r.name, path: r.tag, color: r.color, go: () => flyTo(fitRect(regionRect(r), { maxS: 1 })) });
    for (const p of FakeImage.packages) {
      const band = S.regions.find(r => r.layer === p.layer), pk = band.pkgs.find(k => k.name === p.name);
      out.push({ kind: 'package', label: p.name, path: `L${p.layer} · ${p.classes.length} classes`, color: band.color, go: () => flyTo(fitRect(pk, { maxS: 1 })) });
      for (const c of p.classes) {
        const cc = S.classCards.get(c.name);
        out.push({ kind: 'class', label: c.name, path: `L${p.layer} · ${p.name}`, color: band.color, go: () => S.zoomToCard(cc, { pulse: true }) });
        for (const [proto, ms] of Object.entries(c.protocols)) for (const key of Object.keys(ms))
          out.push({ kind: 'method', label: `${c.name}>>${S.selectorOf(key)}`, path: proto, color: band.color, go: () => S.openMethod(cc, proto, key, { fly: true }) });
      }
    }
    for (const c of S.cards.values()) if (c.kind !== 'class' && c.kind !== 'method')
      out.push({ kind: 'card', label: c.kind === 'object' ? c.res.printString.slice(0, 40) : c.title, path: c.kind === 'object' ? c.res.className + ' · inspector' : c.kind, color: c.accent, go: () => S.zoomToCard(c, { pulse: true }) });
    return out;
  }
  function score(q, s) {
    s = s.toLowerCase();
    if (!q) return 1;
    const i = s.indexOf(q);
    if (i === 0) return 100 - s.length * 0.1;
    if (i > 0) return 60 - i - s.length * 0.1;
    let j = 0, sc = 0, last = -2;
    for (let k = 0; k < s.length && j < q.length; k++) if (s[k] === q[j]) { sc += last === k - 1 ? 3 : 1; last = k; j++; }
    return j === q.length ? sc : -1;
  }
  function renderSpotter() {
    const q = spotIn.value.trim().toLowerCase();
    const all = allTargets();
    spotItems = q ? all.map(t => ({ t, s: score(q, t.label) })).filter(x => x.s > 0).sort((a, b) => b.s - a.s).slice(0, 9).map(x => x.t)
      : all.filter(t => t.kind === 'layer' || t.kind === 'card' || t.kind === 'region').slice(0, 9);
    spotSel = Math.min(spotSel, Math.max(0, spotItems.length - 1));
    spotList.innerHTML = spotItems.length ? spotItems.map((t, i) => `<div class="res ${i === spotSel ? 'on' : ''}" data-i="${i}" style="--c:${t.color}"><span class="k">${t.kind}</span><span class="l">${S.escH(t.label)}</span><span class="p">${S.escH(t.path || '')}</span></div>`).join('')
      : `<div class="none">Nothing matches “${S.escH(q)}”</div>`;
  }
  function openSpotter() {
    hideMenu();
    spotEl.hidden = false; spotIn.value = ''; spotSel = 0; renderSpotter();
    setTimeout(() => spotIn.focus(), 0);
  }
  function closeSpotter() { spotEl.hidden = true; spotIn.blur(); }
  function chooseSpot(i) { const t = spotItems[i]; closeSpotter(); if (t) t.go(); }
  spotIn.addEventListener('input', () => { spotSel = 0; renderSpotter(); });
  spotIn.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { spotSel = Math.min(spotSel + 1, spotItems.length - 1); renderSpotter(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { spotSel = Math.max(spotSel - 1, 0); renderSpotter(); e.preventDefault(); }
    else if (e.key === 'Enter') { chooseSpot(spotSel); e.preventDefault(); }
  });
  spotList.addEventListener('pointerdown', e => { const r = e.target.closest('.res'); if (r) { e.preventDefault(); chooseSpot(+r.dataset.i); } });
  spotList.addEventListener('pointermove', e => { const r = e.target.closest('.res'); if (r && +r.dataset.i !== spotSel) { spotSel = +r.dataset.i; renderSpotter(); } });
  spotEl.addEventListener('pointerdown', e => { if (e.target === spotEl) closeSpotter(); });

  // ------------------------------------------------------------------ startup
  const SNIPPET = `"Select a line (or just place the cursor in it):
 ⌘D do it · ⌘P print it · ⌘I inspect it — or right-click"
100 factorial.
(1 to: 20) select: [:i | i isPrime].
3/4 + (1/4).
3 @ 4 + 1.
Transcript show: 'hello, Samaltak'; cr.
#(3 1 4 1 5 9 2 6) asSortedCollection.
(2/3) + (1/6).

"Green threads: 'crunch' gets its own Process"
[(1 to: 200000000) count: [:i | i isPrime]] forkNamed: 'crunch'.

"Busy in THIS card's Process — ⌘. interrupts"
(1 to: 25000000) count: [:i | i isPrime]`;

  let homeCam = null;
  function home() { if (homeCam) flyTo(homeCam); }
  function lineRange(ed, needle) {
    const t = ed.text, s = t.indexOf(needle);
    return { s, e: s + needle.length, src: needle };
  }
  function buildPlayground() {
    const P = playRegion();
    const snip = new S.SnippetCard({ x: P.x + 40, y: P.y + 104, w: 540, text: SNIPPET, sub: 'workspace' });
    snip.zone = 'play'; snip.mount();
    snip.setTitle('Playground', 'workspace');
    const ed = snip.ed;
    // Exploration trail: inspect → field → object
    const a = S.evaluate(snip, ed, 'inspect', lineRange(ed, '(1 to: 20) select: [:i | i isPrime].'), { reveal: false });
    const rowEl = [...a.card.view.querySelectorAll('.row')].find(r => r.querySelector('.k').textContent === '6');
    const b = S.inspectField(a.card, { name: '6', value: '13' }, rowEl);
    const fr = lineRange(ed, "[(1 to: 200000000) count: [:i | i isPrime]] forkNamed: 'crunch'.");
    S.evaluate(snip, ed, 'do', fr, { reveal: false });
    const tr = new S.TranscriptCard({ x: P.x + 40, y: snip.y + snip.h + 36, w: 540, text: 'Samaltak 0.1 — image started on 1 OS thread\n' });
    tr.zone = 'play'; tr.mount();
    S.transcriptCard = tr;
    S.evaluate(snip, ed, 'do', lineRange(ed, "Transcript show: 'hello, Samaltak'; cr."), { reveal: false });
    const pr = new S.ProcessesCard({ x: b.x, y: b.y + b.h + 36, w: b.w + 30 });
    pr.zone = 'play'; pr.mount();
    const note = new S.NoteCard({
      x: tr.x, y: tr.y + tr.h + 36, w: tr.w, title: 'One plane, every object a card',
      text: 'Evaluate a line to spawn a live object; click a field to follow it. Each card runs in its own green thread — the crunch Process keeps working while you pan, zoom and type.\n\nZoom out (pinch, ⌘-scroll, or 0) to see the layers: Kernel → 3D → 2D → Windows → Widgets → Tools.',
    });
    note.zone = 'play'; note.mount();
    for (const c of S.cards.values()) c.el.style.animation = 'none';
    if (S.focused) { S.focused.el.classList.remove('focused'); S.focused = null; }
    snip.focus();
    // Camera: the trail, with the Tools layer peeking in on the left.
    const s = clamp(Math.min(vw / 1800, vh / 1120), 0.55, 1);
    const left = P.x - 300;
    homeCam = { cx: left + vw / s / 2, cy: P.y - 40 + vh / s / 2, s };
    cancelAnim();
    setCam(vw / 2 - homeCam.cx * s, vh / 2 - homeCam.cy * s, s);
  }

  resize();
  layoutStrata();
  buildPlayground();
  applyCam();
  requestAnimationFrame(frame);
  S._debug = { cam, flyTo, fitAll, home, worldBounds };
})(window.Sam);
