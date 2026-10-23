// Samaltak classic prototype — always-on sampling profiler (docs/design.md, "Debugging and profiling").
// The Profiler object is the Kernel-level API: a fixed 1 MB sample ring fed at every scheduler slice,
// allocation samples at bump-limit sample points, and a per-frame record. The window only reads it.
'use strict';

const Profiler = (() => {
  const RING_BYTES = 1 << 20, ALLOC_EVERY = 256 << 10, FRAME_CAP = 1500, YOUNG = 24 << 20;
  const BUDGET = 1000 / 60, DROP = BUDGET * 1.5;
  const NP = '[] in BlockClosure>>newProcess', LOOP = [NP, 'BlockClosure>>repeat'], WIN = [...LOOP, '[] in Window>>eventLoop'];

  // ---- simulated but plausible stacks, root → leaf; [weight, ...frames] / [weight, class, ...frames]
  const MB = 'MandelbrotView';
  const RR = [`${MB}>>renderRow:`, 'SmallInteger(Number)>>to:do:', `[] in ${MB}>>renderRow:`];
  const ET = [...RR, `${MB}>>escapeTimeAt:`];
  const F = 'SmallInteger(Integer)>>factorial';
  const INJ = [F, 'Interval(Collection)>>inject:into:', 'Interval>>do:', '[] in Interval(Collection)>>inject:into:', '[] in SmallInteger(Integer)>>factorial'];
  const MUL = [...INJ, 'LargePositiveInteger>>*', 'LargePositiveInteger(Integer)>>digitMultiply:neg:'];
  const CF = ['OrderedCollection>>do:', '[] in Compositor>>composeFrame'];
  const MODELS = {
    mandel: () => ({
      base: [...WIN, `${MB}(Widget)>>handleEvent:`, `${MB}>>render`, 'SmallInteger(Number)>>to:do:', `[] in ${MB}>>render`],
      cpu: [[30, ...ET], [24, ...ET, 'Complex>>squared'], [13, ...ET, 'Complex>>+'], [9, ...ET, 'Complex>>squaredMagnitude'], [3, ...ET, 'SmallInteger>>+'],
        [5, ...RR, `${MB}>>complexAt:`], [2, ...RR, `${MB}>>complexAt:`, 'Complex class>>real:imaginary:'], [4, ...RR, 'Palette>>at:'],
        [4, ...RR, 'Bitmap>>at:put:'], [2, ...RR, 'SmallInteger(Number)>>@'], [2, ...RR], [1.5, `${MB}>>publish`, 'DisplayList>>freeze'], [1, `${MB}>>publish`, 'Compositor>>invalidate:']],
      alloc: [26000, [52, 'Complex', ...ET, 'Complex>>squared', 'Complex class(Behavior)>>basicNew'], [33, 'Complex', ...ET, 'Complex>>+', 'Complex class(Behavior)>>basicNew'],
        [7, 'Complex', ...RR, `${MB}>>complexAt:`, 'Complex class>>real:imaginary:', 'Complex class(Behavior)>>basicNew'],
        [6, 'Point', ...RR, 'SmallInteger(Number)>>@', 'Point class(Behavior)>>basicNew'], [2, 'DisplayList', `${MB}>>publish`, 'DisplayList class(Behavior)>>new']],
    }),
    crunch: base => ({
      base,
      cpu: [[50, ...MUL], [9, ...MUL, 'LargePositiveInteger class(Behavior)>>new:'], [7, ...MUL, 'LargePositiveInteger(Integer)>>normalize'], [5, ...INJ, 'LargePositiveInteger>>*'],
        [6, ...INJ], [4, F, 'Interval(Collection)>>inject:into:', 'Interval>>do:'], [3, ...INJ, 'SmallInteger>>*'], [1, F, 'SmallInteger(Number)>>to:'],
        [2, 'TranscriptStream>>show:', 'TranscriptStream(WriteStream)>>nextPutAll:'], [1.2, 'SmallInteger(Number)>>printString', 'SmallInteger(Integer)>>printOn:base:'], [0.8, 'SmallInteger>>\\\\']],
      alloc: [42000, [72, 'LargePositiveInteger', ...MUL, 'LargePositiveInteger class(Behavior)>>new:'],
        [17, 'LargePositiveInteger', ...MUL, 'LargePositiveInteger(Integer)>>normalize', 'LargePositiveInteger(Integer)>>growto:', 'LargePositiveInteger class(Behavior)>>new:'],
        [5, 'Interval', F, 'SmallInteger(Number)>>to:', 'Interval class>>from:to:', 'Interval class(Behavior)>>basicNew'],
        [4, 'ByteString', 'SmallInteger(Number)>>printString', 'ByteString class(Behavior)>>new:'], [2, 'ByteString', 'TranscriptStream>>show:', 'ByteString class(Behavior)>>new:']],
    }),
    user: (base, leaf) => ({ base, cpu: [[75, ...(leaf ? [leaf] : [])], [25]], alloc: [6000, [100, 'Array', 'Array class(Behavior)>>new:']] }),
    compositor: () => ({
      base: [...LOOP, '[] in Compositor>>run', 'Compositor>>composeFrame'],
      cpu: [[26, ...CF, 'VectorRasterizer>>render:into:', 'VectorRasterizer>>encodeFlatten:on:'], [12, ...CF, 'VectorRasterizer>>render:into:', 'VectorRasterizer>>encodeBinning:'],
        [10, ...CF, 'VectorRasterizer>>render:into:', 'GPUDevice>>submit:'], [8, ...CF, 'Layer>>isDirty'],
        [22, 'VectorRasterizer>>composite:to:', 'GPUCommandEncoder>>beginRenderPass:'], [14, 'VectorRasterizer>>composite:to:', 'GPUDevice>>submit:'], [8]],
      alloc: [500, [70, 'GPUCommandEncoder', ...CF, 'VectorRasterizer>>render:into:', 'GPUDevice>>createCommandEncoder', 'GPUCommandEncoder class(Behavior)>>basicNew'],
        [30, 'Array', 'VectorRasterizer>>composite:to:', 'Array class(Behavior)>>new:']],
    }),
    input: () => ({
      base: [...LOOP, '[] in InputDispatcher>>run'],
      cpu: [[40, 'InputDispatcher>>windowAt:', 'Rectangle>>containsPoint:'], [35, 'SharedQueue>>nextPut:', 'Semaphore>>signal'], [25, 'HostEvent>>asEvent']],
      alloc: [1500, [100, 'MouseEvent', 'HostEvent>>asEvent', 'MouseEvent class(Behavior)>>basicNew']],
    }),
    timer: () => ({ base: [...LOOP, '[] in ProcessorScheduler>>timerLoop'], cpu: [[100, 'Delay class>>handleTimerEvent']] }),
    final: () => ({ base: [...LOOP, '[] in WeakRegistry class>>finalizationLoop'], cpu: [[100, 'WeakRegistry>>finalizeValues']] }),
    idle: () => ({ base: [NP, '[] in ProcessorScheduler class>>startUp', 'ProcessorScheduler>>idleProcess'], cpu: [[100, 'ProcessorScheduler>>relinquishProcessorForMicroseconds:']] }),
    procs: () => ({
      base: [...WIN, '[] in ProcessBrowser>>startStepping', 'ProcessBrowser>>updateList'],
      cpu: [[30, 'Process class(Behavior)>>allInstances'], [22, 'Array(SequenceableCollection)>>sort:'], [30, 'ProcessBrowser(Widget)>>drawOn:', 'Canvas>>drawString:at:font:color:'],
        [10, 'ProcessBrowser(Widget)>>drawOn:', 'Canvas>>fillRect:color:'], [8]],
      alloc: [4000, [60, 'Array', 'Process class(Behavior)>>allInstances', 'Array class(Behavior)>>new:'], [40, 'ByteString', 'ProcessBrowser(Widget)>>drawOn:', 'Process(Object)>>printString', 'ByteString class(Behavior)>>new:']],
    }),
    profiler: () => {
      const T = ['Profile>>tallyTree', 'SampleRing>>from:to:do:', '[] in Profile>>tallyTree'];
      return {
        base: [...WIN, '[] in ProfilerView>>startStepping', 'ProfilerView>>update'],
        cpu: [[22, ...T, 'TallyNode>>tally:by:'], [12, ...T, 'Dictionary>>at:ifAbsentPut:'], [24, 'FlameGraph>>drawOn:', 'Canvas>>fillRect:color:'], [16, 'FlameGraph>>drawOn:', 'Canvas>>drawString:at:font:color:'],
          [14, 'FrameTimeline>>drawOn:', 'Canvas>>fillRect:color:'], [6, 'ProfilerView>>updateProcessList'], [6]],
        alloc: [9000, [55, 'TallyNode', ...T, 'TallyNode>>tally:by:', 'TallyNode class(Behavior)>>basicNew'], [30, 'Association', ...T, 'Dictionary>>at:ifAbsentPut:', 'Association class>>key:value:'],
          [15, 'ByteString', 'FlameGraph>>drawOn:', 'ByteString class(Behavior)>>new:']],
      };
    },
    doit: C => ({ base: [...WIN, `${C}(Widget)>>handleEvent:`, 'TextEditor>>doIt', 'Compiler>>evaluate:for:'], cpu: [[85, 'UndefinedObject>>DoIt'], [10, 'Compiler>>compileDoIt:in:'], [5]] }),
    window: (C, text) => ({
      base: [...WIN, `${C}(Widget)>>handleEvent:`],
      cpu: [[28, `${C}(Widget)>>drawOn:`, 'Canvas>>drawString:at:font:color:'], [14, `${C}(Widget)>>drawOn:`, 'Canvas>>fillRect:color:'], [10, 'Window>>redraw', 'DisplayList>>freeze'],
        ...(text ? [[26, 'TextEditor>>keyStroke:', 'Paragraph>>composeFrom:'], [12, 'TextEditor>>doIt', 'Compiler>>evaluate:for:', 'UndefinedObject>>DoIt']] : []), [8]],
      alloc: [3000, [60, 'DisplayList', 'Window>>redraw', 'DisplayList class(Behavior)>>new'], [40, 'ByteString', `${C}(Widget)>>drawOn:`, 'ByteString class(Behavior)>>new:']],
    }),
  };
  const WIN_CLASS = { browser: 'Browser', workspace: 'Workspace', transcript: 'TranscriptView', inspector: 'Inspector', procs: 'ProcessBrowser', debugger: 'Debugger', mandel: MB, profiler: 'ProfilerView' };

  // ---- interned stacks
  const stackIds = new Map(), stacks = [];
  const intern = fr => { const k = fr.join('\n'); let id = stackIds.get(k); if (id == null) { id = stacks.length; stacks.push(fr); stackIds.set(k, id); } return id; };
  const compiled = new Map();
  function compile(m) {
    const pick = rows => { const cum = [], ids = [], cls = []; let s = 0; for (const r of rows) { s += r[0]; cum.push(s); if (typeof r[1] === 'string' && rows.alloc) { cls.push(r[1]); ids.push(intern([...m.base, ...r.slice(2)])); } else ids.push(intern([...m.base, ...r.slice(1)])); } return { cum, ids, cls, sum: s }; };
    const out = { cpu: pick(m.cpu) };
    if (m.alloc) { const rows = m.alloc.slice(1); rows.alloc = true; out.alloc = pick(rows); out.rate = m.alloc[0]; }
    return out;
  }
  const choose = c => { const r = Math.random() * c.sum; let i = 0; while (c.cum[i] < r) i++; return i; };
  function modelOf(p, variant) {
    let key, make;
    if (variant === 'doit') { const w = WM.wins.get(p.win), C = (w && WIN_CLASS[w.kind]) || p.name.replace(/\W/g, '') || 'Widget'; key = 'd:' + C; make = () => MODELS.doit(C); }
    else if (p.name === 'idle') { key = 'idle'; make = MODELS.idle; }
    else if (p.kind === 'system') {
      const n = { 'compositor (vsync)': 'compositor', 'input dispatcher': 'input', 'timer interrupt watcher': 'timer', finalization: 'final' }[p.name] || 'timer';
      key = n; make = MODELS[n];
    } else if (p.kind === 'window') {
      const w = WM.wins.get(p.win), k = w ? w.kind : '';
      if (k === 'mandel' && p.step) { key = 'mandel'; make = MODELS.mandel; }
      else if (k === 'procs') { key = 'procs'; make = MODELS.procs; }
      else if (k === 'profiler') { key = 'profiler'; make = MODELS.profiler; }
      else { const C = WIN_CLASS[k] || p.name.replace(/\W/g, '') || 'Widget'; key = 'w:' + C; make = () => MODELS.window(C, ['workspace', 'browser', 'transcript'].includes(k)); }
    } else {
      const fr = typeof p.frames === 'function' ? p.frames() : p.frames || [NP];
      const rev = [...fr].reverse(), leaf = rev[rev.length - 1];
      key = 'u:' + p.pid;
      if (leaf === F) make = () => MODELS.crunch(rev.slice(0, -1));
      else if (/>>/.test(leaf) && !/DoIt$|newProcess$/.test(leaf)) make = () => MODELS.user(rev.slice(0, -1), leaf);
      else make = () => MODELS.user(rev, null);
    }
    let c = compiled.get(key); if (!c) { c = compile(make()); compiled.set(key, c); }
    return c;
  }

  // ---- the ring: time-ordered, byte-accounted, oldest evicted first
  const ring = { buf: [], head: 0, bytes: 0, total: 0 };
  function push(s) {
    ring.buf.push(s); ring.bytes += s.z; ring.total++;
    while (ring.bytes > RING_BYTES) ring.bytes -= ring.buf[ring.head++].z;
    if (ring.head > 8192) { ring.buf = ring.buf.slice(ring.head); ring.head = 0; }
  }
  const frames = [], marks = [], procs = new Map(), pending = new Map(), carry = new Map(), aCarry = new Map();
  const gc = { young: 0, scavenges: [], phase: null, phaseEnd: 0, nextCycle: performance.now() + 5000, cycles: [] };
  let capturing = true, frameNo = 0, lastNow = 0, pausedAt = 0;

  function register(p, now) {
    let r = procs.get(p.pid);
    if (!r) { r = { pid: p.pid, name: p.name, priority: p.priority, kind: p.kind, win: p.win || null, first: now }; procs.set(p.pid, r); }
    r.last = now; r.gone = false; r.name = p.name;
    return r;
  }
  const jit = (a, b) => a + Math.random() * b;

  function frame(dt) {
    if (!capturing) { pending.clear(); lastNow = 0; return; }
    // the frame clock: rAF intervals laid end to end (performance.now() inside a late callback jitters)
    const wall = performance.now(), now = lastNow && Math.abs(wall - lastNow - dt) < 50 ? lastNow + dt : wall;
    const t0 = now - dt; frameNo++;
    const segs = [...pending]; pending.clear();
    const charged = new Set(segs.map(s => s[0]));
    const nW = WM.wins.size, drag = WM.dragging;
    const comp = Sched.byName('compositor (vsync)'), idleP = Sched.byName('idle');
    const busyWin = segs.some(([p]) => p.kind === 'window' && p.step);
    const draw = jit(0.2 + 0.045 * nW + (drag ? 0.7 : 0), 0.12), raster = jit(0.16 + (busyWin ? 0.45 : 0) + (drag ? 0.35 : 0), 0.15);
    const gpu = jit(0.4 + 0.07 * nW + raster * 0.9, 0.25);
    if (comp) segs.push([comp, draw + raster]);
    for (const p of Sched.procs) {
      if (p.step || p === comp || p === idleP || charged.has(p) || p.state === 'suspended') continue;
      if (p.flash > wall - Math.min(dt, 1000)) segs.push([p, p.name === 'input dispatcher' ? jit(0.12, 0.1) : jit(0.3, 0.3)]);
      else if (p.name === 'timer interrupt watcher' && frameNo % 6 === 0) segs.push([p, 0.12]);
      else if (p.name === 'finalization' && frameNo % 240 === 0) segs.push([p, 0.3]);
    }
    for (const p of Sched.procs) register(p, now);
    // a runnable green thread takes every cycle the higher-priority ones leave (as the Process Browser shows)
    const span = Math.min(dt, 1000), run = Sched.runnable();
    // a late frame with no long slice: the window that just handled an event (a do it) held the thread
    if (dt > DROP && !segs.some(([p, ms]) => p.step && ms > dt / 2)) {
      const ev = segs.filter(([p]) => p.kind === 'window' && !p.step && p.flash > wall - dt && !['procs', 'profiler'].includes((WM.wins.get(p.win) || {}).kind)).sort((p, q) => q[0].flash - p[0].flash).slice(0, 1);
      ev.forEach(sg => { sg[1] += (span - BUDGET) / ev.length; sg[2] = 'doit'; });
    }
    const others = segs.reduce((s, [p, ms]) => s + (run.includes(p) ? 0 : ms), 0);
    const share = run.length ? Math.max(0, span - others) * jit(0.95, 0.03) / run.length : 0;
    for (const p of run) { const i = segs.findIndex(q => q[0] === p); if (i < 0) segs.push([p, share]); else segs[i][1] = Math.max(segs[i][1], share); }
    // allocation: bump-limit sample points, young-generation scavenges, a C4-style concurrent cycle
    let gcRec = null, alloc = 0;
    for (const [p, ms] of segs) { const m = modelOf(p); if (m.alloc) alloc += ms * m.rate; }
    gc.young += alloc;
    if (gc.young > YOUNG) { gc.young = 0; gcRec = { kind: 'scavenge', ms: jit(0.3, 0.45) }; gc.scavenges.push({ t: now, ms: gcRec.ms }); if (gc.scavenges.length > 400) gc.scavenges.shift(); }
    if (!gc.phase && now > gc.nextCycle) { gc.phase = 'mark'; gc.phaseEnd = now + jit(700, 500); gc.cycles.push({ t: now }); if (gc.cycles.length > 50) gc.cycles.shift(); if (!gcRec) gcRec = { kind: 'handshake (mark start)', ms: 0.06 }; }
    else if (gc.phase && now > gc.phaseEnd) {
      const next = { mark: 'relocate', relocate: 'remap', remap: null }[gc.phase];
      if (!gcRec) gcRec = { kind: `handshake (${next || 'cycle end'})`, ms: 0.05 };
      gc.phase = next; gc.phaseEnd = now + jit(250, 250);
      if (!next) gc.nextCycle = now + jit(5000, 4000);
    }
    // samples: one per ms of CPU (1 kHz timer interrupt, taken at the next safepoint)
    let cur = t0, busy = gcRec ? gcRec.ms : 0;
    const rec = { n: frameNo, t: now, dt, segs: [], draw, raster, gpu, gc: gcRec, phase: gc.phase, samples: 0, alloc };
    const emit = (p, ms, variant) => {
      const m = modelOf(p, variant), r = register(p, now);
      let c = (carry.get(p.pid) || 0) + ms; const n = Math.floor(c); carry.set(p.pid, c - n);
      for (let k = 0; k < n; k++) {
        const i = choose(m.cpu), sid = m.cpu.ids[i];
        push({ t: cur + (k + 0.5) * ms / Math.max(1, n), pid: r.pid, sid, b: 0, z: 24 + 8 * stacks[sid].length });
      }
      rec.samples += n;
      if (m.alloc) {
        let a = (aCarry.get(p.pid) || 0) + ms * m.rate * jit(0.8, 0.4);
        while (a >= ALLOC_EVERY) { a -= ALLOC_EVERY; const i = choose(m.alloc); const sid = m.alloc.ids[i]; push({ t: cur + ms / 2, pid: r.pid, sid, b: ALLOC_EVERY, c: m.alloc.cls[i], z: 32 + 8 * stacks[sid].length }); }
        aCarry.set(p.pid, a);
      }
      cur += ms;
    };
    for (const [p, ms, v] of segs) { if (ms <= 0) continue; rec.segs.push([register(p, now).pid, ms]); busy += ms; emit(p, ms, v); }
    if (idleP) { const ms = Math.max(0, span - busy); if (ms > 0) { rec.segs.push([register(idleP, now).pid, ms]); emit(idleP, ms); } }
    frames.push(rec); if (frames.length > FRAME_CAP) frames.shift();
    for (const r of procs.values()) if (r.last !== now) r.gone = true;
    lastNow = now;
  }

  const lower = (arr, from, t, key) => { let lo = from, hi = arr.length; while (lo < hi) { const m = (lo + hi) >> 1; if (key(arr[m]) < t) lo = m + 1; else hi = m; } return lo; };
  const api = {
    BUDGET, DROP, RING_BYTES, ALLOC_EVERY, stacks, procs, marks, frames, gc,
    get capturing() { return capturing; },
    get now() { return capturing ? performance.now() : pausedAt; },
    pause() { if (capturing) { capturing = false; pausedAt = performance.now(); } },
    resume() { capturing = true; },
    onRan(p, ms) { pending.set(p, (pending.get(p) || 0) + ms); },
    charge(p, ms) { if (p && capturing) pending.set(p, (pending.get(p) || 0) + ms); },
    frame,
    mark(label) { const m = { t: this.now, label: label || `mark ${marks.length + 1}` }; marks.push(m); if (marks.length > 40) marks.shift(); return m; },
    size() { return ring.buf.length - ring.head; },
    bytes() { return ring.bytes; },
    oldest() { const s = ring.buf[ring.head]; return s ? s.t : this.now; },
    // iterate samples with a <= t <= b
    each(a, b, f) { const buf = ring.buf; for (let i = lower(buf, ring.head, a, s => s.t); i < buf.length && buf[i].t <= b; i++) f(buf[i]); },
    framesIn(a, b) { const i = lower(frames, 0, a, f => f.t); const out = []; for (let k = i; k < frames.length && frames[k].t - frames[k].dt <= b; k++) out.push(frames[k]); return out; },
  };
  Sched.onRan = (p, ms) => api.onRan(p, ms);
  Sched.listeners.add(dt => frame(dt));
  return api;
})();
window.Profiler = Profiler;

