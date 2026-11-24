Object subclass: #ChaCha20
	instanceVariableNames: 'keyNonce counter'
	classVariableNames: ''
	package: 'System-Crypto'!

ChaCha20 comment: 'I am the ChaCha20 stream cipher of RFC 8439 (2.4), computed by the VM (CryptoExports): a 32-byte key, a 12-byte nonce, a 32-bit block counter (0 unless set with counter:). (ChaCha20 key: k nonce: n counter: 1) xor: bytes answers bytes xored with the key stream from that block on, a new ByteArray (encrypting and decrypting are the same); xor:from:to:into:at: writes into a buffer of the caller''s; nextBlock answers the next 64 bytes of key stream. Each call starts at a block: the rest of a block a call did not use is dropped, and the counter is past it. A counter that would wrap signals CryptoError. SecureRandom''s generator.'!

!ChaCha20 class methodsFor: 'instance creation'!
key: key nonce: nonce
	^self key: key nonce: nonce counter: 0
!
key: key nonce: nonce counter: anInteger
	^self new setKey: key nonce: nonce; counter: anInteger; yourself
! !

!ChaCha20 methodsFor: 'initialization'!
setKey: key nonce: nonce
	key size = 32 ifFalse: [^CryptoError signal: 'ChaCha20: the key must be 32 bytes'].
	nonce size = 12 ifFalse: [^CryptoError signal: 'ChaCha20: the nonce must be 12 bytes'].
	keyNonce := key , nonce.
	counter := 0
! !

!ChaCha20 methodsFor: 'accessing'!
counter
	"The block the next call starts at."
	^counter
!
counter: anInteger
	(anInteger between: 0 and: 16rFFFFFFFF) ifFalse: [^CryptoError signal: 'ChaCha20: the counter is 32 bits'].
	counter := anInteger
! !

!ChaCha20 methodsFor: 'encrypting'!
nextBlock
	"The next 64 bytes of key stream."
	^self xor: (ByteArray new: 64)
!
xor: bytes
	^self xor: bytes from: 1 to: bytes size into: (ByteArray new: bytes size) at: 1
!
xor: input from: start to: stop into: output at: outStart
	"Write input from start to stop, xored with the key stream, into output from outStart; answer output."
	| n blocks |
	n := stop - start + 1.
	n <= 0 ifTrue: [^output].
	blocks := n + 63 // 64.
	counter + blocks > 16r100000000 ifTrue: [^CryptoError signal: 'ChaCha20: the block counter would wrap'].
	output replaceFrom: outStart to: outStart + n - 1 with: input startingAt: start.
	CryptoExports chacha20: keyNonce counter: counter xor: output from: outStart count: n.
	counter := counter + blocks.
	^output
! !
