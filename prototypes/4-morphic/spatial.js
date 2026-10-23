// Spatial: layer x-ray and exposé.
(function () {
  'use strict';
  const { h, esc } = S;
  const HUES = { Button: '#7fb2ff', Slider: '#ffcf6e', Label: '#b5f28a', ListView: '#ff9fd0', TextEditor: '#8ef0e0', FractalView: '#ffb38a', ColorSwatch: '#ffd84d', Ellipse: '#c9b4ff', StickyNote: '#ffe680' };
  const hueFor = c => HUES[c] || '#c3cbe8';

  // ---------- x-ray ----------
  function localRects(face) {
    const fr = face.getBoundingClientRect(), s = fr.width / face.offsetWidth || 1;
    const loc = r => ({ x: (r.left - fr.left) / s, y: (r.top - fr.top) / s, w: r.width / s, h: r.height / s });
    return { fr, s, loc };
  }
  function clipTo(r, c) { const x = Math.max(r.left, c.left), y = Math.max(r.top, c.top), R = Math.min(r.right, c.right), B = Math.min(r.bottom, c.bottom); return R > x && B > y ? { left: x, top: y, right: R, bottom: B, width: R - x, height: B - y } : null; }
  const cloneFace = face => { const c = S.cloneMorph(face); c.style.pointerEvents = 'none'; c.querySelectorAll('.dim, .sheen, .veil, .grip').forEach(x => x.remove()); return c; };

  function buildPlanes(w) {
    const face = w.front, W = w.w, H = w.h;
    const { fr, loc } = localRects(face);
    // widgets
    const morphs = [...face.querySelectorAll('[data-morph]')];
    const pw = h('div', { class: 'xplane xp-widgets' });
    pw.append(h('div', { class: 'xbox', style: { left: '0', top: '0', width: W + 'px', height: H + 'px', borderColor: '#9fb4ff', borderRadius: '14px' } }, h('span', { text: w.cls, style: { background: '#9fb4ff', top: '-17px' } })));
    pw.append(h('div', { class: 'xbox', style: { left: '0', top: '0', width: W + 'px', height: '36px', borderColor: 'rgba(159,180,255,.6)', borderRadius: '14px 14px 0 0' } }));
    for (const m of morphs) {
      const r = loc(m.getBoundingClientRect()), c = hueFor(m.dataset.morph);
      if (r.w < 4 || r.h < 4 || r.y > H || r.x > W) continue;
      pw.append(h('div', { class: 'xbox', style: { left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px', borderColor: c, background: c.replace(')', '') + '14' } }, h('span', { text: m.dataset.morph, style: { background: c } })));
    }
    // display list
    const pd = h('div', { class: 'xplane xp-dl' });
    let fills = 0, glyphs = 0, images = 0;
    const all = [face, ...face.querySelectorAll('*')].slice(0, 900);
    for (const el of all) {
      if (el.closest('.dim, .sheen, .veil')) continue;
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden') continue;
      const hasBg = (cs.backgroundColor && !/rgba\(.*, 0\)$/.test(cs.backgroundColor) && cs.backgroundColor !== 'transparent') || cs.backgroundImage !== 'none';
      const br = el.getBoundingClientRect();
      const cr = clipTo(br, fr); if (!cr) continue;
      if (el.tagName === 'CANVAS') { const r = loc(cr); images++; pd.append(h('div', { class: 'xop', style: { left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px', borderColor: 'rgba(255,140,200,.9)', background: 'repeating-linear-gradient(45deg, rgba(255,140,200,.12) 0 6px, transparent 6px 12px)' } })); continue; }
      if (hasBg && br.width > 3 && br.height > 3) { const r = loc(cr); fills++; pd.append(h('div', { class: 'xop', style: { left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px', borderRadius: cs.borderRadius } })); }
    }
    const tw = document.createTreeWalker(face, NodeFilter.SHOW_TEXT);
    let n, budget = 700;
    while ((n = tw.nextNode()) && budget > 0) {
      if (!n.textContent.trim() || (n.parentElement && n.parentElement.closest('.dim, .sheen, .veil, .ed-err, textarea'))) continue;
      const clipEl = n.parentElement.closest('.ed, .tlist, .pm-rows, .m-list, .val, .bins');
      const clip = clipEl ? clipTo(clipEl.getBoundingClientRect(), fr) : fr;
      if (!clip) continue;
      const rg = document.createRange(); rg.selectNodeContents(n);
      for (const rr of rg.getClientRects()) {
        const c = clipTo(rr, clip); if (!c || c.width < 2) continue;
        const r = loc(c); glyphs++; budget--;
        pd.append(h('div', { class: 'xglyph', style: { left: r.x + 'px', top: (r.y + r.h * .18) + 'px', width: r.w + 'px', height: (r.h * .64) + 'px' } }));
      }
    }
    // gpu texture
    const pg = h('div', { class: 'xplane xp-gpu' }, cloneFace(face), h('div', { class: 'xtiles' }));
    const tx = Math.ceil(W / 32), ty = Math.ceil(H / 32);
    const dirty = new Set();
    const hot = face.querySelector('.fractal-view, .ed, .pm-rows');
    if (hot) { const r = loc(hot.getBoundingClientRect()); for (let i = 0; i < 7; i++) dirty.add(`${Math.floor((r.x + Math.random() * r.w) / 32)},${Math.floor((r.y + Math.random() * r.h) / 32)}`); }
    dirty.add('0,0'); dirty.add('1,0');
    for (const d of dirty) { const [a, b] = d.split(',').map(Number); if (a < tx && b < ty) pg.append(h('div', { class: 'xdirty', style: { left: a * 32 + 'px', top: b * 32 + 'px' } })); }
    // composite
    const pc = h('div', { class: 'xplane xp-comp' }, cloneFace(face));
    const ops = fills + glyphs + images;
    const L = S.LAYER;
    return {
      planes: [pc, pg, pd, pw],
      info: [
        { layer: 3, title: 'Compositor', sub: 'UI-Windows', d: `Composites the latest frozen texture of all ${S.wins.length} windows each vsync — <code>Compositor>>composeFrame</code>. It never waits for a window's Process.` },
        { layer: 1, title: 'Layer texture', sub: 'Graphics-GPU', d: `<code>GPUTexture</code> ${W * 2}×${H * 2} rgba8 · ${tx * ty} tiles, ${dirty.size} dirty this frame. Rasterized by compute passes: flatten → bin → coarse → fine.` },
        { layer: 2, title: 'DisplayList', sub: 'Graphics-Canvas', d: `Frozen, immutable — ${ops} ops: ${fills} FillOp · ${glyphs} GlyphRunOp · ${images} ImageOp. Handed to the compositor without copying.` },
        { layer: 4, title: 'Widgets', sub: 'UI-Widgets', d: `${morphs.length + 1} morphs. <code>Widget>>drawOn:</code> walks submorphs and draws on a Canvas — widgets never see the GPU.` },
      ].map(x => ({ ...x, color: L[x.layer].color })),
    };
  }

  S.xray = {
    w: null,
    open(w) {
      if (this.w) { const same = this.w === w; this.close(); if (same) return; }
      if (!w || w.closing) return;
      if (S.exposing) S.expose.off(w);
      S.halo.hide();
      const { planes, info } = buildPlanes(w);
      const fr = w.front.getBoundingClientRect();
      const scene = h('div', { class: 'xray-scene', onclick: () => this.close() });
      const dim = h('div', { class: 'xray-dim' });
      const group = h('div', { class: 'xgroup', style: { width: w.w + 'px', height: w.h + 'px', '--h': w.hue } });
      const anchors = planes.map(p => { const a = h('div', { class: 'xanchor', style: { left: w.w + 'px', top: (w.h * .5) + 'px' } }); p.append(a); group.append(p); return a; });
      const svgEl = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      const labels = info.map(x => h('div', { class: 'xl', html: `<div class="t"><span class="lchip" style="background:${x.color}">L${x.layer}</span>${esc(x.title)} <span style="font-weight:500;color:#9fb4ff;font-size:12px">${esc(x.sub)}</span></div><div class="d">${x.d}</div>` }));
      const lines = info.map(x => { const l = document.createElementNS('http://www.w3.org/2000/svg', 'path'); l.setAttribute('stroke', x.color); l.setAttribute('fill', 'none'); l.setAttribute('stroke-width', '1.2'); l.setAttribute('stroke-dasharray', '3 3'); svgEl.append(l); return l; });
      const dots = info.map(x => { const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle'); c.setAttribute('r', '3.5'); c.setAttribute('fill', x.color); svgEl.append(c); return c; });
      const head = h('div', { class: 'xhead', html: `<h2>X-ray · ${esc(w.title)}</h2><p>One window, exploded into the layers that produce it. Its Process draws <b>Widgets</b> onto a <b>Canvas</b>, which records a <b>DisplayList</b>; <b>Graphics-GPU</b> rasterizes that into the window's texture; the <b>Compositor</b> stacks all textures every frame. Each layer talks only to the one below.</p><p style="color:#7c86ad">Click anywhere or press <kbd>Esc</kbd> to collapse.</p>` });
      const lab = h('div', { class: 'xlabels' }, svgEl, labels);
      scene.append(dim, group, lab, head);
      document.body.append(scene);
      w.el.style.visibility = 'hidden'; w.shadow.style.visibility = 'hidden';
      const vw = innerWidth, vh = innerHeight;
      const fit = Math.min(1, 540 / w.w, 370 / w.h);
      Object.assign(this, { w, scene, dim, group, planes, anchors, labels, lines, dots, head,
        from: { cx: fr.left + fr.width / 2, cy: fr.top + fr.height / 2, s: fr.width / w.w },
        to: { cx: vw * .36, cy: vh * .52, s: fit },
        t: new S.Spring(0, 120, 17, .001) });
      this.t.set(1);
      S.$$('[data-mb="xray"]').forEach(b => b.classList.add('on'));
      document.body.classList.add('xraying');
    },
    close() {
      if (!this.w) return;
      this.t.set(0); this.closing = true; document.body.classList.remove('xraying');
      S.$$('[data-mb="xray"]').forEach(b => b.classList.remove('on'));
    },
    update(dt) {
      if (!this.w) return;
      this.t.step(dt);
      const t = S.clamp(this.t.x, -0.1, 1.15), tc = S.clamp(t, 0, 1);
      const { from, to, w } = this;
      const cx = S.lerp(from.cx, to.cx, t), cy = S.lerp(from.cy, to.cy, t), s = S.lerp(from.s, to.s, t);
      this.group.style.transform = `translate(${cx - w.w / 2}px,${cy - w.h / 2}px) perspective(2400px) rotateX(${54 * t}deg) rotateZ(${-32 * t}deg) scale(${s})`;
      const gap = 150;
      this.planes.forEach((p, i) => { p.style.transform = `translateZ(${((i - 1.5) * gap * t).toFixed(2)}px)`; p.style.opacity = i === 0 ? 1 : S.clamp(t * 1.6 - .2 * i, 0, 1); });
      this.dim.style.opacity = tc;
      this.head.style.opacity = S.clamp(t * 2 - 1, 0, 1);
      // labels in screen space, to the right of the stack
      const pts = this.anchors.map(a => { const r = a.getBoundingClientRect(); return [r.left, r.top]; });
      const lx = Math.min(innerWidth - 320, Math.max(...pts.map(p => p[0])) + 70);
      const ys = pts.map(p => p[1]);
      // keep labels from overlapping
      const order = ys.map((y, i) => i).sort((a, b) => ys[a] - ys[b]);
      const ly = []; let prev = -1e9;
      for (const i of order) { const y = Math.max(ys[i], prev + 78); ly[i] = y; prev = y; }
      this.labels.forEach((l, i) => {
        l.style.left = lx + 'px'; l.style.top = ly[i] + 'px'; l.style.opacity = S.clamp(t * 2 - 1, 0, 1);
        const [ax, ay] = pts[i];
        this.lines[i].setAttribute('d', `M${ax},${ay} C${ax + 40},${ay} ${lx - 50},${ly[i]} ${lx - 10},${ly[i]}`);
        this.lines[i].style.opacity = l.style.opacity;
        this.dots[i].setAttribute('cx', ax); this.dots[i].setAttribute('cy', ay); this.dots[i].style.opacity = l.style.opacity;
      });
      if (this.closing && this.t.x < .01) {
        this.scene.remove(); this.w.el.style.visibility = ''; this.w.shadow.style.visibility = '';
        this.w = null; this.closing = false;
      }
    },
  };
  S.tickers.push(dt => S.xray.update(dt));

  // ---------- exposé ----------
  S.expose = {
    labels: [],
    toggle() { S.exposing ? this.off() : this.on(); },
    on() {
      if (S.xray.w) S.xray.close();
      const ws = S.wins.filter(w => !w.closing);
      if (!ws.length) return;
      S.exposing = true; document.body.classList.add('exposing'); S.halo.hide();
      const n = ws.length, aw = innerWidth - 80, ah = innerHeight - 190, top = 78;
      const cols = Math.ceil(Math.sqrt(n * aw / ah * .8)), rows = Math.ceil(n / cols);
      const cw = aw / cols, ch = ah / rows;
      const order = [...ws].sort((a, b) => (a.y + a.x * .3) - (b.y + b.x * .3));
      order.forEach((w, i) => {
        const c = i % cols, r = Math.floor(i / cols);
        const inRow = Math.min(cols, n - r * cols), off = (cols - inRow) / 2;
        const cx = 40 + (c + off + .5) * cw, cy = top + (r + .5) * ch;
        const sc = Math.min(cw * .84 / w.w, ch * .78 / w.h, .62);
        w.home = { x: w.x, y: w.y };
        w.s.x.set(cx - w.w / 2); w.s.y.set(cy - w.h / 2); w.s.sc.set(sc);
        w.s.z.set(-40); w.s.ty.set((c + off - (cols - 1) / 2) * -9); w.s.tx.set(7); w.s.elev.set(.7); w.s.dim.set(0);
        w.xp = { cx, cy, sc };
        const lbl = h('div', { class: 'xp-title', html: `${esc(w.title)}<small>${esc(w.cls)} · pid ${w.proc.pid}</small>`, style: { left: cx + 'px', top: (cy + w.h * sc / 2 + 16) + 'px' } });
        document.body.append(lbl); this.labels.push(lbl);
      });
      this.banner = h('div', { class: 'expose-banner', text: 'Exposé — every window keeps running in its own Process. Click one to bring it forward. Esc to leave.' });
      document.body.append(this.banner);
      S.$$('[data-mb="expose"]').forEach(b => b.classList.add('on'));
    },
    off(pick) {
      if (!S.exposing) return;
      S.exposing = false; document.body.classList.remove('exposing');
      for (const w of S.wins) { if (w.home) { w.s.x.set(w.home.x); w.s.y.set(w.home.y); w.home = null; } w.s.tx.set(0); w.s.ty.set(0); w.xp = null; }
      this.labels.forEach(l => l.remove()); this.labels = [];
      if (this.banner) this.banner.remove();
      S.$$('[data-mb="expose"]').forEach(b => b.classList.remove('on'));
      if (pick) S.focus(pick); else S.restack();
    },
  };
  document.addEventListener('pointerdown', e => {
    if (!S.exposing) return;
    const w = S.winOf(e.target);
    if (e.target.closest('#menubar')) return;
    e.preventDefault(); e.stopPropagation();
    S.expose.off(w);
  }, true);
  document.addEventListener('pointerover', e => {
    if (!S.exposing) return;
    const w = S.winOf(e.target);
    for (const x of S.wins) if (x.xp) { const hov = x === w; x.s.z.set(hov ? 30 : -40); x.s.elev.set(hov ? 1.5 : .7); x.s.sc.set(x.xp.sc * (hov ? 1.04 : 1)); }
  });
})();
