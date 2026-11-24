Object subclass: #FFIWire
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

FFIWire comment: 'Decode explicit little-endian FFI byte records. Fixed record layouts and exact sizes are specified by each export, not by C struct padding.'!

!FFIWire class methodsFor: 'integers'!
uint32At: offset in: bytes
	self require: 4 at: offset in: bytes.
	^bytes uint32At: offset
!
int32At: offset in: bytes
	| value |
	value := self uint32At: offset in: bytes.
	^value < 16r80000000 ifTrue: [value] ifFalse: [value - 16r100000000]
!
uint64At: offset in: bytes
	self require: 8 at: offset in: bytes.
	^((bytes uint32At: offset + 4) bitShift: 32) + (bytes uint32At: offset)
!
int64At: offset in: bytes
	| value |
	value := self uint64At: offset in: bytes.
	^value < 16r8000000000000000 ifTrue: [value] ifFalse: [value - 16r10000000000000000]
!
require: width at: offset in: bytes
	(bytes class == ByteArray and: [offset class == SmallInteger
		and: [offset between: 1 and: bytes size - width + 1]])
		ifFalse: [FFIError signal: 'Truncated or invalid FFI record']
! !

!FFIWire class methodsFor: 'arrays'!
uint32VectorFrom: bytes maxCount: limit
	| count result |
	(bytes class == ByteArray and: [bytes size \\ 4 = 0])
		ifFalse: [^FFIError signal: 'Invalid FFI uint32 vector'].
	count := bytes size // 4.
	count > limit ifTrue: [^FFIError signal: 'FFI uint32 vector exceeds its count bound'].
	result := Array new: count.
	1 to: count do: [:i | result at: i put: (bytes uint32At: i * 4 - 3)].
	^result
! !
