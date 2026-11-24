Object subclass: #WrappedFFIPriorBinding
	instanceVariableNames: 'id library symbol tags'
	classVariableNames: ''
	package: 'WrappedFFIBench'!

!WrappedFFIPriorBinding methodsFor: 'benchmark-only prior facade'!
initializeLibrary: aLibrary symbol: aSymbol tags: typeTags
	library := aLibrary.
	symbol := aSymbol.
	tags := typeTags.
	id := self bindLibrary: library symbol: symbol types: tags result: 1.
	id isNil ifTrue: [self error: 'prior binding unavailable']
!
bindLibrary: aLibrary symbol: aSymbol types: typeTags result: resultTag
	<primitive: 'ffiBind'>
	^nil
!
tryInvoke: args
	^self invokeID: id library: library symbol: symbol types: tags result: 1 arguments: args
!
invokeID: anID library: aLibrary symbol: aSymbol types: typeTags result: resultTag arguments: args
	<primitive: 'ffiInvoke'>
	^false
! !

Object subclass: #WrappedFFIBench
	instanceVariableNames: 'pty handle pid scalar priorForeground priorResize priorScalar'
	classVariableNames: ''
	package: 'WrappedFFIBench'!

!WrappedFFIBench class methodsFor: 'benchmark'!
run: iterations warmup: warmup rounds: rounds
	^self new run: iterations warmup: warmup rounds: rounds
! !

