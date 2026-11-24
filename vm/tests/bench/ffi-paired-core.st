!FFIPairedBench class methodsFor: 'core fixtures'!
coreUtcMicroseconds
	self case: 'core-utc-us' repeat: nil
		run: [:n | | value | n timesRepeat: [value := Time utcMicroseconds]. value]
		reset: []
		expect: [:value | value class == SmallInteger and: [value > 1700000000000000]]
!
coreThreadCpuMicroseconds
	| vm |
	vm := Smalltalk vm.
	self case: 'core-thread-cpu-us' repeat: nil
		run: [:n | | value | n timesRepeat: [value := vm threadCpuMicroseconds]. value]
		reset: []
		expect: [:value | value class == SmallInteger and: [value > 0]]
!
coreFloatPrintString
	| x |
	x := Float fromIEEEBits: 16r3FF0000000000001.
	self case: 'core-float-print-string' repeat: nil
		run: [:n | | value | n timesRepeat: [value := x primPrintString]. value]
		reset: []
		expect: [:value | value = '1.0000000000000002']
!
coreGetenv
	| vm name |
	vm := Smalltalk vm.
	name := 'SAMALTAK_PARITY_VALUE'.
	self case: 'core-getenv' repeat: nil
		run: [:n | | value | n timesRepeat: [value := vm getenv: name]. value]
		reset: []
		expect: [:value | value = 'parity value']
! !
