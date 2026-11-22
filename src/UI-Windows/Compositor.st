Object subclass: #Compositor
	instanceVariableNames: 'world displayWindow renderer process running vsync vsyncIndex wake sleeping skip tickTimeout lastTick idleFrames frameCount presenting requests recorder lastFrameWork onWorkClock ownsWorkClock gpuTimer clock knownProcesses lastCpu lastScan lastRecord lastError lastErrorTime pipelineVersion standIn tickCount compositeBytes restMs differ items previousList previousStamps previousItems fullNext presentedCount countsFrame lastDamage'
	classVariableNames: 'Probe Running'
	package: 'UI-Windows'!

Compositor comment: 'I am the compositor: a Process at priority 70 woken by the platform''s vsync semaphore, presenting at 60 Hz (every second refresh on a 120 Hz display). Each frame I step the layer animations (window open/close, focus cross-fades, menus), toasts and the remote pointer, post frame ticks to windows with animations, render every Layer whose DisplayList or chrome changed into its Surface, composite all layers (offset, scale about the center, opacity, hard shadows) over the halftone desk with the top bar and overlays onto the DisplayWindow, and record a FrameRecord (Profiler recordFrame:). I never wait for a window''s Process: a busy window keeps its last frame.

Composition is damage-limited (docs/graphics-damage.md): I keep the screen surface between frames and draw a frame only where it differs from the last one presented, the damage (a DamageRegion): the composite list is drawn item by item (the desk, each window, the top bar, overlays, toasts, tooltip, curtain, pointer), each compared with the same item of the last frame (DisplayListDiff: a window moved damages its old and new rectangle, the top bar its readout), plus what each layer rendered again changed inside its window (Layer>>lastDamage), plus the items whose order changed. A frame without damage is not presented at all; DisplayWindow>>show:clear:damage: renders and presents only the damage where the path allows. DamageCheck verifies it, and DamageCheck forcesFull turns it off.

I present when something changed (World>>changed, animations, requests), and with World presentsContinuously: true (measurements) every tick. The top bar''s readout refreshes at most twice a second and only rides along: a frame presented only because the readout changed is not counted in it, so it settles instead of measuring the frames it makes. On a device that renders in software (UEFI) I rest after each frame as long as the frame took, so that the other Processes keep at least half of the CPU: after 20 ticks without a change I stop the vsync semaphore and sleep until World>>changed wakes me (or 500 ms pass, for the top bar''s statistics). Each tick I also poll the GPUTimer for finished frames'' GPU times; while maxFramesInFlight frames are unfinished on the GPU I skip the tick (except when recording, which waits for each frame''s readback, and while a request waits: its caller is blocked until I ran it).

GPU work of other Processes (screenshots, recording) runs in my Process between frames: do: aBlock / sync: aBlock.'!

!Compositor methodsFor: 'initialization'!
setWorld: aWorld
	world := aWorld.
	displayWindow := aWorld displayWindow.
	running := false.
	onWorkClock := false.
	lastFrameWork := 0.
	sleeping := false.
	idleFrames := 0.
	frameCount := 0.
	tickCount := 0.
	presenting := false.
	presentedCount := 0.
	countsFrame := true.
	fullNext := true.
	requests := SharedQueue new.
	lastCpu := IdentityDictionary new.
	knownProcesses := #().
	lastScan := -1000000000.
	lastErrorTime := 0
! !

!Compositor methodsFor: 'accessing'!
world
	^world
!
process
	^process
!
frameCount
	"Frames composed: presented, or not needed because nothing on the screen changed (World>>waitForFrames:)."
	^frameCount
!
presentedCount
	"Frames presented (damaged)."
	^presentedCount
!
lastDamage
	"The damage of the last frame composed (a DamageRegion of device pixels; empty: it was not presented)."
	^lastDamage
!
redrawAll
	"Draw and present the whole screen at the next frame (my Process, or between frames)."
	fullNext := true
!
tickCount
	"How many ticks I took, presenting or not."
	^tickCount
!
clock
	"The animation clock at the current frame (ms, Float)."
	^clock ifNil: [Animation now]
