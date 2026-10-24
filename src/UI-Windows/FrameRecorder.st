Object subclass: #FrameRecorder
	instanceVariableNames: 'path width height fps stream surface buffer running captured written startTime error'
	classVariableNames: ''
	package: 'UI-Windows'!

FrameRecorder comment: 'I record the composited screen as raw RGBA frames (width × height, downsampled on the GPU) into a FIFO or file, for ffmpeg -f rawvideo -pix_fmt rgba -s WxH -r FPS -i <fifo>. I have no Process: the Compositor hands me each presented frame (captureFrom:compositor:, in its Process) and I write it once for every video slot (1/fps s since start) that has come due, repeating the frame when the compositor presented less often or the writes fell behind, so the video keeps real time. Writes go through the VM''s background writer thread (FileStream>>writeBehind:), so a busy ffmpeg never blocks the image.'!

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
start
	stream := FileStream appendingFileNamed: path.
	stream binary.
	startTime := Time microsecondClockValue / 1000.0.
	running := true
!
stop
	running := false.
	stream isNil ifFalse: [[stream close] on: Error do: [:e | e return: nil]].
	stream := nil.
	surface isNil ifFalse: [surface release. surface := nil]
!
captureFrom: aSurface compositor: aCompositor
	"Compositor Process: if video slots came due since the last write, downsample the presented frame and write it once per due slot."
	| due |
	running ifFalse: [^self].
	due := ((Time microsecondClockValue / 1000.0 - startTime) * fps / 1000.0) floor + 1 - written.
	due <= 0 ifTrue: [^self].
	surface isNil ifTrue: [surface := Surface width: width height: height scale: 1].
	buffer isNil ifTrue: [buffer := ByteArray new: width * height * 4].
	aCompositor downsample: aSurface to: width @ height into: surface bytes: buffer.
	captured := captured + 1.
	[due timesRepeat: [
		(stream writeBehind: buffer) ifFalse: [^self].
		written := written + 1]]
		on: Error do: [:e | error := e messageText. running := false. e return: nil]
!
wantsFrameAt: now
	"Whether the compositor should present although nothing changed: a video slot is due."
	^running and: [((now - startTime) * fps / 1000.0) floor + 1 > written]
! !

!FrameRecorder class methodsFor: 'instance creation'!
path: aString width: w height: h fps: aNumber
	^self new setPath: aString width: w height: h fps: aNumber
! !
