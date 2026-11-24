VMSimulation subclass: #VMGuestSimulation
	instanceVariableNames: 'display exchange'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

Scheduler subclass: #VMGuestScheduler
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

HeadlessPlatform subclass: #VMGuestPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

VMGuestSimulation comment: 'An explicitly attached image simulation. I substitute simulated scheduler and platform implementations to start the mailbox exchange at boot and poll it at the existing interrupt boundary. The display endpoint only receives host copies of complete frames and supplies input; it never accesses the guest heap.'!

!VMGuestSimulation class methodsFor: 'instance creation'!
modules: aCollectionOfClasses display: anEndpoint
	anEndpoint ifNil: [^VMSimulation modules: aCollectionOfClasses].
	^(self modules: aCollectionOfClasses)
		display: anEndpoint;
		yourself
! !

!VMGuestSimulation methodsFor: 'initialization'!
simulationClassFor: aModuleClass
	aModuleClass == HeadlessPlatform ifTrue: [^VMGuestPlatform].
	aModuleClass == Scheduler ifTrue: [^VMGuestScheduler].
	^super simulationClassFor: aModuleClass
!
display: anEndpoint
	display := anEndpoint
!
startGuestExchange
	display ifNil: [^self].
	exchange := GuestImageMailbox simulation: self display: display.
	exchange attach ifFalse: [exchange := nil]
! !

!VMGuestSimulation methodsFor: 'running'!
runMain: aModuleClass arguments: anArrayOfStrings
	^[super runMain: aModuleClass arguments: anArrayOfStrings] ensure: [
		exchange ifNotNil: [
			exchange := nil.
			(self module: Scheduler) requestPeriodicPoll: 0]]
!
hasGuestExchange
	^exchange notNil
!
pollGuestDisplay
	exchange ifNotNil: [exchange poll]
! !

!VMGuestScheduler methodsFor: 'simulation'!
init
	super init.
	"The image is relocated and the ticker is running; no guest code has run yet."
	sim startGuestExchange.
	sim hasGuestExchange ifTrue: [self requestPeriodicPoll: GuestImageMailbox pollMicroseconds]
! !

!VMGuestPlatform methodsFor: 'simulation'!
poll
	sim pollGuestDisplay
!
wait: timeoutUs
	| interval |
	sim hasGuestExchange ifFalse: [^super wait: timeoutUs].
	"The scheduler polls immediately after this wait; respect earlier guest timers."
	interval := GuestImageMailbox pollMicroseconds.
	super wait: (timeoutUs < 0 ifTrue: [interval] ifFalse: [timeoutUs min: interval])
! !
