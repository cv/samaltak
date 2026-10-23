// Code editors with Smalltalk highlighting and live evaluation (do it / print it / inspect it).
(function () {
  'use strict';
  const { h, esc } = S;
  const PSEUDO = new Set(['self', 'super', 'thisContext', 'nil', 'true', 'false']);

  function hlCode(src) {
    let out = '', i = 0; const n = src.length;
    const sp = (c, t) => `<span class="t-${c}">${esc(t)}</span>`;
    while (i < n) {
      const c = src[i];
      if (c === '"') { let j = src.indexOf('"', i + 1); j = j < 0 ? n : j + 1; out += sp('cm', src.slice(i, j)); i = j; continue; }
      if (c === "'") { let j = i + 1; while (j < n) { if (src[j] === "'") { if (src[j + 1] === "'") { j += 2; continue; } j++; break; } j++; } out += sp('str', src.slice(i, j)); i = j; continue; }
      if (c === '$' && i + 1 < n) { out += sp('chr', src.slice(i, i + 2)); i += 2; continue; }
      if (c === '#') {
        if (src[i + 1] === '(') { out += sp('sym', '#('); i += 2; continue; }
        let j = i + 1; while (j < n && /[A-Za-z0-9_:]/.test(src[j])) j++;
        if (j === i + 1) while (j < n && '+-*/\\<>=~@%|&?,'.includes(src[j])) j++;
        out += sp('sym', src.slice(i, j)); i = j; continue;
      }
      if (/[0-9]/.test(c)) { let j = i; while (j < n && /[0-9rA-Fe.]/.test(src[j])) { if (src[j] === '.' && !/[0-9]/.test(src[j + 1] || '')) break; if (src[j] === 'e' && !/[0-9-]/.test(src[j + 1] || '')) break; j++; } out += sp('num', src.slice(i, j)); i = j; continue; }
      if (/[A-Za-z_]/.test(c)) {
        let j = i; while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
        let w = src.slice(i, j), cls = null;
        if (src[j] === ':' && src[j + 1] !== '=') { j++; w += ':'; cls = 'kw'; }
        else if (PSEUDO.has(w)) cls = 'ps';
        else if (/^[A-Z]/.test(w)) cls = 'gl';
        out += cls ? sp(cls, w) : esc(w); i = j; continue;
      }
      if (c === ':' && src[i + 1] === '=') { out += sp('as', ':='); i += 2; continue; }
      if (c === ':' && /[A-Za-z]/.test(src[i + 1] || '')) { let j = i + 1; while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++; out += sp('arg', src.slice(i, j)); i = j; continue; }
      if (c === '^') { out += sp('as', '^'); i++; continue; }
      if (c === '<' && /^<primitive|^<[a-z]+:/.test(src.slice(i, i + 12))) { let j = src.indexOf('>', i); j = j < 0 ? n : j + 1; out += sp('prim', src.slice(i, j)); i = j; continue; }
      if (c === '[' || c === ']') { out += sp('br', c); i++; continue; }
      out += esc(c); i++;
    }
    return out;
  }
  S.highlight = (src, opts = {}) => {
    if (opts.plain) return esc(src) + '\n';
    if (opts.method) {
      const k = src.indexOf('\n'); const hd = k < 0 ? src : src.slice(0, k), rest = k < 0 ? '' : src.slice(k);
      return `<span class="t-hdr">${hlCode(hd)}</span>` + hlCode(rest) + '\n';
    }
    return hlCode(src) + '\n';
  };

  const meta = new WeakMap();
  let edSeq = 1;
  S.makeEditor = function (o = {}) {
    const ta = h('textarea', { class: 'ed-ta', spellcheck: 'false', wrap: 'off', autocapitalize: 'off', autocomplete: 'off', autocorrect: 'off' });
    ta.value = o.text || '';
    if (o.readOnly) ta.readOnly = true;
    const root = h('div', { class: 'ed' + (o.dark ? ' dark' : '') + (o.plain ? ' plain' : ''), 'data-morph': 'TextEditor', 'data-name': o.name || 'editor', 'data-ws': o.ws || ('ws' + (edSeq++)) },
      h('pre', { class: 'ed-hl', 'aria-hidden': 'true' }), ta, h('div', { class: 'ed-err' }));
    if (o.method) root.dataset.method = '1';
    if (o.plain) root.dataset.plain = '1';
    meta.set(root, { onAccept: o.onAccept });
    S.refreshEditor(root);
    return root;
  };
  S.edMeta = root => meta.get(root) || {};
  S.setEdMeta = (root, m) => meta.set(root, Object.assign(meta.get(root) || {}, m));
  S.refreshEditor = root => {
    const ta = root.querySelector('.ed-ta'), pre = root.querySelector('.ed-hl');
    pre.innerHTML = S.highlight(ta.value, { method: root.dataset.method === '1', plain: root.dataset.plain === '1' });
    pre.scrollTop = ta.scrollTop; pre.scrollLeft = ta.scrollLeft;
  };
  S.setEditorText = (root, text) => { const ta = root.querySelector('.ed-ta'); ta.value = text; ta.scrollTop = 0; S.refreshEditor(root); };
  S.editorText = root => root.querySelector('.ed-ta').value;

  document.addEventListener('input', e => {
    if (!e.target.classList || !e.target.classList.contains('ed-ta')) return;
    const root = e.target.parentElement;
    hideErr(root); S.refreshEditor(root); S.touch(S.winOf(root));
  });
  document.addEventListener('scroll', e => {
    if (!e.target.classList || !e.target.classList.contains('ed-ta')) return;
    const pre = e.target.parentElement.querySelector('.ed-hl');
    pre.scrollTop = e.target.scrollTop; pre.scrollLeft = e.target.scrollLeft;
    hideErr(e.target.parentElement);
    const band = e.target.parentElement.querySelector('.pcband');
    if (band) band.style.transform = `translateY(${-e.target.scrollTop}px)`;
  }, true);

  // ---------- evaluation ----------
  function findForkBlocks(src) {
    const out = []; const re = /\]\s*(fork|forkAt:\s*\S+|forkNamed:\s*'((?:[^']|'')*)')/g; let m;
    while ((m = re.exec(src))) {
      let depth = 0, j = m.index;
      for (; j >= 0; j--) { if (src[j] === ']') depth++; else if (src[j] === '[') { depth--; if (depth === 0) break; } }
      if (j >= 0) out.push({ inner: src.slice(j + 1, m.index), name: m[2] ? m[2].replace(/''/g, "'") : null });
    }
    return out;
  }
  S.run = function (src, ws, win) {
    const forks = [];
    try {
      const r = MiniST.evaluate(src, { workspace: ws, transcript: S.transcript, forked: (b, name) => forks.push({ name }) });
      if (forks.length) {
        const blocks = findForkBlocks(src);
        forks.forEach((f, i) => {
          const b = blocks[i] || { inner: '', name: f.name };
          const p = S.spawnUserProcess({ name: f.name || b.name || 'a forked Process', inner: b.inner, ws, win });
          if (i === forks.length - 1 && r.printString === '#aProcess') { r.printString = `a Process('${p.name}' pid ${p.pid})`; r.className = 'Process'; r.value = p; r.isProc = true; }
        });
      }
      return r;
    } catch (e) {
      return { error: e instanceof MiniST.STError ? e.message : 'Error: ' + (e && e.message || e) };
    }
  };

  function hideErr(root) { const b = root.querySelector('.ed-err'); if (b) b.classList.remove('show', 'ok'); }
  function bubble(root, msg, pos, ok) {
    const ta = root.querySelector('.ed-ta'), b = root.querySelector('.ed-err');
    const line = ta.value.slice(0, pos).split('\n').length;
    b.textContent = msg; b.classList.remove('show', 'ok'); void b.offsetWidth;
    b.classList.add('show'); if (ok) b.classList.add('ok');
    b.style.top = (9 + line * 18 - ta.scrollTop + 3) + 'px';
    clearTimeout(b._t); b._t = setTimeout(() => b.classList.remove('show'), ok ? 1400 : 6000);
  }
  S.edBubble = bubble;

  S.selectionOrLine = function (ta) {
    let s = ta.selectionStart, e = ta.selectionEnd;
    if (s === e) {
      const v = ta.value;
      s = v.lastIndexOf('\n', s - 1) + 1; e = v.indexOf('\n', e); if (e < 0) e = v.length;
      ta.setSelectionRange(s, e);
    }
    return { s, e, text: ta.value.slice(s, e) };
  };

  S.evalIn = function (root, mode) {
    const ta = root.querySelector('.ed-ta');
    ta.focus();
    const { e, text } = S.selectionOrLine(ta);
    if (!text.trim()) return;
    const win = S.winOf(root);
    S.touch(win);
    const res = S.run(text, root.dataset.ws || 'default', win);
    if (res.error) { bubble(root, res.error, e); return; }
    if (mode === 'print') {
      const ins = ' ' + res.printString;
      ta.setSelectionRange(e, e);
      if (!document.execCommand('insertText', false, ins)) ta.setRangeText(ins, e, e, 'end');
      ta.setSelectionRange(e + 1, e + ins.length);
      S.refreshEditor(root);
    } else if (mode === 'inspect') {
      S.openInspector({ value: res.value, printString: res.printString, className: res.className, from: win });
    } else {
      bubble(root, res.isProc ? `forked ${res.printString}` : '✓ ' + (res.printString.length > 60 ? res.printString.slice(0, 60) + '…' : res.printString), e, true);
    }
  };

  S.accept = function (root) {
    const m = S.edMeta(root);
    if (m.onAccept) m.onAccept(S.editorText(root), root);
    else S.edBubble(root, '✓ accepted', root.querySelector('.ed-ta').selectionEnd, true);
  };

  // keyboard
  document.addEventListener('keydown', e => {
    const mod = e.metaKey || e.ctrlKey;
    const root = e.target.closest && e.target.closest('.ed');
    if (!root || !mod || e.altKey) return;
    const k = e.key.toLowerCase();
    if (e.shiftKey) return;
    if (k === 'd') { e.preventDefault(); S.evalIn(root, 'do'); }
    else if (k === 'p') { e.preventDefault(); S.evalIn(root, 'print'); }
    else if (k === 'i') { e.preventDefault(); S.evalIn(root, 'inspect'); }
    else if (k === 's') { e.preventDefault(); S.accept(root); }
    else if (k === 'b') { e.preventDefault(); browseSel(root); }
  });
  document.addEventListener('keydown', e => {
    if (e.key !== 'Tab' || !e.target.classList.contains('ed-ta')) return;
    e.preventDefault(); document.execCommand('insertText', false, '\t');
  });

  function browseSel(root) {
    const ta = root.querySelector('.ed-ta');
    let t = ta.value.slice(ta.selectionStart, ta.selectionEnd).trim();
    if (!t) { const v = ta.value, p = ta.selectionStart; let a = p, b = p; while (a > 0 && /\w/.test(v[a - 1])) a--; while (b < v.length && /\w/.test(v[b])) b++; t = v.slice(a, b); }
    if (S.browseClass(t)) return;
    S.edBubble(root, `No class named ${t || '(nothing)'}`, ta.selectionEnd);
  }

  // context menu
  document.addEventListener('contextmenu', e => {
    const root = e.target.closest('.ed');
    if (!root) return;
    e.preventDefault();
    const ta = root.querySelector('.ed-ta');
    S.menu(e.clientX, e.clientY, [
      { label: 'do it', key: '⌘D', run: () => S.evalIn(root, 'do') },
      { label: 'print it', key: '⌘P', run: () => S.evalIn(root, 'print') },
      { label: 'inspect it', key: '⌘I', run: () => S.evalIn(root, 'inspect') },
      '-',
      { label: 'browse it', key: '⌘B', run: () => browseSel(root) },
      { label: 'accept', key: '⌘S', run: () => S.accept(root) },
      '-',
      { label: 'copy', key: '⌘C', run: () => { ta.focus(); document.execCommand('copy'); } },
      { label: 'select all', key: '⌘A', run: () => { ta.focus(); ta.select(); } },
    ], 'TextEditor');
  });

  // ---------- user processes (forked blocks, time-sliced) ----------
  S.spawnUserProcess = function ({ name, inner, ws, win }) {
    const p = S.newProc({ name, kind: 'user', state: 'running', priority: 30, window: win ? win.id : null, hue: 140, inner, ws, elapsed: 0, duration: 5.5 + Math.random() * 1.5, origin: win });
    S.transcript(`[${name}] pid ${p.pid} forked at priority 30 — the forking window stays responsive\n`);
    return p;
  };
  S.tickers.push(dt => {
    for (const p of S.procs) {
      if (p.kind !== 'user' || p.state !== 'running') continue;
      p.elapsed += dt;
      const prog = Math.min(1, p.elapsed / p.duration);
      if (p.origin && !p.origin.closing && !p.origin.busy) p.origin.setChip('fork', `${p.name} ${Math.round(prog * 100)}%`, prog);
      if (prog >= 1) {
        p.state = 'terminated'; p.dead = performance.now();
        if (p.origin && !p.origin.busy) p.origin.setChip(null);
        try { if (p.inner.trim()) MiniST.evaluate('[' + p.inner + '] value', { workspace: p.ws, transcript: S.transcript }); }
        catch (err) { S.transcript(`[${p.name}] Error: ${err.message}\n`); }
        S.transcript(`[${p.name}] terminated after ${p.elapsed.toFixed(1)} s of time slices\n`);
      }
    }
  });
})();
