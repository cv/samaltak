!FFIPairedBench class methodsFor: 'file I/O fixtures'!
fileIO: operation width: width label: label
	"Each arm uses one live descriptor. Rewind every 256 transfers to avoid measuring only EOF."
	| h source target fixture direct candidate |
	h := File primOpen: 'file-ffi-io-payload' mode: 3.
	h isNil ifTrue: [self error: 'Could not open file I/O fixture'].
	source := ByteArray new: width + 2 withAll: 17.
	target := ByteArray new: width + 2 withAll: 33.
	[
		fixture := ByteArray new: width * 256 withAll: 17.
		(File primWrite: h from: fixture startingAt: 1 count: fixture size) = fixture size
			ifFalse: [self error: 'Could not seed file I/O fixture'].
		operation == #read
			ifTrue: [
				direct := [:n | | total |
					total := 0.
					1 to: n do: [:i |
						(i bitAnd: 255) = 1 ifTrue: [File primSeek: h to: 0].
						total := total + (File primRead: h into: target startingAt: 2 count: width)].
					total = (n * width) and: [target first = 33 and: [target second = 17 and: [target last = 33]]]].
				candidate := [:n | | total |
					total := 0.
					1 to: n do: [:i |
						(i bitAnd: 255) = 1 ifTrue: [File primSeek: h to: 0].
						total := total + (File ffiCandidatePrimRead: h into: target startingAt: 2 count: width)].
					total = (n * width) and: [target first = 33 and: [target second = 17 and: [target last = 33]]]]]
			ifFalse: [
				source at: 1 put: 99; at: width + 2 put: 99.
				direct := [:n | | total |
					total := 0.
					1 to: n do: [:i |
						(i bitAnd: 255) = 1 ifTrue: [File primSeek: h to: 0].
						total := total + (File primWrite: h from: source startingAt: 2 count: width)].
					total = (n * width)].
				candidate := [:n | | total |
					total := 0.
					1 to: n do: [:i |
						(i bitAnd: 255) = 1 ifTrue: [File primSeek: h to: 0].
						total := total + (File ffiCandidatePrimWrite: h from: source startingAt: 2 count: width)].
					total = (n * width)]].
		self case: label repeat: nil direct: direct candidate: candidate
			reset: [
				(File primSeek: h to: 0) isNil ifTrue: [self error: 'Could not seek file I/O fixture'].
				target at: 2 put: 33]
			expect: [:ok | ok]
	] ensure: [File primClose: h]
! !
