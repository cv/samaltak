// Samaltak — Direction 3: Acme-style tiling. All text is executable.
(() => {
'use strict';

const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
const K = isMac ? '⌘' : 'Ctrl-';
const OPT = isMac ? '⌥' : 'Alt-';
const TAG_H = 22;
const now = () => performance.now();
const h = (tag, cls, parent, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; if (parent) parent.appendChild(e); return e; };
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const trunc = (s, n = 80) => (s = String(s)).length > n ? s.slice(0, n - 1) + '…' : s;
const oneLine = s => String(s).replace(/\s+/g, ' ').trim();
const fmt = n => Number(n).toLocaleString('en-US');
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const sum = a => a.reduce((s, x) => s + x, 0);
const colsEl = document.getElementById('cols');
const fx = document.getElementById('fx');

// ======================================================================
// Image model (read-only view over FakeImage + accepted edits)
// ======================================================================
const Img = (() => {
  const overrides = new Map();
  const selectorOf = key => {
    key = key.trim();
    if (/^[A-Za-z_]/.test(key)) { const kws = key.match(/[A-Za-z_]\w*:/g); return kws ? kws.join('') : key.split(/\s+/)[0]; }
    return key.split(/\s+/)[0];
  };
  const all = [];
  for (const p of FakeImage.packages) for (const c of p.classes) for (const [proto, ms] of Object.entries(c.protocols || {}))
    for (const [key, src] of Object.entries(ms)) {
      const sel = selectorOf(key);
      all.push({ cls: c.name, pkg: p.name, layer: p.layer, proto, key, sel, ref: `${c.name}>>${sel}`, original: src });
    }
  const classes = FakeImage.allClasses();
  const classNames = new Set(classes.map(c => c.name));
  const pkgNames = new Set(FakeImage.packages.map(p => p.name));
  const EXTRA = { ProtoObject: null, Number: 'Magnitude', Magnitude: 'Object', Link: 'Object', LinkedList: 'SequenceableCollection', SequenceableCollection: 'Collection', Collection: 'Object' };
  const source = m => overrides.has(m.ref) ? overrides.get(m.ref) : m.original;
  const strip = s => s.replace(/"[^"]*"/g, ' ').replace(/'(?:[^']|'')*'/g, ' ');
  const bodyOf = m => strip(source(m).split('\n').slice(1).join('\n'));
  const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const superOf = n => { const c = FakeImage.findClass(n); return c ? c.superclass : (n in EXTRA ? EXTRA[n] : 'Object'); };
  return {
    all, classes, classNames, pkgNames, selectorOf, source, superOf,
    cls: n => FakeImage.findClass(n),
    pkg: n => FakeImage.packages.find(p => p.name === n) || null,
    methodsOf: c => all.filter(m => m.cls === c),
    implementorsOf: s => all.filter(m => m.sel === s),
    sendersOf(sel) {
      let res;
      if (/^[A-Za-z_]/.test(sel)) {
        const parts = sel.includes(':') ? sel.match(/[A-Za-z_]\w*:/g) : [sel];
        res = parts.map(p => new RegExp('(?<![\\w#:])' + reEsc(p) + (p.endsWith(':') ? '' : '(?![\\w:])')));
      } else res = [new RegExp('[\\s\\w)\\]]' + reEsc(sel) + '\\s')];
      return all.filter(m => res.every(r => r.test(bodyOf(m))));
    },
    referencesTo: cn => all.filter(m => new RegExp('\\b' + cn + '\\b').test(bodyOf(m))),
    subclassesOf: n => classes.filter(c => c.superclass === n).map(c => c.name),
    lookupMethod(cn, sel) {
      for (let n = cn, guard = 0; n && guard < 20; n = superOf(n), guard++) { const m = all.find(x => x.cls === n && x.sel === sel); if (m) return m; }
      return null;
    },
    accept: (m, src) => overrides.set(m.ref, src),
    isAccepted: m => overrides.has(m.ref),
  };
})();

// ======================================================================
// Highlighters (colour only: the mirror must keep the textarea's metrics)
// ======================================================================
const CMD = {};
const PSEUDO = new Set(['self', 'super', 'thisContext', 'nil', 'true', 'false']);
const span = (c, s) => c ? `<span class="${c}">${esc(s)}</span>` : esc(s);
const RX = {
  ident: /[A-Za-z_]\w*:?/y,
  num: /\d+(?:r[0-9A-Z]+|\.\d+(?:e-?\d+)?|e-?\d+)?/y,
  sym: /#(?:\(|[A-Za-z_][\w:]*|[-+*\/\\<>=~@%|&?,]+)/y,
  prim: /<primitive:[^>]*>/y,
  ref: /(?:\[\] in )?[A-Z]\w*(?:\([A-Z]\w*\))?(?: class)?>>[^\s\])}.,;]+/y,
  word: /[A-Za-z_+][\w\-]*:?/y,
  lnum: /#?\d[\d,.]*%?/y,
};
const at = (re, t, i) => { re.lastIndex = i; const m = re.exec(t); return m ? m[0] : null; };
function scanQuote(t, i, q) { let j = i + 1; while (j < t.length) { if (t[j] === q) { if (q === "'" && t[j + 1] === "'") { j += 2; continue; } return j + 1; } j++; } return t.length; }

function hlSource(t, header) {
  let out = '', i = 0; const n = t.length;
  if (header) { const j = t.indexOf('\n'); const hd = j < 0 ? t : t.slice(0, j); out += span('s-head', hd); i = hd.length; }
  while (i < n) {
    const c = t[i]; let m;
    if (c === '"') { const j = scanQuote(t, i, '"'); out += span('s-com', t.slice(i, j)); i = j; continue; }
    if (c === "'") { const j = scanQuote(t, i, "'"); out += span('s-str', t.slice(i, j)); i = j; continue; }
    if (c === '$' && i + 1 < n) { out += span('s-str', t.slice(i, i + 2)); i += 2; continue; }
    if (c === '#' && (m = at(RX.sym, t, i))) { out += span('s-sym', m); i += m.length; continue; }
    if (/[A-Za-z_]/.test(c) && (m = at(RX.ident, t, i))) {
      if (m.endsWith(':') && t[i + m.length] === '=') m = m.slice(0, -1);
      out += span(m.endsWith(':') ? 's-kw' : PSEUDO.has(m) ? 's-pseudo' : /^[A-Z]/.test(m) ? 's-cls' : null, m); i += m.length; continue;
    }
    if (/\d/.test(c) && (m = at(RX.num, t, i))) { out += span('s-num', m); i += m.length; continue; }
    if (c === ':' && t[i + 1] === '=') { out += span('s-op', ':='); i += 2; continue; }
    if (c === ':' && /[A-Za-z_]/.test(t[i + 1] || '')) { const w = ':' + at(RX.ident, t, i + 1).replace(/:$/, ''); out += span('s-arg', w); i += w.length; continue; }
    if (c === '^') { out += span('s-op', c); i++; continue; }
    if (c === '<' && (m = at(RX.prim, t, i))) { out += span('s-prim', m); i += m.length; continue; }
    if (c === '[' || c === ']' || c === '|') { out += span('s-br', c); i++; continue; }
    out += esc(c); i++;
  }
  return out;
}

const STATES = { running: 's-run', suspended: 's-susp', debugging: 's-susp', terminated: 's-com' };
function hlListing(t, opts = {}) {
  let out = '', i = 0; const n = t.length; let bol = true;
  while (i < n) {
    const c = t[i]; let m;
    if (bol && opts.heads !== false) {
      bol = false; const j = t.indexOf('\n', i); const line = t.slice(i, j < 0 ? n : j);
      if (/^[a-z][a-zA-Z \-]*$/.test(line)) { out += span('s-head', line); i += line.length; continue; }
    }
    if (c === '\n') { out += c; i++; bol = true; continue; }
    if (c === '"') { const j = scanQuote(t, i, '"'); out += span('s-com', t.slice(i, j)); i = j; continue; }
    if (c === "'") { const j = scanQuote(t, i, "'"); out += span('s-str', t.slice(i, j)); i = j; continue; }
    if ((c === '[' || /[A-Z]/.test(c)) && (m = at(RX.ref, t, i))) { out += span('s-ref', m); i += m.length; continue; }
    if (/[A-Za-z_+]/.test(c) && (m = at(RX.word, t, i))) {
      const cls = Img.classNames.has(m) ? 's-cls' : Img.pkgNames.has(m) ? 's-pkg' : CMD[m] && /^[A-Z+]/.test(m) && !panes.some(p => p.name === m) ? 's-cmd' : (opts.states && STATES[m]) || null;
      out += span(cls, m); i += m.length; continue;
    }
    if (/[#\d]/.test(c) && (m = at(RX.lnum, t, i)) && m !== '#') { out += span('s-num', m); i += m.length; continue; }
    if ('█░━─↓│⇒›'.includes(c)) { let j = i; while (j < n && t[j] === c) j++; out += span(c === '⇒' || c === '›' ? 's-op' : c === '█' ? 's-bar' : 's-rule', t.slice(i, j)); i = j; continue; }
    if ('◐◓◑◒●'.includes(c)) { out += span('s-run', c); i++; continue; }
    if (c === '‖') { out += span('s-susp', c); i++; continue; }
    out += esc(c); i++;
  }
  return out;
}

function hlTag(t, dirty, named) {
  let out = '', i = 0;
  if (named) { const m = /^\s*\S+/.exec(t); if (m) { out += span('t-name', m[0]); i = m[0].length; } }
  const re = /\s+|\S+/g; re.lastIndex = i; let m;
  while ((m = re.exec(t))) {
    const w = m[0];
    out += /^\s/.test(w) ? w : span(w === '|' ? 't-bar' : dirty && (w === 'Accept' || w === 'Put') ? 't-dirty' : CMD[w] ? 't-cmd' : 't-arg', w);
  }
  return out;
}

// ======================================================================
// TextView: a transparent <textarea> over a highlighted mirror <div>
// ======================================================================
class TextView {
  constructor(parent, owner, kind, opts = {}) {
    this.owner = owner; this.kind = kind;
    this.wrap = h('div', `tv tv-${kind}`, parent);
    this.hl = h('div', 'tv-hl', this.wrap);
    const ta = this.ta = h('textarea', 'tv-ta', this.wrap);
    ta.spellcheck = false;
    for (const a of ['autocomplete', 'autocorrect', 'autocapitalize']) ta.setAttribute(a, 'off');
    if (kind !== 'body') { ta.rows = 1; ta.wrap = 'off'; }
    this.highlight = opts.highlight || esc;
    this.onEdit = opts.onEdit || null;
    ta.addEventListener('input', () => { this.render(); if (this.onEdit) this.onEdit(this); });
    ta.addEventListener('scroll', () => this.sync());
    ta.addEventListener('mousedown', e => Mouse.down(e, this));
    ta.addEventListener('contextmenu', e => e.preventDefault());
    ta.addEventListener('auxclick', e => e.preventDefault());
    ta.addEventListener('focus', () => { if (this.owner.pane) setFocused(this.owner.pane); });
    ta.addEventListener('keydown', e => onTextKey(e, this));
    ta.addEventListener('mousemove', e => Hover.move(e, this));
    ta.addEventListener('mouseleave', () => Hover.clear());
  }
  get value() { return this.ta.value; }
  setText(t, keepSel = true) {
    const ta = this.ta; if (t === ta.value) return;
    const s = ta.selectionStart, e = ta.selectionEnd, st = ta.scrollTop;
    ta.value = t;
    if (keepSel) { ta.setSelectionRange(Math.min(s, t.length), Math.min(e, t.length)); ta.scrollTop = st; }
    else { ta.setSelectionRange(0, 0); ta.scrollTop = 0; }
    this.render();
  }
  render() { const t = this.ta.value; this.hl.innerHTML = this.highlight(t) + (t.endsWith('\n') || !t ? ' ' : ''); this.sync(); }
  sync() { this.hl.scrollTop = this.ta.scrollTop; this.hl.scrollLeft = this.ta.scrollLeft; if (this.onScroll) this.onScroll(); }
  offsetAt(x, y) {
    const ta = this.ta, hl = this.hl; let node = null, off = 0;
    ta.style.pointerEvents = 'none'; hl.style.pointerEvents = 'auto';
    try {
      if (document.caretPositionFromPoint) { const p = document.caretPositionFromPoint(x, y); if (p) { node = p.offsetNode; off = p.offset; } }
      else if (document.caretRangeFromPoint) { const r = document.caretRangeFromPoint(x, y); if (r) { node = r.startContainer; off = r.startOffset; } }
    } finally { ta.style.pointerEvents = ''; hl.style.pointerEvents = ''; }
    if (!node || !hl.contains(node)) return null;
    const r = document.createRange(); r.setStart(hl, 0); r.setEnd(node, off);
    return Math.min(r.toString().length, this.value.length);
  }
  nodeAt(off) {
    const w = document.createTreeWalker(this.hl, NodeFilter.SHOW_TEXT); let n, acc = 0, last = null;
    while ((n = w.nextNode())) { if (acc + n.length >= off) return [n, off - acc]; acc += n.length; last = n; }
    return last ? [last, last.length] : [this.hl, 0];
  }
  rects(a, b) {
    if (a === b) return [];
    const r = document.createRange(); const [n1, o1] = this.nodeAt(a), [n2, o2] = this.nodeAt(b);
    try { r.setStart(n1, o1); r.setEnd(n2, o2); } catch { return []; }
    const box = this.wrap.getBoundingClientRect();
    return [...r.getClientRects()].filter(q => q.width > 0.5 && q.bottom > box.top && q.top < box.bottom)
      .map(q => ({ left: Math.max(q.left, box.left), right: Math.min(q.right, box.right), top: Math.max(q.top, box.top), bottom: Math.min(q.bottom, box.bottom) }));
  }
  lineBounds(off) { const t = this.value; const s = t.lastIndexOf('\n', off - 1) + 1; let e = t.indexOf('\n', off); if (e < 0) e = t.length; return [s, e]; }
  wordRange(off) {
    const t = this.value; const [ls, le] = this.lineBounds(off); const line = t.slice(ls, le);
    const re = /(?:\[\] in )?[A-Z]\w*(?:\([A-Z]\w*\))?(?: class)?>>[^\s\])}.,;]+/g; let m;
    while ((m = re.exec(line))) { const a = ls + m.index, b = a + m[0].length; if (off >= a && off <= b) return [a, b]; }
    const isW = c => /[\w:+\-]/.test(c);
    let a = off, b = off; while (a > ls && isW(t[a - 1])) a--; while (b < le && isW(t[b])) b++;
    while (a < b && /[-:]/.test(t[a])) a++; while (b > a && t[b - 1] === '-') b--;
    return a === b ? null : [a, b];
  }
  scrollTo(off) {
    const ta = this.ta; const [n, o] = this.nodeAt(off); const r = document.createRange();
    try { r.setStart(n, o); r.setEnd(n, Math.min(o + 1, n.length || 0)); } catch { return; }
    const q = r.getBoundingClientRect(), box = this.wrap.getBoundingClientRect();
    const y = q.top - box.top + ta.scrollTop;
    if (y < ta.scrollTop + 4 || y > ta.scrollTop + ta.clientHeight - 40) ta.scrollTop = Math.max(0, y - ta.clientHeight / 3);
    this.sync();
  }
  select(a, b, focus = true) { if (focus) this.ta.focus({ preventScroll: true }); this.ta.setSelectionRange(a, b); this.scrollTo(a); }
  insertAt(pos, text, selectInserted) {
    const ta = this.ta; ta.focus({ preventScroll: true }); ta.setSelectionRange(pos, pos);
    if (!document.execCommand('insertText', false, text)) { ta.setRangeText(text, pos, pos, 'end'); this.render(); if (this.onEdit) this.onEdit(this); }
    if (selectInserted) ta.setSelectionRange(selectInserted[0], selectInserted[1]);
  }
}
const trimRange = (t, a, b) => { while (a < b && /\s/.test(t[a])) a++; while (b > a && /\s/.test(t[b - 1])) b--; return [a, b]; };

