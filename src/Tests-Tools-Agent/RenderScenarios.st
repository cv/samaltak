Object subclass: #RenderScenarios
	instanceVariableNames: 'world workspace browser agent provider results device'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

RenderScenarios comment: 'I measure what rendering costs in the nine interactions of docs/graphics-damage.md (idle with a blinking caret, typing 77 characters 60 ms apart into a Workspace, idle, scrolling a System Browser''s method list 8 wheel steps down and up, hovering 16 of its items, dragging the Workspace by its title bar four times, opening an Agent window, the Agent streaming 150 text deltas 30 ms apart, idle) on the GPU the World has (--gpu nv on either backend, --gpu software, SDL_GPU): a World on a hidden 1920x1080 window, the events injected as the platform''s, as UIWindowsTestCase does. tests/nv/frames.sh runs me on each device under a private Xvfb (docs/nv-gpu.md, Small frames).

Per scenario, a presented frame''s mean: render, the CPU the renderer took from the frame''s lists to a frame ready to present (StageTimes: layer.render without its layer.diff, composite.render, composite.blit and present.submit without the host''s upload and present, so the GPU''s wait included); the compositor Process''s CPU (everything: diffs, the host''s present); an NvComputeGPU''s kernel launches and its GPU span (each command buffer''s first launch to its last''s end, GPU clock). On libcuda each scenario is bracketed by marker launches for nsys (NvComputeGPU>>mark:, 1000 + its index blocks at its start, 2000 + at its end).

	RenderScenarios new run       "a String: a line per scenario"'!

