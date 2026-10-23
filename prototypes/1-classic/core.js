// Samaltak classic prototype — core: DOM helpers, highlighter, editor, lists, menus, windows, scheduler.
'use strict';

const TOPBAR = 30;
const IS_MAC = /Mac|iPhone|iPad/.test(navigator.platform);
const MOD = IS_MAC ? '⌘' : 'Ctrl-';

function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  if (attrs) for (const [k, v] of Object.entries(attrs)) {
    if (v === false || v == null) continue;
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(e.style, v);
    else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const k of kids.flat()) if (k != null && k !== false) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
}
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const article = n => (/^[AEIOU]/.test(n) ? 'an ' : 'a ') + n;

const ICON = {
  close: '<svg viewBox="0 0 8 8"><path d="M1.5 1.5l5 5M6.5 1.5l-5 5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
  collapse: '<svg viewBox="0 0 8 8"><path d="M1.5 4h5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
  win: '<svg viewBox="0 0 12 12"><rect x="1" y="1.5" width="10" height="9" rx="1.6" fill="none" stroke="currentColor" stroke-width="1.2"/><path d="M1 4.2h10" stroke="currentColor" stroke-width="1.2"/></svg>',
  warn: '<svg viewBox="0 0 14 14"><path d="M7 1.6l5.6 10H1.4z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M7 5.6v2.8M7 10.1v.2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  pause: '<svg viewBox="0 0 14 14"><path d="M4.5 3v8M9.5 3v8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
};

// ---------------------------------------------------------------- syntax highlighting
const PSEUDO = new Set(['self', 'super', 'true', 'false', 'nil', 'thisContext']);
const BINCH = '+-*/\\<>=~@%|&?,';
function highlight(src) {
  let out = '', plain = '', i = 0;
  const n = src.length;
  const flush = () => { if (plain) { out += esc(plain); plain = ''; } };
  const emit = (cls, s) => { flush(); out += `<span class="t-${cls}">${esc(s)}</span>`; };
  const isW = c => /[A-Za-z0-9_]/.test(c || '');
  while (i < n) {
    const c = src[i];
    if (c === '"') { let j = src.indexOf('"', i + 1); j = j < 0 ? n : j + 1; emit('c', src.slice(i, j)); i = j; continue; }
    if (c === "'") {
      let j = i + 1;
      while (j < n) { if (src[j] === "'") { if (src[j + 1] === "'") { j += 2; continue; } j++; break; } j++; }
      emit('s', src.slice(i, j)); i = j; continue;
    }
    if (c === '$' && i + 1 < n) { emit('ch', src.slice(i, i + 2)); i += 2; continue; }
    if (c === '#') {
      if (src[i + 1] === '(') { emit('sym', '#('); i += 2; continue; }
      let j = i + 1; while (j < n && /[A-Za-z0-9_:]/.test(src[j])) j++;
      if (j === i + 1) while (j < n && BINCH.includes(src[j])) j++;
      emit('sym', src.slice(i, j)); i = j; continue;
    }
    if (/[0-9]/.test(c) && !isW(src[i - 1])) {
      let j = i; while (j < n && /[0-9]/.test(src[j])) j++;
      if (src[j] === 'r') { j++; while (j < n && /[0-9A-Z]/.test(src[j])) j++; }
      else if (src[j] === '.' && /[0-9]/.test(src[j + 1] || '')) { j++; while (j < n && /[0-9]/.test(src[j])) j++; }
      if (src[j] === 'e' && /[-0-9]/.test(src[j + 1] || '')) { j++; if (src[j] === '-') j++; while (j < n && /[0-9]/.test(src[j])) j++; }
      emit('n', src.slice(i, j)); i = j; continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i; while (j < n && isW(src[j])) j++;
      const w = src.slice(i, j);
      if (src[j] === ':' && src[j + 1] !== '=') { emit('k', w + ':'); i = j + 1; continue; }
      emit(PSEUDO.has(w) ? 'pv' : /^[A-Z]/.test(w) ? 'g' : 'v', w); i = j; continue;
    }
    if (c === ':' && src[i + 1] === '=') { emit('as', ':='); i += 2; continue; }
    if (c === ':' && /[A-Za-z]/.test(src[i + 1] || '')) { let j = i + 1; while (j < n && isW(src[j])) j++; emit('arg', src.slice(i, j)); i = j; continue; }
    if (c === '^') { emit('r', '^'); i++; continue; }
    if (c === '<' && /^<primitive:/.test(src.slice(i, i + 12))) { let j = src.indexOf('>', i); j = j < 0 ? n : j + 1; emit('pr', src.slice(i, j)); i = j; continue; }
    if (c === '[' || c === ']') { emit('b', c); i++; continue; }
    if (c === '|') { emit('bar', c); i++; continue; }
    plain += c; i++;
  }
  flush();
  return out;
}
function highlightMethod(src) {
  const k = src.indexOf('\n');
  if (k < 0) return `<span class="t-pat">${highlight(src)}</span>`;
  return `<span class="t-pat">${highlight(src.slice(0, k))}</span>` + highlight(src.slice(k));
}

