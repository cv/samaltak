!FFIPairedBench class methodsFor: 'window fixtures (display CI only)'!
withBenchmarkWindow: aBlock
	| window |
	window := GPUPrimitives openWindow: 128 height: 96 title: 'FFI window benchmark' flags: 3.
	^[aBlock value: window] ensure: [GPUPrimitives closeWindow: window]
!
windowSize
	self withBenchmarkWindow: [:w |
		self case: 'window-size' repeat: nil
			direct: [:n | | result | n timesRepeat: [result := GPUPrimitives windowSize: w]. result]
			candidate: [:n | | result | n timesRepeat: [result := GPUPrimitives ffiCandidateWindowSize: w]. result]
			reset: []
			expect: [:result | result = #(128 96)]]
!
windowPixelSize
	self withBenchmarkWindow: [:w |
		| expected |
		expected := GPUPrimitives windowPixelSize: w.
		(expected size = 2 and: [expected allSatisfy: [:x | x > 0]]) ifFalse: [self error: 'Expected live pixel extent'].
		self case: 'window-pixel-size' repeat: nil
			direct: [:n | | result | n timesRepeat: [result := GPUPrimitives windowPixelSize: w]. result]
			candidate: [:n | | result | n timesRepeat: [result := GPUPrimitives ffiCandidateWindowPixelSize: w]. result]
			reset: []
			expect: [:result | result = expected]]
!
windowTitle
	self withBenchmarkWindow: [:w |
		| titleA titleB |
		titleA := 'FFI café'.
		titleB := 'FFI λ'.
		self case: 'window-title' repeat: nil
			direct: [:n | | title result |
				title := titleA.
				n timesRepeat: [
					result := GPUPrimitives window: w title: title.
					title := title == titleA ifTrue: [titleB] ifFalse: [titleA]].
				result]
			candidate: [:n | | title result |
				title := titleA.
				n timesRepeat: [
					result := GPUPrimitives ffiCandidateWindow: w title: title.
					title := title == titleA ifTrue: [titleB] ifFalse: [titleA]].
				result]
			reset: [GPUPrimitives window: w title: titleB]
			expect: [:result | result == GPUPrimitives]]
!
windowSetSize
	self withBenchmarkWindow: [:w |
		self case: 'window-set-size' repeat: nil
			direct: [:n | | width result |
				width := 160.
				n timesRepeat: [
					result := GPUPrimitives window: w width: width height: 96.
					width := 288 - width].
				result]
			candidate: [:n | | width result |
				width := 160.
				n timesRepeat: [
					result := GPUPrimitives ffiCandidateWindow: w width: width height: 96.
					width := 288 - width].
				result]
			reset: [GPUPrimitives window: w width: 128 height: 96]
			expect: [:result | result == GPUPrimitives]]
! !
