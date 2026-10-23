# Benchmarks

Same suite in three systems, methods compiled normally in each (`vm/tests/bench/suite-*.st`), on an Apple M2 Max, best of five runs. Milliseconds, lower is better.

| benchmark | Samaltak | GNU Smalltalk 3.2.5 (interpreter) | Pharo 12 (Cog JIT) |
|---|---|---|---|
| `fib: 30` | 27 | 45 | 10 |
| loop 30M (`r := r + i`) | 159 | 172 | 64 |
| sends 10M (`self id: r`) | 123 | 167 | 22 |
| blocks 10M (`b value: r`) | 146 | 174 | 30 |
| floats 3M | 36 | 250 | 39 |
| Dictionary 300k (`at:put:`, `at:`) | 106 | 1735 | 227 |
| strings 300k (`printString` into a stream) | 162 | 229 | 63 |
| allocation 3M (`Array new: 4`) | 72 | 1017 | 24 |
| `1000 factorial` ×30 | 384 | 6 | 7 |

GNU Smalltalk and Pharo do large-integer arithmetic in C (GMP, LargeIntegersPlugin); Samaltak's is Smalltalk. Pharo compiles to native code, so it is a ceiling rather than a peer.

Run:

    vm/build/samaltak build/samaltak.image --headless --eval "$(cat vm/tests/bench/suite-samaltak.st)"
    gst vm/tests/bench/suite-gst.st
    Pharo --headless Pharo.image eval "$(cat vm/tests/bench/suite-pharo.st)"