// Replace the pseudo-variable `self` (outside strings/comments) with a workspace variable.
function bindSelf(src, v) {
  let out = '', i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === '"' || c === "'") {
      let j = src.indexOf(c, i + 1); j = j < 0 ? src.length : j + 1;
      out += src.slice(i, j); i = j; continue;
    }
    if (c === '$') { out += src.slice(i, i + 2); i += 2; continue; }
    if (src.startsWith('self', i) && !/[A-Za-z0-9_]/.test(src[i - 1] || '') && !/[A-Za-z0-9_:]/.test(src[i + 4] || '')) { out += v; i += 4; continue; }
    out += c; i++;
  }
  return out;
}

// ---------------------------------------------------------------- toast
const Toast = {
  show(msg, ms = 2200) {
    let t = document.getElementById('toast');
    if (!t) { t = h('div', { id: 'toast' }); document.body.append(t); }
    t.textContent = msg; t.classList.add('on');
    clearTimeout(this.tm); this.tm = setTimeout(() => t.classList.remove('on'), ms);
  },
};

// ---------------------------------------------------------------- menus
const Menu = {
  el: null,
  show(x, y, items, title) {
    this.hide();
    const m = h('div', { class: 'menu' });
    m.addEventListener('mousedown', e => e.preventDefault());
    m.addEventListener('pointerdown', e => e.stopPropagation());
    if (title) m.append(h('div', { class: 'menu-title' }, title));
    for (const it of items) {
      if (!it) continue;
      if (it === '-') { m.append(h('div', { class: 'menu-sep' })); continue; }
      if (it.head) { m.append(h('div', { class: 'menu-head' }, it.head)); continue; }
      m.append(h('div', {
        class: 'menu-item' + (it.disabled ? ' disabled' : ''),
        onclick: () => { this.hide(); it.fn && it.fn(); },
      }, h('span', null, it.label), it.desc ? h('span', { class: 'd' }, it.desc) : null, it.key ? h('span', { class: 'k' }, it.key) : null));
    }
    document.body.append(m);
    const r = m.getBoundingClientRect();
    m.style.left = clamp(x, 4, innerWidth - r.width - 4) + 'px';
    m.style.top = clamp(y, TOPBAR + 2, innerHeight - r.height - 4) + 'px';
    this.el = m;
  },
  hide() { if (this.el) { this.el.remove(); this.el = null; } },
};
addEventListener('pointerdown', () => Menu.hide());
addEventListener('blur', () => Menu.hide());

