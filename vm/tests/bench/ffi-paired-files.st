!FFIPairedBench class methodsFor: 'file fixtures'!
file: path operation: operation label: label size: size position: offset
	| h direct candidate |
	h := File primOpen: path mode: 0.
	h isNil ifTrue: [self error: 'Could not open paired file fixture'].
	[
		operation == #position
			ifTrue: [
				direct := [:n | | value | n timesRepeat: [value := File primPosition: h]. value].
				candidate := [:n | | value | n timesRepeat: [value := File ffiCandidatePrimPosition: h]. value]]
			ifFalse: [
				direct := [:n | | value | n timesRepeat: [value := File primSize: h]. value].
				candidate := [:n | | value | n timesRepeat: [value := File ffiCandidatePrimSize: h]. value]].
		self case: label repeat: nil direct: direct candidate: candidate
			reset: [(File primSeek: h to: offset) isNil ifTrue: [self error: 'Could not seek fixture']]
			expect: [:value | value = (operation == #position ifTrue: [offset] ifFalse: [size])]
	] ensure: [File primClose: h]
! !
