Object subclass: #ChaCha20
	instanceVariableNames: 'state block'
	classVariableNames: ''
	package: 'System-Crypto'!

ChaCha20 comment: 'I am the ChaCha20 stream cipher of RFC 8439 (2.4): a 32-byte key, a 12-byte nonce, a 32-bit block counter (0 unless set with counter:). (ChaCha20 key: k nonce: n counter: 1) xor: bytes answers bytes xored with the key stream from that block on, a new ByteArray (encrypting and decrypting are the same); xor:from:to:into:at: writes into a buffer of the caller''s; nextBlock answers the next 64 bytes of key stream. Each call starts at a block: the rest of a block a call did not use is dropped, and the counter is past it. A counter that would wrap signals CryptoError. The state, 16 words, and the block function''s working words are SmallIntegers, the working words in temps: a rotation is a shift left masked to 32 bits ored with a shift right.'!

!ChaCha20 class methodsFor: 'instance creation'!
key: key nonce: nonce
	^self new setKey: key nonce: nonce
!
key: key nonce: nonce counter: anInteger
	^(self key: key nonce: nonce) counter: anInteger; yourself
! !

!ChaCha20 methodsFor: 'initialization'!
setKey: key nonce: nonce
	key size = 32 ifFalse: [^CryptoError signal: 'ChaCha20: the key must be 32 bytes'].
	nonce size = 12 ifFalse: [^CryptoError signal: 'ChaCha20: the nonce must be 12 bytes'].
	state := Array new: 16.
	state at: 1 put: 16r61707865; at: 2 put: 16r3320646E; at: 3 put: 16r79622D32; at: 4 put: 16r6B206574.
	1 to: 8 do: [:i | state at: 4 + i put: (key uint32At: i * 4 - 3)].
	state at: 13 put: 0.
	1 to: 3 do: [:i | state at: 13 + i put: (nonce uint32At: i * 4 - 3)].
	block := Array new: 16
! !

!ChaCha20 methodsFor: 'accessing'!
counter
	"The block the next call starts at."
	^state at: 13
!
counter: anInteger
	(anInteger between: 0 and: 16rFFFFFFFF) ifFalse: [^CryptoError signal: 'ChaCha20: the counter must be a 32-bit word'].
	state at: 13 put: anInteger
! !

!ChaCha20 methodsFor: 'encrypting'!
nextBlock
	"The next 64 bytes of key stream."
	| bytes |
	self keyBlock.
	bytes := ByteArray new: 64.
	1 to: 16 do: [:i | bytes uint32At: i * 4 - 3 put: (block at: i)].
	^bytes
!
xor: bytes
	^self xor: bytes from: 1 to: bytes size into: (ByteArray new: bytes size) at: 1
!
xor: input from: start to: stop into: output at: outStart
	"Xor input from start to stop with the key stream, into output from outStart on; answer output."
	| b i o w |
	b := block.
	i := start.
	o := outStart.
	[stop - i >= 63] whileTrue: [
		self keyBlock.
		1 to: 16 do: [:j |
			output uint32At: o put: ((input uint32At: i) bitXor: (b at: j)).
			i := i + 4.
			o := o + 4]].
	i <= stop ifTrue: [
		self keyBlock.
		0 to: stop - i do: [:k |
			w := b at: k // 4 + 1.
			output at: o + k put: ((input at: i + k) bitXor: ((w bitShift: k \\ 4 * -8) bitAnd: 255))]].
	^output
! !

