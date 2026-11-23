!FFIPairedBench class methodsFor: 'scalar fixtures'!
fractionPart
	| inputs expected |
	inputs := #(-142.75 82.5 0.25 -0.125).
	expected := #(-0.75 0.5 0.25 -0.125).
	self case: 'float-fraction' repeat: nil
		run: [:n | | index result |
			index := 0.
			n timesRepeat: [index := (index bitAnd: 3) + 1. result := (inputs at: index) fractionPart].
			{index. result}]
		reset: []
		expect: [:value | value second = (expected at: value first)]
!
stream: stream size: size label: label
	| vm buffer loop |
	vm := Smalltalk vm.
	"Include non-ASCII conversion and a newline: stdout and stderr are redirected identically for both arms."
	buffer := (String new: size withAll: (Character value: 233)).
	buffer at: size put: Character lf.
	stream == #stdout
		ifTrue: [
			loop := [:n | | result | n timesRepeat: [result := vm stdoutWrite: buffer]. result]]
		ifFalse: [
			loop := [:n | | result | n timesRepeat: [result := vm stderrWrite: buffer]. result]].
	self case: label repeat: nil run: loop reset: [] expect: [:value | value == vm]
! !
