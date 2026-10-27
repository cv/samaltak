Arm64Module subclass: #JitSample
	instanceVariableNames: 'asm cache libc posix table addFn sumFn callbackFn fibFn hypotFn arrayFn signFn'
	classVariableNames: ''
	package: 'Tests-VM'!

JitSample comment: 'A small Lowtalk program for JitTest, compiled with cc: it assembles a few functions into the code cache and calls them. With the argument bench it measures how fast the assembler emits.'!

!JitSample class methodsFor: 'declaring'!
declarations
	^#((asm Arm64Assembler) (cache CodeCache) (libc LibC) (posix Posix) (table 'int64_t[8]') (addFn uint64_t) (sumFn uint64_t) (callbackFn uint64_t) (fibFn uint64_t) (hypotFn uint64_t) (arrayFn uint64_t) (signFn uint64_t))
! !

!JitSample methodsFor: 'running'!
main: argc argv: argv
	<c: 'int main(int argc, char **argv)'>
	(cache openWithSize: 1048576) ifFalse: [
		libc printf: 'no code cache
'.
		^1].
	asm recordNotes: true.
	self compile.
	self report: 'notes' value: asm noteCount.
	self report: 'note' value: (asm noteOffsetAt: 3) + (asm noteValueAt: 3).
	asm recordNotes: false.
	0 to: 7 do: [:i | table at: i put: i * i].
	self report: 'add' value: ((self cCoerce: addFn to: 'int64_t (*)(int64_t, int64_t)') call: 3 with: 4).
	self report: 'sum' value: ((self cCoerce: sumFn to: 'int64_t (*)(int64_t)') call: 100).
	self report: 'callback' value: ((self cCoerce: callbackFn to: 'int64_t (*)(int64_t, int64_t)') call: 5 with: 7).
	self report: 'fib' value: ((self cCoerce: fibFn to: 'int64_t (*)(int64_t)') call: 15).
	self report: 'hypot' value: ((self cCoerce: hypotFn to: 'double (*)(double, double)') call: 3.0 with: 4.0) truncated.
	self report: 'array' value: ((self cCoerce: arrayFn to: 'int64_t (*)(int64_t *, int64_t)') call: table with: 8).
	self report: 'sign' value: ((self cCoerce: signFn to: 'int64_t (*)(int64_t)') call: -5) + ((self cCoerce: signFn to: 'int64_t (*)(int64_t)') call: 0).
	cache flush.
	self report: 'flushed' value: (self cCoerce: cache top - cache start to: 'int64_t').
	(argc > 1 and: [(libc strcmp: (argv at: 1) with: 'bench') = 0]) ifTrue: [self bench].
	^0
!
report: label value: v
	<c: 'void report(const char *label, int64_t v)'>
	libc printf: '%s=%lld
' with: label with: v
!
callback: a with: b
	"Called from machine code."
	<c: 'int64_t callback(int64_t a, double b)'>
	^(a * 100) + b truncated
! !

