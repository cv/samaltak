UefiModule subclass: #UefiMachine
	instanceVariableNames: 'common events watched watchedSems watchedCount timer lastCheckMs timerArch defaultTick fine'
	classVariableNames: 'UEFI_WAIT_MAX UEFI_WATCH_MAX'
	package: 'VM-UEFI'!

UefiMachine comment: 'The firmware for drivers written in Smalltalk (in place of PlatformMachine): the system table, calls of the firmware''s functions (efi:with:...), and up to UEFI_WATCH_MAX watched events: each signals its semaphore when the firmware signals it, found by UefiPlatform''s wait (WaitForEvent on them and a timer) and poll (CheckEvent, at most once a millisecond). fineTicks: makes the firmware''s timer interrupt (EFI_TIMER_ARCH_PROTOCOL), and so its timer events, tick every millisecond instead of every 10 ms while the NIC is busy (UefiPlatform).'!

!UefiMachine class methodsFor: 'declaring'!
declarations
	^#((common PlatformCommon) (events PlatformEvents) (watched 'void *[UEFI_WATCH_MAX]') (watchedSems 'int32_t[UEFI_WATCH_MAX]') (watchedCount int32_t)
		(timer 'void *') (lastCheckMs int64_t) (timerArch 'EfiTimerArch *') (defaultTick int64_t) (fine bool))
!
replaces
	^PlatformMachine
!
initialize
	"Events watched; waited for: those and a timer."
	UEFI_WATCH_MAX := 16.
	UEFI_WAIT_MAX := 17
! !

!UefiMachine methodsFor: 'firmware'!
firmwareSystemTable
	<function>
	<returns: 'uint64_t'>
	^self cCoerce: firmware systemTable to: 'uint64_t'
!
callFirmware: fn arguments: a count: n ok: ok
	<function>
	<var: #fn type: 'uint64_t'>
	<var: #a type: 'uint64_t *'>
	<var: #n type: 'int32_t'>
	<var: #ok type: 'bool *'>
	<returns: 'uint64_t'>
	ok value: true.
	n = 0 ifTrue: [^(self cCoerce: fn to: 'EfiFn0') call].
	n = 1 ifTrue: [^(self cCoerce: fn to: 'EfiFn1') call: (a at: 0)].
	n = 2 ifTrue: [^(self cCoerce: fn to: 'EfiFn2') call: (a at: 0) with: (a at: 1)].
	n = 3 ifTrue: [^(self cCoerce: fn to: 'EfiFn3') call: (a at: 0) with: (a at: 1) with: (a at: 2)].
	n = 4 ifTrue: [^(self cCoerce: fn to: 'EfiFn4') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3)].
	n = 5 ifTrue: [^(self cCoerce: fn to: 'EfiFn5') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4)].
	n = 6 ifTrue: [^(self cCoerce: fn to: 'EfiFn6') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5)].
	n = 7 ifTrue: [^(self cCoerce: fn to: 'EfiFn7') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6)].
	n = 8 ifTrue: [^(self cCoerce: fn to: 'EfiFn8') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7)].
	n = 9 ifTrue: [^(self cCoerce: fn to: 'EfiFn9') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7) with: (a at: 8)].
	n = 10 ifTrue: [^(self cCoerce: fn to: 'EfiFn10') call: (a at: 0) with: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7) with: (a at: 8) with: (a at: 9)].
	common setError: 'too many arguments'.
	ok value: false.
	^0
! !

!UefiMachine methodsFor: 'events'!
watchEvent: event semaphore: index
	"Watch event for semaphore index (0: no longer); answer whether there was room."
	<function>
	<var: #event type: 'uint64_t'>
	<var: #index type: 'int32_t'>
	<returns: 'bool'>
	| e i |
	e := self cCoerce: event to: 'void *'.
	i := 0.
	[i < watchedCount and: [(watched at: i) ~= e]] whileTrue: [i := i + 1].
	index = 0 ifTrue: [
		i < watchedCount ifTrue: [
			watchedCount := watchedCount - 1.
			watched at: i put: (watched at: watchedCount).
			watchedSems at: i put: (watchedSems at: watchedCount)].
		events updatePollInterval.
		^true].
	i = watchedCount ifTrue: [
		watchedCount = UEFI_WATCH_MAX ifTrue: [
			common setError: 'too many watched events'.
			^false].
		watchedCount := watchedCount + 1].
	watched at: i put: e.
	watchedSems at: i put: index.
	events updatePollInterval.
	^true
