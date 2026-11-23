!FFIPairedBench class methodsFor: 'integer comparison fixtures'!
bigIntegerMixed
	^self bigInteger: 'bigint-27-mixed' left: SmallInteger maxVal + 1 right: SmallInteger maxVal result: 1
!
bigIntegerSign
	| wide |
	wide := (1 bitShift: 255) + 127.
	^self bigInteger: 'bigint-27-sign' left: wide negated right: wide result: -1
!
bigInteger256b
	| wide |
	wide := (1 bitShift: 255) + 127.
	^self bigInteger: 'bigint-27-256b' left: wide right: wide + 1 result: -1
!
bigInteger8192b
	| huge |
	huge := (1 bitShift: 8191) + 254.
	^self bigInteger: 'bigint-27-8192b' left: huge right: huge + 1 result: -1
!
bigInteger: label left: a right: b result: expected
	self case: label repeat: nil
		run: [:n | | last | n timesRepeat: [last := a compareInteger: b]. last]
		reset: []
		expect: [:result | result == expected]
! !