!
tickClock
	"The animation clock at the current frame; nil before the first."
	^clock
!
isPresenting
	^presenting
!
recorder
	^recorder
!
renderer
	^renderer
!
gpuTimer
	^gpuTimer
!
tickTimeout: milliseconds
	"How long after the previous tick I tick without a display refresh."
	tickTimeout := milliseconds
! !

!Compositor methodsFor: 'starting and stopping'!
start
	| rate |
	running ifTrue: [^self].
	running := true.
	renderer := Renderer default.
	pipelineVersion := renderer pipelineVersion.
	vsync := Semaphore new.
	wake := Semaphore new.
	vsyncIndex := Smalltalk vm registerExternalSemaphore: vsync.
	onWorkClock := Smalltalk vm isOnWorkClock.
	Running := self class running copyWith: self.
	self armVsync.
	rate := [displayWindow refreshRate] on: Error do: [:e | e return: 60].
	skip := rate > 61 ifTrue: [(rate / 60) rounded] ifFalse: [1].
	tickTimeout := rate > 0 ifTrue: [(skip * 1500 / rate) rounded] ifFalse: [25].
	lastTick := Time millisecondClockValue.
	gpuTimer := GPUTimer new.
	process := [self run] newProcess.
	process priority: self class priority; name: 'compositor (vsync)'.
	process resume
!
stop
	running := false.
	recorder isNil ifFalse: [self stopRecording].
	Running := self class running copyWithout: self.
	self class armVsync.
	Smalltalk vm unregisterExternalSemaphore: vsyncIndex.
	vsyncIndex := nil.
	gpuTimer isNil ifFalse: [gpuTimer stop].
	(process notNil and: [process ~~ Processor activeProcess]) ifTrue: [process terminate].
	process := nil.
	self dropStandIn
!
abandon
	running := false.
	Running := self class running copyWithout: self.
	Smalltalk vm unregisterExternalSemaphore: vsyncIndex.
	gpuTimer isNil ifFalse: [gpuTimer abandon].
	process isNil ifFalse: [process terminate].
	process := nil.
	self dropStandIn
!
wake
	sleeping ifTrue: [wake signal]
!
startRecording: aFrameRecorder
	"Record on the work clock (the VM's Scheduler): its frame signal replaces the display's refreshes, so I present once per tick of that clock and the recorder gets every frame, whatever the machine does."
	aFrameRecorder open.
	ownsWorkClock := onWorkClock not.
	onWorkClock := true.
	self class armVsync.
	vsync consumeAllSignals.
	aFrameRecorder startAt: (Smalltalk vm workClockStart: FrameRecorder tickRate semaphore: vsyncIndex).
	recorder := aFrameRecorder.
	world changed
!
stopRecording
	"Back to the real clock and the display; answer the recorder."
	| stopped |
	stopped := recorder.
	recorder := nil.
	stopped stop.
	ownsWorkClock ifTrue: [
		Smalltalk vm workClockStop.
		onWorkClock := false.
		self armVsync].
	^stopped
! !

!Compositor methodsFor: 'stand-in'!
processName
	^'compositor (vsync)'
!
process: aProcess
	process := aProcess
!
standIn
	^standIn
!
standIn: aStandInOrNil
	standIn := aStandInOrNil
!
debugged: aProcess changed: aSymbol
	"A debugger holds my Process (#held) or let it go (#released): a stand-in keeps the screen going meanwhile."
	(aProcess == process and: [running]) ifFalse: [^self].
	aSymbol == #held ifTrue: [
		standIn isNil ifTrue: [standIn := StandIn for: self].
		^self].
	standIn isNil ifTrue: [^self].
	aProcess isTerminated ifTrue: [^standIn adopt].
	standIn retire.
	self wake
!
runStandIn
	self run
!
isLoopProcess
	"Whether the active Process is the one that should run my loop: mine, or my stand-in's while my Process is held."
	| active |
	active := Processor activeProcess.
	^active == process or: [standIn notNil and: [standIn process == active]]
!
dropStandIn
	standIn isNil ifFalse: [standIn terminate. standIn := nil]
! !