!RenderScenarios methodsFor: 'running'!
run
	"Open the World and the windows, run the scenarios, close it all; answer the report."
	results := OrderedCollection new.
	RenderScenarioStages start.
	[world := World openHidden: 1920 @ 1080.
	device := (Smalltalk at: #GPUPlatform) device.
	(device respondsTo: #measureSpans) ifTrue: [device measureSpans].
	self openWindows.
	self scenarios doWithIndex: [:pair :i | self measure: pair first index: i during: pair last]]
		ensure: [
			StageTimes stop.
			agent isNil ifFalse: [[agent content conversation stop] on: Error do: [:e | e return: nil]].
			world isNil ifFalse: [world stop]].
	^self report
!
results
	"{name. frames presented. ticks. each presented frame's stages (name -> {count. µs. bytes}), and what came after the last. compositor CPU µs. launches. GPU span µs. ms. waits} a scenario."
	^results
!
scenarios
	^{
		{'idle-caret'. [self idle: 3000]}.
		{'typing'. [self typing]}.
		{'idle-after'. [self idle: 1000]}.
		{'scroll-list'. [self scrolling]}.
		{'hover'. [self hovering]}.
		{'drag-window'. [self dragging]}.
		{'agent-open'. [self openAgent]}.
		{'agent-stream'. [self streaming]}.
		{'idle-end'. [self idle: 2000]}}
! !

!RenderScenarios methodsFor: 'scenarios'!
openWindows
	browser := SystemBrowser openIn: (880 @ 80 extent: 980 @ 600) onClass: OrderedCollection selector: nil.
	self settle.
	workspace := Workspace openOn: 'Transcript show: 3 factorial printString.
"typing goes here" ' in: (60 @ 80 extent: 760 @ 520) focus: true.
	self settle.
	(Delay forMilliseconds: 500) wait.
	self settle
!
idle: milliseconds
	(Delay forMilliseconds: milliseconds) wait
!
typing
	| text |
	text := 'the quick brown fox jumps over the lazy dog, 3 + 4 printString; x := 42 factorial.'.
	1 to: 77 do: [:i |
		self inject: {7. nil. 0. 0. 0. 0. (text at: i) asString}.
		(Delay forMilliseconds: 60) wait]
!
methodListPoint: i
	"The i-th item of the browser's method list (its fourth pane, on the right)."
	^(browser bounds left + (browser bounds width * 7 // 8)) @ (browser bounds top + 52 + (i * 18))
!
scrolling
	| p |
	p := self methodListPoint: 6.
	self move: p.
	#(-1 1) do: [:dir |
		8 timesRepeat: [
			self inject: {4. nil. p x asFloat. p y asFloat. 0. 0. 0.0 @ dir asFloat}.
			(Delay forMilliseconds: 120) wait]]
!
hovering
	1 to: 16 do: [:i |
		self move: (self methodListPoint: i).
		(Delay forMilliseconds: 150) wait]
!
dragging
	| title |
	title := (workspace bounds left + 300) @ (workspace bounds top + 10).
	{400 @ 150. 0 @ 0. 300 @ 250. 0 @ 0} inject: 0 @ 0 into: [:from :to |
		self drag: title + from to: title + to.
		to]
!
drag: from to: to
	self move: from.
	self inject: {2. nil. from x asFloat. from y asFloat. 1. 0. 1}.
	1 to: 20 do: [:i | | p |
		p := from + (to - from * i / 20.0).
		self inject: {1. nil. p x asFloat. p y asFloat. 1. 0. nil}.
		(Delay forMilliseconds: 16) wait].
	self inject: {3. nil. to x asFloat. to y asFloat. 1. 0. 1}.
	self settle
!
openAgent
	AgentWindow account: AgentTestAccount new.
	provider := RenderScenariosProvider new.
	agent := AgentWindow openOn: (AgentConversation new provider: provider; yourself) origin: nil in: (100 @ 60 extent: 720 @ 700).
	self settle.
	(Delay forMilliseconds: 1500) wait
!
streaming
	| deltas conversation deadline |
	deltas := (1 to: 150) collect: [:i | i \\ 12 = 0 ifTrue: ['word ', i printString, '.
'] ifFalse: ['word ', i printString, ' ']].
	provider reply: deltas items: {ScriptedProvider message: (deltas inject: '' into: [:a :b | a, b])}.
	conversation := agent content conversation.
	conversation ask: 'Stream me some words'.
	deadline := Time millisecondClockValue + 20000.
	[(Delay forMilliseconds: 50) wait.
	conversation isBusy and: [Time millisecondClockValue < deadline]] whileTrue
! !

!RenderScenarios methodsFor: 'measuring'!
measure: aName index: i during: aBlock
	| c n0 ticks0 cpu0 l0 w0 g0 t0 stages |
	self settle.
	world compositor renderer device waitIdle.
	StageTimes current takeFrame; takeSamples.
	c := world compositor.
	n0 := c presentedCount.
	ticks0 := c frameCount.
	cpu0 := c process cpuMicroseconds.
	l0 := self launches.
	w0 := self waits.
	g0 := self gpuSpan.
	(device respondsTo: #mark:) ifTrue: [device mark: 1000 + i].
	t0 := Time millisecondClockValue.
	aBlock value.
	self settle.
	(device respondsTo: #mark:) ifTrue: [device mark: 2000 + i].
	stages := StageTimes current takeFrame.
	results add: {aName. c presentedCount - n0. c frameCount - ticks0. StageTimes current takeSamples, {stages}. c process cpuMicroseconds - cpu0.
		self launches - l0. self gpuSpan - g0. Time millisecondClockValue - t0. self waits - w0}
!
launches
	^(device respondsTo: #launchCount) ifTrue: [device launchCount] ifFalse: [0]
!
waits
	^(device respondsTo: #waitCount) ifTrue: [device waitCount] ifFalse: [0]
!
gpuSpan
	(device respondsTo: #gpuSpanMicroseconds) ifFalse: [^0].
	(Delay forMilliseconds: 20) wait.
	^device gpuSpanMicroseconds
!
settle
	world waitUntilSettled: 5000
!
inject: anArray
	"A platform event (UIEvent's codes: 1 move, 2 down, 3 up, 4 wheel, 7 text) for my World's window."
	(Smalltalk at: #DisplayWindow) injectEvent: anArray, {world displayWindow windowId}
!
move: aPoint
	self inject: {1. nil. aPoint x asFloat. aPoint y asFloat. 0. 0. nil}
! !

!RenderScenarios methodsFor: 'report'!
us: aName in: stages
	^(stages at: aName ifAbsent: [#(0 0 0)]) at: 2
!
renderOf: stages
	"The renderer's CPU µs: what the device does with the frame's lists until the frame can be presented."
	^(self us: #'layer.render' in: stages) - (self us: #'layer.diff' in: stages)
		+ (self us: #'composite.render' in: stages) + (self us: #'composite.blit' in: stages)
		+ (self us: #'present.submit' in: stages)
		- (self us: #'host.upload' in: stages) - (self us: #'host.blit' in: stages) - (self us: #'host.surface' in: stages)
!
sum: frames
	"The stages of frames added up."
	| d |
	d := Dictionary new.
	frames do: [:f | f keysAndValuesDo: [:k :e | | t |
		t := d at: k ifAbsent: [d at: k put: (Array new: 3 withAll: 0)].
		1 to: 3 do: [:i | t at: i put: (t at: i) + (e at: i)]]].
	^d
!
percentile: p of: frames
	"The p-th percentile (0..1) of the presented frames' render µs."
	| v |
	frames size <= 1 ifTrue: [^0].
	v := (frames allButLast collect: [:f | self renderOf: f]) asSortedCollection asArray.
	^v at: ((v size - 1 * p) rounded + 1)
!
report
	| s per |
	s := WriteStream on: String new.
	s nextPutAll: 'device ', device class name.
	(device respondsTo: #backend) ifTrue: [s nextPutAll: ' (', device backend, ')'].
	s cr; nextPutAll: 'scenario frames/ticks render_median_us render_p90_us | per presented frame: render_us layer_us composite_us blit_us submit_us nv.wait_us compositor_cpu_us launches gpu_span_us waits'; cr.
	results do: [:r | | st n |
		st := self sum: (r at: 4).
		n := (r at: 2) max: 1.
		s nextPutAll: r first; space; print: (r at: 2); nextPut: $/; print: (r at: 3); space;
			print: (self percentile: 0.5 of: (r at: 4)); space; print: (self percentile: 0.9 of: (r at: 4)); nextPutAll: ' |'.
		per := [:x | (x / n) rounded printString].
		s space; nextPutAll: (per value: (self renderOf: st)); space;
			nextPutAll: (per value: (self us: #'layer.render' in: st) - (self us: #'layer.diff' in: st)); space;
			nextPutAll: (per value: (self us: #'composite.render' in: st)); space;
			nextPutAll: (per value: (self us: #'composite.blit' in: st)); space;
			nextPutAll: (per value: (self us: #'present.submit' in: st) - (self us: #'host.upload' in: st) - (self us: #'host.blit' in: st) - (self us: #'host.surface' in: st)); space;
			nextPutAll: (per value: (self us: #'nv.wait' in: st)); space;
			nextPutAll: (per value: (r at: 5)); space;
			nextPutAll: (per value: (r at: 6)); space;
			nextPutAll: (per value: (r at: 7)); space;
			nextPutAll: ((r at: 9) / n roundTo: 0.1) printString; cr].
	^s contents
! !

StageTimes subclass: #RenderScenarioStages
	instanceVariableNames: 'samples'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

RenderScenarioStages comment: 'StageTimes that also keep each presented frame''s stages apart (RenderScenarios): a frame ends with its present.submit.'!

!RenderScenarioStages methodsFor: 'counting'!
add: aSymbol since: startMicros bytes: anInteger
	| now |
	now := super add: aSymbol since: startMicros bytes: anInteger.
	aSymbol == #'present.submit' ifTrue: [| f |
		f := self takeFrame.
		lock critical: [(samples ifNil: [samples := OrderedCollection new]) add: f]].
	^now
!
takeSamples
	"The presented frames' stages since the last takeSamples, in order."
	| s |
	lock critical: [
		s := samples ifNil: [#()].
		samples := OrderedCollection new].
	^s asArray
! !

ScriptedProvider subclass: #RenderScenariosProvider
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

RenderScenariosProvider comment: 'A ScriptedProvider whose text deltas arrive 30 ms apart, as a model''s stream does (RenderScenarios).'!

!RenderScenariosProvider methodsFor: 'provider'!
send: inputItems tools: toolSpecArray onText: textBlock onItem: itemBlock
	^super send: inputItems tools: toolSpecArray
		onText: [:delta | (Delay forMilliseconds: 30) wait. textBlock value: delta]
		onItem: itemBlock
! !
