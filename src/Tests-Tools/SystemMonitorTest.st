ToolsTestCase subclass: #SystemMonitorTest
	instanceVariableNames: 'crunch window monitor'
	classVariableNames: ''
	package: 'Tests-Tools'!

SystemMonitorTest comment: 'I run the System Monitor on real load: a factorial loop allocating as it goes runs in a Process named crunch. The monitor must open from the World menu''s registry, sample ten times a second, paint its charts, name crunch among the busiest Processes, account for all of the VM''s time, show values on hover, expose its widgets to remote control and use little CPU itself.'!

!SystemMonitorTest methodsFor: 'running'!
setUp
	super setUp.
	crunch := self fork: [[true] whileTrue: [300 factorial. Array new: 1000]] named: 'crunch' at: 30.
	window := self open: [SystemMonitor open].
	monitor := window content.
	self assert: (self waitFor: [monitor ticks >= 15] timeout: 5000) description: 'no samples'.
	self settle
!
tearDown
	window isNil ifFalse: [window close].
	super tearDown
! !

!SystemMonitorTest methodsFor: 'tests'!
testOpensOnceFromTheWorldMenu
	| labels |
	labels := ((ToolsMenu worldMenuAt: nil) items select: [:i | i isItem]) collect: [:i | i label].
	self assert: (labels includes: 'System Monitor').
	self assert: (Tools open: #monitor) == window.
	self assert: (self windowsOf: SystemMonitor) size equals: 1
!
testSamplesAndPaints
	| data s heap cpu |
	data := monitor data.
	self assert: data size >= 15.
	s := data last.
	self assert: s interval > 0.
	self assert: s oldUsed > 0.
	self assert: s oldBudget > 0.
	self assert: s edenSize > 0.
	self assert: (s edenFill between: 0 and: s edenSize).
	self assert: data last time > (data sampleAt: data firstSerial) time.
	heap := monitor heapChart.
	cpu := monitor cpuChart.
	monitor charts do: [:chart | self assert: chart form notNil].
	"The newest column of the heap chart shows old space (not paper) at the bottom."
	self deny: (self in: window do: [self bottomOf: heap]) = Theme current paper premultipliedRGBA8.
	self assert: (heap remoteState anySatisfy: [:w | w beginsWith: 'old=']).
	self assert: (cpu remoteState anySatisfy: [:w | w beginsWith: 'vm=']).
	self assert: (monitor heapReadout cellAt: 'old') notNil.
	self assert: (monitor cpuReadout cellAt: 'vm') notNil
!
testCrunchIsNamedAndTimeAddsUp
	| data |
	data := monitor data.
	self assert: (self waitFor: [data named includes: crunch] timeout: 3000) description: 'crunch is not named'.
	self assert: ((monitor cpuReadout cells collect: [:c | c at: 2]) includes: 'crunch').
	"Every sample accounts for its interval: the Processes, idle and what ended."
	data firstSerial + 1 to: data serial do: [:i | | s sum |
		s := data sampleAt: i.
		sum := s idle + s unaccounted.
		s processesDo: [:p :us | sum := sum + us].
		self assert: (sum - s interval) abs <= (s interval // 20 max: 500) description: 'sample ', i printString, ': ', sum printString, ' of ', s interval printString]
!
testHoverShowsTheValuesAtATime
	| heap cpu |
	heap := monitor heapChart.
	self moveTo: (heap remotePointAt: '5') rounded.
	self assert: (self waitFor: [monitor tipLines notNil]) description: 'no tip'.
	self assert: (monitor tipLines first includesSubstring: ' ago').
	self assert: (monitor tipLines anySatisfy: [:l | l beginsWith: 'old space ']).
	self assert: monitor hoverX notNil.
	cpu := monitor cpuChart.
	self moveTo: (cpu remotePointAt: '3') rounded.
	self assert: (self waitFor: [monitor tipLines notNil and: [monitor tipLines first includesSubstring: 'VM ']]) description: 'no CPU tip'.
	self assert: (monitor tipLines anySatisfy: [:l | l beginsWith: 'idle '])
!
testSpanToggle
	| toggle |
	toggle := monitor widgetNamed: 'span'.
	self click: (toggle screenPointFrom: (toggle segmentRects at: 2) center) rounded.
	self assert: (self waitFor: [monitor span = 300000000]) description: 'the click did not set the span'.
	self assert: monitor data span equals: 300000000.
	self settle.
	"Five minutes in the same width: each column covers five times as long."
	self assert: (monitor heapChart columnMicros * monitor heapChart form width) rounded equals: 300000000
!
testRetainedDrawing
	"The charts redraw at every sample, the rest only when its values change: every replay equals drawing anew, also while hovering."
	| mismatch |
	View verifyDrawing: true.
	[(Delay forMilliseconds: 700) wait.
	 self moveTo: (monitor heapChart remotePointAt: '5') rounded.
	 (Delay forMilliseconds: 700) wait.
	 self assert: View staleDrawings isEmpty description: View staleDrawings size printString, ' stale replays'.
	 mismatch := window retainedDrawingMismatchAfter: [monitor stop].
	 self assert: mismatch isNil description: mismatch printString]
		ensure: [View verifyDrawing: false]
!
testRemoteNames
	| text |
	text := (RemoteSnapshot root: world refTable: RemoteRefTable new) renderDepth: 6 bounds: false maxItems: 2000.
	#('.span' '.sampling ' '.heap-values.old ' '.heap-values.eden ' '.heap-chart ' '.alloc-chart ' '.cpu-values.vm ' '.cpu-chart ' '.status ') do: [:s |
		self assert: (text includesSubstring: s) description: 'snapshot lacks ', s]
!
testCarriesOnAfterARestart
	"A restarted image (a resumed snapshot, a rebuilt VM) has fresh VM counters and a millisecond clock that started again: the data takes a new baseline instead of a sample with negative counts, and the monitor keeps sampling."
	| data serial counters ticks |
	data := monitor data.
	serial := data serial.
	counters := data instVarNamed: 'lastCounters'.
	self in: window do: [
		data instVarNamed: 'lastCounters' put: (counters collect: [:c | c + 1000000000000]).
		self assert: data sample isNil].
	self assert: data serial equals: serial.
	self in: window do: [monitor instVarNamed: 'nextTick' put: Time millisecondClockValue + 100000000].
	ticks := monitor ticks.
	self assert: (self waitFor: [monitor ticks >= (ticks + 5)] timeout: 3000) description: 'no samples after the clock went back'.
	self assert: data last allocated >= 0.
	self assert: data last time > (data sampleAt: data serial - 1) time
!
testUsesLittleCPU
	"With crunch running, ten samples a second (each painting the charts' new columns) cost the monitor's Process little."
	| n0 c0 t0 cpu |
	(Delay forMilliseconds: 1000) wait.
	n0 := monitor ticks.
	c0 := window process cpuMicroseconds.
	t0 := Time microsecondClockValue.
	(Delay forMilliseconds: 3000) wait.
	cpu := (window process cpuMicroseconds - c0) * 100.0 / (Time microsecondClockValue - t0).
	self assert: monitor ticks - n0 >= 25 description: (monitor ticks - n0) printString, ' samples in 3 s'.
	self runsOnTheDefaultJit ifTrue: [
		self assert: cpu < 2.0 description: 'the System Monitor used ', (cpu printShowingDecimalPlaces: 2), '% CPU']
! !

!SystemMonitorTest methodsFor: 'support'!
bottomOf: aChart
	"The pixel at the bottom of the newest column painted (the monitor may have sampled since)."
	| f x |
	f := aChart form.
	x := (aChart instVarNamed: 'right') \\ f width.
	^f pixelValueAt: x @ (f height - 1)
! !
