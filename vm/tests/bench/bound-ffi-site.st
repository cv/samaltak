!PseudoTerminal class methodsFor: 'benchmark-only control'!
ablationLegacyForeground: h
	^self legacyForeground: h
!
ablationLegacyResize: h rows: r columns: c
	^self legacyResize: h rows: r columns: c
!
ablationBindings
	^{ForegroundCall. ResizeCall}
! !

Object subclass: #BoundFFISiteBench
	instanceVariableNames: 'pty handle pid boundForeground boundResize step other calls'
	classVariableNames: ''
	package: 'BoundFFISiteBench'!

!BoundFFISiteBench methodsFor: 'benchmark'!
run: schedule selectors: selectors
	| ready vm beforeSteady expectedCalls |
	vm := Smalltalk vm.
	self assert: (vm platformHandleCounts at: #ptys ifAbsent: [0]) = 0.
	pty := PseudoTerminal
		spawn: #('/bin/sh' '-c' 'stty -echo; printf X; while read line; do case "$line" in size) stty size;; quit) exit 0;; esac; done')
		environment: nil directory: nil rows: 24 columns: 80.
	[
		handle := pty instVarNamed: 'handle'.
		pid := pty pid.
		ready := ByteArray new: 1.
		self assert: (self read: ready) = 1.
		self assert: ready first = $X asciiValue.
		self preflight.
		step := FFI bind: #(call 'wrapped' 'wrapped_step' (i32) i32).
		other := FFI bind: #(call 'wrapped' 'wrapped_other' (i32) i32).
		calls := FFI bind: #(call 'wrapped' 'wrapped_calls' () u32).
		self assert: (step tryInvoke1: 1) == 0.
		self assert: (other tryInvoke1: 1) == 21.
		expectedCalls := calls invoke: #().
		schedule do: [:group |
			| phase round gid count |
			phase := group first.
			round := group second.
			gid := group third.
			count := group fourth.
			(beforeSteady isNil and: [phase = 'steady']) ifTrue: [
				beforeSteady := vm statistics optMethodsCompiled].
			group fifth do: [:id |
				| selector before start result elapsed bytes |
				selector := selectors at: id.
				before := vm statistics bytesAllocated.
				start := Time microsecondClockValue.
				result := self perform: selector with: count.
				elapsed := Time microsecondClockValue - start.
				bytes := vm statistics bytesAllocated - before.
				id <= 8
					ifTrue: [
						self assert: result == (id <= 4 ifTrue: [pid] ifFalse: [
							id = 6 ifTrue: [1] ifFalse: [PseudoTerminal]])]
					ifFalse: [
						| expected misses |
						expected := count * (1 - count) // 2.
						id = 10 ifTrue: [
							misses := count // 64.
							expected := expected + (64 * misses * (misses + 1)) + (19 * misses)].
						self assert: result = expected.
						expectedCalls := expectedCalls + count].
				vm stdoutWrite: 'ffi-site-bench,', phase, ',', round printString, ',', gid printString, ',',
					count printString, ',', selector asString, ',', elapsed printString, ',', bytes printString,
					(String with: Character lf)]].
		self assert: (calls invoke: #()) = expectedCalls.
		vm stdoutWrite: 'ffi-site-stats,', beforeSteady printString, ',', vm statistics optMethodsCompiled printString,
			(String with: Character lf).
		self requireSize: '24 80'.
		self assert: boundForeground == PseudoTerminal ablationBindings first.
		self assert: boundResize == PseudoTerminal ablationBindings second.
		pty nextPutAll: 'quit', (String with: Character lf).
		self assert: pty waitForExit = 0
	] ensure: [pty close].
	self assert: (vm platformHandleCounts at: #ptys ifAbsent: [0]) = 0.
	^true
!
preflight
	| cls fg resize bindings |
	cls := PseudoTerminal class.
	fg := cls compiledMethodAt: #legacyForeground:.
	resize := cls compiledMethodAt: #legacyResize:rows:columns:.
	self assert: fg primitiveName = 'ptyForeground'.
	self assert: resize primitiveName = 'ptyResize'.
	[
		Compiler compile: 'legacyForeground: h self error: ''foreground fell back''' in: cls.
		Compiler compile: 'legacyResize: h rows: r columns: c self error: ''resize fell back''' in: cls.
		self assert: (PseudoTerminal primForeground: handle) = pid.
		self assert: (PseudoTerminal primResize: handle rows: 25 columns: 81) == PseudoTerminal.
		self requireSize: '25 81'.
		self assert: (PseudoTerminal primResize: handle rows: 24 columns: 80) == PseudoTerminal.
		self requireSize: '24 80'
	] ensure: [
		cls addSelector: #legacyForeground: withMethod: fg.
		cls addSelector: #legacyResize:rows:columns: withMethod: resize].
	bindings := PseudoTerminal ablationBindings.
	boundForeground := bindings first.
	boundResize := bindings second.
	self assert: (self rawForeground: 1) = pid.
	self assert: (self directForeground: 1) = pid.
	self assert: (self controlForeground: 1) = pid.
	{
		[:r :c | boundResize tryInvoke3: handle with: r with: c].
		[:r :c | PseudoTerminal legacyResize: handle rows: r columns: c].
		[:r :c | PseudoTerminal ablationLegacyResize: handle rows: r columns: c]
	} doWithIndex: [:call :i |
		| expected |
		expected := i = 1 ifTrue: [1] ifFalse: [PseudoTerminal].
		self assert: (call value: 25 value: 81) == expected.
		self requireSize: '25 81'.
		self assert: (call value: 24 value: 80) == expected.
		self requireSize: '24 80']
!
read: buffer
	| count deadline |
	deadline := Time millisecondClockValue + 3000.
	[(count := pty readInto: buffer) notNil or: [Time millisecondClockValue >= deadline]]
		whileFalse: [pty semaphore waitTimeoutMSecs: 20].
	^count
!
requireSize: expected
	| output buffer count deadline |
	pty nextPutAll: 'size', (String with: Character lf).
	output := ''.
	buffer := ByteArray new: 64.
	deadline := Time millisecondClockValue + 3000.
	[(output includesSubstring: (String with: Character lf)) or: [Time millisecondClockValue >= deadline]]
		whileFalse: [
			count := self read: buffer.
			(count notNil and: [count > 0]) ifTrue: [output := output, (buffer first: count) asString]].
	self assert: output trimBoth = expected
!
assert: aBoolean
	aBoolean ifFalse: [self error: 'FFI site benchmark correctness check failed']
! !

!BoundFFISiteBench methodsFor: 'inner loops'!
directForeground: n
	| answer h |
	h := handle.
	n timesRepeat: [answer := PseudoTerminal legacyForeground: h].
	^answer
!
rawForeground: n
	| answer h binding |
	h := handle.
	binding := boundForeground.
	n timesRepeat: [answer := binding tryInvoke1: h].
	^answer
!
controlForeground: n
	| answer h |
	h := handle.
	n timesRepeat: [answer := PseudoTerminal ablationLegacyForeground: h].
	^answer
!
wrappedForeground: n
	| answer h |
	h := handle.
	n timesRepeat: [answer := PseudoTerminal primForeground: h].
	^answer
!
directResize: n
	| answer h |
	h := handle.
	n // 2 timesRepeat: [
		answer := PseudoTerminal legacyResize: h rows: 25 columns: 81.
		answer := PseudoTerminal legacyResize: h rows: 24 columns: 80].
	^answer
!
rawResize: n
	| answer h binding |
	h := handle.
	binding := boundResize.
	n // 2 timesRepeat: [
		answer := binding tryInvoke3: h with: 25 with: 81.
		answer := binding tryInvoke3: h with: 24 with: 80].
	^answer
!
controlResize: n
	| answer h |
	h := handle.
	n // 2 timesRepeat: [
		answer := PseudoTerminal ablationLegacyResize: h rows: 25 columns: 81.
		answer := PseudoTerminal ablationLegacyResize: h rows: 24 columns: 80].
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
matchedScalar: n
	^self scalar: n alternate: step
!
abruptScalar: n
	^self scalar: n alternate: other
!
scalar: n alternate: alternate
	"One shared send. Both treatments branch at the same i; only identity differs."
	| answer binding selected |
	answer := 0.
	binding := step.
	1 to: n do: [:i |
		selected := (i bitAnd: 63) = 0 ifTrue: [alternate] ifFalse: [binding].
		answer := answer + (selected tryInvoke1: i)].
	^answer
! !
