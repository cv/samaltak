// Card types living on the canvas. Every card owns a (simulated) green-thread Process.
(function (S) {
  'use strict';
  const fmt = n => Number(n).toLocaleString('en-US');
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const escH = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  S.h = h; S.escH = escH; S.fmt = fmt;
  let nextId = 1, zTop = 10;

  S.selectorOf = key => {
    const kws = key.match(/[A-Za-z_]\w*:/g);
    if (kws) return kws.join('');
    const bin = /^[+\-*/\\<>=~@%&?,|]+/.exec(key);
    return bin ? bin[0] : key.trim();
  };

  class Card {
    constructor(o) {
      this.id = 'c' + (nextId++);
      this.x = o.x || 0; this.y = o.y || 0; this.w = o.w || 320; this.h = 120;
      this.kind = o.kind; this.accent = o.accent || '#d9c7a3';
      this.title = o.title || '';
      this.queue = [];
      this.busyProc = null;
      const el = this.el = h('div', 'card card-' + o.kind);
      el.style.setProperty('--acc', this.accent);
      el.dataset.id = this.id;
      el.innerHTML = `<div class="card-head"><span class="badge"></span><span class="card-title"></span><span class="card-sub"></span>` +
        `<span class="proc"><i class="pdot"></i><b></b></span><button class="close" title="Close card">×</button></div>` +
        `<div class="card-body"></div><div class="card-summary"><span class="sum-badge"></span><div class="sum-title"></div><div class="sum-sub"></div></div>`;
      this.head = el.querySelector('.card-head');
      this.body = el.querySelector('.card-body');
      el.querySelector('.badge').textContent = o.badge || '';
      el.querySelector('.sum-badge').textContent = o.badge || '';
      this.setTitle(this.title, o.sub || '');
      this.proc = S.sched.spawn({ name: o.procName || this.title, cardId: this.id, priority: o.priority ?? 40 });
      el.querySelector('.close').addEventListener('click', e => { e.stopPropagation(); this.close(); });
      el.querySelector('.close').addEventListener('pointerdown', e => e.stopPropagation());
      el.addEventListener('pointerdown', e => {
        this.focus();
        if (e.button !== 0) return;
        const onHead = e.target.closest('.card-head') && !e.target.closest('button');
        if (S.mode !== 'detail' || onHead) S.beginCardDrag(this, e);
      });
      this.head.addEventListener('dblclick', e => { e.stopPropagation(); S.zoomToCard(this); });
      this.head.addEventListener('contextmenu', e => {
        e.preventDefault(); e.stopPropagation();
        S.menu(e.clientX, e.clientY, [
          { label: 'Zoom to card', key: 'dbl-click', action: () => S.zoomToCard(this) },
          { label: 'Inspect this card', action: () => S.inspectCard(this) },
          { sep: true },
          { label: 'Close', action: () => this.close() },
        ]);
      });
      this.updateProc();
    }
    mount() {
      S.world.appendChild(this.el);
      this.place();
      this.h = this.el.offsetHeight;
      S.cards.set(this.id, this);
      S.ro.observe(this.el);
      S.dirty();
      return this;
    }
    place() {
      this.el.style.left = this.x + 'px';
      this.el.style.top = this.y + 'px';
      this.el.style.width = this.w + 'px';
    }
    moveTo(x, y, animate) {
      if (animate) { this.el.classList.add('glide'); clearTimeout(this._gt); this._gt = setTimeout(() => this.el.classList.remove('glide'), 450); }
      this.x = x; this.y = y; this.place(); S.dirty();
    }
    rect() { return { x: this.x, y: this.y, w: this.w, h: this.h }; }
    setTitle(t, sub) {
      this.title = t;
      this.el.querySelector('.card-title').textContent = t;
      if (sub != null) this.el.querySelector('.card-sub').textContent = sub;
      this.refreshSummary();
    }
    summary() { return { title: this.title, sub: this.el.querySelector('.card-sub').textContent }; }
    refreshSummary() {
      const s = this.summary();
      this.el.querySelector('.sum-title').textContent = s.title;
      this.el.querySelector('.sum-sub').textContent = s.sub || '';
    }
    focus() {
      if (S.focused === this) return;
      if (S.focused) S.focused.el.classList.remove('focused');
      S.focused = this;
      this.el.classList.add('focused');
      this.el.style.zIndex = ++zTop;
    }
    updateProc() {
      const p = this.proc;
      if (!p) return;
      const dot = this.el.querySelector('.pdot');
      const st = p.busy ? (p.state === 'suspended' ? 'suspended' : 'busy') : p.state;
      dot.className = 'pdot ' + st;
      this.el.querySelector('.proc b').textContent = 'p' + p.pid;
      this.el.querySelector('.proc').title = `Process ${p.pid} '${p.name}' · priority ${p.priority} · ${p.busy && p.state !== 'suspended' ? 'running (busy)' : p.state}`;
    }
    setBusy(proc) {
      this.busyProc = proc;
      this.el.classList.toggle('busy', !!proc);
      if (this.ed) this.ed.setReadOnly(!!proc);
      if (proc) {
        if (!this.strip) { this.strip = h('div', 'busy-strip'); this.el.appendChild(this.strip); }
        this.updateBusy();
      } else {
        if (this.strip) { this.strip.remove(); this.strip = null; }
        if (this.queue.length && this.ed) {
          const txt = this.queue.join('');
          this.queue = [];
          this.ed.ta.focus({ preventScroll: true });
          const len = this.ed.ta.value.length;
          this.ed.ta.setSelectionRange(len, len);
          document.execCommand('insertText', false, txt);
          S.toast(`Delivered ${txt.length} queued event${txt.length === 1 ? '' : 's'} to ${this.proc.name}`);
        }
      }
      S.dirty();
    }
    queueEvent(ch) { this.queue.push(ch); this.updateBusy(); }
    updateBusy() {
      const p = this.busyProc;
      if (!p || !this.strip) return;
      const w = p.work;
      const sus = p.state === 'suspended';
      this.el.classList.toggle('suspended', sus);
      this.strip.innerHTML = `<i class="pdot ${sus ? 'suspended' : 'busy'}"></i><span><b>${sus ? 'Suspended' : 'Busy'}</b> — this card's Process p${p.pid} is ${sus ? 'in the debugger' : 'computing'}` +
        (w ? ` · ${(w.progress * 100).toFixed(0)}%` : '') + `</span>` +
        (this.queue.length ? `<span class="q">${this.queue.length} event${this.queue.length === 1 ? '' : 's'} queued</span>` : '') +
        `<kbd>⌘.</kbd>`;
    }
    close() {
      S.removeCard(this);
    }
  }

  // ---------------------------------------------------------------- Snippet
  class SnippetCard extends Card {
    constructor(o) {
      super({ ...o, kind: 'snippet', badge: 'do', title: o.title || 'Playground', sub: o.sub ?? 'workspace', accent: '#dcc69b', procName: o.title || 'Playground' });
      this.ed = new S.Editor({ text: o.text || '', owner: this, onAction: (k, r, ed) => S.evaluate(this, ed, k, r), onChange: () => this.refreshSummary() });
      this.body.appendChild(this.ed.el);
      const bar = h('div', 'toolbar');
      const btn = (label, key, fn, cls) => {
        const b = h('button', 'btn' + (cls ? ' ' + cls : ''), `${label}${key ? `<kbd>${key}</kbd>` : ''}`);
        b.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); });
        b.addEventListener('click', fn);
        bar.appendChild(b);
        return b;
      };
      btn('Do it', '⌘D', () => this.ed.act('do'));
      btn('Print it', '⌘P', () => this.ed.act('print'));
      btn('Inspect it', '⌘I', () => this.ed.act('inspect'));
      bar.appendChild(h('span', 'grow'));
      btn('Run long computation', null, () => this.runLong(), 'run');
      this.body.appendChild(bar);
    }
    runLong() {
      const t = this.ed.text;
      const m = /^.*count:\s*\[:\w+\s*\|\s*\w+\s+isPrime\].*$/m.exec(t.split('\n').filter(l => !/forkNamed:|fork\b/.test(l)).join('\n'));
      if (m) {
        const s = t.indexOf(m[0]);
        S.evaluate(this, this.ed, 'print', { s, e: s + m[0].length, src: m[0] });
      } else {
        const line = '(1 to: 12000000) count: [:i | i isPrime]';
        this.ed.ta.focus({ preventScroll: true });
        this.ed.ta.setSelectionRange(t.length, t.length);
        document.execCommand('insertText', false, (t.endsWith('\n') ? '' : '\n') + line);
        const s = this.ed.text.length - line.length;
        S.evaluate(this, this.ed, 'print', { s, e: s + line.length, src: line });
      }
    }
    summary() {
      const n = this.ed ? this.ed.text.split('\n').filter(l => /^[^" ]/.test(l)).length : 0;
      return { title: this.title, sub: `workspace · ${n} expressions` };
    }
  }

  // ---------------------------------------------------------------- Object (inspector)
  const isNumArr = v => Array.isArray(v) && v.length > 0 && v.length <= 60 && v.every(x => typeof x === 'bigint' || typeof x === 'number');
  function selfSrcFor(res, src) {
    try { if (MiniST.evaluate(res.printString).printString === res.printString) return res.printString; } catch (e) { /* not re-parsable */ }
    return src || null;
  }

  class ObjectCard extends Card {
    constructor(o) {
      const res = o.res;
      super({ ...o, kind: 'object', badge: 'obj', title: res.className, sub: '', accent: '#86c5b6', procName: 'Inspector on ' + res.className, w: o.w || 270 });
      this.res = res;
      this.src = o.src;
      this.refreshSummary();
      this.selfSrc = selfSrcFor(res, o.src);
      const ps = h('div', 'obj-print');
      ps.textContent = res.printString;
      ps.title = res.printString;
      this.body.appendChild(ps);
      const cls = h('div', 'obj-class');
      const known = S.classCardFor(res.className);
      cls.innerHTML = `<span>an instance of</span> <a class="${known ? 'live' : ''}">${escH(res.className)}</a>`;
      if (known) cls.querySelector('a').addEventListener('click', e => { e.stopPropagation(); S.linkToClass(this, known, cls); });
      this.body.appendChild(cls);
      this.views = this.buildViews();
      this.tabs = h('div', 'tabs');
      this.view = h('div', 'view');
      this.views.forEach((v, i) => {
        const t = h('button', 'tab', v.name);
        t.addEventListener('pointerdown', e => e.stopPropagation());
        t.addEventListener('click', () => this.show(i));
        this.tabs.appendChild(t);
      });
      this.body.appendChild(this.tabs);
      this.body.appendChild(this.view);
      this.ed = new S.Editor({
        text: '', owner: this, placeholder: 'self …   evaluate here with ⌘P / ⌘I',
        onAction: (k, r, ed) => S.evaluate(this, ed, k, r, { selfSrc: this.selfSrc }),
      });
      const evalBox = h('div', 'obj-eval');
      evalBox.appendChild(this.ed.el);
      this.body.appendChild(evalBox);
      const def = this.views.findIndex(v => v.name === o.view);
      this.show(def >= 0 ? def : (this.views[2] && this.views[2].preferred ? 2 : 0));
    }
    summary() { return { title: this.res ? this.res.printString.slice(0, 48) : this.title, sub: this.res ? this.res.className : '' }; }
    show(i) {
      this.viewIndex = i;
      [...this.tabs.children].forEach((t, j) => t.classList.toggle('on', i === j));
      this.view.innerHTML = '';
      this.view.appendChild(this.views[i].render());
    }
    buildViews() {
      const v = this.res.value, cn = this.res.className;
      const views = [{ name: 'Raw', render: () => this.rawView() }, { name: 'Print', render: () => { const p = h('pre', 'printview'); p.textContent = this.res.printString; return p; } }];
      if (isNumArr(v)) views.push({ name: 'Bars', render: () => barsView(v) });
      if (cn === 'Point' && typeof v.x !== 'undefined') views.push({ name: 'Plot', preferred: true, render: () => plotView(v) });
      if (cn === 'Fraction') views.push({ name: 'Pie', preferred: true, render: () => pieView(v) });
      if (typeof v === 'bigint' && this.res.printString.length > 12) views.push({ name: 'Digits', preferred: true, render: () => digitsView(this.res.printString) });
      if (typeof v === 'bigint' && this.res.printString.length <= 12 && v >= 0n) views.push({ name: 'Bits', render: () => bitsView(v) });
      return views;
    }
    rawView() {
      const box = h('div', 'rows');
      MiniST.inspect(this.res.value).filter(r => r.name !== 'self').forEach(r => {
        const row = h('div', 'row', `<span class="k">${escH(r.name)}</span><span class="v">${escH(r.value)}</span><span class="go">›</span>`);
        row.addEventListener('pointerdown', e => e.stopPropagation());
        row.addEventListener('click', () => S.inspectField(this, r, row));
        box.appendChild(row);
      });
      return box;
    }
  }

  function barsView(arr) {
    const nums = arr.map(Number), max = Math.max(...nums.map(Math.abs), 1);
    const W = 260, H = 96, bw = W / nums.length;
    let s = `<svg class="viz" viewBox="0 0 ${W} ${H + 16}" width="100%">`;
    nums.forEach((n, i) => {
      const bh = Math.max(2, Math.abs(n) / max * H);
      s += `<rect x="${(i * bw + bw * 0.14).toFixed(1)}" y="${(H - bh).toFixed(1)}" width="${(bw * 0.72).toFixed(1)}" height="${bh.toFixed(1)}" rx="2" />`;
      if (nums.length <= 20) s += `<text x="${(i * bw + bw / 2).toFixed(1)}" y="${H + 12}">${n}</text>`;
    });
    return h('div', 'vizbox', s + '</svg>');
  }
  function plotView(p) {
    const x = Number(p.x), y = Number(p.y), m = Math.max(Math.abs(x), Math.abs(y), 1) * 1.3;
    const W = 260, H = 150, cx = W / 2, cy = H / 2, k = Math.min(W, H) / 2 / m;
    let s = `<svg class="viz plot" viewBox="0 0 ${W} ${H}" width="100%">`;
    for (let i = -4; i <= 4; i++) { s += `<line class="g" x1="${cx + i * W / 9}" y1="0" x2="${cx + i * W / 9}" y2="${H}"/><line class="g" x1="0" y1="${cy + i * H / 9}" x2="${W}" y2="${cy + i * H / 9}"/>`; }
    s += `<line class="ax" x1="0" y1="${cy}" x2="${W}" y2="${cy}"/><line class="ax" x1="${cx}" y1="0" x2="${cx}" y2="${H}"/>`;
    const px = cx + x * k, py = cy - y * k;
    s += `<line class="vec" x1="${cx}" y1="${cy}" x2="${px}" y2="${py}"/><circle cx="${px}" cy="${py}" r="5"/><text x="${px + 9}" y="${py - 7}">${escH(MiniST.printString(p))}</text></svg>`;
    return h('div', 'vizbox', s);
  }
  function pieView(f) {
    const n = Number(f.n), d = Number(f.d), v = n / d;
    const whole = Math.min(3, Math.floor(Math.abs(v))), part = Math.abs(v) - Math.floor(Math.abs(v));
    let s = `<svg class="viz pie" viewBox="0 0 260 96" width="100%">`;
    let x = 44;
    const arc = (cx, frac) => {
      if (frac >= 0.999) return `<circle cx="${cx}" cy="46" r="34" class="full"/>`;
      const a = frac * Math.PI * 2, ex = cx + 34 * Math.sin(a), ey = 46 - 34 * Math.cos(a);
      return `<circle cx="${cx}" cy="46" r="34" class="bgc"/><path d="M${cx} 46 L${cx} 12 A34 34 0 ${frac > 0.5 ? 1 : 0} 1 ${ex.toFixed(2)} ${ey.toFixed(2)} Z"/>`;
    };
    for (let i = 0; i < whole; i++) { s += arc(x, 1); x += 80; }
    if (part > 0.0001 || whole === 0) s += arc(x, part);
    s += `</svg><div class="vizcap">${n}/${d} ≈ ${v.toFixed(4)}</div>`;
    return h('div', 'vizbox', s);
  }
  function digitsView(str) {
    const neg = str.startsWith('-'), d = str.replace('-', '');
    const groups = [];
    for (let i = d.length; i > 0; i -= 3) groups.unshift(d.slice(Math.max(0, i - 3), i));
    return h('div', 'vizbox', `<div class="digits">${neg ? '−' : ''}${groups.map(g => `<span>${g}</span>`).join('')}</div><div class="vizcap">${d.length} digits · LargePositiveInteger lives on the heap</div>`);
  }
  function bitsView(v) {
    const bits = v.toString(2).padStart(16, '0').split('');
    return h('div', 'vizbox', `<div class="bits">${bits.map(b => `<i class="${b === '1' ? 'on' : ''}"></i>`).join('')}</div><div class="vizcap">tagged immediate · ${v.toString(2).length} significant bits</div>`);
  }

  // ---------------------------------------------------------------- Class
  class ClassCard extends Card {
    constructor(o) {
      const c = o.cls;
      super({ ...o, kind: 'class', badge: 'C', title: c.name, sub: o.pkgName, accent: o.accent, procName: 'Browser: ' + c.name, w: o.w || 300 });
      this.cls = c; this.pkgName = o.pkgName; this.layer = o.layer;
      const def = h('pre', 'static code-static');
      def.innerHTML = S.highlight(`${c.superclass} subclass: #${c.name}\n\tinstanceVariableNames: '${c.ivars.join(' ')}'`, false);
      this.body.appendChild(def);
      this.body.appendChild(h('p', 'cls-comment', escH(c.comment)));
      const protos = h('div', 'protos');
      const entries = Object.entries(c.protocols);
      if (!entries.length) protos.appendChild(h('div', 'proto empty', '<span class="pname">no methods yet</span>'));
      this.chips = new Map();
      for (const [pname, methods] of entries) {
        const row = h('div', 'proto', `<span class="pname">${escH(pname)}</span>`);
        for (const key of Object.keys(methods)) {
          const chip = h('button', 'sel', escH(S.selectorOf(key)));
          chip.title = key;
          chip.addEventListener('pointerdown', e => e.stopPropagation());
          chip.addEventListener('click', () => S.openMethod(this, pname, key));
          this.chips.set(key, chip);
          row.appendChild(chip);
        }
        protos.appendChild(row);
      }
      this.body.appendChild(protos);
      this.methodCount = entries.reduce((n, [, m]) => n + Object.keys(m).length, 0);
      this.refreshSummary();
    }
    summary() { return { title: this.title, sub: `${this.cls ? this.cls.superclass + ' subclass' : ''} · ${this.methodCount || 0} methods` }; }
  }

  // ---------------------------------------------------------------- Method
  class MethodCard extends Card {
    constructor(o) {
      const sel = S.selectorOf(o.key);
      super({ ...o, kind: 'method', badge: 'm', title: `${o.cls.name}>>${sel}`, sub: o.proto, accent: o.accent, procName: `Editor ${o.cls.name}>>${sel}` });
      this.cls = o.cls; this.key = o.key; this.proto = o.proto; this.saved = o.source;
      this.ed = new S.Editor({
        text: o.source, method: true, owner: this,
        onAction: (k, r, ed) => S.evaluate(this, ed, k, r),
        onAccept: () => this.accept(),
        onChange: () => this.status(),
      });
      this.body.appendChild(this.ed.el);
      this.foot = h('div', 'mfoot');
      this.body.appendChild(this.foot);
      this.status();
    }
    status(flash) {
      const dirty = this.ed.text !== this.saved;
      this.el.classList.toggle('dirty', dirty);
      this.foot.innerHTML = dirty
        ? `<i class="dirtydot"></i><span>modified</span><span class="grow"></span><kbd>⌘S</kbd><span>accept</span>`
        : `<span class="ok">${flash ? '✓ accepted · compiled into ' + escH(this.cls.name) : 'saved'}</span><span class="grow"></span><span class="dim">${escH(this.proto)}</span>`;
    }
    accept() {
      if (this.ed.text === this.saved) { S.toast('No changes to accept'); return; }
      this.saved = this.ed.text;
      const firstLine = this.saved.split('\n')[0];
      this.status(true);
      this.el.classList.remove('accepted'); void this.el.offsetWidth; this.el.classList.add('accepted');
      S.transcript(`${this.cls.name}>>${S.selectorOf(firstLine)} accepted\n`);
      S.sched.blip(this.proc);
    }
    summary() { return { title: S.selectorOf(this.key || ''), sub: this.cls ? this.cls.name + ' · ' + this.proto : '' }; }
  }

  // ---------------------------------------------------------------- Forked process
  class ProcessCard extends Card {
    constructor(o) {
      super({ ...o, kind: 'process', badge: '⟳', title: o.name, sub: 'forked Process', accent: '#e8a84c', procName: o.name, w: o.w || 300 });
      this.fproc = this.proc;
      const src = h('pre', 'static code-static oneline');
      src.innerHTML = S.highlight(o.src.trim(), false);
      this.body.appendChild(src);
      this.live = h('div', 'pc-live');
      this.body.appendChild(this.live);
      const bar = h('div', 'toolbar');
      const mk = (label, key, fn) => {
        const b = h('button', 'btn', label + (key ? `<kbd>${key}</kbd>` : ''));
        b.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); });
        b.addEventListener('click', fn); bar.appendChild(b); return b;
      };
      this.bInt = mk('Interrupt', '⌘.', () => S.interrupt(this.fproc));
      this.bTerm = mk('Terminate', null, () => S.terminate(this.fproc));
      this.body.appendChild(bar);
      this.update();
    }
    update() {
      const p = this.fproc, w = p.work;
      const state = p.busy ? (p.state === 'suspended' ? 'suspended' : 'running') : (this.finished ? 'finished' : 'terminated');
      this.el.classList.toggle('busy', p.busy && p.state !== 'suspended');
      this.el.classList.toggle('suspended', p.state === 'suspended');
      const prog = w ? w.progress : 1;
      const res = this.finished != null ? this.finished : null;
      this.live.innerHTML =
        `<div class="pbar ${state}"><i style="width:${(prog * 100).toFixed(1)}%"></i></div>` +
        `<div class="pstats"><span><em>${state}</em></span><span>${(prog * 100).toFixed(1)}%</span></div>` +
        (w && w.N > 1 ? `<div class="pgrid"><span>i</span><b>${fmt(w.i)}</b><span>of</span><b>${fmt(w.N)}</b><span>primes</span><b>${fmt(w.count)}</b><span>slices</span><b>${fmt(p.slices)}</b></div>` : '') +
        (res != null ? `<div class="pgrid"><span>result</span><b class="res">${escH(res)}</b><span>time</span><b>${this.secs.toFixed(1)} s</b></div>` : '') +
        `<div class="pmeta">priority ${p.priority} · preempted at safepoints · ${p.slices ? (p.cpu / p.slices).toFixed(1) : '0.0'} ms/slice</div>`;
      this.bInt.disabled = !p.busy || p.state === 'suspended';
      this.bTerm.disabled = !p.busy;
      this.setTitle(this.title, 'forked · ' + state);
    }
    summary() { const p = this.fproc; return { title: this.title, sub: p ? (p.busy ? `${p.state} · ${((p.work ? p.work.progress : 1) * 100).toFixed(0)}%` : 'done') : '' }; }
  }

  // ---------------------------------------------------------------- Transcript
  class TranscriptCard extends Card {
    constructor(o) {
      super({ ...o, kind: 'transcript', badge: '≡', title: 'Transcript', sub: 'TranscriptStream', accent: '#b9ae98', procName: 'Transcript' });
      this.text = o.text || '';
      this.pre = h('pre', 'transcript');
      this.body.appendChild(this.pre);
      const bar = h('div', 'toolbar slim');
      const clr = h('button', 'btn', 'Clear');
      clr.addEventListener('pointerdown', e => e.stopPropagation());
      clr.addEventListener('click', () => { this.text = ''; this.render(); });
      bar.appendChild(h('span', 'grow dim', 'Transcript show: … appears here'));
      bar.appendChild(clr);
      this.body.appendChild(bar);
      this.render();
    }
    write(s) { this.text += s; this.render(); S.sched.blip(this.proc); }
    render() {
      const lines = this.text.split('\n');
      const shown = lines.slice(-11).join('\n');
      this.pre.innerHTML = escH(shown) + '<span class="caret"></span>';
      this.refreshSummary();
    }
    summary() { const l = (this.text || '').trim().split('\n').pop(); return { title: 'Transcript', sub: l || 'empty' }; }
  }

  // ---------------------------------------------------------------- Processes
  class ProcessesCard extends Card {
    constructor(o) {
      super({ ...o, kind: 'processes', badge: '≋', title: 'Processes', sub: '1 OS thread', accent: '#a7bd84', procName: 'ProcessBrowser', priority: 40 });
      this.list = h('div', 'plist');
      this.body.appendChild(this.list);
      this.body.appendChild(h('div', 'pfoot', 'Every card is a Window with its own Process. Click a row to fly to it.'));
      this.render();
    }
    render() {
      const rank = p => (p.busy ? 2 : 0) + (p.kind === 'system' ? 1 : 0);
      const procs = [...S.sched.procs].filter(p => p.state !== 'terminated' || p.kind === 'fork').sort((a, b) => rank(b) - rank(a) || b.priority - a.priority || a.pid - b.pid);
      const rows = procs.slice(0, 9).map(p => {
        const st = p.busy ? (p.state === 'suspended' ? 'suspended' : 'busy') : p.state;
        const label = p.busy && p.state !== 'suspended' ? 'running' : p.state;
        return `<div class="prow ${p.cardId ? 'link' : ''} ${st}" data-card="${p.cardId || ''}"><i class="pdot ${st}"></i><span class="pid">${p.pid}</span><span class="pn">${escH(p.name)}</span><span class="pp">${p.priority}</span><span class="ps">${label}</span></div>`;
      }).join('');
      const html = `<div class="prow hd"><i></i><span class="pid">pid</span><span class="pn">name</span><span class="pp">pri</span><span class="ps">state</span></div>` + rows +
        (procs.length > 9 ? `<div class="prow more">+ ${procs.length - 9} more — one per card</div>` : '');
      if (html !== this._last) {
        this._last = html;
        this.list.innerHTML = html;
        this.list.querySelectorAll('.prow.link').forEach(r => {
          r.addEventListener('pointerdown', e => e.stopPropagation());
          r.addEventListener('click', () => { const c = S.cards.get(r.dataset.card); if (c) S.zoomToCard(c, { pulse: true }); });
        });
      }
      const n = procs.filter(p => p.busy && p.state !== 'suspended').length;
      this.setTitle('Processes', `${procs.length} green threads · ${n} busy`);
    }
    summary() { return { title: 'Processes', sub: `${S.sched.procs.length} green threads` }; }
  }

  // ---------------------------------------------------------------- Note
  class NoteCard extends Card {
    constructor(o) {
      super({ ...o, kind: 'note', badge: '¶', title: o.title || 'Note', sub: '', accent: '#d9b98a', procName: 'Note', w: o.w || 300 });
      this.ed = new S.Editor({ text: o.text, prose: true, owner: this, onAction: (k, r, ed) => S.evaluate(this, ed, k, r), onChange: () => this.refreshSummary() });
      this.body.appendChild(this.ed.el);
    }
    mount() { super.mount(); this.ed.refresh(); this.h = this.el.offsetHeight; return this; }
    summary() { return { title: this.title, sub: this.ed ? this.ed.text.split('\n')[0].slice(0, 60) : '' }; }
  }

  // ---------------------------------------------------------------- Debugger
  const FAKE = {
    count: `count: aBlock
	"Evaluate aBlock with each of the receiver's elements as the argument.
	 Answer the number of elements that answered true."

	| count |
	count := 0.
	self do: [:each | (aBlock value: each) ifTrue: [count := count + 1]].
	^count`,
    do: `do: aBlock
	| i |
	i := start.
	[i <= stop] whileTrue: [
		aBlock value: i.
		i := i + step]`,
  };
  class DebuggerCard extends Card {
    constructor(o) {
      const p = o.proc;
      super({ ...o, kind: 'debugger', badge: '!', title: 'User Interrupt', sub: `${p.name} · p${p.pid}`, accent: '#e2725f', procName: 'Debugger', w: 560, priority: 45 });
      this.target = p;
      this.ownerCard = o.ownerCard;
      this.stack = h('div', 'stack');
      this.body.appendChild(this.stack);
      this.srcBox = h('div', 'dbg-src');
      this.body.appendChild(this.srcBox);
      this.vars = h('div', 'dbg-vars');
      this.body.appendChild(this.vars);
      const bar = h('div', 'toolbar');
      const mk = (label, fn, cls) => {
        const b = h('button', 'btn' + (cls ? ' ' + cls : ''), label);
        b.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); });
        b.addEventListener('click', fn); bar.appendChild(b); return b;
      };
      mk('Proceed', () => this.proceed(), 'primary');
      mk('Over', () => { this.target.work && this.target.work.stepOne(); this.render(); });
      mk('Restart', () => { this.target.work && this.target.work.restart(); this.sel = 0; this.render(); S.toast('Restarted computation from i = 1'); });
      bar.appendChild(h('span', 'grow'));
      mk('Terminate', () => { S.terminate(this.target); this.close(); }, 'danger');
      this.body.appendChild(bar);
      this.sel = 0;
      this.render();
    }
    frames() {
      const w = this.target.work || { i: 0, count: 0, divisor: () => 0, src: '' };
      const n = w.i, isPrimeSrc = FakeImage.findClass('Integer').protocols.testing.isPrime;
      const fromFork = this.target.kind === 'fork';
      const doit = (w.src || '').trim();
      const frames = [
        { label: 'SmallInteger(Integer)>>isPrime', src: isPrimeSrc, method: true, pc: 2, vars: [['self', fmt(n)], ['i', String(w.divisor())]] },
        { label: '[] in UndefinedObject>>DoIt', src: doit, method: false, pc: 0, vars: [['i', fmt(n)]] },
        { label: 'Interval>>count:', src: FAKE.count, method: true, pc: 6, vars: [['self', `(1 to: ${fmt(w.N || 0)})`], ['count', fmt(w.count)]] },
        { label: 'Interval>>do:', src: FAKE.do, method: true, pc: 4, vars: [['self', `(1 to: ${fmt(w.N || 0)})`], ['i', fmt(n)]] },
      ];
      if (fromFork) frames.push({ label: '[] in BlockClosure>>newProcess', src: FakeImage.findClass('BlockClosure').protocols.scheduling.newProcess, method: true, pc: 4, vars: [["self", "a BlockClosure"]] });
      else frames.push({ label: 'UndefinedObject>>DoIt', src: doit, method: false, pc: 0, vars: [['self', 'nil']] });
      return frames;
    }
    render() {
      const fr = this.frames();
      this.stack.innerHTML = fr.map((f, i) => `<div class="frame ${i === this.sel ? 'on' : ''}" data-i="${i}"><span class="fi">${i}</span>${escH(f.label)}</div>`).join('');
      this.stack.querySelectorAll('.frame').forEach(e => {
        e.addEventListener('pointerdown', ev => ev.stopPropagation());
        e.addEventListener('click', () => { this.sel = +e.dataset.i; this.render(); });
      });
      const f = fr[this.sel];
      if (!this.ed || this.ed.opts.method !== f.method || this.edSrc !== f.src) {
        this.srcBox.innerHTML = '';
        this.ed = new S.Editor({ text: f.src, method: f.method, owner: this, onAction: (k, r, ed) => S.evaluate(this, ed, k, r), onAccept: () => S.toast('Accepted (prototype): method recompiled, frame restarted') });
        this.edSrc = f.src;
        this.srcBox.appendChild(this.ed.el);
      }
      this.ed.markLine(f.pc);
      this.vars.innerHTML = f.vars.map(([k, v]) => `<div class="var"><span class="k">${escH(k)}</span><span class="v">${escH(v)}</span></div>`).join('') +
        `<div class="var note"><span>Process p${this.target.pid} '${escH(this.target.name)}' is suspended. Every other card keeps running.</span></div>`;
    }
    proceed() {
      S.sched.resume(this.target);
      if (this.ownerCard && this.ownerCard.busyProc) this.ownerCard.updateBusy();
      this.close();
    }
    summary() { return { title: 'Debugger', sub: this.target ? `User Interrupt · ${this.target.name}` : '' }; }
  }

  Object.assign(S, { Card, SnippetCard, ObjectCard, ClassCard, MethodCard, ProcessCard, TranscriptCard, ProcessesCard, NoteCard, DebuggerCard });
})(window.Sam = window.Sam || {});
