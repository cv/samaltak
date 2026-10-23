// Boot: menubar, world menu, help, global keys, default arrangement.
(function () {
  'use strict';
  const { h, esc, ICON } = S;

  // ---------- menubar ----------
  const mb = S.$('#menubar');
  mb.innerHTML = `
    <div class="logo"><span class="gem"></span>Samaltak</div>
    <button class="mb" data-mb="world">World</button>
    <button class="mb" data-mb="tools">Tools</button>
    <div class="mb-sep"></div>
    <button class="mb" data-mb="expose" title="Spread all windows out in 3D">${ICON.expose} Exposé <span class="k">⌘E</span></button>
    <button class="mb" data-mb="xray" title="Explode the front window into its layers">${ICON.layers} X-ray <span class="k">⌘⇧X</span></button>
    <button class="mb" data-mb="flip" title="Flip the front window to its implementation">${ICON.flip} Flip <span class="k">⌘⇧F</span></button>
    <div class="mb-gap"></div>
    <div class="mb-stat" id="procstat"></div>
    <div class="mb-sep"></div>
    <div class="mb-stat" title="Compositor frame time (runs at vsync priority, independent of window Processes)">compositor <b id="ft">–</b><canvas id="ftc" width="128" height="36"></canvas></div>
    <button class="mb mb-help" data-mb="help" title="Help (?)">?</button>`;
  const worldItems = () => [
    { label: 'Workspace', run: () => S.openWorkspace({ x: 120 + Math.random() * 200, y: 90 + Math.random() * 120 }) },
    { label: 'System Browser', run: () => S.openBrowser({ x: 300 + Math.random() * 200, y: 70 + Math.random() * 100 }) },
    { label: 'Transcript', run: () => S.openTranscript({ x: 80 + Math.random() * 200, y: 400 + Math.random() * 100 }) },
    { label: 'Process Monitor', run: () => S.openProcessMonitor({ x: 700 + Math.random() * 200, y: 300 + Math.random() * 100 }) },
    { label: 'Fractal demo', run: () => S.openFractal({ x: 400 + Math.random() * 200, y: 120 + Math.random() * 100 }) },
    '-',
    { label: 'Exposé', key: '⌘E', run: () => S.expose.toggle() },
    { label: 'Parts bin', run: () => S.$('#flap').classList.toggle('open') },
    { label: 'Help', key: '?', run: () => S.help() },
  ];
  mb.addEventListener('click', e => {
    const b = e.target.closest('[data-mb]'); if (!b) return;
    const k = b.dataset.mb, r = b.getBoundingClientRect();
    if (k === 'world') S.menu(r.left, r.bottom + 4, worldItems(), 'World');
    else if (k === 'tools') S.menu(r.left, r.bottom + 4, worldItems().slice(0, 5), 'Open a tool');
    else if (k === 'expose') S.expose.toggle();
    else if (k === 'xray') { if (S.xray.w) S.xray.close(); else S.xray.open(S.focused()); }
    else if (k === 'flip') { const f = S.focused(); if (f) S.flip(f); }
    else if (k === 'help') S.help();
  });

  // world menu on empty desktop
  S.$('#desktop').addEventListener('click', e => {
    if (e.target.id !== 'desktop' || e.altKey || e.metaKey || S.exposing) return;
    S.menu(e.clientX, e.clientY, worldItems(), 'World');
  });

  // ---------- help ----------
  S.help = () => {
    if (S.$('.help-wrap')) { S.$('.help-wrap').remove(); return; }
    const r = (a, b) => `<div class="r"><span>${a}</span><span>${b}</span></div>`;
    const wrap = h('div', { class: 'help-wrap', onclick: e => { if (e.target === wrap) wrap.remove(); } },
      h('div', { class: 'help', html: `<button class="m-btn close" onclick="this.closest('.help-wrap').remove()">Close</button>
      <h2>Samaltak — Spatial Morphic</h2><div class="sub">Everything on screen is a live object you can grab. Every window runs in its own green thread; the compositor keeps motion smooth even when one is busy.</div>
      <div class="cols"><div>
        <h3>Objects</h3>
        ${r('Halo on anything', '<kbd>⌥</kbd>-click or <kbd>⌘</kbd>-click')}
        ${r('Halo on the owner', '<kbd>⌥</kbd>-click again')}
        ${r('Pick up / drop into another window', 'black handle, drag')}
        ${r('Resize · rotate', 'yellow · blue handle (<kbd>⇧</kbd> snaps)')}
        ${r('Duplicate · delete · inspect · browse', 'green · red · orange · teal')}
        ${r('Paint', 'color handle, or drop a swatch on it')}
        ${r('Build a UI', 'drag from the Parts flap')}
        ${r('Move a free widget', 'just drag it')}
        ${r('Edit a label or note', 'double-click')}
        <h3>Windows &amp; space</h3>
        ${r('Flip to the implementation', '⟲ in the title bar · <kbd>⌘⇧F</kbd>')}
        ${r('X-ray layers', '◇ in the title bar · <kbd>⌘⇧X</kbd>')}
        ${r('Exposé', '<kbd>⌘E</kbd> · <kbd>F3</kbd>')}
        ${r('World menu', 'click the desktop')}
        ${r('Close overlays / halo', '<kbd>Esc</kbd>')}
      </div><div>
        <h3>Code (every text pane)</h3>
        ${r('Do it', '<kbd>⌘D</kbd>')}
        ${r('Print it (inserted, selected)', '<kbd>⌘P</kbd>')}
        ${r('Inspect it', '<kbd>⌘I</kbd>')}
        ${r('Accept', '<kbd>⌘S</kbd>')}
        ${r('Browse class under cursor', '<kbd>⌘B</kbd>')}
        ${r('Menu', 'right-click')}
        ${r('No selection?', 'the current line is used')}
        <h3>Green threads</h3>
        ${r('Busy window', 'Fractal ▸ Render')}
        ${r('Fork a Process', '<code>[ … ] forkNamed: \'crunch\'</code>')}
        ${r('User interrupt → debugger', '<kbd>⌘.</kbd>')}
        ${r('Watch time slices', 'Process Monitor')}
        ${r('Back of a window', 'edit a label, <kbd>⌘S</kbd>, flip back')}
        <h3>Notes</h3>
        <div class="hint">Ctrl works wherever ⌘ is shown. The evaluator is a small Smalltalk subset (mini-st.js).</div>
      </div></div>` }));
    document.body.append(wrap);
  };

  // ---------- global keys ----------
  document.addEventListener('keydown', e => {
    const mod = e.metaKey || e.ctrlKey;
    const typing = e.target.closest && e.target.closest('textarea, input, [contenteditable="true"]');
    if (mod && e.key === '.') { e.preventDefault(); S.userInterrupt(); return; }
    if ((mod && !e.shiftKey && e.code === 'KeyE') || e.key === 'F3') { e.preventDefault(); S.expose.toggle(); return; }
    if (mod && e.shiftKey && e.code === 'KeyX') { e.preventDefault(); if (S.xray.w) S.xray.close(); else S.xray.open(S.focused()); return; }
    if (mod && e.shiftKey && e.code === 'KeyF') { e.preventDefault(); const f = S.focused(); if (f) S.flip(f); return; }
    if (e.key === 'Escape') {
      if (S.$('.help-wrap')) S.$('.help-wrap').remove();
      else if (S.$('.menu, .palette')) S.closeMenus();
      else if (S.xray.w) S.xray.close();
      else if (S.exposing) S.expose.off();
      else S.halo.hide();
      return;
    }
    if (!typing && e.key === '?') { e.preventDefault(); S.help(); }
  }, true);

  // ---------- stats ----------
  const ft = S.$('#ft'), ftc = S.$('#ftc').getContext('2d'), ps = S.$('#procstat');
  S.tickers.push(() => {
    if (S.FRAME % 10) return;
    const a = [...S.frameTimes].filter(Boolean); const avg = a.reduce((s, x) => s + x, 0) / (a.length || 1);
    ft.textContent = `${avg.toFixed(1)} ms`;
    ftc.clearRect(0, 0, 128, 36);
    ftc.fillStyle = 'rgba(255,255,255,.08)'; ftc.fillRect(0, 36 - 16.7 * 1.2, 128, 1);
    for (let i = 0; i < 64; i++) {
      const v = S.frameTimes[(S.FRAME + i) % 64];
      const hh = Math.min(36, v * 1.2);
      ftc.fillStyle = v > 20 ? '#ff8a6b' : '#7fe0c4';
      ftc.fillRect(i * 2, 36 - hh, 1.4, hh);
    }
    const busy = S.wins.filter(w => w.busy).length, run = S.procs.filter(p => p.state === 'running').length;
    ps.innerHTML = `<b>${S.procs.filter(p => p.state !== 'terminated').length}</b> green threads · <b>${run}</b> running${busy ? ` · <span style="color:#ffc46b">${busy} busy window${busy > 1 ? 's' : ''}</span>` : ''} · 1 OS thread`;
  });

  // ---------- boot ----------
  const sx = Math.min(1.25, innerWidth / 1440), sy = Math.min(1.25, innerHeight / 900);
  const L = (x, y, w, hh) => ({ x: Math.round(x * sx), y: Math.round(34 + (y - 34) * sy), w: Math.round(w * Math.max(.72, Math.min(1, sx))), h: Math.round(hh * Math.max(.72, Math.min(1, sy))) });
  S.openTranscript(L(34, 512, 420, 240));
  S.openBrowser(L(636, 54, 770, 410));
  S.openWorkspace(L(34, 58, 568, 430));
  S.openProcessMonitor(L(918, 474, 488, 300));
  const fr = S.openFractal(L(476, 292, 410, 468));

  // a couple of free morphs living on the desktop
  const note = h('div', { class: 'm-note free', 'data-morph': 'StickyNote', 'data-name': 'welcomeNote', 'data-label': '', text: 'Everything here is a live object. ⌥-click anything for its halo — pick it up, rotate it, drop it into another window. Flip a window to see its code.' });
  note.style.left = Math.round(1160 * sx) + 'px'; note.style.top = Math.round(778 * sy) + 'px';
  S.setRot(note, -3);
  const sw = h('div', { class: 'm-swatch free', 'data-morph': 'ColorSwatch', 'data-name': 'coralSwatch', style: { '--mc': '#ff7a59' } });
  sw.style.left = Math.round(1104 * sx) + 'px'; sw.style.top = Math.round(812 * sy) + 'px';
  S.$('#desktop').append(note, sw);

  if (innerHeight < 860) S.$('#flap').classList.remove('open');
  S.start();
  setTimeout(() => { const b = fr.body.querySelector('[data-name="renderButton"]'); if (b) S.halo.show(b); }, 700);
})();
