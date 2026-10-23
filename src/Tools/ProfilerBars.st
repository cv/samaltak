Object subclass: #ProfilerBars
	instanceVariableNames: 'profiler bars lastNumber shown totals hidden generation droppedCount'
	classVariableNames: ''
	package: 'Tools'!

ProfilerBars comment: 'I keep the Profiler window''s frame bars (ProfilerFrameBar, oldest first) up to date with the profiler''s frame ring: update adds bars for the FrameRecords recorded since the previous update and drops those the ring no longer holds, so a refresh costs only the new frames. I also keep the CPU µs per Process over all my bars (the timelines shade the busiest user Processes) and whether no frame was shown at all (a hidden display: dropped then only means over budget).'!

!ProfilerBars methodsFor: 'accessing'!
bars
	"Answer my bars, oldest first (not a copy)."
	^bars
!
totals
	"Answer an IdentityDictionary Process -> CPU µs in my bars."
	^totals
!
displayHidden
	^hidden
!
droppedCount
	^droppedCount
!
generation
	^generation
!
oldestStart
	^bars isEmpty ifTrue: [nil] ifFalse: [bars first record start]
! !

!ProfilerBars methodsFor: 'updating'!
update
	"Follow the profiler's frame ring. Answer whether anything changed."
	| first new budget changed wasHidden |
	changed := false.
	profiler frameCount < lastNumber ifTrue: [self setProfiler: profiler].
	first := profiler oldestFrameNumber.
	[bars notEmpty and: [bars first number < first]] whileTrue: [
		self forget: bars removeFirst.
		changed := true].
	new := profiler framesAfter: lastNumber.
	budget := FrameRecord budgetMicros.
	wasHidden := hidden.
	new do: [:f | f isDropped ifFalse: [shown := shown + 1]].
	hidden := (bars notEmpty or: [new notEmpty]) and: [shown = 0].
	hidden = wasHidden ifFalse: [
		bars do: [:b | self markDropped: b].
		droppedCount := bars inject: 0 into: [:n :b | b isDropped ifTrue: [n + 1] ifFalse: [n]].
		changed := true].
	new do: [:f | | previousEnd continuous bar |
		previousEnd := bars isEmpty ifTrue: [nil] ifFalse: [bars last end].
		continuous := previousEnd notNil and: [f start - previousEnd between: 0 and: budget * 5 // 2].
		bar := ProfilerFrameBar new
			setRecord: f
			start: (continuous ifTrue: [previousEnd] ifFalse: [f start min: f end - budget])
			duration: (continuous ifTrue: [f end - previousEnd] ifFalse: [f duration])
			dropped: false.
		self markDropped: bar.
		bar isDropped ifTrue: [droppedCount := droppedCount + 1].
		bars addLast: bar.
		f processTimes keysAndValuesDo: [:p :us | totals at: p put: (totals at: p ifAbsent: [0]) + us].
		lastNumber := f number.
		changed := true].
	changed ifTrue: [generation := generation + 1].
	^changed
! !

!ProfilerBars methodsFor: 'private'!
setProfiler: aProfiler
	profiler := aProfiler.
	bars := OrderedCollection new.
	lastNumber := 0.
	shown := 0.
	totals := IdentityDictionary new.
	hidden := false.
	droppedCount := 0.
	generation := (generation ifNil: [0]) + 1
!
forget: aBar
	aBar record isDropped ifFalse: [shown := shown - 1].
	aBar isDropped ifTrue: [droppedCount := droppedCount - 1].
	aBar record processTimes keysAndValuesDo: [:p :us | | t |
		t := (totals at: p ifAbsent: [0]) - us.
		t <= 0 ifTrue: [totals removeKey: p ifAbsent: [nil]] ifFalse: [totals at: p put: t]]
!
markDropped: aBar
	aBar setDropped: ((aBar record isDropped and: [hidden not]) or: [aBar record duration > FrameRecord budgetMicros])
! !

!ProfilerBars class methodsFor: 'instance creation'!
on: aProfiler
	^self new setProfiler: aProfiler
! !
