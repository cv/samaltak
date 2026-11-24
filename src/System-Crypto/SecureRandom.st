Object subclass: #SecureRandom
	instanceVariableNames: 'key session output lock source last direct'
	classVariableNames: 'Default'
	package: 'System-Crypto'!

SecureRandom comment: 'I am a cryptographically secure random generator: SecureRandom default nextBytes: n answers n random bytes (keys, nonces, TLS''s client random, the session token). A ChaCha20 DRBG with fast key erasure: each request runs ChaCha20 under the current 32-byte key (zero nonce) and answers its key stream after the first 32 bytes, which become the next key, so a key never serves twice and the state does not reveal what was answered before. The first key is SHA-256 of two blocks of 32 bytes of the platform''s entropy (platformEntropy:), and after each MB answered SHA-256 of the key and a fresh block.

A snapshot holds every generator''s key, so each run of the image reseeds before it answers again: the key belongs to the image''s session (Smalltalk session), which the image renews when it starts, before any startUp: method (those make secrets too: SessionToken for ControlServer and RfbServer), so no order of the startup list can replay a stream.

Entropy: the firmware''s EFI_RNG_PROTOCOL where there is a firmware (UEFI; Firmware, System-Devices), else /dev/urandom (File''s FileStream). Where there is neither, nextBytes: signals CryptoError: never weaker randomness. Each block from the source is checked (entropy): one with fewer than 8 different byte values, or the same as the block before it, is a stuck source, and nextBytes: signals CryptoError until the source answers sound blocks again (a sound source fails either check once in 10^36 blocks). Where the VM has no cryptography (UEFI: CryptoExports isAvailable is false) there is no ChaCha20 or SHA-256 to run: nextBytes: then answers the source''s bytes as they come (EFI_RNG_PROTOCOL''s, which the firmware already conditions or which are the host''s /dev/urandom under QEMU), with the same checks of each block, and one block more drawn for the check of the next request, never answered. Requests are serialized (a Semaphore), so Processes may share one generator. SecureRandom new is a generator of its own; source: lets a test give it an entropy block. docs/crypto.md, Randomness.'!

!SecureRandom class methodsFor: 'accessing'!
default
	"The image's generator."
	Default isNil ifTrue: [Default := self new].
	^Default
! !

!SecureRandom class methodsFor: 'entropy'!
platformEntropy: n
	"n bytes from the platform's entropy source; CryptoError if it has none."
	| bytes |
	bytes := Firmware current isNil
		ifTrue: [self deviceEntropy: n]
		ifFalse: [self firmwareEntropy: n].
	(bytes isNil or: [bytes size ~= n]) ifTrue: [^CryptoError signal: 'SecureRandom: no source of entropy'].
	^bytes
!
firmwareEntropy: n
	"n bytes of EFI_RNG_PROTOCOL's GetRNG with its default algorithm (UEFI 2.10, 37.5), or nil. QEMU's firmware has only RAW, the virtio-rng device's bytes (the host's /dev/urandom); a machine's own may also have a DRBG over the CPU's generator: SHA-256 of two blocks conditions either."
	| firmware rng buffer status |
	firmware := Firmware current.
	rng := firmware locateProtocol: '3152bca5-eade-433d-862e-c01cdc291f44'.
	rng isNil ifTrue: [^nil].
	buffer := Machine allocate: n.
	^[status := Machine call: (firmware function: rng at: 8) with: rng with: 0 with: n with: buffer.
		(firmware isError: status) ifTrue: [nil] ifFalse: [Machine bytesAt: buffer count: n]]
			ensure: [Machine free: buffer]
!
deviceEntropy: n
	"n bytes of /dev/urandom, or nil."
	^[FileStream readOnlyFileNamed: '/dev/urandom' do: [:s | s binary. s next: n]] on: FileError do: [:e | e return: nil]
! !

!SecureRandom methodsFor: 'initialization'!
initialize
	lock := Semaphore forMutualExclusion.
	source := [:n | self class platformEntropy: n]
!
source: aBlock
	"aBlock value: n answers n bytes of entropy (tests); the generator reseeds from it."
	lock critical: [
		source := aBlock.
		key := last := nil]
!
direct: aBoolean
	"Answer the source's bytes as they come (true), as where the VM has no cryptography, or run the generator (false), for this run of the image (tests)."
	lock critical: [
		direct := aBoolean.
		session := Smalltalk session.
		key := last := nil]
! !

!SecureRandom methodsFor: 'accessing'!
nextBytes: n
	"n random bytes."
	| stream |
	n < 0 ifTrue: [^CryptoError signal: 'SecureRandom: a negative count'].
	^lock critical: [
		(direct isNil or: [session ~~ Smalltalk session]) ifTrue: [
			key := last := nil.
			direct := CryptoExports isAvailable not.
			session := Smalltalk session].
		direct ifTrue: [^self directBytes: n].
		key isNil ifTrue: [self seed].
		output >= 16r100000 ifTrue: [self reseed].
		stream := (ChaCha20 key: key nonce: (ByteArray new: 12)) xor: (ByteArray new: n + 32).
		key := stream copyFrom: 1 to: 32.
		output := output + n.
		stream copyFrom: 33 to: stream size]
! !

!SecureRandom methodsFor: 'private'!
seed
	"A new key from two fresh blocks, for this run of the image. The old key is dropped first: if the source fails, no request answers from it."
	| first |
	key := nil.
	first := self entropy.
	key := SHA256 new update: first; update: self entropy; digest.
	output := 0
!
reseed
	key := SHA256 new update: key; update: self entropy; digest.
	output := 0
!
entropy
	"32 bytes from the source, health-checked: a block of fewer than 8 different byte values (a sound source draws one once in 10^37), or the block it answered before, means the source is stuck. Only a fingerprint of the block is kept, so the state does not give the key away."
	| bytes fingerprint |
	bytes := source value: 32.
	(bytes isNil or: [bytes size ~= 32]) ifTrue: [^CryptoError signal: 'SecureRandom: no source of entropy'].
	fingerprint := (SHA256 hash: bytes) copyFrom: 1 to: 16.
	(bytes asSet size < 8 or: [fingerprint = last]) ifTrue: [^CryptoError signal: 'SecureRandom: the entropy source is stuck'].
	last := fingerprint.
	^bytes
!
directBytes: n
	"n bytes of the source's, in blocks of 32 checked as entropy checks them, each against the one before; the block drawn last is kept for the check of the next request and never answered."
	| out block previous |
	out := ByteArray new: n.
	previous := last.
	last := nil.
	1 to: n by: 32 do: [:i |
		block := self checked: (source value: 32) after: previous.
		out replaceFrom: i to: (i + 31 min: n) with: block startingAt: 1.
		previous := block].
	last := self checked: (source value: 32) after: previous.
	^out
!
checked: bytes after: previous
	(bytes isNil or: [bytes size ~= 32]) ifTrue: [^CryptoError signal: 'SecureRandom: no source of entropy'].
	(bytes asSet size < 8 or: [bytes = previous]) ifTrue: [^CryptoError signal: 'SecureRandom: the entropy source is stuck'].
	^bytes
! !
