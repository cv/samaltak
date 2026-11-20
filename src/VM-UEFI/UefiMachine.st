UefiModule subclass: #UefiMachine
	instanceVariableNames: 'common events watched watchedSems watchedCount timer lastCheckMs'
	classVariableNames: 'UEFI_WAIT_MAX UEFI_WATCH_MAX'
	package: 'VM-UEFI'!

UefiMachine comment: 'The firmware for drivers written in Smalltalk (in place of PlatformMachine): the system table, calls of the firmware''s functions (efi:with:...), and up to UEFI_WATCH_MAX watched events: each signals its semaphore when the firmware signals it, found by UefiPlatform''s wait (WaitForEvent on them and a timer) and poll (CheckEvent, at most once a millisecond).'!

!UefiMachine class methodsFor: 'declaring'!
declarations
	^#((common PlatformCommon) (events PlatformEvents) (watched 'void *[UEFI_WATCH_MAX]') (watchedSems 'int32_t[UEFI_WATCH_MAX]') (watchedCount int32_t)
		(timer 'void *') (lastCheckMs int64_t))
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
! !
