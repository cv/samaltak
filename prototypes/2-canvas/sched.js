// Simulated green-thread scheduler: one JS thread, Processes time-sliced in small chunks per frame.
(function (S) {
  'use strict';
  const procs = [];
  let nextPid = 2;
  const listeners = [];
  const emit = () => listeners.forEach(f => f());
  const FRAME_BUDGET = 7; // ms of "VM time" per frame shared by all busy Processes

  function spawn(o) {
    const p = {
      pid: nextPid++, name: o.name, priority: o.priority ?? 40, state: o.state || 'waiting',
      cardId: o.cardId || null, kind: o.kind || 'card', work: null, busy: false, slices: 0, cpu: 0, blipUntil: 0,
    };
    procs.push(p);
    emit();
    return p;
  }

  function isPrime(n) {
    if (n < 2) return false;
    if (n % 2 === 0) return n === 2;
    if (n % 3 === 0) return n === 3;
    for (let d = 5; d * d <= n; d += 6) if (n % d === 0 || n % (d + 2) === 0) return false;
    return true;
  }
  function smallestFactor(n) {
    if (n % 2 === 0) return 2;
    for (let d = 3; d * d <= n; d += 2) if (n % d === 0) return d;
    return Math.floor(Math.sqrt(n));
  }

  // `(1 to: N) count: [:i | i isPrime]`, resumable.
  function primeWork(N, src) {
    return {
      N, src, i: 1, count: 0,
      step(budget) {
        const end = performance.now() + budget;
        let i = this.i, c = this.count;
        while (i < N) {
          i++;
          if (isPrime(i)) c++;
          if ((i & 511) === 0 && performance.now() > end) break;
        }
        this.i = i; this.count = c;
        return i >= N;
      },
      stepOne() { if (this.i < N) { this.i++; if (isPrime(this.i)) this.count++; } },
      restart() { this.i = 1; this.count = 0; },
      get progress() { return this.i / N; },
      get result() { return this.count; },
      divisor() { return smallestFactor(this.i); },
    };
  }

  // Short-lived generic work: sleeps a little, then runs a thunk once.
  function thunkWork(fn, ms = 400) {
    return {
      t: 0, ms, done: false, value: null, N: 1, i: 0, count: 0, src: '',
      step(budget) { this.t += budget * 3; if (this.t >= this.ms && !this.done) { this.done = true; this.value = fn(); } return this.done; },
      stepOne() {}, restart() { this.t = 0; },
      get progress() { return Math.min(1, this.t / this.ms); },
      get result() { return this.value; },
      divisor() { return 1; },
    };
  }

  function start(p, work, onDone) {
    p.work = work; p.onDone = onDone; p.busy = true; p.state = 'running'; p.slices = 0; p.cpu = 0; p.t0 = performance.now();
    emit();
  }
  function suspend(p) { if (p && p.busy) { p.state = 'suspended'; emit(); } }
  function resume(p) { if (p && p.busy) { p.state = 'running'; emit(); } }
  function terminate(p) {
    if (!p) return;
    p.busy = false; p.state = 'terminated'; p.work = null;
    emit();
  }
  function remove(p) { const i = procs.indexOf(p); if (i >= 0) procs.splice(i, 1); emit(); }
  function blip(p) {
    if (!p || p.busy || p.state === 'terminated') return;
    p.state = 'running'; p.blipUntil = performance.now() + 160;
    emit();
  }

  function tick(now) {
    let changed = false;
    for (const p of procs) if (p.blipUntil && now > p.blipUntil && !p.busy) { p.blipUntil = 0; p.state = 'waiting'; changed = true; }
    const runnable = procs.filter(p => p.busy && p.state !== 'suspended').sort((a, b) => b.priority - a.priority);
    if (runnable.length) {
      const slice = FRAME_BUDGET / runnable.length;
      for (const p of runnable) {
        const t0 = performance.now();
        const done = p.work.step(slice);
        p.cpu += performance.now() - t0; p.slices++;
        if (done) {
          const work = p.work;
          p.busy = false; p.state = 'waiting'; p.work = null; changed = true;
          p.onDone && p.onDone(work, (performance.now() - p.t0) / 1000);
        }
      }
    }
    if (changed) emit();
    return runnable.length > 0;
  }

  (window.FakeImage ? FakeImage.processes : []).filter(p => !p.window).forEach(p =>
    spawn({ name: p.name, priority: p.priority, state: p.state, kind: 'system' }));

  S.sched = {
    procs, spawn, start, suspend, resume, terminate, remove, blip, tick, primeWork, thunkWork,
    onChange: f => listeners.push(f), emit,
    busyProcs: () => procs.filter(p => p.busy),
  };
})(window.Sam = window.Sam || {});
