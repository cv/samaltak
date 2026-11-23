"Benchmark only: fixed fresh-tuple facade and last-tuple memoization comparator."!

!FFIBinding methodsFor: 'benchmark'!
tryInvoke: arguments
	^self tryPrimInvoke: id library: library symbol: symbol types: tags result: resultTag arguments: arguments
!
tryPrimInvoke: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag arguments: arguments
	<primitive: 'ffiInvoke'>
	^false
! !

!PlatformFFI class methodsFor: 'benchmark'!
benchBind: descriptor
	"Cold only: retain compatibility with images without the new private binder."
	(self respondsTo: #bind:) ifTrue: [^self bind: descriptor].
	^[FFI bind: descriptor] on: FFIError do: [:error | nil]
! !

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
		BenchFreshForeground := PlatformFFI benchBind: #(call 'platform' 'pty_foreground' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke: {h}].
	result == false ifTrue: [^self primForeground: h].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
benchFreshResize: h rows: r columns: c
	| binding result |
	binding := BenchFreshResize ifNil: [
		BenchFreshResize := PlatformFFI benchBind: #(call 'platform' 'pty_resize' (i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke: {h. r. c}].
	result == false ifTrue: [^self primResize: h rows: r columns: c].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
benchMemoForeground: h
	| binding result args hit |
	binding := BenchMemoForeground ifNil: [
		BenchMemoForeground := PlatformFFI benchBind: #(call 'platform' 'pty_foreground' (i64) i32)].
	binding isNil ifTrue: [^self primForeground: h].
	args := BenchForegroundTuple.
	hit := args notNil and: [(args at: 1) == h].
	hit ifFalse: [args := {h}].
	result := binding tryInvoke: args.
	result == false ifTrue: [^self primForeground: h].
	hit ifFalse: [BenchForegroundTuple := args].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
benchMemoResize: h rows: r columns: c
	| binding result args hit |
	binding := BenchMemoResize ifNil: [
		BenchMemoResize := PlatformFFI benchBind: #(call 'platform' 'pty_resize' (i64 i64 i64) i32)].
	binding isNil ifTrue: [^self primResize: h rows: r columns: c].
	args := BenchResizeTuple.
	hit := args notNil and: [
		(args at: 1) == h and: [(args at: 2) == r and: [(args at: 3) == c]]].
	hit ifFalse: [args := {h. r. c}].
	result := binding tryInvoke: args.
	result == false ifTrue: [^self primResize: h rows: r columns: c].
	hit ifFalse: [BenchResizeTuple := args].
	^result = 0 ifTrue: [nil] ifFalse: [self]
! !
