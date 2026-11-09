Object subclass: #FrameRecorder
	instanceVariableNames: 'path width height fps stream surface buffer running captured written startTime tickOrigin error lastTick'
	classVariableNames: ''
	package: 'UI-Windows'!

FrameRecorder comment: 'I record the composited screen as raw RGBA frames (width × height, downsampled on the GPU) into a FIFO or file, for ffmpeg -f rawvideo -pix_fmt rgba -s WxH -r FPS -i <fifo>. I have no Process: the Compositor hands me each presented frame (captureFrom:compositor:, in its Process) and I write it once for every video slot (1/fps s of the recording clock since the start) that has come due: more than once when the compositor could not present in time. The recording clock is the VM''s work clock, ticking at the rate of a display (Compositor>>startRecording:), so I wait for the GPU and for the reader, a slow one delays the recording and costs no frame, and each tick''s frame shows that tick''s exact time (tickStartAt:), whatever the machine was doing.'!

!FrameRecorder methodsFor: 'initialization'!
setPath: aString width: w height: h fps: aNumber
	path := aString.
	width := w rounded.
	height := h rounded.
	fps := (aNumber max: 1) min: 60.
	captured := 0.
	written := 0.
	running := false
! !

!FrameRecorder methodsFor: 'accessing'!
width
	^width
!
height
	^height
!
fps
	^fps
!
framesWritten
	^written
!
framesCaptured
	^captured
!
error
	^error
!
isRunning
	^running
! !

!FrameRecorder methodsFor: 'running'!
open
	stream := FileStream appendingFileNamed: path.
	stream binary
!
startAt: firstTick
	"The recording clock's first tick is at firstTick (µs); the video begins at its next one."
	tickOrigin := firstTick.
	startTime := self tickStart: (self tickAt: Time microsecondClockValue) + 1.
	running := true
!
stop
	running := false.
	stream isNil ifFalse: [[stream close] on: Error do: [:e | e return: nil]].
	stream := nil.
	surface isNil ifFalse: [surface release. surface := nil]
!
slotAt: microseconds
	"The index of the video slot holding microseconds (the same grid as the VM's frame signal: the Scheduler's workClockFrameDue)."
	^microseconds - startTime * fps // 1000000 max: -1
!
tickStartAt: microseconds
	"The exact start of the tick of the recording clock holding microseconds: the time its frame shows, the same in every recording."
	^self tickStart: (self tickAt: microseconds)
!
tickAt: microseconds
	^microseconds - tickOrigin * self class tickRate // 1000000
!
tickStart: tick
	"µs of tick number tick: the VM's frame signal comes then (the Scheduler's workClockFrameDue: whole ms)."
	| rate |
	rate := self class tickRate.
	^tick * 1000 + rate - 1 // rate * 1000 + tickOrigin
!
missedTickBefore: microseconds
	"The compositor presents the frame of the tick holding microseconds: did it miss the tick before?"
	| tick missed |
	tick := self tickAt: microseconds.
	missed := lastTick notNil and: [tick > (lastTick + 1)].
	lastTick := tick.
	^missed
!
captureFrom: aSurface compositor: aCompositor
	"Compositor Process: write the presented frame once for each video slot that has come due, waiting for the GPU and the reader."
	| due |
	running ifFalse: [^self].
	due := (self slotAt: Time microsecondClockValue) + 1 - written.
	due <= 0 ifTrue: [^self].
	surface isNil ifTrue: [surface := Surface width: width height: height scale: 1].
	buffer isNil ifTrue: [buffer := ByteArray new: width * height * 4].
	aCompositor downsample: aSurface to: width @ height into: surface bytes: buffer.
	captured := captured + 1.
	[due timesRepeat: [
		stream nextPutAll: buffer.
		written := written + 1]]
		on: Error do: [:e | error := e messageText. running := false. e return: nil]
! !

!FrameRecorder class methodsFor: 'accessing'!
tickRate
	"The ticks of the recording clock per second: what the compositor presents at on a display."
	^60
! !

!FrameRecorder class methodsFor: 'instance creation'!
path: aString width: w height: h fps: aNumber
	^self new setPath: aString width: w height: h fps: aNumber
! !