!Compositor methodsFor: 'running'!
run
	[running and: [self isLoopProcess]] whileTrue: [
		self waitForTick.
		(running and: [self isLoopProcess]) ifTrue: [
			tickCount := tickCount + 1.
			[gpuTimer poll.
			 onWorkClock ifTrue: [self frameOnWorkClock] ifFalse: [self frame]] on: Error do: [:e |
				self reportError: e.
				presenting := false.
				e return: nil]]]
!
waitForTick
	"Wait for skip display refreshes, at most one and a half ticks after the previous tick: the display link may be missing (the display sleeps) or late (macOS throttles it to about 10 Hz while the VM runs in the background role), then I tick on that timeout."
	| late |
	(restMs notNil and: [restMs > 0]) ifTrue: [
		(Delay forMilliseconds: restMs) wait.
		restMs := 0].
	(idleFrames >= 20 and: [gpuTimer isIdle and: [recorder isNil]]) ifTrue: [
		self sleep.
		lastTick := Time millisecondClockValue.
		^self].
	late := Delay forMilliseconds: (lastTick + tickTimeout - Time millisecondClockValue max: 1).
	late signal: vsync.
	(onWorkClock ifTrue: [1] ifFalse: [skip]) timesRepeat: [
		late isExpired ifFalse: [vsync wait].
		vsync consumeAllSignals].
	late cancel.
	lastTick := Time millisecondClockValue
!
armVsync
	"Have the display link signal vsync on every refresh, the recording clock on each of its ticks. While the display sleeps there is none: waitForTick ticks on its timeout."
	onWorkClock ifTrue: [^Smalltalk vm workClockStart: FrameRecorder tickRate semaphore: vsyncIndex].
	self class armVsync
!
wantsVsync
	^sleeping not and: [onWorkClock not]
!
vsyncIndex
	^vsyncIndex
!
sleep
	sleeping := true.
	self class armVsync.
	wake consumeAllSignals.
	world needsFrame ifFalse: [wake waitTimeoutMSecs: 500].
	sleeping := false.
	wake consumeAllSignals.
	self armVsync.
	vsync consumeAllSignals
