Object subclass: #PlatformFFI
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

PlatformFFI comment: 'Private downcalls for platform facades. Cache successful bindings at their call sites and use a fixed-arity tryInvoke method. Use the legacy primitive only when bind: answers nil or invocation answers false. Native results (including zero or nil) never trigger fallback.'!

!PlatformFFI class methodsFor: 'binding'!
bind: descriptor
	"Bind a platform facade's literal call descriptor. Answer nil if it is unavailable."
	^FFI tryBindCall: descriptor
! !
