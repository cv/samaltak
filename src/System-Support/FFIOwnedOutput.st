Object subclass: #FFIOwnedOutput
	instanceVariableNames: ''
	classVariableNames: 'Reserve Size Copy Release'
	package: 'System-Support'!

FFIOwnedOutput comment: 'Private to vetted FFI facades. I reserve native storage before exactly one producer invocation, copy its exact bytes into the image, and release the ticket even on unwind. The opaque integer is not an address.'!

!FFIOwnedOutput class methodsFor: 'capturing'!
captureUpTo: maxBytes do: producer
	"producer must return the result of one prepared i32 call, not translate it.
	Answer false only before producer entry, nil for absent, a negative operation
	status for failure, or an exact ByteArray (which may be empty)."
	| ticketBytes reserve size copy release status ticket count bytes |
	(maxBytes class == SmallInteger and: [maxBytes between: 0 and: 67108864])
		ifFalse: [^false].
	reserve := Reserve ifNil: [Reserve := PlatformFFI bind: #(call 'vm:core' 'ffi_owned_reserve' (u32 writableBytesWithLength) i32)].
	size := Size ifNil: [Size := PlatformFFI bind: #(call 'vm:core' 'ffi_owned_size' (u64) i32)].
	copy := Copy ifNil: [Copy := PlatformFFI bind: #(call 'vm:core' 'ffi_owned_copy' (u64 writableBytesWithLength) i32)].
	release := Release ifNil: [Release := PlatformFFI bind: #(call 'vm:core' 'ffi_owned_release' (u64) i32)].
	(reserve isNil or: [size isNil or: [copy isNil or: [release isNil]]]) ifTrue: [^false].
	ticketBytes := ByteArray new: 8.
	[
		(reserve tryInvoke2: maxBytes with: {ticketBytes. 1. 8}) = 1 ifFalse: [^false].
		ticket := FFIWire uint64At: 1 in: ticketBytes.
		status := producer value: ticket.
		status == false ifTrue: [^false].
		status = 0 ifTrue: [^nil].
		(status class == SmallInteger and: [status < 0]) ifTrue: [^status].
		status = 1 ifFalse: [^FFIError signal: 'Invalid owned producer status'].
		count := size tryInvoke1: ticket.
		(count class == SmallInteger and: [count between: 0 and: maxBytes])
			ifFalse: [^FFIError signal: 'Owned output unavailable after native entry'].
		bytes := ByteArray new: count.
		(copy tryInvoke2: ticket with: {bytes. 1. count}) = 1
			ifFalse: [^FFIError signal: 'Owned output copy failed after native entry'].
		^bytes
	] ensure: [
		"Read the ticket even if unwind interrupted us just after the reserve call."
		ticket := FFIWire uint64At: 1 in: ticketBytes.
		ticket = 0 ifFalse: [
			(release tryInvoke1: ticket) == false ifTrue: [
				FFIError signal: 'Owned output release rejected']]]
! !
