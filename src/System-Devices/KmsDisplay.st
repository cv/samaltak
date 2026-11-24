FirmwareDisplay subclass: #KmsDisplay
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Devices'!

KmsDisplay comment: 'I am the windows and the input on Linux without a window system (the appliance, docs/linux-appliance.md), as FirmwareDisplay is on UEFI, and FirmwareDisplay current while I am asked for: SAMALTAK_SCREEN=kms (any DRM device with a connected output; kms:/dev/dri/cardN, that one). One window, the screen (KmsScreen: a dumb buffer on KMS, its size the display''s mode), at one pixel a point; the input from evdev (EvdevInput: every keyboard, mouse, touchpad, tablet and touch screen in /dev/input, also those plugged in later); the refresh a RefreshClock at the mode''s rate. The World draws with a SoftwareGPU (or --gpu nv, an NvComputeGPU) and presents through me: no SDL window, no SDL_GPU, no GPU userspace. A screen that cannot be opened (no DRM device, no connected output, another master) leaves the VM''s windows (SDL) to it, with a line on stderr.'!

!KmsDisplay methodsFor: 'initialization'!
setScreen: aKmsScreen
	screen := aKmsScreen.
	queue := InputQueue new.
	clock := RefreshClock new.
	devices := #().
	open := false
! !

!KmsDisplay methodsFor: 'devices'!
startDevices
	| input |
	input := EvdevInput display: self.
	devices := input start ifTrue: [{input}] ifFalse: [#()]
!
stop
	"Stop the input and the refresh, and give the screen back."
	super stop.
	screen stop.
	open := false
!
abandon
	super abandon.
	screen abandon
!
input
	"The EvdevInput, once the screen is open."
	^devices detect: [:d | d isKindOf: EvdevInput] ifNone: [nil]
! !

!KmsDisplay methodsFor: 'windows'!
openWindow: w height: h title: aString flags: flags
	"The screen, in its preferred mode (or the one of w x h that --window-size asked for)."
	open ifTrue: [^1].
	(screen start: w @ h) ifFalse: [^self error: 'no KMS screen on ', screen path, ': ', screen failure].
	queue extent: screen extent.
	open := true.
	self startDevices.
	^1
!
windowRefreshRate: window
	self check: window.
	^screen refreshRate
! !

!KmsDisplay class methodsFor: 'accessing'!
requested
	"A display on KMS if SAMALTAK_SCREEN asks for one and a DRM device has a connected output, else nil (with a line on stderr when it was asked for)."
	| spec screen |
	spec := Smalltalk vm getenv: 'SAMALTAK_SCREEN'.
	(spec notNil and: [spec beginsWith: 'kms']) ifFalse: [^nil].
	PosixDevice isAvailable ifFalse: [^nil].
	screen := KmsScreen choose: (spec size > 4 ifTrue: [{spec copyFrom: 5 to: spec size}] ifFalse: [self cards]).
	screen isNil ifTrue: [
		Smalltalk vm stderrWrite: 'Samaltak: SAMALTAK_SCREEN=', spec, ': no DRM device with a connected output: the VM''s windows instead', (String with: Character lf).
		^nil].
	^self new setScreen: screen
!
cards
	"The DRM devices' nodes (/dev/dri/card*)."
	^([Directory entries: '/dev/dri'] on: Error do: [:e | e return: #()])
		select: [:n | n beginsWith: 'card'] thenCollect: [:n | '/dev/dri/', n]
! !
