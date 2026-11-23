"Shared timing harness. Fixtures supply literal-send loops; all argument/result adaptation stays in the facade."

Object subclass: #FFIPairedBench
	instanceVariableNames: ''
	classVariableNames: 'RunCount Warmup Schedule ProofArm'
	package: 'FFIPairedBench'!

!FFIPairedBench class methodsFor: 'running'!
count: count warmup: warmup schedule: schedule proofArm: arm
	RunCount := count.
	Warmup := warmup.
	Schedule := schedule.
	ProofArm := arm
!
case: label repeat: count direct: direct candidate: candidate reset: reset expect: check
	| n |
	n := count ifNil: [RunCount].
	ProofArm notNil ifTrue: [
		reset value.
		self check: check result: ((ProofArm = 0 ifTrue: [direct] ifFalse: [candidate]) value: n) case: label.
		^self].
	reset value.
	self check: check result: (direct value: Warmup) case: label.
	reset value.
	self check: check result: (candidate value: Warmup) case: label.
	1 to: Schedule size do: [:pair |
		| first |
		first := Schedule at: pair.
		reset value.
		self time: (first = 0 ifTrue: [direct] ifFalse: [candidate])
			count: n check: check case: label pair: pair arm: first.
		reset value.
		self time: (first = 0 ifTrue: [candidate] ifFalse: [direct])
			count: n check: check case: label pair: pair arm: 1 - first]
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
