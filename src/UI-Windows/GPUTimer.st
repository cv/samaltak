Object subclass: #GPUTimer
	instanceVariableNames: 'pending last measured total'
	classVariableNames: ''
	package: 'UI-Windows'!

GPUTimer comment: 'I measure the GPU time of presented frames without blocking the Compositor and without a Process of my own. The compositor notes the time just before a frame''s first submit, then submits an empty command buffer with a fence after the frame''s last one (the queue runs command buffers in order, so the fence completes when the frame''s GPU work is done) and hands me the fence, the time from the first submit to the fence''s submit, and the FrameRecord. The platform''s fence watcher stamps when the fence completed; the compositor polls me at its next ticks (poll) and I store first submit to completion into the FrameRecord (gpu:). It is an upper bound on GPU execution time (it includes queueing behind earlier frames), to about 0.2 ms. The value arrives a tick after Profiler recordFrame: (0 until then); records whose fence takes longer than 1 s are left at 0. A frame stays pending until its fence completed (inFlight: the Compositor''s backpressure), or for at most 10 s. totalMicroseconds sums the measured frames'' times: its growth over a span of wall-clock time is the GPU''s load.'!

!GPUTimer methodsFor: 'initialization'!
initialize
	pending := OrderedCollection new.
	measured := 0.
	total := 0
! !

!GPUTimer methodsFor: 'accessing'!
last
	"The last measured frame's GPU µs."
	^last
!
measured
	^measured
!
isIdle
	^pending isEmpty
!
inFlight
	"How many frames the GPU has not finished."
	^pending size
!
totalMicroseconds
	"The GPU time of every frame measured so far (µs): its share of a span of wall-clock time is the GPU's load (the Process Browser)."
	^total ifNil: [0]
! !

!GPUTimer methodsFor: 'running'!
start
!
stop
	pending do: [:each | each first release].
	pending := OrderedCollection new
!
abandon
	pending := OrderedCollection new
!
fence: aFence submittedAt: micros record: aFrameRecord
	"Compositor Process: aFence was submitted micros (µs of the microsecond clock) after the frame's first submit... see poll."
	pending add: (Array with: aFence with: micros with: aFrameRecord with: Time microsecondClockValue)
!
poll
	"Compositor Process, every tick: finish the frames whose fence completed."
	| now |
	pending isEmpty ifTrue: [^self].
	now := Time microsecondClockValue.
	pending copy do: [:item | | elapsed |
		elapsed := item first elapsedMicroseconds.
		(elapsed notNil or: [now - (item at: 4) > 10000000]) ifTrue: [
			(elapsed notNil and: [elapsed <= 1000000]) ifTrue: [
				last := (item at: 2) + elapsed.
				measured := measured + 1.
				total := self totalMicroseconds + last.
				(item at: 3) isNil ifFalse: [(item at: 3) gpu: last]].
			item first release.
			pending remove: item]]
! !
