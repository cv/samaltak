"Workloads Pharo 12 runs faster than Samaltak (docs/benchmarks.md): hash tables over weakly hashed keys, huge Integers printed, process switches and forks, becomeForward:, block and perform: calls that leave machine code. Each answers a checksum that must be the same on every system."!

Object subclass: #AdvCalls
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvPointDict
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvPackedKeys
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvFloatSet
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvArrayKeys
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvAlignedInts
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvHugePrint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvBigPrint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvPingPong
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

AdvPingPong subclass: #AdvDeepPingPong
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvYield
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvForkJoin
	instanceVariableNames: 'total'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvFork
	instanceVariableNames: 'total'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvBecome
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvValueWithArguments
	instanceVariableNames: 'total'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvBlocks
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvPerform3
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #AdvFractions
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!AdvCalls methodsFor: 'calling'!
a: x b: y c: z
	^x + y - z
!
b: x c: y a: z
	^x * y \\ 1000 + z
!
c: x a: y b: z
	^x - y + (z * 2)
! !

!AdvPointDict methodsFor: 'benchmarking'!
benchmark
	^self run: 70
!
verifyResult: result
	^result = 11679080
!
run: n
	"An n x n grid keyed by Points: every cell put, then every cell and its right neighbour looked up."
	| d sum |
	d := Dictionary new.
	0 to: n - 1 do: [:x | 0 to: n - 1 do: [:y | d at: x @ y put: x * y + 1]].
	sum := 0.
	0 to: n - 1 do: [:x | 0 to: n - 1 do: [:y |
		sum := sum + (d at: x @ y) + (d at: (x + 1) @ y ifAbsent: [0])]].
	^sum + d size
! !

!AdvPackedKeys methodsFor: 'benchmarking'!
benchmark
	^self run: 70
!
verifyResult: result
	^result = 352730
!
run: n
	"Coordinates of an n x n grid packed into one Integer, x * 65536 + y, as keys of a Dictionary and elements of a Set."
	| d s sum |
	d := Dictionary new.
	s := Set new.
	0 to: n - 1 do: [:x | 0 to: n - 1 do: [:y | d at: x * 65536 + y put: x + y. s add: x * 65536 + y]].
	sum := 0.
	0 to: n - 1 do: [:x | 0 to: n - 1 do: [:y |
		sum := sum + (d at: x * 65536 + y).
		(s includes: x * 65536 + y + 1) ifTrue: [sum := sum + 1]]].
	^sum + d size + s size
! !

!AdvFloatSet methodsFor: 'benchmarking'!
benchmark
	^self run: 15000
!
verifyResult: result
	^result = 17711
!
run: n
	"n random Floats in hundredths: asSet, a histogram Dictionary keyed by the Floats rounded to tenths, includes: misses."
	| seed xs set hist sum |
	seed := 777.
	xs := (1 to: n) collect: [:i | seed := seed * 16807 \\ 2147483647. (seed \\ 50000 + 1) / 100.0].
	set := xs asSet.
	hist := Dictionary new.
	xs do: [:x | | k | k := (x * 10) rounded / 10.0. hist at: k put: (hist at: k ifAbsent: [0]) + 1].
	sum := set size + hist size.
	xs do: [:x | (set includes: x + 0.005) ifTrue: [sum := sum + 1]].
	^sum
! !

!AdvArrayKeys methodsFor: 'benchmarking'!
benchmark
	^self run: 65
!
verifyResult: result
	^result = 8665410
!
run: n
	"An n x n grid keyed by two-element Arrays: every cell put, then every cell and its right neighbour looked up."
	| d sum |
	d := Dictionary new.
	0 to: n - 1 do: [:x | 0 to: n - 1 do: [:y | d at: (Array with: x with: y) put: x * y + 1]].
	sum := 0.
	0 to: n - 1 do: [:x | 0 to: n - 1 do: [:y |
		sum := sum + (d at: (Array with: x with: y)) + (d at: (Array with: x + 1 with: y) ifAbsent: [0])]].
	^sum + d size
! !

!AdvAlignedInts methodsFor: 'benchmarking'!
benchmark
	^self run: 9000
