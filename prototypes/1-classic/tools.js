// Samaltak classic prototype — evaluation and tools.
'use strict';

const LAYERS = ['Kernel', '3D', '2D', 'Windows', 'Widgets', 'Tools'];
const LAYER_SUB = ['objects · numbers · processes', 'Graphics-GPU', 'Graphics-Canvas', 'compositor · windows', 'UI-Widgets', 'development tools'];

// ---------------------------------------------------------------- transcript buffer
const TranscriptBuf = {
  text: '', subs: new Set(),
  append(s) { this.text += s; if (this.text.length > 60000) this.text = this.text.slice(-50000); this.subs.forEach(f => f(s)); },
};

// ---------------------------------------------------------------- method lookup helpers
function selectorOf(key) {
  const k = key.trim();
  if (!/^[A-Za-z]/.test(k)) return k.split(/\s+/)[0];
  if (!k.includes(':')) return k.split(/\s+/)[0];
  return (k.match(/[A-Za-z0-9_]+:/g) || []).join('');
}
const EXTRA_SRC = {
  'BlockClosure>>repeat': 'repeat\n\t"Evaluate the receiver forever."\n\n\t[self value. true] whileTrue',
  'SharedQueue>>next': 'next\n\t"Answer the next object, waiting until one is available."\n\n\t^accessProtect critical: [\n\t\treadSynch wait.\n\t\titems removeFirst]',
  'Compiler>>evaluate:for:': 'evaluate: aString for: anObject\n\t| method |\n\tmethod := self compileDoIt: aString in: anObject class.\n\t^anObject withArgs: #() executeMethod: method',
  'ZeroDivide(Exception)>>signal': 'signal\n\t"Raise the receiver. Search handler contexts; if none, open a notifier\n\t on the signalling Process. Other Processes keep running."\n\n\t^self signalIn: thisContext sender',
  'SmallInteger(Number)>>/': '/ aNumber\n\t<primitive: 10>\n\taNumber = 0 ifTrue: [^(ZeroDivide dividend: self) signal].\n\t^super / aNumber',
  'Workspace(Widget)>>handleEvent:': null,
  'MandelbrotView>>escapeTimeAt:': 'escapeTimeAt: c\n\t| z n |\n\tz := Complex zero.\n\tn := 0.\n\t[n < maxIterations and: [z squaredMagnitude <= 4]] whileTrue: [\n\t\tz := z squared + c.\n\t\tn := n + 1].\n\t^n',
  'MandelbrotView>>renderRow:': 'renderRow: y\n\t0 to: width - 1 do: [:x |\n\t\tbitmap\n\t\t\tat: x @ y\n\t\t\tput: (palette at: (self escapeTimeAt: (self complexAt: x @ y)))]',
  '[] in MandelbrotView>>render': null,
  'MandelbrotView>>render': 'render\n\t"Runs in my window\'s Process. The compositor keeps showing my last\n\t published DisplayList, so the rest of the world stays smooth."\n\n\t0 to: height - 1 do: [:y |\n\t\tself renderRow: y.\n\t\ty \\\\ 8 = 0 ifTrue: [self publish]].\n\tself publish',
  'ProcessBrowser>>updateList': 'updateList\n\t"I am the active Process while I draw this list."\n\n\tprocesses := Process allInstances\n\t\tsort: [:a :b | a priority >= b priority].\n\tself changed: #processes',
  'InputDispatcher>>run': 'run\n\t[| event |\n\t event := hostEvents next.\n\t (self windowAt: event position) eventQueue nextPut: event] repeat',
  'ProcessorScheduler>>idleProcess': 'idleProcess\n\t"Sleep the OS thread until the next event or timer."\n\n\t[self relinquishProcessorForMicroseconds: 1000] repeat',
};
EXTRA_SRC['[] in MandelbrotView>>render'] = EXTRA_SRC['MandelbrotView>>render'];
function frameSource(label, doit) {
  if (/DoIt$/.test(label)) return 'DoIt\n\t^' + (doit || 'nil').trim();
  const bare = label.replace(/^\[\] in /, '');
  if (EXTRA_SRC[label]) return EXTRA_SRC[label];
  if (EXTRA_SRC[bare]) return EXTRA_SRC[bare];
  const m = bare.match(/^([\w ]+?)(?:\((\w+)\))?>>(.+)$/);
  if (m) {
    const cls = FakeImage.findClass((m[2] || m[1]).replace(/ class$/, ''));
    const sel = m[3].replace(/ #.*/, '');
    if (cls) for (const proto of Object.values(cls.protocols)) for (const [k, src] of Object.entries(proto)) if (selectorOf(k) === sel) return src;
  }
  return `"The source of ${bare} is not part of this prototype image."`;
}
// Which line is "executing" in a frame: the first line mentioning the callee's selector.
function pcRange(src, callee) {
  const lines = src.split('\n'); let off = 0, pick = -1;
  const body = lines.findIndex((l, i) => i > 0 && l.trim() && !l.trim().startsWith('"') && !l.trim().startsWith('|') && !l.trim().startsWith('<'));
  if (callee) {
    const sel = callee.replace(/^\[\] in /, '').split('>>')[1] || '';
    const kw = sel.replace(/ #.*/, '').split(':')[0];
    pick = lines.findIndex((l, i) => i > 0 && kw && l.includes(kw));
  }
  if (pick < 0 && !callee) pick = lines.findIndex(l => l.includes('<primitive:'));
  if (pick < 0) pick = body < 0 ? 0 : body;
  for (let i = 0; i < pick; i++) off += lines[i].length + 1;
  return { s: off, e: off + lines[pick].length };
}

const WINDOW_WAIT = ['Semaphore>>wait', 'SharedQueue>>next', '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'];
const SYS_FRAMES = {
  'timer interrupt watcher': ['Semaphore>>wait', '[] in ProcessorScheduler>>timerLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'],
  'compositor (vsync)': ['Semaphore>>wait', '[] in Compositor>>run', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'],
  'input dispatcher': ['SharedQueue>>next', '[] in InputDispatcher>>run', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'],
  'finalization': ['Semaphore>>wait', '[] in WeakRegistry class>>finalizationLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'],
  'idle': ['ProcessorScheduler>>idleProcess', '[] in ProcessorScheduler class>>startUp', '[] in BlockClosure>>newProcess'],
};
function framesOf(p) {
  if (p.frames) return typeof p.frames === 'function' ? p.frames() : p.frames;
  if (p.kind === 'system') return SYS_FRAMES[p.name] || ['Semaphore>>wait'];
  if (Sched.displayState(p) === 'running') return [`${p.name.replace(/\s/g, '')}(Widget)>>handleEvent:`, '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'];
  return WINDOW_WAIT;
}

// ---------------------------------------------------------------- forking: parse `[ ... ] forkNamed: 'x'` and time-slice it
function matchBracket(s, i) {
  let d = 0;
  for (let j = i; j < s.length; j++) {
    const c = s[j];
    if (c === '"' || c === "'") { const k = s.indexOf(c, j + 1); if (k < 0) return -1; j = k; continue; }
    if (c === '$') { j++; continue; }
    if (c === '[') d++;
    else if (c === ']') { d--; if (d === 0) return j; }
  }
  return -1;
}
function detectFork(text) {
  const t = text.trim().replace(/\.\s*$/, '');
  if (t[0] !== '[') return null;
  const close = matchBracket(t, 0);
  if (close < 0) return null;
  const rest = t.slice(close + 1).trim();
  const m = rest.match(/^(fork|forkNamed:\s*'((?:[^']|'')*)'|forkAt:\s*([\w ]+))$/);
  if (!m) return null;
  return { name: m[2] || 'a Process', priority: m[3] ? (/\d+/.test(m[3]) ? +m[3].match(/\d+/)[0] : 30) : 40, plan: planLoop(t.slice(1, close)) };
}
function planLoop(body) {
  let b = body.trim(), temps = '';
  const tm = b.match(/^\|[\w\s]*\|/); if (tm) { temps = tm[0] + ' '; b = b.slice(tm[0].length).trim(); }
  b = b.replace(/\.\s*$/, '');
  const tail = (s, i) => { const c = matchBracket(s, i); return c > 0 && s.slice(c + 1).trim() === '' ? s.slice(i + 1, c) : null; };
  let m;
  if ((m = b.match(/^(\d+)\s+timesRepeat:\s*\[/))) { const inner = tail(b, m[0].length - 1); if (inner != null) return { kind: 'times', n: +m[1], inner, temps }; }
  if ((m = b.match(/^(-?\d+)\s+to:\s*(-?\d+)\s+do:\s*\[\s*:(\w+)\s*\|/))) {
    const c = matchBracket(b, b.indexOf('['));
    if (c > 0 && b.slice(c + 1).trim() === '') return { kind: 'to', from: +m[1], to: +m[2], v: m[3], inner: b.slice(m[0].length, c), temps };
  }
  if (b[0] === '[') {
    const c = matchBracket(b, 0);
    const r = b.slice(c + 1).trim().match(/^whileTrue:\s*\[/);
    if (c > 0 && r) { const inner = tail(b.slice(c + 1).trim(), r[0].length - 1); if (inner != null) return { kind: 'while', cond: b.slice(1, c), inner, temps }; }
  }
  return { kind: 'once', inner: b, temps };
}
function spawnForked(fk, ed, opts = {}) {
  const ws = ed ? ed.workspace : 'world', origin = ed && ed.win;
  const pl = fk.plan; const tr = s => TranscriptBuf.append(s);
  const ev = src => MiniST.evaluate(pl.temps + src, { transcript: tr, workspace: ws });
  let k = pl.kind === 'to' ? pl.from : 0, ticks = 0, done = 0;
  const total = pl.kind === 'to' ? pl.to - pl.from + 1 : pl.kind === 'times' ? pl.n : null;
  const inner1 = (pl.inner.match(/\b([a-z]\w*)\b/g) || []).find(w => ['factorial', 'isPrime', 'printString', 'inject', 'sqrt', 'raisedTo'].includes(w));
  const p = Sched.add({
    name: fk.name, priority: fk.priority, kind: 'user', state: 'running', origin: origin && origin.id, source: opts.source || '',
    progress: () => total ? `${done}/${total}` : `${done} iterations`,
    frames: () => [
      ...(inner1 ? [{ factorial: 'SmallInteger(Integer)>>factorial', isPrime: 'SmallInteger(Integer)>>isPrime' }[inner1] || `SmallInteger(Object)>>${inner1}`] : []),
      `[] in UndefinedObject>>DoIt`,
      pl.kind === 'to' ? 'SmallInteger(Number)>>to:do:' : pl.kind === 'times' ? 'SmallInteger(Integer)>>timesRepeat:' : pl.kind === 'while' ? 'BlockClosure>>whileTrue:' : 'BlockClosure>>value',
      '[] in UndefinedObject>>DoIt', '[] in BlockClosure>>newProcess'],
    step() {
      ticks++;
      if (pl.kind === 'to') { if (k > pl.to) return 'done'; ev(`${pl.v} := ${k}. ${pl.inner}`); k++; done++; return k > pl.to ? 'done' : undefined; }
      if (pl.kind === 'times') { if (done >= pl.n) return 'done'; ev(pl.inner); done++; return done >= pl.n ? 'done' : undefined; }
      if (pl.kind === 'while') { const c = ev(pl.cond); if (c.value !== true) return 'done'; ev(pl.inner); done++; return; }
      if (ticks === 1) { ev(pl.inner); done = 1; }
      return ticks > 24 ? 'done' : undefined;
    },
    onError(err) { Tools.openNotifier({ title: errTitle(err.message), message: `${err.message} — in Process '${p.name}'`, frames: [errFrame(err.message), ...p.frames()], proc: p, doit: pl.inner, near: origin }); },
  });
  if (origin) { origin.children.add(p); p.onDone = () => origin.children.delete(p); }
  return p;
}
const procPrint = p => `a Process('${p.name}' priority: ${p.priority})`;

// ---------------------------------------------------------------- evaluation (do it / print it / inspect it)
function errTitle(msg) {
  if (/^ZeroDivide/.test(msg)) return 'ZeroDivide';
  if (/doesNotUnderstand/.test(msg)) return 'MessageNotUnderstood: #' + (msg.match(/#(\S+)/) || [, '?'])[1];
  if (/^Undeclared/.test(msg)) return 'UndeclaredVariable';
  if (/Index out of bounds/.test(msg)) return 'SubscriptOutOfBounds';
  if (/NonBoolean/.test(msg)) return 'NonBooleanReceiver';
  return 'Error';
}
function errFrame(msg) {
  if (/^ZeroDivide/.test(msg)) return 'ZeroDivide(Exception)>>signal';
  const m = msg.match(/^(.*) doesNotUnderstand: #(\S+)/);
  if (m) { let cls = 'Object'; try { cls = MiniST.evaluate(`(${m[1]}) class name`).value || 'Object'; } catch (e) { /* receiver not re-parseable */ } return `${cls}(Object)>>doesNotUnderstand: #${m[2]}`; }
  return 'Error(Exception)>>signal';
}
const isSyntax = msg => /^(Expected|Unexpected|Bad literal)/.test(msg);
let inspN = 0;

const Eval = {
  run(ed, act) {
    if (act === 'browse') return this.browse(ed);
    const { s, e, text } = ed.selectionOrLine();
    if (!text.trim()) return;
    const win = ed.win;
    if (win && win.proc) Sched.poke(win.proc, 240);
    const src = ed.o.selfVar ? bindSelf(text, ed.o.selfVar) : text;
    const fk = detectFork(src);
    if (fk) {
      const p = spawnForked(fk, ed, { source: src });
      if (act === 'print') ed.insertAfter(e, ' ' + procPrint(p), 'result');
      else ed.setMark(s, e, 'flash', 600);
      if (act === 'inspect') Toast.show(`Forked ${procPrint(p)} — see the Process Browser`);
      return;
    }
    const opts = { transcript: x => TranscriptBuf.append(x), workspace: ed.workspace, forked: (b, name) => this.opaqueFork(name, ed) };
    let r, v = null;
    try {
      if (act === 'inspect') { v = '__insp' + (++inspN); r = MiniST.evaluate(`${v} := [${src}\n] value`, opts); }
      else r = MiniST.evaluate(src, opts);
    } catch (err) { return this.error(ed, err, s, e, src); }
    if (act === 'print') ed.insertAfter(e, ' ' + r.printString, 'result');
    else if (act === 'inspect') { ed.setMark(s, e, 'flash', 600); Tools.openInspector({ result: r, varName: v, workspace: ed.workspace, near: win, label: text.trim() }); }
    else ed.setMark(s, e, 'flash', 600);
  },
  opaqueFork(name, ed) {
    spawnForked({ name: name || 'a Process', priority: 40, plan: { kind: 'once', inner: 'nil', temps: '' } }, ed);
  },
  error(ed, err, s, e, text) {
    const msg = (err && err.message) || String(err);
    if (isSyntax(msg)) { ed.insertAfter(e, ` ‹${msg} →›`, 'error'); return; }
    const title = errTitle(msg);
    Tools.openNotifier({
      title, message: msg === title ? `${text.trim()} — ${/^ZeroDivide/.test(msg) ? 'division by zero' : 'error'}` : msg, doit: text, near: ed.win,
      frames: [errFrame(msg), 'UndefinedObject>>DoIt', 'Compiler>>evaluate:for:', 'TextEditor>>doIt', `${ed.win ? ed.win.kind[0].toUpperCase() + ed.win.kind.slice(1) : 'Workspace'}(Widget)>>handleEvent:`, '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'],
      onProceed: () => ed.insertAfter(e, ' nil', 'result'),
    });
  },
  browse(ed) {
    const w = ed.wordAtCaret().replace(/^#/, '');
    if (!w) return;
    if (FakeImage.findClass(w)) return Tools.openBrowser({ cls: w, near: ed.win });
    for (const c of FakeImage.allClasses()) for (const [pn, proto] of Object.entries(c.protocols)) for (const k of Object.keys(proto))
      if (selectorOf(k) === w) return Tools.openBrowser({ cls: c.name, proto: pn, sel: k, near: ed.win });
    Toast.show(`No class or implementor named ${w} in this image`);
  },
};

// ---------------------------------------------------------------- the tools
const Tools = {
  // ---------- System Browser
  openBrowser(o = {}) {
    const W = 860, H = 500;
    const pos = o.x != null ? o : WM.near(o.near, W, H, 36, 30);
    const win = WM.create({ title: 'System Browser', kind: 'browser', x: pos.x, y: pos.y, w: o.w || W, h: o.h || H, minW: 520, minH: 300, procName: 'System Browser' });
    const st = { pkg: null, cls: null, side: 'instance', proto: null, sel: null, dirty: false };
    const classSide = new Map();
    const pkgOf = n => FakeImage.packages.find(p => p.name === n);
    const clsObj = () => st.cls && FakeImage.findClass(st.cls) && pkgOf(st.pkg).classes.find(c => c.name === st.cls);
    const protosOf = c => {
      if (st.side !== 'class') return c.protocols;
      if (c.classSide) return c.classSide;
      if (!classSide.has(c.name)) {
        const p = { 'instance creation': { new: `new\n\t"Answer a new, initialized instance of the receiver."\n\n\t^self basicNew initialize` } };
        if (c.name === 'Compositor') p.accessing = { default: 'default\n\t"There is one compositor per display."\n\n\t^Default ifNil: [Default := self new]' };
        if (c.name === 'Window') p['instance creation']['title: aString content: aWidget'] = 'title: aString content: aWidget\n\t^self new\n\t\ttitle: aString;\n\t\tcontent: aWidget;\n\t\tyourself';
        classSide.set(c.name, p);
      }
      return classSide.get(c.name);
    };
    const pkgL = new List({ onSelect: k => selPkg(k) });
    const clsL = new List({ onSelect: k => selCls(k) });
    const protoL = new List({ onSelect: k => selProto(k) });
    const selL = new List({ onSelect: k => selSel(k) });
    const seg = h('div', { class: 'seg' });
    const segB = {};
    for (const [k, l] of [['instance', 'instance'], ['comment', '?'], ['class', 'class']]) {
      segB[k] = h('button', { class: k === 'instance' ? 'on' : '', title: k === 'comment' ? 'class comment' : k + ' side', onclick: () => setSide(k) }, l);
      seg.append(segB[k]);
    }
    const code = new Editor({ win, workspace: 'browser-' + win.id, method: true, onChange: () => setDirty(true), onAccept: () => accept() });
    const crumb = h('span', { class: 'mono' });
    const layerTag = h('span', { class: 'layertag' });
    const state = h('span', { class: 'pill' });
    const status = h('div', { class: 'statusbar' }, crumb, layerTag, h('span', { class: 'r' }, state));
    const top = h('div', { class: 'browser-top' },
      h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Packages', h('span', { class: 'r' }, 'by layer')), pkgL.el),
      h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Classes'), clsL.el, seg),
      h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Protocols'), protoL.el),
      h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Methods'), selL.el));
    win.body.append(top, vSplitter(top, 90), h('div', { class: 'browser-code' }, code.el, status));

    const sorted = [...FakeImage.packages].sort((a, b) => b.layer - a.layer);
    const pkgItems = [];
    let lastL = -1;
    for (const p of sorted) {
      const first = p.layer !== lastL; lastL = p.layer;
      pkgItems.push({ key: p.name, cls: first && pkgItems.length ? 'grp' : '',
        html: `<span class="lchip L${p.layer}"${first ? '' : ' style="visibility:hidden"'} title="layer ${p.layer}: ${LAYER_SUB[p.layer]}">${p.layer}</span><span class="t">${esc(p.name)}</span>${first ? `<span class="muted">${LAYERS[p.layer]}</span>` : ''}` });
    }
    pkgL.set(pkgItems);

    function setDirty(d) { st.dirty = d; code.el.classList.toggle('dirty', d); state.className = 'pill' + (d ? ' dirty' : ''); state.textContent = d ? 'unaccepted edits · ' + MOD + 'S' : ''; }
    function show(text, readOnly) { code.value = text; code.ta.readOnly = !!readOnly; setDirty(false); }
    function updateStatus() {
      const p = st.pkg && pkgOf(st.pkg);
      const c = st.cls ? st.cls + (st.side === 'class' ? ' class' : '') : '';
      crumb.textContent = st.sel ? `${c}>>${selectorOf(st.sel)}` : c || st.pkg || 'Samaltak image';
      layerTag.innerHTML = p ? `<span class="lchip L${p.layer}">${p.layer}</span><span>${esc(LAYERS[p.layer])} · ${esc(p.name)}${st.proto ? ' · ' + esc(st.proto) : ''}</span>` : '';
      win.setTitle(st.cls ? `System Browser: ${st.cls}` : 'System Browser');
    }
    function selPkg(name) {
      st.pkg = name; st.cls = st.proto = st.sel = null;
      const p = pkgOf(name);
      clsL.set(p.classes.map(c => ({ key: c.name, html: `<span class="t">${esc(c.name)}</span>` })));
      protoL.set([]); selL.set([]);
      show(`"${p.name} — layer ${p.layer} (${LAYERS[p.layer]})\n\n${p.comment}"`, true);
      updateStatus();
    }
    function classDef(c) {
      if (st.side === 'class') return `${c.name} class\n\tinstanceVariableNames: ''`;
      if (st.side === 'comment') return c.comment;
      return `${c.superclass} subclass: #${c.name}\n\tinstanceVariableNames: '${c.ivars.join(' ')}'\n\tclassVariableNames: ''\n\tpackage: '${st.pkg}'`;
    }
    function selCls(name) {
      st.cls = name; st.proto = st.sel = null;
      const c = clsObj();
      const pm = protosOf(c);
      protoL.set([{ key: '-- all --', label: '-- all --', cls: 'allproto' }, ...Object.keys(pm).map(k => ({ key: k, label: k }))]);
      selL.set([]);
      code.o.highlight = st.side !== 'comment'; code.el.classList.toggle('plain', st.side === 'comment');
      show(classDef(c));
      updateStatus();
    }
    function methodsIn(proto) {
      const pm = protosOf(clsObj());
      if (proto === '-- all --') return Object.entries(pm).flatMap(([pn, ms]) => Object.keys(ms).map(k => [k, pn]));
      return Object.keys(pm[proto] || {}).map(k => [k, proto]);
    }
    function listMethods() {
      selL.set(methodsIn(st.proto).sort((a, b) => selectorOf(a[0]).localeCompare(selectorOf(b[0])))
        .map(([k]) => ({ key: k, label: selectorOf(k), cls: st.mod && st.mod.has(st.cls + st.side + k) ? 'mod' : '' })), st.sel);
    }
    function selProto(name) {
      st.proto = name; st.sel = null;
      listMethods();
      show(`message selector and argument names\n\t"comment stating purpose of message"\n\n\t| temporary variable names |\n\tstatements`);
      updateStatus();
    }
    function selSel(key) {
      st.sel = key;
      const found = methodsIn(st.proto).find(([k]) => k === key);
      const pm = protosOf(clsObj());
      code.o.highlight = true; code.el.classList.remove('plain');
      show(pm[found[1]][key]);
      updateStatus();
      Sched.poke(win.proc, 120);
    }
    function setSide(k) {
      st.side = k;
      Object.entries(segB).forEach(([n, b]) => b.classList.toggle('on', n === k));
      if (st.cls) selCls(st.cls);
    }
    function accept() {
      const c = clsObj();
      if (!c) { Toast.show('Select a class first'); return; }
      st.mod = st.mod || new Set();
      if (st.proto && st.proto !== '-- all --' || st.sel) {
        const src = code.value;
        const pattern = src.split('\n')[0].trim();
        const pm = protosOf(c);
        let proto = st.proto === '-- all --' || !st.proto ? (st.sel && methodsIn('-- all --').find(([k]) => k === st.sel)[1]) : st.proto;
        if (!proto) proto = 'as yet unclassified';
        pm[proto] = pm[proto] || {};
        const same = st.sel && selectorOf(st.sel) === selectorOf(pattern);
        const key = same ? st.sel : pattern;
        pm[proto][key] = src;
        st.mod.add(st.cls + st.side + key);
        st.sel = key;
        if (!protoL.items.some(i => i.key === proto)) protoL.set([...protoL.items, { key: proto, label: proto }], st.proto);
        listMethods(); selL.select(key, false);
        TranscriptBuf.append(`${c.name}${st.side === 'class' ? ' class' : ''}>>${selectorOf(key)} accepted\n`);
      } else if (st.side === 'comment') { c.comment = code.value; }
      setDirty(false);
      state.className = 'pill ok'; state.textContent = 'accepted';
      setTimeout(() => { if (!st.dirty) { state.className = 'pill'; state.textContent = ''; } }, 1600);
      updateStatus();
    }

    // initial selection
    const startCls = o.cls || 'Window';
    const start = FakeImage.findClass(startCls);
    if (start) {
      pkgL.select(start.package);
      clsL.select(start.name);
      const pn = o.proto || (o.cls ? null : 'opening');
      if (pn) { protoL.select(pn); const sk = o.sel || (o.cls ? null : 'open'); if (sk) selL.select(sk); }
    } else updateStatus();
    return win;
  },

  // ---------- Workspace
  openWorkspace(o = {}) {
    const W = o.w || 600, H = o.h || 330;
    const pos = o.x != null ? o : WM.nextPos(W, H);
    const win = WM.create({ title: o.title || 'Workspace', kind: 'workspace', x: pos.x, y: pos.y, w: W, h: H, procName: o.title || 'Workspace' });
    const ed = new Editor({ win, workspace: win.id, value: o.value || '' });
    const kidsLbl = h('span');
    const foot = h('div', { class: 'statusbar ws-foot' }, h('span', { class: 'pill busy' }, kidsLbl), h('span', { class: 'r' }, h('span', null, `${MOD}. interrupts`)));
    win.body.append(ed.el, foot);
    const upd = () => {
      const kids = [...win.children].filter(c => c.step);
      win.root.classList.toggle('has-children', kids.length > 0);
      kidsLbl.parentElement.classList.toggle('susp', kids.length > 0 && kids.every(c => c.state === 'suspended'));
      kidsLbl.textContent = kids.map(c => `'${c.name}' ${c.state === 'suspended' ? 'suspended' : 'running'} · ${c.progress()}`).join('   ');
    };
    const iv = setInterval(upd, 120);
    win.onClose = () => clearInterval(iv);
    win.editor = ed;
    if (!o.noFocus) setTimeout(() => ed.focus(), 0);
    return win;
  },

  // ---------- Transcript
  openTranscript(o = {}) {
    const W = o.w || 520, H = o.h || 210;
    const pos = o.x != null ? o : WM.nextPos(W, H);
    const win = WM.create({ title: 'Transcript', kind: 'transcript', x: pos.x, y: pos.y, w: W, h: H, procName: 'Transcript' });
    const ed = new Editor({ win, workspace: win.id, highlight: false, cls: 'transcript' });
    ed.value = TranscriptBuf.text;
    const clear = h('button', { class: 'btn', onclick: () => { TranscriptBuf.text = ''; ed.value = ''; } }, 'clear');
    clear.classList.add('tr-clear');
    win.body.append(ed.el, clear);
    const sub = s => {
      const ta = ed.ta, atEnd = ta.scrollTop + ta.clientHeight >= ta.scrollHeight - 30;
      ta.value += s; if (atEnd) ta.scrollTop = ta.scrollHeight;
      Sched.poke(win.proc, 120);
    };
    TranscriptBuf.subs.add(sub);
    win.onClose = () => TranscriptBuf.subs.delete(sub);
    setTimeout(() => { ed.ta.scrollTop = ed.ta.scrollHeight; }, 0);
    return win;
  },

  // ---------- Inspector
  openInspector(o) {
    const r = o.result, W = o.w || 450, H = o.h || 290;
    const pos = o.x != null ? o : WM.near(o.near, W, H, 60, 60);
    const name = article(r.className);
    const win = WM.create({ title: `Inspector: ${name}`, kind: 'inspector', x: pos.x, y: pos.y, w: W, h: H, minW: 300, minH: 200, procName: `Inspector on ${name}` });
    const rows = MiniST.inspect(r.value);
    const fieldExpr = n => /^\d+$/.test(n) ? `${o.varName} at: ${n}` : ['x', 'y', 'numerator', 'denominator', 'class'].includes(n) ? `${o.varName} ${n}` : null;
    const valEd = new Editor({ win, highlight: false, readOnly: true });
    const fields = new List({
      onSelect: k => { valEd.value = rows[+k].value; },
      onDbl: k => {
        const ex = o.varName && fieldExpr(rows[+k].name); if (!ex) return;
        const v = '__insp' + (++inspN);
        try { const rr = MiniST.evaluate(`${v} := ${ex}`, { workspace: o.workspace }); Tools.openInspector({ result: rr, varName: v, workspace: o.workspace, near: win }); }
        catch (err) { Toast.show(err.message); }
      },
    });
    fields.set(rows.map((f, i) => ({ key: String(i), label: f.name, cls: 'k-' + f.name })));
    const samples = { Array: 'self size', Point: 'self x * self y', Fraction: 'self reciprocal', String: 'self asUppercase', Symbol: 'self size', SmallInteger: 'self printString size', LargePositiveInteger: 'self printString size', Float: 'self rounded', Character: 'self asInteger' };
    const evalEd = new Editor({ win, workspace: o.workspace, selfVar: o.varName, value: o.varName ? samples[r.className] || 'self printString' : '' });
    const top = h('div', { class: 'insp-top' },
      h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Fields'), fields.el),
      h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Value', h('span', { class: 'r' }, r.className)), valEd.el));
    const ev = h('div', { class: 'insp-eval pane' }, h('div', { class: 'pane-h' }, 'Evaluate ', h('code', null, 'self'), h('span', { style: { textTransform: 'none', letterSpacing: 0, fontWeight: 500 } }, ` = ${r.printString.length > 40 ? r.printString.slice(0, 40) + '…' : r.printString}`), h('span', { class: 'r' }, `${MOD}D · ${MOD}P · ${MOD}I`)), evalEd.el);
    win.body.append(top, ev);
    fields.select('0');
    return win;
  },

  // ---------- Process Browser
  openProcessBrowser(o = {}) {
    const existing = [...WM.wins.values()].find(w => w.kind === 'procs');
    if (existing) { existing.focus(); if (o.select) existing.selectPid(o.select); return existing; }
    const W = o.w || 530, H = o.h || 340;
    const pos = o.x != null ? o : WM.nextPos(W, H);
    const win = WM.create({ title: 'Process Browser', kind: 'procs', x: pos.x, y: pos.y, w: W, h: H, minW: 400, minH: 240, procName: 'Process Browser', frames: () => ['ProcessBrowser>>updateList', '[] in ProcessBrowser>>startStepping', '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'] });
    let sel = o.select || null, lastFrames = '';
    const rowsEl = h('div', { class: 'pb-rows', tabindex: '0' });
    const stackL = new List({ onSelect: k => showFrame(+k) });
    const srcEd = new Editor({ win, readOnly: true, method: true });
    const live = h('span', { class: 'live' }, h('i'), 'live');
    const btn = (l, f, t) => h('button', { class: 'btn', title: t || '', onclick: f }, l);
    const selProc = () => Sched.procs.find(p => p.pid === sel);
    const bDebug = btn('Debug', () => act('debug'), 'suspend and open a debugger');
    const bSusp = btn('Suspend', () => act('toggle'));
    const bTerm = btn('Terminate', () => act('terminate'));
    const count = h('span', { class: 'note' });
    win.body.append(
      h('div', { class: 'toolbar' }, bDebug, bSusp, bTerm, h('span', { class: 'sp' }), count, live),
      h('div', { class: 'pb-head' }, h('span'), h('span', { style: { textAlign: 'right', paddingRight: '9px' } }, 'Pri'), h('span', null, 'Process'), h('span', null, 'State'), h('span', null, 'CPU')),
      rowsEl, h('div', { class: 'vsplit', style: { cursor: 'default' } }),
      h('div', { class: 'pb-bottom' }, h('div', { class: 'pane' }, h('div', { class: 'pane-h' }, 'Stack'), stackL.el), h('div', { class: 'pane' }, srcEd.el)));
    function act(a) {
      const p = selProc(); if (!p) return;
      if (a === 'debug') {
        if (p.kind === 'system') { Toast.show(`Debugging '${p.name}' would stop the world. Refused.`); return; }
        const prev = p.state; p.state = 'suspended';
        Tools.openNotifier({ title: `Process '${p.name}'`, message: `Suspended from the Process Browser (was ${prev}).`, frames: framesOf(p), proc: p, near: win, interrupt: true, debug: true, doit: p.source });
      } else if (a === 'toggle') {
        if (p.kind === 'system') { Toast.show(`Suspending '${p.name}' would freeze the system. Refused.`); return; }
        p.state = p.state === 'suspended' ? (p.step ? 'running' : 'waiting') : 'suspended';
      } else if (a === 'terminate') {
        if (!Sched.terminate(p)) Toast.show(`'${p.name}' is part of the VM's runtime and cannot be terminated.`);
      }
      render(true);
    }
    function showFrame(i) {
      const p = selProc(); if (!p) return;
      const fr = framesOf(p); const src = frameSource(fr[i], p.source);
      srcEd.value = src;
      const r = pcRange(src, fr[i - 1]); srcEd.setMark(r.s, r.e, 'pc');
    }
    rowsEl.addEventListener('mousedown', e => { const r = e.target.closest('.prow'); if (r) { sel = +r.dataset.pid; render(true); } });
    rowsEl.addEventListener('dblclick', () => act('debug'));
    rowsEl.addEventListener('contextmenu', e => {
      e.preventDefault(); const r = e.target.closest('.prow'); if (!r) return; sel = +r.dataset.pid; render(true);
      const p = selProc();
      Menu.show(e.clientX, e.clientY, [
        { label: 'debug', fn: () => act('debug') },
        { label: p.state === 'suspended' ? 'resume' : 'suspend', fn: () => act('toggle') },
        { label: 'terminate', fn: () => act('terminate') },
        '-',
        { label: 'bring window to front', disabled: !p.win && !p.origin, fn: () => { const w = WM.wins.get(p.win || p.origin); if (w) w.focus(); } },
      ], `Process '${p.name}'`);
    });
    rowsEl.addEventListener('keydown', e => {
      if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
      e.preventDefault(); const ps = sorted(); let k = ps.findIndex(p => p.pid === sel);
      k = clamp(k + (e.key === 'ArrowDown' ? 1 : -1), 0, ps.length - 1); sel = ps[k].pid; render(true);
    });
    const sorted = () => [...Sched.procs].sort((a, b) => b.priority - a.priority || (!!b.step - !!a.step) || a.pid - b.pid);
    function render(force) {
      win.proc.flash = performance.now() + 60; // I am the active process while drawing myself
      const ps = sorted();
      if (!ps.some(p => p.pid === sel)) sel = (ps.find(p => p.step) || ps.find(p => p.kind === 'window') || ps[0]).pid;
      rowsEl.innerHTML = ps.map(p => {
        const s = p === win.proc ? 'running' : Sched.displayState(p);
        const glyph = p.kind === 'window' ? ICON.win : '';
        const cpu = p.cpu || 0;
        return `<div class="prow s-${s}${p.step ? ' busy' : ''}${p.pid === sel ? ' sel' : ''}" data-pid="${p.pid}" title="pid ${p.pid}">
          <span class="sd"></span><span class="pri">${p.priority}</span>
          <span class="nm">${glyph}<span>${esc(p.name)}${p.step && p.progress ? ` <span style="color:var(--ink-3);font-size:11px">${esc(p.progress())}</span>` : ''}</span></span>
          <span class="st">${s}</span>
          <span class="cpu"><span class="track"><i style="width:${Math.min(100, cpu).toFixed(0)}%"></i></span>${cpu.toFixed(1)}%</span></div>`;
      }).join('');
      const run = ps.filter(p => p.step).length;
      count.textContent = `${ps.length} processes · ${run} busy`;
      const p = selProc();
      bSusp.textContent = p && p.state === 'suspended' ? 'Resume' : 'Suspend';
      [bDebug, bSusp, bTerm].forEach(b => { b.disabled = !p || p.kind === 'system'; });
      const fr = p ? framesOf(p) : [];
      const key = (p && p.pid) + fr.join('|');
      if (force || key !== lastFrames) {
        lastFrames = key;
        stackL.set(fr.map((f, i) => ({ key: String(i), label: f })), '0');
        if (fr.length) showFrame(0); else srcEd.value = '';
      }
    }
    win.selectPid = pid => { sel = pid; render(true); };
    render(true);
    const iv = setInterval(() => render(false), 200);
    win.onClose = () => clearInterval(iv);
    return win;
  },

  // ---------- Notifier / Debugger
  openNotifier(o) {
    const W = 470, H = 214;
    const pos = WM.near(o.near, W, H, 70, 90);
    const win = WM.create({ title: o.title, kind: 'debugger', cls: 'notifier', x: pos.x, y: pos.y, w: W, h: H, minW: 360, minH: 180, procName: 'Debugger', priority: 40 });
    const frames = o.frames;
    const stack = new List({ cls: 'nt-stack', onSelect: k => showFrame(+k), onDbl: () => debug() });
    stack.set(frames.map((f, i) => ({ key: String(i), html: `<span class="t">${esc(f)}</span>` })));
    const code = new Editor({ win, readOnly: true, method: true });
    let done = false;
    const finish = how => {
      if (done) return; done = true;
      const p = o.proc;
      if (how === 'proceed') { if (p && p.state === 'suspended') p.state = p.step ? 'running' : 'waiting'; o.onProceed && o.onProceed(); }
      else if (p && p.state === 'suspended') {
        if (p.kind === 'user') Sched.terminate(p);
        else { p.step = null; p.state = 'waiting'; p.onAbandon && p.onAbandon(); }
      }
      win.close();
    };
    const debug = () => {
      if (win.root.classList.contains('debugging')) return;
      win.root.classList.add('debugging');
      win.setTitle('Debugger — ' + o.title);
      win.w = Math.max(win.w, 640); win.h = Math.max(win.h, 470);
      win.x = clamp(win.x, 8, innerWidth - win.w - 8); win.y = clamp(win.y, TOPBAR + 4, innerHeight - win.h - 8);
      win.apply();
      stack.select(String(frames.findIndex(f => /DoIt$/.test(f)) >= 0 && !o.interrupt ? frames.findIndex(f => /DoIt$/.test(f)) : 0));
    };
    function showFrame(i) {
      const src = frameSource(frames[i], o.doit); code.value = src;
      const r = pcRange(src, frames[i - 1]); code.setMark(r.s, r.e, 'pc');
    }
    const head = h('div', { class: 'nt-head' + (o.interrupt ? ' interrupt' : '') },
      h('div', { class: 'nt-icon', html: o.interrupt ? ICON.pause : ICON.warn }),
      h('div', { class: 'nt-msg' }, h('b', null, o.title), h('span', null, o.message)));
    const btns = h('div', { class: 'nt-btns' },
      h('button', { class: 'btn primary', onclick: () => finish('proceed') }, 'Proceed'),
      h('button', { class: 'btn', onclick: () => finish('abandon') }, 'Abandon'),
      h('button', { class: 'btn', onclick: debug }, 'Debug'),
      h('span', { class: 'sp' }),
      o.proc ? h('span', { class: 'note', style: { fontSize: '11px', color: 'var(--ink-3)', alignSelf: 'center' } }, 'other Processes keep running') : null);
    win.body.append(head, btns, stack.el, h('div', { class: 'dbg-code' }, code.el));
    win.onClose = () => { if (!done) { done = true; const p = o.proc; if (p && p.state === 'suspended') { if (p.kind === 'user') Sched.terminate(p); else { p.step = null; p.state = 'waiting'; p.onAbandon && p.onAbandon(); } } } };
    if (o.debug) debug();
    return win;
  },

  // ---------- Mandelbrot: a window whose own Process does heavy work
  openMandelbrot(o = {}) {
    const W = o.w || 330, H = o.h || 300;
    const pos = o.x != null ? o : WM.nextPos(W, H);
    let job = null;
    const frames = () => job ? ['MandelbrotView>>escapeTimeAt:', 'MandelbrotView>>renderRow:', '[] in MandelbrotView>>render', 'SmallInteger(Number)>>to:do:', 'MandelbrotView>>render', 'MandelbrotView(Widget)>>handleEvent:', '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'] : WINDOW_WAIT;
    const win = WM.create({ title: 'Mandelbrot', kind: 'mandel', x: pos.x, y: pos.y, w: W, h: H, minW: 200, minH: 160, procName: 'Mandelbrot', frames });
    win.busyLabel = 'rendering';
    const cv = h('canvas');
    const queued = h('div', { class: 'mb-queued', style: { display: 'none' } });
    const wrap = h('div', { class: 'mb-wrap' }, cv, queued);
    const info = h('span', { class: 'mono' });
    const right = h('span', { class: 'r' });
    win.body.append(wrap, h('div', { class: 'statusbar' }, info, right));
    let view = { cx: -0.62, cy: 0, span: 3.1, iter: 160 }, pending = [];
    const ctx = cv.getContext('2d');
    const lut = new Uint8ClampedArray(256 * 3);
    let inside = [22, 26, 48];
    const buildLut = () => {
      // Themes set --fractal-stops: "r g b, r g b, ..." (first = last) and --fractal-inside: "r g b".
      const cs = getComputedStyle(document.documentElement);
      const rgb = v => v.trim().split(/\s+/).map(Number);
      const stops = cs.getPropertyValue('--fractal-stops').split(',').map(rgb);
      inside = rgb(cs.getPropertyValue('--fractal-inside'));
    for (let i = 0; i < 256; i++) {
      const t = i / 256 * (stops.length - 1), k = Math.floor(t), f = t - k;
      for (let c = 0; c < 3; c++) lut[i * 3 + c] = stops[k][c] + (stops[k + 1][c] - stops[k][c]) * f;
    }
    };
    function start() {
      const dpr = Math.min(2, devicePixelRatio || 1);
      const w = Math.max(1, Math.round(wrap.clientWidth * dpr)), hh = Math.max(1, Math.round(wrap.clientHeight * dpr));
      if (cv.width !== w || cv.height !== hh) { cv.width = w; cv.height = hh; }
      buildLut();
      job = { y: 0, w, h: hh, row: ctx.createImageData(w, 1), t0: performance.now() };
      win.proc.state = 'running';
      win.proc.step = step;
      win.proc.progress = () => job ? `${Math.round(job.y / job.h * 100)}%` : '';
      win.proc.onAbandon = () => { job = null; right.textContent = 'interrupted — click to render again'; };
      info.textContent = `${view.iter} iterations · ×${(3.1 / view.span).toFixed(0)}`;
    }
    function step() {
      if (!job) return 'done';
      const { w, h: hh, row } = job, d = row.data, sc = view.span / w, max = view.iter;
      for (let rr = 0; rr < (view.iter > 200 ? 2 : 3) && job.y < hh; rr++, job.y++) {
        const ci = view.cy + (job.y - hh / 2) * sc;
        for (let x = 0; x < w; x++) {
          const cr = view.cx + (x - w / 2) * sc;
          let zr = 0, zi = 0, n = 0, zr2 = 0, zi2 = 0;
          while (n < max && zr2 + zi2 <= 16) { zi = 2 * zr * zi + ci; zr = zr2 - zi2 + cr; zr2 = zr * zr; zi2 = zi * zi; n++; }
          const o4 = x * 4;
          if (n >= max) { d[o4] = inside[0]; d[o4 + 1] = inside[1]; d[o4 + 2] = inside[2]; }
          else {
            const sm = n + 1 - Math.log2(Math.log(zr2 + zi2) / 2);
            const li = (Math.floor(Math.sqrt(Math.max(0, sm)) * 34) % 256) * 3;
            d[o4] = lut[li]; d[o4 + 1] = lut[li + 1]; d[o4 + 2] = lut[li + 2];
          }
          d[o4 + 3] = 255;
        }
        ctx.putImageData(row, 0, job.y);
      }
      right.textContent = `rendering ${Math.round(job.y / hh * 100)}%`;
      if (job.y >= hh) {
        right.textContent = `${((performance.now() - job.t0) / 1000).toFixed(1)} s in Process 'Mandelbrot'`;
        job = null;
        return 'done';
      }
    }
    win.proc.onDone = null;
    const origFinish = () => {
      if (pending.length) { const ev = pending.shift(); queued.style.display = pending.length ? '' : 'none'; zoom(ev); }
    };
    const idleCheck = setInterval(() => {
      if (!win.proc.step && pending.length) origFinish();
      queued.textContent = `${pending.length} click${pending.length > 1 ? 's' : ''} queued — this window's Process is busy`;
      queued.style.display = pending.length ? '' : 'none';
    }, 100);
    function zoom(ev) {
      const r = wrap.getBoundingClientRect(), dpr = cv.width / r.width;
      const sc = view.span / cv.width;
      view.cx += ((ev.x - r.left) * dpr - cv.width / 2) * sc;
      view.cy += ((ev.y - r.top) * dpr - cv.height / 2) * sc;
      if (ev.shift) { view.span = Math.min(3.1, view.span * 3); view.iter = Math.max(160, view.iter - 90); }
      else { view.span /= 3; view.iter += 90; }
      start();
    }
    wrap.addEventListener('click', e => {
      const ev = { x: e.clientX, y: e.clientY, shift: e.shiftKey };
      if (win.proc.step || win.proc.state === 'suspended') { pending.push(ev); queued.style.display = ''; return; }
      zoom(ev);
    });
    let rt = 0;
    win.onResize = () => { clearTimeout(rt); rt = setTimeout(() => { if (!win.proc.step) start(); }, 200); };
    win.onClose = () => clearInterval(idleCheck);
    win.render = start;
    setTimeout(start, o.delay || 50);
    return win;
  },
};
window.Tools = Tools;
