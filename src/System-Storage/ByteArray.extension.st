!ByteArray methodsFor: '*System-Storage'!
uint64At: byteOffset
	"The little-endian unsigned 64-bit integer at the 1-based byteOffset (GPT headers, EFI variables)."
	^(self uint32At: byteOffset) + ((self uint32At: byteOffset + 4) bitShift: 32)
!
uint64At: byteOffset put: anInteger
	self uint32At: byteOffset put: (anInteger bitAnd: 16rFFFFFFFF).
	self uint32At: byteOffset + 4 put: ((anInteger bitShift: -32) bitAnd: 16rFFFFFFFF).
	^anInteger
! !
