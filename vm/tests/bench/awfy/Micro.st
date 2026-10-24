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
