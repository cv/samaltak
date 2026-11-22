Object subclass: #StageTimes
	instanceVariableNames: 'frame total lock'
	classVariableNames: 'Current'
	package: 'System-Profiling'!

StageTimes comment: 'I count the time and the bytes of the stages a frame goes through below the compositor (rendering a layer, the composite, the blit to the swapchain, a host upload, the firmware screen''s shadow copy and Blt), by name, while a measurement runs. Off by default: Current is nil and a stage only tests that. A stage reports with add:since:bytes:, which answers the clock to time the next stage from; takeFrame answers what the stages reported since it was last sent (a Dictionary name -> {count. µs. bytes}) and adds it to the totals. DamageProbe (UI-Windows) takes one at the end of each presented frame (docs/graphics-damage.md).

	| s t |
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	"... the stage''s work ..."
	s isNil ifFalse: [s add: #upload since: t bytes: n]'!

!StageTimes methodsFor: 'initialization'!
initialize
	frame := Dictionary new.
	total := Dictionary new.
	lock := Semaphore forMutualExclusion
! !

!StageTimes methodsFor: 'counting'!
add: aSymbol since: startMicros bytes: anInteger
	"Count a stage that started at startMicros and moved anInteger bytes; answer the clock now."
	| now |
	now := Time microsecondClockValue.
	lock critical: [| e |
		e := frame at: aSymbol ifAbsent: [frame at: aSymbol put: (Array new: 3 withAll: 0)].
		e at: 1 put: (e at: 1) + 1.
		e at: 2 put: (e at: 2) + (now - startMicros).
		e at: 3 put: (e at: 3) + anInteger].
	^now
!
takeFrame
	"What the stages reported since the previous takeFrame: name -> {count. µs. bytes}."
	| taken |
	lock critical: [
		taken := frame.
		frame := Dictionary new].
	taken keysAndValuesDo: [:k :e | | t |
		t := total at: k ifAbsent: [total at: k put: (Array new: 3 withAll: 0)].
		1 to: 3 do: [:i | t at: i put: (t at: i) + (e at: i)]].
	^taken
!
total
	^total
! !

!StageTimes class methodsFor: 'measuring'!
current
	"The running measurement, or nil (the default: the stages count nothing)."
	^Current
!
start
	^Current := self new
!
stop
	"Stop counting; answer the measurement."
	| s |
	s := Current.
	Current := nil.
	^s
! !