!
verifyResult: result
	^result = 40522499
!
run: n
	"n multiples of 4096 (offsets of 4 KB blocks) in a Set and as Dictionary keys."
	| s d sum |
	s := Set new.
	d := Dictionary new.
	1 to: n do: [:i | s add: i * 4096. d at: i * 4096 put: i].
	sum := 0.
	1 to: n do: [:i | sum := sum + (d at: i * 4096). (s includes: i * 4096 + 4096) ifTrue: [sum := sum + 1]].
	^sum + s size
! !

!AdvHugePrint methodsFor: 'benchmarking'!
benchmark
	^self run: 100000
!
verifyResult: result
	^result = 87339
!
run: e
	"3 raisedTo: e printed in decimal and in hex."
	| x s sum |
	x := 3 raisedTo: e.
	s := x printString.
	sum := s size + (s at: 1000) digitValue.
	s := x printStringBase: 16.
	^sum + s size
! !

!AdvBigPrint methodsFor: 'benchmarking'!
benchmark
	^self run: 3000
!
verifyResult: result
	^result = 200996
!
run: n
	"3 raisedTo: 20000 printed and read back four times; n 51-digit Integers printed."
	| sum x s |
	sum := 0.
	x := 3 raisedTo: 20000.
	1 to: 4 do: [:i |
		s := (x + i) printString.
		sum := sum + s size + (s at: 100) digitValue.
		(Number readFrom: s) = (x + i) ifTrue: [sum := sum + 1]].
	1 to: n do: [:i |
		s := ((7 raisedTo: 60) * i) printString.
		sum := sum + s size].
	^sum
! !

!AdvPingPong methodsFor: 'benchmarking'!
benchmark
	^self pingPong: 100000 depth: 0
!
verifyResult: result
	^result = 5000150000
!
pingPong: n depth: d
	"Two Processes hand control back and forth n times through two Semaphores, each waiting d calls deep."
	| ping pong done sum |
	ping := Semaphore new.
	pong := Semaphore new.
	done := Semaphore new.
	sum := 0.
	[self recurse: d then: [
		1 to: n do: [:i | ping wait. sum := sum + i. pong signal].
		0].
	 done signal] fork.
	self recurse: d then: [
		1 to: n do: [:i | ping signal. pong wait. sum := sum + 1].
		0].
	done wait.
	^sum
!
recurse: d then: aBlock
	^d = 0 ifTrue: [aBlock value] ifFalse: [(self recurse: d - 1 then: aBlock) + 1]
! !

!AdvDeepPingPong methodsFor: 'benchmarking'!
benchmark
	^self pingPong: 20000 depth: 50
!
verifyResult: result
	^result = 200030000
! !

!AdvYield methodsFor: 'benchmarking'!
benchmark
	^self run: 25000
!
verifyResult: result
	^result = 175000
!
run: n
	"Four Processes of one priority take turns with yield n times each, a little arithmetic in between."
	| done sums procs |
	done := Semaphore new.
	sums := Array new: 4 withAll: 0.
	procs := (1 to: 4) collect: [:k |
		[1 to: n do: [:i | sums at: k put: (sums at: k) + (i \\ (k + 2)). Processor yield].
		 done signal] newProcess].
	procs do: [:p | p resume].
	4 timesRepeat: [done wait].
	^sums inject: 0 into: [:a :b | a + b]
! !

!AdvForkJoin methodsFor: 'benchmarking'!
benchmark
	^self run: 3000
!
verifyResult: result
	^result = 8998
!
run: n
	"Fork a Process and wait for it, n times."
	| done |
	done := Semaphore new.
	total := 0.
	1 to: n do: [:i |
		(self job: i signal: done) fork.
		done wait].
	^total
!
job: i signal: done
	^[total := total + (i \\ 7). done signal]
! !

!AdvFork methodsFor: 'benchmarking'!
benchmark
	^self run: 3000
!
verifyResult: result
	^result = 162036
