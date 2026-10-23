// Samaltak classic prototype — remote control (docs/design.md, "Remote control").
// SamaltakCtl is the control service (snapshot, eval, wait, state) plus a virtual input device:
// input is synthesized as DOM pointer/mouse/keyboard/input events dispatched where a human's would land,
// with the browser's default actions (focus, caret, text insertion, pointer capture) emulated by the device.
'use strict';

(() => {
  const PID = 1;                                   // the virtual mouse is pointer 1, like the real one
  const MODKEY = IS_MAC ? 'metaKey' : 'ctrlKey';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const frame = () => new Promise(r => { let done = false; const f = () => { if (!done) { done = true; r(); } }; requestAnimationFrame(f); setTimeout(f, 50); });
  const frames = async n => { for (let i = 0; i < n; i++) await frame(); };
  const q = s => JSON.stringify(String(s));
  const cut = (s, n) => (s = String(s), s.length > n ? s.slice(0, n - 1) + '…' : s);
  const OPS = { '+': 'plus', '-': 'minus', '*': 'star', '/': 'slash', '\\': 'backslash', '<': 'lt', '>': 'gt', '=': 'eq', '~': 'tilde', '@': 'at', '%': 'pct', '|': 'bar', '&': 'amp', '?': 'qm', ',': 'comma', '^': 'caret', '!': 'bang' };
  const slug = s => {
    const t = String(s).replace(/[\u2003✓…]/g, ' ').trim().toLowerCase();
    return (t.replace(/[^a-z0-9_]+/g, '-').replace(/^-+|-+$/g, '') || [...t].map(c => OPS[c]).filter(Boolean).join('-')).slice(0, 40);
  };
  const visible = el => !!el && el.isConnected && el.getClientRects().length > 0;
  const fail = msg => { throw new Error(msg); };

  // ================================================================ refs
  const winOf = el => { const r = el && el.closest('.win'); return r && [...WM.wins.values()].find(w => w.root === r); };
  const wins = () => [...WM.wins.values()].filter(w => w.root.isConnected).sort((a, b) => (+b.root.style.zIndex || 0) - (+a.root.style.zIndex || 0));

  function roleOf(el) {
    if (el.dataset.role) return el.dataset.role;
    return structural(el);
  }
  // What a widget is, regardless of the name a tool gave it via data-role.
  function structural(el) {
    const c = el.classList;
    if (c.contains('ed')) return 'editor';
    if (c.contains('list') || c.contains('pb-rows')) return 'list';
    if (el.tagName === 'BUTTON' || c.contains('btn')) return 'button';
    if (el.tagName === 'CANVAS') return 'canvas';
    if (c.contains('statusbar')) return 'status';
    if (c.contains('nt-msg')) return 'message';
    if (c.contains('vsplit') && el.style.cursor !== 'default') return 'splitter';
    return null;
  }
  const firstText = el => { const t = [...el.childNodes].find(n => n.nodeType === 3 && n.textContent.trim()); return t ? t.textContent.trim() : ''; };
  function labelOf(el, role) {
    if (el.dataset.label) return el.dataset.label;
    if (el.getAttribute('aria-label')) return el.getAttribute('aria-label');
    if (role === 'editor' || role === 'list') {
      const pane = el.closest('.pane'), ph = pane && pane.querySelector(':scope > .pane-h');
      if (ph && firstText(ph)) return firstText(ph);
      if (el.classList.contains('pb-rows')) return 'Processes';
      if (el.classList.contains('nt-stack')) return 'Stack';
      if (el.closest('.browser-code, .dbg-code')) return 'code';
      if (role === 'editor') return el.classList.contains('readonly') ? 'source' : 'text';
      return 'list';
    }
    if (role === 'button') return el.textContent.trim().length > 1 ? el.textContent.trim() : el.title || el.textContent.trim() || 'button';
    if (role === 'canvas') return 'view';
    if (role === 'status') return 'status';
    if (role === 'message') return 'message';
    if (role === 'splitter') return 'split';
    return firstText(el) || (el.querySelector('[data-role]') ? '' : cut(el.textContent.trim().replace(/\s+/g, ' '), 80));
  }
  // names for refs: drop the live part of a label ("Process 'crunch' 49.5% (1,816 samples)" → process-crunch)
  const stable = s => String(s).split(/\s+/).reduce((a, t) => a.done || /\d/.test(t) ? { ...a, done: true } : { w: [...a.w, t] }, { w: [] }).w.join(' ');
  const nameOf = (el, role) => el.dataset.role ? slug(stable(labelOf(el, role))) || slug(role) : slug(labelOf(el, role)) || role;
  const itemLabel = el => {
    if (el.dataset.label) return el.dataset.label;
    const t = el.querySelector('.t') || el.querySelector('.nm > span') || el.querySelector(':scope > span:first-child');
    return (t ? t.childNodes[0] && t.childNodes[0].nodeType === 3 ? t.childNodes[0].textContent : t.textContent : el.textContent).trim();
  };
  const itemsOf = el => [...el.children].filter(c => c.matches('.li:not(.hdr), .prow, .menu-item, [data-role="item"], [data-role="row"]'));
  function claim(el, base, used) {
    if (el.dataset.ref) { used.add(el.dataset.ref); return el.dataset.ref; }
    let r = base, n = 1;
    while (used.has(r) || document.querySelector(`[data-ref="${CSS.escape(r)}"]`)) r = `${base}~${++n}`;
    used.add(r); el.dataset.ref = r; return r;
  }
  function annotateItems(listEl) {
    const used = new Set(), base = listEl.dataset.ref;
    for (const it of itemsOf(listEl)) {
      const name = it.dataset.pid || (it.dataset.role ? slug(stable(itemLabel(it))) || slug(it.dataset.role) : slug(itemLabel(it))) || 'item';
      let r = `${base}.${name}`, n = 1;
      while (used.has(r)) r = `${base}.${name}~${++n}`;
      used.add(r); it.dataset.ref = r;
      it.querySelectorAll('[data-role]').forEach(c => { c.dataset.ref = `${r}.${slug(c.dataset.role)}`; });
    }
  }
  function annotateIn(scope, prefix, used) {
    const walk = el => {
      for (const c of el.children) {
        const role = roleOf(c);
        if (role || c.dataset.ref) {
          if (c.dataset.ref) used.add(c.dataset.ref); else claim(c, `${prefix}.${nameOf(c, role)}`, used);
          if (role === 'list' || itemsOf(c).length) annotateItems(c);
          if (role !== 'editor' && role !== 'list') walk(c);
        } else walk(c);
      }
    };
    walk(scope);
  }
  function annotate() {
    const top = document.getElementById('topbar');
    if (top) {
      top.dataset.ref = 'top';
      top.querySelectorAll('.tbtn').forEach(b => { b.dataset.ref = 'top.' + slug(b.title.replace(/\(.*\)/, '')); });
    }
    if (WM.desktop) WM.desktop.dataset.ref = 'desktop';
    const help = document.getElementById('help');
    if (help) { help.dataset.ref = 'help'; const cb = help.querySelector('.tb-close'); if (cb) cb.dataset.ref = 'help.close'; }
    if (Menu.el) { Menu.el.dataset.ref = 'menu'; annotateItems(Menu.el); }
    for (const w of WM.wins.values()) {
      const r = w.root, id = w.id, used = new Set();
      r.dataset.ref = id;
      const set = (sel, name) => { const e = r.querySelector(sel); if (e) { e.dataset.ref = `${id}.${name}`; used.add(e.dataset.ref); } };
      set(':scope > .titlebar', 'title'); set('.tb-close', 'close'); set('.tb-coll', 'collapse'); set('.tb-proc', 'proc');
      set(':scope > .rz-br', 'resize'); set(':scope > .rz-r', 'resize-r'); set(':scope > .rz-b', 'resize-b'); set(':scope > .rz-l', 'resize-l');
      annotateIn(w.body, id, used);
    }
    // generic widgets outside windows (e.g. overlays other tools add)
    document.querySelectorAll('body > [data-role]:not([data-ref])').forEach(el => claim(el, nameOf(el, el.dataset.role), new Set()));
    document.querySelectorAll('body > [data-role]').forEach(el => annotateIn(el, el.dataset.ref, new Set()));
  }
  const norm = ref => String(ref).trim().replace(/^@/, '');
  function find1(ref) {
    ref = norm(ref);
    const m = ref.match(/^(.*)#(\d+)$/);
    const look = r => { const e = document.querySelector(`[data-ref="${CSS.escape(r)}"]`); return e && e.isConnected ? e : null; };
    let el = m ? null : look(ref);
    if (!el) { annotate(); el = m ? (look(m[1]) && itemsOf(look(m[1]))[+m[2]]) : look(ref); }
    return el || null;
  }
  const resolve = ref => find1(ref) || fail(`no widget @${norm(ref)} (take a snapshot to see current refs)`);
  const refOf = el => { for (let e = el; e; e = e.parentElement) if (e.dataset && e.dataset.ref) return '@' + e.dataset.ref; return null; };

  // ================================================================ snapshot
  const texts = el => { const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT), a = []; for (let t; (t = w.nextNode());) if (t.textContent.trim()) a.push(t.textContent.trim()); return a.join(' ').replace(/\s+/g, ' '); };
  function node(role, el, label, attrs = [], kids = []) { return { role, ref: el && el.dataset.ref, label, attrs: attrs.filter(Boolean), kids, el }; }
  const box = r => `[${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}]`;
  const hasFocus = el => el.contains(document.activeElement) && document.activeElement !== document.body;

  function editorNode(el, opts) {
    const ta = el.querySelector('textarea'); if (!ta) return node('editor', el, labelOf(el, 'editor'));
    const v = ta.value, s = ta.selectionStart, e = ta.selectionEnd;
    const attrs = [`lines=${v ? v.split('\n').length : 0}`, s === e ? `caret=${s}` : `sel=${s}-${e}`,
      el.classList.contains('dirty') ? 'dirty' : el.closest('.browser-code') ? 'dirty=false' : '', ta.readOnly ? 'readonly' : '', hasFocus(el) ? 'focused' : ''];
    if (!opts.text) attrs.push(`text=${q(cut(v.replace(/\s+/g, ' ').trim(), 60))}`);
    const kids = [];
    if (s !== e) kids.push(node('selection', null, cut(v.slice(s, e), 240)));
    const mk = el.querySelector('.ed-hl .mark');
    if (mk) kids.push(node('mark', null, cut(mk.textContent, 240), [[...mk.classList].find(c => c !== 'mark')]));
    if (opts.text) kids.push(...v.split('\n').map(l => ({ raw: '| ' + l })));
    return node('editor', el, labelOf(el, 'editor'), attrs, kids);
  }
  function itemNode(it) {
    const sel = it.classList.contains('sel') || it.classList.contains('selected') || it.getAttribute('aria-selected') === 'true';
    if (it.classList.contains('prow')) {
      const g = s => (it.querySelector(s) || {}).textContent || '';
      return node('row', it, itemLabel(it), [`pri=${g('.pri')}`, g('.st'), `cpu=${g('.cpu').trim()}`, sel ? 'selected' : '']);
    }
    if (it.classList.contains('menu-item')) {
      const d = it.querySelector('.d'), k = it.querySelector('.k');
      return node('item', it, itemLabel(it).replace(/^[✓\u2003]\s*/, ''), [/^✓/.test(itemLabel(it)) ? 'checked' : '', it.classList.contains('disabled') ? 'disabled' : '', k ? `key=${q(k.textContent)}` : '', d ? `desc=${q(d.textContent)}` : '']);
    }
    const inner = [...it.querySelectorAll('[data-role]')].map(c => node(c.dataset.role, c, c.dataset.label || '', genericAttrs(c, c.dataset.role)));
    return node(it.dataset.role || 'item', it, itemLabel(it), [sel ? 'selected' : '', it.dataset.state || '', it.classList.contains('mod') ? 'modified' : ''], inner);
  }
  function listNode(el, depth, opts) {
    const items = itemsOf(el), sel = items.find(i => i.classList.contains('sel') || i.classList.contains('selected'));
    const kids = depth > 0 ? items.slice(0, opts.maxItems).map(itemNode) : [];
    if (depth > 0 && items.length > opts.maxItems) kids.push(node('more', null, `${items.length - opts.maxItems} more items`));
    return node('list', el, labelOf(el, 'list'), [sel ? `sel=${q(itemLabel(sel))}` : '', `n=${items.length}`, hasFocus(el) ? 'focused' : ''], kids);
  }
  function genericAttrs(el, role) {
    const a = [];
    if (el.classList.contains('on') || el.getAttribute('aria-pressed') === 'true') a.push('on');
    if (el.classList.contains('sel') || el.classList.contains('selected') || el.getAttribute('aria-selected') === 'true') a.push('selected');
    if (el.disabled || el.classList.contains('disabled')) a.push('disabled');
    if (el.classList.contains('primary')) a.push('default');
    if (el.dataset.state) a.push(el.dataset.state);
    if (el.dataset.value != null) a.push(`value=${q(el.dataset.value)}`);
    if (role === 'canvas') { const r = el.getBoundingClientRect(); a.push(`${Math.round(r.width)}x${Math.round(r.height)}`); }
    return a;
  }
  function widgets(scope, depth, opts) {
    const out = [];
    const walk = el => {
      for (const c of el.children) {
        if (!visible(c) || c.id === 'remote-ptr' || c.closest('.titlebar')) continue;
        const role = roleOf(c);
        if (!role) { walk(c); continue; }
        let n;
        const kind = structural(c);
        if (kind === 'editor' || kind === 'list') {
          n = kind === 'editor' ? editorNode(c, opts) : listNode(c, depth - 1, opts);
          if (c.dataset.role) n.role = c.dataset.role;
        }
        else if (role === 'status' || role === 'message') n = node(role, c, cut(texts(c), 140));
        else {
          n = node(role, c, role === 'button' ? (c.textContent.trim() || c.title) : labelOf(c, role), genericAttrs(c, role));
          if (role !== 'button' && depth > 1) n.kids = widgets(c, depth - 1, opts);
        }
        if (opts.bounds) n.attrs.push(box(c.getBoundingClientRect()));
        out.push(n);
      }
    };
    walk(scope);
    return out;
  }
  function windowNode(w, depth, opts) {
    const p = w.proc, coll = w.root.classList.contains('collapsed');
    const attrs = [`kind=${w.kind}`, box({ x: w.x, y: w.y, width: w.root.offsetWidth, height: w.root.offsetHeight }), WM.active === w ? 'focused' : '', coll ? 'collapsed' : '',
      w.busy ? 'busy' : '', w.susp ? 'suspended' : '', p ? `process=#${p.pid} ${Sched.displayState(p)}` : ''];
    const kids = [];
    if (depth > 0 && !coll) {
      kids.push({ raw: `controls @${w.id}.title @${w.id}.close @${w.id}.collapse @${w.id}.proc @${w.id}.resize` });
      kids.push(...widgets(w.body, depth, opts));
    }
    return node('window', w.root, w.title || '', attrs, kids);
  }
  function menuNode(depth) {
    const t = Menu.el.querySelector('.menu-title');
    const kids = depth > 0 ? [...Menu.el.children].filter(c => !c.classList.contains('menu-title') && !c.classList.contains('menu-sep'))
      .map(c => c.classList.contains('menu-head') ? node('head', null, c.textContent) : itemNode(c)) : [];
    return node('menu', Menu.el, t ? t.textContent : '', [box(Menu.el.getBoundingClientRect())], kids);
  }
  function tree(opts) {
    annotate();
    const depth = opts.depth == null ? 9 : opts.depth;
    if (opts.window || opts.ref) {
      const el = resolve(opts.window || opts.ref), w = WM.wins.get(el.dataset.ref);
      if (w) return [windowNode(w, depth, opts)];
      if (el === Menu.el) return [menuNode(depth)];
      const role = roleOf(el);
      if (role === 'editor') return [editorNode(el, { ...opts, text: opts.text !== false })];
      if (role === 'list') return [listNode(el, depth, opts)];
      if (el.matches('.li, .prow, .menu-item, [data-role="item"], [data-role="row"]')) return [itemNode(el)];
      return [node(role || 'widget', el, labelOf(el, role || ''), genericAttrs(el, role), widgets(el, depth, opts))];
    }
    const out = [];
    const de = document.documentElement;
    out.push({ raw: `screen ${innerWidth}x${innerHeight} theme=${de.dataset.theme} type=${de.dataset.type} focus=${WM.active ? '@' + WM.active.id : 'desktop'} processes=${Sched.procs.length} busy=${Sched.runnable().filter(p => p.kind !== 'system').length}` });
    const top = document.getElementById('topbar');
    if (top) {
      const st = top.querySelector('.stat');
      const stat = st ? st.innerText.replace(/compositor/i, '').replace(/\s+/g, ' ').trim() : '';
      out.push(node('topbar', top, 'nuuk.image', [stat ? q(stat) : '', tag && tag.classList.contains('on') ? 'remote' : ''],
        depth > 0 ? [...top.querySelectorAll('.tbtn')].map(b => node('button', b, b.title.replace(/\s*\(.*\)/, ''))) : []));
    }
    const help = document.getElementById('help');
    if (help && !help.hidden) out.push(node('help', help, (help.querySelector('.title') || {}).textContent || 'help', [], depth > 0 ? [node('button', help.querySelector('.tb-close'), 'close')] : []));
    if (Menu.el) out.push(menuNode(depth));
    const toast = document.getElementById('toast');
    if (toast && toast.classList.contains('on')) out.push(node('toast', null, toast.textContent));
    document.querySelectorAll('body > [data-role]').forEach(el => { if (visible(el)) out.push(node(el.dataset.role, el, labelOf(el, el.dataset.role), genericAttrs(el), widgets(el, depth, opts))); });
    for (const w of wins()) out.push(windowNode(w, depth, opts));
    out.push(node('desktop', WM.desktop, 'World menu on click'));
    return out;
  }
  function format(nodes, ind = '') {
    let s = '';
    for (const n of nodes) {
      if (n.raw) { s += ind + n.raw + '\n'; continue; }
      s += `${ind}${n.role}${n.ref ? ' @' + n.ref : ''}${n.label !== '' && n.label != null ? ' ' + q(n.label) : ''}${n.attrs.length ? ' ' + n.attrs.join(' ') : ''}\n`;
      if (n.kids.length) s += format(n.kids, ind + '  ');
    }
    return s;
  }
  function flat(nodes, out = []) { for (const n of nodes) { if (!n.raw) out.push(n); if (n.kids) flat(n.kids, out); } return out; }

  // ================================================================ indicator: top-bar tag + fake pointer
  let tag = null, ptr = null, hideT = 0, tagT = 0;
  function indicate(cmd) {
    if (!tag) {
      tag = h('span', { id: 'remote-tag', title: 'A remote session is driving this image' }, h('i'), 'remote');
      const top = document.getElementById('topbar');
      if (top) top.insertBefore(tag, top.querySelector('.tbtn'));
    }
    tag.classList.add('on', 'flash'); tag.title = `A remote session is driving this image — last: ${cmd}`;
    clearTimeout(tagT); tagT = setTimeout(() => tag.classList.remove('flash'), 220);
  }
  function pointerTo(x, y) {
    if (!ptr) {
      ptr = h('div', { id: 'remote-ptr', 'aria-hidden': 'true', html: '<svg viewBox="0 0 12 18"><path d="M1 1v14l3.6-3.4 2.6 5.6 2.3-1.1-2.6-5.4H12z" fill="var(--ink)" stroke="var(--win)" stroke-width="1.1" stroke-linejoin="round"/></svg>' });
      ptr.style.transform = `translate(${innerWidth / 2}px, ${innerHeight / 2}px)`;
      document.body.append(ptr);
      ptr.getBoundingClientRect();
    }
    ptr.classList.add('on');
    ptr.style.transform = `translate(${x - 1}px, ${y - 1}px)`;
    clearTimeout(hideT); hideT = setTimeout(() => ptr.classList.remove('on'), 4000);
  }
  function ring(x, y) {
    const r = h('div', { class: 'remote-ring', 'aria-hidden': 'true', style: { left: x + 'px', top: y + 'px' } });
    document.body.append(r); setTimeout(() => r.remove(), 400);
  }

  // ================================================================ virtual input device
  const vp = { x: innerWidth / 2, y: innerHeight / 2, buttons: 0, capture: null, dispatching: 0, anchor: null, ta: null, suppress: false };
  const EP = Element.prototype, oSet = EP.setPointerCapture, oRel = EP.releasePointerCapture, oHas = EP.hasPointerCapture;
  EP.setPointerCapture = function (id) { if (vp.dispatching && id === PID) { vp.capture = this; return; } return oSet.call(this, id); };
  EP.releasePointerCapture = function (id) { if (vp.dispatching && id === PID) { if (vp.capture === this) vp.capture = null; return; } return oRel.call(this, id); };
  EP.hasPointerCapture = function (id) { if (id === PID && vp.capture === this) return true; return oHas.call(this, id); };

  function modsOf(m) {
    const list = Array.isArray(m) ? m : String(m || '').split('+').filter(Boolean);
    const o = { metaKey: false, ctrlKey: false, shiftKey: false, altKey: false };
    for (const k of list.map(s => s.toLowerCase())) {
      if (['meta', 'cmd', 'command', 'mod', '⌘'].includes(k)) o[MODKEY] = true;
      else if (['ctrl', 'control'].includes(k)) o.ctrlKey = true;
      else if (k === 'shift') o.shiftKey = true;
      else if (['alt', 'option', 'opt'].includes(k)) o.altKey = true;
    }
    return o;
  }
  function send(target, type, init, Ctor) {
    vp.dispatching++;
    try { return target.dispatchEvent(new Ctor(type, { bubbles: true, cancelable: true, composed: true, view: window, ...init })); }
    finally { vp.dispatching--; }
  }
  const BTN = { left: 0, middle: 1, right: 2 }, BTNS = [1, 4, 2];
  function mouseInit(x, y, button, mods, detail) {
    return { clientX: x, clientY: y, screenX: x, screenY: y, button, buttons: vp.buttons, detail, ...mods,
      pointerId: PID, pointerType: 'mouse', isPrimary: true, width: 1, height: 1, pressure: vp.buttons ? 0.5 : 0 };
  }
  const at = (x, y) => document.elementFromPoint(x, y) || document.body;
  function caretAt(ta, x, y) {
    const cp = document.caretPositionFromPoint && document.caretPositionFromPoint(x, y);
    if (cp && cp.offsetNode === ta) return cp.offset;
    return ta.value.length;
  }
  function wordAround(v, i) {
    let s = i, e = i; const w = c => /[A-Za-z0-9_:]/.test(c || '');
    while (s > 0 && w(v[s - 1])) s--; while (e < v.length && w(v[e])) e++;
    return [s, e];
  }
  function focusTargetOf(el) {
    if (el.matches('textarea, input')) return el;
    return el.querySelector('textarea, input') || el.closest('textarea, input, select, button, [tabindex], a[href]') || el.querySelector('[tabindex]');
  }
  function press(x, y, button, mods, detail) {
    const t = at(x, y);
    vp.buttons |= BTNS[button]; vp.x = x; vp.y = y; vp.capture = null; vp.ta = null;
    const i = mouseInit(x, y, button, mods, detail);
    vp.suppress = !send(t, 'pointerdown', i, PointerEvent);
    if (vp.suppress) return t;
    if (send(t, 'mousedown', i, MouseEvent)) {        // default action: focus and caret, like the browser
      const f = t.closest('textarea, input, select, button, [tabindex], a[href]');
      if (f) {
        f.focus({ preventScroll: true });
        if (f.tagName === 'TEXTAREA' && button === 0) {
          const pos = caretAt(f, x, y);
          if (detail === 2) { const [s, e] = wordAround(f.value, pos); f.setSelectionRange(s, e); }
          else if (mods.shiftKey) f.setSelectionRange(Math.min(f.selectionStart, pos), Math.max(f.selectionEnd, pos));
          else f.setSelectionRange(pos, pos);
          vp.ta = f; vp.anchor = f.selectionStart;
        }
      } else if (document.activeElement && document.activeElement !== document.body) document.activeElement.blur();
    }
    if (button === 2) send(t, 'contextmenu', i, MouseEvent);
    return t;
  }
  function move(x, y, mods) {
    vp.x = x; vp.y = y;
    const t = vp.capture || at(x, y), i = mouseInit(x, y, 0, mods, 0);
    send(t, 'pointermove', i, PointerEvent);
    if (!vp.suppress) send(vp.capture || t, 'mousemove', i, MouseEvent);
    if (vp.ta && vp.buttons & 1) { const p = caretAt(vp.ta, x, y); vp.ta.setSelectionRange(Math.min(vp.anchor, p), Math.max(vp.anchor, p), p < vp.anchor ? 'backward' : 'forward'); }
  }
  function release(x, y, button, mods, detail, downT) {
    vp.buttons &= ~BTNS[button];
    const t = vp.capture || at(x, y), i = mouseInit(x, y, button, mods, detail);
    send(t, 'pointerup', i, PointerEvent);
    if (!vp.suppress) send(t, 'mouseup', i, MouseEvent);
    vp.capture = null; vp.suppress = false; vp.ta = null;
    if (button === 0) {
      let c = t; while (c && !c.contains(downT)) c = c.parentElement;   // click goes to the common ancestor
      send(c && c.isConnected ? c : downT.isConnected ? downT : t, 'click', i, MouseEvent);
    }
  }

  // where a human would click: a visible point of the widget (raising its window if it is covered)
  function scrollIntoParent(el) {
    const stop = el.closest('.win, .menu, #help, #topbar') || document.body;
    for (let p = el.parentElement; p && p !== stop; p = p.parentElement) {
      if (p.scrollHeight <= p.clientHeight + 1) continue;
      const oy = getComputedStyle(p).overflowY; if (oy !== 'auto' && oy !== 'scroll') continue;
      const pr = p.getBoundingClientRect(), r = el.getBoundingClientRect();
      if (r.top < pr.top) p.scrollTop -= pr.top - r.top; else if (r.bottom > pr.bottom) p.scrollTop += Math.min(r.bottom - pr.bottom, r.top - pr.top);
    }
  }
  function grabOf(el) {
    const w = WM.wins.get(el.dataset.ref);
    if (w) return w.root.querySelector('.titlebar .title');
    if (el.classList.contains('ed')) return el.querySelector('textarea') || el;
    return el;
  }
  function hitPoint(el) {
    const r = el.getBoundingClientRect();
    const x0 = Math.max(0, r.left), x1 = Math.min(innerWidth - 1, r.right), y0 = Math.max(0, r.top), y1 = Math.min(innerHeight - 1, r.bottom);
    if (x1 <= x0 || y1 <= y0) return null;
    const ok = (x, y) => { const t = document.elementFromPoint(x, y); return t && (t === el || (el !== WM.desktop && el.contains(t))); };
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    if (ok(cx, cy)) return { x: Math.round(cx), y: Math.round(cy) };
    for (const n of [5, 9, 17]) for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
      const x = x0 + (x1 - x0) * (i + 0.5) / n, y = y0 + (y1 - y0) * (j + 0.5) / n;
      if (ok(x, y)) return { x: Math.round(x), y: Math.round(y) };
    }
    return null;
  }
  async function pointOf(target, raise = true) {
    if (target && typeof target === 'object' && 'x' in target) return { x: +target.x, y: +target.y, el: null };
    const el = resolve(target);
    if (el.classList.contains('disabled') || el.disabled) fail(`@${norm(target)} is disabled`);
    const g = grabOf(el);
    scrollIntoParent(g);
    let p = hitPoint(g);
    if (!p && raise) {
      const w = winOf(g);
      if (w && WM.active !== w) {
        const tp = hitPoint(w.root.querySelector('.titlebar .title')) || hitPoint(w.root);
        if (tp) { await clickAt(tp.x, tp.y, {}); p = hitPoint(g); }
      }
    }
    if (!p) {
      const r = g.getBoundingClientRect(), over = winOf(document.elementFromPoint(clamp(r.x + r.width / 2, 0, innerWidth - 1), clamp(r.y + r.height / 2, 0, innerHeight - 1)));
      fail(`@${norm(target)} is not visible (${over && over !== winOf(g) ? `covered by @${over.id}; move or collapse it` : 'collapsed or off-screen'})`);
    }
    return { ...p, el };
  }
  async function travel(x, y) { pointerTo(x, y); await sleep(api.pace); }
  async function clickAt(x, y, o) {
    const button = BTN[o.button] != null ? BTN[o.button] : +(o.button || 0), mods = modsOf(o.mods);
    await travel(x, y); ring(x, y);
    const n = o.double ? 2 : 1;
    let t;
    for (let k = 1; k <= n; k++) { t = press(x, y, button, mods, k); release(x, y, button, mods, k, t); }
    if (o.double) send(at(x, y), 'dblclick', mouseInit(x, y, button, mods, 2), MouseEvent);
    await frames(2);
    return t;
  }

  // keyboard
  const CODES = { ' ': 'Space', '.': 'Period', ',': 'Comma', '/': 'Slash', ';': 'Semicolon', "'": 'Quote', '[': 'BracketLeft', ']': 'BracketRight', '-': 'Minus', '=': 'Equal', '\\': 'Backslash', '`': 'Backquote' };
  const NAMED = { esc: 'Escape', escape: 'Escape', enter: 'Enter', return: 'Enter', tab: 'Tab', backspace: 'Backspace', delete: 'Delete', del: 'Delete', space: ' ',
    up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight', arrowup: 'ArrowUp', arrowdown: 'ArrowDown', arrowleft: 'ArrowLeft', arrowright: 'ArrowRight',
    home: 'Home', end: 'End', pageup: 'PageUp', pagedown: 'PageDown', plus: '+' };
  function parseCombo(combo) {
    const s = String(combo);
    const parts = s.length > 1 && s.endsWith('+') ? [...s.slice(0, -2).split('+'), '+'] : s.split('+');
    let key = parts.pop(); const mods = modsOf(parts);
    key = NAMED[key.toLowerCase()] || key;
    if (key.length === 1 && mods.shiftKey && /[a-z]/.test(key)) key = key.toUpperCase();
    return { key, mods };
  }
  const codeOf = k => /^[a-z]$/i.test(k) ? 'Key' + k.toUpperCase() : /^\d$/.test(k) ? 'Digit' + k : CODES[k] || k;
  const editable = el => el && el.matches && el.matches('textarea, input') && !el.readOnly && !el.disabled;
  function insert(ta, text) {
    if (!document.execCommand('insertText', false, text)) {
      const s = ta.selectionStart; ta.setRangeText(text, s, ta.selectionEnd, 'end');
      ta.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
    }
  }
  function keyDefault(t, key, m) {
    const mod = m[MODKEY], ta = t && t.matches && t.matches('textarea, input') ? t : null;
    if (mod && key.toLowerCase() === 'a' && ta) { ta.select(); return; }
    if (!ta || m.ctrlKey || m.metaKey) return;
    const v = ta.value, s = ta.selectionStart, e = ta.selectionEnd;
    const lineStart = i => v.lastIndexOf('\n', i - 1) + 1, lineEnd = i => { const k = v.indexOf('\n', i); return k < 0 ? v.length : k; };
    const go = p => { p = clamp(p, 0, v.length); if (m.shiftKey) ta.setSelectionRange(Math.min(s, p), Math.max(e, p)); else ta.setSelectionRange(p, p); };
    if (key.length === 1 && !m.altKey && editable(ta)) insert(ta, key);
    else if (key === 'Enter' && editable(ta)) insert(ta, '\n');
    else if (key === 'Backspace' && editable(ta)) document.execCommand('delete') || (s === e ? ta.setRangeText('', Math.max(0, s - 1), s, 'end') : ta.setRangeText('', s, e, 'end'));
    else if (key === 'Delete' && editable(ta)) document.execCommand('forwardDelete');
    else if (key === 'ArrowLeft') go(s === e || m.shiftKey ? s - 1 : s);
    else if (key === 'ArrowRight') go(s === e || m.shiftKey ? e + 1 : e);
    else if (key === 'Home') go(lineStart(s));
    else if (key === 'End') go(lineEnd(e));
    else if (key === 'ArrowUp' || key === 'ArrowDown') {
      const ls = lineStart(s), col = s - ls;
      if (key === 'ArrowUp') { if (ls === 0) return go(0); const ps = lineStart(ls - 1); go(Math.min(ps + col, ls - 1)); }
      else { const le = lineEnd(s); if (le >= v.length) return go(v.length); const ns = le + 1; go(Math.min(ns + col, lineEnd(ns))); }
    }
  }
  function keystroke(key, mods) {
    const t = document.activeElement || document.body;
    const init = { key, code: codeOf(key), keyCode: key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0, ...mods };
    if (send(t, 'keydown', init, KeyboardEvent)) {
      if (key.length === 1 && !mods.metaKey && !mods.ctrlKey) send(t, 'keypress', { ...init, charCode: key.charCodeAt(0) }, KeyboardEvent);
      keyDefault(document.activeElement || t, key, mods);
    }
    send(document.activeElement || t, 'keyup', init, KeyboardEvent);
  }
  function revealCaret() {                         // typing scrolls the caret into view, as in the browser
    const a = document.activeElement;
    if (a && a.tagName === 'TEXTAREA') { const { selectionStart: s, selectionEnd: e, selectionDirection: d } = a; a.blur(); a.focus(); a.setSelectionRange(s, e, d); }
  }
  async function focusRef(ref) {
    const el = resolve(ref), f = focusTargetOf(el);
    if (!f) fail(`@${norm(ref)} cannot take keyboard focus`);
    const w = winOf(f);
    if (w && WM.active !== w) {                     // a human would click the window first; keep the pane's selection
      const tp = hitPoint(w.root.querySelector('.titlebar .title'));
      if (tp) await clickAt(tp.x, tp.y, {});
    }
    if (document.activeElement !== f) f.focus({ preventScroll: true });
    return f;
  }

  // ================================================================ commands
  async function cmd(name, f) { indicate(name); return f(); }
  const api = {
    pace: 110,
    snapshot(o = {}) {
      return cmd('snapshot', () => {
        if (typeof o === 'string') o = { ref: o };
        return format(tree({ maxItems: 60, ...o })).trimEnd();
      });
    },
    find(text) {
      return cmd('find', () => {
        const t = String(text).toLowerCase();
        return flat(tree({ maxItems: 1e9 })).filter(n => n.ref && (String(n.label).toLowerCase().includes(t) || n.ref.toLowerCase().includes(t)))
          .map(n => ({ ref: '@' + n.ref, role: n.role, label: n.label }));
      });
    },
    click(target, o = {}) {
      return cmd('click', async () => {
        const p = await pointOf(target);
        const t = await clickAt(p.x, p.y, o);
        return { ok: true, at: [p.x, p.y], hit: refOf(t), focus: WM.active ? '@' + WM.active.id : null };
      });
    },
    dblclick(target, o = {}) { return api.click(target, { ...o, double: true }); },
    rightclick(target, o = {}) { return api.click(target, { ...o, button: 2 }); },
    type(target, text, o = {}) {
      return cmd('type', async () => {
        const f = target != null ? await focusRef(target) : document.activeElement;
        if (f && f.matches('textarea, input')) {
          if (o.replace) f.select();
          else if (o.at === 'end') f.setSelectionRange(f.value.length, f.value.length);
          else if (o.at === 'start') f.setSelectionRange(0, 0);
          else if (typeof o.at === 'number') f.setSelectionRange(o.at, o.at);
          const r = f.getBoundingClientRect(); pointerTo(r.left + 12, r.top + 12);
        }
        for (const ch of String(text)) keystroke(ch === '\n' ? 'Enter' : ch === '\t' ? 'Tab' : ch, modsOf(o.mods));
        revealCaret();
        await frames(1);
        const a = document.activeElement;
        return { ok: true, typed: String(text).length, focus: refOf(a), caret: a && a.selectionStart != null ? a.selectionStart : null };
      });
    },
    key(combo, target, o = {}) {
      return cmd('key', async () => {
        if (target) await focusRef(target);
        const combos = Array.isArray(combo) ? combo : [combo];
        for (const c of combos) { const { key, mods } = parseCombo(c); keystroke(key, mods); await frames(1); }
        revealCaret();
        await frames(1);
        return { ok: true, focus: refOf(document.activeElement), window: WM.active ? '@' + WM.active.id : null };
      });
    },
    drag(from, to, o = {}) {
      return cmd('drag', async () => {
        const a = await pointOf(from);
        let b;
        if (to && typeof to === 'object' && ('dx' in to || 'dy' in to)) b = { x: a.x + (+to.dx || 0), y: a.y + (+to.dy || 0) };
        else b = await pointOf(to, false);
        const mods = modsOf(o.mods), steps = o.steps || 10;
        await travel(a.x, a.y);
        const t = press(a.x, a.y, 0, mods, 1);
        for (let i = 1; i <= steps; i++) { const x = a.x + (b.x - a.x) * i / steps, y = a.y + (b.y - a.y) * i / steps; move(x, y, mods); pointerTo(x, y); await frame(); }
        release(b.x, b.y, 0, mods, 1, t);
        await frames(2);
        const w = a.el && (WM.wins.get(a.el.dataset.ref) || (a.el.matches('.rz, .titlebar') && winOf(a.el)));
        return { ok: true, from: [a.x, a.y], to: [Math.round(b.x), Math.round(b.y)], ...(w ? { bounds: api._bounds(w.id) } : {}) };
      });
    },
    resize(target, o = {}) {
      const el = resolve(target), w = WM.wins.get(el.dataset.ref) || winOf(el) || fail(`@${norm(target)} is not a window`);
      const dx = o.w != null ? o.w - w.w : +o.dw || +o.dx || 0, dy = o.h != null ? o.h - w.h : +o.dh || +o.dy || 0;
      return api.drag(`${w.id}.resize`, { dx, dy });
    },
    select(target, spec) {
      return cmd('select', async () => {
        const el = resolve(target);
        if (itemsOf(el).length || roleOf(el) === 'list' || el === Menu.el) {
          const want = String(spec && spec.text || spec).toLowerCase();
          const its = itemsOf(el);
          const it = its.find(i => itemLabel(i).replace(/^[✓\u2003]\s*/, '').toLowerCase() === want) || its.find(i => itemLabel(i).toLowerCase().includes(want))
            || fail(`no item ${q(spec)} in @${norm(target)}`);
          annotate();
          return api.click('@' + it.dataset.ref);
        }
        const ta = await focusRef(target);
        const v = ta.value;
        let s, e;
        if (spec === 'all') { s = 0; e = v.length; }
        else if (spec === 'end') s = e = v.length;
        else if (spec === 'start') s = e = 0;
        else if (spec && typeof spec === 'object' && 'from' in spec) { s = +spec.from; e = spec.to == null ? s : +spec.to; }
        else if (spec && typeof spec === 'object' && 'line' in spec) { const ls = v.split('\n'); const n = +spec.line - 1; s = ls.slice(0, n).join('\n').length + (n ? 1 : 0); e = s + (ls[n] || '').length; }
        else {
          const txt = String(spec && spec.text || spec); let k = -1;
          for (let i = 0; i <= (spec && spec.nth || 0); i++) k = v.indexOf(txt, k + 1);
          if (k < 0) fail(`text ${q(txt)} not found in @${norm(target)}`);
          s = k; e = k + txt.length;
        }
        ta.setSelectionRange(s, e);
        ta.dispatchEvent(new Event('select', { bubbles: true }));
        const r = ta.getBoundingClientRect(); pointerTo(r.left + 12, r.top + 12);
        await frames(1);
        return { ok: true, from: s, to: e, text: cut(v.slice(s, e), 200) };
      });
    },
    scroll(target, o = {}) {
      return cmd('scroll', async () => {
        const p = await pointOf(target);
        await travel(p.x, p.y);
        const t = at(p.x, p.y), dy = o.dy != null ? +o.dy : 120, dx = +o.dx || 0;
        if (send(t, 'wheel', { clientX: p.x, clientY: p.y, deltaX: dx, deltaY: dy, deltaMode: 0 }, WheelEvent)) {
          for (let s = t; s && s !== document.body; s = s.parentElement) {
            const cs = getComputedStyle(s);
            if ((s.scrollHeight > s.clientHeight && /auto|scroll/.test(cs.overflowY)) || s.tagName === 'TEXTAREA') { s.scrollBy(dx, dy); break; }
          }
        }
        await frames(2);
        return { ok: true };
      });
    },
    eval(source) {
      return cmd('eval', () => {
        const src = String(source), fk = detectFork(src);
        if (fk) { const p = spawnForked(fk, null, { source: src }); return { printString: procPrint(p), pid: p.pid }; }
        try {
          const r = MiniST.evaluate(src, { transcript: s => TranscriptBuf.append(s), workspace: 'remote', forked: (b, name) => Eval.opaqueFork(name, null) });
          return { printString: r.printString, className: r.className };
        } catch (err) { return { error: (err && err.message) || String(err) }; }
      });
    },
    wait(cond = {}, timeout = 5000) {
      return cmd('wait', async () => {
        if (typeof cond === 'string') cond = cond.startsWith('@') ? { ref: cond } : { text: cond };
        if (typeof cond === 'number') cond = { ms: cond };
        const t0 = performance.now();
        if (cond.frames) await frames(+cond.frames);
        if (cond.ms) await sleep(+cond.ms);
        const allText = () => document.body.innerText + '\n' + [...document.querySelectorAll('textarea')].map(t => t.value).join('\n');
        const holds = () => (!cond.ref || visible(find1(cond.ref)))
          && (!cond.gone || !visible(find1(cond.gone)))
          && (!cond.text || allText().includes(cond.text))
          && (!cond.title || wins().some(w => (w.title || '').includes(cond.title)))
          && (!cond.idle || Sched.runnable().filter(p => p.kind !== 'system').length === 0);
        while (!holds()) {
          if (performance.now() - t0 > timeout) fail(`wait timed out after ${timeout} ms: ${JSON.stringify(cond)}`);
          await frame();
        }
        return { ok: true, ms: Math.round(performance.now() - t0) };
      });
    },
    _bounds(ref) {
      const el = resolve(ref), w = WM.wins.get(el.dataset.ref);
      if (w) return { x: w.x, y: w.y, w: w.root.offsetWidth, h: w.root.offsetHeight };
      const r = el.getBoundingClientRect();
      return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) };
    },
    bounds(ref) { return cmd('bounds', () => api._bounds(ref)); },
    state() {
      return cmd('state', () => {
        annotate();
        const de = document.documentElement, a = document.activeElement;
        return {
          viewport: [innerWidth, innerHeight], theme: de.dataset.theme, type: de.dataset.type,
          focus: WM.active ? '@' + WM.active.id : null, focusedWidget: a && a !== document.body ? refOf(a) : null,
          menu: Menu.el ? (Menu.el.querySelector('.menu-title') || {}).textContent || '' : null,
          help: !document.getElementById('help').hidden,
          windows: wins().map(w => ({ ref: '@' + w.id, title: w.title, kind: w.kind, bounds: api._bounds(w.id), focused: WM.active === w,
            collapsed: w.root.classList.contains('collapsed'), busy: !!w.busy, process: w.proc ? { pid: w.proc.pid, state: Sched.displayState(w.proc) } : null })),
          processes: Sched.procs.map(p => ({ pid: p.pid, name: p.name, priority: p.priority, kind: p.kind, state: Sched.displayState(p), cpu: +(p.cpu || 0).toFixed(1), window: p.win ? '@' + p.win : null })),
        };
      });
    },
    isolate(ref) {                                   // screenshot one window's layer: hide the windows above it
      document.body.classList.toggle('remote-solo', !!ref);
      document.querySelectorAll('.remote-solo-keep').forEach(e => e.classList.remove('remote-solo-keep'));
      if (ref) { const el = resolve(ref), w = WM.wins.get(el.dataset.ref) || winOf(el); if (w) w.root.classList.add('remote-solo-keep'); }
      return true;
    },
    help() {
      return 'snapshot({ref,depth,text,bounds}) find(text) click(ref|{x,y},{button,mods,double}) dblclick rightclick type(ref,text,{at,replace}) key(combo,ref) drag(ref,{dx,dy}|ref) resize(ref,{w,h}|{dw,dh}) select(ref,{from,to}|text|{line}|"all"|"end") scroll(ref,{dy}) eval(src) wait({ref,gone,text,title,idle,frames,ms},timeout) bounds(ref) state()';
    },
  };
  window.SamaltakCtl = api;
})();
