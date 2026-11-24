PlatformInterface subclass: #UefiPlatform
	instanceVariableNames: 'machine nic'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiPlatform comment: 'The platform on UEFI (in place of SDLPlatform and HeadlessPlatform). The image drives the screen and the input devices (System-Devices) through the machine primitives; the VM only polls and waits. Polling checks the firmware events the image watches (UefiMachine) and the NIC; waiting waits for a watched event or the timeout, whichever comes first (at most 10 ms while the image waits for frames: the NIC signals nothing the firmware waits for; while a frame that went out awaits its reply, the NIC is polled without pause: UefiSnp>>spin:coarse:; while frames come and go, the firmware''s timer ticks every millisecond and a wait lasts until its next tick: UefiMachine>>fineTicks:, UefiSnp>>isBusy; without a timer to set, the NIC is polled without pause then too).'!

!UefiPlatform class methodsFor: 'declaring'!
declarations
	^#((machine UefiMachine) (nic UefiSnp))
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiPlatform methodsFor: 'platform'!
init
	<export>
!
poll
	<export>
	machine pollWatched.
	nic poll
!
wait: timeoutUs
	<export>
	| us busy fine |
	us := timeoutUs.
	(nic wantsPolling and: [us < 0 or: [us > 10000]]) ifTrue: [us := 10000].
	busy := nic isBusy.
	fine := machine fineTicks: busy.
	"poll without pause while a reply is due, else until the next tick"
	us ~= 0 ifTrue: [us := nic spin: us coarse: fine not].
	(us ~= 0 and: [busy and: [fine]]) ifTrue: [us := 1].
	(us < 0 and: [machine isWatching not]) ifTrue: [self fatal: 'deadlock: no runnable process and no pending timer'].
	us ~= 0 ifTrue: [machine wait: us].
	machine pollWatched.
	nic poll
!
shutdown
	<export>
!
quitStatus: code
	<export>
	<var: #code type: 'int'>
	<returns: 'int'>
	^code
!
ffiTarget: id
	<export>
	<var: #id type: 'int32_t'>
	<returns: 'uint64_t'>
	^0
!
ffiApprovedPlatform: approvedName signature: signature into: targetOut
	<export>
	<var: #approvedName type: 'const char *'>
	<var: #signature type: 'const uint8_t *'>
	<var: #targetOut type: 'uint64_t *'>
	<returns: 'int32_t'>
	^0
! !