// ======================================================================
// Effects: flashes, sweeps, hover underline
// ======================================================================
function drawRects(rects, cls) {
  return rects.map(q => { const d = h('div', cls, fx); Object.assign(d.style, { left: q.left + 'px', top: q.top + 'px', width: (q.right - q.left) + 'px', height: (q.bottom - q.top) + 'px' }); return d; });
}
function flashRange(tv, a, b, kind) {
  const ds = drawRects(tv.rects(a, b), 'fl fl-' + kind);
  setTimeout(() => ds.forEach(d => (d.style.opacity = '0')), kind === 'err' ? 700 : 260);
  setTimeout(() => ds.forEach(d => d.remove()), kind === 'err' ? 1300 : 800);
}
const Hover = {
  els: [], pending: null, raf: 0, key: '',
  move(e, tv) {
    if (e.buttons || Mouse.sweep) return this.clear();
    this.pending = { x: e.clientX, y: e.clientY, tv, alt: e.altKey, look: e.metaKey || e.ctrlKey };
    if (!this.raf) this.raf = requestAnimationFrame(() => { this.raf = 0; this.update(); });
  },
  update() {
    const p = this.pending; if (!p) return;
    const off = p.tv.offsetAt(p.x, p.y); const r = off == null ? null : p.tv.wordRange(off);
    let cls = null;
    if (r) {
      const w = p.tv.value.slice(r[0], r[1]);
      if (p.alt) cls = 'hu-exec'; else if (p.look) cls = 'hu-look';
      else if (CMD[w] && (p.tv.kind !== 'body' || !(p.tv.owner.pane && p.tv.owner.pane.spec.code))) cls = 'hu-exec';
      else if (p.tv.kind === 'body' && (w.includes('>>') || Img.classNames.has(w) || Img.pkgNames.has(w))) cls = 'hu-link';
    }
    const key = cls ? `${cls}:${r[0]}:${r[1]}:${p.tv.ta.scrollTop}` : '';
    if (key === this.key) return;
    this.clear(); this.key = key;
    if (!cls) return;
    this.els = drawRects(p.tv.rects(r[0], r[1]).map(q => ({ ...q, top: q.bottom - 2, bottom: q.bottom - 1 })), 'hu ' + cls);
  },
  clear() { this.els.forEach(d => d.remove()); this.els = []; this.key = ''; },
};

// ======================================================================
// Mouse: middle / Alt = execute, right / Cmd = look; sweeps with drag
// ======================================================================
const Mouse = {
  sweep: null,
  down(e, tv) {
    const exec = e.button === 1 || (e.button === 0 && e.altKey);
    const look = e.button === 2 || (e.button === 0 && (e.metaKey || e.ctrlKey));
    if (!exec && !look) return;
    e.preventDefault(); Hover.clear();
    const start = tv.offsetAt(e.clientX, e.clientY); if (start == null) return;
    const kind = exec ? 'exec' : 'look';
    const sw = this.sweep = { tv, kind, start, end: start, els: [] };
    const move = ev => {
      const o = tv.offsetAt(ev.clientX, ev.clientY); if (o == null || o === sw.end) return;
      sw.end = o; sw.els.forEach(d => d.remove());
      sw.els = drawRects(tv.rects(Math.min(sw.start, o), Math.max(sw.start, o)), 'fl sw-' + kind);
    };
    const up = ev => {
      document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up, true);
      ev.preventDefault(); sw.els.forEach(d => d.remove()); this.sweep = null;
      let a = Math.min(sw.start, sw.end), b = Math.max(sw.start, sw.end), expanded = false;
      if (a === b) {
        const s = tv.ta.selectionStart, se = tv.ta.selectionEnd;
        if (s !== se && a >= s && a <= se) { a = s; b = se; }
        else { const r = tv.wordRange(a); if (!r) return; [a, b] = r; expanded = true; }
      }
      dispatch(kind, tv, a, b, expanded);
    };
    document.addEventListener('mousemove', move); document.addEventListener('mouseup', up, true);
  },
};
document.addEventListener('contextmenu', e => { if (e.target.closest('.tv, .tag, .coltag, #row')) e.preventDefault(); });

function makeCtx(tv, a, b, expanded) {
  const [ls, le] = tv.lineBounds(a);
  const pane = tv.owner.pane || null;
  return { scope: tv.owner.scope, pane, col: tv.owner.col || (pane && pane.col) || null, tv, range: [a, b], line: tv.value.slice(ls, le), lineRange: [ls, le], expanded };
}
function dispatch(kind, tv, a, b, expanded) {
  const ctx = makeCtx(tv, a, b, expanded);
  const text = tv.value.slice(a, b);
  if (kind === 'look') { flashRange(tv, a, b, 'look'); look(text, ctx); }
  else execute(text, ctx);
}
function execute(text, ctx) {
  const t = text.trim(); if (!t) return;
  const words = t.split(/\s+/); const cmd = CMD[words[0]];
  const inBody = ctx.tv && ctx.tv.kind === 'body';
  const isCode = inBody && ctx.pane && ctx.pane.spec.code;
  if (isCode && ctx.expanded) {
    const line = ctx.line.trim();
    if (!line.split(/\s+/).every(w => CMD[w])) {
      const [a, b] = trimRange(ctx.tv.value, ...ctx.lineRange);
      flashRange(ctx.tv, a, b, 'exec');
      return evalToTranscript(ctx.tv.value.slice(a, b), ctx);
    }
  }
  if (cmd && (words.length === 1 || cmd.arg)) {
    if (ctx.tv) flashRange(ctx.tv, ctx.range[0], ctx.range[1], 'exec');
    return cmd.fn({ ...ctx, arg: words.slice(1).join(' ') });
  }
  if (isCode || (inBody && !ctx.expanded && /\s/.test(t))) {
    if (ctx.tv) flashRange(ctx.tv, ctx.range[0], ctx.range[1], 'exec');
    return evalToTranscript(t, ctx);
  }
  if (ctx.tv) flashRange(ctx.tv, ctx.range[0], ctx.range[1], 'look');
  look(t, ctx);
}

