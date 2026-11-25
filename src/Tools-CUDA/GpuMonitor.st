ToolPane subclass: #GpuMonitor
	instanceVariableNames: 'deviceLabel readout busyHeader busyChart allocations calls recent status wasTracing ticks byAddress lastCalls lastCallsTime callRate integrated'
	classVariableNames: ''
	package: 'Tools-CUDA'!

GpuMonitor comment: 'I am the GPU Monitor (World menu › Apps › GPU): the CUDA device and what this VM does on it, sampled twice a second in my window''s Process. Above, the device''s memory (cudaMemGetInfo; on the GB10, whose GPU shares the system''s memory, "free" is the system''s), this VM''s device memory and handles (the binding''s tables in the VM), the device''s share of each second spent on traced work and the calls a second. Then that share over the last minute; the live allocations (the VM''s table: address and size, with the CudaArray holding each); the bindings'' calls by C function; and the recent operations (CudaTrace: what System-CUDA did, with its shapes, the device''s time measured by CUDA events and the host''s). While I am open, CudaTrace is on. My own calls are not counted.

	GpuMonitor open'!

!GpuMonitor methodsFor: 'initialization'!
initialize
	super initialize.
	ticks := 0.
	byAddress := Dictionary new.
	callRate := 0.
	self build
!
build
	| toolbar |
	deviceLabel := Label new font: #uiBold; name: 'device'; yourself.
	deviceLabel text: GpuTools summary.
	toolbar := Row with: {
		deviceLabel flex: 1; yourself.
		(Button label: 'Clear' action: [self clear]) name: 'clear'; sizeToContent.
		(Button label: 'GC' action: [self collectGarbage]) name: 'gc'; sizeToContent}.
	toolbar spacing: 6; padding: (8 @ 5 corner: 8 @ 5); fixed: 30.
	readout := SystemMonitorReadout new name: 'values'; fixed: 46; yourself.
	busyChart := Sparkline new name: 'busy-chart'; maxValue: 100; color: #ultramarine; yourself.
	allocations := TableView new name: 'allocations'; title: 'Allocations'; yourself.
	allocations
		addColumn: (TableColumn title: 'Address' width: 120 text: [:a | '16r' , (a key printString: 16)]);
		addColumn: ((TableColumn title: 'Size' width: 64 text: [:a | SystemMonitor bytes: a value]) align: #right; yourself);
		addColumn: (TableColumn title: 'Held by' flex: 1 text: [:a | self holderOf: a]).
	allocations emptyText: 'no device memory allocated by this VM'.
	calls := TableView new name: 'calls'; title: 'Calls'; yourself.
	calls
		addColumn: (TableColumn title: 'Function' flex: 1 text: [:c | c first]);
		addColumn: ((TableColumn title: 'Calls' width: 64 text: [:c | (c at: 2) asStringWithCommas]) align: #right; yourself);
		addColumn: ((TableColumn title: 'Last' width: 64 text: [:c | self agoMilliseconds: (c at: 3)]) align: #right; yourself).
	calls emptyText: 'no calls since the monitor opened'.
	recent := TableView new name: 'recent'; title: 'Recent operations'; yourself.
	recent
		addColumn: ((TableColumn title: 'Ago' width: 56 text: [:e | self agoMicroseconds: e startMicros]) align: #right; yourself);
		addColumn: (TableColumn title: 'Operation' width: 190 text: [:e | e name]);
		addColumn: (TableColumn title: 'Detail' flex: 1 text: [:e | e detail]);
		addColumn: ((TableColumn title: 'Device' width: 76 text: [:e | e deviceMilliseconds isNil ifTrue: [e isPending ifTrue: ['…'] ifFalse: ['']] ifFalse: [CudaComparison milliseconds: e deviceMilliseconds]]) align: #right; yourself);
		addColumn: ((TableColumn title: 'Host' width: 76 text: [:e | CudaComparison milliseconds: e hostMicros / 1000.0]) align: #right; yourself).
	recent emptyText: 'nothing yet: run a snippet of the GPU Workspace'.
	status := StatusBar new name: 'status'; yourself.
	self addAll: {
		toolbar.
		ProfilerRule new.
		PaneHeader title: 'Device' right: (GpuTools libraries inject: '' into: [:s :l | s isEmpty ifTrue: [l] ifFalse: [s , ProfilerFormat dot , l]]).
		readout.
		busyHeader := PaneHeader title: 'GPU time' right: 'the device''s share of each second spent on traced work, last minute'.
		(Row with: {busyChart flex: 1; yourself}) padding: (10 @ 4 corner: 10 @ 4); fixed: 56; yourself.
		((Row with: {
			(self pane: allocations title: 'Allocations' right: 'the VM''s table') flex: 1; yourself.
			(self pane: calls title: 'Calls' right: 'by C function') flex: 1; yourself}) separators: true; flex: 1; yourself).
		(self pane: recent title: 'Recent operations' right: 'device time by CUDA events') flex: 1.3; yourself.
		status}
!
minimumWindowExtent
	^560 @ 480
! !

!GpuMonitor methodsFor: 'accessing'!
readout
	^readout
!
busyChart
	^busyChart
!
allocationList
	^allocations
!
callList
	^calls
!
recentList
	^recent
!
statusBar
	^status
!
ticks
	^ticks
! !

!GpuMonitor methodsFor: 'sampling'!
start
	"Trace while I am open; sample now and twice a second."
	wasTracing := CudaTrace isOn.
	GpuTools isAvailable ifFalse: [^self showUnavailable].
	CudaTrace start.
	integrated := [CudaTrace quietly: [(CudaRuntimeAPI cudaDeviceGetAttribute: (CudaRuntimeAPI constant: 'cudaDevAttrIntegrated') device: 0) = 1]]
		on: Error do: [:e | e return: false].
	self sample.
	self every: 500 do: [self sample]
!
windowClosed
	wasTracing == true ifFalse: [CudaTrace stop]
!
showUnavailable
	readout cells: {{'cuda'. 'CUDA'. 'not here'. GpuTools unavailableText. nil}}.
	status text: 'the GPU demos need an NVIDIA GPU with CUDA (docs/cuda.md)'
!
sample
	| info live handles trace count now |
	ticks := ticks + 1.
	CudaTrace quietly: [
		info := [Cuda memoryInfo] on: Error do: [:e | e return: nil].
		live := CudaLibraryAPI allocations.
		handles := CudaLibraryAPI liveHandles].
	byAddress := Dictionary new.
	CudaArray liveArrays do: [:a | byAddress at: a address put: a].
	trace := CudaTrace default.
	now := Time millisecondClockValue.
	count := trace callCount.
	(lastCalls notNil and: [now > lastCallsTime]) ifTrue: [callRate := (count - lastCalls) * 1000.0 / (now - lastCallsTime) max: 0].
	lastCalls := count.
	lastCallsTime := now.
	allocations items: (live asSortedCollection: [:a :b | a value > b value or: [a value = b value and: [a key <= b key]]]) asArray.
	calls items: trace callsByCount.
	recent items: (trace recent: 80).
	busyChart values: (trace busyPercentOver: 60).
	busyChart maxValue: ((busyChart values inject: 10 into: [:m :v | m max: v]) min: 100).
	busyHeader rightText: 'the device''s share of each second spent on traced work, last minute' , ProfilerFormat dot , 'scale ' , (ProfilerFormat oneDecimal: busyChart scaleMax) , '%'.
	readout cells: (self cellsFrom: info allocations: live handles: handles).
	status text: 'tracing for ' , (SystemMonitor age: (now - trace since) * 1000) , ProfilerFormat dot , trace callCount asStringWithCommas , ' calls' , ProfilerFormat dot , 'every 500 ms in this window''s Process, its own calls not counted'
!
cellsFrom: info allocations: live handles: handles
	| bytes busy |
	bytes := live inject: 0 into: [:s :a | s + a value].
	busy := (CudaTrace default busyPercentOver: 2) first.
	^{
		{'total'. 'device memory'. info isNil ifTrue: ['?'] ifFalse: [SystemMonitor bytes: info last]. ''. nil}.
		{'free'. 'free'. info isNil ifTrue: ['?'] ifFalse: [SystemMonitor bytes: info first]. integrated == true ifTrue: ['the system''s'] ifFalse: ['']. nil}.
		{'ours'. 'this VM'. SystemMonitor bytes: bytes. live size printString , (live size = 1 ifTrue: [' allocation'] ifFalse: [' allocations']). #l4}.
		{'handles'. 'handles'. handles printString. ''. nil}.
		{'busy'. 'GPU busy'. (ProfilerFormat oneDecimal: busy) , '%'. 'traced, last second'. #ultramarine}.
		{'calls'. 'calls'. callRate rounded asStringWithCommas , '/s'. ''. nil}}
!
holderOf: anAssociation
	"What holds an allocation: its CudaArray (described), or none (memory another part of the image allocated through the bindings, such as NvComputeGPU's buffers)."
	| a |
	a := byAddress at: anAssociation key ifAbsent: [nil].
	a isNil ifTrue: [^'(not a CudaArray)'].
	^a class name , ' ' , a describe
!
agoMicroseconds: micros
	^SystemMonitor age: (Time microsecondClockValue - micros max: 0)
!
agoMilliseconds: ms
	^SystemMonitor age: ((Time millisecondClockValue - ms) max: 0) * 1000
! !

!GpuMonitor methodsFor: 'actions'!
clear
	CudaTrace default clear.
	lastCalls := nil.
	GpuTools isAvailable ifTrue: [self sample]
!
collectGarbage
	"Collect, so unreferenced arrays free their device memory (CudaReleaser), then sample."
	Smalltalk vm garbageCollect.
	WeakRegistry default finalizeValues.
	GpuTools isAvailable ifTrue: [self sample]
! !

!GpuMonitor class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	| existing |
	existing := Tools windowOf: self.
	existing isNil ifFalse: [existing focus. ^existing].
	^self openIn: (Tools placeAt: aPointOrNil extent: 820 @ 680)
!
openIn: aRectangle
	| monitor window |
	monitor := self new.
	window := monitor openIn: aRectangle title: 'GPU Monitor'.
	window do: [monitor start].
	^window
!
initialize
	ToolsMenu register: 'GPU Monitor' description: 'memory · allocations · calls' group: #gpu order: 30 action: [:point | self openAt: point].
	Tools registerOpener: #gpuMonitor with: [:arg | self open]
! !
