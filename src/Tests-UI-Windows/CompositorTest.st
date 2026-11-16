UIWindowsTestCase subclass: #CompositorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

CompositorTest comment: 'Tests the compositor through screenshot readback: window layers over the halftone desk with the Blue Book frame, title stripes and hard shadows, z-order, FrameRecords, open/close/focus animations, overlays, toasts, the remote pointer, recording.'!

!CompositorTest methodsFor: 'tests'!
testLayersAreCompositedOverTheDesk
	| v w form b |
	v := RecordingTestView new color: Color ultramarine; yourself.
	w := self open: v title: 'Blue' at: (100 @ 100 extent: 300 @ 200).
	form := self screenshot.
	b := w bounds.
	self assertColor: Color ultramarine at: w contentOrigin + (50 @ 50) in: form.
	self assertColor: Color black at: b origin + (150 @ 0) in: form.
	self assertColor: Color black at: (b left + 1) @ (b top + 22) in: form.
	"hard 2-point shadow of the focused window"
	self assertColor: Color black at: (b right + 1) @ (b top + 100) in: form.
	self assertColor: Color black at: (b left + 100) @ (b bottom + 1) in: form.
	"top bar"
	self assertColor: Color white at: 500 @ 3 in: form.
	self assertColor: Color black at: 500 @ 26 in: form.
	"halftone desk: one black dot in every 2x2-point cell"
	self assert: ((#(0 1) inject: 0 into: [:sum :dx | sum + (#(0 1) count: [:dy | (self rgbAt: (50 + dx) @ (600 + dy) in: form) first < 60])]) = 1)
!
testFocusedTitleBarHasStripesAndTab
	| a b wa wb form stripes |
	a := RecordingTestView new.
	b := RecordingTestView new.
	wa := self open: a title: 'Unfocused' at: (100 @ 100 extent: 300 @ 200).
	wb := self open: b title: 'Focused' at: (100 @ 400 extent: 300 @ 200).
	form := world compositor sync: [:c | c screenshotScale: 2].
	"stripes: alternate black and white rows of one point (2 px) left of the tab"
	stripes := (5 to: 16) collect: [:y | (self rgbAt: (wb bounds left + 30) * 2 @ ((wb bounds top + 1 + y) * 2) in: form) first].
	self assert: (stripes count: [:g | g < 60]) >= 5.
	self assert: (stripes count: [:g | g > 200]) >= 5.
	"the unfocused title bar is plain white there"
	self assert: ((5 to: 16) allSatisfy: [:y | (self rgbAt: (wa bounds left + 30) * 2 @ ((wa bounds top + 1 + y) * 2) in: form) first > 200]).
	"the focused title tab is black"
	self assertColor: Color black at: (wb bounds center x) * 2 @ ((wb bounds top + 5) * 2) in: form
!
testZOrderFollowsRaise
	| a b wa wb p form |
	a := RecordingTestView new color: Color ultramarine; yourself.
	b := RecordingTestView new color: (Color r: 1 g: 0 b: 0); yourself.
	wa := self open: a title: 'A' at: (100 @ 100 extent: 300 @ 200).
	wb := self open: b title: 'B' at: (150 @ 150 extent: 300 @ 200).
	p := 300 @ 250.
	self assertColor: (Color r: 1 g: 0 b: 0) at: p in: self screenshot.
	world activate: wa.
	self settle.
	form := self screenshot.
	self assertColor: Color ultramarine at: p in: form
!
testFrameRecordsAreRecorded
	| v w before frames rec |
	before := Profiler default allFrames size.
	v := RecordingTestView new.
	w := self open: v title: 'Frames' at: (100 @ 100 extent: 300 @ 200).
	self click: w contentOrigin + (10 @ 10).
	w invalidate.
	self settle.
	frames := Profiler default allFrames.
	self assert: frames size > before.
	rec := frames last.
	self assert: rec end >= rec start.
	self assert: rec draw >= 0.
	self assert: rec raster >= 0.
	self assert: rec gcCount >= 0.
	self assert: (rec processes includes: world compositor process).
	self assert: (frames anySatisfy: [:f | f processes includes: w process]).
	self assert: world compositor frameCount > 0.
	"GPU time: measured from the frame's fence, filled in after the frame"
	self assert: world compositor gpuTimer measured > 0.
	self assert: (frames anySatisfy: [:f | f gpu > 0]).
	self assert: ((frames select: [:f | f gpu > 0]) allSatisfy: [:f | f gpu < 1000000]).
	self assert: (world topBar statsText includesSubstring: 'fps')
!
testTopBarStatsAfterTheClockStartsAgain
	"After a restart the microsecond clock starts again: the top bar forgets the frames before and its numbers go on (they were frozen until the new clock passed the old one)."
	| bar now |
	bar := TopBar world: world.
	now := 1000000000.
	1 to: 64 do: [:i | bar noteFrame: 2000 end: now + (i * 16667)].
	"twice: a first update may only notice the REMOTE and SLOW tags"
	bar updateAt: now + (64 * 16667); updateAt: now + (64 * 16667).
	self assert: (bar statsText beginsWith: '16.7 ms 60 fps').
	now := 1000000.
	1 to: 64 do: [:i | bar noteFrame: 2000 end: now + (i * 33334)].
	bar updateAt: now + (64 * 33334); updateAt: now + (64 * 33334).
	self assert: (bar statsText beginsWith: '33.3 ms 30 fps')
!
testOpenAndCloseAnimations
	| w layer |
	w := Window new title: 'Animated'; content: RecordingTestView new; bounds: (100 @ 100 extent: 300 @ 200); yourself.
	w openIn: world.
	layer := w layer.
	self assert: layer opacity < 1.
	self assert: layer scale < 1.
	self settle.
	self assert: layer opacity equals: 1.
	self assert: layer scale equals: 1.
	self deny: layer isAnimating.
	w close.
	self assert: (world closingWindows includes: w).
	self assert: layer isAnimating.
	self settle.
	self assert: world closingWindows isEmpty.
	self assert: layer opacity equals: 0.
	self assert: layer surface isNil
!
testFocusCrossFade
	| a b |
	a := self open: RecordingTestView new title: 'A' at: (100 @ 100 extent: 300 @ 200).
	b := self open: RecordingTestView new title: 'B' at: (500 @ 100 extent: 300 @ 200).
	self assert: b focusAmount equals: 1.
	self assert: a focusAmount equals: 0.
	world activate: a.
	self assert: a focusAmount < 1.
	self settle.
	self assert: a focusAmount equals: 1.
	self assert: b focusAmount equals: 0
!
testWindowAnimationRunsInWindowProcess
	| v w anim values processes |
	v := RecordingTestView new.
	w := self open: v title: 'Tween' at: (100 @ 100 extent: 300 @ 200).
	values := OrderedCollection new.
	processes := Set new.
	anim := Animation from: 0 to: 100 duration: 120 easing: #easeOutCubic do: [:x |
		values add: x.
		processes add: Processor activeProcess].
	anim whenDone: [values add: #done].
	w animate: anim.
	self settle.
	self assert: anim isFinished.
	self assert: values last equals: #done.
	self assert: (values at: values size - 1) equals: 100.
	self assert: values size >= 3.
	self assert: processes asArray equals: (Array with: w process)
!
testOverlayMenuFadesInAndCloses
	| menu overlay |
	self open: RecordingTestView new title: 'Under' at: (100 @ 100 extent: 300 @ 200).
	menu := RecordingTestView new color: Color ultramarine; yourself.
	menu bounds: (0 @ 0 extent: 150 @ 100).
	overlay := world openMenu: menu at: 600 @ 300.
	self assert: overlay layer opacity < 1.
	self settle.
	self assert: overlay layer opacity equals: 1.
	self assert: overlay layer offset equals: 0 @ 0.
	self assertColor: Color ultramarine at: 650 @ 350 in: self screenshot.
	self assert: menu isFocused.
	self key: #down modifiers: 0.
	self settle.
	self assert: ((menu eventsOfType: #down) anySatisfy: [:e | e isKey and: [e key == #down]]).
	world closeMenu: menu.
	self settle.
	self assert: world overlays isEmpty.
	self assert: overlay isClosed
!
testMenuIsClampedToTheScreen
	| menu overlay |
	menu := RecordingTestView new.
	menu bounds: (0 @ 0 extent: 200 @ 100).
	overlay := world openMenu: menu at: 950 @ 690.
	self assert: overlay bounds right <= world extent x.
	self assert: overlay bounds bottom <= world extent y.
	overlay close
!
testToastAppearsAndGoes
	| toast |
	toast := world toast: 'Hello toast' duration: 100.
	self assert: (world toasts includes: toast).
	self assert: (self waitFor: [toast isDone and: [(world toasts includes: toast) not]]) description: 'the toast did not go'.
	self settle.
	self assert: toast isDone.
	self deny: (world toasts includes: toast)
!
testRemotePointerIsWhereTheDispatcherSawIt
	"Remote input shows the pointer, drawn where the input dispatcher last saw it."
	| saved |
	saved := RemoteInputDevice default pointer.
	[RemoteInputDevice default pointer: 400 @ 300.
	 self moveTo: 400 @ 300.
	 self settle.
	 world waitForFrames: 3.
	 self assert: world remotePointer isVisible.
	 self assert: world remotePointer shown equals: 400 @ 300.
	 RemoteInputDevice default pointer: 450 @ 320.
	 self moveTo: 450 @ 320.
	 self settle.
	 world waitForFrames: 3.
	 self assert: world remotePointer shown equals: 450 @ 320]
		ensure: [RemoteInputDevice default pointer: saved]
!
testRecordWritesRawFrames
	| path recorder size |
	path := self scratchPath: 'record.rgba'.
	File deleteIfExists: path.
	recorder := FrameRecorder path: path width: 64 height: 40 fps: 30.
	world compositor startRecording: recorder.
	"Record for 250 ms of the recording clock: 8 frames at 30 fps, a frame more if the clock stops just past a slot."
	(Delay forMilliseconds: 250) wait.
	world compositor stopRecording.
	size := File sizeOf: path.
	self assert: (recorder framesWritten between: 8 and: 9).
	self assert: size equals: recorder framesWritten * 64 * 40 * 4.
	File delete: path
!
testRecordingWaitsForASlowReader
	"Frames go to the reader synchronously: one that takes its time delays the recording but loses none."
	| dir fifo out reader recorder |
	dir := self scratchPath: 'fifo'.
	OSProcess run: 'mkdir -p ', dir.
	fifo := dir, '/video'.
	out := dir, '/frames'.
	File deleteIfExists: fifo.
	File deleteIfExists: out.
	OSProcess run: 'mkfifo ', fifo.
	reader := (OSProcess command: 'sleep 0.5; dd if=', fifo, ' of=', out, ' bs=16384 2>/dev/null') start.
	recorder := FrameRecorder path: fifo width: 64 height: 40 fps: 30.
	world compositor startRecording: recorder.
	(Delay forMilliseconds: 300) wait.
	world compositor stopRecording.
	reader wait.
	self assert: (recorder framesWritten between: 9 and: 10).
	self assert: (File sizeOf: out) equals: recorder framesWritten * 64 * 40 * 4.
	OSProcess run: 'rm -rf ', dir
!
testRecordingStepsOneFramePerTick
	"Each tick of the recording clock is presented, whatever the display does; the video takes every second one at 30 fps."
	| recorder path n |
	path := self scratchPath: 'ticks.rgba'.
	File deleteIfExists: path.
	recorder := FrameRecorder path: path width: 16 height: 16 fps: 30.
	n := world compositor frameCount.
	world compositor startRecording: recorder.
	(Delay forMilliseconds: 1000) wait.
	world compositor stopRecording.
	self assert: (world compositor frameCount - n between: 59 and: 61).
	self assert: (recorder framesWritten between: 29 and: 30).
	File delete: path
!
testTheTickGridIsWholeMilliseconds
	| recorder |
	recorder := FrameRecorder path: 'unused' width: 16 height: 16 fps: 30.
	recorder startAt: 1000000.
	self assert: (recorder tickStart: 0) equals: 1000000.
	self assert: (recorder tickStart: 1) equals: 1017000.
	self assert: (recorder tickStart: 2) equals: 1034000.
	self assert: (recorder tickStart: 3) equals: 1050000.
	0 to: 600 do: [:k |
		self assert: (recorder tickAt: (recorder tickStart: k)) equals: k.
		self assert: (recorder tickAt: (recorder tickStart: k) + 900) equals: k]
!
testPresentsWithoutDisplayRefreshes
	"The display link stops while the display sleeps; macOS slows it to about 10 Hz while the VM runs in the background role. The compositor presents anyway."
	| n |
	self open: RecordingTestView new title: 'Ticks' at: (100 @ 100 extent: 300 @ 200).
	world compositor sync: [:c | DisplayWindow vsyncSemaphoreIndex: 0].
	n := world compositor frameCount.
	world waitForFrames: 10.
	self assert: world compositor frameCount - n >= 10
!
testTicksKeepTheirPaceWithoutDisplayRefreshes
	"Without refreshes the next tick comes tickTimeout (here 150 ms) after the previous one, not after the end of a long frame (here 60 ms: 210 between ticks then)."
	| c n t0 |
	self open: RecordingTestView new title: 'Pace' at: (100 @ 100 extent: 300 @ 200).
	c := world compositor.
	c sync: [:x | DisplayWindow vsyncSemaphoreIndex: 0. x tickTimeout: 150].
	n := c frameCount.
	t0 := Time millisecondClockValue.
	1 to: 6 do: [:i |
		c do: [:x | | t | t := Time millisecondClockValue. [Time millisecondClockValue - t < 60] whileTrue].
		self assert: (self waitFor: [c frameCount >= (n + i)]) description: 'no frame'].
	self assert: Time millisecondClockValue - t0 / 6 < 185
!
testHostResize
	DisplayWindow injectEvent: {UIEvent evWindowResized. nil. 1000. 700. 0. 0. nil. world displayWindow windowId}.
	self settle.
	self assert: world extent equals: world displayWindow extent
!
testVsyncWhileAnotherWorldRuns
	| b |
	self keepPresenting.
	(self vsyncDrives: world) ifFalse: [^self].
	b := World openHidden: 400 @ 300.
	[self assert: (self vsyncDrives: world)] ensure: [b stop]
!
testVsyncAfterAnotherWorldStopped
	self keepPresenting.
	(self vsyncDrives: world) ifFalse: [^self].
	(World openHidden: 400 @ 300) stop.
	self assert: (self vsyncDrives: world)
! !

!CompositorTest methodsFor: 'support'!
keepPresenting
	"A window animating every frame: my World never sleeps, so it never re-arms vsync on waking."
	(self open: RecordingTestView new title: 'Frames' at: (100 @ 100 extent: 300 @ 200)) requestAnimationFrames: [:ms | true].
	world compositor tickTimeout: 10000
!
vsyncDrives: aWorld
	"Ticking on its 10 s timeout, aWorld's compositor presents 5 frames within 2 s only on display refreshes. It has none while the display sleeps or an earlier World (a live image's) has them."
	| n |
	n := aWorld compositor frameCount.
	aWorld waitForFrames: 5.
	^aWorld compositor frameCount - n >= 5
! !
