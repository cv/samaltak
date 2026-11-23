"Shared timing harness. Fixtures supply literal-send loops; all argument/result adaptation stays in the facade."

Object subclass: #FFIPairedBench
	instanceVariableNames: ''
	classVariableNames: 'RunCount Warmup Pair Arm'
	package: 'FFIPairedBench'!

!FFIPairedBench class methodsFor: 'running'!
count: count warmup: warmup pair: pair arm: arm
	RunCount := count.
	Warmup := warmup.
	Pair := pair.
	Arm := arm
!
case: label repeat: count run: loop reset: reset expect: check
	| n vm result |
	n := count ifNil: [RunCount].
	reset value.
	Pair isNil ifTrue: [
		vm := Smalltalk vm.
		vm stderrWrite: 'ffi-pair-begin', (String with: Character lf).
		result := loop value: n.
		vm stderrWrite: 'ffi-pair-end', (String with: Character lf).
		self check: check result: result case: label.
		^self].
	self check: check result: (loop value: Warmup) case: label.
	reset value.
	self time: loop count: n check: check case: label pair: Pair arm: Arm
!
check: check result: result case: label
	(check value: result) ifFalse: [self error: 'Wrong workload result: ', label]
!
time: loop count: n check: check case: label pair: pair arm: arm
	| vm before after start cpu cpuUs wallUs result |
	vm := Smalltalk vm.
	before := vm statistics.
	cpu := vm threadCpuMicroseconds.
	start := Time microsecondClockValue.
	result := loop value: n.
	wallUs := Time microsecondClockValue - start.
	cpuUs := vm threadCpuMicroseconds - cpu.
	after := vm statistics - before.
	self check: check result: result case: label.
	self emit: {label. pair. arm. n. wallUs. cpuUs. after bytesAllocated.
		after scavenges. after fullGCs. after gcMicroseconds. after jitMethodsCompiled.
		after optMethodsCompiled. after optDeoptimizations}
!
emit: aRow
	Smalltalk vm stdoutWrite: (String streamContents: [:out |
		out nextPutAll: (String with: Character lf); nextPutAll: 'ffi-pair'.
		aRow do: [:field |
			out space; nextPutAll: (field isString ifTrue: [field] ifFalse: [field printString])].
		out nextPut: Character lf])
! !
