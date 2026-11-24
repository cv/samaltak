VMPlatformModule subclass: #PlatformPagedOutput
	instanceVariableNames: 'rows session serial'
	classVariableNames: 'MAX_PAGED_OUTPUTS'
	package: 'VM-Platform'!

!PlatformPagedOutput class methodsFor: 'declaring'!
declarations
	^#((rows 'pf_output_lease[MAX_PAGED_OUTPUTS]') (session uint64_t) (serial uint64_t))
!
initialize
	MAX_PAGED_OUTPUTS := 16
! !

!PlatformPagedOutput methodsFor: 'paged output'!
roomFor: out capacity: cap
	"Per-process leases, bound only the number of live results, not their aggregate bytes."
	<function>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'pf_output_lease *'>
	| nonce row |
	cap ~= 16 ifTrue: [
		common setError: 'wrong platform output receipt size'.
		^self null].
	0 to: 15 do: [:i | (out at: i) ~= 0 ifTrue: [
		common setError: 'platform output requires a fresh receipt'.
		^self null]].
	session = 0 ifTrue: [
		nonce := self local: 'uint64_t'.
		((posix getEntropy: nonce size: 8) = 0 and: [
			(nonce value bitAnd: 16r3FFFFFFFFFFFFFFF asUInt64) ~= 0]) ifFalse: [
			common setError: 'cannot initialize platform output tickets'.
			^self null].
		session := nonce value bitAnd: 16r3FFFFFFFFFFFFFFF asUInt64].
	serial >= 16r3FFFFFFFFFFFFFFE asUInt64 ifTrue: [
		common setError: 'platform output ticket space exhausted'.
		^self null].
	0 to: MAX_PAGED_OUTPUTS - 1 do: [:i |
		row := rows + i.
		row ticket = 0 ifTrue: [^row]].
	common setError: 'too many outstanding platform outputs'.
	^self null
!
adopt: row bytes: payload count: n receipt: out
	<function>
	<var: #row type: 'pf_output_lease *'>
	<var: #payload type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<returns: 'bool'>
	| ticket |
	n > 16r7FFFFFFF8 asUInt64 ifTrue: [
		common setError: 'platform output cannot fit a ByteArray'.
		^false].
	serial := serial + 1.
	serial = session ifTrue: [serial := serial + 1].
	ticket := session bitXor: serial.
	row payload: payload.
	row payloadBytes: n.
	row ticket: ticket.
	0 to: 7 do: [:i | out at: i + 8 put: (n >> (i * 8)) asUInt8].
	0 to: 7 do: [:i | out at: i put: (ticket >> (i * 8)) asUInt8].
	^true
!
rowFor: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'pf_output_lease *'>
	| row |
	ticket = 0 ifTrue: [^self null].
	0 to: MAX_PAGED_OUTPUTS - 1 do: [:i |
		row := rows + i.
		row ticket = ticket ifTrue: [^row]].
	^self null
!
copy: ticket offset: offset into: out capacity: cap
	<function>
	<var: #ticket type: 'uint64_t'>
	<var: #offset type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'bool'>
	| row |
	row := self rowFor: ticket.
	(row isNull or: [cap > 1048576 or: [offset > row payloadBytes or: [
		cap > (row payloadBytes - offset)]]]) ifTrue: [
		common setError: 'invalid platform output page'.
		^false].
	cap ~= 0 ifTrue: [libc memcpy: out from: row payload + offset size: cap].
	^true
!
clear: row
	<function>
	<var: #row type: 'pf_output_lease *'>
	libc free: row payload.
	row ticket: 0.
	row payload: self null.
	row payloadBytes: 0
!
release: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'bool'>
	| row |
	row := self rowFor: ticket.
	row isNull ifTrue: [^false].
	self clear: row.
	^true
!
discard
	<function>
	| row |
	0 to: MAX_PAGED_OUTPUTS - 1 do: [:i |
		row := rows + i.
		row ticket ~= 0 ifTrue: [self clear: row]]
! !
