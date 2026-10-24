Object subclass: #StandIn
	instanceVariableNames: 'owner process'
	classVariableNames: ''
	package: 'UI-Windows'!

StandIn comment: 'I stand in for one of the window system''s own Processes, the InputDispatcher''s or the Compositor''s, while a debugger holds it suspended (DebugSession process listeners, see World>>debugged:changed:): a fresh Process at the same priority running the same object''s loop with the same state, so input (remote control included) and drawing go on. Breakpoints and watchpoints, targeted ones too, are ignored in my Process: they would stop the stand-in as well. When the original resumes, I retire before my next turn; when it is abandoned (terminated), my Process becomes the owner''s.

My owner understands process, process:, standIn:, processName and runStandIn.'!

!StandIn methodsFor: 'accessing'!
owner
	^owner
!
process
	^process
! !

!StandIn methodsFor: 'running'!
start
	process := [Breakpoint ignoreDuring: [owner runStandIn]] newProcess.
	process priority: owner process priority; name: owner processName, ' (stand-in)'.
	process resume
!
retire
	"The original runs again: my loop ends before its next turn."
	owner standIn: nil
!
adopt
	"The original was terminated: my Process is the owner's from now on (breakpoints still ignore it)."
	owner standIn: nil; process: process.
	process name: owner processName
!
terminate
	process isNil ifFalse: [process terminate]
! !

!StandIn class methodsFor: 'instance creation'!
for: anOwner
	"Start a stand-in for anOwner's suspended Process and answer it."
	^self new setOwner: anOwner; start; yourself
! !

!StandIn methodsFor: 'private'!
setOwner: anObject
	owner := anObject
! !