!ChaCha20 methodsFor: 'private'!
keyBlock
	"The block function (RFC 8439, 2.3) at the counter, into block; then the next counter."
	| s b x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 |
	s := state.
	b := block.
	(s at: 13) > 16rFFFFFFFF ifTrue: [^CryptoError signal: 'ChaCha20: the block counter wrapped'].
	x0 := s at: 1. x1 := s at: 2. x2 := s at: 3. x3 := s at: 4. x4 := s at: 5. x5 := s at: 6. x6 := s at: 7. x7 := s at: 8. x8 := s at: 9. x9 := s at: 10. x10 := s at: 11. x11 := s at: 12. x12 := s at: 13. x13 := s at: 14. x14 := s at: 15. x15 := s at: 16.
	1 to: 10 do: [:round |
		x0 := x0 + x4 bitAnd: 16rFFFFFFFF.
		x12 := x12 bitXor: x0.
		x12 := ((x12 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x12 bitShift: -16).
		x8 := x8 + x12 bitAnd: 16rFFFFFFFF.
		x4 := x4 bitXor: x8.
		x4 := ((x4 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x4 bitShift: -20).
		x0 := x0 + x4 bitAnd: 16rFFFFFFFF.
		x12 := x12 bitXor: x0.
		x12 := ((x12 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x12 bitShift: -24).
		x8 := x8 + x12 bitAnd: 16rFFFFFFFF.
		x4 := x4 bitXor: x8.
		x4 := ((x4 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x4 bitShift: -25).
		x1 := x1 + x5 bitAnd: 16rFFFFFFFF.
		x13 := x13 bitXor: x1.
		x13 := ((x13 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x13 bitShift: -16).
		x9 := x9 + x13 bitAnd: 16rFFFFFFFF.
		x5 := x5 bitXor: x9.
		x5 := ((x5 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x5 bitShift: -20).
		x1 := x1 + x5 bitAnd: 16rFFFFFFFF.
		x13 := x13 bitXor: x1.
		x13 := ((x13 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x13 bitShift: -24).
		x9 := x9 + x13 bitAnd: 16rFFFFFFFF.
		x5 := x5 bitXor: x9.
		x5 := ((x5 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x5 bitShift: -25).
		x2 := x2 + x6 bitAnd: 16rFFFFFFFF.
		x14 := x14 bitXor: x2.
		x14 := ((x14 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x14 bitShift: -16).
		x10 := x10 + x14 bitAnd: 16rFFFFFFFF.
		x6 := x6 bitXor: x10.
		x6 := ((x6 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x6 bitShift: -20).
		x2 := x2 + x6 bitAnd: 16rFFFFFFFF.
		x14 := x14 bitXor: x2.
		x14 := ((x14 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x14 bitShift: -24).
		x10 := x10 + x14 bitAnd: 16rFFFFFFFF.
		x6 := x6 bitXor: x10.
		x6 := ((x6 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x6 bitShift: -25).
		x3 := x3 + x7 bitAnd: 16rFFFFFFFF.
		x15 := x15 bitXor: x3.
		x15 := ((x15 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x15 bitShift: -16).
		x11 := x11 + x15 bitAnd: 16rFFFFFFFF.
		x7 := x7 bitXor: x11.
		x7 := ((x7 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x7 bitShift: -20).
		x3 := x3 + x7 bitAnd: 16rFFFFFFFF.
		x15 := x15 bitXor: x3.
		x15 := ((x15 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x15 bitShift: -24).
		x11 := x11 + x15 bitAnd: 16rFFFFFFFF.
		x7 := x7 bitXor: x11.
		x7 := ((x7 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x7 bitShift: -25).
		x0 := x0 + x5 bitAnd: 16rFFFFFFFF.
		x15 := x15 bitXor: x0.
		x15 := ((x15 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x15 bitShift: -16).
		x10 := x10 + x15 bitAnd: 16rFFFFFFFF.
		x5 := x5 bitXor: x10.
		x5 := ((x5 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x5 bitShift: -20).
		x0 := x0 + x5 bitAnd: 16rFFFFFFFF.
		x15 := x15 bitXor: x0.
		x15 := ((x15 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x15 bitShift: -24).
		x10 := x10 + x15 bitAnd: 16rFFFFFFFF.
		x5 := x5 bitXor: x10.
		x5 := ((x5 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x5 bitShift: -25).
		x1 := x1 + x6 bitAnd: 16rFFFFFFFF.
		x12 := x12 bitXor: x1.
		x12 := ((x12 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x12 bitShift: -16).
		x11 := x11 + x12 bitAnd: 16rFFFFFFFF.
		x6 := x6 bitXor: x11.
		x6 := ((x6 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x6 bitShift: -20).
		x1 := x1 + x6 bitAnd: 16rFFFFFFFF.
		x12 := x12 bitXor: x1.
		x12 := ((x12 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x12 bitShift: -24).
		x11 := x11 + x12 bitAnd: 16rFFFFFFFF.
		x6 := x6 bitXor: x11.
		x6 := ((x6 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x6 bitShift: -25).
		x2 := x2 + x7 bitAnd: 16rFFFFFFFF.
		x13 := x13 bitXor: x2.
		x13 := ((x13 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x13 bitShift: -16).
		x8 := x8 + x13 bitAnd: 16rFFFFFFFF.
		x7 := x7 bitXor: x8.
		x7 := ((x7 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x7 bitShift: -20).
		x2 := x2 + x7 bitAnd: 16rFFFFFFFF.
		x13 := x13 bitXor: x2.
		x13 := ((x13 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x13 bitShift: -24).
		x8 := x8 + x13 bitAnd: 16rFFFFFFFF.
		x7 := x7 bitXor: x8.
		x7 := ((x7 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x7 bitShift: -25).
		x3 := x3 + x4 bitAnd: 16rFFFFFFFF.
		x14 := x14 bitXor: x3.
		x14 := ((x14 bitShift: 16) bitAnd: 16rFFFFFFFF) bitOr: (x14 bitShift: -16).
		x9 := x9 + x14 bitAnd: 16rFFFFFFFF.
		x4 := x4 bitXor: x9.
		x4 := ((x4 bitShift: 12) bitAnd: 16rFFFFFFFF) bitOr: (x4 bitShift: -20).
		x3 := x3 + x4 bitAnd: 16rFFFFFFFF.
		x14 := x14 bitXor: x3.
		x14 := ((x14 bitShift: 8) bitAnd: 16rFFFFFFFF) bitOr: (x14 bitShift: -24).
		x9 := x9 + x14 bitAnd: 16rFFFFFFFF.
		x4 := x4 bitXor: x9.
		x4 := ((x4 bitShift: 7) bitAnd: 16rFFFFFFFF) bitOr: (x4 bitShift: -25)].
	b at: 1 put: (x0 + (s at: 1) bitAnd: 16rFFFFFFFF).
	b at: 2 put: (x1 + (s at: 2) bitAnd: 16rFFFFFFFF).
	b at: 3 put: (x2 + (s at: 3) bitAnd: 16rFFFFFFFF).
	b at: 4 put: (x3 + (s at: 4) bitAnd: 16rFFFFFFFF).
	b at: 5 put: (x4 + (s at: 5) bitAnd: 16rFFFFFFFF).
	b at: 6 put: (x5 + (s at: 6) bitAnd: 16rFFFFFFFF).
	b at: 7 put: (x6 + (s at: 7) bitAnd: 16rFFFFFFFF).
	b at: 8 put: (x7 + (s at: 8) bitAnd: 16rFFFFFFFF).
	b at: 9 put: (x8 + (s at: 9) bitAnd: 16rFFFFFFFF).
	b at: 10 put: (x9 + (s at: 10) bitAnd: 16rFFFFFFFF).
	b at: 11 put: (x10 + (s at: 11) bitAnd: 16rFFFFFFFF).
	b at: 12 put: (x11 + (s at: 12) bitAnd: 16rFFFFFFFF).
	b at: 13 put: (x12 + (s at: 13) bitAnd: 16rFFFFFFFF).
	b at: 14 put: (x13 + (s at: 14) bitAnd: 16rFFFFFFFF).
	b at: 15 put: (x14 + (s at: 15) bitAnd: 16rFFFFFFFF).
	b at: 16 put: (x15 + (s at: 16) bitAnd: 16rFFFFFFFF).
	s at: 13 put: (s at: 13) + 1
! !
