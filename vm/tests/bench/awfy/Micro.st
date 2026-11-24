"The micro suite (suite-samaltak.st) as AWFY benchmarks: one benchmark answers one run of the original."!

Benchmark subclass: #MicroFib
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroLoop
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroFloats
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroSends
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroBlocks
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroDict
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroStrings
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAlloc
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroFactorial
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!MicroFib methodsFor: 'benchmarking'!
benchmark
	^self fib: 30
!
fib: n
	^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]
!
verifyResult: result
	^result = 832040
! !

!MicroLoop methodsFor: 'benchmarking'!
benchmark
	| r |
	r := 0.
	1 to: 30000000 do: [:i | r := r + i].
	^r
!
verifyResult: result
	^result = 450000015000000
! !

!MicroFloats methodsFor: 'benchmarking'!
benchmark
	| r |
	r := 0.0.
	1 to: 3000000 do: [:i | r := r + (i * 1.5)].
	^r
!
verifyResult: result
	^result = 6750002250000.0
! !

!MicroSends methodsFor: 'benchmarking'!
benchmark
	| r |
	r := 0.
	1 to: 10000000 do: [:i | r := self id: r].
	^r
!
id: x
	^x + 1
!
verifyResult: result
	^result = 10000000
! !

!MicroBlocks methodsFor: 'benchmarking'!
benchmark
	| r b |
	r := 0.
	b := [:x | x + 1].
	1 to: 10000000 do: [:i | r := b value: r].
	^r
!
verifyResult: result
	^result = 10000000
! !

!MicroDict methodsFor: 'benchmarking'!
benchmark
	| d |
	d := Dictionary new.
	1 to: 300000 do: [:i | d at: i put: i].
	1 to: 300000 do: [:i | d at: i].
	^d size
!
verifyResult: result
	^result = 300000
! !

!MicroStrings methodsFor: 'benchmarking'!
benchmark
	| s |
	s := WriteStream on: String new.
	1 to: 300000 do: [:i | s nextPutAll: i printString].
	^s contents size
!
verifyResult: result
	^result = 1688895
! !

!MicroAlloc methodsFor: 'benchmarking'!
benchmark
	| a |
	1 to: 3000000 do: [:i | a := Array new: 4].
	^a
!
verifyResult: result
	^result size = 4
! !

!MicroFactorial methodsFor: 'benchmarking'!
benchmark
	| r |
	30 timesRepeat: [r := 1000 factorial].
	^r
!
verifyResult: result
	^result \\ 1000000007 = 641419708
! !

"Allocation, one kind each (not in the micro suite; awfy.sh MicroAllocObject ...): an object with fixed fields made
by new (basicNew and initialize inlined), bytes, an Array of a size known only at run time, a large Array (beyond
optimized code's inline sizes), closures that escape, Points."!

Object subclass: #MicroCell
	instanceVariableNames: 'a b c'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAllocObject
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAllocBytes
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAllocSized
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAllocLarge
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAllocClosure
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #MicroAllocPoint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!MicroCell methodsFor: 'initializing'!
initialize
	a := 0.
	b := 0
!
a
	^a
! !

!MicroAllocObject methodsFor: 'benchmarking'!
benchmark
	| o |
	1 to: 3000000 do: [:i | o := MicroCell new].
	^o
!
verifyResult: result
	^result a = 0
! !

!MicroAllocBytes methodsFor: 'benchmarking'!
benchmark
	| o |
	1 to: 3000000 do: [:i | o := ByteArray new: 24].
	^o
!
verifyResult: result
	^result size = 24
! !

!MicroAllocSized methodsFor: 'benchmarking'!
benchmark
	| o n |
	n := 0.
	1 to: 3000000 do: [:i | o := Array new: (i bitAnd: 15). n := n + o size].
	^n
!
verifyResult: result
	^result = 22500000
! !

!MicroAllocLarge methodsFor: 'benchmarking'!
benchmark
	| o |
	1 to: 3000 do: [:i | o := Array new: 6000].
	^o
!
verifyResult: result
	^result size = 6000
! !

!MicroAllocClosure methodsFor: 'benchmarking'!
benchmark
	| o |
	1 to: 3000000 do: [:i | o := self blockOn: i].
	^o
!
blockOn: i
	^[i]
!
verifyResult: result
	^result value = 3000000
! !

!MicroAllocPoint methodsFor: 'benchmarking'!
benchmark
	| p |
	1 to: 3000000 do: [:i | p := i @ i].
	^p
!
verifyResult: result
	^result x = 3000000
! !
