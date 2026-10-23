// Tools: Workspace, Transcript, System Browser, Inspector, Process Monitor, Fractal demo, Notifier.
(function () {
  'use strict';
  const { h, esc } = S;
  const m = s => s.replace(/^\n/, '').replace(/\n\s*$/, '');

  // ---------- class library: FakeImage plus local prototype classes ----------
  const packages = JSON.parse(JSON.stringify(FakeImage.packages));
  const pkg = n => packages.find(p => p.name === n);
  const add = (pk, c) => pkg(pk).classes.push(c);
  packages.splice(1, 0, { name: 'Kernel-Collections', layer: 0, comment: 'Collections.', classes: [
    { name: 'Interval', superclass: 'SequenceableCollection', ivars: ['start', 'stop', 'step'], comment: 'I am an arithmetic progression.', protocols: { enumerating: { 'do: aBlock': m(`
do: aBlock
	| i |
	i := start.
	[i <= stop] whileTrue: [
		aBlock value: i.
		i := i + step]`) } } }] });
  add('UI-Widgets', { name: 'Label', superclass: 'Widget', ivars: ['label', 'color'], comment: 'I show a line of text. Double-click me to edit.', protocols: { drawing: { 'drawSelfOn: aCanvas': m(`
drawSelfOn: aCanvas
	aCanvas
		drawString: label
		at: bounds origin
		font: self theme font
		color: color`) } } });
  add('UI-Widgets', { name: 'Slider', superclass: 'Widget', ivars: ['value', 'min', 'max', 'action'], comment: 'I let you pick a number by dragging.', protocols: { events: { 'mouseMove: anEvent': m(`
mouseMove: anEvent
	value := (min + ((anEvent position x - bounds left) / bounds width * (max - min))) rounded.
	action value: value.
	self changed`) } } });
  add('UI-Widgets', { name: 'ListView', superclass: 'Widget', ivars: ['items', 'selection', 'scrollOffset'], comment: 'I show a scrollable list of items.', protocols: { events: { 'mouseUp: anEvent': m(`
mouseUp: anEvent
	selection := self itemAt: anEvent position.
	self changed: #selection`) } } });
  add('UI-Widgets', { name: 'ColorSwatch', superclass: 'Widget', ivars: ['color'], comment: 'Drop me onto any widget to paint it.', protocols: { dropping: { 'droppedOn: aWidget': m(`
droppedOn: aWidget
	aWidget color: color.
	self returnToOrigin`) } } });
  add('UI-Widgets', { name: 'Ellipse', superclass: 'Widget', ivars: ['color'], comment: 'I am a shape.', protocols: { drawing: { 'drawSelfOn: aCanvas': m(`
drawSelfOn: aCanvas
	aCanvas fillPath: (Path ellipseIn: bounds) paint: (RadialGradient on: color)`) } } });
  add('UI-Widgets', { name: 'StickyNote', superclass: 'Label', ivars: [], comment: 'A label on paper.', protocols: {} });
  add('UI-Widgets', { name: 'FractalView', superclass: 'Widget', ivars: ['pixels', 'maxIterations', 'palette', 'center', 'scale'], comment: 'I render the Mandelbrot set row by row in my window\'s Process.', protocols: {
    rendering: {
      render: m(`
render
	"Runs in the owning window's Process. The compositor keeps
	 showing the last published DisplayList, so dragging stays smooth."

	0 to: self height - 1 do: [:row |
		self renderRow: row.
		self publishRows]`),
      'renderRow: y': m(`
renderRow: y
	| ci |
	ci := self imaginaryAt: y.
	0 to: self width - 1 do: [:x |
		| n |
		n := self escapeTimeAt: (self realAt: x) @ ci max: maxIterations.
		pixels at: y * self width + x + 1 put: (palette at: n)]`),
      'escapeTimeAt: c max: limit': m(`
escapeTimeAt: c max: limit
	| z n |
	z := 0 @ 0.
	n := 0.
	[n < limit and: [(z x squared + z y squared) < 4]] whileTrue: [
		z := (z x squared - z y squared + c x) @ (2 * z x * z y + c y).
		n := n + 1].
	^n`),
    },
  } });
  add('Tools', { name: 'Inspector', superclass: 'Widget', ivars: ['object', 'fields', 'selection'], comment: 'I show the instance variables of any object.', protocols: { accessing: { 'object: anObject': m(`
object: anObject
	object := anObject.
	fields := anObject class allInstVarNames.
	self changed`) } } });
  add('Tools', { name: 'TranscriptView', superclass: 'TextEditor', ivars: ['stream'], comment: 'I show the Transcript stream.', protocols: { streaming: { 'show: aString': m(`
show: aString
	stream nextPutAll: aString.
	self changed`) } } });
  add('Tools', { name: 'Notifier', superclass: 'Widget', ivars: ['process', 'contexts'], comment: 'I appear when a Process is interrupted or fails.', protocols: { actions: { proceed: m(`
proceed
	process resume.
	self window close`) } } });
  add('Tools', { name: 'FractalWindow', superclass: 'Window', ivars: ['view', 'renderButton', 'resetButton', 'itersSlider', 'paletteList'], comment: 'A small demo app built from UI-Widgets.', protocols: { building: { buildContents: '(generated on the back of the window)' } } });
  S.packages = packages;
  S.findClass = name => { for (const p of packages) for (const c of p.classes) if (c.name === name) return { cls: c, pkg: p }; return null; };
  S.methodSource = (cname, sel) => {
    const f = S.findClass(cname); if (!f) return null;
    for (const pr of Object.values(f.cls.protocols)) for (const [k, v] of Object.entries(pr)) if (k.split(' ')[0] === sel || k === sel) return v;
    return null;
  };
  S.layerChip = layer => `<span class="lchip" style="background:${S.LAYER[layer].color}">L${layer}</span>`;

  // ---------- Workspace ----------
  const WS_TEXT = `"Samaltak Workspace — select text (or put the cursor on a line) and
 ⌘D do it · ⌘P print it · ⌘I inspect it · right-click for the menu"

100 factorial
(1 to: 20) select: [:i | i isPrime]
3/4 + (1/4)
3 @ 4 + 1
#(3 1 4 1 5 9 2 6) asSortedCollection asArray
'Samaltak' reversed asUppercase
(1 to: 10) inject: 0 into: [:a :b | a + b]
Transcript show: 'hello from the Workspace'; cr
3 zork

"Green threads: fork a busy Process, then keep dragging and flipping
 windows. It shows up in the Process Monitor. ⌘. interrupts it."
[| sum | sum := 0. 1 to: 400 do: [:i | sum := sum + (i raisedTo: 3)]. Transcript show: 'crunched '; print: sum; cr] forkNamed: 'crunch'

"Halos: ⌥-click (or ⌘-click) anything — a button, a list, a window."
`;
  S.openWorkspace = (o = {}) => S.openWindow({
    kind: 'workspace', cls: 'Workspace', title: o.title || 'Workspace', hue: 32, x: o.x ?? 60, y: o.y ?? 80, w: o.w || 560, h: o.h || 420, minW: 300, minH: 200,
    build(w, body) {
      w.editor = S.makeEditor({ text: o.text ?? WS_TEXT, ws: w.id, name: 'editor' });
      body.append(w.editor, h('div', { class: 'edfoot', html: '<span><b>⌘D</b>do it</span><span><b>⌘P</b>print it</span><span><b>⌘I</b>inspect it</span><span><b>⌘.</b>interrupt</span>' }));
    },
  });

  // ---------- Transcript ----------
  S.openTranscript = (o = {}) => S.openWindow({
    kind: 'transcript', cls: 'TranscriptView', title: 'Transcript', hue: 205, x: o.x ?? 60, y: o.y ?? 520, w: o.w || 420, h: o.h || 250, minW: 260, minH: 140,
    build(w, body) {
      const ed = S.makeEditor({ text: S.transcriptLog, plain: true, name: 'transcript', ws: w.id });
      body.append(ed);
      const ta = ed.querySelector('.ed-ta');
      const sink = s => {
        const atEnd = ta.scrollTop + ta.clientHeight >= ta.scrollHeight - 30;
        const a = ta.selectionStart, b = ta.selectionEnd;
        ta.value += s; S.refreshEditor(ed);
        ta.setSelectionRange(a, b);
        if (atEnd) { ta.scrollTop = ta.scrollHeight; S.refreshEditor(ed); }
        S.touch(w);
      };
      S.transcriptSinks.add(sink);
      w.onClose = () => S.transcriptSinks.delete(sink);
      requestAnimationFrame(() => { ta.scrollTop = ta.scrollHeight; S.refreshEditor(ed); });
    },
  });

  // ---------- System Browser ----------
  S.openBrowser = (o = {}) => S.openWindow({
    kind: 'browser', cls: 'Browser', title: 'System Browser', hue: 168, x: o.x ?? 620, y: o.y ?? 60, w: o.w || 760, h: o.h || 440, minW: 520, minH: 300,
    build(w, body) {
      const st = { pkg: o.pkg || 'UI-Windows', cls: o.cls || 'Compositor', proto: o.proto || null, sel: o.sel || 'composeFrame' };
      w.bstate = st;
      const lists = { p: h('div', { class: 'pane tlist', 'data-morph': 'ListView', 'data-name': 'packageList' }), c: h('div', { class: 'pane tlist', 'data-morph': 'ListView', 'data-name': 'classList' }), r: h('div', { class: 'pane tlist', 'data-morph': 'ListView', 'data-name': 'protocolList' }), s: h('div', { class: 'pane tlist', 'data-morph': 'ListView', 'data-name': 'methodList' }) };
      const crumbs = h('div', { class: 'crumbs' });
      const ed = S.makeEditor({ name: 'codePane', ws: w.id, method: true, onAccept: (src) => {
        const acc = crumbs.querySelector('.acc'); acc.classList.add('on'); setTimeout(() => acc.classList.remove('on'), 1800);
        const sel = src.split('\n')[0].trim();
        S.transcript(`Browser: compiled ${st.cls}>>${sel.split(/\s+/)[0]} (prototype: not really) — running processes pick it up on their next send\n`);
      } });
      body.append(h('div', { class: 'browser-top' }, lists.p, lists.c, lists.r, lists.s), crumbs, ed);
      const sortedPk = [...packages].sort((a, b) => b.layer - a.layer);
      function render() {
        const P = pkg(st.pkg) || sortedPk[0];
        let html = '<div class="phead">Packages · by layer</div>', lastL = null;
        for (const p of sortedPk) {
          if (lastL !== null && p.layer !== lastL) html += '<div class="lay-sep"></div>';
          lastL = p.layer;
          html += `<div class="li${p.name === st.pkg ? ' sel' : ''}" data-v="${p.name}">${S.layerChip(p.layer)}${esc(p.name)}</div>`;
        }
        lists.p.innerHTML = html;
        const C = P.classes.find(c => c.name === st.cls);
        lists.c.innerHTML = '<div class="phead">Classes</div>' + P.classes.map(c => `<div class="li${C && c.name === C.name ? ' sel' : ''}" data-v="${c.name}">${esc(c.name)}</div>`).join('');
        const protos = C ? Object.keys(C.protocols) : [];
        lists.r.innerHTML = '<div class="phead">Protocols</div>' + (C ? [`<div class="li${!st.proto ? ' sel' : ''}" data-v="">-- all --</div>`] : []).concat(protos.map(p => `<div class="li${p === st.proto ? ' sel' : ''}" data-v="${esc(p)}">${esc(p)}</div>`)).join('');
        const meths = C ? Object.entries(C.protocols).filter(([p]) => !st.proto || p === st.proto).flatMap(([, ms]) => Object.keys(ms)) : [];
        lists.s.innerHTML = '<div class="phead">Methods</div>' + meths.map(k => `<div class="li${k.split(' ')[0] === st.sel ? ' sel' : ''}" data-v="${esc(k.split(' ')[0])}">${esc(k.split(' ')[0])}</div>`).join('');
        let src = '';
        if (C && st.sel) src = S.methodSource(C.name, st.sel) || '';
        else if (C) {
          src = `${C.superclass} subclass: #${C.name}\n\tinstanceVariableNames: '${C.ivars.join(' ')}'\n\tclassVariableNames: ''\n\tpackage: '${P.name}'\n\n"${C.comment}"`;
        } else src = `"${P.comment}"`;
        ed.dataset.method = C && st.sel ? '1' : '';
        S.setEditorText(ed, src);
        const lc = S.LAYER[P.layer].color;
        crumbs.innerHTML = `<span class="lchip" style="background:${lc}">L${P.layer}</span><b>${esc(P.name)}</b>${C ? ' › ' + esc(C.name) : ''}${st.sel ? ' › ' + esc(st.sel) : ''}` +
          `<span class="layers" title="layer stack: each layer only talks to the one below">${[0, 1, 2, 3, 4, 5].map(l => `<i class="${l === P.layer ? 'on' : ''}" style="height:${4 + l * 2}px;background:${S.LAYER[l].color};color:${S.LAYER[l].color}"></i>`).join('')}</span>` +
          `<span class="hint" style="margin-left:6px">${P.layer > 0 ? 'talks only to L' + (P.layer - 1) + ' ' + esc(S.LAYER[P.layer - 1].name) : 'the VM core'}</span><span class="acc">✓ accepted</span>`;
        for (const l of Object.values(lists)) { const s = l.querySelector('.sel'); if (s && (s.offsetTop < l.scrollTop || s.offsetTop > l.scrollTop + l.clientHeight - 20)) l.scrollTop = s.offsetTop - 40; }
      }
      w.browserRender = render;
      body.addEventListener('click', e => {
        const li = e.target.closest('.li'); if (!li || w.busy) return;
        const v = li.dataset.v, list = li.parentElement;
        if (list === lists.p) { st.pkg = v; st.cls = (pkg(v).classes[0] || {}).name; st.proto = null; st.sel = null; }
        else if (list === lists.c) { st.cls = v; st.proto = null; st.sel = null; }
        else if (list === lists.r) { st.proto = v || null; st.sel = null; }
        else if (list === lists.s) { st.sel = v; }
        else return;
        render();
      });
      render();
    },
  });
  S.browseClass = (name, sel) => {
    const alias = { Window: 'Window', Workspace: 'Workspace', Browser: 'Browser', TextEditor: 'TextEditor' };
    const f = S.findClass(alias[name] || name);
    if (!f) return false;
    let w = S.wins.find(x => x.kind === 'browser' && !x.closing);
    if (!w) w = S.openBrowser({ pkg: f.pkg.name, cls: f.cls.name, sel: sel || null });
    else { Object.assign(w.bstate, { pkg: f.pkg.name, cls: f.cls.name, proto: null, sel: sel || null }); w.browserRender(); S.focus(w); }
    w.s.elev.set(1.7); setTimeout(() => S.restack(), 300);
    return true;
  };

  // ---------- Inspector ----------
  let inspN = 0;
  S.openInspector = ({ value, printString, className, rows, title, from, morph }) => {
    const fr = from && !from.closing ? from : S.focused();
    const x = fr ? fr.x + fr.w - 150 + (inspN % 4) * 24 : 300, y = fr ? fr.y + 50 + (inspN % 4) * 24 : 200;
    inspN++;
    return S.openWindow({
      kind: 'inspector', cls: 'Inspector', title: title || `Inspector: ${printString.length > 34 ? printString.slice(0, 34) + '…' : printString}`, hue: 280,
      x: S.clamp(x, 10, innerWidth - 400), y: S.clamp(y, 44, innerHeight - 380), w: 400, h: 340, minW: 300, minH: 220,
      build(w, body) {
        const getRows = () => rows ? rows() : MiniST.inspect(value);
        const list = h('div', { class: 'pane tlist', 'data-morph': 'ListView', 'data-name': 'fieldList' });
        const val = h('div', { class: 'pane val', 'data-morph': 'Label', 'data-name': 'valuePane' });
        const ed = S.makeEditor({ text: morph ? `"evaluate here — e.g."\n${morph}` : `"self = ${printString.replace(/"/g, "''")}"\n`, ws: w.id, name: 'evalPane' });
        body.append(h('div', { class: 'insp' }, list, val), ed);
        ed.style.flex = '0 0 72px';
        let sel = 0;
        const render = () => {
          const rs = getRows();
          list.innerHTML = '<div class="phead">' + esc(className) + '</div>' + rs.map((r, i) => `<div class="li${i === sel ? ' sel' : ''}" data-i="${i}">${esc(r.name)}</div>`).join('');
          val.textContent = rs[sel] ? rs[sel].value : '';
        };
        list.addEventListener('click', e => { const li = e.target.closest('.li'); if (li) { sel = +li.dataset.i; render(); } });
        render();
        if (rows) { const iv = setInterval(() => { if (w.closing) clearInterval(iv); else render(); }, 500); }
      },
    });
  };

  // ---------- Process Monitor ----------
  S.openProcessMonitor = (o = {}) => S.openWindow({
    kind: 'procs', cls: 'ProcessBrowser', title: 'Process Monitor', hue: 258, x: o.x ?? 900, y: o.y ?? 500, w: o.w || 500, h: o.h || 320, minW: 420, minH: 200,
    build(w, body) {
      const rowsEl = h('div', { class: 'pm-rows' });
      const foot = h('div', { class: 'pm-foot' });
      body.append(h('div', { class: 'pane', style: { flex: '1', display: 'flex', flexDirection: 'column', minHeight: '0' }, 'data-morph': 'ListView', 'data-name': 'processList' },
        h('div', { class: 'pm-head', html: '<span></span><span>Process</span><span>pri</span><span>state</span><span style="text-align:right">cpu</span><span>time slices</span>' }), rowsEl), foot);
      let selPid = null;
      const btnDebug = h('button', { class: 'm-btn', 'data-morph': 'Button', 'data-name': 'debugButton', 'data-label': '', 'data-action': 'pmDebug' }, h('span', { class: 'lbl', text: 'Debug' }));
      const btnTerm = h('button', { class: 'm-btn', 'data-morph': 'Button', 'data-name': 'terminateButton', 'data-label': '', 'data-action': 'pmTerminate' }, h('span', { class: 'lbl', text: 'Terminate' }));
      const stat = h('span');
      foot.append(btnDebug, btnTerm, h('span', { class: 'gap' }), stat);
      w.pmSel = () => S.procs.find(p => p.pid === selPid);
      const rowMap = new Map();
      rowsEl.addEventListener('click', e => { const r = e.target.closest('.pm-row'); if (r) { selPid = +r.dataset.pid; for (const [pid, x] of rowMap) x.el.classList.toggle('sel', pid === selPid); } });
      const sorted = () => [...S.procs].sort((a, b) => b.priority - a.priority || a.pid - b.pid);
      let tick = 0;
      const ticker = () => {
        if (w.closing) { S.tickers.splice(S.tickers.indexOf(ticker), 1); return; }
        tick++;
        const ps = sorted();
        // structure
        const ids = ps.map(p => p.pid).join(',');
        if (ids !== w._ids) {
          w._ids = ids; rowsEl.innerHTML = ''; rowMap.clear();
          for (const p of ps) {
            const cv = h('canvas', { width: 150, height: 12 });
            const el = h('div', { class: 'pm-row' + (p.pid === selPid ? ' sel' : ''), 'data-pid': p.pid },
              h('span', { class: 'sw', style: { background: `hsl(${p.hue},65%,55%)` } }), h('span', { class: 'nm' }), h('span', { class: 'pri', text: p.priority }), h('span', { class: 'st' }), h('span', { class: 'cpu' }), h('span', { class: 'lane' }, cv));
            rowsEl.append(el); rowMap.set(p.pid, { el, cv, ctx: cv.getContext('2d') });
          }
        }
        for (const p of ps) {
          const r = rowMap.get(p.pid); if (!r) continue;
          if (tick % 6 === 0 || p.state !== r.state || p.name !== r.name) {
            r.state = p.state; r.name = p.name;
            r.el.children[1].innerHTML = esc(p.name) + (p.kind === 'window' ? '<small>window</small>' : p.kind === 'user' ? '<small>forked</small>' : '');
            r.el.children[3].textContent = p.state; r.el.children[3].className = 'st ' + p.state;
            r.el.children[4].textContent = Math.round(S.clamp(p.cpu, 0, 100)) + '%';
            r.el.classList.toggle('dead', p.state === 'terminated');
          }
          // lane: newest on the right
          const c = r.ctx, L = p.lane.length, f = S.FRAME;
          c.clearRect(0, 0, 150, 12);
          c.fillStyle = `hsl(${p.hue},70%,50%)`;
          for (let i = 0; i < L; i++) {
            const a = p.lane[(f - (L - 1 - i) + L * 100) % L];
            if (a > 0) { c.globalAlpha = Math.min(1, a); c.fillRect(i, 12 - a * 12, 1, a * 12); }
          }
          c.globalAlpha = 1;
        }
        if (tick % 10 === 0) {
          const run = S.procs.filter(p => p.state === 'running').length;
          stat.textContent = `${S.procs.filter(p => p.state !== 'terminated').length} green threads · ${run} running · 1 OS thread`;
        }
      };
      S.tickers.push(ticker);
    },
  });

  // ---------- Fractal demo (busy window) ----------
  const PALETTES = {
    Ember: t => [255 * Math.pow(t, .5), 200 * Math.pow(t, 1.4), 80 * Math.pow(t, 3)],
    Glacier: t => [60 * t * t, 170 * Math.pow(t, .9), 255 * Math.pow(t, .45)],
    Aurora: t => [120 + 120 * Math.sin(6.28 * t + 4), 140 + 110 * Math.sin(6.28 * t + 2), 160 + 90 * Math.sin(6.28 * t)],
    Orchid: t => [230 * Math.pow(t, .6), 90 * t, 255 * Math.pow(t, .5)],
    Moss: t => [90 * t, 220 * Math.pow(t, .7), 120 * t * t],
    Ink: t => [255 * t, 255 * t, 255 * t],
    Solar: t => [255 * Math.pow(t, .3), 160 * Math.pow(t, .8), 40 + 30 * t],
    Lagoon: t => [30 + 40 * t, 200 * Math.pow(t, .6), 200 * Math.pow(t, .8)],
  };
  S.openFractal = (o = {}) => S.openWindow({
    kind: 'fractal', cls: 'FractalWindow', title: o.title || 'Fractal', hue: 350, x: o.x ?? 430, y: o.y ?? 330, w: o.w || 420, h: o.h || 480, minW: 340, minH: 380, name: 'fractalWindow',
    build(w, body) {
      const canvas = h('canvas');
      const scan = h('div', { class: 'scan' });
      const view = h('div', { class: 'fractal-view', 'data-morph': 'FractalView', 'data-name': 'view' }, canvas, scan);
      const out = h('output', { text: '360' });
      const slider = h('div', { class: 'm-slider', 'data-morph': 'Slider', 'data-name': 'itersSlider' }, h('input', { type: 'range', min: 60, max: 1500, value: 360, 'data-act': 'iters' }), out);
      const list = h('div', { class: 'm-list', 'data-morph': 'ListView', 'data-name': 'paletteList', style: { height: '76px', width: '120px' } },
        Object.keys(PALETTES).map((k, i) => h('div', { class: 'li' + (i === 0 ? ' sel' : ''), 'data-v': k, text: k })));
      const btn = (name, label, action, primary) => h('button', { class: 'm-btn' + (primary ? ' primary' : ''), 'data-morph': 'Button', 'data-name': name, 'data-label': '', 'data-action': action }, h('span', { class: 'lbl', text: label }));
      body.append(view,
        h('div', { class: 'row' },
          h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px', flex: '1' } },
            h('div', { class: 'row' }, btn('renderButton', 'Render', 'fractalRender', true), btn('resetButton', 'Reset', 'fractalReset')),
            h('div', { class: 'row' }, h('span', { class: 'm-label', 'data-morph': 'Label', 'data-name': 'itersLabel', 'data-label': '', text: 'iterations' }), slider)),
          list),
        h('div', { class: 'hint', 'data-morph': 'Label', 'data-name': 'hintLabel', html: 'Render runs in <b>this window\'s Process</b>. While it\'s busy, drag or flip it, use other windows — only this one waits. <kbd>⌘.</kbd> interrupts. Click the image to zoom.' }));
      const F = w.fractal = { cx: -.6, cy: 0, sc: 3.1, row: 0, iters: 360, pal: 'Ember', running: false, canvas, view, scan, out };
      const size = () => {
        const dpr = Math.min(2, devicePixelRatio || 1), r = view.getBoundingClientRect(), s = r.width / view.offsetWidth || 1;
        const W = Math.max(40, Math.round(view.offsetWidth * dpr / 1.5)), H = Math.max(30, Math.round(view.offsetHeight * dpr / 1.5));
        if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; F.img = canvas.getContext('2d').createImageData(W, 1); return true; }
        return false;
      };
      F.size = size;
      F.renderRow = (y) => {
        const W = canvas.width, H = canvas.height, ctx = canvas.getContext('2d');
        const pal = PALETTES[F.pal], max = F.iters, d = F.img.data;
        const ci = F.cy + (y / H - .5) * F.sc * H / W;
        for (let x = 0; x < W; x++) {
          const cr = F.cx + (x / W - .5) * F.sc;
          let zr = 0, zi = 0, n = 0;
          while (n < max && zr * zr + zi * zi < 4) { const t = zr * zr - zi * zi + cr; zi = 2 * zr * zi + ci; zr = t; n++; }
          let r = 6, g = 8, b = 18;
          if (n < max) { const sm = n + 1 - Math.log2(Math.max(1e-9, Math.log(Math.sqrt(zr * zr + zi * zi)))); const t = S.clamp(Math.sqrt(sm / max) * 1.15, 0, 1); [r, g, b] = pal(t); }
          const k = x * 4; d[k] = r; d[k + 1] = g; d[k + 2] = b; d[k + 3] = 255;
        }
        ctx.putImageData(F.img, 0, y);
      };
      F.renderAll = () => { size(); for (let y = 0; y < canvas.height; y++) F.renderRow(y); };
      F.start = () => {
        if (F.running) return;
        size(); F.row = 0; F.acc = 0; F.running = true; F.t0 = performance.now(); F.slices = 0;
        const c2 = canvas.getContext('2d'); c2.fillStyle = 'rgba(6,8,18,.72)'; c2.fillRect(0, 0, canvas.width, canvas.height);
        w.setBusy(true, 'busy · rendering');
        w.proc.stack = 'fractal';
        S.transcript(`[${w.title}] render started in the window's own Process (pid ${w.proc.pid})\n`);
      };
      F.finish = () => {
        F.running = false; w.setBusy(false);
        const q = w.queued;
        S.transcript(`[${w.title}] render finished in ${((performance.now() - F.t0) / 1000).toFixed(1)} s, ${F.slices} time slices${q ? `, then handled ${q} queued event${q > 1 ? 's' : ''}` : ''}\n`);
        w.queued = 0;
        w.el.querySelectorAll('.veil > *').forEach(x => x.remove());
      };
      const ticker = () => {
        if (w.closing) { S.tickers.splice(S.tickers.indexOf(ticker), 1); return; }
        if (!F.running || w.proc.state === 'suspended') return;
        // one time slice per frame: a few rows, deliberately slow so the busy state is visible
        const t0 = performance.now(); F.slices++;
        F.acc = (F.acc || 0) + canvas.height / 330;
        while (F.acc >= 1 && F.row < canvas.height && performance.now() - t0 < 8) { F.renderRow(F.row++); F.acc--; }
        w.busyProg = F.row / canvas.height;
        F.scan.style.top = (F.row / canvas.height * 100) + '%';
        if (S.FRAME % 4 === 0) w.setChip('busy', w.queued ? `busy · ${w.queued} event${w.queued > 1 ? 's' : ''} queued` : 'busy · rendering', w.busyProg);
        if (F.row >= canvas.height) F.finish();
      };
      S.tickers.push(ticker);
      w.onResize = () => { if (!F.running && size()) F.renderAll(); };
      requestAnimationFrame(() => F.renderAll());
      view.addEventListener('click', e => {
        if (e.altKey || e.metaKey || w.busy) return;
        const r = view.getBoundingClientRect();
        F.cx += ((e.clientX - r.left) / r.width - .5) * F.sc;
        F.cy += ((e.clientY - r.top) / r.height - .5) * F.sc * r.height / r.width;
        F.sc *= .4; F.start();
      });
      list.addEventListener('click', e => { const li = e.target.closest('.li'); if (!li) return; F.pal = li.dataset.v; if (!F.running) F.renderAll(); });
    },
  });
  const fractalOf = el => { const w = S.winOf(el); return w && w.fractal ? w : S.wins.find(x => x.fractal && !x.closing); };

  // ---------- delegated widget actions ----------
  S.actions = {
    fractalRender: el => { const w = fractalOf(el); if (w) w.fractal.start(); },
    fractalReset: el => { const w = fractalOf(el); if (!w) return; Object.assign(w.fractal, { cx: -.6, cy: 0, sc: 3.1 }); w.fractal.renderAll(); },
    pmDebug: el => { const w = S.winOf(el); const p = w && w.pmSel(); if (!p) return S.toast('Select a process first'); S.interrupt(p); },
    pmTerminate: el => {
      const w = S.winOf(el); const p = w && w.pmSel(); if (!p) return S.toast('Select a process first');
      if (p.kind === 'system') return S.toast(`Terminating <b>${esc(p.name)}</b> would stop the world — refused in the prototype`);
      S.terminate(p);
    },
    partButton: el => { const t = (el.querySelector('.lbl') || el).textContent; S.transcript(`${el.dataset.name || 'aButton'} clicked: '${t}'\n`); },
    proceed: el => { const w = S.winOf(el); w.notifier.proceed(); },
    abandon: el => { const w = S.winOf(el); w.notifier.abandon(); },
    debug: el => { const w = S.winOf(el); w.notifier.debug(); },
    accept: el => { const w = S.winOf(el); const ed = w.back.querySelector('.ed'); S.accept(ed); },
    flipBack: el => { const w = S.winOf(el); if (w.flipped) S.flip(w); },
  };
  document.addEventListener('click', e => {
    if (S.suppressClick) { S.suppressClick = false; e.stopPropagation(); e.preventDefault(); return; }
    const a = e.target.closest('[data-action]');
    if (!a || e.altKey || e.metaKey) return;
    const f = S.actions[a.dataset.action];
    S.touch(S.winOf(a));
    if (f) f(a, e);
  }, false);
  document.addEventListener('input', e => {
    const sl = e.target.closest('.m-slider');
    if (!sl) return;
    const o = sl.querySelector('output'); if (o) o.textContent = e.target.value;
    if (e.target.dataset.act === 'iters') { const w = fractalOf(sl); if (w) w.fractal.iters = +e.target.value; }
    S.touch(S.winOf(sl));
  });
  document.addEventListener('click', e => {
    const li = e.target.closest('.m-list .li');
    if (!li || e.altKey || e.metaKey) return;
    li.parentElement.querySelectorAll('.li').forEach(x => x.classList.toggle('sel', x === li));
  });

  // ---------- interrupts, notifier, debugger ----------
  const fractalStack = () => [
    { label: 'FractalView>>escapeTimeAt:max:', cls: 'FractalView', sel: 'escapeTimeAt:', pc: 5 },
    { label: '[] in FractalView>>renderRow:', cls: 'FractalView', sel: 'renderRow:', pc: 6 },
    { label: 'Interval>>do:', cls: 'Interval', sel: 'do:', pc: 4 },
    { label: 'FractalView>>renderRow:', cls: 'FractalView', sel: 'renderRow:', pc: 4 },
    { label: '[] in FractalView>>render', cls: 'FractalView', sel: 'render', pc: 5 },
    { label: 'Interval>>do:', cls: 'Interval', sel: 'do:', pc: 4 },
    { label: 'FractalView>>render', cls: 'FractalView', sel: 'render', pc: 4 },
    { label: 'Button>>mouseUp:', cls: 'Button', sel: 'mouseUp:', pc: 1 },
    { label: 'Widget>>handleEvent:', cls: 'Widget', sel: 'handleEvent:', pc: 3 },
    { label: 'Window>>eventLoop', cls: 'Window', sel: 'eventLoop', pc: 3 },
    { label: '[] in Window>>open', cls: 'Window', sel: 'open', pc: 1 },
    { label: '[] in BlockClosure>>newProcess', cls: 'BlockClosure', sel: 'newProcess', pc: 3 },
  ];
  const doitStack = p => [
    { label: '[] in UndefinedObject>>DoIt', src: `DoIt\n\t[${p.inner || ''}] ${'forkNamed: ' + "'" + p.name + "'"}`, pc: 1 },
    { label: 'Interval>>do:', cls: 'Interval', sel: 'do:', pc: 4 },
    { label: '[] in UndefinedObject>>DoIt', src: `DoIt\n\t[${p.inner || ''}] forkNamed: '${p.name}'`, pc: 1 },
    { label: '[] in BlockClosure>>newProcess', cls: 'BlockClosure', sel: 'newProcess', pc: 3 },
  ];
  const idleStack = p => [
    { label: 'Semaphore>>wait', cls: 'Semaphore', sel: 'wait', pc: 1 },
    { label: p.window ? 'SharedQueue>>next' : 'ProcessorScheduler>>yield', cls: 'ProcessorScheduler', sel: 'yield', pc: 2 },
    ...(p.window ? [{ label: 'Window>>eventLoop', cls: 'Window', sel: 'eventLoop', pc: 2 }, { label: '[] in Window>>open', cls: 'Window', sel: 'open', pc: 1 }] : [{ label: 'Compositor>>run', cls: 'Compositor', sel: 'run', pc: 1 }]),
    { label: '[] in BlockClosure>>newProcess', cls: 'BlockClosure', sel: 'newProcess', pc: 3 },
  ];

  S.terminate = p => {
    p.state = 'terminated'; p.dead = performance.now();
    const w = S.wins.find(x => x.id === p.window);
    if (p.kind === 'window' && w) { if (w.fractal && w.fractal.running) { w.fractal.running = false; w.setBusy(false); } w.close(); }
    if (p.kind === 'user' && p.origin) p.origin.setChip(null);
    S.transcript(`Process '${p.name}' (pid ${p.pid}) terminated\n`);
  };
  S.userInterrupt = () => {
    const f = S.focused();
    let p = null;
    if (f && f.busy) p = f.proc;
    if (!p) { const ws = S.wins.filter(w => w.busy && !w.closing); if (ws.length) p = ws[ws.length - 1].proc; }
    if (!p) { const us = S.procs.filter(x => x.kind === 'user' && x.state === 'running'); if (us.length) p = us[us.length - 1]; }
    if (!p) { S.toast('User interrupt: no busy Process to interrupt — try <b>Render</b> in the Fractal window or fork the crunch line'); return; }
    S.interrupt(p);
  };
  S.interrupt = p => {
    if (p.state === 'terminated') return;
    const owner = S.wins.find(x => x.id === p.window);
    const wasRunning = p.state === 'running';
    const frames = p.kind === 'user' ? doitStack(p) : (owner && owner.fractal && owner.fractal.running ? fractalStack() : idleStack(p));
    p.prevState = p.state; p.state = 'suspended';
    if (owner && owner.busy) owner.setChip('busy', 'suspended · in debugger');
    const base = owner && !owner.closing ? owner : S.focused();
    S.openWindow({
      kind: 'notifier', cls: 'Notifier', title: `User Interrupt — ${p.name}`, hue: 4, w: 460, h: 300, minW: 380, minH: 240,
      x: base ? S.clamp(base.x + 40, 10, innerWidth - 480) : 400, y: base ? S.clamp(base.y + 50, 44, innerHeight - 320) : 200,
      build(w, body) {
        const list = h('div', { class: 'pane tlist stack', 'data-morph': 'ListView', 'data-name': 'stackList', style: { flex: '1' } },
          frames.map((f, i) => h('div', { class: 'li' + (i === 0 ? ' sel' : ''), 'data-i': i, text: f.label })));
        const btn = (name, label, action, primary) => h('button', { class: 'm-btn' + (primary ? ' primary' : ''), 'data-morph': 'Button', 'data-name': name, 'data-label': '', 'data-action': action }, h('span', { class: 'lbl', text: label }));
        body.append(h('div', { class: 'notice', html: `<b>User Interrupt</b> · Process <b style="color:inherit">'${esc(p.name)}'</b> (pid ${p.pid}, priority ${p.priority}) stopped at a safepoint. Every other Process keeps running.` }),
          list, h('div', { class: 'row' }, btn('proceedButton', 'Proceed', 'proceed', true), btn('abandonButton', 'Abandon', 'abandon'), btn('debugButton', 'Debug', 'debug'), h('span', { class: 'hint', style: { marginLeft: 'auto' }, text: wasRunning ? 'was running' : 'was ' + (p.prevState || 'waiting') })));
        let ed = null, band = null;
        const showFrame = i => {
          list.querySelectorAll('.li').forEach((x, j) => x.classList.toggle('sel', j === i));
          if (!ed) return;
          const f = frames[i];
          const src = f.src || S.methodSource(f.cls, f.sel) || `${f.label}\n\t"source not available in the prototype"`;
          S.setEditorText(ed, src);
          band.style.top = (9 + f.pc * 18) + 'px'; band.style.transform = '';
        };
        list.addEventListener('click', e => { const li = e.target.closest('.li'); if (li) showFrame(+li.dataset.i); });
        let done = false;
        w.notifier = {
          proceed() { if (done) return; done = true; p.state = p.prevState === 'suspended' ? 'running' : (p.prevState || 'running'); if (owner && owner.busy) owner.setChip('busy', 'busy · rendering', owner.busyProg); w.close(); },
          abandon() {
            if (done) return; done = true;
            if (p.kind === 'user') { p.state = 'terminated'; p.dead = performance.now(); if (p.origin) p.origin.setChip(null); S.transcript(`[${p.name}] abandoned in the debugger\n`); }
            else if (owner && owner.fractal && owner.fractal.running) { owner.fractal.running = false; owner.setBusy(false); p.state = 'waiting'; S.transcript(`[${owner.title}] render abandoned — the window's Process unwound to its event loop\n`); }
            else p.state = p.prevState || 'waiting';
            w.close();
          },
          debug() {
            if (ed) return;
            w.setTitle(`Debugger — ${p.name}`);
            ed = S.makeEditor({ name: 'sourcePane', ws: w.id, method: true });
            band = h('div', { class: 'pcband' });
            ed.append(band);
            ed.style.flex = '1.3';
            body.insertBefore(ed, body.lastChild);
            const nh = Math.min(Math.max(w.h, 520), innerHeight - 160); w.resize(Math.max(w.w, 620), nh, true); w.moveTo(S.clamp(w.x, 10, innerWidth - 640), S.clamp(w.y, 44, innerHeight - 140 - nh));
            showFrame(0);
          },
        };
        w.onClose = () => { if (!done) w.notifier.proceed(); };
      },
    });
  };
})();
