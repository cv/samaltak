Object subclass: #CryptoHash
	instanceVariableNames: 'state session'
	classVariableNames: ''
	package: 'System-Crypto'!

CryptoHash comment: 'I am the abstract hash function of FIPS 180-4 (SHA256, SHA384, SHA512), computed by the VM (CryptoExports: libcrypto hosted, mbedTLS on UEFI). Class side: hash: bytes (the digest, a ByteArray), digestSize and blockSize in bytes. Instance side: new, update: (a ByteArray, or a String as UTF-8; also update:from:to:), digest. digest finishes a copy, so the receiver goes on: more update:s, then digest again (the running hash of a transcript); copy forks the state, which is the VM''s, in a ByteArray of mine: a hash cannot go on in another session of the image (CryptoError). A subclass says its algorithm (CryptoExports'' number), digestSize and blockSize.'!

!CryptoHash class methodsFor: 'hashing'!
hash: bytes
	"The digest of bytes (a String as UTF-8)."
	| b |
	b := bytes isString ifTrue: [bytes utf8Encoded] ifFalse: [bytes].
	^CryptoExports digest: self algorithm size: self digestSize of: b from: 1 to: b size
! !

!CryptoHash class methodsFor: 'accessing'!
algorithm
	"The number CryptoExports knows me by."
	^self subclassResponsibility
!
digestSize
	"In bytes."
	^self subclassResponsibility
!
blockSize
	"In bytes."
	^self subclassResponsibility
! !

!CryptoHash methodsFor: 'initialization'!
initialize
	state := ByteArray new: CryptoExports stateSize.
	self reset
!
reset
	"Start over, as new."
	CryptoExports digestInit: self class algorithm state: state.
	session := Smalltalk session
!
postCopy
	state := state copy
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
	self checkSession.
	CryptoExports digestUpdate: self class algorithm state: state bytes: bytes from: start to: stop
!
digest
	"The digest of the bytes given so far; the receiver is unchanged."
	self checkSession.
	^CryptoExports digestFinal: self class algorithm size: self class digestSize state: state
! !

!CryptoHash methodsFor: 'private'!
checkSession
	session == Smalltalk session ifFalse: [^CryptoError signal: 'a hash cannot go on in another session of the image']
! !
