Object subclass: #RefreshClock
	instanceVariableNames: 'index process parked'
	classVariableNames: ''
	package: 'System-Devices'!

RefreshClock comment: 'I am the display refresh where nothing tells it (UEFI): my Process signals an external semaphore (the compositor''s) at 60 Hz, at most once per period; behind by more than a period, it starts again from now. While there is no semaphore to signal (the compositor sleeps) the Process waits, parked, for the next one, so a sleeping and waking display does not come and go in the Process Browser.'!

!RefreshClock methodsFor: 'running'!
semaphoreIndex: anInteger
	"Signal the external semaphore anInteger at every refresh; 0 parks my Process until the next one."
	parked isNil ifTrue: [parked := Semaphore new].
	index := anInteger.
	anInteger = 0 ifTrue: [^self].
	process isNil
		ifTrue: [process := [self run] forkAt: Processor highIOPriority + 5 named: 'refresh clock']
		ifFalse: [parked signal]
!
stop
	process isNil ifFalse: [process terminate].
	process := nil
!
run
	"Refresh n is due n * 50 / 3 ms after the start."
	| start n now due |
	start := Time millisecondClockValue.
	n := 0.
	[index = 0 ifTrue: [
		parked consumeAllSignals.
		[index = 0] whileTrue: [parked wait].
		start := Time millisecondClockValue.
		n := 0].
	n := n + 1.
	due := start + (n * 50 // 3).
	now := Time millisecondClockValue.
	due > now
		ifTrue: [(Delay forMilliseconds: due - now) wait]
		ifFalse: [due + 16 < now ifTrue: [
			start := now.
			n := 0]].
	(Smalltalk vm externalObjects at: index ifAbsent: [nil]) ifNotNil: [:s | s signal]] repeat
! !
