// Code / prose editor with Smalltalk highlighting and do it / print it / inspect it.
(function (S) {
  'use strict';
  const PSEUDO = new Set(['self', 'super', 'nil', 'true', 'false', 'thisContext']);
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const BIN = '+-*/\\<>=~@%&?,';
  const sp = (c, t) => `<span class="t-${c}">${esc(t)}</span>`;

  function highlightPattern(line) {
    const re = /(\s+)|([A-Za-z_]\w*:)|([A-Za-z_]\w*)|([+\-*/\\<>=~@%&?,|]+)|(.)/g;
    let out = '', m, kind = null;
    while ((m = re.exec(line))) {
      if (m[1]) out += m[1];
      else if (m[2]) { kind = 'kw'; out += sp('pattern', m[2]); }
      else if (m[3]) out += kind ? sp('arg', m[3]) : (kind = 'u', sp('pattern', m[3]));
      else if (m[4]) { kind = 'bin'; out += sp('pattern', m[4]); }
      else out += esc(m[5]);
    }
    return out;
  }

  function highlight(src, method) {
    let out = '', i = 0;
    const n = src.length;
    if (method) {
      let e = src.indexOf('\n');
      if (e < 0) e = n;
      out += highlightPattern(src.slice(0, e));
      i = e;
    }
    while (i < n) {
      const c = src[i];
      if (c === '"') { let j = src.indexOf('"', i + 1); j = j < 0 ? n : j + 1; out += sp('comment', src.slice(i, j)); i = j; continue; }
      if (c === "'") {
        let j = i + 1;
        while (j < n) { if (src[j] === "'") { if (src[j + 1] === "'") { j += 2; continue; } j++; break; } j++; }
        if (j > n) j = n;
        out += sp('string', src.slice(i, j)); i = j; continue;
      }
      if (c === '$' && i + 1 < n) { out += sp('char', src.slice(i, i + 2)); i += 2; continue; }
      if (c === '#') {
        if (src[i + 1] === '(') { out += sp('symbol', '#('); i += 2; continue; }
        let j = i + 1;
        while (j < n && /[A-Za-z0-9_:]/.test(src[j])) j++;
        if (j === i + 1) while (j < n && BIN.includes(src[j])) j++;
        out += sp('symbol', src.slice(i, j)); i = j; continue;
      }
      if (c === '<') {
        const m = /^<[a-z]+:[^>\n]*>/.exec(src.slice(i, i + 80));
        if (m) { out += sp('pragma', m[0]); i += m[0].length; continue; }
      }
      if (/[0-9]/.test(c)) {
        const m = /^\d+r[0-9A-Z]+|^\d+(\.\d+)?(e-?\d+)?/.exec(src.slice(i));
        out += sp('number', m[0]); i += m[0].length; continue;
      }
      if (/[A-Za-z_]/.test(c)) {
        let j = i;
        while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
        const w = src.slice(i, j);
        if (src[j] === ':' && src[j + 1] !== '=') { out += sp('kw', w + ':'); i = j + 1; continue; }
        out += PSEUDO.has(w) ? sp('pseudo', w) : /^[A-Z]/.test(w) ? sp('class', w) : esc(w);
        i = j; continue;
      }
      if (c === ':' && src[i + 1] === '=') { out += sp('assign', ':='); i += 2; continue; }
      if (c === ':' && /[A-Za-z]/.test(src[i + 1] || '')) {
        let j = i + 1;
        while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
        out += sp('blockarg', src.slice(i, j)); i = j; continue;
      }
      if (c === '^') { out += sp('ret', '^'); i++; continue; }
      if (c === '|') {
        const m = /^\|(?:[ \t]*[A-Za-z_]\w*)+[ \t]*\|/.exec(src.slice(i, i + 120));
        if (m) { out += sp('temps', m[0]); i += m[0].length; continue; }
        out += sp('bin', '|'); i++; continue;
      }
      if ('[]'.includes(c)) { out += sp('block', c); i++; continue; }
      if ('(){}'.includes(c)) { out += sp('paren', c); i++; continue; }
      if (BIN.includes(c)) { out += sp('bin', c); i++; continue; }
      out += esc(c); i++;
    }
    return out + '\n';
  }

  const LH = 19, PADY = 10, PADX = 14;
  let CHW = 0;
  function charWidth() {
    if (CHW) return CHW;
    const probe = document.createElement('span');
    probe.className = 'ed-probe';
    probe.textContent = 'M'.repeat(100);
    document.body.appendChild(probe);
    CHW = probe.getBoundingClientRect().width / 100 || 7.8;
    probe.remove();
    return CHW;
  }
  const expandedLen = line => { let n = 0; for (const ch of line) n = ch === '\t' ? (Math.floor(n / 4) + 1) * 4 : n + 1; return n; };

  class Editor {
    // opts: {text, method, prose, placeholder, onAction(kind, range, ed), onAccept(ed), onChange(ed), owner}
    constructor(opts) {
      this.opts = opts;
      const el = this.el = document.createElement('div');
      el.className = 'ed ' + (opts.prose ? 'prose' : 'code');
      this.scroller = document.createElement('div');
      this.scroller.className = 'ed-scroll';
      this.inner = document.createElement('div');
      this.inner.className = 'ed-inner';
      if (!opts.prose) {
        this.pre = document.createElement('pre');
        this.pre.className = 'ed-hl';
        this.inner.appendChild(this.pre);
      }
      this.marks = document.createElement('div');
      this.marks.className = 'ed-marks';
      this.inner.appendChild(this.marks);
      const ta = this.ta = document.createElement('textarea');
      ta.spellcheck = false;
      ta.setAttribute('autocomplete', 'off');
      ta.setAttribute('autocapitalize', 'off');
      if (!opts.prose) ta.wrap = 'off';
      if (opts.placeholder) ta.placeholder = opts.placeholder;
      ta.value = opts.text || '';
      this.inner.appendChild(ta);
      this.scroller.appendChild(this.inner);
      el.appendChild(this.scroller);
      ta.addEventListener('input', () => { this.clearError(); this.refresh(); opts.onChange && opts.onChange(this); });
      ta.addEventListener('keydown', e => this.onKey(e));
      ta.addEventListener('focus', () => opts.owner && opts.owner.focus && opts.owner.focus());
      ta.addEventListener('contextmenu', e => {
        e.preventDefault(); e.stopPropagation();
        S.menu(e.clientX, e.clientY, this.menuItems());
      });
      this.refresh();
    }
    get text() { return this.ta.value; }
    set text(v) { this.ta.value = v; this.refresh(); }
    refresh() {
      const t = this.ta.value;
      if (this.opts.prose) {
        this.ta.style.height = 'auto';
        this.ta.style.height = this.ta.scrollHeight + 'px';
        return;
      }
      this.pre.innerHTML = highlight(t, this.opts.method);
      const lines = t.split('\n');
      const w = Math.max(...lines.map(expandedLen)) * charWidth() + PADX * 2 + 4;
      this.inner.style.height = (lines.length * LH + PADY * 2) + 'px';
      this.inner.style.minWidth = Math.ceil(w) + 'px';
    }
    menuItems() {
      const items = [
        { label: 'Do it', key: '⌘D', action: () => this.act('do') },
        { label: 'Print it', key: '⌘P', action: () => this.act('print') },
        { label: 'Inspect it', key: '⌘I', action: () => this.act('inspect') },
      ];
      if (this.opts.onAccept) items.push({ sep: true }, { label: 'Accept', key: '⌘S', action: () => this.opts.onAccept(this) });
      return items;
    }
    onKey(e) {
      const owner = this.opts.owner;
      if (owner && owner.busyProc) {
        // The card's own Process is busy: its events queue up instead of being handled.
        if (e.metaKey || e.ctrlKey) { if (e.key !== '.' && e.key.toLowerCase() !== 'k') e.preventDefault(); return; }
        e.preventDefault();
        if (e.key.length === 1 || e.key === 'Enter') owner.queueEvent(e.key === 'Enter' ? '\n' : e.key);
        return;
      }
      S.sched.blip(owner && owner.proc);
      const mod = e.metaKey || e.ctrlKey;
      if (mod && !e.altKey && !e.shiftKey) {
        const k = e.key.toLowerCase();
        const kind = { d: 'do', p: 'print', i: 'inspect' }[k];
        if (kind) { e.preventDefault(); e.stopPropagation(); this.act(kind); return; }
        if (k === 's') { e.preventDefault(); e.stopPropagation(); this.opts.onAccept && this.opts.onAccept(this); return; }
      }
      if (e.key === 'Tab' && !this.opts.prose && !mod) { e.preventDefault(); document.execCommand('insertText', false, '\t'); }
      if (e.key === 'Escape') this.ta.blur();
    }
    range() {
      const t = this.ta.value;
      let s = this.ta.selectionStart, e = this.ta.selectionEnd;
      if (s === e) {
        s = t.lastIndexOf('\n', s - 1) + 1;
        e = t.indexOf('\n', e);
        if (e < 0) e = t.length;
      }
      return { s, e, src: t.slice(s, e) };
    }
    act(kind) {
      const r = this.range();
      if (!r.src.trim()) { S.toast('Nothing selected'); return; }
      this.opts.onAction && this.opts.onAction(kind, r, this);
    }
    insertResult(r, str) {
      this.ta.focus({ preventScroll: true });
      this.ta.setSelectionRange(r.e, r.e);
      document.execCommand('insertText', false, ' ' + str);
      this.ta.setSelectionRange(r.e + 1, r.e + 1 + str.length);
      this.refresh();
    }
    lineOf(pos) { return this.ta.value.slice(0, pos).split('\n').length - 1; }
    colOf(pos) { const t = this.ta.value; return expandedLen(t.slice(t.lastIndexOf('\n', pos - 1) + 1, pos)); }
    // y (in editor-local px) of the middle of the line containing pos
    lineY(pos) {
      if (this.opts.prose) return this.el.offsetHeight / 2;
      return PADY + this.lineOf(pos) * LH + LH / 2;
    }
    showError(r, msg) {
      this.clearError();
      const b = this.bubble = document.createElement('div');
      b.className = 'ed-error';
      b.innerHTML = `<b>!</b><span></span>`;
      b.querySelector('span').textContent = msg;
      if (this.opts.prose) { b.style.position = 'relative'; b.style.margin = '0 12px 10px'; this.el.appendChild(b); }
      else {
        b.style.top = (PADY + (this.lineOf(r.e) + 1) * LH + 2) + 'px';
        b.style.left = (PADX + this.colOf(r.s) * charWidth() - 4) + 'px';
        this.inner.appendChild(b);
      }
      b.addEventListener('pointerdown', e => { e.stopPropagation(); this.clearError(); });
      S.sched.blip(this.opts.owner && this.opts.owner.proc);
    }
    clearError() { if (this.bubble) { this.bubble.remove(); this.bubble = null; } }
    // Briefly tint the evaluated range (whole lines).
    flash(r, cls = 'flash') {
      if (this.opts.prose) return;
      const a = this.lineOf(r.s), b = this.lineOf(r.e);
      const m = document.createElement('div');
      m.className = 'ed-mark ' + cls;
      m.style.top = (PADY + a * LH) + 'px';
      m.style.height = ((b - a + 1) * LH) + 'px';
      this.marks.appendChild(m);
      if (cls === 'flash') setTimeout(() => m.remove(), 700);
      return m;
    }
    markLine(idx) {
      this.marks.querySelectorAll('.pc').forEach(m => m.remove());
      if (idx == null) return;
      const m = document.createElement('div');
      m.className = 'ed-mark pc';
      m.style.top = (PADY + idx * LH) + 'px';
      m.style.height = LH + 'px';
      this.marks.appendChild(m);
    }
    setReadOnly(v) { this.ta.readOnly = v; this.el.classList.toggle('readonly', v); }
  }

  S.highlight = highlight;
  S.Editor = Editor;
  S.ED_LH = LH;
})(window.Sam = window.Sam || {});
