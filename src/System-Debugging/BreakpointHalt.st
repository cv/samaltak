Halt subclass: #BreakpointHalt
	instanceVariableNames: 'breakpoint context'
	classVariableNames: ''
	package: 'System-Debugging'!

BreakpointHalt comment: 'I am signaled when a Breakpoint stops a process. context is the activation of the breakpointed method; proceeding continues it.'!

!BreakpointHalt methodsFor: 'accessing'!
breakpoint
	^breakpoint
!
breakpoint: aBreakpoint
	breakpoint := aBreakpoint
!
context
	"The activation of the method that hit the breakpoint."
	^context
!
context: aContext
	context := aContext
!
description
	^'Breakpoint'
! !
