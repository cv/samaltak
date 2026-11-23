!FFIPairedBench class methodsFor: 'file fixtures'!
file: path operation: operation label: label size: size position: offset
	| h loop |
	h := File primOpen: path mode: 0.
	h isNil ifTrue: [self error: 'Could not open paired file fixture'].
	[
		operation == #position
			ifTrue: [
				loop := [:n | | value | n timesRepeat: [value := File primPosition: h]. value]]
			ifFalse: [
				loop := [:n | | value | n timesRepeat: [value := File primSize: h]. value]].
		self case: label repeat: nil run: loop
			reset: [(File primSeek: h to: offset) isNil ifTrue: [self error: 'Could not seek fixture']]
			expect: [:value | value = (operation == #position ifTrue: [offset] ifFalse: [size])]
	] ensure: [File primClose: h]
! !