!
frame
	| t0 now animating needs |
	"On the recording clock the GPU's frames, like an external program, take real time: while any are unfinished the clock moves with real time instead of jumping to the next deadline. Not while recording: the recorder waits for each frame, and every tick gets its own."
	onWorkClock ifTrue: [Smalltalk vm workClockPaced: (OSProcess externalWork or: [recorder isNil and: [gpuTimer inFlight > 0]])].
	(recorder isNil and: [requests isEmpty and: [gpuTimer inFlight >= self class maxFramesInFlight]]) ifTrue: [^self].
	t0 := Time microsecondClockValue.
	recorder isNil ifFalse: [t0 := recorder tickStartAt: t0].
	now := Animation nowAt: t0 / 1000.0.
	clock := now.
	animating := self stepAt: now.
	t0 - lastScan > 1000000 ifTrue: [self scanProcesses: t0].
	needs := world consumeNeedsFrame | animating | requests isEmpty not
		| (world presentsContinuously and: [renderer device isSoftware not]) | recorder notNil.
	"A frame for the readout alone does not count in it: otherwise it would measure, and keep making, its own frames."
	countsFrame := needs.
	needs := (world topBar updateAt: t0) | needs.
	needs ifFalse: [
		idleFrames := idleFrames + 1.
		^self].
	idleFrames := 0.
	presenting := true.
	self present: t0 now: now.
	presenting := false.
	renderer device isSoftware ifTrue: [restMs := Time microsecondClockValue - t0 // 1000]
!
frameOnWorkClock
	"A frame on the recording clock: its work does not move the clock (the time of the GPU driver's calls is noise, in every recording another one), unless the CPU work of the previous frame did not fit in a tick: that would have missed a refresh of a real screen, and the clock passes the excess. GPU time is reported only (the fences' latencies are milliseconds of queueing: no measure of a frame's GPU work). The real time a recorded frame waits for the GPU and for the reader does not move the clock either, even while it keeps pace with real time: a reader slower than the ticks would otherwise leave the clock behind for good, each tick due as the frame before it ends, and no other Process would run."
	| excess recording |
	excess := lastFrameWork - (1000000 // FrameRecorder tickRate).
	excess > 0 ifTrue: [Smalltalk vm workClockCharge: excess].
	recording := recorder notNil.
	Smalltalk vm workClockHold.
	[self frame] ensure: [
		"Skipped while the clock still stands: released, its next reading would count the wait."
		recording ifTrue: [Smalltalk vm workClockSkipRealTime].
		lastFrameWork := Smalltalk vm workClockRelease]
!
frameClock
	"The clock of the times a frame reports: on the recording clock its work moves this one but not that (frameOnWorkClock)."
	^onWorkClock ifTrue: [Smalltalk vm workClockHeldMicros] ifFalse: [Time microsecondClockValue]
!
stepAt: now
	"Advance animations; post frame ticks; answer whether anything needs further frames."
	| any |
	any := false.
	(world windows, world overlays, world closingWindows) do: [:w |
		(w layer stepAnimationsAt: now) ifTrue: [any := true].
		(w isOpen and: [w wantsFrames]) ifTrue: [w postFrameTick: now. any := true].
		(w decorationsNeedFrameAt: now) ifTrue: [any := true]].
	world toasts do: [:t |
		(t stepAt: now) ifTrue: [any := true].
		(t needsFramesAt: now) ifTrue: [any := true]].
	(world remotePointer pollAt: now pointer: (world dispatcher ifNotNil: [:d | d pointer])) ifTrue: [any := true].
	world stepCurtain ifTrue: [any := true].
	world dispatcher isNil ifFalse: [world dispatcher checkTooltipAt: now].
	^any
! !

!Compositor methodsFor: 'compositing'!
drawWindow: aWindow on: c time: now
	| layer rect s shadow q |
	layer := aWindow layer.
	(layer isRendered and: [(layer isWaitingAt: now) not]) ifFalse: [^self].
	q := c quadCount.
	rect := aWindow bounds origin extent: layer renderedExtent.
	s := layer scale.
	s = 1 ifFalse: [rect := (rect center - (rect extent * s / 2)) extent: rect extent * s].
	rect := rect translateBy: layer offset.
	shadow := (aWindow isOverlay ifTrue: [2] ifFalse: [1 + aWindow focusAmount]) * s.
	c alpha: layer opacity during: [
		c fillRect: (rect translateBy: shadow @ shadow) color: Color shadow.
		c image: layer surface from: (0 @ 0 extent: layer pixelExtent) in: rect.
		(s = 1 and: [aWindow isOpen and: [aWindow needsDecorations: now]]) ifTrue: [
			c translateBy: rect origin during: [
				c clip: (0 @ 0 extent: rect extent) during: [aWindow drawDecorationsOn: c time: now]]]].
	"Where the layer's pixels land, for its damage: unscaled only (scaled, all of it is damaged)."
	items isNil ifFalse: [items add: (Array with: aWindow with: q with: c quadCount - q with: (s = 1 ifTrue: [c deviceRectOf: rect]) with: layer)]
!
noteItem: aKey from: firstQuad on: c
	items isNil ifFalse: [items add: (Array with: aKey with: firstQuad with: c quadCount - firstQuad with: nil with: nil)]
!
drawToastsOn: c
	| y |
	y := world topBar height + 16.
	world toasts do: [:t |
		t isDone ifFalse: [
			t drawOn: c at: (world extent x / 2) @ y.
			y := y + t extent y + 8]]
! !

!Compositor methodsFor: 'requests'!
do: aBlock
	"Run aBlock (with me as argument) in my Process after the next frame, which I present at my next tick however many frames are in flight."
	requests nextPut: aBlock.
	world changed
!
sync: aBlock
	"Run aBlock in my Process; answer its value (at most 10 s)."
	| done result error |
	Processor activeProcess == process ifTrue: [^aBlock cull: self].
	done := Semaphore new.
	self do: [:c | [result := [aBlock cull: c] on: Error do: [:e | error := e messageText. e return: nil]] ensure: [done signal]].
	(done waitTimeoutMSecs: 10000) ifTrue: [^self error: 'The compositor did not answer within 10 s'].
	error isNil ifFalse: [^self error: error].
	^result
!
runRequests
	| request |
	[(request := requests nextOrNil) notNil] whileTrue: [request cull: self]
! !

!Compositor methodsFor: 'readback'!
screenshotScale: aNumber
	"A Form of the whole screen (without the remote pointer) at aNumber pixels per point. My Process only."
	^self screenshotScale: aNumber pointer: false
!
screenshotScale: aNumber pointer: aBoolean
	| full form |
	full := self renderScreenPointer: aBoolean.
	form := self readback: full from: (0 @ 0 extent: full pixelExtent) extent: world extent scale: aNumber.
	full release.
	^form
!
renderScreenPointer: aBoolean
	| full cmd |
	full := Surface extent: world extent scale: world displayScale.
	cmd := renderer device commandBuffer.
	renderer render: (self compositeListScale: world displayScale pointer: aBoolean time: self clock)
		into: full texture clear: Color paper commandBuffer: cmd.
	cmd submit.
	^full
!
screenshotRect: aRectangle scale: aNumber
	"A Form of part of the screen (points)."
	| full form s |
	full := self renderScreenPointer: false.
	s := world displayScale.
	form := self readback: full from: ((aRectangle origin * s) rounded corner: (aRectangle corner * s) rounded) extent: aRectangle extent scale: aNumber.
	full release.
	^form
!
screenshotOf: aWindowOrView scale: aNumber
	"A Form of a window's layer (frame, content and busy decorations), or of a View's part of it."
	| window layer rect src c ext |
	window := aWindowOrView window.
	window isNil ifTrue: [^self error: 'not in a window'].
	layer := window layer.
	layer isRendered ifFalse: [^self error: 'window not rendered yet'].
	rect := aWindowOrView isWindow
		ifTrue: [0 @ 0 extent: layer renderedExtent]
		ifFalse: [aWindowOrView boundsInWindow translateBy: window contentRectInWindow origin].
	src := (rect origin * world displayScale) rounded corner: (rect corner * world displayScale) rounded.
	ext := rect extent.
	c := Canvas extent: ext scale: aNumber.
	c image: layer surface from: src in: (0 @ 0 extent: ext).
	(window isOpen and: [window needsDecorations: self clock]) ifTrue: [
		c translateBy: rect origin negated during: [
			c clip: (rect origin extent: ext) during: [window drawDecorationsOn: c time: self clock]]].
	^self readbackList: c displayList extent: ext scale: aNumber
!
readbackList: aDisplayList extent: anExtent scale: aNumber
	| target cmd form |
	target := Surface extent: anExtent scale: aNumber.
	cmd := renderer device commandBuffer.
	renderer render: aDisplayList into: target texture clear: Color paper commandBuffer: cmd.
	cmd submit.
	form := target readback.
	target release.
	^form
!
readback: aSurface from: sourceRect extent: anExtent scale: aNumber
	"Draw sourceRect (pixels) of aSurface into a new surface of anExtent points at aNumber, read it back."
	| c |
	(aNumber = aSurface scale and: [sourceRect origin = (0 @ 0) and: [sourceRect extent = aSurface pixelExtent]])
		ifTrue: [^aSurface readback].
	c := Canvas extent: anExtent scale: aNumber.
	c image: aSurface from: sourceRect in: (0 @ 0 extent: anExtent).
	^self readbackList: c displayList extent: anExtent scale: aNumber
!
downsample: aSurface to: aPoint into: aTargetSurface bytes: aByteArray
	"Render aSurface scaled to aPoint pixels into aTargetSurface (scale 1), read its RGBA bytes back into aByteArray and answer it."
	| c cmd |
	c := Canvas extent: aPoint scale: 1.
	c image: aSurface from: (0 @ 0 extent: aSurface pixelExtent) in: (0 @ 0 extent: aPoint).
	cmd := renderer device commandBuffer.
	renderer render: c displayList into: aTargetSurface texture clear: Color black commandBuffer: cmd.
	cmd submit.
	^aTargetSurface readbackBytesInto: aByteArray
! !

!Compositor methodsFor: 'statistics'!
scanProcesses: nowMicros
	| all |
	lastScan := nowMicros.
	all := Processor allProcesses.
	knownProcesses := all.
	world topBar processCount: all size.
	lastCpu keys do: [:p | (all includes: p) ifFalse: [lastCpu removeKey: p]]
!
processTimes: ownMicros
	"Microseconds each Process ran since the previous frame: of those the last scan found, and the windows' (a window opened since is not missed)."
	| times all |
	times := IdentityDictionary new.
	all := knownProcesses.
	world windows do: [:w | (w process notNil and: [(all identityIncludes: w process) not]) ifTrue: [all := all copyWith: w process]].
	all do: [:p |
		| cpu old |
		cpu := p cpuTime ifNil: [0].
		old := lastCpu at: p ifAbsent: [cpu].
		cpu > old ifTrue: [times at: p put: cpu - old].
		lastCpu at: p put: cpu].
	process isNil ifFalse: [times at: process put: ownMicros].
	^times
!
recordFrameStart: t0 end: t1 draw: drawUs raster: rasterUs gcCount: n gcMicros: gcUs dropped: aBoolean
	| record |
	record := FrameRecord start: t0 end: t1 processTimes: (self processTimes: t1 - t0)
		draw: drawUs raster: rasterUs gpu: 0 gcCount: n gcMicros: gcUs dropped: aBoolean.
	[Profiler recordFrame: record] on: Error do: [:e | e return: nil].
	countsFrame ifTrue: [world topBar noteFrame: t1 - t0 end: t1].
	lastRecord := record
!
reportError: anException
	| now |
	now := Time millisecondClockValue.
	lastError := anException.
	now - lastErrorTime < 2000 ifTrue: [^self].
	lastErrorTime := now.
	Transcript show: 'Compositor error: ', ([anException messageText asString] on: Error do: [:e | e return: anException class name]); cr
!
lastError
	^lastError
! !

!Compositor class methodsFor: 'accessing'!
probe
	"The DamageProbe measuring a compositor's frames, or nil (the default)."
	^Probe
!
probe: aDamageProbeOrNil
	Probe := aDamageProbeOrNil
!
priority
	^70
!
running
	"The running compositors in start order."
	^Running ifNil: [#()]
!
armVsync
	"The VM signals one vsync semaphore: the first running compositor that wants it gets it; the others tick on their timeout (waitForTick)."
	| c |
	c := self running detect: [:each | each wantsVsync] ifNone: [nil].
	[DisplayWindow vsyncSemaphoreIndex: (c isNil ifTrue: [0] ifFalse: [c vsyncIndex])] on: Error do: [:e | e return: nil]
!
maxFramesInFlight
	"Frames submitted and not yet finished by the GPU before I skip ticks (the World's changes stay pending for the next one): the GPU works on one while I build the next; a hidden window has no swapchain to hold me back, and closing a window waits for all of them."
	^2
! !

!Compositor class methodsFor: 'instance creation'!
world: aWorld
	^self new setWorld: aWorld
! !

!Compositor methodsFor: 'drawing'!
compositeOn: c pointer: showPointer time: now
	"The whole screen as a DisplayList (while items is a collection, each thing drawn noted in it: {key. first quad. quads. device rectangle of a window's layer. layer})."
	| q |
	q := c quadCount.
	world drawDeskOn: c.
	self noteItem: #desk from: q on: c.
	world windowsInPaintOrder do: [:w | self drawWindow: w on: c time: now].
	q := c quadCount.
	world topBar drawOn: c.
	self noteItem: #topBar from: q on: c.
	world overlays do: [:w | self drawWindow: w on: c time: now].
	world closingWindows do: [:w | w isOverlay ifTrue: [self drawWindow: w on: c time: now]].
	q := c quadCount.
	self drawToastsOn: c.
	self noteItem: #toasts from: q on: c.
	q := c quadCount.
	world tooltip isNil ifFalse: [world tooltip drawOn: c].
	self noteItem: #tooltip from: q on: c.
	q := c quadCount.
	world curtain isNil ifFalse: [world curtain drawOn: c].
	self noteItem: #curtain from: q on: c.
	q := c quadCount.
	showPointer ifTrue: [world remotePointer drawOn: c time: now].
	self noteItem: #pointer from: q on: c.
	^c displayList
!
compositeListScale: aNumber pointer: showPointer time: now
	"The whole screen as an independently owned DisplayList."
	^self compositeOn: (Canvas extent: world extent scale: aNumber) pointer: showPointer time: now
! !

!Compositor methodsFor: 'damage'!
damageOf: aDisplayList items: newItems rendered: toRender
	"What aDisplayList (the screen, drawn item by item: newItems) changes of the last frame presented: a DamageRegion of device pixels (full when there is no last frame to compare with, at a new size, after redrawAll, and with DamageCheck forcesFull)."
	| region old newKeys common oldCommon |
	region := DamageRegion extent: aDisplayList pixelExtent.
	(fullNext or: [previousList isNil or: [DamageCheck forcesFull
		or: [previousList pixelExtent ~= aDisplayList pixelExtent or: [displayWindow needsFullFrame]]]])
			ifTrue: [region beFull. ^region].
	differ region: region; stableSurfaces: true.
	old := IdentityDictionary new.
	previousItems do: [:each | old at: each first put: each].
	newKeys := IdentitySet new.
	newItems do: [:each | | o |
		newKeys add: each first.
		o := old at: each first ifAbsent: [nil].
		o isNil
			ifTrue: [differ damageAll: aDisplayList stamps: nil from: (each at: 2) count: (each at: 3)]
			ifFalse: [
				differ diff: previousList stamps: previousStamps from: (o at: 2) count: (o at: 3)
					to: aDisplayList stamps: nil from: (each at: 2) count: (each at: 3)].
		(each at: 5) isNil ifFalse: [self addLayerDamageOf: each in: aDisplayList rendered: toRender]].
	previousItems do: [:o |
		(newKeys includes: o first) ifFalse: [differ damageAll: previousList stamps: previousStamps from: (o at: 2) count: (o at: 3)]].
	"Raised or lowered: an item whose place among the others changed damages its old and its new bounds (any two that changed order overlap only inside one of them)."
	common := newItems select: [:each | old includesKey: each first].
	oldCommon := previousItems select: [:each | newKeys includes: each first].
	common with: oldCommon do: [:n :o |
		n first == o first ifFalse: [
			differ damageAll: aDisplayList stamps: nil from: (n at: 2) count: (n at: 3).
			differ damageAll: previousList stamps: previousStamps from: (o at: 2) count: (o at: 3)]].
	^region
!
addLayerDamageOf: anItem in: aDisplayList rendered: toRender
	"A window's layer rendered this frame damages the screen where its changed pixels land: moved by where it is drawn when drawn 1:1 (with a pixel around, for filtering), else everywhere it is drawn."
	| layer rect damage |
	(toRender identityIncludes: anItem first) ifFalse: [^self].
	layer := anItem at: 5.
	rect := anItem at: 4.
	damage := layer lastDamage.
	rect isNil ifTrue: [^differ damageAll: aDisplayList stamps: nil from: (anItem at: 2) count: (anItem at: 3)].
	(damage isNil or: [rect extent ~= layer pixelExtent]) ifTrue: [^differ region add: rect].
	damage rects do: [:r |
		differ region addLeft: r left + rect left - 1 top: r top + rect top - 1 right: r right + rect left + 1 bottom: r bottom + rect top + 1]
!
checkDamage: aDamageRegion list: aDisplayList previous: olderList rendered: toRender
	"DamageCheck runs: compare what was drawn in part with drawing it whole."
	| check |
	check := DamageCheck current.
	renderer device waitIdle.
	aDamageRegion isFull ifFalse: [
		check checkFrame: aDisplayList previous: olderList surface: displayWindow surface clear: Color desk renderer: renderer damage: aDamageRegion].
	toRender do: [:w |
		w layer lastDamage isNil ifFalse: [check checkLayer: w layer named: w printString renderer: renderer]]
! !

!Compositor methodsFor: 'private'!
present: t0 now: now
	| scale toRender drawUs rasterUs t cmd list stats0 stats1 t1 shown gpuStart fence fenceAt probe before layerUs showUs newItems damage older |
	scale := world displayScale.
	stats0 := Smalltalk vm statistics.
	t := self frameClock.
	renderer updatePipeline.
	pipelineVersion = renderer pipelineVersion ifFalse: [
		pipelineVersion := renderer pipelineVersion.
		fullNext := true.
		(world windows, world closingWindows, world overlays) do: [:w | w layer markNeedsRender]].
	toRender := OrderedCollection new.
	(world windows, world closingWindows, world overlays) do: [:w |
		| key |
		key := w chromeKey.
		key = w layer chromeKey ifFalse: [
			w layer chromeList: (w chromeDisplayListScale: scale); chromeKey: key].
		w layer needsRender ifTrue: [toRender add: w]].
	probe := (Probe notNil and: [Probe compositor == self]) ifTrue: [Probe].
	probe isNil ifFalse: [before := probe beforeRender: toRender].
	drawUs := self frameClock - t.
	t := self frameClock.
	differ isNil ifTrue: [differ := DisplayListDiff region: (DamageRegion extent: 1 @ 1)].
	toRender isEmpty ifFalse: [
		cmd := renderer device commandBuffer.
		toRender do: [:w | w layer renderExtent: w extent scale: scale renderer: renderer commandBuffer: cmd differ: differ].
		gpuStart := self frameClock.
		cmd submit].
	rasterUs := self frameClock - t.
	layerUs := rasterUs.
	t := self frameClock.
	compositeBytes isNil ifTrue: [compositeBytes := ByteArray new: 32768].
	items := OrderedCollection new.
	list := [self compositeOn: (Canvas extent: world extent scale: scale buffer: compositeBytes) pointer: true time: now]
		ensure: [newItems := items. items := nil].
	damage := self damageOf: list items: newItems rendered: toRender.
	lastDamage := damage.
	drawUs := drawUs + (self frameClock - t).
	(damage isEmpty and: [recorder isNil and: [world presentsContinuously not]]) ifTrue: [
		"Nothing on the screen changed: no frame to present (the next one draws into the same bytes)."
		self runRequests.
		frameCount := frameCount + 1.
		^self].
	t := self frameClock.
	gpuStart isNil ifTrue: [gpuStart := t].
	shown := displayWindow show: list clear: Color desk damage: damage.
	showUs := self frameClock - t.
	"The upload has copied these bytes; the next frame draws into the other buffer: these stay to compare it with (screenshots use independently owned lists)."
	compositeBytes := previousList isNil ifFalse: [previousList vertices].
	older := previousList.
	previousList := list.
	previousStamps := DisplayListDiff stampsOf: list.
	previousItems := newItems.
	fullNext := false.
	fenceAt := self frameClock.
	fence := renderer device commandBuffer submitWithFence.
	rasterUs := rasterUs + (self frameClock - t).
	DamageCheck current isNil ifFalse: [self checkDamage: damage list: list previous: older rendered: toRender].
	recorder isNil ifFalse: [recorder captureFrom: displayWindow surface compositor: self].
	self runRequests.
	frameCount := frameCount + 1.
	presentedCount := presentedCount + 1.
	t1 := self frameClock.
	stats1 := Smalltalk vm statistics.
	self recordFrameStart: t0 end: t1 draw: drawUs raster: rasterUs
		gcCount: stats1 gcCount - stats0 gcCount
		gcMicros: stats1 gcMicroseconds - stats0 gcMicroseconds
		dropped: (recorder isNil ifTrue: [shown not] ifFalse: [recorder missedTickBefore: t0]).
	gpuTimer fence: fence submittedAt: fenceAt - gpuStart record: lastRecord.
	"After the frame: the list's bytes are reused by the next one only."
	probe isNil ifFalse: [probe frame: list rendered: before start: t0 draw: drawUs layers: layerUs show: showUs record: lastRecord]
! !
