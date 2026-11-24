!PlatformFiles methodsFor: 'owned names'!
ownedNamesRoom: receipt capacity: cap
	"One result per fresh receipt, no limit on names in that result. VM thread only."
	<function>
	<var: #receipt type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'pf_owned_names *'>
	| nonce row |
	cap ~= 12 ifTrue: [^self null].
	0 to: 11 do: [:i | (receipt at: i) ~= 0 ifTrue: [^self null]].
	ownedNamesSession = 0 ifTrue: [
		nonce := self local: 'uint64_t'.
		(posix getEntropy: nonce size: 8) ~= 0 ifTrue: [^self null].
		ownedNamesSession := nonce value bitAnd: 16r3FFFFFFFFFFFFFFF asUInt64.
		ownedNamesSession = 0 ifTrue: [^self null]].
	ownedNamesSerial >= 16r3FFFFFFFFFFFFFFE asUInt64 ifTrue: [^self null].
	0 to: PF_OWNED_NAMES - 1 do: [:i |
		row := ownedNames + i.
		row ticket = 0 ifTrue: [^row]].
	common setError: 'too many outstanding file name results'.
	^self null
!
ownedNamesPublish: row names: names count: count receipt: out
	"Adopt the whole native vector. Write the ticket so image unwind can release it even before seeing the return status."
	<function>
	<var: #row type: 'pf_owned_names *'>
	<var: #names type: 'char **'>
	<var: #count type: 'uint32_t'>
	<var: #out type: 'uint8_t *'>
	| ticket |
	ownedNamesSerial := ownedNamesSerial + 1.
	ownedNamesSerial = ownedNamesSession ifTrue: [ownedNamesSerial := ownedNamesSerial + 1].
	ticket := ownedNamesSession bitXor: ownedNamesSerial.
	row count: count.
	row names: names.
	row ticket: ticket.
	0 to: 3 do: [:i | out at: i + 8 put: (count >> (i * 8)) asUInt8].
	0 to: 7 do: [:i | out at: i put: (ticket >> (i * 8)) asUInt8]
!
ownedNamesRow: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'pf_owned_names *'>
	| row |
	ticket = 0 ifTrue: [^self null].
	0 to: PF_OWNED_NAMES - 1 do: [:i |
		row := ownedNames + i.
		row ticket = ticket ifTrue: [^row]].
	^self null
!
ownedName: ticket at: index
	<function>
	<var: #ticket type: 'uint64_t'>
	<var: #index type: 'uint32_t'>
	<returns: 'const char *'>
	| row |
	row := self ownedNamesRow: ticket.
	(row isNull or: [index >= row count]) ifTrue: [^self null].
	^row names at: index
!
releaseOwnedNames: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	| row names |
	row := self ownedNamesRow: ticket.
	row isNull ifTrue: [^0].
	names := row names.
	0 to: row count asInt64 - 1 do: [:i | libc free: (names at: i)].
	libc free: names.
	row ticket: 0.
	row names: self null.
	row count: 0.
	^1
! !
