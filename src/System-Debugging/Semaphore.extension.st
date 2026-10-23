!Semaphore methodsFor: '*System-Debugging'!
simulatorPrimSignal
	"The signal primitive, for the Simulator (which must not run an overriding signal method)."
	<primitive: 'semaphoreSignal'>
	^self primitiveFailed
! !
