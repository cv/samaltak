Object subclass: #TLSReader
	instanceVariableNames: 'bytes position limit'
	classVariableNames: ''
	package: 'System-TLS'!

TLSReader comment: 'I read TLS''s presentation language (RFC 8446, section 3) from a ByteArray: big-endian integers of 1 to 4 bytes (u8, u16, u24, u32), bytes (next:), and vectors with a length prefix of 1, 2 or 3 bytes, as their bytes (vector8, vector16, vector24) or as a reader of just them (reader8, reader16, reader24); extensions reads an extension list into a Dictionary. Reading past my end signals a TLSError with the decode_error alert, as does expectEnd when bytes are left.

	r := TLSReader on: body.
	version := r u16. random := r next: 32. sessionId := r vector8. ... r expectEnd'!

!TLSReader methodsFor: 'initialization'!
setBytes: aByteArray from: start to: stop
	bytes := aByteArray.
	position := start.
	limit := stop
! !

!TLSReader methodsFor: 'reading'!
u8
	self need: 1.
	position := position + 1.
	^bytes at: position - 1
!
u16
	| n |
	self need: 2.
	n := ((bytes at: position) bitShift: 8) + (bytes at: position + 1).
	position := position + 2.
	^n
!
u24
	| high |
	high := self u8.
	^(high bitShift: 16) + self u16
!
u32
	| high |
	high := self u16.
	^(high bitShift: 16) + self u16
!
next: count
	| result |
	self need: count.
	result := bytes copyFrom: position to: position + count - 1.
	position := position + count.
	^result
!
vector8
	^self next: self u8
!
vector16
	^self next: self u16
!
vector24
	^self next: self u24
!
reader8
	^self reader: self u8
!
reader16
	^self reader: self u16
!
reader24
	^self reader: self u24
!
reader: count
	"A reader of my next count bytes, which I skip."
	| reader |
	self need: count.
	reader := TLSReader on: bytes from: position to: position + count - 1.
	position := position + count.
	^reader
!
upToEnd
	^self next: limit - position + 1
!
extensions
	"Read Extension extensions<0..2^16-1>: a Dictionary from each extension's type to its data. A type twice is illegal_parameter."
	| list result type |
	list := self reader16.
	result := Dictionary new.
	[list atEnd] whileFalse: [
		type := list u16.
		(result includesKey: type) ifTrue: [^TLSError signal: 'the extension ', type printString, ' occurs twice' alert: #illegalParameter].
		result at: type put: list vector16].
	^result
! !

!TLSReader methodsFor: 'testing'!
atEnd
	^position > limit
!
remaining
	^limit - position + 1
!
expectEnd
	self atEnd ifFalse: [^TLSError signal: 'decode error: ', self remaining printString, ' bytes too many' alert: #decodeError]
! !

!TLSReader methodsFor: 'private'!
need: count
	limit - position + 1 < count ifTrue: [^TLSError signal: 'decode error: message truncated' alert: #decodeError]
! !

!TLSReader class methodsFor: 'instance creation'!
on: aByteArray
	^self on: aByteArray from: 1 to: aByteArray size
!
on: aByteArray from: start to: stop
	^self new setBytes: aByteArray from: start to: stop
! !
