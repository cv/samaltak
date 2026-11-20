Object subclass: #FirmwareKeyboard
	instanceVariableNames: 'firmware queue protocol event keyData semaphore index process'
	classVariableNames: ''
	package: 'System-Devices'!

FirmwareKeyboard comment: 'I am the firmware''s keyboard: the console''s extended text input (EFI_SIMPLE_TEXT_INPUT_EX_PROTOCOL, UEFI 2.10, 12.2), whose key strokes (a scan code or a character, and the shift state; no releases) I read in my Process whenever the firmware signals its WaitForKeyEx event, and report to an InputQueue as SDL keycodes and modifiers as on Linux: Alt is cmd, the logo key alt (keycodeOf:char:shiftState:).'!

!FirmwareKeyboard methodsFor: 'running'!
setFirmware: aFirmware queue: anInputQueue
	firmware := aFirmware.
	queue := anInputQueue
!
start
	"Answer whether there is a keyboard."
	protocol := firmware protocol: 'dd9e7534-7762-4698-8c14-f58517a625aa' on: firmware conInHandle.
	protocol isNil ifTrue: [^false].
	event := Machine uint64At: protocol + 16.
	keyData := Machine allocate: 16.
	semaphore := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: semaphore.
	Machine watch: event semaphoreIndex: index.
	process := [[semaphore wait. self readKeys] repeat] forkAt: Processor highIOPriority + 5 named: 'keyboard'.
	self readKeys.
	^true
!
stop
	"No longer: my Process ends, my memory is freed."
	protocol isNil ifTrue: [^self].
	Machine watch: event semaphoreIndex: 0.
	self abandon.
	Machine free: keyData
!
abandon
	"Stop without the firmware (the previous VM's)."
	process isNil ifFalse: [process terminate].
	Smalltalk vm unregisterExternalSemaphore: index.
	process := index := protocol := nil
!
readKeys
	"Report the key strokes the firmware has (ReadKeyStrokeEx until it has none)."
	[firmware isError: (Machine call: (firmware function: protocol at: 8) with: protocol with: keyData)] whileFalse: [
		self class
			keyStroke: (Machine uint16At: keyData)
			char: (Machine uint16At: keyData + 2)
			shiftState: (Machine uint32At: keyData + 4)
			to: queue]
! !

!FirmwareKeyboard class methodsFor: 'translating'!
modifiersOf: shiftState
	"EFI_SHIFT_STATE_VALID, then right and left shift, control, alt, logo."
	| m |
	(shiftState bitAnd: 16r80000000) = 0 ifTrue: [^0].
	m := 0.
	(shiftState bitAnd: 3) ~= 0 ifTrue: [m := m bitOr: 1].
	(shiftState bitAnd: 16rC) ~= 0 ifTrue: [m := m bitOr: 2].
	(shiftState bitAnd: 16r30) ~= 0 ifTrue: [m := m bitOr: 8].
	(shiftState bitAnd: 16rC0) ~= 0 ifTrue: [m := m bitOr: 4].
	^m
!
keycodeOfScan: scan
	"The SDL keycode of an EFI scan code: up down right left home end insert delete pageUp pageDown F1..F12 escape; 0 if none."
	scan = 23 ifTrue: [^27].
	scan = 8 ifTrue: [^127].
	(scan between: 11 and: 22) ifTrue: [^16r4000003A + scan - 11].
	(scan between: 1 and: 10) ifTrue: [^#(16r40000052 16r40000051 16r4000004F 16r40000050 16r4000004A 16r4000004D 16r40000049 127 16r4000004B 16r4000004E) at: scan].
	^0
!
keyStroke: scan char: char shiftState: shiftState to: anInputQueue
	"Report a key stroke: ctrl-A .. ctrl-Z (but backspace, tab, return) as ctrl and the letter, a capital as shift and the letter; text for a character typed without ctrl or cmd."
	| mods code ch |
	mods := self modifiersOf: shiftState.
	ch := char.
	code := self keycodeOfScan: scan.
	code = 0 ifTrue: [
		((ch between: 1 and: 26) and: [(#(8 9 13) includes: ch) not]) ifTrue: [
			ch := ch + 96.
			mods := mods bitOr: 2].
		(ch between: $A value and: $Z value) ifTrue: [
			mods := mods bitOr: 1.
			code := ch + 32].
		code = 0 ifTrue: [code := ch]].
	code = 0 ifTrue: [^self].
	anInputQueue keyStroke: code modifiers: mods
		text: ((ch >= 32 and: [ch ~= 127 and: [(mods bitAnd: 10) = 0 and: [scan = 0]]])
			ifTrue: [(Character value: ch) asString]
			ifFalse: [nil])
! !

!FirmwareKeyboard class methodsFor: 'instance creation'!
firmware: aFirmware queue: anInputQueue
	^self new setFirmware: aFirmware queue: anInputQueue
! !