// ---------------------------------------------------------------- list pane
class List {
  constructor(o = {}) {
    this.o = o; this.items = []; this.sel = null;
    this.el = h('div', { class: 'list' + (o.cls ? ' ' + o.cls : ''), tabindex: '0' });
    this.el.addEventListener('mousedown', e => {
      const r = e.target.closest('.li');
      if (!r || r.classList.contains('hdr') || e.button !== 0) return;
      this.select(r.dataset.key);
    });
    this.el.addEventListener('dblclick', e => {
      const r = e.target.closest('.li');
      if (r && !r.classList.contains('hdr') && o.onDbl) o.onDbl(r.dataset.key);
    });
    this.el.addEventListener('keydown', e => {
      if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
      e.preventDefault();
      const keys = this.items.filter(i => !i.hdr).map(i => i.key);
      let k = keys.indexOf(this.sel);
      k = clamp(k + (e.key === 'ArrowDown' ? 1 : -1), 0, keys.length - 1);
      if (keys[k] != null) this.select(keys[k]);
    });
  }
  set(items, sel = null) { this.items = items; this.sel = sel; this.render(); }
  render() {
    this.el.innerHTML = this.items.map(it => it.hdr
      ? `<div class="li hdr">${it.html || esc(it.label)}</div>`
      : `<div class="li${it.key === this.sel ? ' sel' : ''}${it.cls ? ' ' + it.cls : ''}" data-key="${esc(it.key)}">${it.html || `<span class="t">${esc(it.label)}</span>`}</div>`).join('');
    const s = this.el.querySelector('.sel');
    if (s) s.scrollIntoView({ block: 'nearest' });
  }
  select(key, fire = true) {
    this.sel = key;
    this.el.querySelectorAll('.li').forEach(r => r.classList.toggle('sel', r.dataset.key === key));
    const s = this.el.querySelector('.sel'); if (s) s.scrollIntoView({ block: 'nearest' });
    if (fire && this.o.onSelect) this.o.onSelect(key);
  }
}

