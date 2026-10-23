// Tiny Smalltalk-subset evaluator for UI prototypes. Not the real system.
// API: MiniST.evaluate(source, {transcript: s => ..., workspace: id}) -> {value, printString, className}
//      MiniST.printString(value), MiniST.inspect(value) -> [{name, value}]
(function (global) {
  'use strict';

  class Sym { constructor(n) { this.name = n; } }
  class Chr { constructor(c) { this.c = c; } }
  class Pt { constructor(x, y) { this.x = x; this.y = y; } }
  class Frac { constructor(n, d) { this.n = n; this.d = d; } }
  class Block { constructor(params, temps, body, env, home) { Object.assign(this, { params, temps, body, env, home }); } }
  class ClassRef { constructor(name) { this.name = name; } }
  const NIL = null;
  const Transcript = { isTranscript: true };

  const bigGcd = (a, b) => { a = a < 0n ? -a : a; b = b < 0n ? -b : b; while (b) [a, b] = [b, a % b]; return a; };
  function mkFrac(n, d) {
    if (d === 0n) throw new STError('ZeroDivide');
    if (d < 0n) { n = -n; d = -d; }
    const g = bigGcd(n, d);
    n /= g; d /= g;
    return d === 1n ? n : new Frac(n, d);
  }
  const isInt = v => typeof v === 'bigint';
  const isNum = v => typeof v === 'bigint' || typeof v === 'number' || v instanceof Frac;
  const toFloat = v => isInt(v) ? Number(v) : v instanceof Frac ? Number(v.n) / Number(v.d) : v;

  class STError extends Error {}
  class NonLocalReturn { constructor(home, value) { this.home = home; this.value = value; } }

  // ---------- lexer ----------
  function lex(src) {
    const toks = []; let i = 0;
    const push0 = toks.push.bind(toks); toks.push = t => { t.s = i; return push0(t); }; // source positions (debugger)
    const isLetter = c => /[A-Za-z_]/.test(c), isDigit = c => /[0-9]/.test(c);
    const binChars = '+-*/\\<>=~@%|&?,';
    while (i < src.length) {
      if (toks.length && toks[toks.length - 1].e == null) toks[toks.length - 1].e = i;
      const c = src[i];
      if (/\s/.test(c)) { i++; continue; }
      if (c === '"') { const j = src.indexOf('"', i + 1); i = j < 0 ? src.length : j + 1; continue; }
      if (isLetter(c)) {
        let j = i; while (j < src.length && /[A-Za-z0-9_]/.test(src[j])) j++;
        if (src[j] === ':' && src[j + 1] !== '=') { toks.push({ t: 'kw', v: src.slice(i, j + 1) }); i = j + 1; }
        else { toks.push({ t: 'id', v: src.slice(i, j) }); i = j; }
        continue;
      }
      if (isDigit(c) || (c === '-' && isDigit(src[i + 1] || '') && (!toks.length || ['bin', 'kw', '(', '[', '.', ':=', '^'].includes(toks[toks.length - 1].t)))) {
        let j = i + 1; while (j < src.length && isDigit(src[j])) j++;
        if (src[j] === 'r') {
          const radix = parseInt(src.slice(i, j)); let k = j + 1; while (k < src.length && /[0-9A-Z]/.test(src[k])) k++;
          toks.push({ t: 'num', v: BigInt(parseInt(src.slice(j + 1, k), radix)) }); i = k; continue;
        }
        if (src[j] === '.' && isDigit(src[j + 1] || '')) {
          j++; while (j < src.length && isDigit(src[j])) j++;
          if (src[j] === 'e') { j++; if (src[j] === '-') j++; while (isDigit(src[j] || '')) j++; }
          toks.push({ t: 'num', v: parseFloat(src.slice(i, j)) });
        } else toks.push({ t: 'num', v: BigInt(src.slice(i, j)) });
        i = j; continue;
      }
      if (c === "'") {
        let s = '', j = i + 1;
        while (j < src.length) { if (src[j] === "'") { if (src[j + 1] === "'") { s += "'"; j += 2; continue; } break; } s += src[j++]; }
        toks.push({ t: 'str', v: s }); i = j + 1; continue;
      }
      if (c === '$') { toks.push({ t: 'chr', v: src[i + 1] }); i += 2; continue; }
      if (c === '#') {
        if (src[i + 1] === '(') { toks.push({ t: '#(' }); i += 2; continue; }
        let j = i + 1; while (j < src.length && /[A-Za-z0-9_:]/.test(src[j])) j++;
        if (j === i + 1) { while (j < src.length && binChars.includes(src[j])) j++; }
        toks.push({ t: 'sym', v: src.slice(i + 1, j) }); i = j; continue;
      }
      if (c === ':' && src[i + 1] === '=') { toks.push({ t: ':=' }); i += 2; continue; }
      if (c === ':') { toks.push({ t: ':' }); i++; continue; }
      if ('()[].^;{}'.includes(c)) { toks.push({ t: c }); i++; continue; }
      if (binChars.includes(c)) {
        let j = i; while (j < src.length && binChars.includes(src[j])) j++;
        toks.push({ t: 'bin', v: src.slice(i, j) }); i = j; continue;
      }
      throw new STError('Unexpected character: ' + c);
    }
    if (toks.length && toks[toks.length - 1].e == null) toks[toks.length - 1].e = i;
    toks.push({ t: 'eof' });
    return toks;
  }

  // ---------- parser ----------
  function parse(src) {
    const toks = lex(src); let p = 0;
    const peek = () => toks[p], next = () => toks[p++];
    const expect = t => { if (peek().t !== t) throw new STError(`Expected ${t} but found ${peek().v ?? peek().t}`); return next(); };

    function temps() {
      const names = [];
      if (peek().t === 'bin' && peek().v === '|') { next(); while (peek().t === 'id') names.push(next().v); expect('bin'); }
      else if (peek().t === 'bin' && peek().v === '||') { next(); }
      return names;
    }
    function statements(end) {
      const out = [];
      while (peek().t !== end && peek().t !== 'eof') {
        const s0 = peek().s;
        if (peek().t === '^') { next(); out.push({ k: 'ret', e: expr() }); }
        else out.push(expr());
        out[out.length - 1].at = [s0, toks[p - 1].e]; // statement source range (debugger)
        if (peek().t === '.') next(); else break;
      }
      return out;
    }
    function expr() {
      if (peek().t === 'id' && toks[p + 1].t === ':=') { const n = next().v; next(); return { k: 'assign', n, e: expr() }; }
      const e = keywordTail(binaryTail(unaryTail(primary())));
      if (peek().t === ';') {
        const rest = [];
        while (peek().t === ';') { next(); rest.push(keywordTail(binaryTail(unaryTail({ k: 'hole' })))); }
        return { k: 'cascade', first: e, rest };
      }
      return e;
    }
    function unaryTail(r) { while (peek().t === 'id') r = { k: 'send', r, sel: next().v, args: [] }; return r; }
    function binaryTail(r) {
      while (peek().t === 'bin') { const sel = next().v; r = { k: 'send', r, sel, args: [unaryTail(primary())] }; }
      return r;
    }
    function keywordTail(r) {
      if (peek().t !== 'kw') return r;
      let sel = ''; const args = [];
      while (peek().t === 'kw') { sel += next().v; args.push(binaryTail(unaryTail(primary()))); }
      return { k: 'send', r, sel, args };
    }
    function literalArray() {
      const items = [];
      while (peek().t !== ')') {
        const t = next();
        if (t.t === 'num' || t.t === 'str') items.push(t.v);
        else if (t.t === 'sym') items.push(new Sym(t.v));
        else if (t.t === 'chr') items.push(new Chr(t.v));
        else if (t.t === 'id') items.push(t.v === 'true' ? true : t.v === 'false' ? false : t.v === 'nil' ? NIL : new Sym(t.v));
        else if (t.t === 'kw' || t.t === 'bin') items.push(new Sym(t.v));
        else if (t.t === '(' || t.t === '#(') items.push(literalArray());
        else throw new STError('Bad literal array');
      }
      next(); return items;
    }
    function primary() {
      const t = next();
      switch (t.t) {
        case 'num': case 'str': return { k: 'lit', v: t.v };
        case 'sym': return { k: 'lit', v: new Sym(t.v) };
        case 'chr': return { k: 'lit', v: new Chr(t.v) };
        case '#(': return { k: 'lit', v: literalArray() };
        case 'id': return { k: 'var', n: t.v };
        case '(': { const e = expr(); expect(')'); return e; }
        case '{': { const items = statements('}'); expect('}'); return { k: 'brace', items }; }
        case '[': {
          const params = [];
          while (peek().t === ':') { next(); params.push(expect('id').v); }
          if (params.length) {
            if (peek().t === 'bin' && peek().v === '|') next();
            else if (peek().t === 'bin' && peek().v === '||') toks[p] = { t: 'bin', v: '|' };
          }
          const ts = temps(); const body = statements(']'); expect(']');
          return { k: 'block', params, temps: ts, body };
        }
        default: throw new STError('Unexpected ' + (t.v ?? t.t));
      }
    }
    const ts = temps();
    const body = statements('eof');
    if (peek().t !== 'eof') throw new STError('Unexpected ' + (peek().v ?? peek().t));
    return { temps: ts, body };
  }

  // ---------- evaluator ----------
  class Env {
    constructor(parent) { this.vars = new Map(); this.parent = parent; }
    lookup(n) { for (let e = this; e; e = e.parent) if (e.vars.has(n)) return e; return null; }
  }
  const GLOBAL_CLASSES = ['Object', 'Integer', 'SmallInteger', 'Float', 'Fraction', 'String', 'Symbol', 'Array', 'Point', 'Character',
    'BlockClosure', 'Boolean', 'UndefinedObject', 'Smalltalk', 'Processor', 'Process', 'Window', 'Compositor', 'OrderedCollection', 'Date', 'Time'];

  function evalNode(n, env, ctx) {
    switch (n.k) {
      case 'lit': return Array.isArray(n.v) ? n.v.slice() : n.v;
      case 'var': {
        if (n.n === 'nil') return NIL; if (n.n === 'true') return true; if (n.n === 'false') return false;
        if (n.n === 'Transcript') return Transcript;
        const e = env.lookup(n.n); if (e) return e.vars.get(n.n);
        if (GLOBAL_CLASSES.includes(n.n)) return new ClassRef(n.n);
        throw new STError('Undeclared variable: ' + n.n);
      }
      case 'assign': {
        const v = evalNode(n.e, env, ctx);
        (env.lookup(n.n) || ctx.root).vars.set(n.n, v); return v;
      }
      case 'ret': throw new NonLocalReturn(ctx.home, evalNode(n.e, env, ctx));
      case 'brace': return n.items.map(i => evalNode(i, env, ctx));
      case 'block': return new Block(n.params, n.temps, n.body, env, ctx.home);
      case 'send': {
        const r = evalNode(n.r, env, ctx);
        return send(r, n.sel, n.args.map(a => evalNode(a, env, ctx)), ctx);
      }
      case 'cascade': {
        const first = n.first; let recv, result;
        if (first.k === 'send') { recv = evalNode(first.r, env, ctx); result = send(recv, first.sel, first.args.map(a => evalNode(a, env, ctx)), ctx); }
        else { recv = evalNode(first, env, ctx); result = recv; }
        for (const part of n.rest) {
          const saved = ctx.hole; ctx.hole = recv;
          try { result = evalNode(part, env, ctx); } finally { ctx.hole = saved; }
        }
        return result;
      }
      case 'hole': return ctx.hole;
    }
    throw new STError('bad node');
  }
  function runBody(body, env, ctx) { let v = NIL; for (const s of body) v = evalNode(s, env, ctx); return v; }
  function callBlock(b, args, ctx) {
    if (!(b instanceof Block)) throw new STError(`${printString(b)} doesNotUnderstand: #value`);
    if (args.length !== b.params.length) throw new STError(`Block expects ${b.params.length} arguments, got ${args.length}`);
    if (++ctx.counter.steps > 2e6) throw new STError('Too many steps (prototype evaluator limit)');
    const env = new Env(b.env);
    b.params.forEach((p, i) => env.vars.set(p, args[i]));
    b.temps.forEach(t => env.vars.set(t, NIL));
    return runBody(b.body, env, { ...ctx, home: b.home });
  }
  const truthy = v => { if (v === true) return true; if (v === false) return false; throw new STError('NonBooleanReceiver: proceed for truth.'); };

  function numOp(a, b, op) {
    if (!isNum(b)) throw new STError(`${printString(b)} is not a number`);
    if (typeof a === 'number' || typeof b === 'number') {
      const x = toFloat(a), y = toFloat(b);
      switch (op) { case '+': return x + y; case '-': return x - y; case '*': return x * y; case '/': if (y === 0) throw new STError('ZeroDivide'); return x / y; }
    }
    const [an, ad] = isInt(a) ? [a, 1n] : [a.n, a.d], [bn, bd] = isInt(b) ? [b, 1n] : [b.n, b.d];
    switch (op) {
      case '+': return mkFrac(an * bd + bn * ad, ad * bd);
      case '-': return mkFrac(an * bd - bn * ad, ad * bd);
      case '*': return mkFrac(an * bn, ad * bd);
      case '/': return mkFrac(an * bd, ad * bn);
    }
  }
  function cmp(a, b) {
    if (!isNum(b)) throw new STError(`${printString(b)} is not a number`);
    if (typeof a === 'number' || typeof b === 'number') { const x = toFloat(a), y = toFloat(b); return x < y ? -1 : x > y ? 1 : 0; }
    const d = numOp(a, b, '-'); const s = isInt(d) ? d : d.n; return s < 0n ? -1 : s > 0n ? 1 : 0;
  }
  function equal(a, b) {
    if (isNum(a) && isNum(b)) return cmp(a, b) === 0;
    if (a instanceof Sym && b instanceof Sym) return a.name === b.name;
    if (a instanceof Chr && b instanceof Chr) return a.c === b.c;
    if (a instanceof Pt && b instanceof Pt) return equal(a.x, b.x) && equal(a.y, b.y);
    if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => equal(x, b[i]));
    return a === b;
  }
  const toIndex = v => { if (!isInt(v)) throw new STError('Index must be an integer'); return Number(v); };
  function seqOf(v) { if (typeof v === 'string') return [...v].map(c => new Chr(c)); if (Array.isArray(v)) return v; if (v instanceof Sym) return [...v.name].map(c => new Chr(c)); return null; }
  function rebuild(like, items) { if (typeof like === 'string' && items.every(i => i instanceof Chr)) return items.map(i => i.c).join(''); return items; }

  function send(r, sel, args, ctx) {
    const [a, b] = args;
    switch (sel) {
      case '==': return r === a || (r instanceof Sym && a instanceof Sym && r.name === a.name);
      case '~~': return !send(r, '==', args, ctx);
      case '=': return equal(r, a);
      case '~=': return !equal(r, a);
      case 'printString': return printString(r);
      case 'displayString': return typeof r === 'string' ? r : r instanceof Sym ? r.name : printString(r);
      case 'class': return new ClassRef(className(r));
      case 'isNil': return r === NIL; case 'notNil': return r !== NIL;
      case 'ifNil:': return r === NIL ? callBlock(a, [], ctx) : r;
      case 'ifNotNil:': return r !== NIL ? callBlock(a, a.params.length ? [r] : [], ctx) : NIL;
      case 'ifNil:ifNotNil:': return r === NIL ? callBlock(a, [], ctx) : callBlock(b, b.params.length ? [r] : [], ctx);
      case 'yourself': case 'inspect': return r;
      case '->': return { assoc: true, key: r, value: a };
      case 'isString': return typeof r === 'string'; case 'isNumber': return isNum(r); case 'isSymbol': return r instanceof Sym;
    }
    if (r === Transcript) {
      if (sel === 'show:') { ctx.transcript(typeof a === 'string' ? a : a instanceof Sym ? a.name : printString(a)); return r; }
      if (sel === 'cr') { ctx.transcript('\n'); return r; }
      if (sel === 'tab') { ctx.transcript('\t'); return r; }
      if (sel === 'space') { ctx.transcript(' '); return r; }
      if (sel === 'print:') { ctx.transcript(printString(a)); return r; }
    }
    if (r === true || r === false) {
      switch (sel) {
        case 'ifTrue:': return r ? callBlock(a, [], ctx) : NIL;
        case 'ifFalse:': return !r ? callBlock(a, [], ctx) : NIL;
        case 'ifTrue:ifFalse:': return callBlock(r ? a : b, [], ctx);
        case 'ifFalse:ifTrue:': return callBlock(r ? b : a, [], ctx);
        case '&': return r && truthy(a); case '|': return r || truthy(a);
        case 'and:': return r ? truthy(callBlock(a, [], ctx)) : false;
        case 'or:': return r ? true : truthy(callBlock(a, [], ctx));
        case 'not': return !r;
      }
    }
    if (isNum(r)) {
      switch (sel) {
        case '+': case '-': case '*': case '/': return numOp(r, a, sel);
        case '<': return cmp(r, a) < 0; case '>': return cmp(r, a) > 0;
        case '<=': return cmp(r, a) <= 0; case '>=': return cmp(r, a) >= 0;
        case '@': return new Pt(r, a);
        case '//': if (isInt(r) && isInt(a)) { if (a === 0n) throw new STError('ZeroDivide'); let q = r / a; if ((r % a !== 0n) && ((r < 0n) !== (a < 0n))) q -= 1n; return q; } return BigInt(Math.floor(toFloat(r) / toFloat(a)));
        case '\\\\': if (isInt(r) && isInt(a)) { if (a === 0n) throw new STError('ZeroDivide'); let m = r % a; if (m !== 0n && ((m < 0n) !== (a < 0n))) m += a; return m; } { const x = toFloat(r), y = toFloat(a); return x - Math.floor(x / y) * y; }
        case 'rem:': return isInt(r) && isInt(a) ? r % a : toFloat(r) % toFloat(a);
        case 'negated': return numOp(0n, r, '-');
        case 'abs': return cmp(r, 0n) < 0 ? numOp(0n, r, '-') : r;
        case 'squared': return numOp(r, r, '*');
        case 'sqrt': return Math.sqrt(toFloat(r));
        case 'sin': return Math.sin(toFloat(r)); case 'cos': return Math.cos(toFloat(r)); case 'ln': return Math.log(toFloat(r)); case 'exp': return Math.exp(toFloat(r));
        case 'asFloat': return toFloat(r);
        case 'rounded': return BigInt(Math.round(toFloat(r))); case 'truncated': return isInt(r) ? r : BigInt(Math.trunc(toFloat(r)));
        case 'floor': return isInt(r) ? r : BigInt(Math.floor(toFloat(r))); case 'ceiling': return isInt(r) ? r : BigInt(Math.ceil(toFloat(r)));
        case 'reciprocal': return numOp(1n, r, '/');
        case 'numerator': return r instanceof Frac ? r.n : r; case 'denominator': return r instanceof Frac ? r.d : 1n;
        case 'max:': return cmp(r, a) >= 0 ? r : a; case 'min:': return cmp(r, a) <= 0 ? r : a;
        case 'between:and:': return cmp(r, a) >= 0 && cmp(r, b) <= 0;
        case 'isZero': return cmp(r, 0n) === 0; case 'even': return isInt(r) && r % 2n === 0n; case 'odd': return isInt(r) && r % 2n !== 0n;
        case 'isPrime': { if (!isInt(r) || r < 2n) return false; for (let i = 2n; i * i <= r; i++) if (r % i === 0n) return false; return true; }
        case 'sign': return BigInt(cmp(r, 0n));
        case 'factorial': { if (!isInt(r) || r < 0n) throw new STError('Not valid for negative integers'); let f = 1n; for (let i = 2n; i <= r; i++) f *= i; return f; }
        case 'raisedTo:': if (isInt(r) && isInt(a) && a >= 0n) return r ** a; return Math.pow(toFloat(r), toFloat(a));
        case 'gcd:': return bigGcd(r, a); case 'lcm:': return (r * a) / bigGcd(r, a);
        case 'printString:': case 'printStringBase:': case 'radix:': return isInt(r) ? r.toString(Number(a)).toUpperCase() : printString(r);
        case 'asString': return printString(r);
        case 'asCharacter': return new Chr(String.fromCharCode(Number(r)));
        case 'to:': { const out = []; for (let i = r; cmp(i, a) <= 0; i = numOp(i, 1n, '+')) out.push(i); return out; }
        case 'to:by:': { const out = []; const up = cmp(b, 0n) > 0; for (let i = r; up ? cmp(i, a) <= 0 : cmp(i, a) >= 0; i = numOp(i, b, '+')) out.push(i); return out; }
        case 'to:do:': { for (let i = r; cmp(i, a) <= 0; i = numOp(i, 1n, '+')) callBlock(b, [i], ctx); return r; }
        case 'timesRepeat:': { for (let i = 0n; i < r; i++) callBlock(a, [], ctx); return r; }
      }
    }
    if (r instanceof Pt) {
      const pw = op => a instanceof Pt ? new Pt(numOp(r.x, a.x, op), numOp(r.y, a.y, op)) : new Pt(numOp(r.x, a, op), numOp(r.y, a, op));
      switch (sel) {
        case 'x': return r.x; case 'y': return r.y;
        case '+': case '-': case '*': return pw(sel);
        case 'dist:': return Math.hypot(toFloat(r.x) - toFloat(a.x), toFloat(r.y) - toFloat(a.y));
        case 'transposed': return new Pt(r.y, r.x);
      }
    }
    if (r instanceof Block) {
      switch (sel) {
        case 'value': return callBlock(r, [], ctx);
        case 'value:': return callBlock(r, [a], ctx);
        case 'value:value:': return callBlock(r, [a, b], ctx);
        case 'value:value:value:': return callBlock(r, args, ctx);
        case 'valueWithArguments:': return callBlock(r, a, ctx);
        case 'numArgs': return BigInt(r.params.length);
        case 'whileTrue:': while (truthy(callBlock(r, [], ctx))) callBlock(a, [], ctx); return NIL;
        case 'whileFalse:': while (!truthy(callBlock(r, [], ctx))) callBlock(a, [], ctx); return NIL;
        case 'whileTrue': while (truthy(callBlock(r, [], ctx))); return NIL;
        case 'fork': case 'forkAt:': case 'forkNamed:': if (ctx.forked) ctx.forked(r, sel === 'forkNamed:' ? a : null); return new Sym('aProcess');
        case 'on:do:': try { return callBlock(r, [], ctx); } catch (e) { if (e instanceof STError) return callBlock(b, b.params.length ? [e.message] : [], ctx); throw e; }
        case 'ensure:': try { return callBlock(r, [], ctx); } finally { callBlock(a, [], ctx); }
        case 'timeToRun': { const t = performance.now(); callBlock(r, [], ctx); return BigInt(Math.round(performance.now() - t)); }
      }
    }
    if (r instanceof Chr) {
      switch (sel) {
        case 'asInteger': case 'value': case 'asciiValue': return BigInt(r.c.charCodeAt(0));
        case 'asUppercase': return new Chr(r.c.toUpperCase()); case 'asLowercase': return new Chr(r.c.toLowerCase());
        case 'isVowel': return 'aeiouAEIOU'.includes(r.c); case 'isLetter': return /[A-Za-z]/.test(r.c); case 'isDigit': return /[0-9]/.test(r.c);
        case 'asString': return r.c; case 'asSymbol': return new Sym(r.c);
        case '<': return r.c < a.c; case '>': return r.c > a.c;
      }
    }
    if (r instanceof Sym) {
      switch (sel) {
        case 'asString': return r.name; case 'asSymbol': return r; case 'size': return BigInt(r.name.length);
        case 'numArgs': return BigInt((r.name.match(/:/g) || []).length || (/^[A-Za-z]/.test(r.name) ? 0 : 1));
        case 'value:': return send(a, r.name, [], ctx);
        case 'value:value:': return send(a, r.name, [b], ctx);
      }
    }
    if (r instanceof ClassRef) {
      switch (sel) {
        case 'name': return r.name;
        case 'new': if (r.name === 'OrderedCollection' || r.name === 'Array') return []; break;
        case 'new:': if (r.name === 'Array') return new Array(toIndex(a)).fill(NIL); if (r.name === 'String') return ' '.repeat(toIndex(a)); return [];
        case 'with:': return [a]; case 'with:with:': return [a, b]; case 'with:with:with:': return args.slice();
        case 'x:y:': if (r.name === 'Point') return new Pt(a, b); break;
        case 'pi': return Math.PI; case 'e': return Math.E;
        case 'today': return new Date().toDateString(); case 'now': return new Date().toLocaleTimeString();
        case 'superclass': return new ClassRef({ SmallInteger: 'Integer', Integer: 'Number', Float: 'Number', Fraction: 'Number', String: 'ArrayedCollection', Symbol: 'String', Array: 'ArrayedCollection', Object: 'ProtoObject' }[r.name] || 'Object');
        case 'version': return 'Prototype 0.0 (mini-st.js)';
        case 'activeProcess': if (r.name === 'Processor') return new Sym('aProcess'); break;
        case 'yield': if (r.name === 'Processor') return r; break;
      }
    }
    const seq = seqOf(r);
    if (seq) {
      const rb = items => rebuild(r, items);
      switch (sel) {
        case 'size': return BigInt(seq.length);
        case 'isEmpty': return seq.length === 0; case 'notEmpty': return seq.length > 0;
        case 'first': return seq[0] ?? NIL; case 'last': return seq[seq.length - 1] ?? NIL;
        case 'at:': { const i = toIndex(a); if (i < 1 || i > seq.length) throw new STError(`Index out of bounds: ${i}`); return seq[i - 1]; }
        case 'at:put:': { const i = toIndex(a); if (!Array.isArray(r)) throw new STError('Literal is read-only'); if (i < 1 || i > r.length) throw new STError(`Index out of bounds: ${i}`); r[i - 1] = b; return b; }
        case 'add:': case 'addLast:': if (Array.isArray(r)) { r.push(a); return a; } break;
        case 'addFirst:': if (Array.isArray(r)) { r.unshift(a); return a; } break;
        case 'addAll:': if (Array.isArray(r)) { r.push(...seqOf(a)); return a; } break;
        case 'removeFirst': if (Array.isArray(r)) return r.shift(); break;
        case 'removeLast': if (Array.isArray(r)) return r.pop(); break;
        case 'do:': seq.forEach(x => callBlock(a, [x], ctx)); return r;
        case 'doWithIndex:': case 'withIndexDo:': seq.forEach((x, i) => callBlock(a, [x, BigInt(i + 1)], ctx)); return r;
        case 'reverseDo:': [...seq].reverse().forEach(x => callBlock(a, [x], ctx)); return r;
        case 'do:separatedBy:': seq.forEach((x, i) => { if (i) callBlock(b, [], ctx); callBlock(a, [x], ctx); }); return r;
        case 'collect:': return rebuild(r, seq.map(x => a instanceof Sym ? send(x, a.name, [], ctx) : callBlock(a, [x], ctx)));
        case 'select:': return rb(seq.filter(x => truthy(callBlock(a, [x], ctx))));
        case 'reject:': return rb(seq.filter(x => !truthy(callBlock(a, [x], ctx))));
        case 'detect:': return seq.find(x => truthy(callBlock(a, [x], ctx))) ?? NIL;
        case 'detect:ifNone:': { const f = seq.find(x => truthy(callBlock(a, [x], ctx))); return f === undefined ? callBlock(b, [], ctx) : f; }
        case 'inject:into:': return seq.reduce((acc, x) => callBlock(b, [acc, x], ctx), a);
        case 'anySatisfy:': return seq.some(x => truthy(callBlock(a, [x], ctx)));
        case 'allSatisfy:': return seq.every(x => truthy(callBlock(a, [x], ctx)));
        case 'count:': return BigInt(seq.filter(x => truthy(callBlock(a, [x], ctx))).length);
        case 'includes:': return seq.some(x => equal(x, a));
        case 'indexOf:': return BigInt(seq.findIndex(x => equal(x, a)) + 1);
        case 'reversed': case 'reverse': return rb([...seq].reverse());
        case 'asArray': case 'asOrderedCollection': case 'asBag': return [...seq];
        case 'asSet': { const out = []; seq.forEach(x => { if (!out.some(y => equal(x, y))) out.push(x); }); return out; }
        case 'asSortedCollection': case 'sorted': return rb([...seq].sort((x, y) => isNum(x) ? cmp(x, y) : (x.c ?? String(x)) < (y.c ?? String(y)) ? -1 : 1));
        case 'asSortedCollection:': case 'sorted:': case 'sort:': return rb([...seq].sort((x, y) => truthy(callBlock(a, [x, y], ctx)) ? -1 : 1));
        case 'sum': return seq.reduce((s, x) => numOp(s, x, '+'), 0n);
        case 'max': return seq.reduce((m, x) => cmp(x, m) > 0 ? x : m);
        case 'min': return seq.reduce((m, x) => cmp(x, m) < 0 ? x : m);
        case 'average': return numOp(seq.reduce((s, x) => numOp(s, x, '+'), 0n), BigInt(seq.length), '/');
        case ',': { const other = seqOf(a); if (!other) throw new STError('Cannot concatenate'); return rebuild(r, [...seq, ...other]); }
        case 'copyFrom:to:': return rb(seq.slice(toIndex(a) - 1, toIndex(b)));
        case 'copyWith:': return rb([...seq, a]);
        case 'allButFirst': return rb(seq.slice(1)); case 'allButLast': return rb(seq.slice(0, -1));
        case 'first:': return rb(seq.slice(0, toIndex(a))); case 'last:': return rb(seq.slice(-toIndex(a)));
        case 'with:collect:': { const o = seqOf(a); return seq.map((x, i) => callBlock(b, [x, o[i]], ctx)); }
      }
      if (typeof r === 'string') {
        switch (sel) {
          case 'asUppercase': return r.toUpperCase(); case 'asLowercase': return r.toLowerCase();
          case 'asSymbol': return new Sym(r); case 'asString': return r;
          case 'asNumber': case 'asInteger': return /^-?\d+$/.test(r.trim()) ? BigInt(r.trim()) : parseFloat(r);
          case 'substrings': return r.split(/\s+/).filter(Boolean);
          case 'substrings:': return r.split(new RegExp('[' + a.replace(/[\]\\^-]/g, '\\$&') + ']')).filter(Boolean);
          case 'includesSubstring:': return r.includes(a);
          case 'beginsWith:': return r.startsWith(a); case 'endsWith:': return r.endsWith(a);
          case 'trimBoth': return r.trim();
          case 'occurrencesOf:': return BigInt([...r].filter(c => c === a.c).length);
          case 'copyReplaceAll:with:': return r.split(a).join(b);
          case 'lines': return r.split('\n');
          case '<': return r < a; case '>': return r > a;
          case 'format:': return r.replace(/\{(\d+)\}/g, (_, i) => { const v = a[Number(i) - 1]; return typeof v === 'string' ? v : printString(v); });
        }
      }
    }
    if (r && r.assoc) { if (sel === 'key') return r.key; if (sel === 'value') return r.value; }
    if (global.MiniST.fallback) { const f = global.MiniST.fallback(r, sel, args, ctx); if (f) return f.value; } // debugger: user methods, extras
    throw new STError(`${printString(r)} doesNotUnderstand: #${sel}`);
  }

  function className(v) {
    if (v === NIL) return 'UndefinedObject';
    if (v === true) return 'True'; if (v === false) return 'False';
    if (typeof v === 'bigint') return (v < 2n ** 60n && v >= -(2n ** 60n)) ? 'SmallInteger' : v < 0n ? 'LargeNegativeInteger' : 'LargePositiveInteger';
    if (typeof v === 'number') return 'Float';
    if (typeof v === 'string') return 'String';
    if (v instanceof Frac) return 'Fraction'; if (v instanceof Sym) return 'Symbol'; if (v instanceof Chr) return 'Character';
    if (v instanceof Pt) return 'Point'; if (v instanceof Block) return 'BlockClosure'; if (Array.isArray(v)) return 'Array';
    if (v instanceof ClassRef) return v.name + ' class';
    if (v === Transcript) return 'TranscriptStream';
    if (v && v.assoc) return 'Association';
    return 'Object';
  }

  function printFloat(f) {
    if (!isFinite(f)) return isNaN(f) ? 'NaN' : f > 0 ? 'Float infinity' : 'Float negativeInfinity';
    if (Number.isInteger(f) && Math.abs(f) < 1e16) return f.toFixed(1);
    return String(f).replace('e+', 'e');
  }
  function printString(v, depth = 0) {
    if (depth > 6) return '...';
    if (v === NIL) return 'nil';
    if (v === true) return 'true'; if (v === false) return 'false';
    if (typeof v === 'bigint') return v.toString();
    if (typeof v === 'number') return printFloat(v);
    if (typeof v === 'string') return "'" + v.replace(/'/g, "''") + "'";
    if (v instanceof Frac) return `(${v.n}/${v.d})`;
    if (v instanceof Sym) return '#' + v.name;
    if (v instanceof Chr) return '$' + v.c;
    if (v instanceof Pt) return `${printString(v.x)}@${printString(v.y)}`;
    if (v instanceof Block) return 'a BlockClosure';
    if (v instanceof ClassRef) return v.name;
    if (v === Transcript) return 'a TranscriptStream';
    if (v && v.assoc) return `${printString(v.key, depth + 1)}->${printString(v.value, depth + 1)}`;
    if (Array.isArray(v)) {
      const items = v.length > 200 ? v.slice(0, 200) : v;
      return `#(${items.map(x => printString(x, depth + 1)).join(' ')}${v.length > 200 ? ' ...' : ''})`;
    }
    return 'an Object';
  }

  const workspaces = new Map();
  function evaluate(source, opts = {}) {
    const tree = parse(source);
    const id = opts.workspace || 'default';
    let root = workspaces.get(id);
    if (!root) { root = new Env(null); workspaces.set(id, root); }
    tree.temps.forEach(t => { if (!root.vars.has(t)) root.vars.set(t, NIL); });
    const home = {};
    const ctx = { root, home, counter: { steps: 0 }, hole: null, transcript: opts.transcript || (() => {}), forked: opts.forked };
    let value;
    try { value = runBody(tree.body, root, ctx); }
    catch (e) {
      if (e instanceof NonLocalReturn && e.home === home) value = e.value;
      else if (e instanceof NonLocalReturn) throw new STError('BlockCannotReturn');
      else if (e instanceof STError) throw e;
      else if (e instanceof RangeError) throw new STError('Stack overflow');
      else throw new STError(String(e.message || e));
    }
    return { value, printString: printString(value), className: className(value) };
  }

  function inspect(v) {
    const rows = [{ name: 'self', value: printString(v) }, { name: 'class', value: className(v) }];
    if (v instanceof Pt) rows.push({ name: 'x', value: printString(v.x) }, { name: 'y', value: printString(v.y) });
    else if (v instanceof Frac) rows.push({ name: 'numerator', value: v.n.toString() }, { name: 'denominator', value: v.d.toString() });
    else if (Array.isArray(v)) v.slice(0, 50).forEach((x, i) => rows.push({ name: String(i + 1), value: printString(x) }));
    else if (typeof v === 'string') [...v].slice(0, 50).forEach((c, i) => rows.push({ name: String(i + 1), value: '$' + c }));
    else if (typeof v === 'bigint') rows.push({ name: 'hex', value: '16r' + (v < 0n ? '-' + (-v).toString(16) : v.toString(16)).toUpperCase() }, { name: 'digits', value: String(v.toString().replace('-', '').length) });
    else if (v instanceof Block) rows.push({ name: 'numArgs', value: String(v.params.length) }, { name: 'outerContext', value: 'a Context' });
    return rows;
  }

  global.MiniST = { evaluate, printString, inspect, className, STError,
    // internals for the debugger's stepping interpreter
    _: { parse, evalNode, send, callBlock, truthy, Env, Block, Sym, Chr, Pt, Frac, ClassRef, NonLocalReturn, STError, workspaces, Transcript, printString, className } };
})(typeof window !== 'undefined' ? window : globalThis);
