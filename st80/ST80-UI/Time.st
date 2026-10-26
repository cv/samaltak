Object subclass: #Time
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'ST80-UI'!

Time comment: 'I am the clock: the VM''s monotonic milliseconds (the kernel''s timing methods use me).'!

!Time class methodsFor: 'clocks'!
millisecondClockValue
	<primitive: 'millisecondClock'>
	^self primitiveFailed
!
microsecondClockValue
	<primitive: 'microsecondClock'>
	^self primitiveFailed
!
millisecondsToRun: aBlock
	| start |
	start := self millisecondClockValue.
	aBlock value.
	^self millisecondClockValue - start
! !
