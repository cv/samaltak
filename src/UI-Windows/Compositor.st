Object subclass: #Compositor
	instanceVariableNames: 'world displayWindow renderer process running vsync vsyncIndex wake sleeping skip tickTimeout idleFrames frameCount presenting requests recorder gpuTimer clock knownProcesses lastCpu lastScan lastRecord lastError lastErrorTime pipelineVersion standIn'
	classVariableNames: ''
	package: 'UI-Windows'!

Compositor comment: 'I am the compositor: a Process at priority 70 woken by the platform''s vsync semaphore, presenting at 60 Hz (every second refresh on a 120 Hz display). Each frame I step the layer animations (window open/close, focus cross-fades, menus), toasts and the remote pointer, post frame ticks to windows with animations, render every Layer whose DisplayList or chrome changed into its Surface, composite all layers (offset, scale about the center, opacity, hard shadows) over the halftone desk with the top bar and overlays onto the DisplayWindow, and record a FrameRecord (Profiler recordFrame:). I never wait for a window''s Process: a busy window keeps its last frame.

While the World is on screen I present every tick (continuous composition: the screen always shows the current state of every layer, at a steady frame rate). A hidden World (tests) presents only when something changed: after 20 ticks without a change I stop the vsync semaphore and sleep until World>>changed wakes me (or 500 ms pass, for the top bar''s statistics). Each tick I also poll the GPUTimer for finished frames'' GPU times.

GPU work of other Processes (screenshots, recording) runs in my Process between frames: do: aBlock / sync: aBlock.'!

!Compositor methodsFor: 'initialization'!
setWorld: aWorld
	world := aWorld.
	displayWindow := aWorld displayWindow.
	running := false.
	sleeping := false.
	idleFrames := 0.
	frameCount := 0.
	presenting := false.
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
	^frameCount
!
clock
	"The animation clock at the current frame (ms, Float)."
	^clock ifNil: [Animation now]
!
isPresenting
	^presenting
!
recorder
	^recorder
!
recorder: aFrameRecorderOrNil
	recorder := aFrameRecorderOrNil.
	world changed
!
renderer
	^renderer
!
gpuTimer
	^gpuTimer
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
	self armVsync.
	rate := [displayWindow refreshRate] on: Error do: [:e | e return: 60].
	skip := rate > 61 ifTrue: [(rate / 60) rounded] ifFalse: [1].
	tickTimeout := rate > 0 ifTrue: [(skip * 1500 / rate) rounded] ifFalse: [25].
	gpuTimer := GPUTimer new.
	process := [self run] newProcess.
	process priority: self class priority; name: 'compositor (vsync)'.
	process resume
!
stop
	running := false.
	DisplayWindow vsyncSemaphoreIndex: 0.
	Smalltalk vm unregisterExternalSemaphore: vsyncIndex.
	vsyncIndex := nil.
	recorder isNil ifFalse: [recorder stop. recorder := nil].
	gpuTimer isNil ifFalse: [gpuTimer stop].
	(process notNil and: [process ~~ Processor activeProcess]) ifTrue: [process terminate].
	process := nil.
	self dropStandIn
!
abandon
	running := false.
	Smalltalk vm unregisterExternalSemaphore: vsyncIndex.
	gpuTimer isNil ifFalse: [gpuTimer abandon].
	process isNil ifFalse: [process terminate].
	process := nil.
	self dropStandIn
!
wake
	sleeping ifTrue: [wake signal]
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
			[gpuTimer poll.
			 self frame] on: Error do: [:e |
				self reportError: e.
				presenting := false.
				e return: nil]]]
!
waitForTick
	"Wait for skip display refreshes, at most one and a half ticks: the display link may be missing (the display sleeps) or late (macOS throttles it to about 10 Hz while the VM runs in the background role), then I tick on that timeout."
	| late |
	(idleFrames >= 20 and: [gpuTimer isIdle]) ifTrue: [^self sleep].
	late := Delay forMilliseconds: tickTimeout.
	late signal: vsync.
	skip timesRepeat: [
		late isExpired ifFalse: [vsync wait].
		vsync consumeAllSignals].
	late cancel
!
armVsync
	"Have the display link signal vsync on every refresh. While the display sleeps there is none: waitForTick ticks on its timeout."
	[DisplayWindow vsyncSemaphoreIndex: vsyncIndex] on: Error do: [:e | e return: nil]
!
sleep
	sleeping := true.
	DisplayWindow vsyncSemaphoreIndex: 0.
	wake consumeAllSignals.
	world needsFrame ifFalse: [wake waitTimeoutMSecs: 500].
	sleeping := false.
	wake consumeAllSignals.
	self armVsync.
	vsync consumeAllSignals
