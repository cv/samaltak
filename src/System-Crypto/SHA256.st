CryptoHash subclass: #SHA256
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

SHA256 comment: 'I am SHA-256 (FIPS 180-4, 6.2): a 32-byte digest of 64-byte blocks. SHA256 hash: bytes; SHA256 new update: bytes; update: more; digest (CryptoHash).'!

!SHA256 class methodsFor: 'accessing'!
algorithm
	^1
!
digestSize
	^32
!
blockSize
	^64
! !