// ---------------------------------------------------------------- the image knows these classes
(function addProfilerClasses() {
  const pkg = n => FakeImage.packages.find(p => p.name === n);
  const add = (pn, c) => { const p = pkg(pn); if (p && !FakeImage.findClass(c.name)) p.classes.push(c); };
  add('Kernel-Numbers', {
    name: 'Complex', superclass: 'Number', ivars: ['real', 'imaginary'],
    comment: 'I am a complex number. Unlike SmallIntegers and Floats I live on the heap, so every arithmetic result is a fresh allocation.',
    protocols: { arithmetic: {
      squared: 'squared\n\t"Answer the receiver times itself. Allocates one Complex."\n\n\t^Complex\n\t\treal: real * real - (imaginary * imaginary)\n\t\timaginary: 2 * real * imaginary',
      '+ aComplex': '+ aComplex\n\t^Complex\n\t\treal: real + aComplex real\n\t\timaginary: imaginary + aComplex imaginary',
      squaredMagnitude: 'squaredMagnitude\n\t^real * real + (imaginary * imaginary)' } },
  });
  add('Kernel-Numbers', {
    name: 'LargePositiveInteger', superclass: 'Integer', ivars: [],
    comment: 'I am an arbitrary-precision positive integer, stored as bytes on the heap.',
    protocols: { arithmetic: {
      '* aNumber': '* aNumber\n\t"Primitive 29 handles 64-bit results; the fallback multiplies digit by digit."\n\n\t<primitive: 29>\n\t^self digitMultiply: aNumber neg: aNumber negative' },
    'private': {
      'digitMultiply: arg neg: aBoolean': 'digitMultiply: arg neg: aBoolean\n\t| prod |\n\tprod := LargePositiveInteger new: self digitLength + arg digitLength.\n\tprod primDigitMultiply: self by: arg.\n\t^prod normalize',
      normalize: 'normalize\n\t"Strip leading zero digits; answer a SmallInteger if I fit."\n\n\t<primitive: \'primNormalizePositive\' module: \'LargeIntegers\'>\n\t^self growto: self digitLength' } },
  });
  add('Kernel-Processes', {
    name: 'SamplingProfiler', superclass: 'Object', ivars: ['ring', 'frames', 'marks', 'timer', 'allocationInterval'],
    comment: 'I am the always-on profiler; the single instance is the global Profiler. A timer interrupt makes the VM record the active Process\'s stack at its next safepoint into a fixed 1 MB ring. Allocation samples piggyback on the bump allocator\'s limit check. The compositor adds one FrameRecord per presented frame. Profile data are ordinary objects; tools never call raw primitives.',
    protocols: {
      accessing: {
        last: 'last\n\t"Answer a Profile over everything still in the ring."\n\n\t^Profile on: self from: ring oldestTime to: Time millisecondClock',
        buffer: 'buffer\n\t^ring',
        frames: 'frames\n\t^frames' },
      sampling: {
        sampleActiveProcess: 'sampleActiveProcess\n\t"Run by the VM at the first safepoint after the profiler timer fired.\n\t Copies method and pc of each Context of the active Process into the\n\t ring. Never allocates, never sends."\n\n\t<primitive: \'primitiveRecordSample\'>',
        'mark: aString': 'mark: aString\n\t"Drop a labelled marker into the ring and the frame timeline."\n\n\tmarks add: (ProfileMark label: aString at: Time millisecondClock)' },
      control: {
        pause: 'pause\n\ttimer disable',
        resume: 'resume\n\ttimer enable' },
    },
  });
  add('Kernel-Processes', {
    name: 'SampleRing', superclass: 'Object', ivars: ['bytes', 'head', 'tail'],
    comment: 'I am a fixed 1 MB ring of samples. When full I overwrite the oldest; the sampling path never allocates.',
    protocols: { enumerating: { 'from: t0 to: t1 do: aBlock': 'from: t0 to: t1 do: aBlock\n\t| i |\n\ti := self indexOfTime: t0.\n\t[i ~= tail and: [(self timeAt: i) <= t1]] whileTrue: [\n\t\taBlock value: (self sampleAt: i).\n\t\ti := self next: i]' } },
  });
  add('Kernel-Processes', {
    name: 'Profile', superclass: 'Object', ivars: ['profiler', 'start', 'stop', 'process'],
    comment: 'I am a window onto the sample ring: a time range, optionally one Process. I answer samples, allocations, frames and a MessageTally-style tree.',
    protocols: { accessing: {
      samples: 'samples\n\t^SampleSet withAll: (profiler buffer from: start to: stop select: [:s |\n\t\tprocess isNil or: [s process == process]])',
      tallyTree: 'tallyTree\n\t| root |\n\troot := TallyNode new.\n\tprofiler buffer from: start to: stop do: [:s |\n\t\troot tally: s stack reversed by: 1].\n\t^root' } },
  });
  add('Kernel-Processes', {
    name: 'FrameRecord', superclass: 'Object', ivars: ['number', 'presented', 'duration', 'processes', 'draw', 'raster', 'gpu', 'gcPhases'],
    comment: 'I record one presented frame: which Processes ran and for how long, draw and raster times, the GPU timestamp query, GC phases.',
    protocols: { testing: { isDropped: 'isDropped\n\t^duration > (Display refreshInterval * 3 / 2)' } },
  });
  const src = k => (typeof EXTRA_SRC !== 'undefined' && EXTRA_SRC[k]) || null;
  add('Tools', {
    name: 'MandelbrotView', superclass: 'Widget', ivars: ['bitmap', 'palette', 'width', 'height', 'maxIterations'],
    comment: 'I render the Mandelbrot set in my window\'s Process. The compositor keeps showing my last published DisplayList.',
    protocols: { rendering: {
      render: src('MandelbrotView>>render') || 'render',
      'renderRow: y': src('MandelbrotView>>renderRow:') || 'renderRow: y',
      'escapeTimeAt: c': src('MandelbrotView>>escapeTimeAt:') || 'escapeTimeAt: c',
      'complexAt: aPoint': 'complexAt: aPoint\n\t^Complex\n\t\treal: origin x + (aPoint x * scale)\n\t\timaginary: origin y + (aPoint y * scale)',
      publish: 'publish\n\t"Freeze my DisplayList and hand it to the compositor."\n\n\tself owner layer publish: canvas displayList freeze' } },
  });
})();

