Object subclass: #UIWindows
	instanceVariableNames: ''
	classVariableNames: 'StartupAction'
	package: 'UI-Windows'!

UIWindows comment: 'I start the window system. A normal start of the image (no --stage2, --test or --eval) runs my main action: unless --headless, open the host window (1440×900 points, or --window-size WxH; --hidden keeps it offscreen), start the World with its Compositor and InputDispatcher, register the World with remote control when the control server runs (--control), and run the startup action (set by the Demos or the Tools package: UIWindows startupAction: [...]).

	UIWindows startUp          "open the World now (answers it)"
	UIWindows startupAction: [World current ...]'!

!UIWindows class methodsFor: 'class initialization'!
initialize
	Smalltalk mainAction: [self runMainAction].
	Smalltalk addToStartUpList: self
!
startUp: resuming
	"A World saved in the image lost its processes and handles."
	resuming ifTrue: [
		World current isNil ifFalse: [World current abandon]]
! !

!UIWindows class methodsFor: 'starting'!
runMainAction
	"The kernel's main action. The World runs in its own Processes, so the main Process ends after the startup action."
	Smalltalk isHeadless ifTrue: [^self runHeadless].
	self startUp.
	self runStartupAction
!
runHeadless
	"No display: keep serving remote control if it runs, else explain and quit."
	ControlServer current isNil ifFalse: [^Semaphore new wait].
	Transcript show: 'Samaltak: headless and nothing to do (use --test, --eval <expression> or --control)'; cr.
	Smalltalk quit: 0
!
startUp
	"Open the host window and the World; answer the World."
	| world |
	World current isNil ifFalse: [^World current].
	world := World openExtent: self windowSize hidden: self isHidden.
	ControlServer current isNil ifFalse: [UIRemote installOn: world].
	^world
!
runStartupAction
	[StartupAction isNil ifFalse: [StartupAction value]]
		on: Error do: [:e |
			Transcript show: 'Startup action failed: ', e messageText asString; cr.
			World current isNil ifFalse: [World current toast: 'Startup action failed: ', e messageText asString].
			e return: nil]
!
startupAction
	^StartupAction
!
startupAction: aBlock
	"What runs after the World opened."
	StartupAction := aBlock
!
windowSize
	"--window-size WxH, default 1440x900 points."
	| arg x |
	arg := Smalltalk argumentAfter: '--window-size'.
	arg isNil ifTrue: [^1440 @ 900].
	x := arg indexOf: $x.
	x = 0 ifTrue: [^1440 @ 900].
	^(Integer readFrom: (arg copyFrom: 1 to: x - 1) ifFail: [1440]) @ (Integer readFrom: (arg copyFrom: x + 1 to: arg size) ifFail: [900])
!
isHidden
	^Smalltalk vm arguments includes: '--hidden'
! !