// ======================================================================
// Evaluation
// ======================================================================
let evalCtx = null;
function stEval(src, pane, extra = {}) {
  const prev = evalCtx;
  evalCtx = { pane, ws: (pane && pane.wsId) || 'global', src, forks: [], ...extra };
  const me = evalCtx;
  if (pane) pane.proc.touch();
  try {
    const r = MiniST.evaluate(src, { workspace: me.ws, transcript: transcriptOut, forked: (b, n) => me.forks.push(forkBlock(b, n, me)) });
    r.forks = me.forks; return r;
  } finally { evalCtx = prev; }
}
const errMsg = err => (err && err.message) || String(err);
function resultNote(res) {
  if (res.forks && res.forks.length) { const p = res.forks[res.forks.length - 1]; return `forked Process '${p.name}' #${p.id}`; }
  return '⇒ ' + trunc(res.printString, 70);
}
function evalSel(tv, mode) {
  const ta = tv.ta; let s = ta.selectionStart, e = ta.selectionEnd;
  if (s === e) [s, e] = trimRange(ta.value, ...tv.lineBounds(s));
  const src = ta.value.slice(s, e); const pane = tv.owner.pane || null;
  if (!src.trim()) return;
  let res;
  try { res = stEval(src, pane); } catch (err) { flashRange(tv, s, e, 'err'); return reportError(pane, src, err); }
  if (mode === 'print') {
    const ins = ' ' + res.printString;
    tv.insertAt(e, ins, [e + 1, e + ins.length]);
  } else if (mode === 'inspect') {
    flashRange(tv, s, e, 'look'); openInspector(res.value, oneLine(src), pane);
  } else { flashRange(tv, s, e, 'exec'); note(pane, resultNote(res), 'ok'); }
}
function evalToTranscript(src, ctx) {
  let res;
  try { res = stEval(src, ctx.pane); } catch (err) { if (ctx.tv) flashRange(ctx.tv, ...ctx.range, 'err'); return reportError(ctx.pane, src, err); }
  note(ctx.pane, resultNote(res), 'ok');
  if (res.className !== 'TranscriptStream' && !(res.forks && res.forks.length)) transcriptOut(`${trunc(oneLine(src), 48)} ⇒ ${trunc(res.printString, 600)}\n`);
}
function reportError(pane, src, err) {
  const msg = errMsg(err);
  const ep = openPane('errors', '+Errors', { text: '' }, { pane }, 'tool', { index: 'end', frac: 0.26, focus: false });
  appendText(ep, `${pane ? pane.name : 'command'} · ${trunc(oneLine(src), 64)}\n\t${msg}\n`);
  ep.flash('err');
  if (pane) { pane.note(msg, 'err'); pane.flash('err'); } else rowNote(msg, true);
}
function transcriptOut(s) {
  let p = panes.find(x => x.kind === 'transcript');
  if (!p) p = openPane('transcript', 'Transcript', { text: '' }, null, 'tool', { index: 'end', frac: 0.25, focus: false });
  appendText(p, s); p.proc.touch();
}
function appendText(p, s) {
  const ta = p.body.ta; const atEnd = ta.scrollTop + ta.clientHeight >= ta.scrollHeight - 6;
  p.body.setText(ta.value + s, true);
  if (atEnd) { ta.scrollTop = ta.scrollHeight; p.body.sync(); }
}
function wsRoot(ws) {
  let root = null;
  MiniST.evaluate('[] fork', { workspace: ws, forked: b => { let e = b.env; while (e.parent) e = e.parent; root = e; } });
  return root;
}

// ======================================================================
// Processes: green threads simulated with time slices
// ======================================================================
const Procs = {
  list: [], seq: 0,
  add(p) {
    p.id = ++this.seq; p.cpu = 0; p.slices = 0;
    p.touch = () => { if (p.state === 'waiting' || p.state === 'running') { p.state = 'running'; p.until = now() + 180; } };
    this.list.push(p); return p;
  },
  remove(p) { this.list = this.list.filter(x => x !== p); },
  byId(id) { return this.list.find(p => p.id === id) || null; },
  runnable() { return this.list.filter(p => p.kind === 'forked' && p.state === 'running'); },
  latestForked() { return this.list.filter(p => p.kind === 'forked' && p.state === 'running').sort((a, b) => b.started - a.started)[0] || null; },
};
for (const p of FakeImage.processes) if (!p.window) Procs.add({ name: p.name, priority: p.priority, state: p.state, kind: 'system' });

function forkBlock(r, name, ectx) {
  const B = r.constructor, E = r.env.constructor;
  let root = r.env; while (root.parent) root = root.parent;
  const penv = new E(r.env); r.temps.forEach(t => penv.vars.set(t, null));
  const mk = (body, params = [], temps = []) => new B(params, temps, body, penv, r.home);
  const isBlk = n => n && n.k === 'block';
  const steps = r.body.map(st => {
    if (st.k === 'send' && st.sel === 'to:do:' && isBlk(st.args[1])) return { type: 'todo', fromB: mk([st.r]), toB: mk([st.args[0]]), body: mk(st.args[1].body, st.args[1].params, st.args[1].temps) };
    if (st.k === 'send' && st.sel === 'timesRepeat:' && isBlk(st.args[0])) return { type: 'times', nB: mk([st.r]), body: mk(st.args[0].body, [], st.args[0].temps) };
    if (st.k === 'send' && (st.sel === 'whileTrue:' || st.sel === 'whileFalse:') && isBlk(st.r) && isBlk(st.args[0])) return { type: 'while', cond: mk(st.r.body, [], st.r.temps), body: mk(st.args[0].body, [], st.args[0].temps), want: st.sel === 'whileTrue:' };
    return { type: 'stmt', b: mk([st]) };
  });
  const nm = name == null ? 'a Process' : typeof name === 'string' ? name : MiniST.printString(name);
  const p = Procs.add({ name: nm, priority: ectx.owner ? 30 : 35, state: 'running', kind: 'forked', origin: ectx.pane || null, owner: ectx.owner || null,
    steps, pc: 0, root, ws: ectx.ws, penv, src: ectx.src, started: now(), progress: 0, queued: [] });
  p.call = (expr, binds) => {
    for (const k in binds) root.vars.set(k, binds[k]);
    try { return MiniST.evaluate(expr, { workspace: p.ws, transcript: transcriptOut, forked: (b, n) => forkBlock(b, n, { pane: p.origin, ws: p.ws, src: p.src }) }).value; }
    finally { for (const k in binds) root.vars.delete(k); }
  };
  if (p.owner) p.owner.data.proc = p;
  schedule();
  return p;
}
let schedTimer = null;
function schedule() { if (!schedTimer) schedTimer = setTimeout(schedTick, 0); }
function schedTick() {
  schedTimer = null; const t0 = now(); let rs;
  while ((rs = Procs.runnable()).length && now() - t0 < 7) for (const p of rs) { if (p.state === 'running') runSlice(p, 2.2); if (now() - t0 >= 7) break; }
  if (Procs.runnable().length) schedTimer = setTimeout(schedTick, 0);
}
function adapt(s, dt) { s.chunk = clamp(Math.round(s.chunk * clamp(0.9 / Math.max(dt, 0.02), 0.25, 4)), 1, 500000); }
function runSlice(p, ms) {
  const t0 = now(); p.slices++;
  try {
    while (now() - t0 < ms && p.state === 'running') {
      const s = p.steps[p.pc];
      if (!s) { finishProc(p); break; }
      if (s.type === 'stmt') { p.call('__b value', { __b: s.b }); p.pc++; }
      else if (s.type === 'todo') {
        if (s.i === undefined) {
          s.i = p.call('__b value', { __b: s.fromB }); s.to = p.call('__b value', { __b: s.toB }); s.from = s.i; s.chunk = 8;
          if (typeof s.i !== 'bigint' || typeof s.to !== 'bigint') { p.call('__f to: __t do: __b', { __f: s.i, __t: s.to, __b: s.body }); p.pc++; continue; }
        }
        if (s.i > s.to) { p.pc++; p.progress = 1; continue; }
        let end = s.i + BigInt(s.chunk) - 1n; if (end > s.to) end = s.to;
        const tc = now(); p.call('__f to: __t do: __b', { __f: s.i, __t: end, __b: s.body }); adapt(s, now() - tc);
        s.i = end + 1n; p.progress = Number(s.i - s.from) / Math.max(1, Number(s.to - s.from + 1n));
      } else if (s.type === 'times') {
        if (s.left === undefined) { s.n = Number(p.call('__b value', { __b: s.nB })); s.left = s.n; s.chunk = 8; }
        if (s.left <= 0) { p.pc++; p.progress = 1; continue; }
        const c = Math.min(s.left, s.chunk); const tc = now();
        p.call('__n timesRepeat: __b', { __n: BigInt(c), __b: s.body }); adapt(s, now() - tc);
        s.left -= c; p.progress = 1 - s.left / Math.max(1, s.n);
      } else if (s.type === 'while') {
        if (p.call('__b value', { __b: s.cond }) !== s.want) { p.pc++; continue; }
        p.call('__b value', { __b: s.body }); s.iter = (s.iter || 0) + 1;
      }
    }
  } catch (err) {
    p.state = 'terminated'; p.ended = now(); p.error = errMsg(err);
    reportError(p.origin, `[] in DoIt — Process '${p.name}' #${p.id}`, err);
    reap(p);
  }
  p.cpu += now() - t0;
}
function finishProc(p) {
  p.state = 'terminated'; p.ended = now(); p.progress = 1;
  const secs = ((p.ended - p.started) / 1000).toFixed(1);
  if (p.origin) p.origin.note(`Process '${p.name}' finished · ${secs} s`, 'ok');
  reap(p);
}
function reap(p) { setTimeout(() => { Procs.remove(p); }, 2500); }
function terminateProc(p) {
  if (!p) return;
  if (p.kind === 'system') return rowNote(`won't terminate system process '${p.name}'`, true);
  if (p.kind === 'pane') { closePane(p.pane); return; }
  if (p.state === 'terminated') return;
  p.state = 'terminated'; p.ended = now(); p.killed = true;
  transcriptOut(`Process '${p.name}' #${p.id} terminated\n`);
  if (p.origin) p.origin.note(`terminated '${p.name}'`, 'err');
  reap(p);
  panes.filter(x => x.kind === 'debugger' && x.data.proc === p).forEach(closePane);
}
function interruptProc(p, reason = 'user interrupt') {
  if (!p) return;
  if (p.kind === 'system') return rowNote(`'${p.name}' is a VM-level process; not debuggable in this prototype`, true);
  if (p.state === 'terminated') return rowNote('process already terminated', true);
  if (p.kind === 'pane' && p.pane.kind === 'debugger') return rowNote('that is a debugger already', true);
  p.state = 'suspended';
  openPane('debugger', `Debug/${p.name.replace(/\s+/g, '-')}`, { proc: p, reason }, null, 'browse', { index: 0, frac: 0.52, update: true });
}
function resumeProc(p) {
  if (!p || p.state !== 'suspended') return;
  p.state = p.kind === 'forked' ? 'running' : 'waiting';
  if (p.kind === 'forked') schedule();
  panes.filter(x => x.kind === 'debugger' && x.data.proc === p).forEach(closePane);
}
function userInterrupt() {
  const p = Procs.latestForked();
  if (p) return interruptProc(p);
  const fp = focusedPane;
  if (fp && fp.kind !== 'debugger') return interruptProc(fp.proc);
  rowNote('nothing to interrupt', true);
}

// ======================================================================
// Panes & columns
// ======================================================================
const panes = []; const cols = [];
let focusedPane = null, paneSeq = 0, globalMono = false, rowTV = null;

const KINDS = {
  image:      { tag: 'Close Get | Flat Layers', content: p => imageText(p), hl: t => hlListing(t) },
  package:    { tag: 'Close Get', content: p => packageText(p), hl: t => hlListing(t) },
  class:      { tag: 'Close Get | Hierarchy References', content: p => classText(p), hl: t => hlListing(t) },
  method:     { tag: 'Close Accept Get | Senders Implementors', content: p => Img.source(p.data.m), hl: t => hlSource(t, true), code: true, dirtyable: true },
  list:       { tag: 'Close', content: p => p.data.text, hl: t => hlListing(t) },
  workspace:  { tag: 'Close | Do Print Inspect Clear Crunch', content: p => p.data.text || '', hl: t => hlSource(t, false), code: true, ws: true },
  transcript: { tag: 'Close Clear', content: p => p.data.text || '', hl: t => hlListing(t, { heads: false }) },
  errors:     { tag: 'Close Clear', content: p => p.data.text || '', hl: t => hlListing(t, { heads: false }) },
  processes:  { tag: 'Close | Crunch Interrupt', content: () => processesText(), hl: t => hlListing(t, { heads: false, states: true }), font: 'mono', live: true, nowrap: true },
  inspector:  { tag: 'Close Back Get', content: p => inspectorText(p), hl: t => hlListing(t), ws: true },
  debugger:   { tag: 'Close | Proceed Terminate', content: p => debuggerText(p), hl: t => hlListing(t, { states: true }) },
  crunch:     { tag: 'Close | Crunch Debug Kill', content: p => crunchText(p), hl: t => hlListing(t, { states: true }), live: true, font: 'mono' },
};

