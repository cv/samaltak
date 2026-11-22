Object subclass: #CryptoHash
	instanceVariableNames: 'buffer bufferCount length'
	classVariableNames: ''
	package: 'System-Crypto'!

CryptoHash comment: 'I am the abstract Merkle-Damgård hash function of FIPS 180-4 (SHA256, SHA384, SHA512): the bytes given so far, a block at a time. Class side: hash: bytes (the digest, a ByteArray), digestSize and blockSize in bytes. Instance side: new, update: (a ByteArray, or a String as UTF-8; also update:from:to:), digest. digest finishes a copy, so the receiver goes on: more update:s, then digest again (the running hash of a TLS transcript); copy forks the state. A subclass holds its chaining state, processes a block of bytes at a 0-based offset (processBlock:at:; processBlocks:at:count: does several, in Smalltalk one at a time), answers its digest bytes (digestBytes) and says how many bytes the message length takes in the padding (lengthSize).'!

!CryptoHash class methodsFor: 'hashing'!
hash: bytes
	"The digest of bytes."
	^self new update: bytes; digest
! !

!CryptoHash class methodsFor: 'accessing'!
digestSize
	"In bytes."
	^self subclassResponsibility
!
blockSize
	"In bytes."
	^self subclassResponsibility
!
lengthSize
	"The bytes of the big-endian message length (in bits) that end the padding."
	^self subclassResponsibility
! !

!CryptoHash methodsFor: 'initialization'!
initialize
	buffer := ByteArray new: self class blockSize.
	bufferCount := 0.
	length := 0.
	self resetState
!
resetState
	"Set the chaining state to the initial hash value."
	^self subclassResponsibility
!
reset
	"Start over, as new."
	bufferCount := 0.
	length := 0.
	self resetState
!
postCopy
	buffer := buffer copy
! !

!CryptoHash methodsFor: 'hashing'!
update: bytes
	"Hash bytes next (a String as UTF-8)."
	| b |
	b := bytes isString ifTrue: [bytes utf8Encoded] ifFalse: [bytes].
	^self update: b from: 1 to: b size
!
update: bytes from: start to: stop
	"Hash bytes start to stop next."
	| i n blockSize |
	blockSize := buffer size.
	length := length + (stop - start + 1).
	i := start.
	bufferCount > 0 ifTrue: [
		n := blockSize - bufferCount min: stop - i + 1.
		buffer replaceFrom: bufferCount + 1 to: bufferCount + n with: bytes startingAt: i.
		bufferCount := bufferCount + n.
		i := i + n.
		bufferCount = blockSize ifTrue: [
			self processBlocks: buffer at: 0 count: 1.
			bufferCount := 0]].
	n := stop - i + 1 // blockSize.
	n > 0 ifTrue: [
		self processBlocks: bytes at: i - 1 count: n.
		i := i + (n * blockSize)].
	i <= stop ifTrue: [
		buffer replaceFrom: 1 to: stop - i + 1 with: bytes startingAt: i.
		bufferCount := stop - i + 1]
!
digest
	"The digest of the bytes given so far; the receiver is unchanged."
	^self copy finish
!
finish
	"Pad (a 1 bit, zeros, the length in bits), then answer the digest."
	| n lengthSize pad bits |
	n := buffer size.
	lengthSize := self class lengthSize.
	pad := ByteArray new: n - ((length + lengthSize + 1) \\ n) \\ n + 1 + lengthSize.
	pad at: 1 put: 16r80.
	bits := length * 8.
	pad size to: pad size - lengthSize + 1 by: -1 do: [:i |
		pad at: i put: (bits bitAnd: 255).
		bits := bits bitShift: -8].
	self update: pad.
	^self digestBytes
!
processBlock: bytes at: offset
	"Hash the block of bytes offset + 1 to offset + blockSize."
	^self subclassResponsibility
!
processBlocks: bytes at: offset count: n
	"Hash the n blocks of bytes from offset + 1 on (a subclass may hash them all at once: NativeCrypto)."
	| blockSize |
	blockSize := buffer size.
	0 to: n - 1 do: [:k | self processBlock: bytes at: offset + (k * blockSize)]
!
digestBytes
	^self subclassResponsibility
! !
