Object subclass: #PlatformFFI
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

PlatformFFI comment: 'Private downcalls for platform facades. Cache successful bindings at their call sites. Use the legacy primitive only when bind: answers nil or the binding''s tryInvoke: answers false. The VM revalidates each invocation; native results (including zero or nil) never trigger fallback.'!

!PlatformFFI class methodsFor: 'binding'!
bind: descriptor
	"Bind a platform facade's literal call descriptor. Answer nil if it is unavailable."
	^FFI tryBindCall: descriptor
! !