!
run: n
	"Fork n short-lived Processes at once; each adds to a total under a mutual-exclusion Semaphore and signals completion."
	| done mutex |
	done := Semaphore new.
	mutex := Semaphore forMutualExclusion.
	total := 0.
	1 to: n do: [:i | (self job: i mutex: mutex signal: done) fork].
	n timesRepeat: [done wait].
	^total
!
job: i mutex: mutex signal: done
	^[| s |
		s := 0.
		1 to: 20 do: [:j | s := s + (i * j \\ 7)].
		mutex critical: [total := total + s].
		done signal]
! !

!AdvBecome methodsFor: 'benchmarking'!
benchmark
	^self run: 50
!
verifyResult: result
	^result = 2550
!
run: n
	"n placeholders replaced by their real objects with becomeForward:, as a lazy loader does."
	| holders sum |
	holders := (1 to: n) collect: [:i | Array with: i].
	holders do: [:h | h becomeForward: (Array with: h first * 2)].
	sum := 0.
	holders do: [:h | sum := sum + h first].
	^sum
! !

!AdvValueWithArguments methodsFor: 'benchmarking'!
benchmark
	^self run: 1000000
!
verifyResult: result
	^result = 1000000
!
run: n
	"Two one-argument blocks called n times each through valueWithArguments:."
	| bs |
	bs := {[:a | total := total + a]. [:a | total := total - a + 1]}.
	total := 0.
	1 to: n do: [:i | bs do: [:b | self call: b with: i \\ 10]].
	^total
!
call: aBlock with: i
	^aBlock valueWithArguments: {i}
! !

!AdvBlocks methodsFor: 'benchmarking'!
benchmark
	^self run: 150000
!
verifyResult: result
	^result = 1050000
!
run: n
	"Blocks of 0 to 4 arguments kept in an Array and called through value..., valueWithArguments:, numArgs and cull:; they write a captured temp."
	| total handlers args |
	total := 0.
	handlers := {
		[total := total + 1].
		[:a | total := total + a].
		[:a :b | total := total + a - b].
		[:a :b :c | total := total + (a * b) - c].
		[:a :b :c :d | total := total + a + b - c - d]}.
	args := #(3 5 7 11).
	1 to: n do: [:i |
		handlers do: [:h |
			h numArgs = 0 ifTrue: [h value].
			h numArgs = 1 ifTrue: [h value: i \\ 10].
			h numArgs = 2 ifTrue: [h value: i \\ 10 value: 3].
			h numArgs = 3 ifTrue: [h value: 1 value: 2 value: i \\ 4].
			h numArgs = 4 ifTrue: [h value: 1 value: 2 value: 3 value: i \\ 4].
			h valueWithArguments: (args copyFrom: 1 to: h numArgs)].
		(handlers at: 2) cull: i \\ 3].
	^total
! !

!AdvPerform3 methodsFor: 'benchmarking'!
benchmark
	^self run: 300000
!
verifyResult: result
	^result = 305548740
!
run: n
	"Three 3-argument selectors sent n times each through perform:with:with:with: and perform:withArguments:."
	| r sum sels |
	r := AdvCalls new.
	sum := 0.
	sels := #(#a:b:c: #b:c:a: #c:a:b:).
	1 to: n do: [:i |
		sels do: [:s |
			sum := sum + (r perform: s with: i with: 2 with: 3).
			sum := sum + (r perform: s withArguments: {i. 5. 7})].
		sum := sum \\ 1000000007].
	^sum
! !

!AdvFractions methodsFor: 'benchmarking'!
benchmark
	^self run: 40
!
verifyResult: result
	^result = 42216355
!
run: n
	"Exact rational arithmetic, n rounds: a harmonic sum of 120 terms and a continued fraction 60 deep."
	| h c sum |
	sum := 0.
	1 to: n do: [:k |
		h := 0.
		1 to: 120 do: [:i | h := h + (1 / (i + k))].
		sum := sum + (h numerator \\ 1000003) + (h denominator \\ 1009).
		c := 1.
		60 timesRepeat: [c := 1 + (1 / (c + k))].
		sum := sum + (c numerator \\ 1000003) + (c > (3 / 2) ifTrue: [1] ifFalse: [0])].
	^sum
! !