// ---------------------------------------------------------------- helpers
const PF = {
  num: n => Math.round(n).toLocaleString('en-US'),
  pct: (a, b) => (b ? a / b * 100 : 0).toFixed(1) + '%',
  ms: v => (v >= 100 ? v.toFixed(0) : v.toFixed(1)) + ' ms',
  bytes: b => b >= 1 << 20 ? (b / (1 << 20)).toFixed(1) + ' MB' : b >= 1024 ? (b / 1024).toFixed(0) + ' KB' : b + ' B',
  secs: ms => (ms / 1000).toFixed(1) + ' s',
  // "Class(Impl)>>sel" → CompiledMethod print "Impl>>#sel"
  methodPrint(label) {
    const blk = /^\[\] in /.test(label), m = label.replace(/^\[\] in /, '').match(/^(\w+)( class)?(?:\((\w+)\))?>>(.+)$/);
    if (!m) return label;
    return `${blk ? '[] in ' : ''}${m[3] || m[1]}${m[3] ? '' : m[2] || ''}>>#${m[4]}`;
  },
  browse(label, near) {
    const m = label.replace(/^\[\] in /, '').match(/^(\w+)( class)?(?:\((\w+)\))?>>(.+)$/);
    if (!m) { Toast.show(`${label} is not a method`); return; }
    const clsName = m[3] || m[1], sel = m[4], classSide = !!m[2] && !m[3];
    const cls = FakeImage.findClass(clsName);
    if (!cls) { Toast.show(`${clsName} is not part of this prototype image`); return; }
    const protos = classSide ? cls.classSide || {} : cls.protocols;
    for (const [pn, proto] of Object.entries(protos)) for (const k of Object.keys(proto))
      if (selectorOf(k) === sel && !classSide) return Tools.openBrowser({ cls: clsName, proto: pn, sel: k, near });
    Tools.openBrowser({ cls: clsName, near });
    Toast.show(`${clsName}${classSide ? ' class' : ''}>>${sel} is not part of this prototype image`);
  },
};

