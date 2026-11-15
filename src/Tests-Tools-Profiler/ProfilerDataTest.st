TestCase subclass: #ProfilerDataTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-Profiler'!

ProfilerDataTest comment: 'I test the Profiler window''s model (ProfilerData, ProfilerNode, ProfilerFrameBar) on real samples of the running profiler.'!

!ProfilerDataTest methodsFor: 'tests'!
testFitKeepsClustersWhole
	"Labels cut with an ellipsis end between grapheme clusters (here family emoji of 7 characters) and fit."
	| family s f fitted |
	family := String withAll: (#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466) collect: [:cp | Character value: cp]).
	s := 'ab', family, family, family.
	f := Font ui.
	30 to: (f widthOf: s) by: 3 do: [:w |
		fitted := ProfilerFormat fit: s font: f width: w.
		self assert: (f widthOf: fitted) <= w.
		self assert: (s isGraphemeClusterBoundaryAt: fitted size - 1)].
	self assert: (ProfilerFormat fit: s font: f width: (f widthOf: 'ab', family, '…')) size equals: 10.
	2 to: 20 do: [:n |
		fitted := ProfilerFormat fit: s advance: 1 width: n.
		self assert: (s isGraphemeClusterBoundaryAt: fitted size - 1)]
!
testFormat
	self assert: (ProfilerFormat count: 1872) equals: '1,872'.
	self assert: (ProfilerFormat percentString: 1 of: 4) equals: '25.0%'.
	self assert: (ProfilerFormat ms: 16667) equals: '16.7 ms'.
	self assert: (ProfilerFormat fit: 'abcdef' advance: 1 width: 10) equals: 'abcdef'.
	self assert: (ProfilerFormat fit: 'abcdefghijkl' advance: 1 width: 6) equals: 'abcde', ProfilerFormat ellipsis
! !