!
isWatching
	<function>
	<returns: 'bool'>
	^watchedCount > 0
!
pollWatched
	"Signal the semaphores of the watched events the firmware signaled (CheckEvent), at most once a millisecond."
	<function>
	| now |
	watchedCount = 0 ifTrue: [^self].
	now := common nowMs.
	now = lastCheckMs ifTrue: [^self].
	lastCheckMs := now.
	0 to: watchedCount - 1 do: [:i |
		(self efiFailed: (self efi: self boot checkEvent with: (watched at: i))) ifFalse: [
			scheduler signalExternalSemaphore: (watchedSems at: i)]]
!
wait: us
	"Until a watched event or us microseconds (no timeout if negative); signal the semaphore of the event that ended it."
	<function>
	<var: #us type: 'int64_t'>
	| events n index |
	timer isNull ifTrue: [
		events := self local: 'void *'.
		(self efiFailed: (self efi: self boot createEvent with: EFI_EVT_TIMER with: 0 with: self null with: self null with: events))
			ifFalse: [timer := events value]].
	events := self local: 'void *[UEFI_WAIT_MAX]'.
	n := 0.
	0 to: watchedCount - 1 do: [:i |
		events at: n put: (watched at: i).
		n := n + 1].
	(timer notNull and: [us >= 0]) ifTrue: [
		self efi: self boot setTimer with: timer with: EFI_TIMER_RELATIVE with: (us * 10) + 1.
		events at: n put: timer.
		n := n + 1].
	n = 0 ifTrue: [^self].
	index := self local: 'uint64_t'.
	(self efiFailed: (self efi: self boot waitForEvent with: n with: events with: index)) ifTrue: [^self].
	index value < watchedCount asUInt64 ifTrue: [scheduler signalExternalSemaphore: (watchedSems at: index value)]
!
fineTicks: on
	"The firmware's timer interrupt every millisecond (on), or at its own period again; answer whether it ticks every millisecond now (not without EFI_TIMER_ARCH_PROTOCOL). Then a wait: of 1 lasts until the next tick, and the CPU halts meanwhile."
	<function>
	<var: #on type: 'bool'>
	<returns: 'bool'>
	| guid p period |
	on = fine ifTrue: [^fine].
	defaultTick = 0 ifTrue: [
		defaultTick := -1.
		guid := self local: 'EfiGuid'.
		firmware guid: guid data1: 16r26BACCB3 data2: 16r6F42 data3: 16r11D4 data4: 16rBCE70080C73C8881.
		p := self local: 'void *'.
		((self efiFailed: (self efi: self boot locateProtocol with: guid with: self null with: p)) not and: [p value notNull]) ifTrue: [
			timerArch := self cCoerce: p value to: 'EfiTimerArch *'.
			period := self local: 'uint64_t'.
			(self efiFailed: (self efi: timerArch getTimerPeriod with: timerArch with: period)) ifFalse: [defaultTick := period value asInt64]]].
	defaultTick <= 0 ifTrue: [^false].
	defaultTick > 10000 ifTrue: [
		(self efiFailed: (self efi: timerArch setTimerPeriod with: timerArch with: (on ifTrue: [10000] ifFalse: [defaultTick]))) ifTrue: [^false]].
	fine := on.
	^fine
! !

VMStruct subclass: #EfiTimerArch
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiTimerArch comment: 'EFI_TIMER_ARCH_PROTOCOL (PI 1.8, volume 2, 12.10): the timer interrupt that drives the firmware''s timer events (periods in 100 ns).'!

!EfiTimerArch class methodsFor: 'declaring'!
fields
	^#((registerHandler 'void *') (setTimerPeriod 'void *') (getTimerPeriod 'void *') (generateSoftInterrupt 'void *'))
! !
