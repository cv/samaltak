!Process methodsFor: '*System-Debugging'!
interrupt
	"Stop me at my next safepoint with a UserInterrupt: like a halt there, so a debugger opens on me (if one is installed). I keep my place: proceeding continues where I was."
	self isActiveProcess ifTrue: [^UserInterrupt new signal].
	self signalException: UserInterrupt new
!
simulator
	"A Simulator for stepping my suspended stack from another process."
	self isActiveProcess ifTrue: [^self error: 'A process cannot step itself'].
	self isSuspended ifFalse: [^self error: 'Suspend the process before stepping it'].
	^Simulator onProcess: self
!
step
	"Execute one bytecode of my top context. Answer my new top context."
	^self simulator stepProcess
!
stepToSendOrReturn
	^self simulator stepToSendOrReturn
!
stepInto
	^self stepInto: suspendedContext
!
stepOver
	^self stepOver: suspendedContext
!
stepThrough
	^self stepThrough: suspendedContext
!
stepInto: aContext
	^self simulator stepInto: aContext
!
stepOver: aContext
	^self simulator stepOver: aContext
!
stepThrough: aContext
	^self simulator stepThrough: aContext
!
runToPc: anInteger in: aContext
	^self simulator runToPc: anInteger in: aContext
!
completeStep: aContext
	^self simulator completeStep: aContext
!
completeTo: aContext
	"Run me (simulated) until aContext is my top context again."
	^self simulator completeTo: aContext
!
popTo: aContext
	^self simulator popTo: aContext
!
return: value from: aContext
	^self simulator return: value from: aContext
!
restartContext: aContext
	^self simulator restart: aContext
!
calleeOf: aContext
	^self simulator calleeOf: aContext
! !