!JitSample methodsFor: 'compiling'!
compile
	<c: 'void compile(void)'>
	| start loop done base |
	start := cache top.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	"x0 + x1"
	addFn := asm pc.
	asm bytecode: 0.
	asm comment: 'x0 + x1'.
	asm add: X0 with: X0 with: X1.
	asm ret.
	"1 + 2 + ... + x0"
	sumFn := asm pc.
	loop := asm newLabel.
	done := asm newLabel.
	asm bytecode: 1.
	asm comment: 'loop %d times' with: 100.
	asm mov: X1 with: X0.
	asm mov: X0 imm: 0.
	asm bind: loop.
	asm cbz: X1 to: done.
	asm add: X0 with: X0 with: X1.
	asm sub: X1 with: X1 imm: 1.
	asm b: loop.
	asm bind: done.
	asm ret.
	"callback(x0, (double)x1) + 1"
	callbackFn := asm pc.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm scvtf: D0 with: X1.
	asm mov: X16 imm64: (self cCoerce: (self functionPointer: #callback:with:) to: 'uint64_t').
	asm blr: X16.
	asm add: X0 with: X0 imm: 1.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret.
	"fib(x0), recursively"
	fibFn := asm pc.
	base := asm newLabel.
	asm cmp: X0 imm: 2.
	asm b: base if: COND_LT.
	asm stp: X29 with: X30 base: SP preIndex: -32.
	asm mov: X29 with: SP.
	asm stp: X19 with: X20 base: SP offset: 16.
	asm mov: X19 with: X0.
	asm sub: X0 with: X0 imm: 1.
	asm bl: (asm labelAt: fibFn).
	asm mov: X20 with: X0.
	asm sub: X0 with: X19 imm: 2.
	asm bl: (asm labelAt: fibFn).
	asm add: X0 with: X0 with: X20.
	asm ldp: X19 with: X20 base: SP offset: 16.
	asm ldp: X29 with: X30 base: SP postIndex: 32.
	asm bind: base.
	asm ret.
	"sqrt(d0 * d0 + d1 * d1)"
	hypotFn := asm pc.
	asm fmul: D0 with: D0 with: D0.
	asm fmul: D1 with: D1 with: D1.
	asm fadd: D0 with: D0 with: D1.
	asm fsqrt: D0 with: D0.
	asm ret.
	"the sum of the x1 int64s at x0"
	arrayFn := asm pc.
	loop := asm newLabel.
	done := asm newLabel.
	asm mov: X2 imm: 0.
	asm bind: loop.
	asm cbz: X1 to: done.
	asm ldr: X3 base: X0 postIndex: 8.
	asm add: X2 with: X2 with: X3.
	asm sub: X1 with: X1 imm: 1.
	asm b: loop.
	asm bind: done.
	asm mov: X0 with: X2.
	asm ret.
	"the sign of x0: -1, 0 or 1"
	signFn := asm pc.
	asm cmp: X0 imm: 0.
	asm cset: X1 cond: COND_GT.
	asm csetm: X2 cond: COND_LT.
	asm orr: X0 with: X1 with: X2.
	asm ret.
	asm finish = ASM_OK ifFalse: [
		libc printf: 'assembler error %d
' with: asm errorCode.
		libc exit: 1].
	cache allocate: asm codeSize.
	cache endWritingFrom: start size: asm codeSize
! !

!JitSample methodsFor: 'benchmarking'!
bench
	"Emit 8 instructions (add, ldr, str, cmp, b.cond, mov, mov imm, orr imm) 8192 times per pass into a buffer, for about a second."
	<c: 'void bench(void)'>
	| buffer passes t0 us |
	buffer := self cCoerce: (libc malloc: 262144) to: 'uint64_t'.
	passes := 0.
	t0 := self microseconds.
	[(us := self microseconds - t0) < 1000000] whileTrue: [
		0 to: 99 do: [:p |
			| skip |
			asm beginAt: buffer limit: buffer + 262144.
			0 to: 8191 do: [:i |
				skip := asm newLabel.
				asm add: X0 with: X1 imm: 12.
				asm ldr: X2 base: X3 offset: 16.
				asm str: X2 base: SP offset: 8.
				asm cmp: X0 with: X2.
				asm b: skip if: COND_NE.
				asm mov: X4 with: X5.
				asm mov: X6 imm: 4095.
				asm orr: X7 with: X8 imm: 16rFF00.
				asm bind: skip.
				(i bitAnd: 511) = 511 ifTrue: [asm beginAt: buffer limit: buffer + 262144]]].
		passes := passes + 100].
	libc printf: 'emit: %lld instructions in %lld us, %lld per second
' with: passes * 8192 * 8 with: us with: (passes * 8192 * 8 * 1000000 quo: us).
	libc free: (self cCoerce: buffer to: 'void *')
!
microseconds
	<c: 'int64_t microseconds(void)'>
	| ts |
	ts := self local: 'struct timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
! !