!WrappedFFIBench methodsFor: 'benchmark'!
run: iterations warmup: warmup rounds: rounds
	| ready seen vm count result |
	vm := Smalltalk vm.
	scalar := FFI bind: #(call 'wrapped' 'wrapped_step' (i32) i32).
	count := FFI bind: #(call 'wrapped' 'wrapped_calls' () u32).
	priorForeground := WrappedFFIPriorBinding new initializeLibrary: 'platform' symbol: 'pty_foreground' tags: #[3].
	priorResize := WrappedFFIPriorBinding new initializeLibrary: 'platform' symbol: 'pty_resize' tags: #[3 3 3].
	priorScalar := WrappedFFIPriorBinding new initializeLibrary: 'wrapped' symbol: 'wrapped_step' tags: #[1].
	self assert: (scalar tryInvoke1: 1) = 0.
	pty := PseudoTerminal spawn: #('/bin/sh' '-c' 'stty -echo; printf X; read line')
		environment: nil directory: nil rows: 24 columns: 80.
	[
		handle := pty instVarNamed: 'handle'.
		pid := pty pid.
		ready := ByteArray new: 1.
		seen := Time millisecondClockValue + 3000.
		[(pty readInto: ready) = 1 or: [Time millisecondClockValue > seen]]
			whileFalse: [pty semaphore waitTimeoutMSecs: 20].
		self assert: ready first = $X asciiValue.
		self requireWrappedPTY.
		seen := count tryInvoke0.
		result := self timed: #(directForeground: wrappedForeground: priorForeground:
			directResize: wrappedResize: priorResize: directScalar: arrayScalar: priorScalar:)
			iterations: iterations warmup: warmup rounds: rounds.
		self assert: count tryInvoke0 - seen = result.
		pty nextPutAll: (String with: Character lf).
		self assert: pty waitForExit = 0
	] ensure: [pty close].
	self assert: (vm platformHandleCounts at: #ptys ifAbsent: [0]) = 0.
	^true
!
requireWrappedPTY
	| class foreground resize |
	class := PseudoTerminal class.
	foreground := class compiledMethodAt: #legacyForeground:.
	resize := class compiledMethodAt: #legacyResize:rows:columns:.
	self assert: foreground primitiveName = 'ptyForeground'.
	self assert: resize primitiveName = 'ptyResize'.
	[
		Compiler compile: 'legacyForeground: h self error: ''foreground fell back''' in: class.
		Compiler compile: 'legacyResize: h rows: r columns: c self error: ''resize fell back''' in: class.
		self assert: (self wrappedForeground: 1) = pid.
		self assert: (self wrappedResize: 2) == PseudoTerminal.
		self assert: (self priorForeground: 1) = pid.
		self assert: (self priorResize: 2) == PseudoTerminal
	] ensure: [
		class addSelector: #legacyForeground: withMethod: foreground.
		class addSelector: #legacyResize:rows:columns: withMethod: resize]
!
timed: selectors iterations: iterations warmup: warmup rounds: rounds
	| vm nativeCalls roundCount |
	vm := Smalltalk vm.
	nativeCalls := 0.
	roundCount := 5 + rounds.
	1 to: roundCount do: [:round |
		| order count phase |
		count := round <= 4 ifTrue: [warmup // 4] ifFalse: [iterations].
		phase := round <= 4 ifTrue: ['warmup'] ifFalse: [round = 5 ifTrue: ['discard'] ifFalse: ['steady']].
		order := round odd ifTrue: [#(1 2 3 4 5 6 7 8 9)] ifFalse: [#(9 8 7 6 5 4 3 2 1)].
		order do: [:id |
			| selector before start result elapsed bytes |
			selector := selectors at: id.
			before := vm statistics bytesAllocated.
			start := Time microsecondClockValue.
			result := self perform: selector with: count.
			elapsed := Time microsecondClockValue - start.
			bytes := vm statistics bytesAllocated - before.
			id <= 3 ifTrue: [self assert: result = pid].
			(id between: 4 and: 6) ifTrue: [self assert: result == PseudoTerminal].
			id >= 7 ifTrue: [
				"Sum of 1-i for i=1..count."
				self assert: result = (count * (1 - count) // 2).
				nativeCalls := nativeCalls + count].
			vm stdoutWrite: 'wrapped-ffi,', phase, ',', round printString, ',', selector asString, ',',
				count printString, ',', elapsed printString, ',', bytes printString, (String with: Character lf)]].
	^nativeCalls
!
assert: aBoolean
	aBoolean ifFalse: [self error: 'wrapped FFI benchmark correctness check failed']
! !

!WrappedFFIBench methodsFor: 'inner loops'!
directForeground: n
	| answer h |
	h := handle.
	n timesRepeat: [answer := PseudoTerminal legacyForeground: h].
	^answer
!
wrappedForeground: n
	| answer h |
	h := handle.
	n timesRepeat: [answer := PseudoTerminal primForeground: h].
	^answer
!
priorForeground: n
	| answer h |
	h := handle.
	n timesRepeat: [answer := self priorForegroundHandle: h].
	^answer
!
priorForegroundHandle: h
	| result |
	result := priorForeground isNil ifTrue: [false] ifFalse: [priorForeground tryInvoke: {h}].
	result == false ifTrue: [^PseudoTerminal legacyForeground: h].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
directResize: n
	| answer h |
	h := handle.
	n // 2 timesRepeat: [
		answer := PseudoTerminal legacyResize: h rows: 25 columns: 81.
		answer := PseudoTerminal legacyResize: h rows: 24 columns: 80].
	^answer
!
wrappedResize: n
	| answer h |
	h := handle.
	n // 2 timesRepeat: [
		answer := PseudoTerminal primResize: h rows: 25 columns: 81.
		answer := PseudoTerminal primResize: h rows: 24 columns: 80].
	^answer
!
priorResize: n
	| answer h |
	h := handle.
	n // 2 timesRepeat: [
		answer := self priorResizeHandle: h rows: 25 columns: 81.
		answer := self priorResizeHandle: h rows: 24 columns: 80].
	^answer
!
priorResizeHandle: h rows: r columns: c
	| result |
	result := priorResize isNil ifTrue: [false] ifFalse: [priorResize tryInvoke: {h. r. c}].
	result == false ifTrue: [^PseudoTerminal legacyResize: h rows: r columns: c].
	^result = 0 ifTrue: [nil] ifFalse: [PseudoTerminal]
!
directScalar: n
	| answer binding |
	answer := 0.
	binding := scalar.
	1 to: n do: [:i | answer := answer + (binding tryInvoke1: i)].
	^answer
!
arrayScalar: n
	| answer binding |
	answer := 0.
	binding := scalar.
	1 to: n do: [:i | answer := answer + (binding invoke: {i})].
	^answer
!
priorScalar: n
	| answer binding |
	answer := 0.
	binding := priorScalar.
	1 to: n do: [:i | answer := answer + (binding tryInvoke: {i})].
	^answer
! !
