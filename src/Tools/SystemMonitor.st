ToolPane subclass: #SystemMonitor
	instanceVariableNames: 'data span spanToggle samplingLabel heapReadout heapChart allocChart cpuReadout cpuChart statusBar timer nextTick ticks hoverX hoverY hoverChart tipLines tipPoint'
	classVariableNames: ''
	package: 'Tools'!

SystemMonitor comment: 'I am the System Monitor: the heap and the CPU over the last minute (or five), sampled ten times a second in my window''s Process (SystemMonitorData). Heap: old space in use against its budget, eden''s fill, the bytes allocated per second and the GCs with their pauses. CPU: the share of the VM''s time each Process used (the busiest named, the rest grouped, idle), and the VM''s total. Current values above each chart; hover a chart for the values at a time.

The charts paint only the new columns of their bitmaps (SystemMonitorChart), so I use little CPU myself; my own Process is one of those shown.

	SystemMonitor open.
	Tools open: #monitor.'!

!SystemMonitor methodsFor: 'initialization'!
initialize
	super initialize.
	span := 60000000.
	ticks := 0.
	data := SystemMonitorData new.
	data span: span.
	self build
!
build
	| toolbar |
	spanToggle := ToggleGroup options: (Array with: 60000000 -> '1 min' with: 300000000 -> '5 min').
	spanToggle name: 'span'; selection: span; onChange: [:key | self setSpan: key].
	samplingLabel := Label new font: #smallItalic; color: #ink3; align: #right; name: 'sampling'; yourself.
	toolbar := Row with: {
		spanToggle sizeToContent.
		(Button label: 'GC' action: [Smalltalk vm garbageCollect]) name: 'gc'; sizeToContent.
		samplingLabel flex: 1; yourself.
		(Label text: '■ live' font: #uiBold) align: #right; fixed: 40; yourself}.
	toolbar spacing: 6; padding: (8 @ 5 corner: 8 @ 5); fixed: 30.
	heapReadout := SystemMonitorReadout new name: 'heap-values'; fixed: 46; yourself.
	heapChart := SystemMonitorHeapChart new monitor: self; name: 'heap-chart'; yourself.
	allocChart := SystemMonitorAllocChart new monitor: self; name: 'alloc-chart'; fixed: 64; yourself.
	cpuReadout := SystemMonitorReadout new name: 'cpu-values'; fixed: 46; yourself.
	cpuChart := SystemMonitorCPUChart new monitor: self; name: 'cpu-chart'; yourself.
	statusBar := StatusBar new name: 'status'; yourself.
	self addAll: {
		toolbar.
		ProfilerRule new.
		PaneHeader title: 'Heap' right: 'old space · eden · budget · allocation · GC'.
		heapReadout.
		heapChart flex: 3; yourself.
		allocChart.
		SystemMonitorAxis new monitor: self; fixed: 16; yourself.
		ProfilerRule new.
		PaneHeader title: 'CPU' right: 'share of the VM''s time, by Process'.
		cpuReadout.
		cpuChart flex: 2; yourself.
		SystemMonitorAxis new monitor: self; fixed: 16; yourself.
		statusBar}
!
minimumWindowExtent
	^520 @ 480
! !

!SystemMonitor methodsFor: 'accessing'!
data
	^data
!
span
	"The µs the charts show."
	^span
!
heapChart
	^heapChart
!
allocChart
	^allocChart
!
cpuChart
	^cpuChart
!
heapReadout
	^heapReadout
!
cpuReadout
	^cpuReadout
!
statusBar
	^statusBar
!
ticks
	"Answer how many samples I took."
	^ticks
!
hoverX
	^hoverX
!
tipLines
	^tipLines
!
charts
	^Array with: heapChart with: allocChart with: cpuChart
! !

!SystemMonitor methodsFor: 'sampling'!
start
	"Take the baseline and sample ten times a second (in my window's Process)."
	data start.
	self scheduleTick
!
scheduleTick
	"Keep the phase: a sample that came late delays the next one less. The millisecond clock starts again with the image (a restart): then the phase does too."
	| w now interval |
	w := self window.
	w isNil ifTrue: [^self].
	interval := SystemMonitorData interval.
	now := Time millisecondClockValue.
	nextTick := (nextTick isNil or: [(now - nextTick) abs > interval])
		ifTrue: [now + interval]
		ifFalse: [nextTick + interval].
	timer := w after: (nextTick - now max: 10) do: [self tick]
!
tick
	| w |
	w := self window.
	(w isNil or: [w isOpen not]) ifTrue: [^self].
	self sample.
	self scheduleTick
!
stop
	timer isNil ifFalse: [timer cancel. timer := nil]
!
windowClosed
	self stop
!
sample
	"Take a sample; the charts paint it when they draw next. The values and the named Processes change less often, so they can be read."
	data sample.
	ticks := ticks + 1.
	ticks \\ 10 = 1 ifTrue: [data updateNamed].
	(self window notNil and: [self window isCollapsed]) ifTrue: [^self].
	self charts do: [:each | each invalidate].
	ticks \\ 5 = 1 ifTrue: [self updateValues].
	hoverX isNil ifFalse: [self updateTip]
!
setSpan: microseconds
	span = microseconds ifTrue: [^self].
	span := microseconds.
	data span: span.
	data updateNamed.
	spanToggle selection: span.
	self updateValues.
	self invalidate
! !

!SystemMonitor methodsFor: 'values'!
averageOver: microseconds do: aBlock
	"aBlock value: aSample value: weight, over the last microseconds; answer the µs covered."
	| t total |
	data isEmpty ifTrue: [^0].
	t := data last time.
	total := 0.
	data from: t - microseconds to: t do: [:s :o | total := total + o. aBlock value: s value: o].
	^total
!
cpuShares
	"Over the last second: {VM. named shares by slot. other. idle} (percent)."
	| named shares other idle vm total |
	named := data named.
	shares := Array new: named size withAll: 0.
	other := 0.
	idle := 0.
	vm := 0.
	total := self averageOver: 1000000 do: [:s :o | | f |
		f := o asFloat / (s interval max: 1).
		s processesDo: [:p :us | | slot |
			slot := named indexOf: p.
			slot > 0 ifTrue: [shares at: slot put: (shares at: slot) + (us * f)] ifFalse: [other := other + (us * f)]].
		other := other + (s unaccounted * f).
		idle := idle + (s idle * f)].
	total = 0 ifTrue: [total := 1].
	^Array with: (shares inject: other into: [:a :b | a + b]) * 100.0 / total with: (shares collect: [:x | x * 100.0 / total]) with: other * 100.0 / total with: idle * 100.0 / total
!
updateValues
	| s |
	data isEmpty ifTrue: [^self].
	s := data last.
	heapReadout cells: (self heapCellsFor: s).
	cpuReadout cells: self cpuCells.
	samplingLabel text: 'every ', SystemMonitorData interval printString, ' ms', ProfilerFormat dot, (ProfilerFormat count: data size), ' samples'.
	statusBar text: 'this window samples in its own Process: ', (self class percent: self ownShare), ' CPU over the last 5 s', ProfilerFormat dot, 'hover a chart for its values'
!
heapCellsFor: s
	| alloc scavenges pause fulls lastFull covered |
	alloc := 0.
	scavenges := 0.
	pause := 0.
	covered := self averageOver: 5000000 do: [:x :o |
		alloc := alloc + (x allocationRate * o).
		x time > (s time - 5000000) ifTrue: [scavenges := scavenges + x scavenges. pause := pause + x gcMicros]].
	covered = 0 ifTrue: [covered := 1].
	fulls := 0.
	lastFull := nil.
	(data serialAtOrAfter: s time - span) to: data serial do: [:i | | x |
		x := data sampleAt: i.
		x fullGCs > 0 ifTrue: [fulls := fulls + x fullGCs. lastFull := x]].
	^Array
		with: (Array with: 'old' with: 'old space' with: (self class bytes: s oldUsed) with: (s oldUsed * 100 // (s oldBudget max: 1)) printString, '%' with: #l4)
		with: (Array with: 'budget' with: 'budget' with: (self class bytes: s oldBudget) with: '' with: #dashed)
		with: (Array with: 'eden' with: 'eden' with: '≈', (self class bytes: s edenFill) with: 'of ', (self class bytes: s edenSize) with: #l5)
		with: (Array with: 'alloc' with: 'allocating' with: (self class rate: alloc / covered) with: '' with: #ink4)
		with: (Array with: 'scavenges' with: 'scavenges' with: (ProfilerFormat oneDecimal: scavenges * 1000000.0 / covered), '/s' with: (self class percent: pause * 100.0 / covered), ' paused' with: #ink3)
		with: (Array with: 'full-gcs' with: 'full GCs' with: fulls printString
			with: (lastFull isNil
				ifTrue: ['in ', (self class age: span)]
				ifFalse: [(ProfilerFormat ms: lastFull fullGCMicros), ', ', (self class age: s time - lastFull time), ' ago'])
			with: #rule)
!
cpuCells
	| shares cells named |
	shares := self cpuShares.
	named := data named.
	cells := OrderedCollection new.
	cells add: (Array with: 'vm' with: 'VM total' with: (self class percent: shares first) with: (self class percent: (shares at: 4)), ' idle' with: #rule).
	named doWithIndex: [:p :i |
		p isNil ifFalse: [
			cells add: (Array with: 'process-', i printString with: (self class labelOf: p) with: (self class percent: ((shares at: 2) at: i)) with: '' with: (#(#l1 #l2 #l3 #l4) at: i))]].
	cells add: (Array with: 'other' with: 'other' with: (self class percent: (shares at: 3)) with: '' with: #ink4).
	^cells asArray
!
ownShare
	"My window's Process's CPU over the last 5 s (percent)."
	| me used total |
	me := Processor activeProcess.
	used := 0.
	total := self averageOver: 5000000 do: [:s :o | used := used + ((s timeFor: me) * o asFloat / (s interval max: 1))].
	^total = 0 ifTrue: [0] ifFalse: [used * 100.0 / total]
! !

!SystemMonitor methodsFor: 'hover'!
hover: aPointOrNil in: aChart
	aPointOrNil isNil
		ifTrue: [hoverX := nil. hoverChart := nil. tipLines := nil]
		ifFalse: [
			hoverX := aPointOrNil x.
			hoverY := aPointOrNil y.
			hoverChart := aChart].
	self updateTip
!
updateTip
	| t s |
	tipLines := nil.
	hoverChart isNil ifFalse: [
		t := hoverChart timeAtX: hoverX.
		s := t isNil ifTrue: [nil] ifFalse: [data sampleCovering: t].
		s isNil ifFalse: [
			tipLines := hoverChart tipLinesFor: s.
			tipPoint := hoverChart pointInWindow: hoverX @ hoverY]].
	self charts do: [:each | each invalidateOverlay].
	self invalidateOverlay
!
heapTipLinesFor: s
	| gc |
	gc := OrderedCollection new.
	s scavenges > 0 ifTrue: [gc add: (self class count: s scavenges of: 'scavenge'), ' ', (ProfilerFormat ms: s scavengeMicros)].
	s fullGCs > 0 ifTrue: [gc add: (self class count: s fullGCs of: 'full GC'), ' ', (ProfilerFormat ms: s fullGCMicros)].
	gc isEmpty ifTrue: [gc add: 'no GC'].
	^Array
		with: (self class age: data last time - s time), ' ago', ProfilerFormat dot, (self class bytes: s oldUsed + s edenFill), ' in use'
		with: 'old space ', (self class bytes: s oldUsed), ' of ', (self class bytes: s oldBudget), ' budget'
		with: 'eden ≈', (self class bytes: s edenFill), ' of ', (self class bytes: s edenSize)
		with: 'allocating ', (self class rate: s allocationRate)
		with: (gc inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ProfilerFormat dot, b]])
!
cpuTipLinesFor: s
	| pairs lines |
	pairs := OrderedCollection new.
	s processesDo: [:p :us | pairs add: p -> us].
	pairs := pairs asArray sort: [:a :b | a value > b value].
	lines := OrderedCollection new.
	lines add: (self class age: data last time - s time), ' ago', ProfilerFormat dot, 'VM ', (self class percent: s vmShare * 100).
	(pairs first: (pairs size min: 5)) do: [:each |
		lines add: (self class labelOf: each key), ' ', (self class percent: each value * 100.0 / (s interval max: 1))].
	pairs size > 5 ifTrue: [lines add: (pairs size - 5) printString, ' more'].
	lines add: 'idle ', (self class percent: s idle * 100.0 / (s interval max: 1)).
	^lines asArray
!
drawOverlayOn: aCanvas
	"The hover tip (as the Profiler's)."
	| bold italic w h x y r |
	tipLines isNil ifTrue: [^self].
	bold := self theme font: #code12Bold.
	italic := self theme font: #smallItalic.
	w := bold widthOf: tipLines first.
	tipLines allButFirst do: [:l | w := w max: (italic widthOf: l)].
	w := (w + 16) min: 420.
	h := 10 + 17 + (tipLines size - 1 * 16).
	x := tipPoint x + 14.
	y := tipPoint y + 16.
	x + w > (self width - 6) ifTrue: [x := tipPoint x - w - 10].
	y + h > (self height - 6) ifTrue: [y := tipPoint y - h - 10].
	r := x @ y extent: w @ h.
	aCanvas fillRect: (r translateBy: 2 @ 2) color: self theme ink.
	aCanvas fillRect: r color: self theme paper.
	aCanvas strokeRect: r color: self theme ink width: 1.
	aCanvas clip: (r insetBy: 1) during: [
		aCanvas drawString: tipLines first at: (x + 8) @ (y + 5) font: bold color: self theme ink.
		tipLines allButFirst doWithIndex: [:l :i |
			aCanvas drawString: l at: (x + 8) @ (y + 6 + 17 + (i - 1 * 16)) font: italic color: self theme ink]]
! !

!SystemMonitor class methodsFor: 'formatting'!
bytes: anInteger
	^self megabytes: anInteger / 1048576.0
!
megabytes: mb
	mb >= 1000 ifTrue: [^(ProfilerFormat oneDecimal: mb / 1024.0), ' GB'].
	mb >= 100 ifTrue: [^mb rounded printString, ' MB'].
	mb >= 1 ifTrue: [^(mb = mb rounded ifTrue: [mb rounded printString] ifFalse: [ProfilerFormat oneDecimal: mb]), ' MB'].
	^(mb * 1024) rounded printString, ' KB'
!
rate: bytesPerSecond
	^(self bytes: bytesPerSecond), '/s'
!
percent: aNumber
	^(ProfilerFormat oneDecimal: aNumber), '%'
!
age: microseconds
	"10.2 s, 2 min"
	microseconds >= 120000000 ifTrue: [^(microseconds / 60000000) rounded printString, ' min'].
	^ProfilerFormat seconds: microseconds
!
count: n of: aString
	^n printString, ' ', aString, (n = 1 ifTrue: [''] ifFalse: ['s'])
!
labelOf: aProcess
	^aProcess name ifNil: ['a Process']
! !

!SystemMonitor class methodsFor: 'opening'!
open
	"Open the System Monitor (or bring the open one to the front)."
	^self openAt: nil
!
openAt: aPointOrNil
	| existing |
	existing := Tools windowOf: self.
	existing isNil ifFalse: [existing focus. ^existing].
	^self openIn: (Tools placeAt: aPointOrNil extent: 800 @ 660)
!
openIn: aRectangle
	| monitor window |
	monitor := self new.
	window := monitor openIn: aRectangle title: 'System Monitor'.
	window do: [monitor start].
	^window
!
initialize
	ToolsMenu register: 'System Monitor' description: 'heap', ProfilerFormat dot, 'CPU' order: 45 action: [:point | self openAt: point].
	Tools registerOpener: #monitor with: [:arg | self open]
! !
