"Benchmark only: fixed fresh-tuple facade and last-tuple memoization comparator."!

PseudoTerminal addClassVarNamed: 'BenchFreshForeground'!
PseudoTerminal addClassVarNamed: 'BenchFreshResize'!
PseudoTerminal addClassVarNamed: 'BenchMemoForeground'!
PseudoTerminal addClassVarNamed: 'BenchMemoResize'!
PseudoTerminal addClassVarNamed: 'BenchForegroundTuple'!
PseudoTerminal addClassVarNamed: 'BenchResizeTuple'!

!PseudoTerminal class methodsFor: 'benchmark'!
benchFreshForeground: h
	| binding result |
	binding := BenchFreshForeground ifNil: [
		BenchFreshForeground := PTYBenchBinding tryBind: #(call 'platform' 'pty_foreground' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke: {h}].
	result == false ifTrue: [^self legacyForeground: h].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
benchFreshResize: h rows: r columns: c
	| binding result |
	binding := BenchFreshResize ifNil: [
		BenchFreshResize := PTYBenchBinding tryBind: #(call 'platform' 'pty_resize' (i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke: {h. r. c}].
	result == false ifTrue: [^self legacyResize: h rows: r columns: c].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
benchMemoForeground: h
	| binding result args hit |
	binding := BenchMemoForeground ifNil: [
		BenchMemoForeground := PTYBenchBinding tryBind: #(call 'platform' 'pty_foreground' (i64) i32)].
	binding isNil ifTrue: [^self legacyForeground: h].
	args := BenchForegroundTuple.
	hit := args notNil and: [(args at: 1) == h].
	hit ifFalse: [args := {h}].
	result := binding tryInvoke: args.
	result == false ifTrue: [^self legacyForeground: h].
	hit ifFalse: [BenchForegroundTuple := args].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
benchMemoResize: h rows: r columns: c
	| binding result args hit |
	binding := BenchMemoResize ifNil: [
		BenchMemoResize := PTYBenchBinding tryBind: #(call 'platform' 'pty_resize' (i64 i64 i64) i32)].
	binding isNil ifTrue: [^self legacyResize: h rows: r columns: c].
	args := BenchResizeTuple.
	hit := args notNil and: [
		(args at: 1) == h and: [(args at: 2) == r and: [(args at: 3) == c]]].
	hit ifFalse: [args := {h. r. c}].
	result := binding tryInvoke: args.
	result == false ifTrue: [^self legacyResize: h rows: r columns: c].
	hit ifFalse: [BenchResizeTuple := args].
	^result = 0 ifTrue: [nil] ifFalse: [self]
! !
