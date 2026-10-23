// Samaltak — Direction 4 "Spatial Morphic". Core: helpers, springs, windows, compositor loop, processes.
(function () {
  'use strict';
  const S = window.S = {};
  S.$ = (s, r = document) => r.querySelector(s);
  S.$$ = (s, r = document) => [...r.querySelectorAll(s)];
  S.esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  S.clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  S.lerp = (a, b, t) => a + (b - a) * t;

  function h(tag, props, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v;
      else if (k === 'style' && typeof v === 'object') { for (const [sk, sv] of Object.entries(v)) { if (sk.startsWith('--')) e.style.setProperty(sk, sv); else e.style[sk] = sv; } }
      else if (k === 'html') e.innerHTML = v;
      else if (k === 'text') e.textContent = v;
      else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat(3)) if (k != null && k !== false) e.append(k.nodeType ? k : document.createTextNode(k));
    return e;
  }
  S.h = h;

  // ---------- icons ----------
  const svg = p => `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${p}</svg>`;
  S.ICON = {
    close: svg('<path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/>'),
    flip: svg('<path d="M2.5 8a5.5 5.5 0 0 1 9.6-3.6M13.5 8a5.5 5.5 0 0 1-9.6 3.6"/><path d="M12.4 1.8v2.8H9.6M3.6 14.2v-2.8h2.8"/>'),
    layers: svg('<path d="M8 2l6 3.2L8 8.4 2 5.2z"/><path d="M2 8l6 3.2L14 8"/><path d="M2 10.8L8 14l6-3.2"/>'),
    grab: svg('<path d="M5.5 8V3.8a1 1 0 0 1 2 0V7.5M7.5 7V2.8a1 1 0 0 1 2 0V7.5M9.5 7.2V3.8a1 1 0 0 1 2 0v5.4a4.8 4.8 0 0 1-4.8 4.8h-.4A3.8 3.8 0 0 1 3 10.7L2.2 8.6a1 1 0 0 1 1.7-1L5.5 9.5"/>'),
    dup: svg('<rect x="5" y="5" width="8.5" height="8.5" rx="2"/><path d="M11 3.2V3a1.5 1.5 0 0 0-1.5-1.5H3A1.5 1.5 0 0 0 1.5 3v6.5A1.5 1.5 0 0 0 3 11h.2"/>'),
    inspect: svg('<circle cx="7" cy="7" r="4.5"/><path d="M10.4 10.4L14 14"/>'),
    browse: svg('<path d="M5.5 2.5c-1.6 0-2 .8-2 2v1.6c0 .9-.6 1.6-1.5 1.9.9.3 1.5 1 1.5 1.9v1.6c0 1.2.4 2 2 2M10.5 2.5c1.6 0 2 .8 2 2v1.6c0 .9.6 1.6 1.5 1.9-.9.3-1.5 1-1.5 1.9v1.6c0 1.2-.4 2-2 2"/>'),
    color: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" fill="url(#rb)"/><defs><linearGradient id="rb" x1="0" x2="1"><stop offset="0" stop-color="#ff5f6d"/><stop offset=".33" stop-color="#ffc371"/><stop offset=".66" stop-color="#47e3b5"/><stop offset="1" stop-color="#6a8bff"/></linearGradient></defs></svg>',
    rotate: svg('<path d="M13 8a5 5 0 1 1-1.6-3.7"/><path d="M13.2 1.8v3.4H9.8"/>'),
    resize: svg('<path d="M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5L9 7M2.5 13.5L7 9"/>'),
    x: svg('<path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/>'),
    expose: svg('<rect x="1.5" y="2.5" width="5.5" height="4.5" rx="1"/><rect x="9" y="2.5" width="5.5" height="4.5" rx="1"/><rect x="1.5" y="9" width="5.5" height="4.5" rx="1"/><rect x="9" y="9" width="5.5" height="4.5" rx="1"/>'),
    up: svg('<path d="M4 10l4-4 4 4"/>'),
  };

  // ---------- springs ----------
  class Spring {
    constructor(x, k = 180, c = 22, eps = 0.01) { this.x = x; this.t = x; this.v = 0; this.k = k; this.c = c; this.eps = eps; }
    set(t) { this.t = t; return this; }
    snap(x) { this.x = this.t = x; this.v = 0; return this; }
    step(dt) {
      if (Math.abs(this.x - this.t) < this.eps && Math.abs(this.v) < this.eps * 10) { this.x = this.t; this.v = 0; return false; }
      const n = Math.max(1, Math.ceil(dt / 0.006)), hh = dt / n;
      for (let i = 0; i < n; i++) { const a = -this.k * (this.x - this.t) - this.c * this.v; this.v += a * hh; this.x += this.v * hh; }
      return true;
    }
  }
  S.Spring = Spring;

  // ---------- layers (package layer colors) ----------
  S.LAYER = {
    0: { name: 'Kernel', color: '#7a86a8' },
    1: { name: 'Graphics-GPU', color: '#ff6b6b' },
    2: { name: 'Graphics-Canvas', color: '#f5a524' },
    3: { name: 'UI-Windows', color: '#34c38f' },
    4: { name: 'UI-Widgets', color: '#4f8dff' },
    5: { name: 'Tools', color: '#a77bff' },
  };

  // ---------- processes (green threads) ----------
  let nextPid = 100;
  S.procs = [];
  S.newProc = (p) => {
    const proc = Object.assign({ pid: nextPid++, priority: 40, state: 'waiting', kind: 'window', window: null, lane: new Float32Array(150), act: 0, cpu: 0, hue: 220 }, p);
    S.procs.push(proc);
    return proc;
  };
  S.FRAME = 0;
  for (const p of FakeImage.processes) {
    if (p.window) continue;
    S.newProc({ name: p.name, priority: p.priority, state: p.state, kind: 'system', hue: { 'timer interrupt watcher': 260, 'compositor (vsync)': 160, 'input dispatcher': 200, finalization: 30, idle: 220 }[p.name] ?? 220 });
  }
  S.sysProc = name => S.procs.find(p => p.name === name);

  // ---------- transcript ----------
  S.transcriptLog = 'Samaltak 0.1 (prototype) — image booted in 41 ms, 1 OS thread, ' + 'green threads preemptive at safepoints\n' +
    'Compositor: GPU device "Apple M-series" · vsync 60 Hz · layer textures off-heap\n';
  S.transcriptSinks = new Set();
  S.transcript = s => {
    S.transcriptLog += s;
    if (!S.transcriptSinks.size && S.openTranscript) S.openTranscript({});
    for (const f of S.transcriptSinks) f(s);
  };

  // ---------- windows ----------
  S.wins = [];
  S.P = 1700;
  let nextWid = 1;
  const DEPTH_Z = [0, -34, -62, -84, -100, -112];
  const DEPTH_E = [1, .52, .38, .3, .24, .2];

  class Win {
    constructor(o) {
      this.id = 'w' + (nextWid++);
      this.kind = o.kind; this.cls = o.cls || 'Window'; this.hue = o.hue ?? 220;
      this.w = o.w; this.h = o.h; this.rot = 0; this.opts = o;
      this.busy = false; this.queued = 0; this.flipped = false; this.lastTouch = 0;
      const sp = (x, k, c, e) => new Spring(x, k, c, e);
      this.s = {
        x: sp(o.x, 220, 26, .05), y: sp(o.y, 220, 26, .05), z: sp(-180, 150, 20, .02), elev: sp(0, 160, 22, .002),
        flip: sp(0, 95, 13.5, .02), W: sp(o.w, 170, 22, .3), H: sp(o.h, 170, 22, .3), tx: sp(0, 260, 16, .01), ty: sp(0, 260, 16, .01), sc: sp(.9, 210, 21, .0005), op: sp(0, 200, 26, .002), dim: sp(0, 200, 26, .002),
      };
      this.el = h('div', { class: 'win', 'data-morph': this.cls, 'data-name': o.name || (this.kind + this.id.slice(1)), 'data-win': this.id, style: { width: o.w + 'px', height: o.h + 'px' } });
      this.el.style.setProperty('--h', this.hue);
      this.el.style.opacity = 0;
      this.shadow = h('div', { class: 'wshadow', style: { width: o.w + 'px', height: o.h + 'px' } });
      this.titleEl = h('span', { class: 'wtitle', text: o.title });
      this.pdot = h('span', { class: 'pdot', title: 'this window\'s Process' });
      this.chip = h('span', { class: 'wchip' });
      this.titlebar = h('div', { class: 'titlebar' }, this.pdot, this.titleEl, this.chip, h('span', { class: 'tb-spacer' }),
        h('button', { class: 'tbtn', 'data-tb': 'xray', title: 'X-ray: explode into layers (⌘⇧X)', html: S.ICON.layers }),
        h('button', { class: 'tbtn', 'data-tb': 'flip', title: 'Flip: show implementation (⌘⇧F)', html: S.ICON.flip }),
        h('button', { class: 'tbtn close', 'data-tb': 'close', title: 'Close', html: S.ICON.close }));
      this.body = h('div', { class: 'wbody drop-target' });
      this.veil = h('div', { class: 'veil' });
      this.front = h('div', { class: 'face front' }, this.titlebar, this.body, this.veil, h('div', { class: 'grip' }), h('div', { class: 'dim' }), h('div', { class: 'sheen' }));
      this.back = h('div', { class: 'face back' });
      this.el.append(this.front, this.back);
      this.proc = S.newProc({ name: o.title, window: this.id, kind: 'window', hue: this.hue });
      S.$('#stage').append(this.shadow, this.el);
      S.wins.push(this);
      this.el._win = this;
      if (o.build) o.build(this, this.body);
      S.focus(this);
    }
    get title() { return this.titleEl.textContent; }
    setTitle(t) { this.titleEl.textContent = t; this.proc.name = t; }
    get x() { return this.s.x.t; } get y() { return this.s.y.t; }
    moveTo(x, y, snap) { if (snap) { this.s.x.snap(x); this.s.y.snap(y); } else { this.s.x.set(x); this.s.y.set(y); } }
    resize(w, hh, animate) {
      w = Math.max(this.opts.minW || 260, w); hh = Math.max(this.opts.minH || 160, hh);
      if (animate) { this.s.W.set(w); this.s.H.set(hh); return; }
      this.s.W.snap(w); this.s.H.snap(hh); this.applySize(w, hh);
    }
    applySize(w, hh) {
      this.w = Math.round(w); this.h = Math.round(hh);
      for (const e of [this.el, this.shadow]) { e.style.width = this.w + 'px'; e.style.height = this.h + 'px'; }
      if (this.onResize) this.onResize();
    }
    setBusy(b, label) {
      this.busy = b; this.el.classList.toggle('busy', b);
      this.pdot.className = 'pdot' + (b ? ' busy' : '');
      this.proc.state = b ? 'running' : 'waiting';
      if (b) { this.queued = 0; this.setChip('busy', label || 'busy'); }
      else this.setChip(null);
    }
    setChip(kind, text, prog) {
      if (!kind) { this.chip.className = 'wchip'; return; }
      this.chip.className = 'wchip on' + (kind === 'fork' ? ' fork' : '');
      this.chip.innerHTML = (kind === 'fork' ? '⟳ ' : '') + S.esc(text) + (prog != null ? `<span class="bar"><i style="width:${Math.round(prog * 100)}%"></i></span>` : '');
    }
    close() {
      if (this.closing) return;
      this.closing = true; this.s.op.set(0); this.s.sc.set(.88); this.s.z.set(-140);
      this.proc.state = 'terminated'; this.proc.dead = performance.now();
      if (this.onClose) this.onClose();
      if (S.halo && S.halo.target && this.el.contains(S.halo.target)) S.halo.hide();
    }
    update(dt) {
      let moving = false;
      for (const k in this.s) if (this.s[k].step(dt)) moving = true;
      const s = this.s;
      if (Math.round(s.W.x) !== this.w || Math.round(s.H.x) !== this.h) this.applySize(s.W.x, s.H.x);
      const X = moving ? s.x.x.toFixed(2) : Math.round(s.x.x), Y = moving ? s.y.x.toFixed(2) : Math.round(s.y.x);
      const flip = s.flip.x, z = s.z.x, sc = s.sc.x;
      const tf = `translate3d(${X}px,${Y}px,0) perspective(${S.P}px) translateZ(${z.toFixed(2)}px) rotateX(${s.tx.x.toFixed(2)}deg) rotateY(${(s.ty.x + flip).toFixed(2)}deg) rotateZ(${this.rot.toFixed(1)}deg) scale(${sc.toFixed(4)})`;
      if (tf !== this._tf) {
        this.el.style.transform = tf; this._tf = tf;
        const e = s.elev.x, cos = Math.abs(Math.cos(flip * Math.PI / 180));
        this.shadow.style.transform = `translate3d(${X}px,${(+Y + 4 + e * 16).toFixed(2)}px,0) perspective(${S.P}px) translateZ(${z.toFixed(2)}px) rotateZ(${this.rot.toFixed(1)}deg) scale(${(sc * (0.95 + e * 0.035) * Math.max(.03, cos)).toFixed(4)}, ${(sc * (0.96 + e * 0.03)).toFixed(4)})`;
        this.shadow.style.setProperty('--e', e.toFixed(3));
        const sx = 100 - (s.ty.x * 6 + 50) + '%';
        this.front.style.setProperty('--sx', sx);
        this.front.style.setProperty('--so', S.clamp(Math.abs(s.tx.x) * .08 + Math.abs(s.ty.x) * .1, 0, .9).toFixed(3));
        const showBack = Math.abs(((flip % 360) + 360) % 360 - 180) < 90;
        if (showBack !== this._showBack) { this._showBack = showBack; this.front.style.pointerEvents = showBack ? 'none' : ''; this.back.style.pointerEvents = showBack ? '' : 'none'; }
      }
      const op = s.op.x;
      if (op !== this._op) {
        this._op = op;
        this.el.style.opacity = op > .999 ? '' : op.toFixed(3);
        this.shadow.style.opacity = op.toFixed(3);
        if (this.closing && op < .02) { this.el.remove(); this.shadow.remove(); S.wins.splice(S.wins.indexOf(this), 1); S.restack(); }
      }
      const dim = s.dim.x;
      if (dim !== this._dim) { this._dim = dim; for (const d of this.el.querySelectorAll(':scope > .face > .dim')) d.style.opacity = dim.toFixed(3); }
      this.moving = moving;
    }
  }
  S.Win = Win;
  S.openWindow = o => new Win(o);
  S.winOf = el => { const w = el && el.closest && el.closest('.win'); return w ? w._win : null; };
  S.focused = () => S.wins.filter(w => !w.closing).slice(-1)[0] || null;

  S.restack = () => {
    const live = S.wins.filter(w => !w.closing);
    S.wins.forEach((w, i) => { w.shadow.style.zIndex = 10 + i * 2; w.el.style.zIndex = 11 + i * 2; });
    if (S.exposing) return;
    live.forEach((w, i) => {
      const rank = live.length - 1 - i;
      w.el.classList.toggle('focused', rank === 0);
      if (w.dragging) return;
      w.s.z.set(DEPTH_Z[Math.min(rank, DEPTH_Z.length - 1)]);
      w.s.elev.set(DEPTH_E[Math.min(rank, DEPTH_E.length - 1)]);
      w.s.dim.set(Math.min(rank, 4) * .045);
      if (!w.closing) { w.s.sc.set(1); w.s.op.set(1); }
    });
  };
  S.focus = w => {
    if (!w || w.closing) return;
    const i = S.wins.indexOf(w);
    if (i !== S.wins.length - 1) { S.wins.splice(i, 1); S.wins.push(w); }
    S.restack();
  };
  S.touch = w => { if (w) w.lastTouch = performance.now(); };

  // ---------- window chrome interactions ----------
  let drag = null;
  document.addEventListener('pointerdown', e => {
    if (e.button !== 0 || e.altKey || e.metaKey) return;
    const winEl = e.target.closest('.win');
    if (!winEl) return;
    const w = winEl._win;
    if (S.exposing) return;
    S.focus(w); S.touch(w);
    const tb = e.target.closest('[data-tb]');
    if (tb) return;
    if (e.target.closest('.titlebar') || e.target.classList.contains('grip')) {
      e.preventDefault();
      S.beginWinDrag(w, e, e.target.classList.contains('grip'));
    }
  }, true);
  S.beginWinDrag = (w, e, grip) => {
    S.focus(w);
    drag = { w, grip, sx: e.clientX, sy: e.clientY, x0: w.x, y0: w.y, w0: w.w, h0: w.h, lx: e.clientX, ly: e.clientY, lt: performance.now(), vx: 0, vy: 0 };
    if (!grip) { w.dragging = true; w.s.elev.set(1.7); w.s.sc.set(1.012); w.s.z.set(0); }
    document.body.style.cursor = grip ? 'nwse-resize' : 'grabbing';
  };
  document.addEventListener('pointermove', e => {
    S.pointerMoved = true;
    if (!drag) return;
    const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
    if (drag.grip) { drag.w.resize(drag.w0 + dx, drag.h0 + dy); return; }
    drag.w.moveTo(drag.x0 + dx, drag.y0 + dy, true);
    const t = performance.now(), ddt = Math.max(1, t - drag.lt);
    drag.vx = drag.vx * .6 + (e.clientX - drag.lx) / ddt * 1000 * .4;
    drag.vy = drag.vy * .6 + (e.clientY - drag.ly) / ddt * 1000 * .4;
    drag.lx = e.clientX; drag.ly = e.clientY; drag.lt = t;
    drag.w.s.ty.set(S.clamp(drag.vx * .0055, -10, 10));
    drag.w.s.tx.set(S.clamp(-drag.vy * .0055, -10, 10));
  });
  const endDrag = () => {
    if (!drag) return;
    const w = drag.w; w.dragging = false; w.s.tx.set(0); w.s.ty.set(0);
    drag = null; document.body.style.cursor = '';
    S.restack();
  };
  document.addEventListener('pointerup', endDrag);
  document.addEventListener('pointercancel', endDrag);
  // decay tilt when the pointer stops while still dragging
  S.dragTick = () => {
    if (drag && !drag.grip && performance.now() - drag.lt > 60) { drag.vx *= .8; drag.vy *= .8; drag.w.s.ty.set(S.clamp(drag.vx * .0055, -10, 10)); drag.w.s.tx.set(S.clamp(-drag.vy * .0055, -10, 10)); }
  };

  document.addEventListener('click', e => {
    const tb = e.target.closest('[data-tb]');
    if (!tb || S.exposing) return;
    const w = S.winOf(tb);
    if (!w) return;
    const a = tb.dataset.tb;
    if (a === 'close') w.close();
    else if (a === 'flip') S.flip(w);
    else if (a === 'xray') S.xray.open(w);
  });

  // busy windows queue their events — the compositor still moves them
  document.addEventListener('pointerdown', e => {
    if (!e.target.classList.contains('veil') || e.altKey || e.metaKey) return;
    const w = S.winOf(e.target);
    w.queued++;
    const r = e.target.getBoundingClientRect(), s = r.width / e.target.offsetWidth;
    const x = (e.clientX - r.left) / s, y = (e.clientY - r.top) / s;
    e.target.append(h('div', { class: 'ripple', style: { left: x + 'px', top: y + 'px' } }), h('div', { class: 'qtag', text: `queued (${w.queued})`, style: { left: x + 'px', top: y + 'px' } }));
    setTimeout(() => { const k = e.target.querySelectorAll('.ripple,.qtag'); if (k.length > 6) for (let i = 0; i < k.length - 6; i++) k[i].remove(); }, 0);
    w.setChip('busy', `busy · ${w.queued} event${w.queued > 1 ? 's' : ''} queued`, w.busyProg);
  });

  // ---------- flip ----------
  S.flip = w => {
    if (!w.flipped && S.buildBack) {
      if (w.w < 640) { w.preFlip = { w: w.w, x: w.x }; const nw = 640; w.moveTo(S.clamp(w.x - (nw - w.w) / 2, 8, innerWidth - nw - 8), w.y); w.resize(nw, w.h, true); }
      S.buildBack(w);
    } else if (w.flipped && w.preFlip) { w.moveTo(w.preFlip.x, w.y); w.resize(w.preFlip.w, w.h, true); w.preFlip = null; }
    w.flipped = !w.flipped;
    w.s.flip.set(w.flipped ? 180 : 0);
    w.s.elev.set(1.6); w.s.z.set(40);
    setTimeout(() => S.restack(), 380);
    S.focus(w);
  };

  // ---------- compositor loop ----------
  S.frameTimes = new Float32Array(64); let fti = 0;
  let last = performance.now();
  S.tickers = [];
  function frame(t) {
    const dtMs = t - last; last = t;
    const dt = Math.min(.05, dtMs / 1000);
    S.frameTimes[fti++ % 64] = dtMs;
    S.FRAME++;
    S.dragTick();
    let animating = false;
    for (const w of [...S.wins]) { w.update(dt); if (w.moving) animating = true; }
    for (const f of S.tickers) { try { f(dt, t); } catch (err) { console.error(err); } }
    sampleProcs(animating);
    S.pointerMoved = false;
    requestAnimationFrame(frame);
  }
  S.start = () => requestAnimationFrame(t => { last = t; frame(t); });

  // green-thread activity sampling (what "ran" during this frame on the single OS thread)
  function sampleProcs(animating) {
    const now = performance.now();
    const busy = S.procs.filter(p => p.state === 'running' && (p.kind === 'user' || (p.kind === 'window' && S.wins.find(w => w.id === p.window && w.busy))));
    const turn = busy.length ? busy[S.FRAME % busy.length] : null;
    let any = false;
    for (const p of S.procs) {
      let a = 0;
      if (p.kind === 'system') {
        if (p.name === 'compositor (vsync)') a = animating ? .7 : .22;
        else if (p.name === 'input dispatcher') a = S.pointerMoved ? .8 : 0;
        else if (p.name === 'timer interrupt watcher') a = S.FRAME % 6 === 0 ? .5 : 0;
        else if (p.name === 'finalization') a = S.FRAME % 97 === 0 ? .6 : 0;
      } else if (p === turn) a = 1;
      else if (p.kind === 'window' && p.state !== 'terminated') {
        const w = S.wins.find(w => w.id === p.window);
        if (w && now - w.lastTouch < 140) a = .9;
        if (w) {
          const cls = w.busy ? 'pdot busy' : (now - w.lastTouch < 140 ? 'pdot run' : (p.state === 'suspended' ? 'pdot susp' : 'pdot'));
          if (w.pdot.className !== cls) w.pdot.className = cls;
        }
      }
      if (a > .3 && p.name !== 'compositor (vsync)') any = true;
      p.lane[S.FRAME % p.lane.length] = a;
      p.cpu = p.cpu * .96 + a * 4;
    }
    const idle = S.sysProc('idle');
    if (idle) { const a = any || turn ? 0 : .35; idle.lane[S.FRAME % idle.lane.length] = a; idle.cpu = idle.cpu * .96 + a * 4; }
    // forget terminated processes after a while
    for (let i = S.procs.length - 1; i >= 0; i--) if (S.procs[i].dead && now - S.procs[i].dead > 4000) S.procs.splice(i, 1);
  }

  // ---------- small UI helpers ----------
  S.toast = (msg, ms = 2200) => {
    const t = h('div', { class: 'toast', html: msg });
    document.body.append(t);
    setTimeout(() => { t.style.transition = 'opacity .3s'; t.style.opacity = 0; setTimeout(() => t.remove(), 320); }, ms);
  };
  S.closeMenus = () => S.$$('.menu, .palette').forEach(m => m.remove());
  S.menu = (x, y, items, title) => {
    S.closeMenus();
    const m = h('div', { class: 'menu' }, title ? h('div', { class: 'mh', text: title }) : null,
      items.map(it => it === '-' ? h('div', { class: 'ms' }) : h('div', { class: 'mi', onpointerdown: e => e.preventDefault(), onclick: () => { S.closeMenus(); it.run(); } }, h('span', { text: it.label }), it.key ? h('span', { class: 'k', text: it.key }) : null)));
    document.body.append(m);
    const r = m.getBoundingClientRect();
    m.style.left = Math.min(x, innerWidth - r.width - 8) + 'px';
    m.style.top = Math.min(y, innerHeight - r.height - 8) + 'px';
    return m;
  };
  document.addEventListener('pointerdown', e => { if (!e.target.closest('.menu, .palette')) S.closeMenus(); }, true);
})();
