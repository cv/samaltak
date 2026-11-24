Object subclass: #FFIPagedPlatformOutput
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

!FFIPagedPlatformOutput class methodsFor: 'capturing'!
capture: producer
	"Invoke once. Answer false on refusal before entry, nil for absence, a
	negative native status on failure, or an exact ByteArray. Release any
	published token even if the producer or a page copy unwinds."
	<ffiSite>
	| receipt copy release status token count bytes offset page |
	receipt := ByteArray new: 16.
	copy := self ffiSite: #(call 'platform' 'platform_output_copy' (u64 u64 writableBytesWithLength) i32).
	release := self ffiSite: #(call 'platform' 'platform_output_release' (u64) i32).
	(copy prepare and: [release prepare]) ifFalse: [^false].
	[
		status := producer value: receipt.
		status == false ifTrue: [^false].
		status = 0 ifTrue: [^nil].
		status < 0 ifTrue: [^status].
		status = 1 ifFalse: [^FFIError signal: 'Invalid platform output status'].
		token := FFIWire uint64At: 1 in: receipt.
		count := FFIWire uint64At: 9 in: receipt.
		(count <= 16r7FFFFFFF8 and: [token > 0 or: [count = 0]])
			ifFalse: [^FFIError signal: 'Invalid platform output receipt'].
		bytes := ByteArray new: count.
		offset := 0.
		[offset < count] whileTrue: [
			page := 1048576 min: count - offset.
			(copy tryInvoke3: token with: offset with: {bytes. offset + 1. page}) = 1
				ifFalse: [^FFIError signal: 'Platform output copy failed'].
			offset := offset + page].
		^bytes
	] ensure: [
		token := FFIWire uint64At: 1 in: receipt.
		token = 0 ifFalse: [
			(release tryInvoke1: token) = 1 ifFalse: [
				FFIError signal: 'Platform output release refused']]]
! !
