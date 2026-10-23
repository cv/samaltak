Object subclass: #ProfilerFrameBar
	instanceVariableNames: 'record start end duration dropped'
	classVariableNames: ''
	package: 'Tools'!

ProfilerFrameBar comment: 'I am one bar of the frame timelines: a FrameRecord and the interval it stands for. The compositor presents only when something changed, so while it presents frame after frame (the previous frame ended less than 2.5 budgets earlier) a bar spans from the previous frame''s end and its duration is the frame time the user saw; otherwise the bar is one budget wide and its duration is the frame''s own work. I am dropped when the compositor overran the budget or the frame could not be shown (FrameRecord>>isDropped; ignored when no frame was shown at all, i.e. the display is hidden).'!

!ProfilerFrameBar methodsFor: 'accessing'!
record
	^record
!
start
	"Answer the start of my interval (µs)."
	^start
!
end
	^end
!
duration
	"Answer the frame time (µs): since the previous frame while presenting continuously, else the frame's own work."
	^duration
!
milliseconds
	^duration / 1000.0
!
number
	^record number
!
isDropped
	^dropped
!
includesTime: microseconds
	^microseconds between: start and: end
!
overlapsFrom: t0 to: t1
	^end >= t0 and: [start <= t1]
! !

!ProfilerFrameBar methodsFor: 'private'!
setDropped: aBoolean
	dropped := aBoolean
!
setRecord: aFrameRecord start: startMicros duration: micros dropped: aBoolean
	record := aFrameRecord.
	start := startMicros.
	end := aFrameRecord end.
	duration := micros.
	dropped := aBoolean
! !

!ProfilerFrameBar class methodsFor: 'instance creation'!
barsFor: frameRecords
	"Answer my instances for frameRecords (oldest first)."
	| budget previousEnd ignoreShown bars |
	budget := FrameRecord budgetMicros.
	ignoreShown := frameRecords notEmpty and: [frameRecords allSatisfy: [:f | f isDropped]].
	previousEnd := nil.
	bars := frameRecords collect: [:f | | continuous bar |
		continuous := previousEnd notNil and: [f start - previousEnd between: 0 and: budget * 5 // 2].
		bar := self new
			setRecord: f
			start: (continuous ifTrue: [previousEnd] ifFalse: [f start min: f end - budget])
			duration: (continuous ifTrue: [f end - previousEnd] ifFalse: [f duration])
			dropped: ((f isDropped and: [ignoreShown not]) or: [f duration > budget]).
		previousEnd := f end.
		bar].
	^bars asArray
!
displayHiddenIn: frameRecords
	"Answer whether no frame in frameRecords was shown (a hidden display)."
	^frameRecords notEmpty and: [frameRecords allSatisfy: [:f | f isDropped]]
! !
