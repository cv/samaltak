!FFIPrimitives methodsFor: 'owned output registry'!
ownedReserve: capacity ticketBytes: out length: length
	"Write the opaque ticket last. Image ensure: can release it even if the process is terminated before it sees our return."
	<function>
	<approvedFFI: 4000 symbol: 'ffi_owned_reserve' arguments: #(2 9) result: 1>
	<var: #capacity type: 'uint32_t'>
	<var: #out type: 'uint8_t *'>
	<var: #length type: 'uint64_t'>
	<returns: 'int32_t'>
	| row nonce ticket |
	length = 8 ifFalse: [^0].
	"Reject a nonfresh ticket buffer; leave the existing ticket available to its owner."
	0 to: 7 do: [:i | (out at: i) ~= 0 ifTrue: [^0]].
	capacity > (FFI_OWNED_BYTE_LIMIT asUInt32 - ownedReserved) ifTrue: [^0].
	row := self ownedRow: 0 asUInt64.
	row isNull ifTrue: [^0].
	ownedSession = 0 ifTrue: [
		nonce := self local: 'uint64_t'.
		(posix getEntropy: nonce size: 8) ~= 0 ifTrue: [^0].
		ownedSession := nonce value bitAnd: VM_INT_MAX asUInt64.
		ownedSession = 0 ifTrue: [^0]].
	"Never recycle a generation, even after cancellation. The random process mask separates restored images."
	ownedSerial = VM_INT_MAX asUInt64 ifTrue: [^0].
	ownedSerial := ownedSerial + 1.
	ownedSerial = ownedSession ifTrue: [
		ownedSerial = VM_INT_MAX asUInt64 ifTrue: [^0].
		ownedSerial := ownedSerial + 1].
	ticket := ownedSession bitXor: ownedSerial.
	row capacity: capacity.
	row state: 0.
	row ticket: ticket.
	ownedReserved := ownedReserved + capacity.
	0 to: 7 do: [:i | out at: i put: (ticket >> (8 * i)) asUInt8].
	^1
!
ownedSize: ticket
	<function>
	<approvedFFI: 4001 symbol: 'ffi_owned_size' arguments: #(4) result: 1>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	| row |
	ticket = 0 ifTrue: [^-1].
	row := self ownedRow: ticket.
	(row isNull or: [row state ~= 2]) ifTrue: [^-1].
	^row payloadBytes asInt32
!
ownedCopy: ticket into: out length: length
	<function>
	<approvedFFI: 4002 symbol: 'ffi_owned_copy' arguments: #(4 9) result: 1>
	<var: #ticket type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #length type: 'uint64_t'>
	<returns: 'int32_t'>
	| row |
	ticket = 0 ifTrue: [^0].
	row := self ownedRow: ticket.
	(row isNull or: [row state ~= 2 or: [length ~= row payloadBytes asUInt64]]) ifTrue: [^0].
	length ~= 0 ifTrue: [libc memcpy: out from: row bytes size: length].
	^1
!
ownedRelease: ticket
	<function>
	<approvedFFI: 4003 symbol: 'ffi_owned_release' arguments: #(4) result: 1>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	| row |
	ticket = 0 ifTrue: [^0].
	row := self ownedRow: ticket.
	row isNull ifTrue: [^0].
	self ownedClear: row.
	^1
! !

!FFIPrimitives methodsFor: 'owned output producers'!
ownedCanProduce: ticket
	"Claim before calling a side-effecting backend. Even an absent or failed result consumes this claim."
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'bool'>
	| row |
	ticket = 0 ifTrue: [^false].
	row := self ownedRow: ticket.
	(row isNull or: [row state ~= 0]) ifTrue: [^false].
	row state: 1.
	^true
!
ownedPublish: ticket from: bytes size: size
	"Clone exactly size bytes. The producer still owns bytes, including when this fails."
	<function>
	<var: #ticket type: 'uint64_t'>
	<var: #bytes type: 'const uint8_t *'>
	<var: #size type: 'uint64_t'>
	<returns: 'bool'>
	| row copy |
	ticket = 0 ifTrue: [^false].
	row := self ownedRow: ticket.
	(row isNull or: [row state ~= 1 or: [size > row capacity asUInt64]]) ifTrue: [^false].
	size = 0 ifTrue: [^self ownedAdopt: ticket from: self null size: 0 asUInt64 capacity: 0 asUInt64].
	bytes isNull ifTrue: [^false].
	copy := self cCoerce: (libc malloc: size) to: 'uint8_t *'.
	copy isNull ifTrue: [^false].
	libc memcpy: copy from: bytes size: size.
	(self ownedAdopt: ticket from: copy size: size capacity: size) ifTrue: [^true].
	libc free: copy.
	^false
!
ownedAdopt: ticket from: allocation size: size capacity: capacity
	"Transfer an exclusive libc allocation (base pointer, actual allocated bytes). No cleanup callback or image pointer."
	<function>
	<var: #ticket type: 'uint64_t'>
	<var: #allocation type: 'uint8_t *'>
	<var: #size type: 'uint64_t'>
	<var: #capacity type: 'uint64_t'>
	<returns: 'bool'>
	| row |
	(ticket = 0 or: [size > capacity or: [capacity = 0 ifTrue: [allocation notNull] ifFalse: [allocation isNull]]])
		ifTrue: [^false].
	row := self ownedRow: ticket.
	(row isNull or: [row state ~= 1 or: [capacity > row capacity asUInt64]]) ifTrue: [^false].
	row bytes: allocation.
	row payloadBytes: size asUInt32.
	row state: 2.
	^true
! !

!FFIPrimitives methodsFor: 'owned output private'!
ownedRow: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'FFIOwnedRow *'>
	| row |
	0 to: FFI_OWNED_LIMIT - 1 do: [:i |
		row := ownedRows + i.
		row ticket = ticket ifTrue: [^row]].
	^self null
!
ownedClear: row
	<function>
	<var: #row type: 'FFIOwnedRow *'>
	row bytes notNull ifTrue: [libc free: row bytes].
	ownedReserved := ownedReserved - row capacity.
	row bytes: self null.
	row payloadBytes: 0.
	row capacity: 0.
	row ticket: 0
! !
