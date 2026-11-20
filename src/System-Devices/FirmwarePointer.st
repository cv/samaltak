Object subclass: #FirmwarePointer
	instanceVariableNames: 'firmware display absolute relative state semaphore index events process lastZ'
	classVariableNames: ''
	package: 'System-Devices'!

FirmwarePointer comment: 'I am the firmware''s pointer: an absolute one (EFI_ABSOLUTE_POINTER_PROTOCOL, UEFI 2.10, 12.7: a USB tablet, a touch screen) if it reports, else a relative one (EFI_SIMPLE_POINTER_PROTOCOL, 12.5: a mouse). My Process reads their state whenever the firmware signals their WaitForInput events and reports it to my display (FirmwareDisplay>>pointerAt:buttons:wheel:).'!

!FirmwarePointer methodsFor: 'running'!
setFirmware: aFirmware display: aDisplay
	firmware := aFirmware.
	display := aDisplay.
	lastZ := 0
!
start
	"Answer whether there is a pointer."
	absolute := firmware locateProtocol: '8d59d32b-c655-4ae9-9b15-f25904992a43'.
	relative := firmware locateProtocol: '31878c87-0b75-11d5-9a4f-0090273fc14d'.
	(absolute isNil and: [relative isNil]) ifTrue: [^false].
	state := Machine allocate: 32.
	semaphore := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: semaphore.
	events := ({absolute. relative} reject: [:p | p isNil]) collect: [:p | Machine uint64At: p + 16].
	events do: [:e | Machine watch: e semaphoreIndex: index].
	process := [[semaphore wait. self poll] repeat] forkAt: Processor highIOPriority + 5 named: 'pointer'.
	^true
!
stop
	state isNil ifTrue: [^self].
	events do: [:e | Machine watch: e semaphoreIndex: 0].
	self abandon.
	Machine free: state.
	state := nil
!
abandon
	"Stop without the firmware (the previous VM's)."
	process isNil ifFalse: [process terminate].
	Smalltalk vm unregisterExternalSemaphore: index.
	process := index := nil
!
getState: aProtocol
	"Did aProtocol's state (into state) change?"
	^aProtocol notNil and: [(firmware isError: (Machine call: (firmware function: aProtocol at: 8) with: aProtocol with: state)) not]
!
poll
	"Report the absolute pointer's state if it changed, else the relative one's movement."
	| mode extent x y z ab |
	extent := display extent.
	(self getState: absolute) ifTrue: [
		mode := Machine uint64At: absolute + 24.
		x := display pointerPosition x.
		y := display pointerPosition y.
		(Machine uint64At: mode + 24) > (Machine uint64At: mode) ifTrue: [
			x := ((Machine uint64At: state) - (Machine uint64At: mode)) * extent x / ((Machine uint64At: mode + 24) - (Machine uint64At: mode) + 1)].
		(Machine uint64At: mode + 32) > (Machine uint64At: mode + 8) ifTrue: [
			y := ((Machine uint64At: state + 8) - (Machine uint64At: mode + 8)) * extent y / ((Machine uint64At: mode + 32) - (Machine uint64At: mode + 8) + 1)].
		z := Machine uint64At: state + 16.
		ab := Machine uint32At: state + 24.
		display
			pointerAt: x asFloat @ y asFloat
			buttons: ((ab bitAnd: 1) ~= 0 ifTrue: [1] ifFalse: [0]) + ((ab bitAnd: 2) ~= 0 ifTrue: [4] ifFalse: [0])
			wheel: z - lastZ.
		lastZ := z.
		^self].
	(self getState: relative) ifTrue: [
		display
			pointerAt: display pointerPosition + ((Machine int32At: state) @ (Machine int32At: state + 4))
			buttons: ((Machine uint8At: state + 12) ~= 0 ifTrue: [1] ifFalse: [0]) + ((Machine uint8At: state + 13) ~= 0 ifTrue: [4] ifFalse: [0])
			wheel: (Machine int32At: state + 8)]
! !

!FirmwarePointer class methodsFor: 'instance creation'!
firmware: aFirmware display: aDisplay
	^self new setFirmware: aFirmware display: aDisplay
! !
