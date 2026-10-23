Object subclass: #ProfilerLive
	instanceVariableNames: 'profiler cpu allocations bars now refreshes allocationsUpdated'
	classVariableNames: ''
	package: 'Tools'!

ProfilerLive comment: 'I am what the Profiler window follows while it is live: ProfileAggregates of the profiler''s CPU and allocation samples and the frame bars (ProfilerBars), all updated incrementally. update costs about what was recorded since the previous one, so the window can refresh ten times a second with a full ring. The allocation aggregate catches up only when asked for (updatedAllocations: the Allocations and Tally tabs), as allocation samples can come as often as CPU samples.'!

!ProfilerLive methodsFor: 'accessing'!
profiler
	^profiler
!
cpu
	^cpu
!
allocations
	"Answer the allocation aggregate as it is (see updatedAllocations)."
	^allocations
!
updatedAllocations
	"Answer the allocation aggregate, caught up with the profiler once per update."
	allocationsUpdated = refreshes ifFalse: [
		allocations update.
		allocationsUpdated := refreshes].
	^allocations
!
bars
	^bars
!
now
	"Answer when I was updated last (µs)."
	^now
! !

!ProfilerLive methodsFor: 'updating'!
update
	"Catch up with the profiler. Answer whether anything changed."
	| changed |
	changed := cpu update.
	changed := bars update | changed.
	refreshes := refreshes + 1.
	now := Time microsecondClockValue.
	^changed
! !

!ProfilerLive methodsFor: 'private'!
setProfiler: aProfiler
	profiler := aProfiler.
	cpu := ProfileAggregate on: aProfiler kind: #cpu.
	allocations := ProfileAggregate on: aProfiler kind: #allocation.
	bars := ProfilerBars on: aProfiler.
	refreshes := 0.
	now := Time microsecondClockValue
! !

!ProfilerLive class methodsFor: 'instance creation'!
on: aProfiler
	^self new setProfiler: aProfiler
! !
