Object subclass: #FrameRecord
	instanceVariableNames: 'number start end processTimes draw raster gpu gcCount gcMicros dropped marks'
	classVariableNames: 'BudgetMicros'
	package: 'System-Profiling'!

FrameRecord comment: 'I record one presented frame, as reported by the compositor through Profiler recordFrame: — start and end (microsecond clock), the microseconds each Process ran during the frame (processTimes: a Dictionary Process -> µs), the compositor''s draw and raster times, the GPU time from timestamp queries, the GCs (count and µs) and whether the frame missed its deadline. The Profiler numbers me and attaches the ProfileMarks dropped since the previous frame. All times are µs.'!

!FrameRecord methodsFor: 'accessing'!
number
	^number
!
start
	^start
!
end
	^end
!
duration
	"Answer the frame time in µs."
	^end - start
!
milliseconds
	^(end - start) / 1000.0
!
processTimes
	^processTimes
!
processes
	"Answer the Processes that ran in this frame, longest first."
	^(processTimes keys asArray) sort: [:a :b | (processTimes at: a) > (processTimes at: b)]
!
timeFor: aProcess
	^processTimes at: aProcess ifAbsent: [0]
!
processTotal
	^processTimes inject: 0 into: [:sum :each | sum + each]
!
draw
	^draw
!
raster
	^raster
!
gpu
	^gpu
!
gcCount
	^gcCount
!
gcMicros
	^gcMicros
!
otherTime
	"Answer the µs of the frame not accounted for by Processes, draw, raster and GC (system work)."
	^(self duration - self processTotal - draw - raster - gcMicros) max: 0
!
overBudget
	"Answer how many µs I exceeded the frame budget (0 if within)."
	^(self duration - self class budgetMicros) max: 0
!
marks
	^marks ifNil: [#()]
! !

!FrameRecord methodsFor: 'testing'!
isDropped
	^dropped == true
!
includesTime: microseconds
	^microseconds between: start and: end
!
overlapsFrom: startMicroseconds to: stopMicroseconds
	^end >= startMicroseconds and: [start <= stopMicroseconds]
! !

!FrameRecord methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FrameRecord(#'; print: number; space;
		nextPutAll: (Profiler printMicros: self duration).
	self isDropped ifTrue: [aStream nextPutAll: ' dropped'].
	aStream nextPut: $)
! !

!FrameRecord methodsFor: 'private'!
setStart: startMicros end: endMicros processTimes: aDictionary draw: drawMicros raster: rasterMicros gpu: gpuMicros gcCount: n gcMicros: gcTime dropped: aBoolean
	start := startMicros.
	end := endMicros.
	processTimes := aDictionary ifNil: [IdentityDictionary new].
	draw := drawMicros ifNil: [0].
	raster := rasterMicros ifNil: [0].
	gpu := gpuMicros ifNil: [0].
	gcCount := n ifNil: [0].
	gcMicros := gcTime ifNil: [0].
	dropped := aBoolean == true
!
setNumber: anInteger marks: anArray
	number := anInteger.
	marks := anArray
! !

!FrameRecord class methodsFor: 'instance creation'!
start: startMicros end: endMicros processTimes: aDictionary draw: drawMicros raster: rasterMicros gpu: gpuMicros gcCount: n gcMicros: gcTime dropped: aBoolean
	^self new setStart: startMicros end: endMicros processTimes: aDictionary draw: drawMicros raster: rasterMicros gpu: gpuMicros gcCount: n gcMicros: gcTime dropped: aBoolean
! !

!FrameRecord class methodsFor: 'budget'!
budgetMicros
	"Answer the frame budget in µs (default 16667, 60 Hz)."
	^BudgetMicros ifNil: [16667]
!
budgetMicros: anInteger
	BudgetMicros := anInteger
! !
