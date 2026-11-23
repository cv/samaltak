!FFIPairedBench class methodsFor: 'owned Integer benchmarks'!
bigIntegerAddSmallResult
	| a b |
	a := (1 bitShift: 95) + 127.
	b := (a - 4) negated.
	^self bigIntegerAdd: 'bigint-20-cancel' left: a right: b
!
bigIntegerAddMixed
	^self bigIntegerAdd: 'bigint-20-mixed' left: SmallInteger maxVal + 1 right: 5
!
bigIntegerAdd256b
	| a |
	a := (1 bitShift: 251) + 127.
	^self bigIntegerAdd: 'bigint-20-256b' left: a right: a + 1
!
bigIntegerAdd8192b
	| a |
	a := (1 bitShift: 8191) + 254.
	^self bigIntegerAdd: 'bigint-20-8192b' left: a right: a + 1
!
bigIntegerAdd: label left: a right: b
	| expected |
	expected := a + b.
	self case: label repeat: nil
		run: [:n | | last | n timesRepeat: [last := a + b]. last]
		reset: []
		expect: [:result | result = expected and: [result class == expected class]]
! !