// Evaluator pane: profile data are objects. A tiny pattern-matched stand-in for the real compiler.
class ProfEditor extends Editor {
  action(act) {
    if (act === 'do' || act === 'print' || act === 'inspect') {
      const { s, e, text } = this.selectionOrLine();
      const r = this.o.evaluate(text.trim().replace(/\.$/, ''));
      if (r) {
        if (this.win && this.win.proc) Sched.poke(this.win.proc, 200);
        if (r.error) this.insertAfter(e, ` ‹${r.error}›`, 'error');
        else if (act === 'do') this.setMark(s, e, 'flash', 600);
        else this.insertAfter(e, ' ' + r.print, 'result');
        return;
      }
    }
    super.action(act);
  }
}

// ---------------------------------------------------------------- the Profiler window
Tools.openProfiler = function (o = {}) {
  const existing = [...WM.wins.values()].find(w => w.kind === 'profiler');
  if (existing) { existing.focus(); if (o.select != null) existing.selectProc(o.select); return existing; }
  const W = o.w || 900, H = o.h || 660;
  const x = clamp(o.x != null ? o.x : 100, 8, Math.max(8, innerWidth - W - 8)), y = clamp(o.y != null ? o.y : TOPBAR + 40, TOPBAR + 8, Math.max(TOPBAR + 8, innerHeight - H - 8));
  const win = WM.create({ title: 'Profiler', kind: 'profiler', x, y, w: W, h: H, minW: 620, minH: 420, procName: 'Profiler',
    frames: () => ['ProfilerView>>update', '[] in ProfilerView>>startStepping', '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'] });
  const S = { tab: 'flame', pid: o.select != null ? String(o.select) : 'all', sel: null, pin: null, bigEnd: null, frame: null, span: 2000,
    zoom: { cpu: [], alloc: [] }, open: new Map(), pick: null, hover: null, hoverFrame: null, lastDown: null };

  // ---- toolbar
  const btn = (l, f, t) => h('button', { class: 'btn', title: t || '', onclick: f }, l);
  const capLbl = h('span', { class: 'live pf-cap' }, h('i'), 'capturing');
  const bPause = btn('Pause', () => { Profiler.capturing ? Profiler.pause() : Profiler.resume(); render(true); }, 'pause / resume capture (the ring keeps its data)');
  const bMark = btn('Mark', () => { const m = Profiler.mark(); Toast.show(`${m.label} — also from code: Profiler mark: 'label'`); render(true); }, 'drop a marker into the timeline');
  const tabs = h('div', { class: 'seg pf-tabs', 'data-role': 'tabs' });
  const tabB = {};
  for (const [k, l] of [['tally', 'Tally'], ['flame', 'Flame graph'], ['alloc', 'Allocations'], ['frames', 'Frames']]) {
    tabB[k] = h('button', { 'data-role': 'tab', 'data-label': l, onclick: () => setTab(k) }, l);
    tabs.append(tabB[k]);
  }
  const stats = h('span', { class: 'note pf-stats', 'data-role': 'ring-stats' });
  win.body.append(h('div', { class: 'toolbar pf-bar' }, bPause, bMark, h('span', { class: 'pf-gap' }), tabs, h('span', { class: 'sp' }), stats, capLbl));

  // ---- left: processes
  const procL = new List({ cls: 'pf-procs', onSelect: k => { S.pid = k; S.zoom = { cpu: [], alloc: [] }; S.pick = null; render(true); } });
  const left = h('div', { class: 'pane pf-left' }, h('div', { class: 'pane-h' }, 'Processes', h('span', { class: 'r' }, 'of samples')), procL.el);

  // ---- overview strip
  const stripCv = h('canvas', { class: 'pf-cv', tabindex: '-1', 'data-role': 'frame-timeline-overview' });
  const stripNote = h('span', { class: 'r' });
  const strip = h('div', { class: 'pf-strip' }, h('div', { class: 'pane-h' }, 'Frames', stripNote), h('div', { class: 'pf-cvwrap' }, stripCv));

  // ---- views
  const tallyEl = h('div', { class: 'pf-tally', 'data-role': 'tally-tree' });
  const tallyV = h('div', { class: 'pf-view' }, h('div', { class: 'pane-h' }, 'MessageTally', h('span', { class: 'r' }, 'click ▸ to expand · double-click a method to browse')), tallyEl);
  const crumbs = { cpu: h('span', { class: 'pf-crumbs' }), alloc: h('span', { class: 'pf-crumbs' }) };
  const flameEl = { cpu: h('div', { class: 'pf-flame', 'data-role': 'flame-graph' }), alloc: h('div', { class: 'pf-flame', 'data-role': 'alloc-flame-graph' }) };
  const flameV = h('div', { class: 'pf-view' }, h('div', { class: 'pane-h' }, 'Flame graph', crumbs.cpu, h('span', { class: 'r' }, 'click: zoom · double-click: browse')), flameEl.cpu);
  const sitesEl = h('div', { class: 'pf-sites', 'data-role': 'alloc-sites' });
  const allocV = h('div', { class: 'pf-view' }, h('div', { class: 'pane-h' }, 'Allocations', crumbs.alloc, h('span', { class: 'r' }, 'sampled every 256 KB at the bump limit')), flameEl.alloc,
    h('div', { class: 'pane-h pf-sites-h' }, 'Top allocating sites'), sitesEl);
  const bigCv = h('canvas', { class: 'pf-cv', tabindex: '-1', 'data-role': 'frame-timeline' });
  const spanSeg = h('span', { class: 'pf-span' });
  for (const [ms, l] of [[2000, '2 s'], [5000, '5 s'], [0, 'all']]) spanSeg.append(h('button', { 'data-span': ms, onclick: () => { S.span = ms; if (S.sel) follow(); else S.bigEnd = null; render(true); } }, l));
  const legend = h('span', { class: 'pf-legend' }, ...[['proc', 'Processes'], ['other', 'system'], ['draw', 'draw'], ['raster', 'raster'], ['gpu', 'GPU'], ['gc', 'GC']].map(([k, l]) => h('span', null, h('i', { class: 'sw-' + k }), l)), h('span', null, h('i', { class: 'sw-budget' }), '16.7 ms'));
  const legendOther = legend.children[1].lastChild;
  const recEl = h('div', { class: 'pf-rec', 'data-role': 'frame-record' });
  const framesV = h('div', { class: 'pf-view' }, h('div', { class: 'pane-h' }, 'Frame timeline', legend, h('span', { class: 'r' }, spanSeg)), h('div', { class: 'pf-cvwrap pf-big' }, bigCv), recEl);
  const views = { tally: tallyV, flame: flameV, alloc: allocV, frames: framesV };
  const right = h('div', { class: 'pf-right' }, strip, ...Object.values(views));
  const tip = h('div', { class: 'pf-tip', 'data-role': 'tooltip', hidden: true });

  // ---- evaluator
  const ev = new ProfEditor({ win, workspace: win.id, cls: 'pf-ed', evaluate: s => evaluate(s),
    value: 'Profiler last samples groupBy: #method\nProfiler last frames detectMax: [:f | f duration]\nProfiler mark: \'before zoom\'' });
  const evalP = h('div', { class: 'pane pf-eval' }, h('div', { class: 'pane-h' }, 'Evaluate', h('span', { class: 'r' }, `profile data are objects · ${MOD}P print it`)), ev.el);

  // ---- status
  const rangeLbl = h('span', { class: 'pf-range' });
  const bClear = h('button', { class: 'btn pf-clear', onclick: () => clearSel() }, 'clear range');
  const pickLbl = h('span', { class: 'mono pf-pick' });
  const bBrowse = h('button', { class: 'btn', onclick: () => S.pick && PF.browse(S.pick, win) }, 'browse');
  const status = h('div', { class: 'statusbar pf-status' }, rangeLbl, bClear, h('span', { class: 'r' }, pickLbl, bBrowse));

  win.body.append(h('div', { class: 'pf-main' }, left, right), evalP, status, tip);

  // ---------------------------------------------------------------- data
  const procName = pid => { const r = Profiler.procs.get(+pid); return r ? r.name : '?'; };
  const isIdle = pid => procName(pid) === 'idle';
  function range() {
    if (S.sel) return { a: S.sel[0], b: S.sel[1] };
    const now = S.pin ? S.pin.end : Profiler.now;
    return { a: S.pin ? S.pin.start : Profiler.oldest(), b: now };
  }
  // samples in range → {pid → {sid → weight}}, per-process CPU counts
  function gather(alloc) {
    const { a, b } = range(), by = new Map(), cpu = new Map(); let total = 0, wsum = 0;
    Profiler.each(a, b, s => {
      if (!s.b) { cpu.set(s.pid, (cpu.get(s.pid) || 0) + 1); total++; }
      if (!!s.b !== alloc) return;
      if (S.pid === 'all' ? isIdle(s.pid) : String(s.pid) !== S.pid) return;
      let m = by.get(s.pid); if (!m) by.set(s.pid, m = new Map());
      const w = s.b || 1; m.set(s.sid, (m.get(s.sid) || 0) + w); wsum += w;
    });
    return { by, cpu, total, wsum, a, b };
  }
  function tree(g) {
    const node = name => ({ name, total: 0, self: 0, kids: new Map() });
    const all = S.pid === 'all';
    const root = node(all ? 'all Processes' : `Process '${procName(S.pid)}'`);
    root.pid = all ? null : +S.pid;
    for (const [pid, m] of g.by) {
      let top = root;
      if (all) { const nm = `Process '${procName(pid)}'`; top = root.kids.get(nm); if (!top) { root.kids.set(nm, top = node(nm)); top.pid = pid; } }
      for (const [sid, w] of m) {
        let n = top; root.total += w; if (all) top.total += w;
        for (const f of Profiler.stacks[sid]) { let k = n.kids.get(f); if (!k) n.kids.set(f, k = node(f)); k.total += w; n = k; }
        n.self += w;
      }
    }
    return root;
  }
  const kidsSorted = n => [...n.kids.values()].sort((p, q) => q.total - p.total);

  // ---------------------------------------------------------------- render
  let lastTab = null;
  function setTab(k) { S.tab = k; render(true); }
  function render(force) {
    if (win.root.classList.contains('collapsed') || !WM.wins.has(win.id)) return;
    if (!force && !Profiler.capturing) return;
    const t0 = performance.now();
    if (lastTab !== S.tab) { lastTab = S.tab; for (const [k, v] of Object.entries(views)) v.hidden = k !== S.tab; Object.entries(tabB).forEach(([k, b]) => b.classList.toggle('on', k === S.tab)); }
    const cov = Profiler.now - Profiler.oldest(), full = Profiler.bytes() > Profiler.RING_BYTES * 0.97;
    stats.textContent = `${PF.num(Profiler.size())} samples · last ${PF.secs(cov)} · ${full ? '1.0 MB ring' : `${(Profiler.bytes() / (1 << 20)).toFixed(2)} of 1.0 MB ring`}`;
    stats.dataset.label = stats.textContent;
    capLbl.lastChild.textContent = Profiler.capturing ? 'capturing' : 'paused';
    capLbl.classList.toggle('off', !Profiler.capturing);
    bPause.textContent = Profiler.capturing ? 'Pause' : 'Resume';
    legendOther.textContent = S.pid === 'all' ? 'system' : 'others';
    spanSeg.querySelectorAll('button').forEach(b => b.classList.toggle('on', +b.dataset.span === S.span));
    const g = gather(S.tab === 'alloc');
    renderProcs(g);
    drawTimeline(stripCv, false);
    if (S.tab === 'tally') renderTally(g);
    else if (S.tab === 'flame') renderFlame(g, 'cpu');
    else if (S.tab === 'alloc') { renderFlame(g, 'alloc'); renderSites(g); }
    else { drawTimeline(bigCv, true); renderRecord(); }
    renderStatus(g);
    win.proc.flash = performance.now() + 60;
    Profiler.charge(win.proc, performance.now() - t0);
  }
  function renderProcs(g) {
    const rows = [...g.cpu].sort((p, q) => q[1] - p[1]);
    const nonIdle = rows.filter(([pid]) => !isIdle(pid)).reduce((s, r) => s + r[1], 0);
    const item = (key, name, n, cls, glyph) => ({ key, cls, html: `${glyph || ''}<span class="t">${esc(name)}</span><span class="pf-pbar"><i style="width:${Math.min(100, n / Math.max(1, g.total) * 100).toFixed(1)}%"></i></span><span class="pf-pct">${PF.pct(n, g.total)}</span>` });
    const items = [item('all', 'All but idle', nonIdle, 'pf-all')];
    for (const [pid, n] of rows) {
      const r = Profiler.procs.get(pid);
      items.push(item(String(pid), r.name, n, (r.gone ? 'gone' : '') + (r.name === 'idle' ? ' idle' : ''), r.kind === 'window' ? ICON.win : ''));
    }
    if (S.pid !== 'all' && !items.some(i => i.key === S.pid)) items.push(item(S.pid, procName(S.pid), 0, 'gone'));
    procL.set(items, S.pid);
  }

  // ---- tally tree (Squeak MessageTally format)
  function renderTally(g) {
    const root = tree(g), total = root.total || 1, msPer = 1; // one sample per ms
    const out = [];
    const line = (html, cls, attrs = '') => out.push(`<div class="tl${cls ? ' ' + cls : ''}"${attrs}>${html}</div>`);
    const span = g.b - g.a;
    line(` - ${PF.num(total)} tallies, ${PF.num(total * msPer)} msec.${S.pid === 'all' ? `  (idle excluded: ${PF.pct(g.total - total, g.total)})` : ''}`, 'hd');
    line(`   sampled at 1 kHz over ${PF.secs(span)}${S.sel ? ' (selected range)' : ' (whole ring)'}`, 'hd dim');
    line('', '');
    line('**Tree**', 'sec');
    const sections = S.pid === 'all' ? kidsSorted(root) : [root];
    for (const sec of sections) {
      const pr = Profiler.procs.get(sec.pid);
      line('--------------------------------', 'rule');
      line(`Process: (${pr ? pr.priority : '?'}) ${sec.pid}: ${esc(pr ? pr.name : '?')}`, 'proc');
      line('--------------------------------', 'rule');
      const walk = (n, depth, path) => {
        for (const k of kidsSorted(n)) {
          if (k.total / total < 0.005) continue;
          const p = path + '\n' + k.name;
          const has = [...k.kids.values()].some(c => c.total / total >= 0.005);
          const open = S.open.has(p) ? S.open.get(p) : k.total / total >= 0.02;
          const guides = '  |'.repeat(depth);
          const pc = (k.total / total * 100).toFixed(1).padStart(depth ? 4 : 5);
          line(`<span class="g">${guides}</span><span class="tg" data-p="${esc(p)}">${has ? (open ? '▾' : '▸') : ' '}</span>${pc}% {${PF.num(k.total)}ms} <span class="m${S.pick === k.name ? ' pick' : ''}" data-m="${esc(k.name)}">${esc(k.name)}</span>`,
            '', ` data-role="tally-node" data-label="${esc(`${k.name} ${pc.trim()}%`)}"`);
          if (has && open) walk(k, depth + 1, p);
        }
      };
      walk(sec, 0, String(sec.pid));
    }
    line('', '');
    line('**Leaves**', 'sec');
    const leaves = new Map();
    const lw = n => { if (n.self) leaves.set(n.name, (leaves.get(n.name) || 0) + n.self); n.kids.forEach(lw); };
    lw(root);
    for (const [m, n] of [...leaves].sort((p, q) => q[1] - p[1]).slice(0, 14)) {
      if (n / total < 0.005) break;
      line(`${(n / total * 100).toFixed(1).padStart(5)}% {${PF.num(n)}ms} <span class="m${S.pick === m ? ' pick' : ''}" data-m="${esc(m)}">${esc(m)}</span>`, '', ` data-role="tally-leaf" data-label="${esc(m)}"`);
    }
    // memory and GC, from allocation samples and frame records in range
    let ab = 0; Profiler.each(g.a, g.b, s => { if (s.b && (S.pid === 'all' || String(s.pid) === S.pid)) ab += s.b; });
    const fr = Profiler.framesIn(g.a, g.b), sc = fr.filter(f => f.gc && f.gc.kind === 'scavenge'), hs = fr.filter(f => f.gc && f.gc.kind !== 'scavenge');
    const scMs = sc.reduce((s, f) => s + f.gc.ms, 0);
    line('', '');
    line('**Memory**', 'sec');
    line(`\tyoung\t\t+${PF.num(ab)} bytes  (${PF.num(ab / Profiler.ALLOC_EVERY)} samples × 256 KB)`, '');
    line(`\trate\t\t${PF.bytes(ab / Math.max(0.001, span / 1000))}/s`, '');
    line('**GCs**', 'sec');
    line(`\tscavenges\t${sc.length} totalling ${scMs.toFixed(1)} ms (${sc.length ? (scMs / sc.length).toFixed(2) : '0.00'} ms average)`, '');
    line(`\tconcurrent\t${hs.length} handshakes totalling ${hs.reduce((s, f) => s + f.gc.ms, 0).toFixed(2)} ms — mark, relocate, remap run beside the mutator`, '');
    tallyEl.innerHTML = out.join('');
  }
  tallyEl.addEventListener('pointerdown', e => {
    const tg = e.target.closest('.tg');
    if (tg && tg.textContent.trim()) { const p = tg.dataset.p; const cur = tg.textContent === '▾'; S.open.set(p, !cur); render(true); return; }
    const m = e.target.closest('.m');
    if (m) pickMethod(m.dataset.m, e);
  });

  // ---- flame graph (icicle, top-down)
  const ROW = 19;
  let flameNodes = { cpu: [], alloc: [] };
  function renderFlame(g, kind) {
    const root = tree(g), el = flameEl[kind], unit = kind === 'alloc' ? b => PF.bytes(b) : n => `${PF.num(n)} samples`;
    // resolve zoom path
    const path = [root]; for (const nm of S.zoom[kind]) { const k = path[path.length - 1].kids.get(nm); if (!k) break; path.push(k); }
    S.zoom[kind] = path.slice(1).map(n => n.name);
    const z = path[path.length - 1], zt = z.total || 1, rt = root.total || 1;
    let maxSelf = 0; const ms = n => { maxSelf = Math.max(maxSelf, n.self); n.kids.forEach(ms); }; ms(z);
    const list = [], html = [];
    path.slice(0, -1).forEach((n, i) => list.push({ n, x: 0, w: 1, d: i, anc: true, zi: i }));
    const lay = (n, x, w, d) => {
      list.push({ n, x, w, d, zi: -1 });
      let cx = x;
      for (const k of kidsSorted(n)) { const kw = w * k.total / n.total; if (kw * 640 >= 1.2) lay(k, cx, kw, d + 1); cx += kw; }
    };
    lay(z, 0, 1, path.length - 1);
    const px = el.clientWidth || 640;
    list.forEach((f, i) => {
      const hh = f.anc ? 0.04 : 0.05 + 0.88 * Math.sqrt(maxSelf ? f.n.self / maxSelf : 0);
      const label = f.n.name, pc = PF.pct(f.n.total, rt);
      const cls = 'ff' + (f.anc ? ' anc' : '') + (hh > 0.52 ? ' dk' : '') + (S.pick === label ? ' pick' : '') + (S.hover === label + '\n' + f.d ? ' hov' : '') + (f.w * px < 30 ? ' tiny' : '') + (/^Process '/.test(label) ? ' pr' : '');
      html.push(`<div class="${cls}" data-i="${i}" data-role="flame-frame" data-label="${esc(`${label} ${pc} (${unit(f.n.total)})`)}" style="left:${(f.x * 100).toFixed(4)}%;width:${(f.w * 100).toFixed(4)}%;top:${f.d * ROW}px;--h:${hh.toFixed(3)}">${f.w * px >= 30 ? esc(label) : ''}</div>`);
    });
    const depth = list.reduce((m, f) => Math.max(m, f.d), 0);
    html.push(`<div class="pf-flame-pad" style="top:${(depth + 1) * ROW + 6}px"></div>`);
    if (!root.total) html.push(`<div class="pf-empty">No ${kind === 'alloc' ? 'allocation ' : ''}samples for this Process in the selected range.</div>`);
    el.innerHTML = html.join('');
    flameNodes[kind] = list;
    if (S.move && S.move.kind === kind) { const t = document.elementFromPoint(S.move.clientX, S.move.clientY); if (t && el.contains(t)) hoverFlame(kind, { target: t, clientX: S.move.clientX, clientY: S.move.clientY }); }
    el.dataset.label = `${kind === 'alloc' ? 'Allocation' : 'CPU'} flame graph of ${root.name}: ${unit(root.total)}; zoomed to ${z.name}`;
    crumbs[kind].innerHTML = path.map((n, i) => `<a data-z="${i}">${esc(i === 0 ? (S.pid === 'all' ? 'all' : n.name) : n.name.replace(/^Process /, ''))}</a>`).join('<b>›</b>') +
      `<em>${unit(root.total)}${kind === 'alloc' ? ` · ${PF.bytes(root.total / Math.max(0.001, (g.b - g.a) / 1000))}/s` : ''}</em>`;
  }
  function flameHit(kind, e) {
    const d = e.target.closest('.ff'); if (!d) return null;
    return flameNodes[kind][+d.dataset.i] || null;
  }
  // hover: tooltip + inversion; re-run after each live render so the numbers stay current
  function hoverFlame(kind, e) {
    const el = flameEl[kind], f = flameHit(kind, e);
    const key = f ? f.n.name + '\n' + f.d : null;
    if (key !== S.hover) { S.hover = key; el.querySelectorAll('.ff.hov').forEach(x => x.classList.remove('hov')); const d = e.target.closest('.ff'); if (d) d.classList.add('hov'); }
    if (!f) { tip.hidden = true; return; }
    const rt = (flameNodes[kind].find(q => q.d === 0) || f).n.total || 1;
    const unit = kind === 'alloc' ? PF.bytes : n => `${PF.num(n)} samples`;
    tip.innerHTML = `<b>${esc(f.n.name)}</b><span>${unit(f.n.total)} · ${PF.pct(f.n.total, rt)} of ${kind === 'alloc' ? 'bytes' : 'samples'} shown</span><span>self ${unit(f.n.self)} · ${PF.pct(f.n.self, rt)}</span>`;
    showTip(e);
  }
  for (const kind of ['cpu', 'alloc']) {
    const el = flameEl[kind];
    el.addEventListener('pointermove', e => { S.move = { kind, clientX: e.clientX, clientY: e.clientY }; hoverFlame(kind, e); });
    el.addEventListener('pointerleave', () => { S.move = null; tip.hidden = true; S.hover = null; el.querySelectorAll('.ff.hov').forEach(x => x.classList.remove('hov')); });
    el.addEventListener('pointerdown', e => {
      if (e.button !== 0) return;
      const f = flameHit(kind, e); if (!f) return;
      const now = performance.now(), dbl = S.lastDown && S.lastDown.k === f.n.name && now - S.lastDown.t < 420;
      S.lastDown = { k: f.n.name, t: now };
      if (dbl || e.altKey || e.metaKey) { if (!/^Process '|^all /.test(f.n.name)) PF.browse(f.n.name, win); return; }
      const z = S.zoom[kind];
      if (f.anc) S.zoom[kind] = z.slice(0, f.zi);
      else { const chain = []; let lst = flameNodes[kind], idx = lst.indexOf(f); // walk up by depth to collect the path
        let d = f.d; chain.unshift(f.n.name);
        for (let i = idx - 1; i >= 0 && d > 0; i--) if (lst[i].d === d - 1 && lst[i].x <= f.x + 1e-9 && lst[i].x + lst[i].w >= f.x + f.w - 1e-9) { chain.unshift(lst[i].n.name); d--; }
        S.zoom[kind] = chain.slice(1); }
      S.pick = f.n.name;
      render(true);
    });
    el.addEventListener('contextmenu', e => {
      e.preventDefault(); const f = flameHit(kind, e); if (!f) return;
      Menu.show(e.clientX, e.clientY, [
        { label: 'browse method', disabled: !/>>/.test(f.n.name), fn: () => PF.browse(f.n.name, win) },
        { label: 'reset zoom', fn: () => { S.zoom[kind] = []; render(true); } },
        f.n.pid ? { label: 'only this Process', fn: () => { S.pid = String(f.n.pid); S.zoom[kind] = []; render(true); } } : null,
      ], f.n.name);
    });
    crumbs[kind].addEventListener('pointerdown', e => { const a = e.target.closest('a'); if (!a) return; S.zoom[kind] = S.zoom[kind].slice(0, +a.dataset.z); render(true); });
  }
  function showTip(e) {
    const r = win.body.getBoundingClientRect();
    tip.hidden = false;
    const tw = tip.offsetWidth, th = tip.offsetHeight;
    let lx = e.clientX - r.left + 14, ly = e.clientY - r.top + 16;
    if (lx + tw > r.width - 6) lx = e.clientX - r.left - tw - 10;
    if (ly + th > r.height - 6) ly = e.clientY - r.top - th - 10;
    tip.style.left = lx + 'px'; tip.style.top = ly + 'px';
  }
  function renderSites(g) {
    const sites = new Map(); let tot = 0;
    for (const [pid, m] of g.by) for (const [sid, w] of m) {
      const st = Profiler.stacks[sid], site = st[st.length - 2] || st[st.length - 1];
      const alloc = st[st.length - 1].match(/^(\w+) class/), cls = alloc ? alloc[1] : '?';
      const k = site + '\n' + cls; const s = sites.get(k) || { site, cls, b: 0, n: 0, pid }; s.b += w; s.n += w / Profiler.ALLOC_EVERY; sites.set(k, s); tot += w;
    }
    const rows = [...sites.values()].sort((p, q) => q.b - p.b).slice(0, 8);
    sitesEl.innerHTML = `<div class="sr hd"><span>bytes</span><span>%</span><span>class</span><span>site</span><span>Process</span></div>` + rows.map(s =>
      `<div class="sr" data-role="alloc-site" data-label="${esc(`${s.site} allocates ${s.cls} ${PF.bytes(s.b)} ${PF.pct(s.b, tot)}`)}"><span>${PF.bytes(s.b)}</span><span>${PF.pct(s.b, tot)}</span><span class="c">${esc(s.cls)}</span><span class="m${S.pick === s.site ? ' pick' : ''}" data-m="${esc(s.site)}">${esc(s.site)}</span><span class="p">${esc(procName(s.pid))}</span></div>`).join('') +
      (rows.length ? '' : '<div class="pf-empty">No allocation samples in range.</div>');
  }
  sitesEl.addEventListener('pointerdown', e => { const m = e.target.closest('.m'); if (m) pickMethod(m.dataset.m, e); });
  function pickMethod(name, e) {
    const now = performance.now(), dbl = S.lastDown && S.lastDown.k === name && now - S.lastDown.t < 420;
    S.lastDown = { k: name, t: now }; S.pick = name;
    if (dbl || e.altKey || e.metaKey) PF.browse(name, win);
    render(true);
  }

  // ---- frame timeline (canvas; overview strip and big view share the drawing code)
  let hatch = null;
  function patterns(g, col) {
    const mk = (n, f) => { const c = document.createElement('canvas'); c.width = c.height = n; f(c.getContext('2d')); return g.createPattern(c, 'repeat'); };
    hatch = mk(4, x => { x.strokeStyle = col('gpu'); x.lineWidth = 1; x.beginPath(); x.moveTo(0, 4); x.lineTo(4, 0); x.stroke(); });
  }
  // CSS colour expressions (var(), color-mix()) → rgb() for the canvas
  const probe = h('i', { style: { display: 'none' } }), colorCache = new Map();
  win.body.append(probe);
  function resolveColor(v) {
    let c = colorCache.get(v);
    if (!c) { probe.style.color = ''; probe.style.color = v; c = getComputedStyle(probe).color; colorCache.set(v, c); }
    return c;
  }
  function windowOf(big) {
    const end = S.pin ? S.pin.end : Profiler.now;
    if (!big || !S.span) return { a: S.pin ? S.pin.start : Math.max(Profiler.oldest(), end - 30000), b: end };
    const e = S.bigEnd || end;
    return { a: e - S.span, b: e };
  }
  function drawTimeline(cv, big) {
    const wrap = cv.parentElement, W = wrap.clientWidth, H = wrap.clientHeight;
    if (!W || !H) return;
    const dpr = Math.min(2, devicePixelRatio || 1);
    if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) { cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); cv.style.width = W + 'px'; cv.style.height = H + 'px'; }
    const g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, W, H);
    const cs = getComputedStyle(win.root), col = n => resolveColor(cs.getPropertyValue('--pf-' + n).trim());
    patterns(g, col);
    const { a, b } = windowOf(big);
    const padL = big ? 38 : 4, padR = 6, padT = big ? 16 : 4, gcH = big ? 10 : 5, axH = big ? 16 : 0;
    const plotW = W - padL - padR, base = H - axH - gcH - 2, plotH = base - padT;
    const maxMs = big ? 40 : 36;
    const yOf = v => base - Math.min(v, maxMs) / maxMs * plotH, xOf = t => padL + (t - a) / (b - a) * plotW;
    cv._geo = { a, b, padL, plotW };
    const fr = Profiler.framesIn(a, b);
    const target = S.pid === 'all' ? null : +S.pid;
    // busiest Processes in view get the three accent shades; system Processes are grey
    const rank = new Map();
    for (const f of fr) for (const [pid, ms] of f.segs) { const r = Profiler.procs.get(pid); if (r && (r.kind === 'user' || r.kind === 'window')) rank.set(pid, (rank.get(pid) || 0) + ms); }
    const shades = [col('proc'), col('proc2'), col('proc3')], shade = new Map([...rank].sort((p, q) => q[1] - p[1]).map(([pid], i) => [pid, shades[Math.min(i, 2)]]));
    const procCol = pid => target != null ? (pid === target ? col('proc') : col('other')) : shade.get(pid) || col('other');
    const comp = [...Profiler.procs.values()].find(r => r.name === 'compositor (vsync)');
    // y grid
    g.font = `11px ${cs.getPropertyValue('--ui')}`; g.textBaseline = 'middle';
    if (big) {
      g.fillStyle = col('ink3');
      for (const v of [33.3]) { g.fillRect(padL, Math.round(yOf(v)) + 0.5, plotW, 0.5); g.textAlign = 'right'; g.fillText(v.toFixed(0) + ' ms', padL - 5, yOf(v)); }
    }
    let dropped = 0, worst = 0;
    for (const f of fr) {
      let x0 = xOf(f.t - f.dt), x1 = xOf(f.t); const w0 = x1 - x0;
      if (w0 >= 4) x1 -= 1;
      const w = Math.max(big ? 1 : 0.8, x1 - x0);
      worst = Math.max(worst, f.dt);
      // the frame interval
      g.fillStyle = col('idle'); g.fillRect(x0, yOf(f.dt), w, base - yOf(f.dt));
      // stacked work: Processes (compositor split into draw + raster), GPU, GC
      let y = base;
      const seg = (ms, fill) => { const hh = Math.min(ms / maxMs * plotH, y - padT); if (hh <= 0) return; g.fillStyle = fill; g.fillRect(x0, y - hh, w, hh); y -= hh; };
      for (const [pid, ms] of [...f.segs].sort((p, q) => (rank.get(q[0]) || 0) - (rank.get(p[0]) || 0))) { if (isIdle(pid) || (comp && pid === comp.pid)) continue; seg(ms, procCol(pid)); }
      seg(f.draw, col('draw')); seg(f.raster, col('raster')); seg(f.gpu, hatch);
      if (f.gc && f.gc.kind === 'scavenge') seg(f.gc.ms * 2, col('gc'));
      if (f.dt > Profiler.DROP) {
        dropped++;
        g.fillStyle = col('drop'); g.fillRect(x0, yOf(f.dt) - (big ? 2 : 1), w, big ? 3 : 2);
        if (big) {
          g.strokeStyle = col('drop'); g.lineWidth = 1; g.strokeRect(x0 + 0.5, yOf(f.dt) + 0.5, w - 1, base - yOf(f.dt) - 0.5);
          if (f.dt > maxMs && x0 + w / 2 < padL + plotW - 8) { g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(f.dt.toFixed(0), x0 + w / 2, padT - 8); }
        }
        if (big) { const cx = x0 + w / 2; g.beginPath(); g.moveTo(cx - 3.5, base + gcH + 9); g.lineTo(cx + 3.5, base + gcH + 9); g.lineTo(cx, base + gcH + 3); g.closePath(); g.fill(); }
      }
      // GC lane: concurrent phases as bands, scavenges as ticks
      if (f.phase) { g.fillStyle = f.phase === 'mark' ? hatch : col('gc'); g.fillRect(x0, base + 2 + (f.phase === 'mark' ? 0 : gcH / 3), w + 1, f.phase === 'mark' ? gcH - 1 : gcH / 3); }
      if (f.gc) { g.fillStyle = col('gc'); g.fillRect(Math.round(x0), base + 1, 1.5, gcH); }
      if (big && f.n === S.frame) { g.strokeStyle = col('sel-edge'); g.lineWidth = 1.5; g.strokeRect(x0 - 1, yOf(f.dt) - 4, w + 2, base - yOf(f.dt) + 4); }
      if (big && f.n === S.hoverFrame) { g.fillStyle = col('hover'); g.fillRect(x0, padT, w, base - padT); }
    }
    // budget line
    g.fillStyle = col('budget'); const yb = Math.round(yOf(Profiler.BUDGET)) + 0.5;
    for (let xx = padL; xx < padL + plotW; xx += 4) g.fillRect(xx, yb - 0.5, 2, 1);
    if (big) { g.textAlign = 'right'; g.fillStyle = col('ink'); g.fillText('16.7', padL - 5, yb); }
    // baseline
    g.fillStyle = col('ink'); g.fillRect(padL, base, plotW, 1);
    // marks
    g.textAlign = 'left'; g.textBaseline = 'top';
    for (const m of Profiler.marks) {
      if (m.t < a || m.t > b) continue;
      const xm = Math.round(xOf(m.t)) + 0.5; g.fillStyle = col('mark');
      for (let yy = padT - (big ? 12 : 2); yy < base; yy += 3) g.fillRect(xm - 0.5, yy, 1, 1.5);
      if (big) { g.font = `italic 11px ${cs.getPropertyValue('--ui')}`; g.fillText(m.label, xm + 3, 2); }
    }
    // selection: dim outside, edges
    if (S.sel) {
      const sx0 = clamp(xOf(S.sel[0]), padL, padL + plotW), sx1 = clamp(xOf(S.sel[1]), padL, padL + plotW);
      g.fillStyle = col('dim'); g.fillRect(padL, 0, sx0 - padL, base + gcH + 2); g.fillRect(sx1, 0, padL + plotW - sx1, base + gcH + 2);
      g.fillStyle = col('sel-edge'); g.fillRect(Math.round(sx0) - 0.5, 0, 1.5, base + gcH + 2); g.fillRect(Math.round(sx1) - 1, 0, 1.5, base + gcH + 2);
      g.fillStyle = col('sel'); g.fillRect(sx0, 0, sx1 - sx0, base + gcH + 2);
    }
    // time axis
    if (big) {
      g.font = `11px ${cs.getPropertyValue('--ui')}`; g.fillStyle = col('ink3'); g.textBaseline = 'top';
      const now = Profiler.now, step = (b - a) > 8000 ? 2000 : (b - a) > 3000 ? 1000 : 500;
      for (let t = Math.ceil((a - now) / step) * step; t <= b - now + 1; t += step) {
        const xx = xOf(now + t); if (xx < padL + 10 || xx > padL + plotW - 4) continue;
        g.fillRect(Math.round(xx), base + gcH + 2, 1, 3);
        g.textAlign = 'center'; g.fillText(t === 0 ? 'now' : `${(t / 1000).toFixed(step < 1000 ? 1 : 0)} s`, xx, base + gcH + 5);
      }
      g.textAlign = 'left'; g.fillText('GC', 4, base + 1);
    }
    cv.dataset.label = `${big ? 'Frame timeline' : 'Frame overview'}: ${PF.secs(b - a)}, ${fr.length} frames, ${dropped} dropped (>${Profiler.DROP.toFixed(0)} ms), worst ${PF.ms(worst)}` +
      (S.sel ? `; selected ${PF.secs(S.sel[1] - S.sel[0])} ending ${PF.secs(Profiler.now - S.sel[1])} ago` : '') + (S.frame ? `; frame #${S.frame} selected` : '');
    if (!big) stripNote.textContent = `${fr.length} frames · ${dropped} dropped · drag to select a range`;
  }
  function frameAt(cv, clientX) {
    const geo = cv._geo; if (!geo) return null;
    const r = cv.getBoundingClientRect(), t = geo.a + (clientX - r.left - geo.padL) / geo.plotW * (geo.b - geo.a);
    return Profiler.framesIn(t, t).find(f => f.t - f.dt <= t && f.t >= t) || null;
  }
  for (const [cv, big] of [[stripCv, false], [bigCv, true]]) {
    cv.addEventListener('pointerdown', e => {
      if (e.button !== 0 || !cv._geo) return;
      e.preventDefault(); cv.setPointerCapture(e.pointerId); cv.focus();
      const geo = { ...cv._geo }, r = cv.getBoundingClientRect();
      const tOf = cx => clamp(geo.a + (cx - r.left - geo.padL) / geo.plotW * (geo.b - geo.a), geo.a, geo.b);
      const t0 = tOf(e.clientX); let moved = false, raf = 0;
      const pinNow = () => { if (!S.pin) S.pin = { end: Profiler.now, start: windowOf(false).a }; };
      const mv = ev => {
        if (!moved && Math.abs(ev.clientX - e.clientX) < 4) return;
        moved = true; pinNow();
        const t1 = tOf(ev.clientX); S.sel = [Math.min(t0, t1), Math.max(t0, t1)]; S.frame = null;
        if (!raf) raf = requestAnimationFrame(() => { raf = 0; render(true); });
      };
      cv.addEventListener('pointermove', mv);
      cv.addEventListener('pointerup', ev => {
        cv.removeEventListener('pointermove', mv);
        if (moved) { if (!big) follow(); render(true); return; }
        const f = frameAt(cv, ev.clientX);
        if (!f) { clearSel(); return; }
        pinNow(); S.frame = f.n; S.sel = [f.t - f.dt, f.t];
        if (!big) follow();
        render(true);
      }, { once: true });
    });
  }
  bigCv.addEventListener('pointermove', e => {
    if (e.buttons) return;
    const f = frameAt(bigCv, e.clientX), n = f ? f.n : null;
    if (n !== S.hoverFrame) { S.hoverFrame = n; drawTimeline(bigCv, true); }
    if (!f) { tip.hidden = true; return; }
    tip.innerHTML = `<b>Frame #${f.n} · ${PF.ms(f.dt)}${f.dt > Profiler.DROP ? ' · dropped' : ''}</b><span>${esc(topProcs(f, 3))}</span><span>draw ${PF.ms(f.draw)} · raster ${PF.ms(f.raster)} · GPU ${PF.ms(f.gpu)}${f.gc ? ' · GC ' + esc(f.gc.kind) : ''}</span>`;
    showTip(e);
  });
  bigCv.addEventListener('pointerleave', () => { tip.hidden = true; if (S.hoverFrame != null) { S.hoverFrame = null; drawTimeline(bigCv, true); } });
  function topProcs(f, n) {
    return f.segs.filter(([pid]) => !isIdle(pid)).sort((p, q) => q[1] - p[1]).slice(0, n).map(([pid, ms]) => `${procName(pid)} ${PF.ms(ms)}`).join(' · ') || 'idle';
  }
  // centre the big timeline on a selection made in the overview
  function follow() { const [a, b] = S.sel; S.bigEnd = S.span ? Math.min(S.pin.end, b + Math.max(0, S.span - (b - a)) / 2) : null; }
  function clearSel() { S.sel = null; S.pin = null; S.frame = null; S.bigEnd = null; render(true); }
  win.root.addEventListener('keydown', e => { if (e.key === 'Escape' && !/TEXTAREA/.test(e.target.tagName) && S.sel) clearSel(); });

  function renderRecord() {
    const kv = (k, v) => `<div class="kv"><span class="k">${k}</span><span class="v">${v}</span></div>`;
    const f = S.frame != null && Profiler.frames.find(q => q.n === S.frame);
    if (f) {
      const over = f.dt - Profiler.BUDGET;
      const procs = f.segs.filter(([pid]) => !isIdle(pid)).sort((p, q) => q[1] - p[1]).map(([pid, ms]) => `${esc(procName(pid))} <b>${PF.ms(ms)}</b>`).join(' · ');
      const idle = f.segs.find(([pid]) => isIdle(pid));
      recEl.innerHTML = `<div class="rh">a FrameRecord <b>#${f.n}</b> · presented ${PF.secs(Profiler.now - f.t)} ago · <b>${PF.ms(f.dt)}</b>${over > 0.5 ? ` · over budget by ${PF.ms(over)}` : ' · within budget'}${f.dt > Profiler.DROP ? ' · <span class="drop">dropped</span>' : ''}</div>` +
        kv('Processes', procs + (idle ? ` · idle ${PF.ms(idle[1])}` : '')) +
        kv('Compositor', `draw <b>${PF.ms(f.draw)}</b> · raster <b>${PF.ms(f.raster)}</b> · GPU <b>${PF.ms(f.gpu)}</b> (timestamp query)`) +
        kv('GC', f.gc ? `${esc(f.gc.kind)} <b>${PF.ms(f.gc.ms)}</b>` + (f.phase ? ` · concurrent ${f.phase} in progress` : '') : f.phase ? `concurrent ${f.phase} in progress, no pause` : 'none') +
        kv('Samples', `${f.samples} CPU · ${PF.bytes(f.alloc)} allocated — flame graph and tally now show this frame`);
    } else {
      const { a, b } = range(), fr = Profiler.framesIn(a, b), dts = fr.map(q => q.dt).sort((p, q) => p - q);
      const dropped = fr.filter(q => q.dt > Profiler.DROP), sc = fr.filter(q => q.gc && q.gc.kind === 'scavenge');
      recEl.innerHTML = `<div class="rh">${S.sel ? 'Selected range' : 'Whole ring'} · ${fr.length} frames over ${PF.secs(b - a)} — click a bar for its record, drag to select</div>` +
        kv('Frame time', fr.length ? `median <b>${PF.ms(dts[dts.length >> 1])}</b> · p95 <b>${PF.ms(dts[Math.floor(dts.length * 0.95)])}</b> · worst <b>${PF.ms(dts[dts.length - 1])}</b>` : '—') +
        kv('Dropped', `${dropped.length} frame${dropped.length === 1 ? '' : 's'} over ${PF.ms(Profiler.DROP)}` + (dropped.length ? ` — worst while ${esc(topProcs(dropped.sort((p, q) => q.dt - p.dt)[0], 2))}` : '')) +
        kv('GC', `${sc.length} scavenges · ${sc.reduce((s, q) => s + q.gc.ms, 0).toFixed(1)} ms paused`);
    }
  }
  function renderStatus(g) {
    rangeLbl.textContent = S.sel
      ? `range ${PF.secs(Profiler.now - S.sel[0])} – ${PF.secs(Profiler.now - S.sel[1])} ago (${(S.sel[1] - S.sel[0] >= 1000 ? PF.secs(S.sel[1] - S.sel[0]) : PF.ms(S.sel[1] - S.sel[0]))}) · pinned`
      : `whole ring · last ${PF.secs(g.b - g.a)} · live`;
    bClear.hidden = !S.sel;
    pickLbl.textContent = S.pick || 'click a frame or method';
    bBrowse.disabled = !S.pick || !/>>/.test(S.pick);
  }

  // ---------------------------------------------------------------- evaluator: profile data are objects
  function profileProcName() { return S.pid === 'all' ? 'all Processes' : procName(S.pid); }
  function evaluate(src) {
    const s = src.replace(/\s+/g, ' ').trim();
    let m;
    const g = () => gather(false);
    if (/^Profiler last$/.test(s)) { const x = g(); return { print: `a Profile('${profileProcName()}', ${PF.secs(x.b - x.a)}, ${PF.num(x.wsum)} samples)` }; }
    if (/^Profiler buffer$/.test(s)) return { print: `a SampleRing(${PF.num(Profiler.size())} samples, ${PF.secs(Profiler.now - Profiler.oldest())}, ${(Profiler.bytes() / (1 << 20)).toFixed(2)} MB of 1.0 MB)` };
    if (/^Profiler last samples size$/.test(s)) return { print: PF.num(g().wsum).replace(/,/g, '') };
    if ((m = s.match(/^Profiler last (samples|allocations) groupBy: #(method|process|class)$/))) {
      const alloc = m[1] === 'allocations', x = gather(alloc), groups = new Map();
      for (const [pid, mm] of x.by) for (const [sid, w] of mm) {
        const st = Profiler.stacks[sid];
        const k = m[2] === 'process' ? `'${procName(pid)}'` : m[2] === 'class' ? ((alloc ? st[st.length - 1] : st[st.length - 1]).match(/^(?:\[\] in )?(\w+)/) || [, '?'])[1] : PF.methodPrint(alloc ? st[st.length - 2] || st[st.length - 1] : st[st.length - 1]);
        groups.set(k, (groups.get(k) || 0) + w);
      }
      const rows = [...groups].sort((p, q) => q[1] - p[1]);
      const shown = rows.slice(0, 3).map(([k, n]) => `${k}->a SampleSet(${alloc ? PF.bytes(n) : PF.num(n)})`).join(' ');
      return { print: `a Dictionary(${shown}${rows.length > 3 ? ` …${rows.length - 3} more` : ''})` };
    }
    if ((m = s.match(/^Profiler last frames(?: (select|detectMax|detectMin): \[:(\w+) ?\| ?\2 (duration|isDropped)\])?( size)?$/))) {
      const { a, b } = range(); let fr = Profiler.framesIn(a, b);
      const rec = f => `a FrameRecord(#${f.n} ${PF.ms(f.dt)}${f.dt > Profiler.DROP ? ' dropped' : ''})`;
      if (m[1] === 'select') fr = fr.filter(f => m[3] === 'isDropped' ? f.dt > Profiler.DROP : f.dt);
      else if (m[1]) { if (!fr.length) return { print: 'nil' }; const f = fr.reduce((p, q) => (m[1] === 'detectMax' ? q.dt > p.dt : q.dt < p.dt) ? q : p); if (S.tab === 'frames') { S.frame = f.n; render(true); } return { print: rec(f) }; }
      if (m[4]) return { print: String(fr.length) };
      return { print: `an Array(${fr.slice(-3).map(rec).join(' ')}${fr.length > 3 ? ` …${fr.length - 3} more` : ''})` };
    }
    if ((m = s.match(/^Profiler mark: '((?:[^']|'')*)'$/))) { const mk = Profiler.mark(m[1].replace(/''/g, "'")); render(true); return { print: `a ProfileMark('${mk.label}')` }; }
    if (/^Profiler (pause|resume)$/.test(s)) { s.endsWith('pause') ? Profiler.pause() : Profiler.resume(); render(true); return { print: 'Profiler' }; }
    if (/^Profiler\b/.test(s)) return { error: 'Profiler understands: last · buffer · mark: · pause · resume; a Profile: samples · allocations · frames' };
    return null;
  }

  // ---------------------------------------------------------------- live, throttled
  win.selectProc = pid => { S.pid = String(pid); render(true); };
  setTab(S.tab);
  const iv = setInterval(() => render(false), 250);
  let rt = 0;
  win.onResize = () => { if (!rt) rt = requestAnimationFrame(() => { rt = 0; render(true); }); };
  win.onClose = () => clearInterval(iv);
  return win;
};