class Pane {
  constructor(kind, name, data = {}) {
    this.id = ++paneSeq; this.kind = kind; this.name = name; this.data = data; this.dirty = false;
    this.spec = KINDS[kind]; this.font = this.spec.font || (globalMono ? 'mono' : 'prop');
    this.wsId = this.spec.ws ? `ws-${this.id}` : 'global';
    this.queued = []; this.w = 1; this.px = { y: 0, h: 0 };
    this.el = h('div', 'pane' + (this.spec.nowrap ? ' nowrap' : ''));
    const tag = h('div', 'tag', this.el);
    this.handle = h('div', 'handle', tag); this.handle.title = 'drag: resize, or drop in another column · click: grow / restore';
    this.glyph = h('span', 'glyph', tag, '○');
    this.tag = new TextView(tag, { scope: 'pane', pane: this }, 'tag', { highlight: t => hlTag(t, this.dirty, true) });
    this.statusEl = h('span', 'status', tag);
    const body = h('div', 'body', this.el);
    this.gutter = h('div', 'gutter', body); this.thumb = h('div', 'thumb', this.gutter);
    this.body = new TextView(body, { scope: 'pane', pane: this }, 'body', { highlight: this.spec.hl, onEdit: () => this.edited() });
    this.body.onScroll = () => this.updateThumb();
    this.tag.setText(`${name}  ${this.spec.tag}`);
    this.applyFont();
    this.proc = Procs.add({ name, priority: 40, state: 'waiting', kind: 'pane', pane: this });
    panes.push(this);
    setupHandleDrag(this); setupGutter(this);
    this.refresh(false);
  }
  refresh(keep = true) { if (this.spec.content) this.body.setText(this.spec.content(this), keep); }
  setDirty(d) { if (this.dirty === d) return; this.dirty = d; this.el.classList.toggle('dirty', d); this.tag.render(); }
  edited() { this.proc.touch(); if (this.spec.dirtyable) this.setDirty(true); }
  applyFont() { this.el.classList.toggle('mono', this.font === 'mono'); this.body.render(); }
  focus() { reveal(this, false); this.body.ta.focus({ preventScroll: true }); setFocused(this); }
  note(msg, cls = '', ms = 3200) {
    this.statusMsg = { msg, cls, until: now() + ms }; this.renderStatus();
  }
  renderStatus() {
    let msg = '', cls = '';
    if (this.statusMsg && this.statusMsg.until > now()) ({ msg, cls } = this.statusMsg);
    else {
      const kids = Procs.list.filter(p => p.kind === 'forked' && p.origin === this && p.state !== 'terminated' && !p.owner);
      if (kids.length) { const k = kids[kids.length - 1]; msg = `${k.state === 'suspended' ? '‖' : SPIN[spinI]} ${k.name} ${Math.round(k.progress * 100)}%${kids.length > 1 ? ` +${kids.length - 1}` : ''}`; cls = 'busy'; }
      else if (this.frozen && this.queued.length) { msg = `busy · ${this.queued.length} event${this.queued.length > 1 ? 's' : ''} queued`; cls = 'busy'; }
      else if (this.frozen) { const own = this.kind === 'crunch' && this.data.proc; msg = this.proc.state === 'suspended' || (own && own.state === 'suspended') ? 'suspended in debugger' : 'busy'; cls = 'busy'; }
    }
    const k = msg + '|' + cls;
    if (k !== this._st) { this._st = k; this.statusEl.textContent = msg; this.statusEl.className = 'status' + (cls ? ' st-' + cls : ''); this.statusEl.title = msg; }
  }
  flash(kind = 'ok') { const c = kind === 'err' ? 'flash-err' : 'flash'; this.el.classList.remove(c); void this.el.offsetWidth; this.el.classList.add(c); }
  updateThumb() {
    const ta = this.body.ta, gh = this.gutter.clientHeight; if (!gh) return;
    const sh = ta.scrollHeight, ch = ta.clientHeight;
    const top = sh > ch ? ta.scrollTop / sh * gh : 0, hh = sh > ch ? Math.max(8, ch / sh * gh) : gh;
    const k = `${top | 0}:${hh | 0}`; if (k === this._th) return; this._th = k;
    this.thumb.style.top = (top | 0) + 'px'; this.thumb.style.height = (hh | 0) + 'px';
  }
}
function setFocused(p) { if (focusedPane === p) return; if (focusedPane) focusedPane.el.classList.remove('focused'); focusedPane = p; if (p) p.el.classList.add('focused'); }
function note(pane, msg, cls) { if (pane) pane.note(msg, cls); else rowNote(msg, cls === 'err'); }
let rowTimer = 0;
function rowNote(msg, err) { const r = document.getElementById('rowstatus'); r.textContent = msg; r.className = err ? 'err' : ''; clearTimeout(rowTimer); rowTimer = setTimeout(() => (r.textContent = ''), 4000); }

function makeCol(w, index = cols.length) {
  const c = { w, panes: [], px: { x: 0, w: 0 } };
  c.el = h('div', 'col'); colsEl.insertBefore(c.el, colsEl.children[index] || null);
  const tag = h('div', 'coltag', c.el);
  c.handle = h('div', 'handle', tag); c.handle.title = 'drag: resize column';
  c.tag = new TextView(tag, { scope: 'col', col: c }, 'col', { highlight: t => hlTag(t, false, false) });
  c.tag.setText('New  Sort  Delcol');
  setupColDrag(c);
  cols.splice(index, 0, c);
  return c;
}
const colBodyH = () => colsEl.clientHeight - TAG_H;
function colPx(c) { const n = c.panes.length, extra = Math.max(0, colBodyH() - n * TAG_H), sw = sum(c.panes.map(p => p.w)) || 1; return c.panes.map(p => TAG_H + extra * p.w / sw); }
function setColPx(c, px) { const ex = px.map(v => Math.max(0, v - TAG_H)); const s = sum(ex); c.panes.forEach((p, i) => (p.w = s > 0 ? ex[i] / s : 1 / px.length)); }

let layoutRaf = 0;
function layoutSoon() { if (!layoutRaf) layoutRaf = requestAnimationFrame(() => { layoutRaf = 0; layout(); }); }
function layout() {
  const W = colsEl.clientWidth, H = colsEl.clientHeight, tw = sum(cols.map(c => c.w)) || 1;
  let x = 0;
  cols.forEach((c, i) => {
    const w = i === cols.length - 1 ? W - x : Math.round(W * c.w / tw);
    c.px = { x, w }; c.el.style.left = x + 'px'; c.el.style.width = w + 'px'; c.el.style.height = H + 'px';
    const px = colPx(c); let y = TAG_H;
    c.panes.forEach((p, j) => {
      let ph = j === c.panes.length - 1 ? Math.max(TAG_H, H - y) : Math.round(px[j]);
      p.px = { y, h: ph }; p.el.style.top = y + 'px'; p.el.style.height = ph + 'px';
      p.el.classList.toggle('collapsed', ph < TAG_H + 10); p.el.classList.toggle('first', j === 0);
      y += ph;
    });
    x += w;
  });
  for (const p of panes) p.updateThumb();
}
function fitHeight(p, col) {
  const cpl = Math.max(20, (col.px.w - 40) / 7.4);
  const rows = p.body.value.split('\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.replace(/\t/g, '    ').length / cpl)), 0);
  return TAG_H + 18 * rows + 30;
}
function placePane(p, col, index, frac = 0.5, spare = null) {
  const px = colPx(col); const H = colBodyH();
  if (index === 'end') index = col.panes.length;
  index = clamp(index, 0, col.panes.length);
  const want = Math.max(TAG_H * 4, Math.min(Math.round(H * frac), p.spec.live ? Infinity : fitHeight(p, col)));
  const extras = px.map(v => v - TAG_H); const totalExtra = sum(extras);
  let need = Math.min(Math.max(0, totalExtra - TAG_H), want + TAG_H);
  // take space from the other panes first, sparing the one we were opened from
  const si = spare ? col.panes.indexOf(spare) : -1;
  const pool = sum(extras.filter((_, i) => i !== si)); const fromPool = Math.min(need, pool * 0.85);
  const rest = si < 0 ? need - fromPool : Math.min(need - fromPool, extras[si] * 0.5);
  need = fromPool + rest;
  const newPx = extras.map((e, i) => TAG_H + Math.max(0, i === si ? e - rest : e - (pool > 0 ? fromPool * e / pool : 0)));
  newPx.splice(index, 0, need);
  col.panes.splice(index, 0, p); p.col = col;
  col.el.appendChild(p.el);
  setColPx(col, newPx);
}
function openPane(kind, name, data, ctx, where = 'browse', o = {}) {
  let p = panes.find(x => x.name === name);
  if (p) { if (o.update) { Object.assign(p.data, data); p.refresh(false); } reveal(p, o.focus !== false); p.flash(); return p; }
  p = new Pane(kind, name, data);
  const col = o.col || (where === 'tool' ? cols[Math.min(2, cols.length - 1)] : cols[Math.min(1, cols.length - 1)]);
  let idx = 0; const from = ctx && ctx.pane;
  if (o.index != null) idx = o.index; else if (from && from.col === col) idx = col.panes.indexOf(from) + 1;
  placePane(p, col, idx, o.frac || 0.5, from && from.col === col ? from : null);
  layout(); p.flash();
  if (o.focus !== false) p.focus();
  return p;
}
function reveal(p, focus = true) {
  if (p.px.h < TAG_H * 4) {
    const c = p.col, px = colPx(c), i = c.panes.indexOf(p), H = colBodyH();
    const want = H * 0.45, others = sum(px) - px[i], room = H - want;
    c.panes.forEach((q, j) => { if (j !== i) px[j] = TAG_H + Math.max(0, (px[j] - TAG_H) * Math.max(0, room - (c.panes.length - 1) * TAG_H) / Math.max(1, others - (c.panes.length - 1) * TAG_H)); });
    px[i] = want; setColPx(c, px); c.grown = null; layout();
  }
  if (focus) { p.body.ta.focus({ preventScroll: true }); setFocused(p); }
}
function closePane(p) {
  const c = p.col, i = c.panes.indexOf(p);
  if (i < 0) return;
  const heir = c.panes[i - 1] || c.panes[i + 1];
  if (heir) heir.w += p.w;
  c.panes.splice(i, 1); panes.splice(panes.indexOf(p), 1); Procs.remove(p.proc); p.el.remove();
  if (c.grown === p) c.grown = null;
  if (p.kind === 'crunch' && p.data.proc) terminateProc(p.data.proc);
  if (p.kind === 'debugger' && p.data.proc && p.data.proc.state === 'suspended') {
    const q = p.data.proc; if (q.kind === 'forked') terminateProc(q); else q.state = 'waiting';
  }
  if (focusedPane === p) { setFocused(null); if (heir) heir.focus(); }
  Hover.clear(); layout();
}
function toggleGrow(p) {
  const c = p.col;
  if (c.grown === p && c.saved) { c.panes.forEach(q => (q.w = c.saved.get(q) ?? q.w)); c.grown = null; }
  else { c.saved = new Map(c.panes.map(q => [q, q.w])); c.panes.forEach(q => (q.w = q === p ? 1 : 0)); c.grown = p; }
  layout(); p.focus();
}
function movePane(p, c2, y) {
  const c = p.col, i = c.panes.indexOf(p);
  const heir = c.panes[i - 1] || c.panes[i + 1]; if (heir) heir.w += p.w;
  c.panes.splice(i, 1); if (c.grown) c.grown = null;
  const px = colPx(c2); let acc = TAG_H, j = 0;
  for (; j < c2.panes.length; j++) { if (y < acc + px[j]) break; acc += px[j]; }
  if (j >= c2.panes.length) { j = c2.panes.length - 1; acc -= px[j] || 0; }
  if (j < 0) { c2.panes.push(p); p.col = c2; p.w = 1; }
  else {
    const top = acc, hT = px[j]; const cut = clamp(y - top, TAG_H, Math.max(TAG_H, hT - Math.min(hT / 2, TAG_H + 120)));
    px[j] = cut; px.splice(j + 1, 0, hT - cut);
    c2.panes.splice(j + 1, 0, p); p.col = c2; setColPx(c2, px);
  }
  c2.el.appendChild(p.el); layout(); p.flash();
}

// ---------- drags ----------
const colAtX = x => { const r = colsEl.getBoundingClientRect(); return cols.find(c => x - r.left >= c.px.x && x - r.left < c.px.x + c.px.w) || cols[cols.length - 1]; };
function setupHandleDrag(p) {
  p.handle.addEventListener('mousedown', e => {
    if (e.button !== 0) return; e.preventDefault();
    const sx = e.clientX, sy = e.clientY; let dragging = false, target = null, last = null, raf = 0, drop = null, ghost = null;
    const apply = () => {
      raf = 0; const ev = last; const r = colsEl.getBoundingClientRect(); const y = ev.clientY - r.top; const c2 = colAtX(ev.clientX);
      if (c2 === p.col) {
        target = null; if (drop) drop.style.display = 'none';
        const c = p.col, i = c.panes.indexOf(p); if (i <= 0) return;
        const px = colPx(c); const top = p.col.panes[i - 1].px.y, bottom = p.px.y + p.px.h;
        const ny = clamp(y, top + TAG_H, bottom - TAG_H);
        px[i - 1] = ny - top; px[i] = bottom - ny; setColPx(c, px); c.grown = null; layout();
      } else {
        target = { c: c2, y };
        if (!drop) drop = h('div', 'drop', fx);
        Object.assign(drop.style, { display: 'block', left: (r.left + c2.px.x + 2) + 'px', width: (c2.px.w - 4) + 'px', top: (r.top + clamp(y, TAG_H, r.height - 3)) + 'px' });
      }
      if (ghost) { ghost.style.left = (ev.clientX + 12) + 'px'; ghost.style.top = (ev.clientY + 10) + 'px'; }
    };
    const move = ev => {
      if (!dragging && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return;
      if (!dragging) { dragging = true; document.body.classList.add('dragging'); Hover.clear(); ghost = h('div', 'ghost', fx, p.name); }
      last = ev; if (!raf) raf = requestAnimationFrame(apply);
    };
    const up = () => {
      document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up);
      if (raf) { cancelAnimationFrame(raf); if (last) apply(); }
      document.body.classList.remove('dragging'); if (drop) drop.remove(); if (ghost) ghost.remove();
      if (!dragging) toggleGrow(p); else if (target) movePane(p, target.c, target.y);
    };
    document.addEventListener('mousemove', move); document.addEventListener('mouseup', up);
  });
}
function setupColDrag(c) {
  c.handle.addEventListener('mousedown', e => {
    if (e.button !== 0) return; e.preventDefault();
    const i = cols.indexOf(c); if (i <= 0) return rowNote('drag the handle of a column to its right to resize');
    document.body.classList.add('dragging-col'); let last = null, raf = 0;
    const apply = () => {
      raf = 0; const r = colsEl.getBoundingClientRect(); const x = last.clientX - r.left;
      const prev = cols[i - 1]; const lo = prev.px.x + 160, hi = c.px.x + c.px.w - 160; if (hi <= lo) return;
      const nx = clamp(x, lo, hi); const ws = cols.map(q => q.px.w);
      ws[i - 1] = nx - prev.px.x; ws[i] = c.px.x + c.px.w - nx; cols.forEach((q, k) => (q.w = ws[k])); layout();
    };
    const move = ev => { last = ev; if (!raf) raf = requestAnimationFrame(apply); };
    const up = () => { document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up); document.body.classList.remove('dragging-col'); };
    document.addEventListener('mousemove', move); document.addEventListener('mouseup', up);
  });
}
function setupGutter(p) {
  p.gutter.addEventListener('mousedown', e => {
    e.preventDefault();
    const go = ev => { const r = p.gutter.getBoundingClientRect(), ta = p.body.ta; ta.scrollTop = (ev.clientY - r.top) / r.height * ta.scrollHeight - ta.clientHeight / 2; p.body.sync(); };
    go(e);
    const up = () => { document.removeEventListener('mousemove', go); document.removeEventListener('mouseup', up); };
    document.addEventListener('mousemove', go); document.addEventListener('mouseup', up);
  });
}

