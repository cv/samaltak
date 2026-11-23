!ByteArray methodsFor: 'network byte order'!
netUint16At: index
	"The big-endian 16-bit integer at index (1-based): uint16BigEndianAt:, one load in optimized code."
	^self uint16BigEndianAt: index
!
netUint16At: index put: anInteger
	self at: index put: ((anInteger bitShift: -8) bitAnd: 255).
	self at: index + 1 put: (anInteger bitAnd: 255).
	^anInteger
!
netUint32At: index
	"The big-endian 32-bit integer at index (1-based)."
	^self uint32BigEndianAt: index
!
netUint32At: index put: anInteger
	self netUint16At: index put: ((anInteger bitShift: -16) bitAnd: 16rFFFF).
	self netUint16At: index + 2 put: (anInteger bitAnd: 16rFFFF).
	^anInteger
!
internetSumFrom: start count: n
	"The ones' complement sum (RFC 1071) of n bytes from start as big-endian 16-bit words (an odd last byte padded), folded to 16 bits. Summed as little-endian 32-bit words, sixteen bytes a step, then swapped: the sum does not depend on the byte order but for that swap."
	| sum i last |
	sum := 0.
	i := start.
	last := start + n - 16.
	[i <= last] whileTrue: [
		sum := sum + (self uint32At: i) + (self uint32At: i + 4) + (self uint32At: i + 8) + (self uint32At: i + 12).
		i := i + 16].
	last := start + n - 4.
	[i <= last] whileTrue: [
		sum := sum + (self uint32At: i).
		i := i + 4].
	last := start + n - 2.
	[i <= last] whileTrue: [
		sum := sum + (self uint16At: i).
		i := i + 2].
	i < (start + n) ifTrue: [sum := sum + (self at: i)].
	[sum > 16rFFFF] whileTrue: [sum := (sum bitAnd: 16rFFFF) + (sum bitShift: -16)].
	^((sum bitAnd: 255) bitShift: 8) + (sum bitShift: -8)
! !
