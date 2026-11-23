Object subclass: #ST80DisplayProbe
	instanceVariableNames: 'screen'
	classVariableNames: ''
	package: 'ST80-UI'!

!ST80DisplayProbe methodsFor: 'running'!
run
	[self exercise] on: Error do: [:e |
		Transcript show: 'Display probe: ', e messageText; cr.
		Smalltalk quit: 2]
!
exercise
	self requireImageRenderer.
	screen := DisplayScreen new.
	(screen open: 19 @ 16) ifFalse: [self error: 'open failed'].
	self scavenge; collect.
	screen black: (-2 @ -1 extent: 8 @ 4).
	screen grey: (6 @ 0 extent: 5 @ 3).
	screen reverse: (4 @ 1 extent: 5 @ 4).
	screen bits: #[16rB2 16rFF 16r4D 16r80] extent: 9 @ 2 at: 12 @ 2.
	screen flush.

	"Clip the source and destination while scrolling down/right, then up/left."
	screen copy: (-2 @ 0 extent: 20 @ 5) to: 1 @ 1.
	screen copy: (3 @ 2 extent: 14 @ 4) to: -1 @ 1.
	screen bits: #[16r78] extent: 7 @ 1 at: -2 @ 0 rule: 1.
	screen bits: #[16rEC] extent: 8 @ 1 at: 16 @ 5 rule: 2.
	self scavenge; collect.
	Transcript show: 'Awaiting input before flush'; cr.
	self expectEvent: #(1 10 5 0 1).
	Transcript show: 'Received input before flush'; cr.
	self expectEvent: #(3 15 9 0 2).
	self expectEvent: #(2 16 10 0 0).
	"More events than fit in the mailbox; it must refill and wrap."
	1 to: 45 do: [:i |
		i \\ 7 = 0 ifTrue: [self scavenge].
		self expectEvent: {4. 0. 0. 65 + (i \\ 26). i bitAnd: 15}].
	screen nextEvent ifNotNil: [self error: 'extra input event'].
	screen flush.

	self expectEvent: #(4 0 0 32 8).
	self scavenge; collect.
	screen white: screen bounds.
	screen show: 'H' at: 1 @ -2.
	screen showReversed: 'H' at: 14 @ 0.
	screen flush.
	self expectEvent: #(4 0 0 13 0).
	Smalltalk quit: 0
!
requireImageRenderer
	"Check the methods actually installed in the guest, including helpers and class-side code."
	{DisplayScreen. DisplayBitmap. DisplayFont} do: [:cls |
		(cls methods, cls class methods) do: [:method |
			(method primitiveNumber = 0 and: [
				(method pragmaAt: #ffiSite) isNil and: [
					method literals noneSatisfy: [:literal | literal isKindOf: FFIBinding]]]) ifFalse: [
						self error: 'Native display method: ', cls name, '>>', method selector]]]
!
expectEvent: expected
	| event wake |
	wake := Semaphore new.
	[(event := screen nextEvent) isNil] whileTrue: [
		self signal: wake at: Time millisecondClockValue + 5.
		wake wait].
	event = expected ifFalse: [self error: 'wrong event; expected ', expected printString, ' got ', event printString]
! !

!ST80DisplayProbe methodsFor: 'VM services'!
signal: aSemaphore at: milliseconds
	<primitive: 'signalAtMilliseconds'>
	^self primitiveFailed
!
scavenge
	<primitive: 'scavenge'>
	^self primitiveFailed
!
collect
	<primitive: 'gc'>
	^self primitiveFailed
! !