// ======================================================================
// Pane contents
// ======================================================================
function imageText(p) {
  const layers = [...new Set(FakeImage.packages.map(q => q.layer))].sort((a, b) => b - a);
  let s = `"${layers.length} layers · ${FakeImage.packages.length} packages · ${Img.classes.length} classes. Each layer calls only the one directly below."\n\n`;
  if (p.data.flat) {
    for (const c of [...Img.classes].sort((a, b) => a.name.localeCompare(b.name))) s += `${c.name}\t\t${c.package}\n`;
    return s;
  }
  layers.forEach((L, i) => {
    FakeImage.packages.filter(q => q.layer === L).forEach((q, j) => {
      s += (j === 0 ? L : '') + '\t' + q.name + '\n';
      s += '\t\t' + q.classes.map(c => c.name).join('  ') + '\n';
    });
    if (i < layers.length - 1) s += '\t↓\n';
  });
  s += `\n"Right-click (${K}click) a name to open it. Middle-click (${OPT}click) a command."\n`;
  return s;
}
function packageText(p) {
  const q = Img.pkg(p.name);
  let s = `"${q.comment}"\n\nlayer ${q.layer} · ${q.layer > 0 ? 'calls only layer ' + (q.layer - 1) : 'bottom of the stack: talks to VM primitives'}\n\n`;
  for (const c of q.classes) {
    const n = Img.methodsOf(c.name).length;
    s += `${c.name}  ← ${c.superclass}  · ${n} method${n === 1 ? '' : 's'}\n`;
    if (c.ivars.length) s += `\t${c.ivars.join(' ')}\n`;
  }
  return s;
}
function classText(p) {
  const c = Img.cls(p.name); const pk = FakeImage.packages.find(q => q.classes.some(x => x.name === c.name));
  let s = `${c.superclass} subclass: #${c.name}\n\tinstanceVariableNames: '${c.ivars.join(' ')}'\n\tpackage: '${pk.name}'\n\n"${c.comment}"\n\n`;
  const protos = Object.entries(c.protocols || {});
  if (!protos.length) s += '"no methods yet"\n';
  for (const [proto, ms] of protos) { s += proto + '\n'; for (const key of Object.keys(ms)) s += `\t${c.name}>>${Img.selectorOf(key)}\n`; }
  return s;
}
function listText(header, ms) {
  return `"${header}"\n\n` + (ms.length ? ms.map(m => `${m.ref}\t"${m.proto} · ${m.pkg}"`).join('\n') : '"(none in this image)"') + '\n';
}
function hierarchyText(cn) {
  const chain = []; for (let n = cn, g = 0; n && g < 20; n = Img.superOf(n), g++) chain.unshift(n);
  let s = `"Hierarchy of ${cn}"\n\n`;
  chain.forEach((n, i) => (s += '\t'.repeat(i) + n + (n === cn ? '  ◂' : '') + '\n'));
  const sub = (n, d) => Img.subclassesOf(n).forEach(k => { s += '\t'.repeat(d) + k + '\n'; sub(k, d + 1); });
  sub(cn, chain.length);
  return s;
}
function inspectorText(p) {
  const d = p.data; const rows = MiniST.inspect(d.value);
  let s = `"${d.title}"\n\n`;
  rows.forEach(r => (s += `${r.name}: ${r.value}\n`));
  s += `\n"self is bound here: ${K}P prints, ${K}I inspects. Right-click a field to dive in."\nself printString size\n`;
  return s;
}
function bindSelf(p) { const root = wsRoot(p.wsId); if (root) root.vars.set('self', p.data.value); }
function openInspector(value, title, from) {
  const ps = MiniST.printString(value);
  const name = 'Inspect/' + trunc(ps.replace(/\s+/g, ''), 26);
  const p = openPane('inspector', name, { value, title, history: [] }, { pane: from }, 'tool', { update: true, frac: 0.34, focus: !from || from.kind === 'inspector' || from.kind === 'debugger' });
  bindSelf(p); return p;
}
function inspectorDive(p, line) {
  const m = /^\s*(\w+):\s(.*)$/.exec(line); if (!m) return false;
  if (!MiniST.inspect(p.data.value).some(r => r.name === m[1])) return false;
  let v; try { v = MiniST.evaluate(m[2], { workspace: 'dive' }).value; } catch { v = m[2]; }
  p.data.history.push({ value: p.data.value, title: p.data.title });
  p.data.value = v; p.data.title = `${p.data.title} › ${m[1]}`; bindSelf(p); p.refresh(false); p.flash();
  return true;
}
const SPIN = ['◐', '◓', '◑', '◒']; let spinI = 0;
function procGlyph(p) { return p.state === 'running' ? (p.kind === 'forked' ? SPIN[spinI] : '●') : p.state === 'suspended' ? '‖' : p.state === 'terminated' ? '×' : p.state === 'ready' ? '·' : '○'; }
function processesText() {
  const hot = p => (p.kind === 'forked' && p.state !== 'terminated') || p.state === 'suspended' ? 0 : 1;
  const L = [...Procs.list].sort((a, b) => hot(a) - hot(b) || b.priority - a.priority || a.id - b.id);
  let s = ' pid pr state       name\n';
  for (const p of L) {
    let extra = '';
    if (p.kind === 'forked') {
      extra = `${String(Math.round(p.progress * 100)).padStart(3)}% ${(p.cpu / 1000).toFixed(1).padStart(4)}s`;
      extra += p.state === 'running' ? '  Debug Kill' : p.state === 'suspended' ? '  Resume Kill' : p.killed ? '  killed' : p.error ? '  error' : '  done';
    } else if (p.kind === 'pane') extra = p.state === 'suspended' ? 'pane  Resume' : 'pane';
    s += `${('#' + p.id).padStart(4)} ${String(p.priority).padStart(2)} ${p.state.padEnd(9)} ${procGlyph(p)} ${extra ? (p.kind === 'forked' ? trunc(p.name, 14).padEnd(15) : trunc(p.name, 22).padEnd(23)) + extra : p.name}\n`;
  }
  const run = Procs.list.filter(p => p.state === 'running').length;
  s += `\n"${Procs.list.length} processes · ${run} running · 1 OS thread.\n Preempted at safepoints; the compositor runs at priority 70."\n`;
  return s;
}
function forkedFrames(pr) {
  const s = pr.steps[pr.pc]; const frames = [];
  if (s && s.type !== 'stmt') {
    const sels = []; const walk = n => {
      if (!n || typeof n !== 'object') return;
      if (Array.isArray(n)) return n.forEach(walk);
      if (n.k === 'send') { sels.push(n.sel); walk(n.r); walk(n.args); }
      else if (n.k === 'block') walk(n.body); else if (n.k === 'cascade') { walk(n.first); walk(n.rest); } else if (n.e) walk(n.e);
    };
    walk(s.body.body);
    const m = sels.map(x => Img.implementorsOf(x)[0]).find(Boolean);
    if (m) frames.push(m.cls === 'Integer' ? `SmallInteger(Integer)>>${m.sel}` : `${m.cls}>>${m.sel}`);
    frames.push('[] in UndefinedObject>>DoIt');
    frames.push(s.type === 'todo' ? 'SmallInteger(Number)>>to:do:' : s.type === 'times' ? 'SmallInteger(Integer)>>timesRepeat:' : 'BlockClosure>>whileTrue:');
  }
  frames.push('[] in UndefinedObject>>DoIt', '[] in BlockClosure>>newProcess');
  return frames;
}
function debuggerText(p) {
  const d = p.data, pr = d.proc; d.vars = {};
  let s = `${d.reason}\n"Process '${pr.name}' #${pr.id} · priority ${pr.priority} · ${pr.state}.\n Only this process is stopped; every other pane keeps running."\n\n`;
  let frames;
  if (pr.kind === 'forked') {
    frames = forkedFrames(pr);
    const st = pr.steps[pr.pc];
    for (const [k, v] of pr.penv.vars) d.vars[k] = v;
    if (st && st.type === 'todo' && st.i !== undefined && st.body.params[0]) d.vars[st.body.params[0]] = st.i;
  } else {
    frames = ['Semaphore>>wait', 'SharedQueue>>next', '[] in Window>>eventLoop', 'BlockClosure>>repeat', 'Window>>eventLoop', '[] in Window>>open', '[] in BlockClosure>>newProcess'];
    d.vars = { self: `a Window('${pr.pane.name}')`, event: null };
  }
  s += frames.map(f => '\t' + f).join('\n') + '\n\n';
  if (pr.kind === 'forked') s += `"DoIt"\n${pr.src.trim()}\n\n`;
  s += 'thisContext\n' + Object.entries(d.vars).map(([k, v]) => `\t${k}: ${typeof v === 'string' && k === 'self' ? v : MiniST.printString(v)}`).join('\n') + '\n\n';
  s += 'Proceed  Terminate\n';
  return s;
}
function debuggerDive(p, line) {
  const m = /^\s*(\w+):\s(.*)$/.exec(line); if (!m || !p.data.vars || !(m[1] in p.data.vars)) return false;
  openInspector(p.data.vars[m[1]], `${p.data.proc.name} · ${m[1]}`, p); return true;
}
const CRUNCH_N = 5000000;
const CRUNCH_SRC = `[| n | n := 0.\n\t1 to: ${CRUNCH_N} do: [:i | i isPrime ifTrue: [n := n + 1]].\n\tTranscript show: 'crunch: ', n printString, ' primes below ${fmt(CRUNCH_N)}'; cr] forkNamed: 'crunch'`;
function crunchText(p) {
  const tail = `\n"A CPU-bound Process at priority 30. While it runs this pane's own process is busy, so typing here queues. Every other pane stays live. ${K}. or Debug interrupts it."\n\n${CRUNCH_SRC}\n`;
  let s = '';
  const pr = p.data.proc; if (!pr) return '"Crunch to start."\n' + tail;
  const st = pr.steps[pr.pc] || pr.steps.find(x => x.type === 'todo');
  const i = st && st.i !== undefined ? st.i : 0n, n = pr.penv.vars.get('n') ?? 0n;
  const cells = 44, f = Math.round(pr.progress * cells);
  const el = ((pr.ended || now()) - pr.started) / 1000;
  s += `${'█'.repeat(f)}${'░'.repeat(cells - f)} ${String(Math.round(pr.progress * 100)).padStart(3)}%\n`;
  s += `i = ${fmt(i > BigInt(CRUNCH_N) ? CRUNCH_N : i)} of ${fmt(CRUNCH_N)} · n = ${fmt(n)} primes\n`;
  s += `Process #${pr.id} ${pr.state} · ${el.toFixed(1)} s wall · ${(pr.cpu / 1000).toFixed(1)} s cpu · ${fmt(pr.slices)} slices\n`;
  return s + tail;
}
function startCrunch(ctx) {
  const tc = cols[Math.min(2, cols.length - 1)];
  const ti = tc.panes.findIndex(x => x.kind === 'transcript');
  const p = openPane('crunch', '+Crunch', {}, ctx, 'tool', { index: ti < 0 ? 'end' : ti, frac: 0.3, focus: false });
  const old = p.data.proc;
  if (old && (old.state === 'running' || old.state === 'suspended')) return p.note('already crunching', 'err');
  p.data.proc = null;
  try { stEval(CRUNCH_SRC, p, { owner: p }); } catch (err) { reportError(p, CRUNCH_SRC, err); }
  p.refresh(false); p.note('forked crunch', 'ok', 1500);
}

