!SystemDictionary methodsFor: 'startup'!
bootstrapStartUp
	"The guest starts here, in the bootstrap process: initialize the classes that need it and run the desk. The image builder's hash tables are already laid out as the kernel's (the same hash, the same probing), so nothing is rehashed."
	self at: #Transcript put: TranscriptView new.
	VMConstants initialize.
	Float initialize.
	Process initialize.
	ScreenController open
! !

!SystemDictionary methodsFor: 'vm'!
vmBanner
	<primitive: 'vmBanner'>
	^self primitiveFailed
!
quit: exitCode
	<primitive: 'quit'>
	^self primitiveFailed
! !

!SystemDictionary methodsFor: 'error handling'!
handleUnhandledError: anException
	"UnhandledError's default action: say so on the Transcript and stop the process, unless it is the desk's (whose loop goes on)."
	| desk |
	Transcript show: 'Unhandled ' , anException class name , ': ' , anException messageText; cr.
	desk := ScreenController current.
	(desk notNil and: [desk process == Processor activeProcess]) ifFalse: [Processor activeProcess terminate].
	^nil
!
handleWarning: aWarning
	Transcript show: 'Warning: ' , aWarning messageText; cr.
	^nil
! !