// ---------------------------------------------------------------- code editor (textarea over highlighted pre)
class Editor {
  constructor(o = {}) {
    this.o = o; this.win = o.win || null; this.workspace = o.workspace || 'default'; this.mark = null;
    const plain = o.highlight === false;
    this.el = h('div', { class: 'ed' + (plain ? ' plain' : '') + (o.readOnly ? ' readonly' : '') + (o.cls ? ' ' + o.cls : '') });
    this.pre = h('pre', { class: 'ed-hl', 'aria-hidden': 'true' });
    this.ta = h('textarea', { class: 'ed-ta', spellcheck: 'false', autocomplete: 'off', autocapitalize: 'off', autocorrect: 'off' });
    if (o.placeholder) this.ta.placeholder = o.placeholder;
    if (o.readOnly) this.ta.readOnly = true;
    this.el.append(this.pre, this.ta);
    this.ta.addEventListener('input', () => { this.mark = null; this.render(); o.onChange && o.onChange(this); });
    this.ta.addEventListener('scroll', () => this.sync());
    this.ta.addEventListener('keydown', e => this.key(e));
    this.ta.addEventListener('mousedown', e => { if (e.button === 2) this.savedSel = [this.ta.selectionStart, this.ta.selectionEnd]; });
    this.ta.addEventListener('contextmenu', e => this.contextMenu(e));
    new ResizeObserver(() => { this.pre.style.width = this.ta.clientWidth + 'px'; }).observe(this.ta);
    this.value = o.value || '';
  }
  get value() { return this.ta.value; }
  set value(v) { this.ta.value = v; this.mark = null; this.render(); this.ta.scrollTop = 0; this.sync(); }
  sync() { this.pre.style.transform = `translate(${-this.ta.scrollLeft}px, ${-this.ta.scrollTop}px)`; }
  render() {
    if (this.o.highlight === false) return;
    const v = this.ta.value, m = this.mark;
    const hl = this.o.method && !m ? highlightMethod : highlight;
    let html;
    if (m && m.e <= v.length) html = hl(v.slice(0, m.s)) + `<span class="mark ${m.kind}">${highlight(v.slice(m.s, m.e))}</span>` + hl(v.slice(m.e));
    else html = hl(v);
    this.pre.innerHTML = html + '\n ';
  }
  setMark(s, e, kind, ms) {
    this.mark = { s, e, kind }; this.render();
    if (ms) { const m = this.mark; setTimeout(() => { if (this.mark === m) { this.mark = null; this.render(); } }, ms); }
  }
  selectionOrLine() {
    const ta = this.ta, v = ta.value;
    let s = ta.selectionStart, e = ta.selectionEnd;
    if (s === e) {
      s = s === 0 ? 0 : v.lastIndexOf('\n', s - 1) + 1;
      const k = v.indexOf('\n', e); e = k < 0 ? v.length : k;
      ta.setSelectionRange(s, e);
    }
    return { s, e, text: v.slice(s, e) };
  }
  wordAtCaret() {
    const v = this.ta.value; let s = this.ta.selectionStart, e = this.ta.selectionEnd;
    if (s !== e) return v.slice(s, e).trim();
    while (s > 0 && /[A-Za-z0-9_:]/.test(v[s - 1])) s--;
    while (e < v.length && /[A-Za-z0-9_:]/.test(v[e])) e++;
    return v.slice(s, e);
  }
  insertAfter(pos, text, kind) {
    const ta = this.ta;
    ta.focus(); ta.setSelectionRange(pos, pos);
    if (ta.readOnly || !document.execCommand('insertText', false, text)) ta.setRangeText(text, pos, pos, 'end');
    const lead = text.length - text.trimStart().length;
    ta.setSelectionRange(pos + lead, pos + text.length);
    this.setMark(pos + lead, pos + text.length, kind);
  }
  focus() { this.ta.focus(); }
  key(e) {
    const mod = IS_MAC ? e.metaKey : e.ctrlKey;
    if (mod && !e.altKey) {
      const act = { d: 'do', p: 'print', i: 'inspect', b: 'browse', s: 'accept' }[e.key.toLowerCase()];
      if (act) { e.preventDefault(); e.stopPropagation(); this.action(act); return; }
    }
    if (e.key === 'Tab' && !mod && !e.shiftKey && !this.ta.readOnly) { e.preventDefault(); document.execCommand('insertText', false, '\t'); }
    if (this.win && this.win.proc) Sched.poke(this.win.proc);
  }
  action(act) {
    if (act === 'accept') { if (this.o.onAccept) this.o.onAccept(this); else Toast.show('Nothing to accept here — workspaces evaluate, browsers compile.'); return; }
    Eval.run(this, act);
  }
  contextMenu(e) {
    e.preventDefault();
    if (this.savedSel) { this.ta.setSelectionRange(...this.savedSel); this.savedSel = null; }
    this.ta.focus();
    Menu.show(e.clientX, e.clientY, [
      { label: 'do it', key: MOD + 'D', fn: () => this.action('do') },
      { label: 'print it', key: MOD + 'P', fn: () => this.action('print') },
      { label: 'inspect it', key: MOD + 'I', fn: () => this.action('inspect') },
      { label: 'browse it', key: MOD + 'B', fn: () => this.action('browse') },
      '-',
      { label: 'accept', key: MOD + 'S', fn: () => this.action('accept'), disabled: !this.o.onAccept },
      { label: 'select all', key: MOD + 'A', fn: () => this.ta.select() },
    ]);
  }
}

// ---------------------------------------------------------------- splitter
function vSplitter(topEl, min = 60) {
  const s = h('div', { class: 'vsplit' });
  s.addEventListener('pointerdown', e => {
    e.preventDefault(); s.setPointerCapture(e.pointerId);
    const y0 = e.clientY, h0 = topEl.getBoundingClientRect().height;
    const parentH = topEl.parentElement.getBoundingClientRect().height;
    const mv = ev => { topEl.style.height = clamp(h0 + ev.clientY - y0, min, parentH - 70) + 'px'; };
    s.addEventListener('pointermove', mv);
    s.addEventListener('pointerup', () => s.removeEventListener('pointermove', mv), { once: true });
  });
  return s;
}

