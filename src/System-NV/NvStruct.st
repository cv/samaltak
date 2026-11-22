Object subclass: #NvStruct
	instanceVariableNames: 'bytes'
	classVariableNames: ''
	package: 'System-NV'!

NvStruct comment: 'I am a C struct as bytes, for the parameter blocks of the NVIDIA driver''s ioctls and of its resource manager (RM) calls (NvRm builds them). Offsets are 0-based byte offsets as in the C headers (docs/nv-rm.md lists the layouts); integers are little-endian and unsigned.

	(NvStruct new: 16) u32At: 4 put: 7; u64At: 8 put: 16r123456789; bytes

copyToMachine answers a copy in memory outside the heap (Machine allocate:) to pass to an ioctl, readFrom: reads it back, NvStruct fromMachine:size: reads one.'!

!NvStruct methodsFor: 'initialization'!
setBytes: aByteArray
	bytes := aByteArray
! !

!NvStruct methodsFor: 'accessing'!
bytes
	^bytes
!
size
	^bytes size
!
u8At: offset
	^bytes at: offset + 1
!
u8At: offset put: anInteger
	^bytes at: offset + 1 put: anInteger
!
u16At: offset
	^bytes uint16At: offset + 1
!
u16At: offset put: anInteger
	^bytes uint16At: offset + 1 put: anInteger
!
u32At: offset
	^bytes uint32At: offset + 1
!
u32At: offset put: anInteger
	"anInteger may be negative (-1 is 16rFFFFFFFF)."
	^bytes uint32At: offset + 1 put: (anInteger bitAnd: 16rFFFFFFFF)
!
s32At: offset
	| v |
	v := self u32At: offset.
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
!
u64At: offset
	^(self u32At: offset) + ((self u32At: offset + 4) bitShift: 32)
!
u64At: offset put: anInteger
	self u32At: offset put: (anInteger bitAnd: 16rFFFFFFFF).
	self u32At: offset + 4 put: ((anInteger bitShift: -32) bitAnd: 16rFFFFFFFF).
	^anInteger
!
stringAt: offset size: n
	"The NUL-terminated C string in the n bytes at offset."
	| end |
	end := offset + 1.
	[end <= (offset + n) and: [(bytes at: end) ~= 0]] whileTrue: [end := end + 1].
	^(bytes copyFrom: offset + 1 to: end - 1) asString
!
bytesAt: offset put: aByteArray
	bytes replaceFrom: offset + 1 to: offset + aByteArray size with: aByteArray startingAt: 1
! !

!NvStruct methodsFor: 'machine memory'!
copyToMachine
	"The address of a copy of me outside the heap; free it with Machine free:."
	| address |
	address := Machine allocate: (bytes size max: 8).
	Machine bytesAt: address put: bytes.
	^address
!
readFrom: address
	"Replace my bytes with those at address (after an ioctl wrote them)."
	bytes isEmpty ifFalse: [Machine copy: bytes size from: address at: 0 to: bytes at: 0]
! !

!NvStruct class methodsFor: 'instance creation'!
new: size
	^self new setBytes: (ByteArray new: size)
!
on: aByteArray
	^self new setBytes: aByteArray
!
fromMachine: address size: n
	^self on: (Machine bytesAt: address count: n)
! !
