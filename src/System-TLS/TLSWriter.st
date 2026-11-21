Object subclass: #TLSWriter
	instanceVariableNames: 'stream'
	classVariableNames: ''
	package: 'System-TLS'!

TLSWriter comment: 'I write TLS''s presentation language (RFC 8446, section 3) into a ByteArray (contents): big-endian integers (u8:, u16:, u24:), bytes (bytes:), and vectors with a length prefix of 1, 2 or 3 bytes, of a ByteArray (vector8:, vector16:, vector24:) or of what a block writes on a writer it is given (vector8Do:, vector16Do:, vector24Do:).

	TLSWriter new u16: 16r0303; vector16Do: [:w | w u16: 16r1301; u16: 16r1303]; contents'!

!TLSWriter methodsFor: 'initialization'!
initialize
	stream := WriteStream on: (ByteArray new: 64)
! !

!TLSWriter methodsFor: 'writing'!
u8: anInteger
	stream nextPut: anInteger
!
u16: anInteger
	stream nextPut: ((anInteger bitShift: -8) bitAnd: 255); nextPut: (anInteger bitAnd: 255)
!
u24: anInteger
	stream nextPut: ((anInteger bitShift: -16) bitAnd: 255).
	self u16: (anInteger bitAnd: 16rFFFF)
!
bytes: aByteArray
	stream nextPutAll: aByteArray asByteArray
!
vector8: aByteArray
	aByteArray size > 255 ifTrue: [^TLSError signal: 'vector too long' alert: #internalError].
	self u8: aByteArray size; bytes: aByteArray
!
vector16: aByteArray
	aByteArray size > 16rFFFF ifTrue: [^TLSError signal: 'vector too long' alert: #internalError].
	self u16: aByteArray size; bytes: aByteArray
!
vector24: aByteArray
	self u24: aByteArray size; bytes: aByteArray
!
vector8Do: aBlock
	self vector8: (self class contentsOf: aBlock)
!
vector16Do: aBlock
	self vector16: (self class contentsOf: aBlock)
!
vector24Do: aBlock
	self vector24: (self class contentsOf: aBlock)
! !

!TLSWriter methodsFor: 'accessing'!
contents
	^stream contents
! !

!TLSWriter class methodsFor: 'instance creation'!
contentsOf: aBlock
	"What aBlock writes on a new writer."
	| writer |
	writer := self new.
	aBlock value: writer.
	^writer contents
! !