// ---------------------------------------------------------------- scheduler (simulated green threads)
const Sched = {
  procs: [], pid: 1200, frameTimes: [], listeners: new Set(),
  add(p) {
    p.pid = (this.pid += 7 + Math.floor(Math.random() * 40));
    p.used = 0; p.cpu = 0; p.flash = 0; p.started = performance.now();
    this.procs.push(p); return p;
  },
  remove(p) { this.procs = this.procs.filter(q => q !== p); },
  byName(n) { return this.procs.find(p => p.name === n); },
  poke(p, ms = 160) { if (!p) return; p.flash = performance.now() + ms; p.used += 0.25; },
  displayState(p) {
    if (p.state === 'suspended' || p.state === 'terminated') return p.state;
    if (p.step) return p.ranLast ? 'running' : 'ready';
    if (p.flash > performance.now()) return 'running';
    return p.state;
  },
  runnable() { return this.procs.filter(p => p.step && p.state !== 'suspended' && p.state !== 'terminated'); },
  slice() {
    const t0 = performance.now();
    const rs = this.runnable().sort((a, b) => b.priority - a.priority || (a.lastRun || 0) - (b.lastRun || 0));
    this.procs.forEach(p => { p.ranLast = false; });
    for (const p of rs) {
      if (performance.now() - t0 > 9) break;
      const ts = performance.now();
      let r;
      try { r = p.step(); } catch (err) { p.ranLast = true; p.state = 'suspended'; if (p.onError) p.onError(err); continue; }
      p.used += performance.now() - ts + 0.6;
      if (this.onRan) this.onRan(p, performance.now() - ts + 0.6); // profiler: sample this time slice
      p.ranLast = true; p.lastRun = ts;
      if (r === 'done') this.finish(p);
    }
    WM.syncBusy();
  },
  finish(p) {
    const done = p.onDone; p.step = null; p.onDone = null;
    if (p.kind === 'user') { p.state = 'terminated'; setTimeout(() => this.remove(p), 1400); }
    else p.state = 'waiting';
    if (done) done();
  },
  terminate(p) {
    if (p.kind === 'system') return false;
    if (p.kind === 'window') { const w = WM.wins.get(p.win); if (w) w.close(); return true; }
    p.step = null; p.state = 'terminated'; p.onAbandon && p.onAbandon();
    setTimeout(() => this.remove(p), 1400);
    return true;
  },
  start() {
    let last = performance.now(), acc = 0, accT = performance.now();
    const frame = now => {
      const dt = now - last; last = now;
      this.frameTimes.push(dt); if (this.frameTimes.length > 64) this.frameTimes.shift();
      requestAnimationFrame(frame);
      setTimeout(() => this.slice(), 0);
      const comp = this.byName('compositor (vsync)'); if (comp) comp.used += 0.35 + (WM.dragging ? 0.6 : 0);
      if (now - accT > 500) {
        const el = now - accT; accT = now;
        // A runnable green thread takes every cycle the higher-priority ones leave it.
        let sum = 0; const busy = this.runnable();
        for (const p of this.procs) { p.cpu = Math.min(100, p.used / el * 100); p.used = 0; if (!busy.includes(p) && p.name !== 'idle') sum += p.cpu; }
        busy.forEach(p => { p.cpu = (100 - sum) * (0.96 + Math.random() * 0.02) / busy.length; sum += p.cpu; });
        const idle = this.byName('idle'); if (idle) idle.cpu = Math.max(0, 100 - sum);
      }
      this.listeners.forEach(f => f(dt));
    };
    requestAnimationFrame(frame);
  },
};