// ======================================================================
// Look: open the class / method / package named by some text
// ======================================================================
function openMethod(m, ctx) { return openPane('method', m.ref, { m }, ctx, 'browse', { frac: 0.5 }); }
function openClass(cn, ctx) { return openPane('class', cn, {}, ctx, 'browse', { frac: 0.45 }); }
function openPackage(pn, ctx) { return openPane('package', pn, {}, ctx, 'browse', { frac: 0.4 }); }
function openList(name, header, ms, ctx) { return openPane('list', name, { text: listText(header, ms) }, ctx, 'browse', { frac: 0.3, update: true }); }
function searchIn(tv, text, range) {
  const v = tv.value; let from = range ? range[1] : tv.ta.selectionEnd;
  let i = v.indexOf(text, from); if (i < 0) i = v.indexOf(text);
  if (i < 0 || (range && i === range[0])) return false;
  tv.select(i, i + text.length); flashRange(tv, i, i + text.length, 'look'); return true;
}
function look(text, ctx = {}) {
  text = (text || '').trim().replace(/^#/, '').replace(/[.,;)\]]+$/, '');
  if (!text) return;
  const m = /^(?:\[\] in )?([A-Z]\w*)(?:\(([A-Z]\w*)\))?(?: class)?>>(\S+)$/.exec(text);
  if (m) {
    const cn = m[2] || m[1], sel = m[3];
    if (sel === 'DoIt') { if (ctx.tv && searchIn(ctx.tv, '"DoIt"')) return; return note(ctx.pane, 'DoIt: a throwaway method compiled for evaluated text', 'ok'); }
    const meth = Img.lookupMethod(cn, sel);
    if (meth) return openMethod(meth, ctx);
    return note(ctx.pane, `${cn}>>${sel} is not in this prototype image`, 'err');
  }
  if (Img.classNames.has(text)) return openClass(text, ctx);
  if (Img.pkgNames.has(text)) return openPackage(text, ctx);
  if (text === 'Image') return openPane('image', 'Image', {}, ctx, 'browse');
  const pn = panes.find(p => p.name === text); if (pn) { reveal(pn); pn.flash(); return; }
  if (text === 'Processes') return CMD.Processes.fn(ctx);
  if (ctx.pane && ctx.pane.kind === 'inspector' && ctx.line && inspectorDive(ctx.pane, ctx.line)) return;
  if (ctx.pane && ctx.pane.kind === 'debugger' && ctx.line && debuggerDive(ctx.pane, ctx.line)) return;
  const sel = text.replace(/\s+/g, '');
  const imps = Img.implementorsOf(sel);
  if (imps.length === 1) return openMethod(imps[0], ctx);
  if (imps.length > 1) return openList(`Implementors/#${sel}`, `${imps.length} implementors of #${sel}`, imps, ctx);
  if (ctx.tv && searchIn(ctx.tv, text, ctx.range)) return;
  note(ctx.pane, `no match for “${trunc(text, 32)}”`, 'err');
}

// ======================================================================
// Commands (any word in any text can be one)
// ======================================================================
const CMD_DOC = [];
function def(names, doc, fn, opts = {}) { const list = names.split(' '); list.forEach(n => (CMD[n] = { fn, arg: !!opts.arg, doc })); CMD_DOC.push({ name: list[0], alias: list.slice(1), doc }); }
const target = ctx => ctx.pane || focusedPane;
function selectorFor(ctx) {
  if (ctx.arg) return ctx.arg.replace(/^#/, '').replace(/\s+/g, '');
  const p = target(ctx); if (!p) return null;
  const ta = p.body.ta;
  if (ta.selectionStart !== ta.selectionEnd) return Img.selectorOf(ta.value.slice(ta.selectionStart, ta.selectionEnd).trim()).replace(/^#/, '');
  if (p.kind === 'method') return p.data.m.sel;
  return null;
}
function classFor(ctx) {
  if (ctx.arg && Img.classNames.has(ctx.arg)) return ctx.arg;
  const p = target(ctx); if (!p) return null;
  if (p.kind === 'class') return p.name;
  if (p.kind === 'method') return p.data.m.cls;
  return null;
}
function procFor(ctx) {
  if (ctx.arg) { const m = /#?(\d+)/.exec(ctx.arg); return m ? Procs.byId(+m[1]) : Procs.list.find(p => p.name === ctx.arg) || null; }
  if (ctx.tv && ctx.tv.kind === 'body' && ctx.line) { const m = /#(\d+)/.exec(ctx.line); if (m) return Procs.byId(+m[1]); }
  const p = ctx.pane;
  if (p && (p.kind === 'debugger' || p.kind === 'crunch')) return p.data.proc || null;
  return Procs.latestForked();
}
function accept(p) {
  if (!p || p.kind !== 'method') return note(p, 'nothing to accept here', 'err');
  if (!p.dirty) return p.note('no changes', '');
  Img.accept(p.data.m, p.body.value); p.setDirty(false); p.note('accepted', 'ok'); p.flash();
  transcriptOut(`${p.name} accepted · running processes pick it up on their next send\n`);
}

def('Close Del', 'close this pane', ctx => { const p = ctx.pane; if (!p) return rowNote('Close works in a pane tag', true); if (p.dirty && !p.warned) { p.warned = true; return p.note('unaccepted edits · Close again to discard', 'err'); } closePane(p); });
def('Accept Put', `accept (compile) the edited method · ${K}S`, ctx => accept(target(ctx)));
def('Putall', 'accept every edited method', () => { const d = panes.filter(p => p.dirty); d.forEach(accept); rowNote(d.length ? `accepted ${d.length} method${d.length > 1 ? 's' : ''}` : 'nothing to accept'); });
def('Get', 'reload from the image, discarding edits', ctx => { const p = target(ctx); if (!p) return; p.setDirty(false); p.warned = false; if (p.kind === 'inspector') bindSelf(p); p.refresh(false); p.note('reloaded'); });
def('Senders', 'methods that send this selector', ctx => { const s = selectorFor(ctx); if (!s) return note(target(ctx), 'Senders of what? select a selector', 'err'); const ms = Img.sendersOf(s); openList(`Senders/#${s}`, `${ms.length} sender${ms.length === 1 ? '' : 's'} of #${s}`, ms, ctx); }, { arg: true });
def('Implementors', 'methods that implement this selector', ctx => { const s = selectorFor(ctx); if (!s) return note(target(ctx), 'Implementors of what? select a selector', 'err'); const ms = Img.implementorsOf(s); openList(`Implementors/#${s}`, `${ms.length} implementor${ms.length === 1 ? '' : 's'} of #${s}`, ms, ctx); }, { arg: true });
def('Hierarchy', 'superclass chain and subclasses', ctx => { const c = classFor(ctx); if (!c) return note(target(ctx), 'Hierarchy of what?', 'err'); openPane('list', `Hierarchy/${c}`, { text: hierarchyText(c) }, ctx, 'browse', { frac: 0.3, update: true }); }, { arg: true });
def('References', 'methods that mention this class', ctx => { const c = classFor(ctx); if (!c) return note(target(ctx), 'References to what?', 'err'); const ms = Img.referencesTo(c); openList(`References/${c}`, `${ms.length} reference${ms.length === 1 ? '' : 's'} to ${c}`, ms, ctx); }, { arg: true });
def('Look', 'look up the argument: class, Class>>selector, package, selector', ctx => look(ctx.arg, ctx), { arg: true });
def('Crunch', 'fork a CPU-bound Process with its own pane', ctx => startCrunch(ctx));
def('Interrupt', `user interrupt: debug the busiest process · ${K}.`, () => userInterrupt());
def('Debug', 'suspend the process and open a debugger', ctx => { const p = procFor(ctx); if (!p) return note(ctx.pane, 'no process to debug', 'err'); interruptProc(p); }, { arg: true });
def('Kill', 'terminate the process', ctx => { const p = procFor(ctx); if (!p) return note(ctx.pane, 'no process to kill', 'err'); terminateProc(p); }, { arg: true });
def('Proceed Resume', 'resume the suspended process', ctx => { const p = procFor(ctx); if (!p || p.state !== 'suspended') return note(ctx.pane, 'nothing suspended', 'err'); resumeProc(p); }, { arg: true });
def('Terminate', 'terminate the debugged process', ctx => { const p = procFor(ctx); if (!p) return; terminateProc(p); });
def('Do', `do it: selection or current line · ${K}D`, ctx => { const p = target(ctx); if (p) evalSel(p.body, 'do'); });
def('Print', `print it, inserting the result · ${K}P`, ctx => { const p = target(ctx); if (p) evalSel(p.body, 'print'); });
def('Inspect', `inspect it in an inspector pane · ${K}I`, ctx => { const p = target(ctx); if (p) evalSel(p.body, 'inspect'); });
def('Clear', 'empty the pane', ctx => { const p = target(ctx); if (p) { p.body.setText('', false); p.data.text = ''; } });
def('Back', 'inspector: back to the previous object', ctx => { const p = target(ctx); if (!p || p.kind !== 'inspector' || !p.data.history.length) return note(p, 'nothing to go back to', 'err'); Object.assign(p.data, p.data.history.pop()); bindSelf(p); p.refresh(false); });
def('Flat', 'image: alphabetical class list', ctx => { const p = panes.find(x => x.kind === 'image'); if (p) { p.data.flat = true; p.refresh(false); } });
def('Layers', 'image: layered package view', ctx => { const p = panes.find(x => x.kind === 'image'); if (p) { p.data.flat = false; p.refresh(false); } });
def('Grow', 'grow pane to fill its column, or restore', ctx => { const p = target(ctx); if (p) toggleGrow(p); });
def('Font', 'toggle proportional / monospace (row tag: all panes)', ctx => {
  if (ctx.pane) { ctx.pane.font = ctx.pane.font === 'mono' ? 'prop' : 'mono'; ctx.pane.applyFont(); return; }
  globalMono = !globalMono; panes.forEach(p => { p.font = globalMono ? 'mono' : (p.spec.font || 'prop'); p.applyFont(); }); layout();
  rowNote(globalMono ? 'monospace' : 'proportional');
});
def('Theme', 'toggle the Acme and Graphite palettes', () => { const g = document.body.classList.toggle('theme-graphite'); document.body.classList.toggle('theme-acme', !g); rowNote(g ? 'Graphite' : 'Acme'); try { localStorage.setItem('samaltak3-theme', g ? 'graphite' : 'acme'); } catch {} });
def('Help', 'show interactions', () => Help.toggle(true));
def('Newcol', 'new column with a workspace', () => { const w = sum(cols.map(c => c.w)) / cols.length; const c = makeCol(w * 0.8); newWorkspace(c); });
def('New', 'new workspace pane in this column', ctx => newWorkspace(ctx.col || (focusedPane && focusedPane.col) || cols[cols.length - 1]));
def('Delcol', 'close this column and its panes', ctx => {
  const c = ctx.col; if (!c) return; if (cols.length < 2) return rowNote('the last column stays', true);
  [...c.panes].forEach(closePane); cols.splice(cols.indexOf(c), 1); c.el.remove(); layout();
});
def('Sort', 'sort panes in this column by name', ctx => { const c = ctx.col; if (!c) return; c.panes.sort((a, b) => a.name.localeCompare(b.name)); c.panes.forEach(p => c.el.appendChild(p.el)); layout(); });
def('Processes', 'open the live process list', ctx => openPane('processes', 'Processes', {}, ctx, 'tool', { index: 'end', frac: 0.35 }));
def('Workspace', 'open a new workspace', ctx => newWorkspace(cols[Math.min(2, cols.length - 1)]));
def('Snapshot', 'save the image (pretend)', () => transcriptOut(`Snapshot · samaltak.image written (${Img.all.length} methods, ${Procs.list.length} processes) — pretend\n`));

function newWorkspace(col) {
  let n = 1, name = 'Workspace'; while (panes.some(p => p.name === name)) name = `Workspace${++n}`;
  return openPane('workspace', name, { text: '"scratch"\n\n' }, null, 'browse', { col, index: 0, frac: 0.5 });
}

// ======================================================================
// Keyboard
// ======================================================================
const modKey = e => (isMac ? e.metaKey : e.ctrlKey);
function onTextKey(e, tv) {
  const pane = tv.owner.pane;
  if (pane && pane.frozen && tv.kind === 'body' && !modKey(e)) {
    if (e.key.length === 1 || e.key === 'Enter' || e.key === 'Backspace') { e.preventDefault(); pane.queued.push(e.key); pane.renderStatus(); }
    return;
  }
  if (modKey(e) && !e.altKey && !e.shiftKey) {
    const k = e.key.toLowerCase();
    if (k === 'd') { e.preventDefault(); e.stopPropagation(); return evalSel(tv, 'do'); }
    if (k === 'p') { e.preventDefault(); e.stopPropagation(); return evalSel(tv, 'print'); }
    if (k === 'i') { e.preventDefault(); e.stopPropagation(); return evalSel(tv, 'inspect'); }
    if (k === 's') { e.preventDefault(); e.stopPropagation(); return accept(pane); }
  }
  if (e.key === 'Tab' && !modKey(e) && !e.altKey && tv.kind === 'body') { e.preventDefault(); document.execCommand('insertText', false, '\t'); }
  if (e.key === 'Enter' && tv.kind !== 'body') {
    e.preventDefault();
    const r = tv.wordRange(Math.max(0, tv.ta.selectionStart - 1)); if (r) dispatch('exec', tv, r[0], r[1], true);
  }
  if (pane) pane.proc.touch();
}
function navigate(dir) {
  const p = focusedPane || panes[0]; if (!p) return;
  const c = p.col, ci = cols.indexOf(c), i = c.panes.indexOf(p); let q = null;
  if (dir === 'down') q = c.panes[i + 1]; else if (dir === 'up') q = c.panes[i - 1];
  else {
    const c2 = cols[ci + (dir === 'left' ? -1 : 1)]; if (!c2 || !c2.panes.length) return;
    const mid = p.px.y + Math.min(p.px.h, 200) / 2;
    q = c2.panes.find(x => mid >= x.px.y && mid < x.px.y + x.px.h) || c2.panes[c2.panes.length - 1];
  }
  if (q) { q.focus(); q.flash(); }
}
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') { if (!document.getElementById('help').hidden) return Help.toggle(false); if (!Cmdk.el.hidden) return Cmdk.close(); }
  if (modKey(e) && !e.altKey) {
    const k = e.key.toLowerCase();
    if (k === 'k') { e.preventDefault(); return Cmdk.open(); }
    if (k === '.') { e.preventDefault(); return userInterrupt(); }
    if (k === '/' || (k === '?' )) { e.preventDefault(); return Help.toggle(); }
    if (['d', 'p', 'i', 's'].includes(k) && !e.shiftKey && focusedPane && e.target === document.body) {
      e.preventDefault(); return k === 's' ? accept(focusedPane) : evalSel(focusedPane.body, { d: 'do', p: 'print', i: 'inspect' }[k]);
    }
  }
  if (e.key === 'F1') { e.preventDefault(); return Help.toggle(); }
  if (e.altKey && !e.metaKey && !e.ctrlKey) {
    const dir = { KeyH: 'left', KeyJ: 'down', KeyK: 'up', KeyL: 'right' }[e.code];
    if (dir) { e.preventDefault(); return navigate(dir); }
    if (e.code === 'Enter' && focusedPane) { e.preventDefault(); return toggleGrow(focusedPane); }
  }
});

// ======================================================================
// Command line (Cmd-K)
// ======================================================================
const Cmdk = {
  el: document.getElementById('cmdk'), input: document.getElementById('ck-in'), list: document.getElementById('ck-list'), out: document.getElementById('ck-out'),
  items: [], sel: 0, from: null,
  open() { this.from = focusedPane; this.el.hidden = false; this.input.value = ''; this.out.textContent = ''; this.update(); this.input.focus(); },
  close() { this.el.hidden = true; if (this.from && panes.includes(this.from)) this.from.body.ta.focus({ preventScroll: true }); },
  candidates() {
    const c = [];
    CMD_DOC.forEach(d => c.push({ label: d.name, kind: 'command', desc: d.doc }));
    Img.classes.forEach(x => c.push({ label: x.name, kind: 'class', desc: x.package }));
    Img.all.forEach(m => c.push({ label: m.ref, kind: 'method', desc: m.proto }));
    FakeImage.packages.forEach(p => c.push({ label: p.name, kind: 'package', desc: 'layer ' + p.layer }));
    panes.forEach(p => c.push({ label: p.name, kind: 'pane', desc: 'open pane' }));
    return c;
  },
  update() {
    const q = this.input.value.trim(); this.items = [];
    if (q && !/\s/.test(q)) {
      const lq = q.toLowerCase();
      this.items = this.candidates().map(c => { const l = c.label.toLowerCase(); const i = l.indexOf(lq); return i < 0 ? null : { ...c, score: (i === 0 ? 0 : 10) + l.length / 100 + (c.kind === 'command' ? -1 : 0) }; })
        .filter(Boolean).sort((a, b) => a.score - b.score).slice(0, 9);
    } else if (!q) this.items = CMD_DOC.slice(0, 8).map(d => ({ label: d.name, kind: 'command', desc: d.doc }));
    this.sel = 0; this.render();
  },
  render() {
    this.list.innerHTML = this.items.map((it, i) => `<div data-i="${i}" class="${i === this.sel ? 'sel' : ''}"><span>${esc(it.label)}</span><span class="d">${esc(it.desc || '')}</span><span class="k">${it.kind}</span></div>`).join('');
  },
  run(it) {
    const ctx = { scope: 'row', pane: null };
    if (it) {
      if (it.kind === 'command') { this.close(); return CMD[it.label].fn({ ...ctx, pane: null, arg: '' }); }
      this.close(); return look(it.label, ctx);
    }
    const q = this.input.value.trim(); if (!q) return;
    const w = q.split(/\s+/);
    if (CMD[w[0]] && (w.length === 1 || CMD[w[0]].arg)) { this.close(); return CMD[w[0]].fn({ ...ctx, arg: w.slice(1).join(' ') }); }
    try { const r = stEval(q, null); this.out.className = ''; this.out.textContent = resultNote(r).startsWith('⇒') ? r.printString : resultNote(r); }
    catch (err) { this.out.className = 'err'; this.out.textContent = errMsg(err); }
  },
};
Cmdk.input.addEventListener('input', () => Cmdk.update());
Cmdk.input.addEventListener('keydown', e => {
  if (e.key === 'ArrowDown') { e.preventDefault(); Cmdk.sel = Math.min(Cmdk.items.length - 1, Cmdk.sel + 1); Cmdk.render(); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); Cmdk.sel = Math.max(0, Cmdk.sel - 1); Cmdk.render(); }
  else if (e.key === 'Tab') { e.preventDefault(); const it = Cmdk.items[Cmdk.sel]; if (it) { Cmdk.input.value = it.label; Cmdk.update(); } }
  else if (e.key === 'Enter') {
    e.preventDefault(); const q = Cmdk.input.value.trim(); const it = Cmdk.items[Cmdk.sel];
    const exact = it && it.label.toLowerCase() === q.toLowerCase();
    Cmdk.run(q && !/\s/.test(q) && it && (exact || !/^[\d'#($\[-]/.test(q)) ? it : null);
  } else if (e.key === 'Escape') { e.preventDefault(); Cmdk.close(); }
});
Cmdk.list.addEventListener('mousedown', e => { const d = e.target.closest('[data-i]'); if (d) { e.preventDefault(); Cmdk.run(Cmdk.items[+d.dataset.i]); } });
document.addEventListener('mousedown', e => { if (!Cmdk.el.hidden && !Cmdk.el.contains(e.target)) Cmdk.close(); });

// ======================================================================
// Help
// ======================================================================
const Help = {
  el: document.getElementById('help'),
  build() {
    const row = (k, d) => `<dt>${k}</dt><dd>${d}</dd>`;
    this.el.innerHTML = `<div class="help-card"><div class="ck-bar"><div class="handle"></div><b>Help</b><span>Samaltak · tiling · all text is executable</span></div>
<div class="help-cols"><div>
<h4>Mouse</h4><dl>
${row(`middle · ${OPT}click`, 'execute the word: a command, or in code the whole line as Smalltalk')}
${row('middle-drag', 'sweep a phrase and execute it, e.g. <code>Look Semaphore</code>')}
${row(`right · ${K}click`, 'look: open the class, <code>Class>>selector</code>, package or implementors; otherwise find the next match')}
${row('click in selection', 'middle/right on a selection uses the whole selection')}
${row('drag ■ in a tag', 'resize against the pane above; drop in another column to move')}
${row('click ■', 'grow the pane to fill its column; click again to restore')}
${row('drag ■ in a column', 'resize columns')}
${row('scroll bar', 'the dark strip left of every body: click or drag to jump')}
</dl>
<h4>Tags</h4><dl>
${row('name', 'first word: what the pane shows')}
${row('■', 'pale = clean, dark = unaccepted edits')}
${row('○ ● ◐ ‖', 'its green thread: waiting · handling input · busy · suspended')}
${row('right side', 'last result, errors, progress of forked processes')}
</dl></div><div>
<h4>Keyboard</h4><dl>
${row(`${K}D  ${K}P  ${K}I`, 'do it · print it (inserted, selected) · inspect it — selection or current line')}
${row(`${K}S`, 'accept the edited method')}
${row(`${K}K`, 'command line: commands, classes, methods, expressions')}
${row(`${K}.`, 'user interrupt: debugger on the busy process (or this pane’s)')}
${row(`${OPT}H ${OPT}J ${OPT}K ${OPT}L`, 'focus the pane left · below · above · right')}
${row(`${OPT}↵`, 'grow / restore the focused pane')}
${row('↵ in a tag', 'execute the word before the caret')}
${row(`${K}/ · F1 · Esc`, 'help · close')}
</dl>
<h4>Commands</h4><dl>
${row('Close Accept Get', 'pane basics (Del, Put also work)')}
${row('Senders Implementors', 'of the method, or a selected selector')}
${row('Hierarchy References', 'of the class')}
${row('Crunch Debug Kill', 'start a busy process · debug it · terminate it')}
${row('Proceed Terminate', 'in a debugger')}
${row('Newcol New Delcol Sort', 'columns')}
${row('Theme Font Help', 'Acme ↔ Graphite · proportional ↔ mono')}
</dl></div></div>
<div class="help-foot">Every pane runs in its own green Process. Try: middle-click <code>Crunch</code> in the top tag, keep typing in the Workspace, then press ${K}. — only the crunch stops.</div></div>`;
    this.el.addEventListener('mousedown', e => { if (e.target === this.el) this.toggle(false); });
  },
  toggle(on) { if (!this.el.innerHTML) this.build(); this.el.hidden = on === undefined ? !this.el.hidden : !on; },
};

// ======================================================================
// Ticker: compositor stats, glyphs, live panes
// ======================================================================
const frames = []; let lastFrame = 0, lastUI = 0, lastSlow = 0;
let statText, statCanvas;
function updateGlyphs() {
  const t = now();
  for (const p of Procs.list) if (p.kind === 'pane' && p.state === 'running' && p.until < t) p.state = 'waiting';
  for (const p of panes) {
    const pr = p.proc; const own = p.kind === 'crunch' ? p.data.proc : null;
    const frozen = pr.state === 'suspended' || !!(own && (own.state === 'running' || own.state === 'suspended'));
    let g, cls;
    if (pr.state === 'suspended' || (own && own.state === 'suspended')) { g = '‖'; cls = 'g-susp'; }
    else if (own && own.state === 'running') { g = SPIN[spinI]; cls = 'g-busy'; }
    else if (pr.state === 'running') { g = '●'; cls = 'g-run'; }
    else { g = '○'; cls = ''; }
    const k = g + cls; if (k !== p._g) { p._g = k; p.glyph.textContent = g; p.glyph.className = 'glyph ' + cls; p.glyph.title = `Process #${pr.id} '${pr.name}' · ${own ? own.state : pr.state}`; }
    if (frozen !== !!p.frozen) {
      p.frozen = frozen; p.el.classList.toggle('frozen', frozen); p.body.ta.readOnly = frozen;
      if (!frozen && p.queued.length) {
        const keys = p.queued.splice(0); let txt = '';
        for (const k2 of keys) txt = k2 === 'Enter' ? txt + '\n' : k2 === 'Backspace' ? txt.slice(0, -1) : txt + k2;
        if (txt) { const pos = p.body.value.length; p.body.insertAt(pos, txt); }
        p.note(`${keys.length} queued event${keys.length > 1 ? 's' : ''} delivered`, 'ok');
      }
    }
    p.renderStatus();
  }
}
function updateSlow() {
  for (const p of panes) if (p.spec.live) {
    if (p.kind === 'crunch') { const pr = p.data.proc; if (!pr || (pr.state === 'terminated' && p._final === pr)) continue; if (pr.state === 'terminated') p._final = pr; }
    p.refresh(true);
  }
}
function drawStats() {
  const recent = frames.slice(-30); if (!recent.length) return;
  const avg = sum(recent) / recent.length, worst = Math.max(...recent);
  statText.innerHTML = `compositor <b>${avg.toFixed(1)}</b>ms <b>${Math.min(999, Math.round(1000 / avg))}</b>fps · max ${worst.toFixed(0)} · ${Procs.list.filter(p => p.state === 'running').length}/${Procs.list.length} procs`;
  const cv = statCanvas, dpr = window.devicePixelRatio || 1, W = 60, H = 14;
  if (cv.width !== W * dpr) { cv.width = W * dpr; cv.height = H * dpr; }
  const g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, W, H);
  const cs = getComputedStyle(document.body);
  const yOf = d => H - 1 - clamp(d / 50 * (H - 2), 0, H - 2);
  g.fillStyle = cs.getPropertyValue('--rule-soft'); g.fillRect(0, Math.round(yOf(16.7)), W, 1);
  const data = frames.slice(-60);
  g.strokeStyle = cs.getPropertyValue('--muted'); g.lineWidth = 1; g.beginPath();
  data.forEach((d, i) => { const x = W - data.length + i + 0.5; i ? g.lineTo(x, yOf(d)) : g.moveTo(x, yOf(d)); }); g.stroke();
  g.fillStyle = cs.getPropertyValue('--err');
  data.forEach((d, i) => { if (d > 24) g.fillRect(W - data.length + i, yOf(d) - 1, 1.5, 2.5); });
}
function tick(t) {
  if (lastFrame) { frames.push(t - lastFrame); if (frames.length > 120) frames.shift(); }
  lastFrame = t;
  if (t - lastUI > 120) { lastUI = t; spinI = (spinI + 1) % 4; updateGlyphs(); }
  if (t - lastSlow > 250) { lastSlow = t; updateSlow(); drawStats(); }
  requestAnimationFrame(tick);
}

// ======================================================================
// Boot
// ======================================================================
const WS_TEXT = `"Select an expression, or put the caret on its line:
 ${K}D do it · ${K}P print it · ${K}I inspect it.
 Middle-click (${OPT}click) a line does it too; right-click (${K}click) a name looks it up."

100 factorial
(1 to: 20) select: [:i | i isPrime]
3/4 + (1/4)
3 @ 4 + 1
#(3 1 4 1 5 9 2 6) asSortedCollection
'samaltak' asUppercase reversed
(1 to: 10) inject: 0 into: [:sum :each | sum + each]
Transcript show: 'hello from a green thread'; cr

"Fork a Process: this pane stays live, watch Processes. ${K}. interrupts it."
[| n | n := 0. 1 to: 3000000 do: [:i | i isPrime ifTrue: [n := n + 1]]. Transcript show: 'primes below 3000000: ', n printString; cr] forkNamed: 'primes'

"For contrast, runs inline and blocks this pane until done:"
(1 to: 40000) count: [:i | i isPrime]
`;

function boot() {
  try { if (localStorage.getItem('samaltak3-theme') === 'graphite') { document.body.classList.replace('theme-acme', 'theme-graphite'); } } catch {}
  const row = document.getElementById('row');
  const brand = h('div', 'brand', row); h('i', null, brand); h('span', null, brand, 'Samaltak');
  const rowTv = rowTV = new TextView(row, { scope: 'row' }, 'row', { highlight: t => hlTag(t, false, false) });
  rowTv.setText('Newcol  Crunch  Processes  Workspace  Snapshot  Theme  Font  Help');
  h('span', null, row).id = 'rowstatus';
  const stat = h('div', null, row); stat.id = 'stat';
  statCanvas = h('canvas', null, stat); statText = h('span', null, stat);
  stat.title = 'frame time as seen by the compositor (rAF); red bars are frames over 24 ms';
  const hb = h('button', null, row, '?'); hb.id = 'helpbtn'; hb.title = `Help (${K}/)`; hb.addEventListener('click', () => Help.toggle());

  const c1 = makeCol(0.235), c2 = makeCol(0.335), c3 = makeCol(0.43);
  const add = (col, kind, name, data, w) => { const p = new Pane(kind, name, data); p.col = col; p.w = w; col.panes.push(p); col.el.appendChild(p.el); return p; };
  add(c1, 'image', 'Image', {}, 0.6);
  add(c1, 'package', 'Kernel-Processes', {}, 0.4);
  add(c2, 'class', 'Window', {}, 0.36);
  add(c2, 'method', 'Window>>open', { m: Img.lookupMethod('Window', 'open') }, 0.25);
  add(c2, 'method', 'Compositor>>composeFrame', { m: Img.lookupMethod('Compositor', 'composeFrame') }, 0.39);
  const ws = add(c3, 'workspace', 'Workspace', { text: WS_TEXT }, 0.47);
  add(c3, 'transcript', 'Transcript', { text: `Samaltak 0.1 prototype · ${Img.classes.length} classes · ${Img.all.length} methods\n1 OS thread · ${Procs.list.length} green processes · compositor on vsync\n` }, 0.17);
  add(c3, 'processes', 'Processes', {}, 0.36);
  layout();
  ws.body.ta.focus({ preventScroll: true }); ws.body.ta.setSelectionRange(0, 0); setFocused(ws);
  window.addEventListener('resize', layoutSoon);
  requestAnimationFrame(tick);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => panes.forEach(p => p.body.render()));
}
boot();

// debugging hook for automated checks
window.Samaltak = { panes, cols, Procs, look, execute, CMD, layout, userInterrupt, openPane,
  where(paneName, word, part = 'body', nth = 0) {
    const p = paneName === 'row' ? null : panes.find(x => x.name === paneName);
    const tv = paneName === 'row' ? rowTV : p[part];
    let i = -1; for (let k = 0; k <= nth; k++) i = tv.value.indexOf(word, i + 1);
    if (i < 0) return null; const r = tv.rects(i, i + word.length)[0]; return r ? [Math.round((r.left + r.right) / 2), Math.round((r.top + r.bottom) / 2)] : null;
  } };
})();
