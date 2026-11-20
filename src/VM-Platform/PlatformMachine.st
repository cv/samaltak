VMPlatformModule subclass: #PlatformMachine
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformMachine comment: 'The firmware, for drivers written in Smalltalk (the machine primitives of PlatformPrimitives): its system table, calls of its functions by address, and its events, which wake the VM''s wait and signal semaphores. On an operating system there is no firmware: every function fails. VM-UEFI''s UefiMachine replaces me.'!

!PlatformMachine methodsFor: 'firmware'!
firmwareSystemTable
	"The firmware's system table; 0 (the error set) if there is none."
	<function>
	<returns: 'uint64_t'>
	common setError: 'no firmware'.
	^0
!
callFirmware: fn arguments: args count: n ok: ok
	"The result of the firmware function at fn called with the n words args (n <= 10) in the firmware's calling convention."
	<function>
	<var: #fn type: 'uint64_t'>
	<var: #args type: 'uint64_t *'>
	<var: #n type: 'int32_t'>
	<var: #ok type: 'bool *'>
	<returns: 'uint64_t'>
	common setError: 'no firmware'.
	ok value: false.
	^0
!
watchEvent: event semaphore: index
	"Signal external semaphore index whenever the firmware event at event is signaled (0: no longer)."
	<function>
	<var: #event type: 'uint64_t'>
	<var: #index type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'no firmware'.
	^false
! !
