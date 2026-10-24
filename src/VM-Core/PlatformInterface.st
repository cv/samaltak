VMCoreModule subclass: #PlatformInterface
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

PlatformInterface comment: 'What the core needs from a platform layer: start up, poll at interrupt checks, wait while idle, shut down. HeadlessPlatform implements it in the core; VM-Platform''s SDL layer instead. The build links one (the C names are the same); a simulation connects one.'!

!PlatformInterface class methodsFor: 'declaring'!
isAbstractModule
	^self == PlatformInterface
!
isInterface
	^self == PlatformInterface
! !

!PlatformInterface methodsFor: 'platform'!
init
	"At startup unless --headless."
	<c: 'void platform_init(void)'>
	self subclassResponsibility
!
poll
	"At interrupt checks."
	<c: 'void platform_poll(void)'>
	self subclassResponsibility
!
wait: timeoutUs
	"Idle wait; < 0 = forever."
	<c: 'void platform_wait(int64_t timeout_us)'>
	self subclassResponsibility
!
shutdown
	"At quit."
	<c: 'void platform_shutdown(void)'>
	self subclassResponsibility
! !

PlatformInterface subclass: #HeadlessPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

HeadlessPlatform comment: 'The platform of a VM without windows: waiting sleeps; nothing to poll.'!

!HeadlessPlatform methodsFor: 'platform'!
init
	<c: 'void platform_init(void)'>
	<export>
!
poll
	<c: 'void platform_poll(void)'>
	<export>
!
wait: timeoutUs
	<c: 'void platform_wait(int64_t timeout_us)'>
	<export>
	timeoutUs < 0 ifTrue: [self fatal: 'deadlock: no runnable process and no pending timer'].
	posix usleep: (timeoutUs > 1000000 ifTrue: [1000000] ifFalse: [timeoutUs]) asUInt32
!
shutdown
	<c: 'void platform_shutdown(void)'>
	<export>
! !
