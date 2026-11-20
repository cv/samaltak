Object subclass: #Machine
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Devices'!

Machine comment: 'I am the machine as drivers in Smalltalk see it (the machine primitives, docs/platform.md): memory by address (bytes, words, copies to and from objects), memory outside the object heap that never moves (allocate:, free:; on UEFI physical memory a device can read at its address), the CPU''s barrier, and the firmware: its system table, calls of its functions by address in its calling convention, and its events, which signal a Semaphore (watch:semaphoreIndex:). On an operating system there is no firmware (hasFirmware is false) and those fail; the memory works everywhere.

Addresses are Integers; a word read is unsigned. Misused, I crash the VM like a driver in C would.'!

!Machine class methodsFor: 'firmware'!
systemTable
	"The address of the firmware's system table, or nil without a firmware."
	<primitive: 'machineSystemTable'>
	^nil
!
hasFirmware
	"Does the image drive the machine itself (UEFI) rather than run on an operating system?"
	^self systemTable notNil
!
call: fn
	"The word the firmware function at the address fn answers."
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d with: e
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d with: e with: f
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d with: e with: f with: g
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d with: e with: f with: g with: h
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d with: e with: f with: g with: h with: i
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
call: fn with: a with: b with: c with: d with: e with: f with: g with: h with: i with: j
	<primitive: 'machineCall'>
	^self error: 'no firmware'
!
watch: event semaphoreIndex: anInteger
	"Signal the external semaphore anInteger whenever the firmware signals event (the address of a wait event); 0 stops."
	<primitive: 'machineWatch'>
	^self error: 'cannot watch the event'
! !

!Machine class methodsFor: 'memory'!
read: address size: n
	"The unsigned Integer of n bytes (1, 2, 4, 8) at address."
	<primitive: 'machineRead'>
	^self error: 'bad address'
!
write: address size: n value: anInteger
	<primitive: 'machineWrite'>
	^self error: 'bad address'
!
uint8At: address
	^self read: address size: 1
!
uint16At: address
	^self read: address size: 2
!
uint32At: address
	^self read: address size: 4
!
uint64At: address
	^self read: address size: 8
!
int32At: address
	| v |
	v := self read: address size: 4.
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
!
uint8At: address put: anInteger
	^self write: address size: 1 value: anInteger
!
uint16At: address put: anInteger
	^self write: address size: 2 value: anInteger
!
uint32At: address put: anInteger
	^self write: address size: 4 value: anInteger
!
uint64At: address put: anInteger
	^self write: address size: 8 value: anInteger
!
copy: count from: source at: sourceOffset to: destination at: destinationOffset
	"count bytes; source and destination are addresses or byte objects (Bitmaps), the offsets 0-based."
	<primitive: 'machineCopy'>
	^self error: 'bad copy'
!
bytesAt: address count: n
	"A new ByteArray of the n bytes at address."
	| b |
	b := ByteArray new: n.
	n > 0 ifTrue: [self copy: n from: address at: 0 to: b at: 0].
	^b
!
bytesAt: address put: bytes
	bytes isEmpty ifFalse: [self copy: bytes size from: bytes at: 0 to: address at: 0]
!
allocate: size
	"The address of size zeroed bytes that never move; free them with free:."
	<primitive: 'machineAllocate'>
	^self error: 'out of memory'
!
free: address
	<primitive: 'machineFree'>
	^self error: 'bad address'
!
barrier
	"A full memory barrier: a device sees the stores before it before those after it."
	<primitive: 'machineBarrier'>
	^self
! !
