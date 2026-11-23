!FFIPairedBench class methodsFor: 'core fixtures'!
coreUtcMicroseconds
	self case: 'core-utc-us' repeat: nil
		direct: [:n | | value | n timesRepeat: [value := Time utcMicroseconds]. value]
		candidate: [:n | | value | n timesRepeat: [value := Time ffiCandidateUtcMicroseconds]. value]
		reset: []
		expect: [:value | value class == SmallInteger and: [value > 1700000000000000]]
!
coreThreadCpuMicroseconds
	| vm |
	vm := Smalltalk vm.
	self case: 'core-thread-cpu-us' repeat: nil
		direct: [:n | | value | n timesRepeat: [value := vm threadCpuMicroseconds]. value]
		candidate: [:n | | value | n timesRepeat: [value := vm ffiCandidateThreadCpuMicroseconds]. value]
		reset: []
		expect: [:value | value class == SmallInteger and: [value > 0]]
!
coreFloatPrintString
	| x |
	x := Float fromIEEEBits: 16r3FF0000000000001.
	self case: 'core-float-print-string' repeat: nil
		direct: [:n | | value | n timesRepeat: [value := x primPrintString]. value]
		candidate: [:n | | value | n timesRepeat: [value := x ffiCandidatePrimPrintString]. value]
		reset: []
		expect: [:value | value = '1.0000000000000002']
! !
