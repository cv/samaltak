// Morphic: halos, the hand (pick up / drop), parts bin, the back side of windows.
(function () {
  'use strict';
  const { h, esc, ICON } = S;
  const isWin = el => el && el.classList.contains('win');
  const labelEl = el => el.querySelector(':scope > .lbl') || el;
  S.getLabel = el => labelEl(el).textContent;
  S.setLabel = (el, t) => { labelEl(el).textContent = t; };
  const counters = {};
  S.newName = base => { counters[base] = (counters[base] || 0) + 1; return base + counters[base]; };

  // ---------- halo ----------
  const HANDLES = [
    { id: 'del', c: '#e5484d', icon: ICON.x, tip: 'Delete' },
    { id: 'grab', c: '#2b2f3d', icon: ICON.grab, tip: 'Pick up — drag anywhere', drag: true, cls: 'grab' },
    { id: 'dup', c: '#22a55b', icon: ICON.dup, tip: 'Duplicate' },
    { id: 'insp', c: '#f08c2e', icon: ICON.inspect, tip: 'Inspect' },
    { id: 'browse', c: '#13a0a8', icon: ICON.browse, tip: 'Browse class' },
    { id: 'color', c: '#f4f4f8', icon: ICON.color, tip: 'Change color' },
    { id: 'rsz', c: '#e8b10f', icon: ICON.resize, tip: 'Resize', drag: true, cls: 'rsz' },
    { id: 'rot', c: '#3b6cff', icon: ICON.rotate, tip: 'Rotate (⇧ snaps)', drag: true, cls: 'rot' },
    { id: 'flip', c: '#8b5cf6', icon: ICON.flip, tip: 'Flip window', win: true },
    { id: 'xray', c: '#0ea5e9', icon: ICON.layers, tip: 'X-ray layers', win: true },
  ];
  const haloEl = h('div', { class: 'halo' });
  const frameEl = h('div', { class: 'halo-frame' });
  const nameEl = h('div', { class: 'halo-name' });
  const hEls = {};
  haloEl.append(frameEl, nameEl);
  S.$('#halo-layer').append(haloEl);
  HANDLES.forEach((d, i) => {
    const e = h('div', { class: 'hh' + (d.cls ? ' ' + d.cls : ''), 'data-h': d.id, style: { '--c': d.c, transitionDelay: (i * 16) + 'ms' }, html: d.icon + `<span class="tip">${d.tip}</span>` });
    if (d.id === 'color') e.style.color = '#333';
    hEls[d.id] = e; haloEl.append(e);
  });

  S.halo = {
    target: null,
    show(t) {
      if (!t) return this.hide();
      this.target = t;
      const win = isWin(t);
      hEls.flip.style.display = hEls.xray.style.display = win ? '' : 'none';
      const cls = t.dataset.morph;
      nameEl.innerHTML = win ? `${esc(t._win.title)}<i>${esc(cls)}</i>` : `${esc(t.dataset.name || 'a' + cls)}<i>${esc(cls)}</i>`;
      haloEl.classList.remove('on'); void haloEl.offsetWidth;
      this.update(); haloEl.classList.add('on');
    },
    hide() { this.target = null; haloEl.classList.remove('on'); },
    update() {
      const t = this.target;
      if (!t) return;
      if (!t.isConnected || (isWin(t) && t._win.closing) || t.closest('#hand') && !S.hand.carrying || (t.closest('.front') && S.winOf(t) && S.winOf(t)._showBack) || t.closest('.win') && t.closest('.win').style.visibility === 'hidden') { this.hide(); return; }
      const r = t.getBoundingClientRect();
      const pad = 6;
      let L = r.left - pad, T = r.top - pad, R = r.right + pad, B = r.bottom + pad;
      frameEl.style.cssText = `left:${L}px;top:${T}px;width:${R - L}px;height:${B - T}px`;
      // keep handles usable for tiny morphs
      const minW = 150, minH = 118;
      if (R - L < minW) { const c = (L + R) / 2; L = c - minW / 2; R = c + minW / 2; }
      if (B - T < minH) { const c = (T + B) / 2; T = c - minH / 2; B = c + minH / 2; }
      L -= 12; T -= 12; R += 12; B += 12;
      L = S.clamp(L, 16, innerWidth - 60); R = S.clamp(R, L + 40, innerWidth - 16); T = S.clamp(T, 48, innerHeight - 60); B = S.clamp(B, T + 40, innerHeight - 16);
      const cy = (T + B) / 2;
      const pos = { del: [L, T], grab: [L + 34, T], dup: [L + 68, T], insp: [R, T], browse: [R, T + 34], color: [R, T + 68], rsz: [R, B], rot: [L, B], flip: [L, cy - 17], xray: [L, cy + 17] };
      for (const k in pos) hEls[k].style.cssText += `;left:${pos[k][0]}px;top:${pos[k][1]}px`;
      nameEl.style.left = (L + R) / 2 + 'px'; nameEl.style.top = (B + 4) + 'px';
    },
  };
  S.tickers.push(() => S.halo.update());

  function morphUnder(x, y) {
    for (const el of document.elementsFromPoint(x, y)) {
      if (el.closest('#halo-layer, #hand, .menu, .palette, .help-wrap, .xray-scene')) return null;
      if (el.classList.contains('veil') || el.classList.contains('dim') || el.classList.contains('sheen')) continue;
      const m = el.closest('[data-morph]');
      if (m) return m;
      if (el.id === 'desktop' || el.closest('#menubar, #flap')) return null;
    }
    return null;
  }
  document.addEventListener('pointerdown', e => {
    if (!(e.altKey || e.metaKey) || e.button !== 0 || S.exposing) return;
    if (e.target.closest('#halo-layer, .menu, #menubar, #flap, .help-wrap, .xray-scene')) return;
    let t = morphUnder(e.clientX, e.clientY);
    e.preventDefault(); e.stopPropagation();
    const cur = S.halo.target;
    if (cur && t && (t === cur || cur.contains(t))) {
      const up = cur.parentElement && cur.parentElement.closest('[data-morph]');
      t = up || null;
    }
    S.halo.show(t);
    if (t) { const w = S.winOf(t); if (w) S.focus(w); }
  }, true);
  document.addEventListener('pointerdown', e => {
    if (e.altKey || e.metaKey || !S.halo.target) return;
    if (e.target.closest('#halo-layer, .palette, .menu')) return;
    S.halo.hide();
  }, true);
  document.addEventListener('click', e => { if (e.altKey || e.metaKey) { e.preventDefault(); } }, true);

  // handle actions
  haloEl.addEventListener('pointerdown', e => {
    const hd = e.target.closest('.hh'); if (!hd) return;
    e.preventDefault(); e.stopPropagation();
    const t = S.halo.target; if (!t) return;
    const id = hd.dataset.h, win = isWin(t) ? t._win : null;
    if (id === 'grab') { if (win) S.beginWinDrag(win, e); else S.hand.carry(t, e); return; }
    if (id === 'rsz') return startResize(t, win, e);
    if (id === 'rot') return startRotate(t, win, e);
    hd._down = true;
  });
  haloEl.addEventListener('click', e => {
    const hd = e.target.closest('.hh'); if (!hd || !hd._down) return; hd._down = false;
    const t = S.halo.target; if (!t) return;
    const id = hd.dataset.h, win = isWin(t) ? t._win : null;
    if (id === 'del') { if (win) win.close(); else S.deleteMorph(t); S.halo.hide(); }
    else if (id === 'dup') { const c = win ? S.duplicateWindow(win) : S.duplicateMorph(t); if (c) S.halo.show(c.el || c); }
    else if (id === 'insp') S.inspectMorph(t);
    else if (id === 'browse') { if (!S.browseClass(t.dataset.morph)) S.toast(`No class ${esc(t.dataset.morph)} in the prototype image`); }
    else if (id === 'color') S.colorPalette(hd, t);
    else if (id === 'flip' && win) S.flip(win);
    else if (id === 'xray' && win) { S.halo.hide(); S.xray.open(win); }
  });

  function track(move, up) {
    const mv = e => move(e), u = e => { removeEventListener('pointermove', mv); removeEventListener('pointerup', u); if (up) up(e); };
    addEventListener('pointermove', mv); addEventListener('pointerup', u);
  }
  function startResize(t, win, e) {
    const sx = e.clientX, sy = e.clientY;
    if (win) { const w0 = win.w, h0 = win.h; track(ev => win.resize(w0 + ev.clientX - sx, h0 + ev.clientY - sy)); return; }
    const r = t.getBoundingClientRect(), s = (r.width / t.offsetWidth) || 1;
    const w0 = t.offsetWidth, h0 = t.offsetHeight;
    t.style.flex = 'none';
    track(ev => { t.style.width = Math.max(16, w0 + (ev.clientX - sx) / s) + 'px'; t.style.height = Math.max(12, h0 + (ev.clientY - sy) / s) + 'px'; if (win === null && t._onResize) t._onResize(); });
  }
  function startRotate(t, win, e) {
    const r = t.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const a0 = Math.atan2(e.clientY - cy, e.clientX - cx);
    const rot0 = win ? win.rot : +(t.dataset.rot || 0);
    track(ev => {
      let a = rot0 + (Math.atan2(ev.clientY - cy, ev.clientX - cx) - a0) * 180 / Math.PI;
      if (ev.shiftKey) a = Math.round(a / 15) * 15;
      if (Math.abs(a) < 2.5) a = 0;
      if (win) win.rot = a; else S.setRot(t, a);
    });
  }
  S.setRot = (t, a) => { t.dataset.rot = a.toFixed(1); t.style.transform = a ? `rotate(${a.toFixed(1)}deg)` : ''; };

  const COLORS = ['#ff5f6d', '#ff9f43', '#ffd84d', '#47e3b5', '#2ec4b6', '#4f8dff', '#7c6cff', '#c86bfa', '#ff7eb6', '#ffffff', '#9aa3b5', '#2b2f3d'];
  S.colorPalette = (anchor, t) => {
    S.closeMenus();
    const r = anchor.getBoundingClientRect();
    const p = h('div', { class: 'palette' }, COLORS.map(c => h('i', { style: { background: c }, onclick: () => { S.paint(t, c); S.closeMenus(); } })));
    document.body.append(p);
    p.style.left = Math.min(r.right + 10, innerWidth - 200) + 'px'; p.style.top = Math.max(40, r.top - 20) + 'px';
  };
  const hueOf = hex => { const n = parseInt(hex.slice(1), 16), r = (n >> 16) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255; const mx = Math.max(r, g, b), mn = Math.min(r, g, b); if (mx === mn) return 220; const d = mx - mn; let hh = mx === r ? (g - b) / d % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; return Math.round(hh * 60 + 360) % 360; };
  S.paint = (t, c) => {
    if (isWin(t)) { t._win.hue = hueOf(c); t.style.setProperty('--h', t._win.hue); t._win.proc.hue = t._win.hue; }
    else {
      t.style.setProperty('--mc', c);
      if (!t.matches('.m-btn, .m-label, .m-slider, .m-list, .m-swatch, .m-ellipse, .m-note')) t.style.background = `color-mix(in srgb, ${c} 22%, white)`;
    }
    t.classList.remove('morph-flash'); void t.offsetWidth; t.classList.add('morph-flash');
  };

  S.deleteMorph = t => {
    const a = t.animate([{ transform: (t.style.transform || '') + ' scale(1)', opacity: 1 }, { transform: (t.style.transform || '') + ' scale(.2)', opacity: 0 }], { duration: 260, easing: 'cubic-bezier(.5,0,.8,.4)' });
    a.onfinish = () => t.remove();
  };
  S.cloneMorph = src => {
    const c = src.cloneNode(true);
    const sc = src.querySelectorAll('canvas'), cc = c.querySelectorAll('canvas');
    sc.forEach((s, i) => { cc[i].width = s.width; cc[i].height = s.height; cc[i].getContext('2d').drawImage(s, 0, 0); });
    const st = src.querySelectorAll('textarea, input'), ct = c.querySelectorAll('textarea, input');
    st.forEach((s, i) => { ct[i].value = s.value; });
    return c;
  };
  S.duplicateMorph = t => {
    const c = S.cloneMorph(t);
    c.dataset.name = S.newName((t.dataset.morph[0].toLowerCase() + t.dataset.morph.slice(1)));
    c.querySelectorAll('.ed').forEach(ed => { ed.dataset.ws = 'dup' + Math.random().toString(36).slice(2, 7); });
    if (t.classList.contains('free')) {
      c.style.left = (parseFloat(t.style.left) || 0) + 18 + 'px'; c.style.top = (parseFloat(t.style.top) || 0) + 18 + 'px';
      t.after(c);
    } else t.after(c);
    c.animate([{ transform: (c.style.transform || '') + ' scale(.6)', opacity: 0 }, { transform: (c.style.transform || '') + ' scale(1)', opacity: 1 }], { duration: 380, easing: 'cubic-bezier(.3,1.6,.5,1)' });
    return c;
  };
  S.duplicateWindow = w => {
    const o = { x: w.x + 32, y: w.y + 32, w: w.w, h: w.h };
    const k = w.kind;
    if (k === 'workspace') return S.openWorkspace({ ...o, text: S.editorText(w.editor), title: w.title });
    if (k === 'browser') return S.openBrowser({ ...o, ...w.bstate });
    if (k === 'transcript') return S.openTranscript(o);
    if (k === 'procs') return S.openProcessMonitor(o);
    if (k === 'fractal') return S.openFractal({ ...o, title: w.title });
    S.toast('This window can\'t be duplicated'); return null;
  };

  S.inspectMorph = t => {
    const win = S.winOf(t), isW = isWin(t);
    const cls = t.dataset.morph;
    const rows = () => {
      const r = t.getBoundingClientRect();
      const own = isW ? null : t.parentElement.closest('[data-morph]');
      const lbl = t.hasAttribute('data-label') ? S.getLabel(t) : null;
      const out = [
        { name: 'self', value: isW ? `a ${cls}('${t._win.title}')` : `a ${cls}${lbl ? `('${lbl}')` : ''}` },
        { name: 'class', value: cls },
        { name: 'name', value: '#' + (t.dataset.name || '') },
        { name: 'bounds', value: `${Math.round(r.left)}@${Math.round(r.top)} corner: ${Math.round(r.right)}@${Math.round(r.bottom)}` },
        { name: 'owner', value: isW ? 'the World' : own ? `a ${own.dataset.morph}${own._win ? `('${own._win.title}')` : ''}` : (t.closest('#desktop') ? 'the World' : 'nil') },
        { name: 'submorphs', value: `an Array(${t.querySelectorAll('[data-morph]').length} morphs)` },
      ];
      if (lbl != null) out.push({ name: 'label', value: `'${lbl}'` });
      const mc = t.style.getPropertyValue('--mc'); out.push({ name: 'color', value: mc ? `Color fromString: '${mc.trim()}'` : 'Color default' });
      out.push({ name: 'rotation', value: (isW ? t._win.rot : +(t.dataset.rot || 0)).toFixed(1) + '°' });
      if (isW) {
        const w = t._win;
        out.push({ name: 'title', value: `'${w.title}'` }, { name: 'process', value: `a Process('${w.proc.name}' pid ${w.proc.pid} ${w.proc.state})` },
          { name: 'layer', value: `a CompositorLayer(z: ${S.wins.indexOf(w)} depth: ${w.s.z.x.toFixed(0)} texture: ${w.w * 2}x${w.h * 2})` }, { name: 'flipped', value: String(w.flipped) });
      } else if (win) out.push({ name: 'window', value: `a ${win.cls}('${win.title}')` }, { name: 'process', value: `a Process('${win.proc.name}' pid ${win.proc.pid} ${win.proc.state})` });
      const inp = t.matches('.m-slider') && t.querySelector('input'); if (inp) out.push({ name: 'value', value: inp.value }, { name: 'min', value: inp.min }, { name: 'max', value: inp.max });
      const items = t.querySelectorAll(':scope > .li'); if (items.length) out.push({ name: 'items', value: '#(' + [...items].slice(0, 12).map(i => `'${i.textContent}'`).join(' ') + ')' }, { name: 'selection', value: (t.querySelector('.li.sel') || {}).textContent || 'nil' });
      return out;
    };
    const nm = isW ? `a ${cls}('${t._win.title}')` : `a ${cls}${t.hasAttribute('data-label') ? `('${S.getLabel(t)}')` : ''}`;
    S.openInspector({ value: null, printString: nm, className: cls, rows, from: win, morph: '3 @ 4 + 1', title: `Inspector: ${nm}` });
  };

  // label editing
  document.addEventListener('dblclick', e => {
    const l = e.target.closest('.m-label, .m-note');
    if (!l || l.closest('#flap') || e.altKey) return;
    l.contentEditable = 'true'; l.focus();
    const sel = getSelection(), r = document.createRange(); r.selectNodeContents(l); sel.removeAllRanges(); sel.addRange(r);
  });
  document.addEventListener('focusout', e => { if (e.target.matches && e.target.matches('[contenteditable="true"]')) e.target.contentEditable = 'false'; });
  document.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey && e.target.matches && e.target.matches('.m-label[contenteditable="true"]')) { e.preventDefault(); e.target.blur(); } });

  // ---------- the hand ----------
  const handEl = S.$('#hand');
  S.hand = {
    carrying: null,
    tilt: new S.Spring(0, 220, 14, .01), lift: new S.Spring(1, 260, 18, .001),
    carry(m, e, opts = {}) {
      if (this.carrying) return;
      const fromWin = S.winOf(m);
      if (m.isConnected) {
        const r = m.getBoundingClientRect();
        this.ox = e.clientX - (r.left + r.width / 2); this.oy = e.clientY - (r.top + r.height / 2);
        if (!m.classList.contains('free')) { m.style.width = m.offsetWidth + 'px'; if (m.matches('.m-list, .pane, .ed, .fractal-view')) m.style.height = m.offsetHeight + 'px'; m.style.flex = 'none'; }
        this.origin = opts.origin || { parent: m.parentElement, next: m.nextSibling, left: m.style.left, top: m.style.top, wasFree: m.classList.contains('free') };
      } else { this.ox = 0; this.oy = 0; this.origin = null; }
      this.fromParts = !!opts.fromParts;
      m.classList.add('free');
      handEl.append(m);
      m.style.left = (-m.offsetWidth / 2) + 'px'; m.style.top = (-m.offsetHeight / 2) + 'px';
      this.carrying = m; this.x = e.clientX - this.ox; this.y = e.clientY - this.oy; this.lx = e.clientX; this.lt = performance.now();
      this.lift.snap(1).set(1.07); this.tilt.snap(0);
      if (fromWin) S.touch(fromWin);
      const mv = ev => this.move(ev), up = ev => { removeEventListener('pointermove', mv); removeEventListener('pointerup', up); this.drop(ev); };
      addEventListener('pointermove', mv); addEventListener('pointerup', up);
      this.apply();
    },
    move(e) {
      const t = performance.now(), dt = Math.max(1, t - this.lt);
      const vx = (e.clientX - this.lx) / dt * 1000; this.lx = e.clientX; this.lt = t;
      this.tilt.set(S.clamp(vx * .012, -14, 14));
      this.x = e.clientX - this.ox; this.y = e.clientY - this.oy;
      const tgt = this.dropTarget(e.clientX, e.clientY);
      if (tgt !== this.hi) { if (this.hi) this.hi.classList.remove('drop-hi'); this.hi = tgt; if (tgt && tgt.id !== 'desktop') tgt.classList.add('drop-hi'); }
    },
    dropTarget(x, y) {
      for (const el of document.elementsFromPoint(x, y)) {
        if (el.closest('#hand, #halo-layer')) continue;
        if (el.closest('#flap')) return S.$('#flap');
        if (el.classList.contains('veil')) return el.parentElement.querySelector('.wbody');
        const b = el.closest('.wbody, #desktop');
        if (b) return b;
        if (el.closest('.win')) return null;
      }
      return S.$('#desktop');
    },
    drop(e) {
      const m = this.carrying; if (!m) return;
      if (this.hi) this.hi.classList.remove('drop-hi'); this.hi = null;
      const x = e.clientX - this.ox, y = e.clientY - this.oy;
      // a color swatch paints whatever it is dropped on
      if (m.dataset.morph === 'ColorSwatch') {
        handEl.style.display = 'none';
        const under = morphUnder(e.clientX, e.clientY);
        handEl.style.display = '';
        if (under && under !== m) {
          S.paint(under, getComputedStyle(m).getPropertyValue('--mc').trim() || '#ff7a59');
          this.carrying = null;
          if (this.origin) this.restore(m); else S.deleteMorph(m);
          return this.reset();
        }
      }
      const tgt = this.dropTarget(e.clientX, e.clientY);
      this.carrying = null;
      if (!tgt || tgt.id === 'flap') { S.deleteMorph(m); this.reset(); return; }
      const r = tgt.getBoundingClientRect(), s = tgt.id === 'desktop' ? 1 : (r.width / tgt.offsetWidth || 1);
      const lx = (x - r.left) / s + tgt.scrollLeft, ly = (y - r.top) / s + tgt.scrollTop;
      tgt.append(m);
      m.style.left = (lx - m.offsetWidth / 2) + 'px'; m.style.top = (ly - m.offsetHeight / 2) + 'px';
      const rot = m.style.transform || '';
      m.animate([{ transform: rot + ' scale(1.08)' }, { transform: rot + ' scale(1)' }], { duration: 420, easing: 'cubic-bezier(.3,1.7,.5,1)' });
      const w = S.winOf(tgt); if (w) { S.touch(w); S.focus(w); }
      S.transcript(`${m.dataset.name || 'a' + m.dataset.morph} dropped into ${w ? `${w.cls} '${w.title}'` : 'the World'}\n`);
      this.reset();
    },
    restore(m) {
      const o = this.origin;
      if (o.parent && o.parent.isConnected) { o.parent.insertBefore(m, o.next && o.next.parentNode === o.parent ? o.next : null); m.style.left = o.left; m.style.top = o.top; if (!o.wasFree) m.classList.remove('free'); }
      else S.deleteMorph(m);
    },
    reset() { handEl.style.transform = ''; this.origin = null; },
    apply() {
      if (!this.carrying) return;
      handEl.style.transform = `translate(${this.x}px,${this.y}px) rotate(${this.tilt.x.toFixed(2)}deg) scale(${this.lift.x.toFixed(4)})`;
    },
  };
  S.tickers.push(dt => {
    if (!S.hand.carrying) return;
    if (performance.now() - S.hand.lt > 50) S.hand.tilt.set(0);
    S.hand.tilt.step(dt); S.hand.lift.step(dt); S.hand.apply();
  });

  // plain drag on free morphs picks them up
  let pend = null;
  document.addEventListener('pointerdown', e => {
    if (e.button || e.altKey || e.metaKey || S.hand.carrying) return;
    const f = e.target.closest('.free');
    if (!f || f.closest('#hand') || e.target.closest('input, textarea, .m-list, [contenteditable="true"], .ed')) return;
    if (S.winOf(f) && S.winOf(f).busy) return;
    pend = { f, x: e.clientX, y: e.clientY };
  }, true);
  addEventListener('pointermove', e => {
    if (!pend) return;
    if (Math.hypot(e.clientX - pend.x, e.clientY - pend.y) > 5) { const f = pend.f; pend = null; S.suppressClick = true; S.hand.carry(f, e); }
  });
  addEventListener('pointerup', () => { pend = null; setTimeout(() => { S.suppressClick = false; }, 0); });

  // ---------- parts bin ----------
  const btnPart = (label = 'Button') => h('button', { class: 'm-btn', 'data-morph': 'Button', 'data-name': S.newName('button'), 'data-label': '', 'data-action': 'partButton' }, h('span', { class: 'lbl', text: label }));
  const PARTS = [
    { name: 'Button', make: () => btnPart() },
    { name: 'Slider', make: () => h('div', { class: 'm-slider', 'data-morph': 'Slider', 'data-name': S.newName('slider') }, h('input', { type: 'range', min: 0, max: 100, value: 50 }), h('output', { text: '50' })) },
    { name: 'Label', make: () => h('div', { class: 'm-label', 'data-morph': 'Label', 'data-name': S.newName('label'), 'data-label': '', text: 'Double-click to edit' }) },
    { name: 'List', make: () => h('div', { class: 'm-list', 'data-morph': 'ListView', 'data-name': S.newName('list') }, ['Kernel', 'Graphics-GPU', 'Graphics-Canvas', 'UI-Windows', 'UI-Widgets', 'Tools', 'Demo'].map((t, i) => h('div', { class: 'li' + (i === 3 ? ' sel' : ''), text: t }))) },
    { name: 'Swatch', make: () => h('div', { class: 'm-swatch', 'data-morph': 'ColorSwatch', 'data-name': S.newName('swatch'), style: { '--mc': COLORS[Math.floor(Math.random() * 9)] } }) },
    { name: 'Ellipse', make: () => h('div', { class: 'm-ellipse', 'data-morph': 'Ellipse', 'data-name': S.newName('ellipse') }) },
    { name: 'Note', make: () => h('div', { class: 'm-note', 'data-morph': 'StickyNote', 'data-name': S.newName('note'), 'data-label': '', text: 'A note. Double-click to edit.' }) },
  ];
  S.PARTS = PARTS;
  const flap = S.$('#flap');
  const tray = h('div', { class: 'flap-tray' });
  PARTS.forEach(p => {
    const pv = p.make(); pv.removeAttribute('data-morph');
    if (p.name === 'Note') { pv.style.width = '80px'; pv.style.fontSize = '9px'; pv.style.padding = '5px 7px'; pv.textContent = 'A note…'; }
    if (p.name === 'Ellipse') { pv.style.width = '54px'; pv.style.height = '36px'; }
    const tile = h('div', { class: 'part', title: `Drag a ${p.name} out` }, h('div', { class: 'pv' }, pv), h('span', { text: p.name }));
    tile.addEventListener('pointerdown', e => {
      if (e.button) return;
      e.preventDefault();
      const sx = e.clientX, sy = e.clientY;
      const mv = ev => { if (Math.hypot(ev.clientX - sx, ev.clientY - sy) > 4) { removeEventListener('pointermove', mv); removeEventListener('pointerup', up); S.hand.carry(p.make(), ev, { fromParts: true }); } };
      const up = () => { removeEventListener('pointermove', mv); removeEventListener('pointerup', up); S.toast(`Drag the ${p.name} onto the desktop or into any window`); };
      addEventListener('pointermove', mv); addEventListener('pointerup', up);
    });
    tray.append(tile);
  });
  tray.append(h('div', { class: 'flap-hint', html: 'Drag parts into any window or onto the desktop. Drop a swatch on a widget to paint it. Drop things here to discard.' }));
  flap.append(h('div', { class: 'flap-tab', onclick: () => flap.classList.toggle('open'), html: S.ICON.up + ' Parts' }), tray);

  // ---------- back side ----------
  const listItems = el => [...el.querySelectorAll(':scope > .li')].map(x => x.textContent);
  function morphsOf(w) {
    const seen = new Set();
    return [...w.body.querySelectorAll('[data-morph]')].filter(el => !el.parentElement.closest('[data-morph]:not(.win)') || el.classList.contains('free')).map(el => {
      let n = el.dataset.name || S.newName(el.dataset.morph.toLowerCase());
      while (seen.has(n)) n += 'X';
      seen.add(n); el.dataset.name = n;
      return el;
    });
  }
  function genSource(w) {
    const ms = morphsOf(w);
    const lines = [`${w.cls} >> buildContents`, `\t"Runs in this window's Process. Edit a label or the title,`, `\t accept with ⌘S, then flip back (⟲) to see the change."`, '', `\tself title: '${w.title.replace(/'/g, "''")}'.`];
    for (const el of ms) {
      const n = el.dataset.name, c = el.dataset.morph;
      if (el.hasAttribute('data-label')) lines.push(`\t${n} := ${c} new label: '${S.getLabel(el).replace(/'/g, "''")}'.`);
      else if (c === 'Slider') { const i = el.querySelector('input'); lines.push(`\t${n} := Slider new min: ${i.min} max: ${i.max}; value: ${i.value}.`); }
      else if (c === 'ListView' && listItems(el).length) lines.push(`\t${n} := ListView new items: #(${listItems(el).slice(0, 5).map(t => /^[A-Za-z]\w*$/.test(t) ? t : `'${t}'`).join(' ')}${listItems(el).length > 5 ? ' …' : ''}).`);
      else lines.push(`\t${n} := ${c} new.`);
      if (+el.dataset.rot) lines.push(`\t${n} rotationDegrees: ${(+el.dataset.rot).toFixed(0)}.`);
    }
    lines.push(`\tself addAll: {${ms.map(e => e.dataset.name).join('. ')}}`);
    return lines.join('\n');
  }
  function applyBack(w, src) {
    let changed = 0;
    const t = src.match(/self\s+title:\s*'((?:[^']|'')*)'/);
    if (t) { const v = t[1].replace(/''/g, "'"); if (v !== w.title) { w.setTitle(v); changed++; } }
    const re = /(\w+)\s*:=\s*\w+\s+new\s+label:\s*'((?:[^']|'')*)'/g; let mm;
    while ((mm = re.exec(src))) {
      const el = w.body.querySelector(`[data-name="${mm[1]}"][data-label]`);
      const v = mm[2].replace(/''/g, "'");
      if (el && S.getLabel(el) !== v) { S.setLabel(el, v); changed++; }
    }
    return changed;
  }
  S.buildBack = w => {
    const f = S.findClass(w.cls) || S.findClass('Window');
    const layer = f.pkg.layer;
    const narrow = Math.max(w.w, w.s.W.t) < 560;
    const ed = S.makeEditor({ text: genSource(w), dark: true, method: true, name: 'buildSource', ws: w.id + 'b', onAccept: src => {
      const n = applyBack(w, src);
      renderInsp();
      S.transcript(`${w.cls}>>buildContents accepted — ${n} change${n === 1 ? '' : 's'} applied to the live window\n`);
      acc.textContent = n ? `✓ accepted · ${n} change${n === 1 ? '' : 's'} — flip back to see` : '✓ accepted · nothing changed'; acc.classList.add('on'); clearTimeout(acc._t); acc._t = setTimeout(() => acc.classList.remove('on'), 3500);
    } });
    const insp = h('div', { class: 'bins', 'data-morph': 'Inspector', 'data-name': 'stateInspector' });
    const acc = h('span', { class: 'acc' });
    function renderInsp() {
      const rows = [['self', `a ${w.cls}`], ['title', null, 'title', w.title], ['bounds', `${Math.round(w.x)}@${Math.round(w.y)} extent: ${w.w}@${w.h}`], ['process', `pid ${w.proc.pid} · ${w.proc.state}`], ['priority', String(w.proc.priority)], ['layer', `texture ${w.w * 2}×${w.h * 2}`], ['depth', `${S.wins.length - 1 - S.wins.indexOf(w)} from front`]];
      for (const el of morphsOf(w)) if (el.hasAttribute('data-label')) rows.push([el.dataset.name + ' label', null, el.dataset.name, S.getLabel(el)]);
      insp.innerHTML = '';
      for (const [k, v, key, val] of rows) {
        const valEl = key ? h('input', { value: val, 'data-k': key, spellcheck: 'false' }) : h('span', { class: 'v', text: v });
        insp.append(h('div', { class: 'brow' }, h('span', { class: 'k', text: k }), valEl));
      }
    }
    insp.addEventListener('keydown', e => { if (e.key === 'Enter') e.target.blur(); e.stopPropagation(); });
    insp.addEventListener('change', e => {
      const k = e.target.dataset.k; if (!k) return;
      if (k === 'title') w.setTitle(e.target.value);
      else { const el = w.body.querySelector(`[data-name="${k}"][data-label]`); if (el) S.setLabel(el, e.target.value); }
      S.setEditorText(ed, genSource(w));
      acc.textContent = '✓ applied — flip back to see'; acc.classList.add('on'); clearTimeout(acc._t); acc._t = setTimeout(() => acc.classList.remove('on'), 3000);
    });
    renderInsp();
    const tb = h('div', { class: 'titlebar' },
      h('span', { class: 'pdot' }), h('span', { class: 'wtitle', text: `inside ${w.cls}` }), h('span', { class: 'wkind', html: `${S.layerChip(layer)} ${esc(f.pkg.name)} · ${esc(f.cls.superclass)} subclass` }),
      h('span', { class: 'tb-spacer' }),
      h('button', { class: 'tbtn', 'data-tb': 'flip', title: 'Flip back (⌘⇧F)', html: S.ICON.flip }));
    const bcode = h('div', { class: 'bcol' }, h('div', { class: 'bhead', html: `${S.layerChip(layer)} source · ${esc(w.cls)}>>buildContents` }), ed);
    const bins = h('div', { class: 'bcol' }, h('div', { class: 'bhead', text: 'live state · edit a value' }), insp);
    const foot = h('div', { class: 'bfoot', style: { padding: '0 12px 10px' } },
      h('button', { class: 'm-btn primary', 'data-action': 'accept' }, h('span', { class: 'lbl', text: 'Accept ⌘S' })),
      h('button', { class: 'm-btn', 'data-action': 'flipBack' }, h('span', { class: 'lbl', text: 'Flip back ⟲' })), acc, h('span', { class: 'gap' }), h('span', { text: f.cls.comment.length > 70 ? f.cls.comment.slice(0, 70) + '…' : f.cls.comment }));
    w.back.innerHTML = '';
    w.back.append(tb, h('div', { class: 'backbody' + (narrow ? ' narrow' : '') }, bcode, bins), foot, h('div', { class: 'grip' }), h('div', { class: 'dim' }));
    w.back.style.pointerEvents = 'none';
    w._showBack = undefined; w._tf = null;
  };
})();