!
frame
	| t0 now animating needs |
	t0 := Time microsecondClockValue.
	now := Animation nowAt: t0 / 1000.0.
	clock := now.
	animating := self stepAt: now.
	t0 - lastScan > 1000000 ifTrue: [self scanProcesses: t0].
	needs := world consumeNeedsFrame.
	needs := (world topBar updateAt: t0) | needs | animating | requests isEmpty not | world isHidden not
		| (recorder notNil and: [recorder wantsFrameAt: t0 / 1000.0]).
	needs ifFalse: [
		idleFrames := idleFrames + 1.
		^self].
	idleFrames := 0.
	presenting := true.
	self present: t0 now: now.
	presenting := false
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
!
present: t0 now: now
	| scale toRender drawUs rasterUs t cmd list stats0 stats1 t1 shown gpuStart fence fenceAt |
	scale := world displayScale.
	stats0 := Smalltalk vm statistics.
	t := Time microsecondClockValue.
	renderer updatePipeline.
	pipelineVersion = renderer pipelineVersion ifFalse: [
		pipelineVersion := renderer pipelineVersion.
		(world windows, world closingWindows, world overlays) do: [:w | w layer markNeedsRender]].
	toRender := OrderedCollection new.
	(world windows, world closingWindows, world overlays) do: [:w |
		| key |
		key := w chromeKey.
		key = w layer chromeKey ifFalse: [
			w layer chromeList: (w chromeDisplayListScale: scale); chromeKey: key].
		w layer needsRender ifTrue: [toRender add: w]].
	drawUs := Time microsecondClockValue - t.
	t := Time microsecondClockValue.
	toRender isEmpty ifFalse: [
		cmd := renderer device commandBuffer.
		toRender do: [:w | w layer renderExtent: w extent scale: scale renderer: renderer commandBuffer: cmd].
		gpuStart := Time microsecondClockValue.
		cmd submit].
	rasterUs := Time microsecondClockValue - t.
	t := Time microsecondClockValue.
	list := self compositeListScale: scale pointer: true time: now.
	drawUs := drawUs + (Time microsecondClockValue - t).
	t := Time microsecondClockValue.
	gpuStart isNil ifTrue: [gpuStart := t].
	shown := displayWindow show: list clear: Color white.
	fenceAt := Time microsecondClockValue.
	fence := renderer device commandBuffer submitWithFence.
	rasterUs := rasterUs + (Time microsecondClockValue - t).
	recorder isNil ifFalse: [recorder captureFrom: displayWindow surface compositor: self].
	self runRequests.
	frameCount := frameCount + 1.
	t1 := Time microsecondClockValue.
	stats1 := Smalltalk vm statistics.
	self recordFrameStart: t0 end: t1 draw: drawUs raster: rasterUs
		gcCount: stats1 gcCount - stats0 gcCount
		gcMicros: stats1 gcMicroseconds - stats0 gcMicroseconds
		dropped: shown not.
	gpuTimer fence: fence submittedAt: fenceAt - gpuStart record: lastRecord
! !

!Compositor methodsFor: 'compositing'!
compositeListScale: aNumber pointer: showPointer time: now
	"The whole screen as a DisplayList."
	| c |
	c := Canvas extent: world extent scale: aNumber.
	world drawDeskOn: c.
	world windows reverseDo: [:w | self drawWindow: w on: c time: now].
	world closingWindows do: [:w | w isOverlay ifFalse: [self drawWindow: w on: c time: now]].
	world topBar drawOn: c.
	world overlays do: [:w | self drawWindow: w on: c time: now].
	world closingWindows do: [:w | w isOverlay ifTrue: [self drawWindow: w on: c time: now]].
	self drawToastsOn: c.
	world tooltip isNil ifFalse: [world tooltip drawOn: c].
	world curtain isNil ifFalse: [world curtain drawOn: c].
	showPointer ifTrue: [world remotePointer drawOn: c time: now].
	^c displayList
!
drawWindow: aWindow on: c time: now
	| layer rect s shadow |
	layer := aWindow layer.
	(layer isRendered and: [(layer isWaitingAt: now) not]) ifFalse: [^self].
	rect := aWindow bounds origin extent: layer renderedExtent.
	s := layer scale.
	s = 1 ifFalse: [rect := (rect center - (rect extent * s / 2)) extent: rect extent * s].
	rect := rect translateBy: layer offset.
	shadow := (aWindow isOverlay ifTrue: [2] ifFalse: [1 + aWindow focusAmount]) * s.
	c alpha: layer opacity during: [
		c fillRect: (rect translateBy: shadow @ shadow) color: Color black.
		c image: layer surface from: (0 @ 0 extent: layer pixelExtent) in: rect.
		(s = 1 and: [aWindow isOpen and: [aWindow needsDecorations: now]]) ifTrue: [
			c translateBy: rect origin during: [
				c clip: (0 @ 0 extent: rect extent) during: [aWindow drawDecorationsOn: c time: now]]]]
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
	"Run aBlock (with me as argument) in my Process after the next frame."
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
		into: full texture clear: Color white commandBuffer: cmd.
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
	renderer render: aDisplayList into: target texture clear: Color white commandBuffer: cmd.
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
	"Microseconds each Process ran since the previous frame."
	| times |
	times := IdentityDictionary new.
	knownProcesses do: [:p |
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
	world topBar noteFrame: t1 - t0 end: t1.
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
priority
	^70
! !

!Compositor class methodsFor: 'instance creation'!
world: aWorld
	^self new setWorld: aWorld
! !
