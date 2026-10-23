// Samaltak classic prototype — Debugger (docs/design.md, "Debugging and profiling").
// A statement-stepping interpreter over MiniST's AST: contexts are plain objects, so every frame is
// inspectable, restartable and editable. Breakpoints are image-side (a recompiled method, or a
// per-object anonymous subclass); watchpoints use the immutability bit. The debugger runs in its own
// window Process; the debugged Process is suspended and every other window stays live.
'use strict';

(function () {
  const M = MiniST._;
  const NIL = null;
  const PASS = Symbol('pass');
  const rawEvaluate = MiniST.evaluate;

  // ------------------------------------------------------------ image: classes, methods, executability
  const CLS = new Map();
  for (const p of FakeImage.packages) for (const c of p.classes) CLS.set(c.name, c);
  const ORIGINAL = new Map();
  for (const c of CLS.values()) for (const proto of Object.values(c.protocols)) for (const [k, src] of Object.entries(proto)) ORIGINAL.set(`${c.name}>>${selectorOf(k)}`, src);
  // Fake-image methods this evaluator can run from source; every method written or edited by the user runs too.
  const EXEC_OK = new Set(['Integer>>factorial', 'Integer>>gcd:', 'Integer>>isPrime']);
  const SUPER = {
    SmallInteger: 'Integer', LargePositiveInteger: 'Integer', LargeNegativeInteger: 'Integer', Integer: 'Number', Float: 'Number',
    Fraction: 'Number', Number: 'Magnitude', Character: 'Magnitude', Magnitude: 'Object', Symbol: 'String', String: 'ArrayedCollection',
    Array: 'ArrayedCollection', ArrayedCollection: 'SequenceableCollection', SequenceableCollection: 'Collection', Collection: 'Object',
    True: 'Boolean', False: 'Boolean', Boolean: 'Object',
  };
  const chainOf = cn => { const out = []; for (let c = cn; c; c = c === 'Object' ? null : SUPER[c] || 'Object') out.push(c); return out; };
  function findMethod(cn, sel) {
    const head = sel.split(':')[0];
    for (const c of chainOf(cn)) {
      const cls = CLS.get(c); if (!cls) continue;
      for (const [pn, proto] of Object.entries(cls.protocols)) for (const [k, src] of Object.entries(proto))
        if (k.startsWith(head) && selectorOf(k) === sel) return { cls: c, sel, key: k, proto: pn, src, id: `${c}>>${sel}` };
    }
    return null;
  }
  const isUser = m => ORIGINAL.get(m.id) !== m.src;
  const runnable = m => EXEC_OK.has(m.id) || isUser(m);

  function parsePattern(head) {
    const t = head.replace(/"[^"]*"/g, '').trim();
    if (/^[A-Za-z_]\w*$/.test(t)) return { sel: t, args: [] };
    let m = t.match(/^([-+*/\\<>=~@%|&?,]+)\s*([A-Za-z_]\w*)$/);
    if (m) return { sel: m[1], args: [m[2]] };
    const parts = [...t.matchAll(/([A-Za-z_]\w*:)\s*([A-Za-z_]\w*)/g)];
    if (parts.length && parts.map(p => p[0]).join(' ') === t.replace(/\s+/g, ' ')) return { sel: parts.map(p => p[1]).join(''), args: parts.map(p => p[2]) };
    throw new M.STError('Bad message pattern: ' + t);
  }
  const compiled = new Map();
  function compile(src) {
    let c = compiled.get(src); if (c) return c;
    const nl = src.indexOf('\n'), head = nl < 0 ? src : src.slice(0, nl);
    const pat = parsePattern(head);
    const body = (' '.repeat(head.length) + src.slice(head.length)).replace(/<primitive:[^>]*>/g, x => ' '.repeat(x.length));
    const tree = M.parse(body);
    c = { ...pat, temps: tree.temps, body: tree.body };
    compiled.set(src, c);
    return c;
  }
  function recompile(m, src) {
    const proto = CLS.get(m.cls).protocols[m.proto];
    delete proto[m.key];
    const key = src.split('\n')[0].replace(/"[^"]*"/g, '').trim();
    proto[key] = src; m.key = key; m.src = src;
  }
  function rootEnv(id) { let r = M.workspaces.get(id); if (!r) { r = new M.Env(null); M.workspaces.set(id, r); } return r; }

  // ------------------------------------------------------------ printing helpers
  class Ctx { constructor(fr, X) { this.fr = fr; this.X = X; } }  // thisContext
  const dprint = v => v instanceof Ctx ? v.fr.label : M.printString(v);
  const display = v => typeof v === 'string' ? v : v instanceof M.Sym ? v.name : dprint(v);
  const trunc = (s, n) => (s = String(s)).length > n ? s.slice(0, n - 1) + '…' : s;
  function sendText(r, sel, args) {
    const rp = trunc(dprint(r), 30);
    if (!args.length) return `${rp} ${sel}`;
    if (!/^[A-Za-z]/.test(sel)) return `${rp} ${sel} ${trunc(dprint(args[0]), 24)}`;
    return rp + ' ' + sel.split(':').filter(Boolean).map((k, i) => `${k}: ${trunc(dprint(args[i]), 24)}`).join(' ');
  }
  const lineOf = (src, pos) => src.slice(0, pos).split('\n').length;

  // ------------------------------------------------------------ breakpoints, logpoints, per-object breakpoints, watchpoints
  const BP = {
    items: [], n: 0, subs: new Set(),
    add(o) { const b = { id: ++this.n, hits: 0, enabled: true, ...o }; this.items.push(b); this.changed(); return b; },
    remove(b) { this.items = this.items.filter(x => x !== b); this.changed(); },
    changed() { for (const f of [...this.subs]) try { f(); } catch (e) { console.error(e); } },
    method(id) { return this.items.find(b => b.type === 'method' && b.mid === id); },
    hit(m) { const b = this.method(m.id); return b && b.enabled ? b : null; },
    objectBreak(r, sel) { return this.items.find(b => b.type === 'object' && b.enabled && b.obj === r && b.sel === sel); },
    watchFor(r, f) { return this.items.find(b => b.type === 'watch' && b.enabled && b.obj === r && (b.field === f || b.field === 'self')); },
    watchOf(r, f) { return this.items.find(b => b.type === 'watch' && b.obj === r && b.field === f); },
    title(b) {
      if (b.type === 'method') return b.mid;
      if (b.type === 'object') return `${trunc(dprint(b.obj), 22)} receives #${b.sel}`;
      return `${trunc(dprint(b.obj), 22)} ${b.field === 'self' ? 'any field' : /^\d+$/.test(b.field) ? 'slot ' + b.field : '#' + b.field}`;
    },
    desc(b) {
      const what = b.type === 'watch' ? 'halt on write' : b.type === 'object' ? 'per-object break'
        : { break: 'break', once: 'break once', log: 'log ' + trunc(b.expr, 26), cond: 'if ' + trunc(b.expr, 26) }[b.mode];
      return `${what}${b.enabled ? '' : ' · disabled'} · ${b.hits} hit${b.hits === 1 ? '' : 's'}`;
    },
  };
  function evalIn(fr, src) {
    const X = new Exec({ src, workspace: 'dbg-eval', transcript: s => TranscriptBuf.append(s), scope: fr.curEnv || fr.env, recv: fr.recv, label: fr.label, canStop: false, ignoreBP: true });
    const res = X.start();
    if (res.error) throw res.error;
    return res.value;
  }
  function evalBreak(bp, fr) {
    bp.hits++;
    let stop = true;
    if (bp.mode === 'log') {
      let out; try { out = display(evalIn(fr, bp.expr)); } catch (e) { out = `‹${e.message}›`; }
      TranscriptBuf.append(`[${fr.label}] ${out}\n`);
      stop = false;
    } else if (bp.mode === 'cond') {
      const src = bp.expr.trim();
      try { stop = evalIn(fr, src.startsWith('[') ? `(${src}) value` : src) === true; } catch (e) { stop = true; }
    }
    if (stop && bp.mode === 'once') BP.remove(bp); else BP.changed();
    return stop;
  }

  // ------------------------------------------------------------ the stepping interpreter
  class Restart { constructor(fr) { this.fr = fr; } }
  let frameN = 0;
  class Frame { constructor(o) { Object.assign(this, o); this.id = ++frameN; this.pc = null; } }

  function* body(stmts, env, ctx, fr, X) {
    let v = NIL;
    for (const st of stmts) {
      fr.pc = st; fr.curEnv = env;
      yield { t: 'stmt', fr, st };
      v = yield* ev(st, env, ctx, fr, X);
    }
    return v;
  }
  function* ev(n, env, ctx, fr, X) {
    switch (n.k) {
      case 'lit': case 'block': case 'hole': return M.evalNode(n, env, ctx);
      case 'var':
        try { return M.evalNode(n, env, ctx); } catch (e) { if (e instanceof M.STError) return yield* fault(e, fr, X); throw e; }
      case 'assign': { const v = yield* ev(n.e, env, ctx, fr, X); (env.lookup(n.n) || ctx.root).vars.set(n.n, v); return v; }
      case 'ret': throw new M.NonLocalReturn(ctx.home, yield* ev(n.e, env, ctx, fr, X));
      case 'brace': { const out = []; for (const i of n.items) out.push(yield* ev(i, env, ctx, fr, X)); return out; }
      case 'send': {
        const r = yield* ev(n.r, env, ctx, fr, X);
        const args = []; for (const a of n.args) args.push(yield* ev(a, env, ctx, fr, X));
        return yield* send(r, n.sel, args, ctx, fr, X);
      }
      case 'cascade': {
        const first = n.first; let recv, result;
        if (first.k === 'send') {
          recv = yield* ev(first.r, env, ctx, fr, X);
          const args = []; for (const a of first.args) args.push(yield* ev(a, env, ctx, fr, X));
          result = yield* send(recv, first.sel, args, ctx, fr, X);
        } else { recv = yield* ev(first, env, ctx, fr, X); result = recv; }
        for (const part of n.rest) {
          const saved = ctx.hole; ctx.hole = recv;
          try { result = yield* ev(part, env, ctx, fr, X); } finally { ctx.hole = saved; }
        }
        return result;
      }
    }
    throw new M.STError('bad node');
  }
  function* fault(err, fr, X, extra) {
    const res = yield { t: 'stop', kind: 'error', err, fr, ...extra };
    return res && 'value' in res ? res.value : NIL;
  }
  function* truth(v, fr, X) {
    if (v === true || v === false) return v;
    yield* fault(new M.STError('NonBooleanReceiver: proceed for truth.'), fr, X);
    return false;
  }

  function* send(r, sel, args, ctx, fr, X) {
    if (r instanceof Ctx) { const v = ctxSend(r, sel); if (v !== undefined) return v; }
    if (!X.ignoreBP) {
      const ob = BP.objectBreak(r, sel);
      if (ob) { ob.hits++; BP.changed(); yield { t: 'stop', kind: 'objbreak', bp: ob, fr, recv: r, sel, args, synth: [objBreakFrame(r, sel, args)] }; }
    }
    const wf = writeField(r, sel, args);
    if (wf != null) {
      const w = BP.watchFor(r, wf);
      if (w) { w.hits++; BP.changed(); yield { t: 'stop', kind: 'watch', bp: w, fr, recv: r, sel, args, field: wf, synth: watchFrames(r, sel, args) }; }
    }
    const inl = INLINE[sel];
    if (inl) { const v = yield* inl(r, args, ctx, fr, X); if (v !== PASS) return v; }
    const m = findMethod(M.className(r), sel);
    if (m && runnable(m) && (X.mode === 'into' || isUser(m) || (!X.ignoreBP && BP.hit(m)))) return yield* invoke(m, r, args, ctx, X);
    const it = ITER[sel];
    if (it) { const v = yield* it(r, args, ctx, fr, X); if (v !== PASS) return v; }
    if (sel === 'halt') { yield { t: 'stop', kind: 'halt', fr, recv: r, sel, args, synth: [haltFrame(r)] }; return r; }
    if (sel === 'shouldBeImplemented') return yield* fault(new M.STError(`${fr.label} is not yet implemented`), fr, X, { recv: r, sel, args, synth: [{ label: `${M.className(r)}(Object)>>shouldBeImplemented`, src: 'shouldBeImplemented\n\t"Announce that this message should be implemented."\n\n\t^self error: \'This method should be implemented\'', pcText: '^self error:', recv: r }] });
    if (sel === 'inspect' && !X.ignoreBP) { inspectValue(r, X.workspace, null, 'inspect'); return r; }
    try {
      const x = extra(r, sel, args);
      if (x) return x.value;
      return M.send(r, sel, args, ctx);
    } catch (e) {
      if (!(e instanceof M.STError)) throw e;
      if (e.message === `${M.printString(r)} doesNotUnderstand: #${sel}`) {
        const res = yield { t: 'stop', kind: 'dnu', err: e, fr, recv: r, sel, args, synth: [dnuFrame(r, sel, args)] };
        if (res && res.resend) return yield* send(r, sel, args, ctx, fr, X);
        return res && 'value' in res ? res.value : NIL;
      }
      return yield* fault(e, fr, X, { recv: r, sel, args, synth: errFrames(e, r, sel, args) });
    }
  }

  // Selectors MiniST lacks: point setters (watchable stores), and a few kernel methods.
  function extra(r, sel, args) {
    const [a, b] = args;
    if (r instanceof M.Pt) {
      if (sel === 'x:') { r.x = a; return { value: r }; }
      if (sel === 'y:') { r.y = a; return { value: r }; }
      if (sel === 'setX:setY:') { r.x = a; r.y = b; return { value: r }; }
    }
    if (typeof r === 'bigint' && sel === 'sqrtFloor') {
      if (r < 0n) throw new M.STError('sqrtFloor of a negative number');
      let x = BigInt(Math.floor(Math.sqrt(Number(r))));
      while (x * x > r) x--; while ((x + 1n) * (x + 1n) <= r) x++;
      return { value: x };
    }
    if (sel === 'error:') throw new M.STError(display(a));
    return null;
  }
  function writeField(r, sel, args) {
    if (r instanceof M.Pt) return sel === 'x:' || sel === 'setX:setY:' ? 'x' : sel === 'y:' ? 'y' : null;
    if (Array.isArray(r)) {
      if (sel === 'at:put:') return typeof args[0] === 'bigint' ? String(args[0]) : 'self';
      if (['add:', 'addLast:', 'addFirst:', 'addAll:', 'removeFirst', 'removeLast'].includes(sel)) return 'self';
    }
    return null;
  }
  function ctxSend(c, sel) {
    const fr = c.fr, X = c.X;
    const below = () => { const i = X.frames.indexOf(fr); return i > 0 ? new Ctx(X.frames[i - 1], X) : NIL; };
    switch (sel) {
      case 'printString': case 'displayString': return fr.label;
      case 'sender': return below();
      case 'receiver': return fr.recv === undefined ? NIL : fr.recv;
      case 'method': return fr.label.replace(/^\[\] in /, '');
      case 'selector': return new M.Sym((fr.label.split('>>')[1] || 'DoIt'));
      case 'pc': return fr.pc && fr.pc.at ? BigInt(lineOf(fr.src || '', fr.pc.at[0])) : 0n;
      case 'isBlockContext': return fr.kind === 'block';
      case 'stack': return X.labels();
      case 'class': return new M.ClassRef('Context');
    }
    return undefined;
  }

  // Blocks the compiler would inline run in their home frame, as in Smalltalk-80.
  const own = (b, ctx) => b instanceof M.Block && b.home === ctx.home;
  const isNum = v => typeof v === 'bigint' || typeof v === 'number' || v instanceof M.Frac;
  const bool = v => v === true || v === false;
  function* inline(b, args, ctx, fr, X) {
    if (args.length !== b.params.length) return yield* fault(new M.STError(`Block expects ${b.params.length} arguments, got ${args.length}`), fr, X);
    if (++ctx.counter.steps > 2e6) throw new M.STError('Too many steps (prototype evaluator limit)');
    const env = new M.Env(b.env);
    b.params.forEach((p, i) => env.vars.set(p, args[i])); b.temps.forEach(t => env.vars.set(t, NIL));
    const savedEnv = fr.curEnv, savedPc = fr.pc;
    try { return yield* body(b.body, env, { ...ctx, home: b.home }, fr, X); } finally { fr.curEnv = savedEnv; fr.pc = savedPc; }
  }
  const INLINE = {
    *'ifTrue:'(r, [a], c, f, X) { if (!bool(r) || !own(a, c)) return PASS; return r ? yield* inline(a, [], c, f, X) : NIL; },
    *'ifFalse:'(r, [a], c, f, X) { if (!bool(r) || !own(a, c)) return PASS; return r ? NIL : yield* inline(a, [], c, f, X); },
    *'ifTrue:ifFalse:'(r, [a, b], c, f, X) { if (!bool(r) || !own(a, c) || !own(b, c)) return PASS; return yield* inline(r ? a : b, [], c, f, X); },
    *'ifFalse:ifTrue:'(r, [a, b], c, f, X) { if (!bool(r) || !own(a, c) || !own(b, c)) return PASS; return yield* inline(r ? b : a, [], c, f, X); },
    *'and:'(r, [a], c, f, X) { if (!bool(r) || !own(a, c)) return PASS; return r ? yield* truth(yield* inline(a, [], c, f, X), f, X) : false; },
    *'or:'(r, [a], c, f, X) { if (!bool(r) || !own(a, c)) return PASS; return r ? true : yield* truth(yield* inline(a, [], c, f, X), f, X); },
    *'whileTrue:'(r, [a], c, f, X) { if (!own(r, c) || !own(a, c)) return PASS; while (yield* truth(yield* inline(r, [], c, f, X), f, X)) yield* inline(a, [], c, f, X); return NIL; },
    *'whileFalse:'(r, [a], c, f, X) { if (!own(r, c) || !own(a, c)) return PASS; while (!(yield* truth(yield* inline(r, [], c, f, X), f, X))) yield* inline(a, [], c, f, X); return NIL; },
    *whileTrue(r, _, c, f, X) { if (!own(r, c)) return PASS; while (yield* truth(yield* inline(r, [], c, f, X), f, X)); return NIL; },
    *'to:do:'(r, [to, b], c, f, X) {
      if (!isNum(r) || !isNum(to) || !own(b, c)) return PASS;
      for (let i = r; M.send(i, '<=', [to], c); i = M.send(i, '+', [1n], c)) yield* inline(b, [i], c, f, X);
      return r;
    },
    *'timesRepeat:'(r, [b], c, f, X) { if (typeof r !== 'bigint' || !own(b, c)) return PASS; for (let i = 0n; i < r; i++) yield* inline(b, [], c, f, X); return r; },
    *'ifNil:'(r, [a], c, f, X) { if (!own(a, c)) return PASS; return r === NIL ? yield* inline(a, [], c, f, X) : r; },
    *'ifNotNil:'(r, [a], c, f, X) { if (!own(a, c)) return PASS; return r !== NIL ? yield* inline(a, a.params.length ? [r] : [], c, f, X) : NIL; },
    *'ifNil:ifNotNil:'(r, [a, b], c, f, X) { if (!own(a, c) || !own(b, c)) return PASS; return r === NIL ? yield* inline(a, [], c, f, X) : yield* inline(b, b.params.length ? [r] : [], c, f, X); },
  };

  // Real blocks get their own frame: `[] in Home>>method`.
  function* callBlock(b, args, ctx0, fr0, X) {
    if (args.length !== b.params.length) return yield* fault(new M.STError(`Block expects ${b.params.length} arguments, got ${args.length}`), fr0, X);
    const home = b.home && b.home.fr;
    const fr = new Frame({ kind: 'block', block: b, homeFr: home, label: '[] in ' + (home ? home.label.replace(/^\[\] in /, '') : 'UndefinedObject>>DoIt'), recv: home ? home.recv : NIL, src: home ? home.src : '"source not available"', srcKind: home ? home.srcKind : 'doit', args });
    X.push(fr);
    try {
      for (;;) {
        if (++ctx0.counter.steps > 2e6) throw new M.STError('Too many steps (prototype evaluator limit)');
        const env = new M.Env(b.env);
        b.params.forEach((p, i) => env.vars.set(p, args[i])); b.temps.forEach(t => env.vars.set(t, NIL));
        fr.env = fr.curEnv = env;
        if (home) fr.src = home.src;
        try { return yield* body(b.body, env, { ...ctx0, home: b.home }, fr, X); }
        catch (e) { if (e instanceof Restart && e.fr === fr) continue; throw e; }
      }
    } finally { X.pop(fr); }
  }
  const STUB = {
    'do:': ['do: aBlock\n\t"Evaluate aBlock with each of the receiver\'s elements as the argument."\n\n\t1 to: self size do: [:index |\n\t\taBlock value: (self at: index)]', 'aBlock value:'],
    'collect:': ['collect: aBlock\n\t| result |\n\tresult := self species new: self size.\n\t1 to: self size do: [:index |\n\t\tresult at: index put: (aBlock value: (self at: index))].\n\t^result', 'aBlock value:'],
    'select:': ['select: aBlock\n\t^self species streamContents: [:stream |\n\t\tself do: [:each |\n\t\t\t(aBlock value: each) ifTrue: [stream nextPut: each]]]', 'aBlock value:'],
    'reject:': ['reject: aBlock\n\t^self select: [:each | (aBlock value: each) == false]', 'aBlock value:'],
    'detect:ifNone:': ['detect: aBlock ifNone: exceptionBlock\n\tself do: [:each | (aBlock value: each) ifTrue: [^each]].\n\t^exceptionBlock value', 'aBlock value:'],
    'inject:into:': ['inject: thisValue into: binaryBlock\n\t"Accumulate a running value associated with evaluating binaryBlock\n\t with the current value and each element of the receiver."\n\n\t| nextValue |\n\tnextValue := thisValue.\n\tself do: [:each | nextValue := binaryBlock value: nextValue value: each].\n\t^nextValue', 'binaryBlock value:'],
    'doWithIndex:': ['doWithIndex: elementAndIndexBlock\n\t1 to: self size do: [:index |\n\t\telementAndIndexBlock value: (self at: index) value: index]', 'elementAndIndexBlock value:'],
  };
  STUB['withIndexDo:'] = STUB['doWithIndex:'];
  const IMPL = { 'do:': 'SequenceableCollection', 'collect:': 'SequenceableCollection', 'select:': 'Collection', 'reject:': 'Collection', 'detect:ifNone:': 'Collection', 'inject:into:': 'Collection', 'doWithIndex:': 'SequenceableCollection', 'withIndexDo:': 'SequenceableCollection' };
  function* iterating(X, r, sel, args, gen) {
    const [src, pcText] = STUB[sel];
    const sf = { synthetic: true, label: `${M.className(r)}(${IMPL[sel]})>>${sel}`, src, pcText, recv: r, args };
    X.push(sf);
    try { return yield* gen; } finally { X.pop(sf); }
  }
  const blk = v => v instanceof M.Block;
  const ITER = {
    *value(r, args, c, f, X) { return blk(r) ? yield* callBlock(r, args, c, f, X) : PASS; },
    *'value:'(r, args, c, f, X) { return blk(r) ? yield* callBlock(r, args, c, f, X) : PASS; },
    *'value:value:'(r, args, c, f, X) { return blk(r) ? yield* callBlock(r, args, c, f, X) : PASS; },
    *'value:value:value:'(r, args, c, f, X) { return blk(r) ? yield* callBlock(r, args, c, f, X) : PASS; },
    *'valueWithArguments:'(r, [a], c, f, X) { return blk(r) && Array.isArray(a) ? yield* callBlock(r, a, c, f, X) : PASS; },
    *'do:'(r, [a], c, f, X) {
      if (!Array.isArray(r) || !blk(a)) return PASS;
      return yield* iterating(X, r, 'do:', [a], (function* () { for (let i = 0; i < r.length; i++) yield* callBlock(a, [r[i]], c, f, X); return r; })());
    },
    *'collect:'(r, [a], c, f, X) {
      if (!Array.isArray(r) || !blk(a)) return PASS;
      return yield* iterating(X, r, 'collect:', [a], (function* () { const out = []; for (let i = 0; i < r.length; i++) out.push(yield* callBlock(a, [r[i]], c, f, X)); return out; })());
    },
    *'select:'(r, [a], c, f, X) {
      if (!Array.isArray(r) || !blk(a)) return PASS;
      return yield* iterating(X, r, 'select:', [a], (function* () { const out = []; for (const x of r.slice()) if (yield* truth(yield* callBlock(a, [x], c, f, X), f, X)) out.push(x); return out; })());
    },
    *'reject:'(r, [a], c, f, X) {
      if (!Array.isArray(r) || !blk(a)) return PASS;
      return yield* iterating(X, r, 'reject:', [a], (function* () { const out = []; for (const x of r.slice()) if (!(yield* truth(yield* callBlock(a, [x], c, f, X), f, X))) out.push(x); return out; })());
    },
    *'detect:ifNone:'(r, [a, b], c, f, X) {
      if (!Array.isArray(r) || !blk(a) || !blk(b)) return PASS;
      return yield* iterating(X, r, 'detect:ifNone:', [a, b], (function* () { for (const x of r.slice()) if (yield* truth(yield* callBlock(a, [x], c, f, X), f, X)) return x; return yield* callBlock(b, [], c, f, X); })());
    },
    *'inject:into:'(r, [a, b], c, f, X) {
      if (!Array.isArray(r) || !blk(b)) return PASS;
      return yield* iterating(X, r, 'inject:into:', [a, b], (function* () { let acc = a; for (const x of r.slice()) acc = yield* callBlock(b, [acc, x], c, f, X); return acc; })());
    },
    *'doWithIndex:'(r, [a], c, f, X) {
      if (!Array.isArray(r) || !blk(a)) return PASS;
      return yield* iterating(X, r, 'doWithIndex:', [a], (function* () { for (let i = 0; i < r.length; i++) yield* callBlock(a, [r[i], BigInt(i + 1)], c, f, X); return r; })());
    },
  };
  ITER['withIndexDo:'] = ITER['doWithIndex:'];

  function* invoke(m, r, args, ctx0, X) {
    const rc = M.className(r);
    const fr = new Frame({ kind: 'method', m, recv: r, args, label: rc === m.cls ? `${m.cls}>>${m.sel}` : `${rc}(${m.cls})>>${m.sel}`, home: {}, srcKind: 'method' });
    fr.home.fr = fr;
    X.push(fr);
    let entry = true;
    try {
      for (;;) {
        let cm;
        try { cm = compile(m.src); } catch (e) { fr.src = m.src; return yield* fault(e, fr, X); }
        fr.src = m.src; fr.cm = cm; fr.returning = false;
        const env = new M.Env(null);
        env.vars.set('self', r); env.vars.set('super', r); env.vars.set('thisContext', new Ctx(fr, X));
        cm.args.forEach((a, i) => env.vars.set(a, args[i] === undefined ? NIL : args[i]));
        cm.temps.forEach(t => env.vars.set(t, NIL));
        fr.env = fr.curEnv = env; fr.entry = entry; entry = false;
        const ctx = { root: ctx0.root, home: fr.home, counter: ctx0.counter, hole: NIL, transcript: ctx0.transcript, forked: ctx0.forked };
        let v, again = false;
        try { yield* body(cm.body, env, ctx, fr, X); v = r; }
        catch (e) {
          if (e instanceof M.NonLocalReturn && e.home === fr.home) v = e.value;
          else if (e instanceof Restart && e.fr === fr) again = true;
          else throw e;
        }
        if (again) continue;
        fr.returning = true; fr.retValue = v;
        try { yield { t: 'ret', fr, value: v }; } catch (e) { if (e instanceof Restart && e.fr === fr) continue; throw e; }
        return v;
      }
    } finally { X.pop(fr); }
  }
  function* runDoit(X) {
    const fr = new Frame({ kind: 'doit', label: X.label || 'UndefinedObject>>DoIt', recv: X.recv === undefined ? NIL : X.recv, home: {}, srcKind: 'doit', args: [] });
    fr.home.fr = fr; X.doitFrame = fr;
    X.push(fr);
    try {
      for (;;) {
        const tree = M.parse(X.src);
        tree.temps.forEach(t => { if (!X.root.vars.has(t)) X.root.vars.set(t, NIL); });
        fr.src = X.src; fr.temps = tree.temps; fr.returning = false;
        const env = new M.Env(X.scope || X.root);
        if (!X.scope) { env.vars.set('self', fr.recv); env.vars.set('thisContext', new Ctx(fr, X)); }
        fr.env = fr.curEnv = env;
        const ctx = { root: X.root, home: fr.home, counter: { steps: 0 }, hole: NIL, transcript: X.transcript || (() => {}), forked: X.forked };
        let v, again = false;
        try { v = yield* body(tree.body, env, ctx, fr, X); }
        catch (e) {
          if (e instanceof M.NonLocalReturn && e.home === fr.home) v = e.value;
          else if (e instanceof M.NonLocalReturn) throw new M.STError('BlockCannotReturn');
          else if (e instanceof Restart && e.fr === fr) again = true;
          else throw e;
        }
        if (again) continue;
        fr.returning = true; fr.retValue = v;
        try { yield { t: 'ret', fr, value: v }; } catch (e) { if (e instanceof Restart && e.fr === fr) continue; throw e; }
        return v;
      }
    } finally { X.pop(fr); }
  }

  // ------------------------------------------------------------ an execution: one debuggable Process's interpreted stack
  const toST = e => e instanceof M.STError ? e : e instanceof RangeError ? new M.STError('Stack overflow') : new M.STError(String(e && e.message || e));
  class Exec {
    constructor(o) {
      Object.assign(this, o);
      this.root = o.root || rootEnv(o.workspace || 'default');
      this.frames = []; this.mode = 'run'; this.steps = 0; this.stop = null; this.done = false;
    }
    push(f) { f.depth = this.frames.length; this.frames.push(f); }
    pop(f) { const i = this.frames.lastIndexOf(f); if (i >= 0) this.frames.length = i; }
    topFrame() { for (let i = this.frames.length - 1; i >= 0; i--) if (!this.frames[i].synthetic) return this.frames[i]; return null; }
    start() { this.gen = runDoit(this); return this.drive(() => this.gen.next()); }
    drive(first) {
      let r;
      const step = f => { try { r = f(); return true; } catch (e) { this.done = true; this.error = toST(e); return false; } };
      if (!step(first)) return { error: this.error };
      for (;;) {
        if (r.done) { this.done = true; this.value = r.value; return { done: true, value: r.value }; }
        const y = r.value; let stop = null, payload;
        if (y.t === 'stmt') {
          if (++this.steps > 4e6) { if (!step(() => this.gen.throw(new M.STError('Too many steps (prototype evaluator limit)')))) return { error: this.error }; continue; }
          stop = this.checkStmt(y);
        } else if (y.t === 'ret') stop = this.checkRet(y);
        else if (this.canStop) stop = y;
        else if (y.kind === 'error' || y.kind === 'dnu' || y.kind === 'halt') {
          const err = y.err || new M.STError('Halt');
          if (!step(() => this.gen.throw(err))) return { error: this.error };
          continue;
        } else payload = y.kind === 'watch' ? { retry: true } : undefined;
        if (stop) { this.stop = stop; this.mode = null; return { stopped: stop }; }
        if (!step(() => this.gen.next(payload))) return { error: this.error };
      }
    }
    checkStmt(y) {
      const fr = y.fr;
      if (fr.entry) {
        fr.entry = false;
        const bp = !this.ignoreBP && fr.m && BP.hit(fr.m);
        if (bp && evalBreak(bp, fr)) return { t: 'stop', kind: 'break', bp, fr };
      }
      const s = { t: 'stop', kind: 'step', fr };
      switch (this.mode) {
        case 'into': return s;
        case 'over': return fr.depth <= this.startDepth ? s : null;
        case 'through': return fr.depth <= this.startDepth || this.ownBlock(fr) ? s : null;
        case 'toHere': {
          const t = this.target;
          if (!this.frames.includes(t.fr) || fr.depth < t.fr.depth) return s;
          return fr === t.fr && y.st.at && y.st.at[1] > t.pos ? s : null;
        }
      }
      return null;
    }
    checkRet(y) {
      const fr = y.fr, s = { t: 'stop', kind: 'ret', fr, value: y.value };
      switch (this.mode) {
        case 'into': return s;
        case 'over': case 'through': return fr.depth <= this.startDepth ? s : null;
        case 'toHere': return fr === this.target.fr || !this.frames.includes(this.target.fr) ? s : null;
      }
      return null;
    }
    ownBlock(fr) {
      if (fr.kind !== 'block') return false;
      const home = this.startFr && (this.startFr.kind === 'block' ? this.startFr.homeFr : this.startFr);
      return fr.homeFr === home;
    }
    resume(mode, opts = {}) {
      if (this.done) return { done: true, value: this.value };
      const st = this.stop; this.stop = null; this.mode = mode;
      const fr = opts.fr && this.frames.includes(opts.fr) ? opts.fr : this.topFrame();
      this.startFr = fr; this.startDepth = fr ? fr.depth : 0; this.target = opts.target;
      const payload = 'payload' in opts ? opts.payload : st && (st.kind === 'error' || st.kind === 'dnu') ? { value: NIL } : st && st.kind === 'watch' ? { retry: true } : undefined;
      return this.drive(() => opts.restart ? this.gen.throw(new Restart(opts.restart)) : this.gen.next(payload));
    }
    abandon() { if (!this.done) { this.done = true; try { this.gen.return(); } catch (e) { /* unwinding */ } } }
    stackEntries() {
      const top = (this.stop && this.stop.synth || []).map(s => ({ ...s, synthetic: true, top: true }));
      const mid = this.frames.slice().reverse().map(f => f.synthetic ? { ...f, synthetic: true } : { label: f.label, fr: f });
      const base = (this.base || []).map(label => ({ label, synthetic: true, base: true }));
      return [...top, ...mid, ...base];
    }
    labels() { return this.stackEntries().map(e => e.label); }
  }

  // ------------------------------------------------------------ synthetic frames at the top of a stopped stack
  function errFrames(e, r, sel, args) {
    const cn = M.className(r);
    if (/^ZeroDivide/.test(e.message)) return [
      { label: 'ZeroDivide(Exception)>>signal', src: EXTRA_SRC['ZeroDivide(Exception)>>signal'], pcText: '^self signalIn: thisContext sender', recvText: 'a ZeroDivide' },
      { label: `${cn}(Number)>>${sel}`, src: EXTRA_SRC['SmallInteger(Number)>>/'].replace(/^\/ aNumber/, `${sel} aNumber`), pcText: '^(ZeroDivide dividend: self) signal', recv: r, args }];
    const t = errTitle(e.message);
    return [{ label: `${t === 'Error' ? 'Error' : t}(Exception)>>signal`, src: EXTRA_SRC['ZeroDivide(Exception)>>signal'], pcText: '^self signalIn: thisContext sender', recvText: 'an ' + (t === 'Error' ? 'Error' : t) }];
  }
  function dnuFrame(r, sel, args) {
    const o = findMethod('Object', 'doesNotUnderstand:');
    return { label: `${M.className(r)}(Object)>>doesNotUnderstand: #${sel}`, src: o ? o.src : 'doesNotUnderstand: aMessage\n\t^MessageNotUnderstood new signal', pcText: 'signal', recv: r, argsText: [`${sel}${args.length ? ' ' + args.map(dprint).join(' ') : ''}`] };
  }
  function haltFrame(r) {
    return { label: `${M.className(r)}(Object)>>halt`, src: 'halt\n\t"Stop here: open a Debugger on the active Process.\n\t Every other Process keeps running."\n\n\t^Halt new signal', pcText: '^Halt new signal', recv: r };
  }
  function objBreakFrame(r, sel, args) {
    const cn = M.className(r);
    let pat;
    if (!args.length) pat = sel;
    else if (!/^[A-Za-z]/.test(sel)) pat = `${sel} anObject`;
    else pat = sel.split(':').filter(Boolean).map((k, i) => `${k}: arg${i + 1}`).join(' ');
    return { label: `${cn}(anonymous)>>${sel}`, recv: r, args, pcText: 'self halt.',
      src: `${pat}\n\t"Per-object breakpoint. Only this ${cn} was moved to an anonymous\n\t subclass whose #${sel} halts, then forwards to super; every other\n\t instance runs the original method."\n\n\tself halt.\n\t^super ${pat}` };
  }
  function watchFrames(r, sel, args) {
    const sig = { label: 'ModificationForbidden(Exception)>>signal', recvText: 'a ModificationForbidden', pcText: '^self signalIn: thisContext sender',
      src: 'signal\n\t"A store into a read-only object failed. Watchpoints set the\n\t immutability bit, so the VM\'s existing store check reports\n\t the write here. Proceed retries the store."\n\n\t^self signalIn: thisContext sender' };
    if (r instanceof M.Pt) {
      const f = sel === 'y:' ? 'y' : 'x';
      return [sig, { label: `Point>>${sel}`, recv: r, args, pcText: sel === 'setX:setY:' ? 'x := xValue' : `${f} := aNumber`,
        src: sel === 'setX:setY:' ? 'setX: xValue setY: yValue\n\tx := xValue.\n\ty := yValue' : `${sel} aNumber\n\t"Store into my ${f}."\n\n\t${f} := aNumber` }];
    }
    return [sig, { label: `Array(Object)>>${sel}`, recv: r, args, pcText: 'self isReadOnlyObject',
      src: `${sel === 'at:put:' ? 'at: index put: value' : sel.endsWith(':') ? sel + ' anObject' : sel}\n\t<primitive: 61>\n\tself isReadOnlyObject\n\t\tifTrue: [^self modificationForbiddenFor: #${sel}].\n\t^self primitiveFailed` }];
  }

  // ------------------------------------------------------------ MiniST.evaluate goes through the interpreter
  const D = window.Debugger = { BP, Exec, current: null, rawEvaluate, findMethod, compile, chainOf };

  MiniST.evaluate = function (source, opts = {}) {
    const cur = D.current;
    let src = source, pre = null;
    // forked loops evaluate `i := 17. body` per iteration: bind the block argument, step only the body
    const pm = cur && /^(\s*\|[\w\s]*\|\s*)?([a-z]\w*) := (-?\d+)\. /.exec(source);
    if (pm) { pre = { name: pm[2], value: BigInt(pm[3]) }; src = (pm[1] || '') + source.slice(pm[0].length); }
    const X = new Exec({ src, workspace: opts.workspace || 'default', transcript: opts.transcript, forked: opts.forked, canStop: !!cur, label: cur ? '[] in UndefinedObject>>DoIt' : 'UndefinedObject>>DoIt' });
    if (pre) { X.root.vars.set(pre.name, pre.value); X.blockArgs = [pre.name]; }
    const res = X.start();
    if (res.stopped) { holdFork(X, cur); present(X, WM.wins.get(cur.origin)); return { value: NIL, printString: 'nil', className: 'UndefinedObject' }; }
    if (res.error) throw res.error;
    return { value: res.value, printString: dprint(res.value), className: M.className(res.value) };
  };
  // User-written methods reached from inside MiniST primitives (e.g. a block in #detect:) run synchronously.
  MiniST.fallback = (r, sel, args, ctx) => {
    const m = findMethod(M.className(r), sel);
    if (m && isUser(m)) {
      const X = new Exec({ workspace: 'default', canStop: false, ignoreBP: true });
      X.gen = invoke(m, r, args, ctx, X);
      const res = X.drive(() => X.gen.next());
      if (res.error) throw res.error;
      return { value: res.value };
    }
    if (sel === 'halt') throw new M.STError('Halt');
    return extra(r, sel, args);
  };

  // Forked user Processes: note which Process is running so a stop can suspend it.
  const origAdd = Sched.add;
  Sched.add = function (p) {
    const r = origAdd.call(this, p);
    if (p.kind === 'user' && typeof p.step === 'function' && !p.dbgOwn) {
      const st = p.step;
      p.step = function () {
        if (p.dbgHold) { advance(p.dbgHold.X, 'run'); return undefined; }
        const prev = D.current; D.current = p;
        try { const res = st.call(this); if (p.dbgHold) { p.dbgHold.after = res; return undefined; } return res; }
        finally { D.current = prev; }
      };
    }
    return r;
  };

  function holdFork(X, p) {
    const hold = { X, after: undefined };
    const savedFrames = p.frames, savedAbandon = p.onAbandon;
    const base = (typeof savedFrames === 'function' ? savedFrames() : savedFrames) || [];
    const k = base.indexOf('[] in UndefinedObject>>DoIt');
    X.base = k >= 0 ? base.slice(k + 1) : base;
    p.dbgHold = hold; p.state = 'suspended';
    p.frames = () => X.labels();
    const release = () => { p.dbgHold = null; p.frames = savedFrames; p.onAbandon = savedAbandon; };
    p.onAbandon = () => { release(); X.abandon(); if (X.ui) X.ui.closeQuiet(); if (savedAbandon) savedAbandon(); };
    X.owner = {
      proc: p,
      finish: () => { release(); if (hold.after === 'done') Sched.finish(p); else p.state = 'running'; },
      abandon: () => { release(); X.abandon(); if (p.state !== 'terminated') Sched.terminate(p); },
    };
  }
  const kindName = win => win ? win.kind[0].toUpperCase() + win.kind.slice(1) : 'Workspace';
  function holdDoit(X, ed, act, s, e, text) {
    const win = ed.win;
    const p = Sched.add({
      name: `${win ? win.title.replace(/:.*/, '') : 'Workspace'} doIt`, priority: 40, kind: 'user', state: 'suspended', dbgOwn: true,
      origin: win && win.id, source: X.src, progress: () => 'in the Debugger', frames: () => X.labels(),
      step: () => { advance(X, 'run'); return undefined; },
    });
    if (win) win.children.add(p);
    let gone = false;
    const drop = () => { if (gone) return; gone = true; if (win) win.children.delete(p); };
    p.onAbandon = () => { drop(); X.abandon(); if (X.ui) X.ui.closeQuiet(); };
    X.owner = {
      proc: p,
      finish: v => { drop(); Sched.finish(p); completeDoit(ed, act, s, e, text, v, true); },
      abandon: () => { drop(); X.abandon(); if (p.state !== 'terminated') Sched.terminate(p); },
    };
  }
  function inspectValue(v, ws, near, label) {
    const name = '__insp' + (++inspN);
    rootEnv(ws).vars.set(name, v);
    return Tools.openInspector({ result: { value: v, printString: dprint(v), className: M.className(v) }, varName: name, workspace: ws, near, label });
  }
  function completeDoit(ed, act, s, e, text, v, late) {
    if (act === 'print') ed.insertAfter(e, ' ' + dprint(v), 'result');
    else if (act === 'inspect') { ed.setMark(s, e, 'flash', 600); inspectValue(v, ed.workspace, ed.win, text.trim()); }
    else { ed.setMark(s, e, 'flash', 600); if (late) Toast.show(`${trunc(text.trim(), 40)} → ${trunc(dprint(v), 40)}`); }
  }
  // Resume an execution; then close, update or open its Debugger.
  function advance(X, mode, opts) {
    const p = X.owner && X.owner.proc;
    if (p) p.state = 'running';
    const res = X.resume(mode, opts);
    if (res.done) { if (X.ui) X.ui.closeQuiet(); X.owner.finish(res.value); }
    else if (res.error) {
      if (X.ui) X.ui.closeQuiet(); X.owner.abandon();
      Toast.show(`Process '${p ? p.name : 'doIt'}' failed: ${res.error.message}`, 3200);
    } else {
      if (p) p.state = 'suspended';
      if (X.ui) X.ui.onStop(); else present(X);
    }
    WM.syncBusy();
    return res;
  }
  function present(X, near) {
    const k = X.stop.kind;
    if (k === 'error' || k === 'dnu') notifierWin({ X, near });
    else openDebugger({ X, near });
  }

  // ------------------------------------------------------------ workspace evaluation: do it / print it / inspect it
  const origRun = Eval.run;
  Eval.run = function (ed, act) {
    if (!['do', 'print', 'inspect'].includes(act)) return origRun.call(this, ed, act);
    const { s, e, text } = ed.selectionOrLine();
    if (!text.trim()) return;
    if (ed.o.frameScope) return evalInFrame(ed, act, s, e, text);
    const src = ed.o.selfVar ? bindSelf(text, ed.o.selfVar) : text;
    if (detectFork(src)) return origRun.call(this, ed, act);
    const win = ed.win;
    if (win && win.proc) Sched.poke(win.proc, 240);
    try { M.parse(src); } catch (err) { return Eval.error(ed, err, s, e, src); }
    const X = new Exec({ src, workspace: ed.workspace, transcript: x => TranscriptBuf.append(x), forked: (b, name) => Eval.opaqueFork(name, ed), canStop: true });
    X.base = ['Compiler>>evaluate:for:', `TextEditor>>${act}It`, `${kindName(win)}(Widget)>>handleEvent:`, '[] in Window>>eventLoop', 'BlockClosure>>repeat', '[] in BlockClosure>>newProcess'];
    const res = X.start();
    if (res.error) return Eval.error(ed, res.error, s, e, src);
    if (res.done) return completeDoit(ed, act, s, e, text, res.value, false);
    holdDoit(X, ed, act, s, e, text);
    present(X, win);
  };
  // The Debugger's evaluators run in the selected frame: temps, args and self are live.
  function evalInFrame(ed, act, s, e, text) {
    const sc = ed.o.frameScope();
    if (ed.win && ed.win.proc) Sched.poke(ed.win.proc, 200);
    try { M.parse(text); } catch (err) { ed.insertAfter(e, ` ‹${err.message} →›`, 'error'); return; }
    const X = new Exec({ src: text, workspace: ed.workspace, transcript: x => TranscriptBuf.append(x), scope: sc && sc.env, recv: sc && sc.recv, label: sc ? sc.label : 'UndefinedObject>>DoIt', canStop: false, ignoreBP: true });
    const res = X.start();
    if (res.error) { ed.insertAfter(e, ` ‹${res.error.message}›`, 'error'); return; }
    const v = res.value;
    if (act === 'print') ed.insertAfter(e, ' ' + dprint(v), 'result');
    else if (act === 'inspect') { ed.setMark(s, e, 'flash', 600); inspectValue(v, ed.workspace, ed.win, text.trim()); }
    else ed.setMark(s, e, 'flash', 600);
    if (ed.o.onDone) ed.o.onDone();
  }

  // ------------------------------------------------------------ header text for a stop
  const HICON = {
    break: '<svg viewBox="0 0 14 14"><circle cx="7" cy="7" r="4.2" fill="currentColor"/></svg>',
    objbreak: '<svg viewBox="0 0 14 14"><circle cx="7" cy="7" r="4.6" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="7" cy="7" r="2" fill="currentColor"/></svg>',
    halt: '<svg viewBox="0 0 14 14"><path d="M4.7 1.6h4.6l3.1 3.1v4.6l-3.1 3.1H4.7L1.6 9.3V4.7z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M4.8 7h4.4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    watch: '<svg viewBox="0 0 14 14"><path d="M1.2 7s2.3-3.9 5.8-3.9S12.8 7 12.8 7s-2.3 3.9-5.8 3.9S1.2 7 1.2 7z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><circle cx="7" cy="7" r="1.8" fill="currentColor"/></svg>',
  };
  const stmtText = fr => fr && fr.pc && fr.pc.at ? fr.src.slice(fr.pc.at[0], fr.pc.at[1]).replace(/\s+/g, ' ') : '';
  function describe(st) {
    const r = st.recv;
    switch (st.kind) {
      case 'error': {
        const msg = st.err.message, t = errTitle(msg);
        return { kind: 'error', title: t, message: msg === t ? `${trunc(stmtText(st.fr), 60)} — ${/^ZeroDivide/.test(t) ? 'division by zero' : 'error'}` : msg };
      }
      case 'dnu': return { kind: 'dnu', title: `MessageNotUnderstood: ${M.className(r)}>>#${st.sel}`, message: `${trunc(dprint(r), 30)} doesNotUnderstand: #${st.sel} — Create defines it; Proceed then resends the message.` };
      case 'halt': return { kind: 'halt', title: 'Halt', message: `${stmtText(st.fr)} — in ${st.fr.label}` };
      case 'break': {
        const fr = st.fr, b = st.bp;
        const how = { break: 'breakpoint', once: 'break-once (now removed)', cond: `conditional: ${b.expr}` }[b.mode] || 'breakpoint';
        return { kind: 'break', title: `Breakpoint: ${fr.m.id}`, message: `${sendText(fr.recv, fr.m.sel, fr.args)} — ${how}, hit ${b.hits}×. Image-side: the method was recompiled with a break at entry.` };
      }
      case 'objbreak': return { kind: 'objbreak', title: `Breakpoint: ${trunc(dprint(r), 24)} receives #${st.sel}`, message: `${sendText(r, st.sel, st.args)} — per-object: only this instance halts (it now belongs to an anonymous subclass).` };
      case 'watch': {
        const f = /^\d+$/.test(st.field) ? `slot ${st.field}` : st.field === 'self' ? 'any field' : '#' + st.field;
        return { kind: 'watch', title: `ModificationForbidden → watchpoint on ${f}`, message: `${sendText(r, st.sel, st.args)} — the object is read-only while watched; Proceed retries the store.` };
      }
    }
    return null;
  }

  // ------------------------------------------------------------ notifier (pre-debugger)
  function simProceed(p, o) {
    if (p && p.state === 'suspended') p.state = p.step ? 'running' : 'waiting';
    if (o && o.onProceed) o.onProceed();
  }
  function simAbandon(p) {
    if (!p || p.state !== 'suspended') return;
    if (p.kind === 'user') Sched.terminate(p);
    else { p.step = null; p.state = 'waiting'; if (p.onAbandon) p.onAbandon(); }
  }
  function notifierWin(o) {
    const X = o.X || null;
    const proc = X ? X.owner.proc : o.proc;
    const d = X ? describe(X.stop) : { kind: o.interrupt ? 'interrupt' : 'error', title: o.title, message: o.message };
    const W = 480, H = 226;
    const pos = WM.near(o.near, W, H, 70, 90);
    const win = WM.create({ title: d.title, kind: 'debugger', cls: 'notifier dbg-notifier', x: pos.x, y: pos.y, w: W, h: H, minW: 360, minH: 180, procName: 'Debugger' });
    let done = false;
    if (proc) proc.dbgUI = { win, notifier: true };
    const close = () => { done = true; if (proc && proc.dbgUI && proc.dbgUI.win === win) proc.dbgUI = null; if (X && X.ui === nui) X.ui = null; win.close(); };
    const nui = { closeQuiet: () => { if (!done) close(); }, onStop: () => {} };
    if (X) X.ui = nui;
    const proceed = () => { close(); if (X) advance(X, 'run'); else simProceed(proc, o); };
    const abandon = () => { close(); if (X) X.owner.abandon(); else simAbandon(proc); };
    const debug = then => { const at = { x: win.x, y: win.y }; close(); const ui = openDebugger({ ...o, X, pos: at }); if (then) then(ui); };
    const labels = X ? X.labels() : (proc ? framesOf(proc) : o.frames) || [];
    const stack = new List({ cls: 'nt-stack', onDbl: () => debug() });
    stack.set(labels.map((f, i) => ({ key: String(i), html: `<span class="t">${esc(f)}</span>` })));
    const head = h('div', { class: 'nt-head dbg-head k-' + d.kind + (d.kind === 'interrupt' ? ' interrupt' : '') },
      h('div', { class: 'nt-icon', html: HICON[d.kind] || (d.kind === 'interrupt' ? ICON.pause : ICON.warn) }),
      h('div', { class: 'nt-msg' }, h('b', null, d.title), h('span', null, d.message)));
    const createB = X && X.stop.kind === 'dnu' ? h('button', { class: 'btn', title: 'Open the Debugger and define the missing method', onclick: ev => { const r = ev.currentTarget.getBoundingClientRect(); debug(ui => ui.create({ x: r.left, y: r.bottom })); } }, 'Create') : null;
    const btns = h('div', { class: 'nt-btns' },
      h('button', { class: 'btn primary', onclick: proceed }, 'Proceed'),
      h('button', { class: 'btn', onclick: abandon }, 'Abandon'),
      h('button', { class: 'btn', onclick: () => debug() }, 'Debug'), createB,
      h('span', { class: 'sp' }),
      proc ? h('span', { class: 'note' }, 'other Processes keep running') : null);
    win.body.append(head, btns, stack.el);
    win.onClose = () => { if (done) return; done = true; if (proc && proc.dbgUI && proc.dbgUI.win === win) proc.dbgUI = null; if (X && X.ui === nui) X.ui = null; if (X) X.owner.abandon(); else simAbandon(proc); };
    return win;
  }
  Tools.openNotifier = function (o) {
    if (o.X) return notifierWin(o);
    const p = o.proc;
    if (p && p.dbgUI && WM.wins.has(p.dbgUI.win.id)) { p.dbgUI.win.focus(); return p.dbgUI.win; }
    if (p && p.dbgHold) return openDebugger({ X: p.dbgHold.X, near: o.near }).win;
    if (o.debug) return openDebugger(o).win;
    return notifierWin(o);
  };

  // ------------------------------------------------------------ the Debugger window
  function openDebugger(o) {
    if (!o.X && o.proc && o.proc.dbgHold) o = { ...o, X: o.proc.dbgHold.X };
    const X = o.X || null;
    const proc = X ? X.owner && X.owner.proc : o.proc || null;
    if (proc && proc.dbgUI && WM.wins.has(proc.dbgUI.win.id)) { if (!proc.dbgUI.notifier) { proc.dbgUI.win.focus(); return proc.dbgUI; } proc.dbgUI.win.close(); }
    const W = Math.min(820, innerWidth - 16), H = Math.min(700, innerHeight - TOPBAR - 16);
    const pos = o.pos ? { x: clamp(o.pos.x, 8, innerWidth - W - 8), y: clamp(o.pos.y, TOPBAR + 4, innerHeight - H - 8) } : WM.near(o.near, W, H, 56, 34);
    let head = X ? describe(X.stop) || { kind: 'halt', title: 'Debugger', message: '' } : { kind: o.interrupt ? 'interrupt' : 'error', title: o.title || `Process '${proc ? proc.name : '?'}'`, message: o.message || '' };
    const win = WM.create({ title: 'Debugger', kind: 'debugger', cls: 'dbg', x: pos.x, y: pos.y, w: W, h: H, minW: 600, minH: 480, procName: `Debugger on '${proc ? proc.name : 'doIt'}'` });
    const ui = { win, X, proc, full: false, sel: null, done: false };
    if (X) X.ui = ui;
    if (proc) proc.dbgUI = ui;
    const dbgWs = 'dbg-' + win.id;

    // header
    const icon = h('div', { class: 'nt-icon' }), hTitle = h('b'), hMsg = h('span');
    const procLink = h('button', { class: 'dbg-proc', 'data-role': 'process-link', 'data-label': 'debugged Process', title: 'Show the debugged Process in the Process Browser', onclick: () => proc && Tools.openProcessBrowser({ select: proc.pid }) });
    const headEl = h('div', { class: 'nt-head dbg-head', 'data-role': 'debugger-header', 'data-label': 'reason' }, icon, h('div', { class: 'nt-msg' }, hTitle, hMsg), procLink);
    function setHead(d) {
      head = d;
      headEl.className = 'nt-head dbg-head k-' + d.kind + (d.kind === 'interrupt' ? ' interrupt' : '');
      icon.innerHTML = HICON[d.kind] || (d.kind === 'interrupt' ? ICON.pause : ICON.warn);
      hTitle.textContent = d.title; hMsg.textContent = d.message;
      win.setTitle('Debugger — ' + d.title);
    }

    // buttons
    const B = {};
    const btn = (k, label, tip, fn, cls) => (B[k] = h('button', { class: 'btn' + (cls ? ' ' + cls : ''), title: tip, 'data-role': 'button', 'data-label': label, onclick: fn }, label));
    const bar = h('div', { class: 'toolbar dbg-bar', 'data-role': 'debugger-buttons', 'data-label': 'Debugger' },
      btn('proceed', 'Proceed', 'Resume the Process (this Debugger closes)', () => proceed(), 'primary'),
      btn('restart', 'Restart', 'Restart the selected frame at its first statement', () => restart()),
      btn('into', 'Into', 'Step into the next message send', () => step('into')),
      btn('over', 'Over', 'Run the current statement of the selected frame', () => step('over')),
      btn('through', 'Through', 'Like Over, but stop inside blocks of the selected frame', () => step('through')),
      btn('here', 'Run to here', 'Run until the selected frame reaches the caret', () => runToHere()),
      h('span', { class: 'dbg-sep' }),
      btn('where', 'Where', 'Select the active frame and show its current statement', () => where()),
      btn('full', 'Full stack', 'Show every frame down to the Process root', () => { ui.full = !ui.full; render(ui.sel && ui.sel.fr); }),
      h('span', { class: 'sp' }),
      btn('create', 'Create', 'Define the missing method in a class you choose and continue in it', ev => { const r = ev.currentTarget.getBoundingClientRect(); create({ x: r.left, y: r.bottom + 2 }); }),
      btn('unbp', 'Remove breakpoint', 'Remove the breakpoint or watchpoint that stopped this Process', () => removeStopBp()),
      btn('bps', 'Breakpoints', 'All breakpoints, logpoints and watchpoints', () => openBreakpoints({ near: win })));

    // stack
    const stack = new List({ cls: 'dbg-stack-list', onSelect: k => selectEntry(+k) });
    Object.assign(stack.el.dataset, { role: 'stack', label: 'Stack' });
    stack.el.addEventListener('mousedown', e => { if (e.target.closest('.dbg-more')) { ui.full = true; render(ui.sel && ui.sel.fr); } });
    const stackCount = h('span', { class: 'r' });
    const stackPane = h('div', { class: 'pane dbg-stack' }, h('div', { class: 'pane-h' }, 'Stack', stackCount), stack.el);

    // source
    const srcEd = new Editor({ win, method: true, workspace: dbgWs, onAccept: () => accept(), onChange: () => setDirty(true) });
    Object.assign(srcEd.el.dataset, { role: 'source', label: 'Source' });
    const srcTitle = h('span', { class: 'dbg-crumb' }), srcHint = h('span', { class: 'r' });
    const pcInfo = h('span', { class: 'mono' }), pill = h('span', { class: 'pill' });
    const srcPane = h('div', { class: 'pane dbg-src' }, h('div', { class: 'pane-h' }, srcTitle, srcHint), srcEd.el, h('div', { class: 'statusbar' }, pcInfo, h('span', { class: 'r' }, pill)));
    function setDirty(d) {
      ui.dirty = d; srcEd.el.classList.toggle('dirty', d);
      if (d) { pill.className = 'pill dirty'; pill.textContent = `unaccepted · ${MOD}S recompiles & restarts`; }
    }

    // receiver and context inspectors, each with an evaluator bound to the selected frame
    function inspector(name, ph) {
      let rows = [];
      const val = new Editor({ win, highlight: false, readOnly: true, cls: 'dbg-val' });
      const list = new List({ cls: 'dbg-fields', onSelect: k => { const r = rows[+k]; val.value = r ? (r.long != null ? r.long : r.value) : ''; } });
      Object.assign(list.el.dataset, { role: 'fields', label: name });
      const evEd = new Editor({ win, workspace: dbgWs, cls: 'dbg-eval', placeholder: ph, frameScope: () => scope(), onDone: () => refreshInspectors(true) });
      Object.assign(evEd.el.dataset, { role: 'evaluator', label: name + ' evaluator' });
      const sub = h('span', { class: 'r' });
      const el = h('div', { class: 'pane dbg-ip', 'data-role': 'inspector', 'data-label': name },
        h('div', { class: 'pane-h' }, name, sub), h('div', { class: 'dbg-ip-top' }, list.el, val.el), evEd.el);
      return {
        el, sub,
        set(rs, keep) {
          const prev = list.sel; rows = rs;
          list.set(rs.map((r, i) => ({ key: String(i), cls: r.cls || '', html: `<span class="t">${esc(r.name)}</span><span class="muted v">${esc(trunc(r.value, 60))}</span>` })));
          if (rs.length) list.select(keep && prev != null && +prev < rs.length ? prev : String(rs.length > 1 && name === 'Context' ? 1 : 0)); else val.value = '';
        },
      };
    }
    const recvI = inspector('Receiver', `evaluate with self bound · ${MOD}D ${MOD}P ${MOD}I`);
    const ctxI = inspector('Context', 'evaluate in this frame · temps are live');
    win.body.append(headEl, bar, stackPane, vSplitter(stackPane, 50), srcPane, h('div', { class: 'dbg-bottom' }, recvI.el, ctxI.el));

    // ---- model → view
    let entries = [];
    function computeEntries() {
      if (X) return X.stackEntries();
      const labels = proc ? framesOf(proc) : o.frames || [];
      return labels.map(label => {
        const e = { label, synthetic: true, sim: true };
        const sel = (label.split('>>')[1] || '').trim(), m = /^[a-z]\w*$/.test(sel) && proc && proc.source && new RegExp(`(-?\\d+)\\s+${sel}\\b`).exec(proc.source);
        if (m && /^SmallInteger/.test(label)) e.recv = BigInt(m[1]);
        return e;
      });
    }
    function defaultIndex() { const i = entries.findIndex(e => e.fr); return i < 0 ? 0 : i; }
    function render(keepFr) {
      entries = computeEntries();
      let vis = entries.map((e, i) => i), hidden = 0;
      if (!ui.full) {
        const cut = entries.findIndex(e => e.base);
        if (cut >= 0 && entries.length - cut > 1) { hidden = entries.length - cut - 1; vis = vis.slice(0, cut + 1); }
      }
      const items = vis.map(i => {
        const e = entries[i], b = e.fr && e.fr.m && BP.method(e.fr.m.id);
        return { key: String(i), cls: e.fr ? 'act' : 'syn', html: `<span class="bp-g${b ? ` on ${b.mode}${b.enabled ? '' : ' off'}` : ' none'}"></span><span class="t">${esc(e.label)}</span>${e.fr && e.fr.returning ? '<span class="muted">returning</span>' : ''}` };
      });
      if (hidden) items.push({ hdr: true, html: `<span class="dbg-more" data-role="button" data-label="Full stack">… ${hidden} more frame${hidden > 1 ? 's' : ''} — Full stack</span>` });
      let si = keepFr ? entries.findIndex(e => e.fr === keepFr) : -1;
      if (si < 0) si = defaultIndex();
      if (!vis.includes(si)) si = 0;
      stack.set(items, String(si));
      stackCount.textContent = `${entries.length} frames`;
      selectEntry(si);
    }
    function selectEntry(i) {
      const e = entries[i]; if (!e) return;
      ui.sel = e;
      showSource(e); refreshInspectors(false); updateButtons();
    }
    function markOf(e, src, i) {
      if (e.fr) { const fr = e.fr; return fr.pc && fr.pc.at ? { s: fr.pc.at[0], e: fr.pc.at[1], kind: 'pc' + (fr.returning ? ' ret' : '') } : null; }
      if (e.pcText) { const k = src.indexOf(e.pcText); if (k >= 0) return { s: k, e: k + e.pcText.length, kind: 'pc' }; }
      const r = pcRange(src, i > 0 ? entries[i - 1].label : null);
      return { s: r.s, e: r.e, kind: 'pc' };
    }
    function showSource(e) {
      const i = entries.indexOf(e), fr = e.fr;
      const src = fr ? fr.src || '' : e.src || frameSource(e.label, X ? X.src : o.doit || (proc && proc.source));
      const editable = !!(fr && X && !X.done);
      srcEd.o.method = !(fr && (fr.srcKind === 'doit'));
      srcEd.value = src;
      srcEd.ta.readOnly = !editable; srcEd.el.classList.toggle('readonly', !editable);
      const mk = markOf(e, src, i);
      if (mk) { srcEd.setMark(mk.s, mk.e, mk.kind); scrollTo(mk.s); }
      setDirty(false);
      srcTitle.textContent = e.label;
      srcHint.textContent = editable ? `edit · ${MOD}S recompiles and restarts this frame` : e.sim ? 'simulated frame · read-only' : 'read-only';
      pcInfo.textContent = mk ? `line ${lineOf(src, mk.s)}` + (fr && fr.kind === 'method' ? ` · ${fr.m.id}` : '') : '';
      if (fr && fr.returning) { pill.className = 'pill ok'; pill.textContent = `↩ returning ${trunc(dprint(fr.retValue), 40)}`; }
      else if (ui.note) { pill.className = 'pill ok'; pill.textContent = ui.note; }
      else { pill.className = 'pill'; pill.textContent = ''; }
    }
    function scrollTo(pos) {
      const line = lineOf(srcEd.value, pos) - 1;
      const lh = parseFloat(getComputedStyle(srcEd.ta).lineHeight) || 20;
      requestAnimationFrame(() => { srcEd.ta.scrollTop = Math.max(0, (line - 2) * lh); srcEd.sync(); });
    }
    function recvRows(e) {
      const has = e.fr || 'recv' in e;
      const recv = e.fr ? e.fr.recv : e.recv;
      if (!has) {
        const cn = (e.label.replace(/^\[\] in /, '').match(/^([\w ]+?)(?:\(|>>)/) || [, 'Object'])[1];
        const txt = e.recvText || (cn === 'UndefinedObject' ? 'nil' : / class$/.test(cn) ? cn.replace(/ class$/, '') : article(cn));
        return { rows: [{ name: 'self', value: txt }, { name: 'class', value: cn }], label: txt };
      }
      const rows = MiniST.inspect(recv).map(r => ({ name: r.name, value: r.value }));
      rows.forEach(r => { const f = watchableField(recv, r.name); if (f && BP.watchOf(recv, f)) { r.cls = 'dbg-watched'; r.long = r.value + '\n\n(read-only: halt on write)'; } });
      return { rows, label: dprint(recv) };
    }
    function ctxDesc(fr) {
      const k = entries.findIndex(e => e.fr === fr), sender = k >= 0 && k + 1 < entries.length ? entries[k + 1].label : 'nil';
      return `a Context\nmethod: ${fr.kind === 'method' ? fr.m.id : fr.label.replace(/^\[\] in /, '')}\nreceiver: ${dprint(fr.recv)}\npc: line ${fr.pc && fr.pc.at ? lineOf(fr.src, fr.pc.at[0]) : '-'}, ${stmtText(fr)}\nsender: ${sender}${fr.homeFr ? `\nhome: ${fr.homeFr.label}` : ''}`;
    }
    function ctxRows(e, i) {
      const fr = e.fr;
      if (fr) {
        const rows = [{ name: 'thisContext', value: fr.label, long: ctxDesc(fr), cls: 'k-ctx' }];
        const skip = new Set(['self', 'super', 'thisContext']);
        const chain = [];
        for (let env = fr.curEnv || fr.env; env && env !== X.root; env = env.parent) chain.push(env);
        const own = chain.indexOf(fr.env);
        const argNames = new Set(fr.kind === 'method' ? fr.cm.args : fr.kind === 'block' ? fr.block.params : X.blockArgs || []);
        chain.slice().reverse().forEach((env, j) => {
          const outer = fr.kind === 'block' && chain.length - 1 - j > own;
          for (const [k, v] of env.vars) if (!skip.has(k)) { skip.add(k); rows.push({ name: k, value: dprint(v), cls: outer ? 'outer' : argNames.has(k) ? 'arg' : '' }); }
        });
        if (fr.kind === 'doit') [...(X.blockArgs || []), ...(fr.temps || [])].forEach(k => { if (!skip.has(k) && X.root.vars.has(k)) { skip.add(k); rows.push({ name: k, value: dprint(X.root.vars.get(k)), cls: argNames.has(k) ? 'arg' : '' }); } });
        if (fr.returning) rows.push({ name: '↩ return', value: dprint(fr.retValue), cls: 'k-ret' });
        return rows;
      }
      const src = e.src || frameSource(e.label, X ? X.src : o.doit || (proc && proc.source));
      const rows = [{ name: 'thisContext', value: e.label, long: `a Context\nmethod: ${e.label}\n${e.sim ? 'simulated: this Process was interrupted, not stepped' : e.base ? 'below the stepped code' : 'signalling machinery'}${i + 1 < entries.length ? `\nsender: ${entries[i + 1].label}` : ''}`, cls: 'k-ctx' }];
      let pat = null; try { pat = parsePattern(src.split('\n')[0]); } catch (err) { /* no pattern */ }
      if (pat) pat.args.forEach((a, k) => rows.push({ name: a, value: e.args && k < e.args.length ? dprint(e.args[k]) : e.argsText ? e.argsText[k] || '…' : '…', cls: 'arg' }));
      const tm = /\n\s*\|([\w\s]*)\|/.exec(src);
      if (tm) tm[1].trim().split(/\s+/).filter(Boolean).forEach(t => rows.push({ name: t, value: '…' }));
      if (e.sim && /^\[\] in UndefinedObject>>DoIt$/.test(e.label) && proc && proc.source) {
        const fk = detectFork(proc.source), root = M.workspaces.get(proc.origin || 'world');
        if (fk && fk.plan.v && root && root.vars.has(fk.plan.v)) rows.push({ name: fk.plan.v, value: dprint(root.vars.get(fk.plan.v)), cls: 'arg' });
      }
      return rows;
    }
    function refreshInspectors(keep) {
      const e = ui.sel; if (!e) return;
      const i = entries.indexOf(e);
      const rr = recvRows(e);
      recvI.set(rr.rows, keep); ctxI.set(ctxRows(e, i), keep);
      recvI.sub.textContent = trunc(rr.label, 36);
      ctxI.sub.textContent = trunc(e.label, 44);
    }
    function scope() {
      const e = ui.sel; if (!e) return null;
      if (e.fr) return { env: e.fr.curEnv || e.fr.env, recv: e.fr.recv, label: e.fr.label };
      const root = e.sim && proc && proc.origin ? rootEnv(proc.origin) : null;
      const env = new M.Env(root);
      env.vars.set('self', 'recv' in e ? e.recv : NIL);
      return { env, recv: 'recv' in e ? e.recv : NIL, label: e.label };
    }
    function updateButtons() {
      const live = !!(X && !X.done && X.stop), e = ui.sel, st = X && X.stop;
      B.proceed.disabled = X ? !live : false;
      B.restart.disabled = !live || !(e && e.fr);
      B.into.disabled = B.over.disabled = B.through.disabled = X ? !live : !(proc && proc.step);
      B.here.disabled = !live || !(e && e.fr);
      B.create.hidden = !(st && st.kind === 'dnu');
      B.unbp.hidden = !(st && ['break', 'objbreak', 'watch'].includes(st.kind) && BP.items.includes(st.bp));
      B.unbp.textContent = st && st.kind === 'watch' ? 'Unwatch' : 'Remove breakpoint';
      B.unbp.dataset.label = B.unbp.textContent;
      B.full.classList.toggle('on', ui.full);
      procLink.textContent = proc ? `Process '${proc.name}' · ${Sched.displayState(proc)}` : '';
    }

    // ---- actions
    const selFr = () => ui.sel && ui.sel.fr && X.frames.includes(ui.sel.fr) ? ui.sel.fr : X.topFrame();
    function go(mode, opts, note) { if (!X || X.done || !X.stop) return; Sched.poke(win.proc, 200); ui.note = note || ''; advance(X, mode, opts); }
    function proceed() {
      if (X) return go('run');
      ui.done = true; win.close(); simProceed(proc, o);
    }
    function step(mode) {
      if (X) return go(mode, { fr: selFr() });
      if (!proc || !proc.step) { Toast.show(`'${proc ? proc.name : '?'}' is waiting — nothing to step`); return; }
      let r; try { r = proc.step(); } catch (err) { Toast.show(err.message); return; }
      Sched.poke(win.proc, 200);
      if (proc.dbgHold) { ui.done = true; win.close(); openDebugger({ X: proc.dbgHold.X, pos: { x: win.x, y: win.y } }); return; }
      if (r === 'done') { Sched.finish(proc); ui.done = true; win.close(); Toast.show(`Process '${proc.name}' finished`); return; }
      ui.simSteps = (ui.simSteps || 0) + 1; ui.note = `ran ${ui.simSteps} ${ui.simSteps > 1 ? 'quanta' : 'quantum'} · ${proc.progress ? proc.progress() : ''}`;
      render();
    }
    function restart() { const e = ui.sel; if (!X || !e || !e.fr) return; go('into', { restart: e.fr }, 'restarted'); }
    function runToHere() {
      const e = ui.sel; if (!X || !e || !e.fr) return;
      go('toHere', { fr: e.fr, target: { fr: e.fr, pos: srcEd.ta.selectionStart } });
    }
    function where() {
      const i = defaultIndex();
      stack.select(String(i)); stack.el.focus();
      const e = entries[i]; if (!e) return;
      const mk = markOf(e, srcEd.value, i);
      if (mk) { srcEd.setMark(mk.s, mk.e, mk.kind + ' where'); scrollTo(mk.s); setTimeout(() => { if (srcEd.mark && srcEd.mark.kind.endsWith(' where')) srcEd.setMark(mk.s, mk.e, mk.kind); }, 700); }
    }
    function removeStopBp() { const st = X && X.stop; if (st && st.bp) { BP.remove(st.bp); Toast.show(st.kind === 'watch' ? 'Watchpoint removed — the object is writable again' : 'Breakpoint removed — the original method is back'); } }
    function accept() {
      const e = ui.sel; if (!X || X.done || !e || !e.fr) return;
      const txt = srcEd.value, fr = e.fr;
      const home = fr.kind === 'block' ? fr.homeFr : fr;
      if (!home || !X.frames.includes(home)) { Toast.show('The home context of this block has returned; accept it in a Browser'); return; }
      try {
        if (home.kind === 'doit') { M.parse(txt); X.src = txt; }
        else {
          const cm = compile(txt);
          if (cm.sel !== home.m.sel) throw new M.STError(`selector changed to #${cm.sel} — accept it in a Browser`);
          recompile(home.m, txt);
          TranscriptBuf.append(`${home.m.id} recompiled in the Debugger\n`);
        }
      } catch (err) {
        const at = srcEd.ta.selectionEnd;
        srcEd.insertAfter(at, ` ‹${err.message} →›`, 'error');
        return;
      }
      go('into', { restart: home }, 'accepted · frame restarted');
    }
    function create(at) {
      const st = X && X.stop; if (!st || st.kind !== 'dnu') return;
      const cn = M.className(st.recv), sel = st.sel;
      const classes = chainOf(cn).filter(c => CLS.has(c));
      Menu.show(at.x, at.y, classes.map(c => ({ label: c, desc: c === cn ? 'the receiver\'s class' : 'superclass', fn: () => createIn(c) })), `Define #${sel} in…`);
      function createIn(c) {
        const names = st.args.map((a, i) => { const n = article(M.className(a)).replace(' ', ''); return st.args.findIndex(b => M.className(b) === M.className(a)) === i ? n : n + (i + 1); });
        const pat = !st.args.length ? sel : !/^[A-Za-z]/.test(sel) ? `${sel} ${names[0]}` : sel.split(':').filter(Boolean).map((k, i) => `${k}: ${names[i]}`).join(' ');
        const src = `${pat}\n\t"Created in the Debugger. Write it, accept (${MOD}S), then Proceed."\n\n\t^self shouldBeImplemented`;
        const cls = CLS.get(c);
        (cls.protocols['as yet unclassified'] = cls.protocols['as yet unclassified'] || {})[pat] = src;
        TranscriptBuf.append(`${c}>>${sel} created in the Debugger\n`);
        go('into', { payload: { resend: true } }, `${c}>>${sel} created`);
        if (ui.done) return;
        const k = srcEd.value.indexOf('self shouldBeImplemented');
        if (k >= 0) { srcEd.focus(); srcEd.ta.setSelectionRange(k, k + 'self shouldBeImplemented'.length); }
      }
    }
    ui.create = create;
    ui.onStop = () => { if (ui.done) return; const d = describe(X.stop); if (d) setHead(d); render(); };
    ui.closeQuiet = () => { if (ui.done) return; ui.done = true; win.close(); };

    const bpSub = () => { if (!ui.done) { const keep = ui.sel && ui.sel.fr; const i = entries.indexOf(ui.sel); render(keep); if (!keep && i >= 0 && entries[i]) stack.select(String(i)); } };
    BP.subs.add(bpSub);
    const iv = setInterval(() => { if (proc) procLink.textContent = `Process '${proc.name}' · ${Sched.displayState(proc)}`; }, 300);
    win.onClose = () => {
      clearInterval(iv); BP.subs.delete(bpSub);
      if (proc && proc.dbgUI === ui) proc.dbgUI = null;
      if (X && X.ui === ui) X.ui = null;
      if (ui.done) return;
      ui.done = true;
      if (X) X.owner.abandon(); else simAbandon(proc);
    };
    setHead(head);
    render();
    setTimeout(() => stack.el.focus(), 0);
    return ui;
  }

  // ------------------------------------------------------------ Breakpoints window
  function openBreakpoints(o = {}) {
    const ex = [...WM.wins.values()].find(w => w.kind === 'breakpoints');
    if (ex) { ex.focus(); return ex; }
    const W = 520, H = 236;
    const pos = o.x != null ? o : WM.near(o.near, W, H, 40, 40);
    const win = WM.create({ title: 'Breakpoints', kind: 'breakpoints', cls: 'bpw', x: pos.x, y: pos.y, w: W, h: H, minW: 320, minH: 150, procName: 'Breakpoints' });
    let sel = null;
    const cur = () => BP.items.find(b => String(b.id) === sel);
    const list = new List({ cls: 'bpw-list', onSelect: k => { sel = k; upd(); }, onDbl: k => { sel = k; browse(); } });
    Object.assign(list.el.dataset, { role: 'breakpoints', label: 'Breakpoints' });
    const bEn = h('button', { class: 'btn', onclick: () => { const b = cur(); if (b) { b.enabled = !b.enabled; BP.changed(); } } }, 'Disable');
    const bRm = h('button', { class: 'btn', onclick: () => { const b = cur(); if (b) BP.remove(b); } }, 'Remove');
    const bAll = h('button', { class: 'btn', onclick: () => { BP.items = []; BP.changed(); } }, 'Remove all');
    const count = h('span', { class: 'note' });
    win.body.append(h('div', { class: 'toolbar' }, bEn, bRm, bAll, h('span', { class: 'sp' }), count), list.el,
      h('div', { class: 'statusbar' }, h('span', null, 'Browser method gutter: click to set · right-click for once, log, conditional'), h('span', { class: 'r' }, 'image-side')));
    function browse() {
      const b = cur(); if (!b) return;
      if (b.type === 'method') Tools.openBrowser({ cls: b.cls, proto: b.proto, sel: b.key, near: win });
      else inspectValue(b.obj, 'bp-' + win.id, win, BP.title(b));
    }
    function upd() {
      const b = cur();
      bEn.disabled = bRm.disabled = !b; bAll.disabled = !BP.items.length;
      bEn.textContent = b && !b.enabled ? 'Enable' : 'Disable';
    }
    function render() {
      if (!BP.items.some(b => String(b.id) === sel)) sel = null;
      list.set(BP.items.length ? BP.items.map(b => ({ key: String(b.id), cls: b.enabled ? '' : 'off',
        html: `<span class="bp-g on ${b.type === 'method' ? b.mode : b.type}${b.enabled ? '' : ' off'}"></span><span class="t">${esc(BP.title(b))}</span><span class="muted">${esc(BP.desc(b))}</span>` }))
        : [{ hdr: true, label: 'No breakpoints. Set one in a Browser\'s method list or an Inspector.' }], sel);
      count.textContent = `${BP.items.length} set`;
      upd();
    }
    BP.subs.add(render);
    win.onClose = () => BP.subs.delete(render);
    render();
    return win;
  }

  // ------------------------------------------------------------ small prompt (logpoint / condition source)
  function promptWin({ title, label, value, near, onOk }) {
    const W = 440, H = 176;
    const pos = WM.near(near, W, H, 90, 90);
    const win = WM.create({ title, kind: 'prompt', cls: 'dbg-prompt', x: pos.x, y: pos.y, w: W, h: H, minW: 300, minH: 140, proc: false });
    const ed = new Editor({ win, workspace: 'prompt-' + win.id, value, onAccept: () => ok() });
    function ok() {
      const v = ed.value.trim(); if (!v) return;
      try { M.parse(v); } catch (e) { ed.insertAfter(ed.value.length, ` ‹${e.message}›`, 'error'); return; }
      win.close(); onOk(v);
    }
    win.body.append(h('div', { class: 'dbg-prompt-l' }, label), ed.el,
      h('div', { class: 'nt-btns' }, h('button', { class: 'btn primary', onclick: ok }, 'Set'), h('button', { class: 'btn', onclick: () => win.close() }, 'Cancel'), h('span', { class: 'sp' }), h('span', { class: 'note' }, `${MOD}S sets`)));
    setTimeout(() => { ed.focus(); ed.ta.select(); }, 0);
    return win;
  }

  // ------------------------------------------------------------ System Browser: breakpoint gutter on the method list
  function setMethodBp(m, mode, expr) {
    const old = BP.method(m.id); if (old) BP.remove(old);
    BP.add({ type: 'method', mid: m.id, cls: m.cls, sel: m.sel, key: m.key, proto: m.proto, mode, expr });
    const full = findMethod(m.cls, m.sel);
    if (full && !runnable(full)) Toast.show(`Set. This prototype only runs Integer>>factorial, gcd:, isPrime and methods you write from source.`, 3400);
  }
  function methodMenu(x, y, m, near) {
    const b = BP.method(m.id);
    const full = findMethod(m.cls, m.sel), args = full ? (() => { try { return compile(full.src).args; } catch (e) { return []; } })() : [];
    Menu.show(x, y, [
      { label: b ? 'Remove breakpoint' : 'Set breakpoint', key: 'click', fn: () => b ? BP.remove(b) : setMethodBp(m, 'break') },
      { label: 'Break once', desc: 'removed on first hit', fn: () => setMethodBp(m, 'once') },
      { label: 'Logpoint…', desc: 'Transcript, no stop', fn: () => promptWin({ title: `Logpoint: ${m.id}`, label: 'Evaluated at entry with the arguments bound; the result goes to the Transcript.', near, value: `self printString, ' ${m.sel.includes(':') ? m.sel.split(':')[0] + ': ' : m.sel}'${args.length ? ', ' + args[0] + ' printString' : ''}`, onOk: v => setMethodBp(m, 'log', v) }) },
      { label: 'Conditional breakpoint…', desc: 'block source', fn: () => promptWin({ title: `Conditional breakpoint: ${m.id}`, label: 'Stops when this block answers true. Arguments and self are bound.', near, value: `[${args.length ? args[0] + ' > 10' : 'self > 5'}]`, onOk: v => setMethodBp(m, 'cond', v) }) },
      b ? { label: b.enabled ? 'Disable' : 'Enable', fn: () => { b.enabled = !b.enabled; BP.changed(); } } : null,
      '-',
      { label: 'Breakpoints…', fn: () => openBreakpoints({ near }) },
    ], m.id);
  }
  function attachBrowser(win) {
    const panes = win.body.querySelectorAll('.browser-top > .pane');
    const listEl = panes[3] && panes[3].querySelector('.list');
    if (!listEl) return;
    listEl.classList.add('bp-gutter');
    const clsName = () => {
      const t = /^System Browser: (.+)$/.exec(win.title || ''), side = win.body.querySelector('.seg button.on');
      return t && !(side && side.title === 'class side') ? t[1] : null;
    };
    const methodFor = key => {
      const cn = clsName(), cls = cn && CLS.get(cn); if (!cls) return null;
      for (const [pn, proto] of Object.entries(cls.protocols)) if (key in proto) return { cls: cn, sel: selectorOf(key), key, proto: pn, id: `${cn}>>${selectorOf(key)}` };
      return null;
    };
    const decorate = () => {
      for (const li of listEl.querySelectorAll('.li[data-key]')) {
        const m = methodFor(li.dataset.key);
        let g = li.querySelector('.bp-g');
        if (!m) { if (g) g.remove(); continue; }
        if (!g) { g = h('span', { 'data-role': 'breakpoint-toggle' }); li.prepend(g); }
        const b = BP.method(m.id);
        g.className = 'bp-g' + (b ? ` on ${b.mode}${b.enabled ? '' : ' off'}` : '');
        g.dataset.label = `breakpoint ${m.id}`;
        g.dataset.state = b ? `${b.mode}${b.enabled ? '' : ' disabled'}` : 'unset';
        g.title = b ? `${BP.desc(b)} — click to remove, right-click for more` : 'Click: set a breakpoint · right-click: once, logpoint, conditional';
      }
    };
    new MutationObserver(decorate).observe(listEl, { childList: true });
    listEl.addEventListener('mousedown', e => {
      const g = e.target.closest('.bp-g'); if (!g || e.button !== 0) return;
      e.stopPropagation(); e.preventDefault();
      const m = methodFor(g.closest('.li').dataset.key); if (!m) return;
      const b = BP.method(m.id);
      if (b) BP.remove(b); else setMethodBp(m, 'break');
    }, true);
    listEl.addEventListener('contextmenu', e => {
      const li = e.target.closest('.li[data-key]'); if (!li) return;
      e.preventDefault();
      const m = methodFor(li.dataset.key); if (m) methodMenu(e.clientX, e.clientY, m, win);
    });
    BP.subs.add(decorate);
    const oc = win.onClose; win.onClose = () => { BP.subs.delete(decorate); if (oc) oc(); };
    decorate();
  }
  const origBrowser = Tools.openBrowser;
  Tools.openBrowser = function (o) { const win = origBrowser.call(this, o); attachBrowser(win); return win; };

  // ------------------------------------------------------------ Inspector: halt on write, break when this object receives…
  function watchableField(obj, name) {
    if (!(Array.isArray(obj) || obj instanceof M.Pt)) return null;
    if (name === 'self') return 'self';
    if (obj instanceof M.Pt) return name === 'x' || name === 'y' ? name : null;
    return /^\d+$/.test(name) ? name : null;
  }
  const RECEIVES = {
    Array: ['at:', 'at:put:', 'do:', 'collect:', 'size', 'printString'], Point: ['x', 'y', 'x:', '+', 'printString'],
    String: ['size', 'asUppercase', 'reversed', 'printString'], Symbol: ['size', 'printString'],
    SmallInteger: ['factorial', 'gcd:', 'isPrime', 'printString'], LargePositiveInteger: ['factorial', 'printString', '*'],
    Fraction: ['reciprocal', '+', 'printString'],
  };
  function receivesMenu(x, y, obj) {
    const cn = M.className(obj);
    Menu.show(x, y, (RECEIVES[cn] || ['printString', '=', 'class']).map(s => ({
      label: '#' + s, fn: () => { BP.add({ type: 'object', obj, sel: s }); Toast.show(`Only this ${cn} halts on #${s} — it now belongs to an anonymous subclass`, 2800); },
    })), `Break when ${trunc(dprint(obj), 22)} receives…`);
  }
  function attachInspector(win, o) {
    const obj = o.result && o.result.value;
    const listEl = win.body.querySelector('.insp-top .list');
    if (!listEl) return;
    const rows = MiniST.inspect(obj);
    const decorate = () => {
      for (const li of listEl.querySelectorAll('.li[data-key]')) {
        const r = rows[+li.dataset.key], f = r && watchableField(obj, r.name), w = f && BP.watchOf(obj, f);
        li.classList.toggle('dbg-watched', !!w);
        let tag = li.querySelector('.dbg-wtag');
        if (w && !tag) li.append(h('span', { class: 'muted dbg-wtag', 'data-role': 'watch-tag', 'data-label': 'halt on write' }, 'halt on write'));
        if (!w && tag) tag.remove();
      }
    };
    listEl.addEventListener('contextmenu', e => {
      const li = e.target.closest('.li[data-key]'); if (!li) return;
      e.preventDefault();
      const r = rows[+li.dataset.key], f = watchableField(obj, r.name), w = f && BP.watchOf(obj, f);
      Menu.show(e.clientX, e.clientY, [
        { label: w ? 'Remove watchpoint' : f === 'self' ? 'Halt on any write' : 'Halt on write', desc: f ? 'sets the immutability bit' : 'immutable value', disabled: !f,
          fn: () => { if (w) BP.remove(w); else { BP.add({ type: 'watch', obj, field: f }); Toast.show(`Watchpoint: ${trunc(dprint(obj), 20)} is read-only now; a store into ${f === 'self' ? 'it' : f} halts`, 2800); } } },
        { label: 'Break when this object receives…', fn: () => receivesMenu(e.clientX, e.clientY, obj) },
        '-',
        { label: 'Breakpoints…', fn: () => openBreakpoints({ near: win }) },
      ], r.name === 'self' ? trunc(dprint(obj), 28) : `${r.name} of ${trunc(dprint(obj), 20)}`);
    });
    BP.subs.add(decorate);
    const oc = win.onClose; win.onClose = () => { BP.subs.delete(decorate); if (oc) oc(); };
    decorate();
  }
  const origInspector = Tools.openInspector;
  Tools.openInspector = function (o) { const win = origInspector.call(this, o); attachInspector(win, o); return win; };

  Tools.openDebugger = o => openDebugger(o || {});
  Tools.openBreakpoints = openBreakpoints;
  Object.assign(D, { open: openDebugger, openBreakpoints, advance });
})();
