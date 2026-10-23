TestCase subclass: #ProfilerDataTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-Profiler'!

ProfilerDataTest comment: 'I test the Profiler window''s model (ProfilerData, ProfilerNode, ProfilerFrameBar) on real samples of the running profiler.'!

!ProfilerDataTest methodsFor: 'tests'!
testFormat
	self assert: (ProfilerFormat count: 1872) equals: '1,872'.
	self assert: (ProfilerFormat percentString: 1 of: 4) equals: '25.0%'.
	self assert: (ProfilerFormat ms: 16667) equals: '16.7 ms'.
	self assert: (ProfilerFormat fit: 'abcdef' advance: 1 width: 10) equals: 'abcdef'.
	self assert: (ProfilerFormat fit: 'abcdefghijkl' advance: 1 width: 6) equals: 'abcde', ProfilerFormat ellipsis
! !