// ---------------------------------------------------------------- window manager
const WM = {
  wins: new Map(), z: 10, active: null, n: 0, dragging: false,
  desktop: null,
  create(o) {
    const id = 'w' + (++this.n);
    const root = h('div', { class: 'win ' + (o.cls || ''), 'data-kind': o.kind || '' });
    const chip = h('span', { class: 'tb-proc' }, h('i', { class: 'dot' }), h('span', { class: 'lbl' }, 'busy'));
    const titleEl = h('div', { class: 'title' }, o.title);
    const closeB = h('button', { class: 'tb-box tb-close', title: 'Close', html: ICON.close });
    const collB = h('button', { class: 'tb-box tb-coll', title: 'Collapse', html: ICON.collapse });
    const tb = h('div', { class: 'titlebar' }, closeB, h('div', { class: 'stripes' }), titleEl, h('div', { class: 'stripes' }), chip, collB);
    const body = h('div', { class: 'win-body' });
    root.append(tb, h('div', { class: 'busybar' }), body,
      h('div', { class: 'rz rz-r', 'data-rz': 'r' }), h('div', { class: 'rz rz-b', 'data-rz': 'b' }),
      h('div', { class: 'rz rz-l', 'data-rz': 'l' }), h('div', { class: 'rz rz-br', 'data-rz': 'br' }));
    const win = {
      id, root, body, kind: o.kind, x: o.x, y: o.y, w: o.w, h: o.h, minW: o.minW || 220, minH: o.minH || 120,
      onClose: o.onClose, onResize: o.onResize, busy: false, susp: false, children: new Set(),
      setTitle(t) { titleEl.textContent = t; win.title = t; },
      close: () => this.close(win),
      focus: () => this.focus(win),
      apply() { root.style.transform = `translate3d(${win.x}px, ${win.y}px, 0)`; root.style.width = win.w + 'px'; root.style.height = win.h + 'px'; },
    };
    win.title = o.title;
    win.apply();
    if (o.proc !== false) {
      win.proc = Sched.add({ name: o.procName || o.title, priority: o.priority || 40, state: 'waiting', kind: 'window', win: id, frames: o.frames });
    }
    chip.title = win.proc ? `Process '${win.proc.name}' · priority ${win.proc.priority} — click to show in Process Browser` : '';
    chip.addEventListener('pointerdown', e => e.stopPropagation());
    chip.addEventListener('click', () => { if (win.proc && window.Tools) Tools.openProcessBrowser({ select: win.proc.pid }); });
    closeB.addEventListener('pointerdown', e => e.stopPropagation());
    collB.addEventListener('pointerdown', e => e.stopPropagation());
    closeB.addEventListener('click', () => win.close());
    collB.addEventListener('click', () => root.classList.toggle('collapsed'));
    tb.addEventListener('dblclick', e => { if (!e.target.closest('button')) root.classList.toggle('collapsed'); });
    root.addEventListener('pointerdown', () => { this.focus(win); Sched.poke(Sched.byName('input dispatcher'), 80); }, true);
    this.dragOn(win, tb);
    root.querySelectorAll('.rz').forEach(r => this.resizeOn(win, r));
    this.desktop.append(root);
    this.wins.set(id, win);
    this.focus(win);
    return win;
  },
  focus(win) {
    if (this.active === win) return;
    if (this.active) this.active.root.classList.remove('active');
    this.active = win;
    if (win) { win.root.classList.add('active'); win.root.style.zIndex = ++this.z; }
  },
  close(win) {
    if (!this.wins.has(win.id)) return;
    this.wins.delete(win.id);
    if (win.proc) Sched.remove(win.proc);
    win.onClose && win.onClose();
    win.root.classList.add('closing');
    setTimeout(() => win.root.remove(), 130);
    if (this.active === win) { this.active = null; const top = [...this.wins.values()].sort((a, b) => b.root.style.zIndex - a.root.style.zIndex)[0]; if (top) this.focus(top); }
  },
  dragOn(win, handle) {
    handle.addEventListener('pointerdown', e => {
      if (e.button !== 0 || e.target.closest('button, .tb-proc')) return;
      e.preventDefault();
      handle.setPointerCapture(e.pointerId);
      const dx = e.clientX - win.x, dy = e.clientY - win.y;
      let raf = 0; this.dragging = true;
      win.root.classList.add('dragging');
      const mv = ev => {
        win.x = clamp(ev.clientX - dx, 60 - win.w, innerWidth - 60);
        win.y = clamp(ev.clientY - dy, TOPBAR, innerHeight - 26);
        if (!raf) raf = requestAnimationFrame(() => { raf = 0; win.root.style.transform = `translate3d(${win.x}px, ${win.y}px, 0)`; });
        Sched.poke(Sched.byName('input dispatcher'), 60);
      };
      handle.addEventListener('pointermove', mv);
      handle.addEventListener('pointerup', () => {
        handle.removeEventListener('pointermove', mv); this.dragging = false; win.root.classList.remove('dragging');
      }, { once: true });
    });
  },
  resizeOn(win, r) {
    r.addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      e.preventDefault(); e.stopPropagation(); r.setPointerCapture(e.pointerId);
      const mode = r.dataset.rz, x0 = e.clientX, y0 = e.clientY, w0 = win.w, h0 = win.h, X0 = win.x;
      let raf = 0;
      const mv = ev => {
        const ddx = ev.clientX - x0, ddy = ev.clientY - y0;
        if (mode === 'r' || mode === 'br') win.w = Math.max(win.minW, w0 + ddx);
        if (mode === 'b' || mode === 'br') win.h = Math.max(win.minH, h0 + ddy);
        if (mode === 'l') { const w = Math.max(win.minW, w0 - ddx); win.x = X0 + (w0 - w); win.w = w; }
        if (!raf) raf = requestAnimationFrame(() => { raf = 0; win.apply(); win.onResize && win.onResize(); });
      };
      r.addEventListener('pointermove', mv);
      r.addEventListener('pointerup', () => r.removeEventListener('pointermove', mv), { once: true });
    });
  },
  syncBusy() {
    for (const w of this.wins.values()) {
      const p = w.proc;
      const kids = [...w.children].filter(c => c.step && c.state !== 'terminated');
      const own = p && p.step && p.state !== 'suspended';
      const kidRun = kids.some(c => c.state !== 'suspended');
      const busy = !!(own || kidRun);
      const susp = !busy && ((p && p.state === 'suspended') || kids.some(c => c.state === 'suspended'));
      const label = own ? (w.busyLabel || 'busy') : kidRun ? kids.find(c => c.state !== 'suspended').name : 'suspended';
      if (busy !== w.busy || susp !== w.susp || label !== w.lastLabel) {
        w.busy = busy; w.susp = susp; w.lastLabel = label;
        w.root.classList.toggle('busy', busy); w.root.classList.toggle('suspended', susp);
        w.root.querySelector('.tb-proc .lbl').textContent = label;
        w.onBusy && w.onBusy(busy, kids);
      }
      w.root.querySelector('.tb-proc').classList.toggle('input', !!(p && p.flash > performance.now()));
    }
  },
  nextPos(w, h) {
    const n = this.wins.size % 8;
    return { x: clamp(120 + n * 28, 8, innerWidth - w - 8), y: clamp(70 + n * 26, TOPBAR + 8, innerHeight - h - 8) };
  },
  near(win, w, h, dx = 40, dy = 40) {
    if (!win) return this.nextPos(w, h);
    return { x: clamp(win.x + dx, 8, innerWidth - w - 8), y: clamp(win.y + dy, TOPBAR + 8, innerHeight - h - 8) };
  },
};
